#include "pch.h"
#include "Doc/DocGenerator.h"
#include "Doc/DocInternal.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace DocInternal
{
    std::mutex               g_RuntimeDocMutex;
    std::unordered_set<Utf8> g_GeneratedRuntimeDocs;
    std::mutex               g_StylesheetMutex;

    Utf8 fromRuntimeString(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};
        return Utf8(value.ptr, static_cast<size_t>(value.length));
    }

    PageOptions getPageOptions(const CompilerInstance& compiler)
    {
        const Runtime::BuildCfgGenDoc& genDoc = compiler.buildCfg().genDoc;

        PageOptions result;
        result.kind                = genDoc.kind;
        result.outputName          = fromRuntimeString(genDoc.outputName);
        result.titleToc            = fromRuntimeString(genDoc.titleToc);
        result.titleContent        = fromRuntimeString(genDoc.titleContent);
        result.css                 = fromRuntimeString(genDoc.css);
        result.icon                = fromRuntimeString(genDoc.icon);
        result.morePages           = fromRuntimeString(genDoc.morePages);
        result.quoteIconNote       = fromRuntimeString(genDoc.quoteIconNote);
        result.quoteIconTip        = fromRuntimeString(genDoc.quoteIconTip);
        result.quoteIconWarning    = fromRuntimeString(genDoc.quoteIconWarning);
        result.quoteIconAttention  = fromRuntimeString(genDoc.quoteIconAttention);
        result.quoteIconExample    = fromRuntimeString(genDoc.quoteIconExample);
        result.quoteTitleNote      = fromRuntimeString(genDoc.quoteTitleNote);
        result.quoteTitleTip       = fromRuntimeString(genDoc.quoteTitleTip);
        result.quoteTitleWarning   = fromRuntimeString(genDoc.quoteTitleWarning);
        result.quoteTitleAttention = fromRuntimeString(genDoc.quoteTitleAttention);
        result.quoteTitleExample   = fromRuntimeString(genDoc.quoteTitleExample);
        result.syntaxDefaultColor  = genDoc.syntaxDefaultColor;
        result.hasSwagWatermark    = genDoc.hasSwagWatermark;

        if (!compiler.cmdLine().docCss.empty())
            result.css = compiler.cmdLine().docCss;
        return result;
    }

    PageOptions getRuntimePageOptions(const CompilerInstance& compiler)
    {
        PageOptions result     = getPageOptions(compiler);
        result.kind            = Runtime::BuildCfgDocKind::Api;
        result.outputName      = "swag.runtime";
        result.titleContent    = "Swag Runtime";
        if (result.css.empty())
            result.css = "style.css";
        return result;
    }

    Result reportDocDirectoryError(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_doc_dir_create_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    Result reportDocFileError(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_doc_file_write_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    Result ensureOutputDirectory(TaskContext& ctx, const fs::path& path)
    {
        std::error_code ec;
        fs::create_directories(path, ec);
        if (ec)
            return reportDocDirectoryError(ctx, path, FileSystem::normalizeSystemMessage(ec));
        return Result::Continue;
    }

    Result writeDocumentationFile(TaskContext& ctx, const fs::path& path, const std::string_view content)
    {
        if (!ctx.cmdLine().outputDoc)
            return Result::Continue;

        FileSystem::IoErrorInfo error;
        if (FileSystem::writeBinaryFile(path, content.data(), content.size(), error) != Result::Continue)
            return reportDocFileError(ctx, path, FileSystem::describeIoFailure(error));
        return Result::Continue;
    }

    Result writeDocumentationStyles(TaskContext& ctx, const PageOptions& options)
    {
        if (!ctx.cmdLine().outputDoc)
            return Result::Continue;

        const fs::path outputDir = DocGenerator::outputDirectory(ctx.compiler()).lexically_normal();
        const fs::path cssPath(options.css.c_str());
        if (cssPath.is_absolute() || options.css.contains("://"))
            return reportDocFileError(ctx, cssPath, "the stylesheet path must be relative to the documentation output directory");

        const fs::path path     = (outputDir / cssPath).lexically_normal();
        const fs::path relative = path.lexically_relative(outputDir);
        if (relative.empty() || (relative.begin() != relative.end() && *relative.begin() == ".."))
            return reportDocFileError(ctx, cssPath, "the stylesheet path must stay inside the documentation output directory");

        const std::scoped_lock lock(g_StylesheetMutex);
        SWC_RESULT(ensureOutputDirectory(ctx, path.parent_path()));
        return writeDocumentationFile(ctx, path, documentationStyles());
    }

    Utf8 defaultOutputBaseName(const CompilerInstance& compiler, const PageOptions& options)
    {
        if (!options.outputName.empty())
            return options.outputName;

        if (!compiler.cmdLine().workspacePath.empty() && !compiler.cmdLine().modulePath.empty())
        {
            Utf8 result = compiler.cmdLine().workspacePath.filename();
            result += ".";
            result.append(compiler.cmdLine().modulePath.filename().string());
            return result;
        }

        return defaultArtifactName(compiler.cmdLine());
    }

    fs::path outputFilePath(const CompilerInstance& compiler, const PageOptions& options)
    {
        Utf8 baseName = defaultOutputBaseName(compiler, options);
        baseName.make_lower();
        baseName += ".html";
        fs::path result = DocGenerator::outputDirectory(compiler) / fs::path(baseName.c_str());
        return result.lexically_normal();
    }

    Utf8 correctTitle(Utf8 title)
    {
        std::ranges::replace(title, '_', ' ');
        const std::unordered_set<std::string_view> exceptions = {"and", "or", "in", "the", "of", "a", "an", "but", "for", "nor", "on", "at", "by", "with", "to"};

        std::vector<Utf8>  words;
        std::istringstream stream(title);
        std::string        word;
        while (stream >> word)
            words.emplace_back(word);

        Utf8 result;
        for (size_t i = 0; i < words.size(); ++i)
        {
            Utf8 value = words[i];
            value.make_lower();
            if (i == 0 || i + 1 == words.size() || !exceptions.contains(value.view()))
                value.front() = static_cast<char>(std::toupper(static_cast<unsigned char>(value.front())));
            if (!result.empty())
                result += " ";
            result += value;
        }
        return result;
    }

    Result readDocumentationSource(TaskContext& ctx, const fs::path& path, std::string& outText)
    {
        FileSystem::IoErrorInfo error;
        if (FileSystem::readTextFile(path, outText, error) != Result::Continue)
            return reportDocFileError(ctx, path, FileSystem::describeIoFailure(error));
        return Result::Continue;
    }

    Utf8 renderExampleSource(TaskContext& ctx, const RenderContext& renderCtx, const std::string_view source)
    {
        const std::vector<Utf8> lines = splitLines(source);
        Utf8                    result;
        size_t                  index = 0;
        while (index < lines.size())
        {
            Utf8 code;
            while (index < lines.size() && !trimView(lines[index]).starts_with("/**"))
            {
                code += lines[index++];
                code += "\n";
            }
            result += renderCodeBlock(ctx, code, true, &renderCtx);
            if (index == lines.size())
                break;

            index++;
            std::vector<Utf8> comment;
            while (index < lines.size() && !trimView(lines[index]).starts_with("*/"))
                comment.push_back(lines[index++]);
            if (index < lines.size())
                index++;
            result += renderMarkdownLines(renderCtx, comment, 2);
        }
        return result;
    }

    std::vector<const SourceFile*> moduleSourceFiles(const CompilerInstance& compiler)
    {
        std::vector<const SourceFile*> result;
        for (const SourceFile* file : compiler.files())
        {
            if (file && file->hasFlag(FileFlagsE::ModuleSrc))
                result.push_back(file);
        }
        std::ranges::sort(result, [](const SourceFile* lhs, const SourceFile* rhs) { return lhs->path().filename().string() < rhs->path().filename().string(); });
        return result;
    }

    Result generateExamples(TaskContext& ctx, PageOptions options, fs::path& outPath)
    {
        if (options.titleContent.empty())
            options.titleContent = "Swag Examples";
        if (options.titleToc.empty())
            options.titleToc = "Table of Contents";

        const RenderContext renderCtx = {
            .ctx        = &ctx,
            .options    = &options,
            .references = nullptr,
        };

        Utf8 toc     = std::format("<h2>{}</h2>\n<ul>\n", escapeHtml(options.titleToc));
        Utf8 content = std::format("<h1>{}</h1>\n", escapeHtml(options.titleContent));

        uint32_t currentLevel = 1;
        for (const SourceFile* file : moduleSourceFiles(ctx.compiler()))
        {
            Utf8 stem = file->path().stem().string();
            if (stem.size() < 9 ||
                !std::isdigit(static_cast<unsigned char>(stem[0])) ||
                !std::isdigit(static_cast<unsigned char>(stem[1])) ||
                !std::isdigit(static_cast<unsigned char>(stem[2])) ||
                stem[3] != '_' ||
                !std::isdigit(static_cast<unsigned char>(stem[4])) ||
                !std::isdigit(static_cast<unsigned char>(stem[5])) ||
                !std::isdigit(static_cast<unsigned char>(stem[6])) ||
                stem[7] != '_')
                continue;

            const uint32_t level = stem.substr(4, 3) == "000" ? 1 : 2;
            while (currentLevel < level)
            {
                toc += "<ul>\n";
                currentLevel++;
            }
            while (currentLevel > level)
            {
                toc += "</ul>\n";
                currentLevel--;
            }

            const Utf8 title  = correctTitle(stem.substr(8));
            const Utf8 anchor = makeAnchor(file->name());
            toc.append(std::format("<li><a href=\"#{}\">{}</a></li>\n", anchor, escapeHtml(title)));
            content.append(std::format("<h{} id=\"{}\">{}</h{}>\n", level + 1, anchor, escapeHtml(title), level + 1));

            if (file->path().extension() == ".md")
                content += renderMarkdownLines(renderCtx, splitLines(file->sourceView()), level + 1);
            else
                content += renderExampleSource(ctx, renderCtx, file->sourceView());
        }
        while (currentLevel > 1)
        {
            toc += "</ul>\n";
            currentLevel--;
        }
        toc += "</ul>\n";

        outPath         = outputFilePath(ctx.compiler(), options);
        const Utf8 page = constructPage(options, toc, content, false);
        return writeDocumentationFile(ctx, outPath, page);
    }

    Result appendAdditionalPages(TaskContext& ctx, const PageOptions& options, std::vector<fs::path>& paths)
    {
        if (options.morePages.empty())
            return Result::Continue;

        size_t start = 0;
        while (start <= options.morePages.size())
        {
            size_t end = options.morePages.find(';', start);
            if (end == Utf8::npos)
                end = options.morePages.size();
            const std::string_view value = trimView(options.morePages.subView(start, end - start));
            if (!value.empty())
            {
                fs::path path(value);
                if (path.is_relative())
                    path = ctx.compiler().cmdLine().modulePath / path;

                Utf8 because;
                if (FileSystem::resolveExistingFile(path, because) != Result::Continue)
                    return reportDocFileError(ctx, path, because);
                paths.push_back(path);
            }
            if (end == options.morePages.size())
                break;
            start = end + 1;
        }
        return Result::Continue;
    }

    Result collectPageSourcePaths(TaskContext& ctx, std::vector<fs::path>& paths)
    {
        const fs::path  sourceRoot = ctx.cmdLine().modulePath / "src";
        std::error_code ec;
        if (!ctx.cmdLine().modulePath.empty() && fs::is_directory(sourceRoot, ec))
        {
            fs::recursive_directory_iterator       it(sourceRoot, ec);
            const fs::recursive_directory_iterator end;
            while (!ec && it != end)
            {
                if (it->is_regular_file(ec))
                {
                    Utf8 extension = Utf8(it->path().extension().string());
                    extension.make_lower();
                    if (extension == ".md" || extension == ".swg" || extension == ".swgs")
                        paths.push_back(it->path());
                }
                it.increment(ec);
            }

            if (ec)
                return reportDocFileError(ctx, sourceRoot, FileSystem::normalizeSystemMessage(ec));
        }
        else
        {
            for (const SourceFile* file : moduleSourceFiles(ctx.compiler()))
                paths.push_back(file->path());
        }

        std::ranges::sort(paths);
        paths.erase(std::unique(paths.begin(), paths.end()), paths.end());
        return Result::Continue;
    }

    Result generatePages(TaskContext& ctx, PageOptions options, std::vector<fs::path>& outPaths)
    {
        std::vector<fs::path> paths;
        SWC_RESULT(collectPageSourcePaths(ctx, paths));
        SWC_RESULT(appendAdditionalPages(ctx, options, paths));

        const RenderContext renderCtx = {
            .ctx        = &ctx,
            .options    = &options,
            .references = nullptr,
        };

        for (const fs::path& path : paths)
        {
            std::string source;
            SWC_RESULT(readDocumentationSource(ctx, path, source));

            Utf8 content;
            if (path.extension() == ".md")
                content = renderMarkdownLines(renderCtx, splitLines(source));
            else
                content = renderExampleSource(ctx, renderCtx, source);

            fs::path outPath = DocGenerator::outputDirectory(ctx.compiler()) / path.filename();
            outPath.replace_extension(".html");
            outPath = outPath.lexically_normal();

            PageOptions pageOptions  = options;
            pageOptions.titleContent = correctTitle(path.stem().string());
            const Utf8 page          = constructPage(pageOptions, {}, content, true);
            SWC_RESULT(writeDocumentationFile(ctx, outPath, page));
            outPaths.push_back(std::move(outPath));
        }
        return Result::Continue;
    }

    Result generateRuntimeDocumentationOnce(TaskContext& ctx, const fs::path& outputDirectory, uint32_t& outNumFiles)
    {
        PageOptions options = getRuntimePageOptions(ctx.compiler());
        if (options.titleToc.empty())
            options.titleToc = "Table of Contents";

        Utf8 runtimeFileName = "swag.runtime.html";
        fs::path runtimePath  = outputDirectory / fs::path(runtimeFileName.c_str());
        runtimePath           = runtimePath.lexically_normal();
        const Utf8 runtimeKey = Utf8(FileSystem::normalizePath(runtimePath));

        {
            const std::scoped_lock lock(g_RuntimeDocMutex);
            if (!g_GeneratedRuntimeDocs.insert(runtimeKey).second)
                return Result::Continue;
        }

        fs::path generatedPath;
        if (generateApi(ctx, options, true, generatedPath) != Result::Continue)
        {
            const std::scoped_lock lock(g_RuntimeDocMutex);
            g_GeneratedRuntimeDocs.erase(runtimeKey);
            return Result::Error;
        }
        outNumFiles++;
        return Result::Continue;
    }
}

using namespace DocInternal;

Result DocGenerator::generate(GenerateResult& outResult) const
{
    SWC_ASSERT(ctx_ != nullptr);
    outResult = {};

    TaskContext&      ctx       = *ctx_;
    CompilerInstance& compiler  = ctx.compiler();
    PageOptions       options   = getPageOptions(compiler);
    const fs::path    outputDir = outputDirectory(compiler);
    if (ctx.cmdLine().outputDoc)
        SWC_RESULT(ensureOutputDirectory(ctx, outputDir));

    if (options.css.empty())
        options.css = "style.css";
    if (options.titleToc.empty())
        options.titleToc = "Table of Contents";
    if (options.titleContent.empty())
    {
        options.titleContent = "Module ";
        options.titleContent += defaultArtifactName(compiler.cmdLine());
    }
    SWC_RESULT(writeDocumentationStyles(ctx, options));

    switch (options.kind)
    {
        case Runtime::BuildCfgDocKind::None:
            break;

        case Runtime::BuildCfgDocKind::Api:
            SWC_RESULT(generateApi(ctx, options, false, outResult.primaryOutput));
            outResult.numFiles++;
            break;

        case Runtime::BuildCfgDocKind::Examples:
            SWC_RESULT(generateExamples(ctx, options, outResult.primaryOutput));
            outResult.numFiles++;
            break;

        case Runtime::BuildCfgDocKind::Pages:
        {
            std::vector<fs::path> paths;
            SWC_RESULT(generatePages(ctx, options, paths));
            outResult.numFiles += static_cast<uint32_t>(paths.size());
            if (!paths.empty())
                outResult.primaryOutput = paths.front();
            break;
        }
    }

    SWC_RESULT(generateRuntimeDocumentationOnce(ctx, outputDir, outResult.numFiles));
    return Result::Continue;
}

fs::path DocGenerator::outputDirectory(const CompilerInstance& compiler)
{
    const CommandLine& cmdLine = compiler.cmdLine();
    if (!cmdLine.docOutputDir.empty())
        return cmdLine.docOutputDir;
    if (!cmdLine.workspacePath.empty())
        return (cmdLine.workspacePath / ".output" / "doc").lexically_normal();
    if (!cmdLine.modulePath.empty())
        return (cmdLine.modulePath / ".output" / "doc").lexically_normal();
    if (!cmdLine.moduleFilePath.empty())
        return (cmdLine.moduleFilePath.parent_path() / ".output" / "doc").lexically_normal();
    return (fs::current_path() / ".output" / "doc").lexically_normal();
}

Utf8 DocGenerator::renderMarkdownForTest(TaskContext& ctx, const std::string_view text)
{
    const PageOptions   options;
    const RenderContext renderCtx = {
        .ctx        = &ctx,
        .options    = &options,
        .references = nullptr,
    };
    return renderMarkdownLines(renderCtx, splitLines(text));
}

SWC_END_NAMESPACE();

