#include "pch.h"
#include "Doc/DocApi.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/SourceFile.h"
#include "Doc/DocFile.h"
#include "Doc/DocMarkdown.h"
#include "Doc/DocPage.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result collectApiGuides(TaskContext& ctx, std::vector<DocGuide>& guides)
    {
        if (ctx.cmdLine().modulePath.empty())
            return Result::Continue;

        const fs::path  helpRoot = ctx.cmdLine().modulePath / "help";
        std::error_code ec;
        if (!fs::is_directory(helpRoot, ec))
            return Result::Continue;

        std::vector<fs::path>                  paths;
        fs::recursive_directory_iterator       it(helpRoot, ec);
        const fs::recursive_directory_iterator end;
        while (!ec && it != end)
        {
            if (it->is_regular_file(ec))
            {
                Utf8 extension = it->path().extension().string();
                extension.make_lower();
                if (extension == ".md")
                    paths.push_back(it->path());
            }
            it.increment(ec);
        }
        if (ec)
            return DocFile::reportError(ctx, helpRoot, FileSystem::normalizeSystemMessage(ec));
        std::ranges::sort(paths);

        std::unordered_set<Utf8> anchors;
        for (const fs::path& path : paths)
        {
            std::string source;
            SWC_RESULT(DocFile::read(ctx, path, source));

            DocGuide guide;
            guide.lines = Utf8Helper::splitLines(source);
            for (auto lineIt = guide.lines.begin(); lineIt != guide.lines.end(); ++lineIt)
            {
                const std::string_view line = Utf8Helper::trim(*lineIt);
                if (line.empty())
                    continue;
                if (line.starts_with("# "))
                {
                    guide.title = Utf8(Utf8Helper::trim(line.substr(2)));
                    guide.lines.erase(lineIt);
                }
                break;
            }
            if (guide.title.empty())
                guide.title = Utf8Helper::toTitle(path.stem().string());

            guide.anchor = "guide_";
            guide.anchor += DocMarkdown::makeAnchor(guide.title);
            const Utf8 anchorBase = guide.anchor;
            uint32_t   suffix     = 2;
            while (!anchors.insert(guide.anchor).second)
                guide.anchor = std::format("{}_{}", anchorBase, suffix++);
            guides.push_back(std::move(guide));
        }
        return Result::Continue;
    }

    Utf8 extractModuleDocComment(std::string_view source)
    {
        source = Utf8Helper::trim(source);
        std::vector<Utf8> result;
        if (source.starts_with("/*"))
        {
            const size_t end = source.find("*/", 2);
            if (end != std::string_view::npos)
                DocApi::appendNormalizedComment(result, source.substr(0, end + 2));
        }
        else
        {
            for (const Utf8& line : Utf8Helper::splitLines(source))
            {
                const std::string_view view = Utf8Helper::trim(line);
                if (!view.starts_with("//"))
                    break;
                DocApi::appendNormalizedComment(result, view);
            }
        }

        Utf8 comment;
        for (const Utf8& line : result)
        {
            comment += line;
            comment += "\n";
        }
        return comment;
    }

    // What the reader can reach on an API page: every namespace, every documented symbol under
    // its qualified spelling, and the guides that open the page.
    std::vector<DocSearchEntry> collectSearchEntries(const DocApiDocument& document)
    {
        std::vector<DocSearchEntry> entries;
        entries.reserve(document.items.size() + document.namespaceNames.size() + document.guides.size());

        std::unordered_set<Utf8> namespaceNames;
        for (const Utf8& name : document.namespaceNames)
        {
            namespaceNames.insert(name);
            entries.push_back({.name = name, .anchor = std::format("namespace_{}", DocMarkdown::makeAnchor(name)), .kind = 'n'});
        }

        for (const DocItem& item : document.items)
        {
            if (item.overloads.empty() || namespaceNames.contains(item.fullName))
                continue;

            Utf8 detail;
            for (const Utf8& line : item.overloads.front().commentLines)
            {
                if (!Utf8Helper::trim(line).empty())
                {
                    detail = DocSearch::summarize(line);
                    break;
                }
            }
            entries.push_back({.name = item.fullName, .anchor = DocMarkdown::makeAnchor(item.fullName), .detail = std::move(detail), .kind = DocSearch::kindLetter(item.kind)});
        }

        for (const DocGuide& guide : document.guides)
            entries.push_back({.name = guide.title, .anchor = guide.anchor, .kind = 'h'});
        return entries;
    }

    Utf8 defaultModuleDocComment(const CompilerInstance& compiler)
    {
        for (const SourceFile* file : compiler.files())
        {
            if (file && file->hasFlag(FileFlagsE::Module))
            {
                Utf8 result = extractModuleDocComment(file->sourceView());
                if (!result.empty())
                    return result;
            }
        }

        fs::path path = compiler.cmdLine().moduleFilePath;
        if (path.empty() && !compiler.cmdLine().modulePath.empty())
            path = compiler.cmdLine().modulePath / "module.swg";
        if (!path.empty())
        {
            std::string             source;
            FileSystem::IoErrorInfo error;
            if (FileSystem::readTextFile(path, source, error) == Result::Continue)
                return extractModuleDocComment(source);
        }
        return {};
    }
}

Result DocApi::generate(TaskContext& ctx, DocPageOptions options, const bool runtime, fs::path& outPath)
{
    if (options.titleContent.empty())
    {
        if (!ctx.cmdLine().modulePath.empty())
            options.titleContent = Utf8Helper::toTitle(ctx.cmdLine().modulePath.filename().string());
        else
            options.titleContent = "API Reference";
    }
    if (options.titleToc.empty())
        options.titleToc = options.titleContent;

    DocApiDocument document;
    if (!runtime)
        SWC_RESULT(collectApiGuides(ctx, document.guides));
    collectDocItems(ctx, document.items, runtime);
    renderApiDocument(ctx, document, options, runtime);

    Utf8 moduleName = ctx.compiler().buildCfg().moduleNamespace;
    if (moduleName.empty())
        moduleName = options.titleContent;

    DocRenderContext renderCtx = {
        .ctx                = &ctx,
        .options            = &options,
        .references         = &document.references,
        .externalReferences = &document.externalReferences,
        .externalModules    = &document.externalModules,
        .moduleName         = moduleName,
    };

    Utf8 content;
    content.append(std::format("<section class=\"module-overview\"><h1 id=\"overview\">{}</h1>\n", Utf8Helper::escapeHtml(options.titleContent)));
    if (!runtime)
    {
        const Utf8 moduleComment = defaultModuleDocComment(ctx.compiler());
        if (!moduleComment.empty())
        {
            const std::vector<Utf8> lines = Utf8Helper::splitLines(moduleComment);
            renderCtx.headingAnchorPrefix = "overview";
            content += DocMarkdown::renderLines(renderCtx, lines);
        }
    }
    content += "</section>\n";
    content += document.content;

    Utf8 toc;
    toc.append(std::format("<h2>{}</h2>\n", Utf8Helper::escapeHtml(options.titleToc)));
    toc += document.toc;

    const std::vector<DocSearchEntry> searchEntries = collectSearchEntries(document);

    outPath = DocFile::outputPath(ctx.compiler(), options);

    const DocPageContent pageContent = {
        .toc           = toc,
        .article       = content,
        .searchEntries = searchEntries,
    };

    const Utf8 page = DocPage::construct(options, pageContent);
    return DocFile::write(ctx, outPath, page);
}
SWC_END_NAMESPACE();
