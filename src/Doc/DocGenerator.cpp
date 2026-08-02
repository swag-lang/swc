#include "pch.h"
#include "Doc/DocGenerator.h"
#include "Compiler/SourceFile.h"
#include "Doc/DocApi.h"
#include "Doc/DocFile.h"
#include "Doc/DocMarkdown.h"
#include "Doc/DocPage.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::mutex               g_RuntimeDocMutex;
    std::unordered_set<Utf8> g_GeneratedRuntimeDocs;
    std::mutex               g_StylesheetMutex;

    DocPageOptions getPageOptions(const CompilerInstance& compiler)
    {
        const Runtime::BuildCfgGenDoc& genDoc = compiler.buildCfg().genDoc;

        DocPageOptions result;
        result.kind                = genDoc.kind;
        result.theme               = genDoc.theme;
        result.outputName          = Utf8(genDoc.outputName);
        result.titleToc            = Utf8(genDoc.titleToc);
        result.titleContent        = Utf8(genDoc.titleContent);
        result.css                 = Utf8(genDoc.css);
        result.icon                = Utf8(genDoc.icon);
        result.morePages           = Utf8(genDoc.morePages);
        result.quoteIconNote       = Utf8(genDoc.quoteIconNote);
        result.quoteIconTip        = Utf8(genDoc.quoteIconTip);
        result.quoteIconWarning    = Utf8(genDoc.quoteIconWarning);
        result.quoteIconAttention  = Utf8(genDoc.quoteIconAttention);
        result.quoteIconExample    = Utf8(genDoc.quoteIconExample);
        result.quoteTitleNote      = Utf8(genDoc.quoteTitleNote);
        result.quoteTitleTip       = Utf8(genDoc.quoteTitleTip);
        result.quoteTitleWarning   = Utf8(genDoc.quoteTitleWarning);
        result.quoteTitleAttention = Utf8(genDoc.quoteTitleAttention);
        result.quoteTitleExample   = Utf8(genDoc.quoteTitleExample);
        result.brandName           = Utf8(genDoc.brandName);
        result.brandUrl            = Utf8(genDoc.brandUrl);
        result.navLinks            = Utf8(genDoc.navLinks);
        result.footer              = Utf8(genDoc.footer);
        result.syntaxDefaultColor  = genDoc.syntaxDefaultColor;
        result.accentColor         = genDoc.accentColor;
        result.hasSwagWatermark    = genDoc.hasSwagWatermark;
        result.hasSymbolIndex      = genDoc.hasSymbolIndex;

        if (!compiler.cmdLine().docCss.empty())
            result.css = compiler.cmdLine().docCss;
        return result;
    }

    DocPageOptions getRuntimePageOptions(const CompilerInstance& compiler)
    {
        DocPageOptions result = getPageOptions(compiler);
        result.kind           = Runtime::BuildCfgDocKind::Api;
        result.outputName     = "swag.runtime";
        result.titleContent   = "Swag Runtime";
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

    Result ensureOutputDirectory(TaskContext& ctx, const fs::path& path)
    {
        std::error_code ec;
        fs::create_directories(path, ec);
        if (ec)
            return reportDocDirectoryError(ctx, path, FileSystem::normalizeSystemMessage(ec));
        return Result::Continue;
    }

    Result writeDocumentationStyles(TaskContext& ctx, const DocPageOptions& options)
    {
        if (!ctx.cmdLine().outputDoc)
            return Result::Continue;

        const fs::path outputDir = DocGenerator::outputDirectory(ctx.compiler()).lexically_normal();
        const fs::path cssPath(options.css.c_str());
        if (cssPath.is_absolute() || options.css.contains("://"))
            return DocFile::reportError(ctx, cssPath, "the stylesheet path must be relative to the documentation output directory");

        const fs::path path     = (outputDir / cssPath).lexically_normal();
        const fs::path relative = path.lexically_relative(outputDir);
        if (relative.empty() || (relative.begin() != relative.end() && *relative.begin() == ".."))
            return DocFile::reportError(ctx, cssPath, "the stylesheet path must stay inside the documentation output directory");

        const std::scoped_lock lock(g_StylesheetMutex);
        SWC_RESULT(ensureOutputDirectory(ctx, path.parent_path()));
        return DocFile::write(ctx, path, DocPage::styles());
    }

    // The leading '#global' directives of a documented source file configure the module, not
    // the example, so the reader gains nothing from seeing them repeated on every chapter.
    bool isModulePreamble(const std::string_view code)
    {
        bool hasDirective = false;
        for (const Utf8& line : Utf8Helper::splitLines(code))
        {
            const std::string_view value = Utf8Helper::trim(line);
            if (value.empty())
                continue;
            if (!value.starts_with("#global"))
                return false;
            hasDirective = true;
        }
        return hasDirective;
    }

    Utf8 renderExampleSource(const TaskContext& ctx, const DocRenderContext& renderCtx, const std::string_view source)
    {
        const std::vector<Utf8> lines = Utf8Helper::splitLines(source);
        Utf8                    result;
        size_t                  index   = 0;
        bool                    isFirst = true;
        while (index < lines.size())
        {
            Utf8 code;
            while (index < lines.size() && !Utf8Helper::trim(lines[index]).starts_with("/**"))
            {
                code += lines[index++];
                code += "\n";
            }
            if (!(isFirst && isModulePreamble(code)))
                result += DocMarkdown::renderCodeBlock(ctx, code, true, &renderCtx);
            isFirst = false;
            if (index == lines.size())
                break;

            index++;
            std::vector<Utf8> comment;
            while (index < lines.size() && !Utf8Helper::trim(lines[index]).starts_with("*/"))
                comment.push_back(lines[index++]);
            if (index < lines.size())
                index++;
            result += DocMarkdown::renderLines(renderCtx, comment, 2);
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

    Result generateExamples(TaskContext& ctx, DocPageOptions options, fs::path& outPath)
    {
        if (options.titleContent.empty())
            options.titleContent = "Swag Examples";
        if (options.titleToc.empty())
            options.titleToc = "Table of Contents";

        const DocRenderContext renderCtx = {
            .ctx        = &ctx,
            .options    = &options,
            .references = nullptr,
        };

        Utf8 toc     = std::format("<h2>{}</h2>\n<ul>\n", Utf8Helper::escapeHtml(options.titleToc));
        Utf8 content = std::format("<h1>{}</h1>\n", Utf8Helper::escapeHtml(options.titleContent));

        uint32_t currentLevel = 1;
        bool     hasOpenItem  = false;
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
            if (currentLevel < level)
            {
                SWC_ASSERT(hasOpenItem);
                toc += "\n<ul>\n";
                currentLevel++;
            }
            else
            {
                if (hasOpenItem)
                    toc += "</li>\n";
                while (currentLevel > level)
                {
                    toc += "</ul>\n</li>\n";
                    currentLevel--;
                }
            }

            const Utf8 title  = Utf8Helper::toTitle(stem.substr(8));
            const Utf8 anchor = DocMarkdown::makeAnchor(file->name());
            toc.append(std::format("<li><a href=\"#{}\">{}</a>", anchor, Utf8Helper::escapeHtml(title)));
            hasOpenItem = true;
            content.append(std::format("<h{} id=\"{}\">{}</h{}>\n", level + 1, anchor, Utf8Helper::escapeHtml(title), level + 1));

            if (file->path().extension() == ".md")
                content += DocMarkdown::renderLines(renderCtx, Utf8Helper::splitLines(file->sourceView()), level + 1);
            else
                content += renderExampleSource(ctx, renderCtx, file->sourceView());
        }
        if (hasOpenItem)
            toc += "</li>\n";
        while (currentLevel > 1)
        {
            toc += "</ul>\n</li>\n";
            currentLevel--;
        }
        toc += "</ul>\n";

        outPath         = DocFile::outputPath(ctx.compiler(), options);
        const Utf8 page = DocPage::construct(options, toc, content, false);
        return DocFile::write(ctx, outPath, page);
    }

    Result appendAdditionalPages(TaskContext& ctx, const DocPageOptions& options, std::vector<fs::path>& paths)
    {
        if (options.morePages.empty())
            return Result::Continue;

        size_t start = 0;
        while (start <= options.morePages.size())
        {
            size_t end = options.morePages.find(';', start);
            if (end == Utf8::npos)
                end = options.morePages.size();
            const std::string_view value = Utf8Helper::trim(options.morePages.subView(start, end - start));
            if (!value.empty())
            {
                fs::path path(value);
                if (path.is_relative())
                    path = ctx.compiler().cmdLine().modulePath / path;

                Utf8 because;
                if (FileSystem::resolveExistingFile(path, because) != Result::Continue)
                    return DocFile::reportError(ctx, path, because);
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
                    auto extension = Utf8(it->path().extension().string());
                    extension.make_lower();
                    if (extension == ".md" || extension == ".swg" || extension == ".swgs")
                        paths.push_back(it->path());
                }
                it.increment(ec);
            }

            if (ec)
                return DocFile::reportError(ctx, sourceRoot, FileSystem::normalizeSystemMessage(ec));
        }
        else
        {
            for (const SourceFile* file : moduleSourceFiles(ctx.compiler()))
                paths.push_back(file->path());
        }

        std::ranges::sort(paths);
        paths.erase(std::ranges::unique(paths).begin(), paths.end());
        return Result::Continue;
    }

    Result generatePages(TaskContext& ctx, const DocPageOptions& options, std::vector<fs::path>& outPaths)
    {
        std::vector<fs::path> paths;
        SWC_RESULT(collectPageSourcePaths(ctx, paths));
        SWC_RESULT(appendAdditionalPages(ctx, options, paths));

        const DocRenderContext renderCtx = {
            .ctx        = &ctx,
            .options    = &options,
            .references = nullptr,
        };

        for (const fs::path& path : paths)
        {
            std::string source;
            SWC_RESULT(DocFile::read(ctx, path, source));

            Utf8 content;
            if (path.extension() == ".md")
                content = DocMarkdown::renderLines(renderCtx, Utf8Helper::splitLines(source));
            else
                content = renderExampleSource(ctx, renderCtx, source);

            fs::path outPath = DocGenerator::outputDirectory(ctx.compiler()) / path.filename();
            outPath.replace_extension(".html");
            outPath = outPath.lexically_normal();

            DocPageOptions pageOptions = options;
            if (path.stem() != "index")
                pageOptions.titleContent = Utf8Helper::toTitle(path.stem().string());
            const Utf8 page            = DocPage::construct(pageOptions, {}, content, true);
            SWC_RESULT(DocFile::write(ctx, outPath, page));
            outPaths.push_back(std::move(outPath));
        }
        return Result::Continue;
    }

    Result generateRuntimeDocumentationOnce(TaskContext& ctx, const fs::path& outputDirectory, uint32_t& outNumFiles)
    {
        DocPageOptions options = getRuntimePageOptions(ctx.compiler());
        if (options.titleToc.empty())
            options.titleToc = "Table of Contents";

        const Utf8 runtimeFileName = "swag.runtime.html";
        fs::path   runtimePath     = outputDirectory / fs::path(runtimeFileName.c_str());
        runtimePath                = runtimePath.lexically_normal();
        const auto runtimeKey      = Utf8(FileSystem::normalizePath(runtimePath));

        {
            const std::scoped_lock lock(g_RuntimeDocMutex);
            if (!g_GeneratedRuntimeDocs.insert(runtimeKey).second)
                return Result::Continue;
        }

        fs::path generatedPath;
        if (DocApi::generate(ctx, options, true, generatedPath) != Result::Continue)
        {
            const std::scoped_lock lock(g_RuntimeDocMutex);
            g_GeneratedRuntimeDocs.erase(runtimeKey);
            return Result::Error;
        }
        outNumFiles++;
        return Result::Continue;
    }
}

Result DocGenerator::generate(GenerateResult& outResult) const
{
    SWC_ASSERT(ctx_ != nullptr);
    outResult = {};

    TaskContext&            ctx       = *ctx_;
    const CompilerInstance& compiler  = ctx.compiler();
    DocPageOptions          options   = getPageOptions(compiler);
    const fs::path          outputDir = outputDirectory(compiler);
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
            SWC_RESULT(DocApi::generate(ctx, options, false, outResult.primaryOutput));
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
    const DocPageOptions   options;
    const DocRenderContext renderCtx = {
        .ctx        = &ctx,
        .options    = &options,
        .references = nullptr,
    };
    return DocMarkdown::renderLines(renderCtx, Utf8Helper::splitLines(text));
}

SWC_END_NAMESPACE();
