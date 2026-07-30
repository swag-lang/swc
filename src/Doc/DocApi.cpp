#include "pch.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/SourceFile.h"
#include "Doc/DocInternal.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/SyntaxColor.h"

SWC_BEGIN_NAMESPACE();

namespace DocInternal
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
            return reportDocFileError(ctx, helpRoot, FileSystem::normalizeSystemMessage(ec));
        std::ranges::sort(paths);

        std::unordered_set<Utf8> anchors;
        for (const fs::path& path : paths)
        {
            std::string source;
            SWC_RESULT(readDocumentationSource(ctx, path, source));

            DocGuide guide;
            guide.lines = splitLines(source);
            for (auto lineIt = guide.lines.begin(); lineIt != guide.lines.end(); ++lineIt)
            {
                const std::string_view line = trimView(*lineIt);
                if (line.empty())
                    continue;
                if (line.starts_with("# "))
                {
                    guide.title = trimCopy(line.substr(2));
                    guide.lines.erase(lineIt);
                }
                break;
            }
            if (guide.title.empty())
                guide.title = correctTitle(path.stem().string());

            guide.anchor = "guide_";
            guide.anchor += makeAnchor(guide.title);
            const Utf8 anchorBase = guide.anchor;
            uint32_t   suffix     = 2;
            while (!anchors.insert(guide.anchor).second)
                guide.anchor = std::format("{}_{}", anchorBase, suffix++);
            guides.push_back(std::move(guide));
        }
        return Result::Continue;
    }

    Result generateApi(TaskContext& ctx, PageOptions options, const bool runtime, fs::path& outPath)
    {
        if (options.titleContent.empty())
        {
            if (!ctx.cmdLine().modulePath.empty())
                options.titleContent = correctTitle(ctx.cmdLine().modulePath.filename().string());
            else
                options.titleContent = "API Reference";
        }
        if (options.titleToc.empty())
            options.titleToc = options.titleContent;

        ApiDocument document;
        if (!runtime)
            SWC_RESULT(collectApiGuides(ctx, document.guides));
        collectDocItems(ctx, document.items, runtime);
        renderApiDocument(ctx, document, options, runtime);

        Utf8 moduleName = fromRuntimeString(ctx.compiler().buildCfg().moduleNamespace);
        if (moduleName.empty())
            moduleName = options.titleContent;

        RenderContext renderCtx = {
            .ctx                = &ctx,
            .options            = &options,
            .references         = &document.references,
            .externalReferences = &document.externalReferences,
            .externalModules    = &document.externalModules,
            .moduleName         = moduleName,
        };

        Utf8 content;
        content.append(std::format("<section class=\"module-overview\"><h1 id=\"overview\">{}</h1>\n", escapeHtml(options.titleContent)));
        if (!runtime)
        {
            const Utf8 moduleComment = defaultModuleDocComment(ctx.compiler());
            if (!moduleComment.empty())
            {
                const std::vector<Utf8> lines = splitLines(moduleComment);
                renderCtx.headingAnchorPrefix = "overview";
                content += renderMarkdownLines(renderCtx, lines);
            }
        }
        content += "</section>\n";
        content += document.content;

        Utf8 toc;
        toc.append(std::format("<h2>{}</h2>\n", escapeHtml(options.titleToc)));
        toc += document.toc;

        outPath         = outputFilePath(ctx.compiler(), options);
        const Utf8 page = constructPage(options, toc, content, false);
        return writeDocumentationFile(ctx, outPath, page);
    }
}

SWC_END_NAMESPACE();
