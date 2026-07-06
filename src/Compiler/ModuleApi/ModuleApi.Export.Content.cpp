#include "pch.h"
#include "Backend/RuntimeName.h"
#include "Compiler/ModuleApi/ModuleApi.Export.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/SourceFile.h"
#include "Format/Formatter.h"
#include "Main/Command/CommandLine.h"
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();
using namespace ModuleApi::Export;

namespace
{
    struct ModuleApiImplEntry
    {
        Utf8              prefix;
        std::vector<Utf8> snippets;
    };

    struct ModuleApiUsingSnippet
    {
        std::vector<IdentifierRef> namespacePath;
        Utf8                       snippet;
    };

    struct ModuleApiOrderedEntry
    {
        std::vector<IdentifierRef> namespacePath;
        std::vector<Utf8>          snippets;
        Utf8                       implPrefix;
        const SourceFile*          file    = nullptr;
        AstNodeRef                 implRef = AstNodeRef::invalid();
        bool                       isImpl  = false;
    };

    bool extractFileNamespacePath(TaskContext& ctx, const SourceFile& file, std::string_view moduleNamespace, std::vector<IdentifierRef>& outNamespacePath)
    {
        outNamespacePath.clear();
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return true;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return true;

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, rootNode.cast<AstFile>().spanGlobalsRef);
        for (const AstNodeRef globalRef : globalRefs)
        {
            if (globalRef.isInvalid())
                continue;

            const AstNode& globalNode = file.ast().node(globalRef);
            if (globalNode.isNot(AstNodeId::CompilerGlobal))
                continue;

            const auto& global = globalNode.cast<AstCompilerGlobal>();
            if (global.mode != AstCompilerGlobal::Mode::Namespace)
                continue;

            SmallVector<TokenRef> nameRefs;
            file.ast().appendTokens(nameRefs, global.spanNameRef);
            for (const TokenRef nameRef : nameRefs)
            {
                if (!nameRef.isValid())
                    continue;

                const std::string_view name = file.ast().srcView().tokenString(nameRef);
                if (name.empty() || name == ".")
                    continue;

                if (outNamespacePath.empty() && name == moduleNamespace)
                    continue;

                outNamespacePath.push_back(ctx.idMgr().addIdentifier(name));
            }

            break;
        }

        return true;
    }

    void appendIndentedSnippet(Utf8& outContent, std::string_view snippetText, std::string_view indent, std::string_view eol)
    {
        size_t pos = 0;
        while (pos < snippetText.size())
        {
            const size_t lineStart = pos;
            size_t       lineEnd   = pos;
            while (lineEnd < snippetText.size() && snippetText[lineEnd] != '\r' && snippetText[lineEnd] != '\n')
                lineEnd++;

            const std::string_view line = snippetText.substr(lineStart, lineEnd - lineStart);
            if (!line.empty())
                outContent += indent;
            outContent.append(line);

            if (lineEnd < snippetText.size())
            {
                outContent += eol;
                pos = lineEnd + 1;
                if (snippetText[lineEnd] == '\r' && pos < snippetText.size() && snippetText[pos] == '\n')
                    pos++;
                continue;
            }

            pos = lineEnd;
        }
    }

    void appendImplEntry(Utf8& outContent, const ModuleApiImplEntry& entry, const Utf8& indent, const std::string_view eol)
    {
        if (entry.prefix.empty())
            return;

        appendIndentedSnippet(outContent, entry.prefix.view(), indent.view(), eol);
        outContent += eol;
        outContent += indent;
        outContent += "{";
        outContent += eol;

        Utf8 childIndent = indent;
        childIndent += "    ";
        for (const Utf8& snippet : entry.snippets)
        {
            appendIndentedSnippet(outContent, snippet.view(), childIndent.view(), eol);
            if (snippet.back() != '\n' && snippet.back() != '\r')
                outContent += eol;
        }

        outContent += indent;
        outContent += "}";
        outContent += eol;
    }

    Result formatGeneratedModuleApiContent(const TaskContext& ctx, Utf8& outContent)
    {
        FormatOptions options;
        options.insertFinalNewline         = true;
        options.trimTrailingNewlines       = true;
        options.preserveTrailingWhitespace = false;

        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(ctx.global(), outContent.view()));
        outContent = formatter.text();
        return Result::Continue;
    }

    fs::path buildGeneratedModuleApiImportPath(const CompilerInstance& compiler, const fs::path& exportApiDir)
    {
        const Utf8 moduleName = buildModuleArtifactName(compiler);
        fs::path   result     = exportApiDir / fs::path(moduleName.c_str());
        result.replace_extension(".deps");
        return result.lexically_normal();
    }

    Utf8 moduleApiImportLocationForExport(const CompilerInstance& compiler, const CompilerInstance::ModuleSetupImport& importRequest)
    {
        if (importRequest.location.empty())
            return {};
        if (importRequest.location == "swag@std")
            return importRequest.location;

        fs::path locationPath{importRequest.location.c_str()};
        if (locationPath.is_relative())
        {
            const fs::path baseDir = compiler.cmdLine().moduleFilePath.parent_path();
            if (!baseDir.empty())
                locationPath = (baseDir / locationPath).lexically_normal();
        }

        return Utf8{FileSystem::normalizePath(locationPath)};
    }

    void appendGeneratedModuleImportLine(Utf8& outContent, const CompilerInstance& compiler, const CompilerInstance::ModuleSetupImport& importRequest, const std::string_view eol)
    {
        outContent += "#import(\"";
        outContent += importRequest.moduleName;
        outContent += "\"";

        const Utf8 location = moduleApiImportLocationForExport(compiler, importRequest);
        if (!location.empty())
        {
            outContent += ", location: \"";
            outContent += location;
            outContent += "\"";
        }

        if (!importRequest.version.empty())
        {
            outContent += ", version: \"";
            outContent += importRequest.version;
            outContent += "\"";
        }

        if (importRequest.linkBackendKind != Runtime::BuildCfgBackendKind::None)
        {
            outContent += ", link: \"";
            outContent += backendKindName(importRequest.linkBackendKind);
            outContent += "\"";
        }

        outContent += ")";
        outContent += eol;
    }

    Result collectFileUsingSnippets(TaskContext& ctx, const SourceFile& file, std::string_view moduleNamespace, std::string_view eol, std::vector<ModuleApiUsingSnippet>& outSnippets)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return Result::Continue;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return Result::Continue;

        std::vector<IdentifierRef> namespacePath;
        extractFileNamespacePath(ctx, file, moduleNamespace, namespacePath);

        SmallVector<AstNodeRef> usingRefs;
        file.ast().appendNodes(usingRefs, rootNode.cast<AstFile>().spanUsingsRef);
        for (const AstNodeRef usingRef : usingRefs)
        {
            if (usingRef.isInvalid())
                continue;

            std::string_view snippetText;
            if (!tryGetModuleApiSnippet(ctx, file, usingRef, snippetText))
                continue;

            uint32_t startOffset = 0;
            uint32_t endOffset   = 0;
            if (!tryGetModuleApiSnippetOffsets(ctx, file, usingRef, startOffset, endOffset))
                continue;

            Utf8 sanitizedSnippet = buildSanitizedModuleApiSnippet(ctx, file, usingRef, startOffset, snippetText, eol);
            if (sanitizedSnippet.empty())
                continue;

            outSnippets.push_back({.namespacePath = namespacePath, .snippet = std::move(sanitizedSnippet)});
        }

        return Result::Continue;
    }

    Utf8 buildNamespacePathKey(TaskContext& ctx, std::span<const IdentifierRef> namespacePath)
    {
        Utf8 key;
        for (const IdentifierRef idRef : namespacePath)
        {
            key += "::";
            key += ctx.idMgr().get(idRef).name;
        }

        return key;
    }

    uint32_t commonNamespacePrefixCount(std::span<const IdentifierRef> lhs, std::span<const IdentifierRef> rhs)
    {
        const uint32_t limit = std::min<uint32_t>(static_cast<uint32_t>(lhs.size()), static_cast<uint32_t>(rhs.size()));
        uint32_t       count = 0;
        while (count < limit && lhs[count] == rhs[count])
            ++count;
        return count;
    }

    Utf8 buildNamespaceIndent(const uint32_t depth)
    {
        Utf8 indent;
        for (uint32_t i = 0; i < depth; ++i)
            indent += "    ";
        return indent;
    }

    void closeNamespaceBlocks(Utf8& outContent, std::span<const IdentifierRef> openNamespacePath, const uint32_t keepCount, std::string_view eol)
    {
        for (uint32_t depth = static_cast<uint32_t>(openNamespacePath.size()); depth > keepCount; --depth)
        {
            const Utf8 indent = buildNamespaceIndent(depth - 1);
            outContent += indent;
            outContent += "}";
            outContent += eol;
        }
    }

    void openNamespaceBlocks(TaskContext& ctx, Utf8& outContent, std::span<const IdentifierRef> namespacePath, const uint32_t fromCount, std::string_view eol)
    {
        for (uint32_t depth = fromCount; depth < namespacePath.size(); ++depth)
        {
            const Utf8 indent = buildNamespaceIndent(depth);
            outContent += indent;
            outContent += "namespace ";
            outContent += ctx.idMgr().get(namespacePath[depth]).name;
            outContent += eol;
            outContent += indent;
            outContent += "{";
            outContent += eol;
        }
    }

    void appendOrderedEntryContent(Utf8& outContent, const ModuleApiOrderedEntry& entry, std::string_view eol)
    {
        const Utf8 indent = buildNamespaceIndent(static_cast<uint32_t>(entry.namespacePath.size()));
        if (entry.isImpl)
        {
            appendImplEntry(outContent, {.prefix = entry.implPrefix, .snippets = entry.snippets}, indent, eol);
            return;
        }

        for (const Utf8& snippet : entry.snippets)
        {
            appendIndentedSnippet(outContent, snippet.view(), indent.view(), eol);
            if (snippet.back() != '\n' && snippet.back() != '\r')
                outContent += eol;
        }
    }

    void appendOrderedSnippet(std::vector<ModuleApiOrderedEntry>& outEntries, std::span<const IdentifierRef> namespacePath, Utf8&& snippet)
    {
        if (snippet.empty())
            return;

        if (!outEntries.empty() &&
            !outEntries.back().isImpl &&
            sameNamespacePath(outEntries.back().namespacePath, namespacePath))
        {
            outEntries.back().snippets.push_back(std::move(snippet));
            return;
        }

        ModuleApiOrderedEntry entry;
        entry.namespacePath.assign(namespacePath.begin(), namespacePath.end());
        entry.snippets.push_back(std::move(snippet));
        outEntries.push_back(std::move(entry));
    }

    void appendOrderedImplSnippet(std::vector<ModuleApiOrderedEntry>& outEntries, std::span<const IdentifierRef> namespacePath, const SourceFile& file, AstNodeRef implRef, Utf8&& implPrefix, Utf8&& snippet)
    {
        if (snippet.empty() || implPrefix.empty())
            return;

        if (!outEntries.empty() &&
            outEntries.back().isImpl &&
            outEntries.back().file == &file &&
            outEntries.back().implRef == implRef &&
            outEntries.back().implPrefix == implPrefix &&
            sameNamespacePath(outEntries.back().namespacePath, namespacePath))
        {
            outEntries.back().snippets.push_back(std::move(snippet));
            return;
        }

        ModuleApiOrderedEntry entry;
        entry.namespacePath.assign(namespacePath.begin(), namespacePath.end());
        entry.snippets.push_back(std::move(snippet));
        entry.implPrefix = std::move(implPrefix);
        entry.file       = &file;
        entry.implRef    = implRef;
        entry.isImpl     = true;
        outEntries.push_back(std::move(entry));
    }

    void appendOrderedEntries(TaskContext& ctx, Utf8& outContent, std::span<const ModuleApiOrderedEntry> entries, std::string_view eol)
    {
        std::vector<IdentifierRef> openNamespacePath;
        for (const ModuleApiOrderedEntry& entry : entries)
        {
            const uint32_t sharedCount = commonNamespacePrefixCount(openNamespacePath, entry.namespacePath);
            closeNamespaceBlocks(outContent, openNamespacePath, sharedCount, eol);
            openNamespaceBlocks(ctx, outContent, entry.namespacePath, sharedCount, eol);
            openNamespacePath = entry.namespacePath;
            appendOrderedEntryContent(outContent, entry, eol);
        }

        closeNamespaceBlocks(outContent, openNamespacePath, 0, eol);
    }

    bool tryExtractLeadingNamespacePath(TaskContext& ctx, std::vector<IdentifierRef>& outNamespacePath, std::span<const IdentifierRef> parentNamespacePath, std::string_view snippet)
    {
        constexpr std::string_view namespacePrefix = "namespace ";
        outNamespacePath.clear();
        if (!snippet.starts_with(namespacePrefix))
            return false;

        outNamespacePath.assign(parentNamespacePath.begin(), parentNamespacePath.end());

        std::string_view remaining = snippet.substr(namespacePrefix.size());
        const size_t     bodyPos   = remaining.find_first_of("{\r\n");
        if (bodyPos == std::string_view::npos)
            return false;

        remaining = remaining.substr(0, bodyPos);
        while (!remaining.empty())
        {
            const size_t splitPos = remaining.find('.');
            const auto   name     = splitPos == std::string_view::npos ? remaining : remaining.substr(0, splitPos);
            if (name.empty())
                return false;

            outNamespacePath.push_back(ctx.idMgr().addIdentifier(name));
            if (splitPos == std::string_view::npos)
                break;

            remaining.remove_prefix(splitPos + 1);
        }

        return !outNamespacePath.empty();
    }

    Utf8 buildForwardNamespaceDeclLine(TaskContext& ctx, std::span<const IdentifierRef> namespacePath)
    {
        Utf8 result;
        result += "namespace ";
        for (size_t i = 0; i < namespacePath.size(); ++i)
        {
            if (i)
                result += ".";
            result += ctx.idMgr().get(namespacePath[i]).name;
        }

        result += " {}";
        return result;
    }

    void appendForwardNamespaceDeclLine(TaskContext& ctx, Utf8& outContent, std::span<const IdentifierRef> namespacePath, std::string_view eol, std::unordered_set<Utf8>* emittedPreambleLines)
    {
        const Utf8 line = buildForwardNamespaceDeclLine(ctx, namespacePath);
        outContent += line;
        outContent += eol;
        if (emittedPreambleLines)
            emittedPreambleLines->insert(line);
    }

    bool appendForwardNamespaceDecls(TaskContext& ctx, Utf8& outContent, std::span<const ModuleApiGeneratedRoot> roots, std::string_view eol, ModuleApiValidationStack& validationStack, std::unordered_set<Utf8>* emittedPreambleLines = nullptr)
    {
        bool                       emitted = false;
        std::unordered_set<Utf8>   emittedPaths;
        std::vector<IdentifierRef> namespacePath;
        Utf8                       snippet;

        for (const ModuleApiGeneratedRoot& root : roots)
        {
            if (!root.namespacePath.empty())
            {
                const Utf8 pathKey = buildNamespacePathKey(ctx, root.namespacePath);
                if (emittedPaths.insert(pathKey).second)
                {
                    appendForwardNamespaceDeclLine(ctx, outContent, root.namespacePath, eol, emittedPreambleLines);
                    emitted = true;
                }
            }

            if (buildGeneratedRootSnippet(ctx, root, eol, snippet, validationStack) != Result::Continue || snippet.empty())
                continue;
            if (!tryExtractLeadingNamespacePath(ctx, namespacePath, root.namespacePath, snippet.view()))
                continue;

            const Utf8 pathKey = buildNamespacePathKey(ctx, namespacePath);
            if (!emittedPaths.insert(pathKey).second)
                continue;

            appendForwardNamespaceDeclLine(ctx, outContent, namespacePath, eol, emittedPreambleLines);
            emitted = true;
        }

        return emitted;
    }

    Result buildGeneratedModuleApiContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent, ModuleApiValidationStack& validationStack)
    {
        outContent.clear();
        outContent += "#global namespace ";
        outContent += moduleNamespace;
        outContent += eol;
        outContent += "#global public";
        outContent += eol;
        if (appendForwardNamespaceDecls(ctx, outContent, roots, eol, validationStack))
            outContent += eol;

        std::vector<ModuleApiOrderedEntry>    orderedEntries;
        std::unordered_set<Utf8>              emittedUsingKeys;
        std::unordered_set<const SourceFile*> usingFiles;

        for (const ModuleApiGeneratedRoot& root : roots)
        {
            if (root.file && usingFiles.insert(root.file).second)
            {
                std::vector<ModuleApiUsingSnippet> usingSnippets;
                SWC_RESULT(collectFileUsingSnippets(ctx, *root.file, moduleNamespace, eol, usingSnippets));
                for (ModuleApiUsingSnippet& usingSnippet : usingSnippets)
                {
                    Utf8 usingKey = buildNamespacePathKey(ctx, usingSnippet.namespacePath);
                    usingKey += '\n';
                    usingKey += usingSnippet.snippet;
                    if (!emittedUsingKeys.insert(usingKey).second)
                        continue;

                    appendOrderedSnippet(orderedEntries, usingSnippet.namespacePath, std::move(usingSnippet.snippet));
                }
            }

            Utf8 sanitizedSnippet;
            SWC_RESULT(buildGeneratedRootSnippet(ctx, root, eol, sanitizedSnippet, validationStack));
            if (sanitizedSnippet.empty())
                continue;

            const AstNodeRef implRef = root.file ? findEnclosingImplRef(*root.file, root.nodeRef) : AstNodeRef::invalid();
            if (root.file && implRef.isValid())
            {
                Utf8 implPrefix;
                if (tryBuildImplPrefix(ctx, *root.file, implRef, eol, implPrefix))
                {
                    appendOrderedImplSnippet(orderedEntries, root.namespacePath, *root.file, implRef, std::move(implPrefix), std::move(sanitizedSnippet));
                    continue;
                }
            }

            AstNodeRef        semanticImplRef  = AstNodeRef::invalid();
            const SourceFile* semanticImplFile = nullptr;
            if (tryFindSemanticImplRef(ctx, root, semanticImplRef, semanticImplFile))
            {
                Utf8 implPrefix;
                if (tryBuildImplPrefix(ctx, *semanticImplFile, semanticImplRef, eol, implPrefix))
                {
                    appendOrderedImplSnippet(orderedEntries, root.namespacePath, *semanticImplFile, semanticImplRef, std::move(implPrefix), std::move(sanitizedSnippet));
                    continue;
                }
            }

            appendOrderedSnippet(orderedEntries, root.namespacePath, std::move(sanitizedSnippet));
        }

        appendOrderedEntries(ctx, outContent, orderedEntries, eol);

        if (roots.empty() && outContent.back() != '\n' && outContent.back() != '\r')
            outContent += eol;

        return formatGeneratedModuleApiContent(ctx, outContent);
    }

    Result removeGeneratedModuleApiHeader(Utf8& ioContent, std::string_view moduleNamespace, std::string_view eol)
    {
        Utf8 prefix;
        prefix += "#global namespace ";
        prefix += moduleNamespace;
        prefix += eol;
        prefix += "#global public";
        prefix += eol;
        if (!ioContent.starts_with(prefix))
            return Result::Error;

        ioContent.erase(0, prefix.size());
        if (ioContent.starts_with(eol))
            ioContent.erase(0, eol.size());
        return Result::Continue;
    }

    bool isGeneratedModuleApiPreambleLine(std::string_view line)
    {
        return line.starts_with("using ") || (line.starts_with("namespace ") && line.ends_with(" {}"));
    }

    void trimLeadingGeneratedModulePreamble(Utf8& ioContent, std::unordered_set<Utf8>& emittedPreambleLines, std::string_view eol)
    {
        size_t pos = 0;
        Utf8   trimmed;
        bool   emittedAnyPreambleLine = false;
        while (pos < ioContent.size())
        {
            const size_t lineStart = pos;
            size_t       lineEnd   = pos;
            while (lineEnd < ioContent.size() && ioContent[lineEnd] != '\r' && ioContent[lineEnd] != '\n')
                ++lineEnd;

            const std::string_view line = ioContent.subView(lineStart, lineEnd - lineStart);
            if (line.empty())
            {
                pos = lineEnd;
                while (pos < ioContent.size() && (ioContent[pos] == '\r' || ioContent[pos] == '\n'))
                    ++pos;
                continue;
            }

            if (!isGeneratedModuleApiPreambleLine(line))
                break;

            Utf8 preambleLine{line};
            if (emittedPreambleLines.insert(preambleLine).second)
            {
                trimmed += preambleLine;
                trimmed += eol;
                emittedAnyPreambleLine = true;
            }

            pos = lineEnd;
            while (pos < ioContent.size() && (ioContent[pos] == '\r' || ioContent[pos] == '\n'))
                ++pos;
        }

        if (emittedAnyPreambleLine && pos < ioContent.size())
            trimmed += eol;

        trimmed.append(ioContent.substr(pos));
        ioContent = std::move(trimmed);
    }
}

namespace ModuleApi::Export
{
    Utf8 buildExportedModuleApiContent(const SourceFile& file, std::string_view moduleNamespace, bool hasModuleNamespace)
    {
        const std::string_view source = file.sourceView();
        if (hasModuleNamespace)
            return Utf8{source};

        uint32_t insertOffset = file.ast().srcView().sourceStartOffset();
        if (file.ast().srcView().numTokens())
        {
            const Token& firstToken = file.ast().srcView().token(TokenRef(0));
            if (firstToken.id != TokenId::EndOfFile)
                insertOffset = firstToken.byteStart;
        }

        insertOffset = std::min<uint32_t>(insertOffset, static_cast<uint32_t>(source.size()));

        Utf8 content;
        content.reserve(source.size() + moduleNamespace.size() + 32);
        content.append(source.substr(0, insertOffset));
        content += "#global namespace ";
        content += moduleNamespace;
        content += preferredLineEnding(file);
        content.append(source.substr(insertOffset));
        return content;
    }

    Result writeGeneratedModuleImports(TaskContext& ctx, const fs::path& exportApiDir, std::string_view eol)
    {
        const auto& moduleImports = ctx.compiler().moduleSetupImports();
        if (moduleImports.empty())
            return Result::Continue;

        Utf8 content;
        for (const CompilerInstance::ModuleSetupImport& importRequest : moduleImports)
            appendGeneratedModuleImportLine(content, ctx.compiler(), importRequest, eol);

        SWC_RESULT(formatGeneratedModuleApiContent(ctx, content));
        return writeModuleApiFile(ctx, buildGeneratedModuleApiImportPath(ctx.compiler(), exportApiDir), content.view());
    }

    Result buildGeneratedModuleApiSingleFileContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent)
    {
        outContent.clear();
        outContent += "#global namespace ";
        outContent += moduleNamespace;
        outContent += eol;
        outContent += "#global public";
        outContent += eol;

        std::unordered_set<Utf8> emittedPreambleLines;
        ModuleApiValidationStack validationStack;
        if (appendForwardNamespaceDecls(ctx, outContent, roots, eol, validationStack, &emittedPreambleLines))
            outContent += eol;

        // Split the roots into per-source-file contiguous groups (cheap, sequential).
        struct RootGroup
        {
            size_t start;
            size_t count;
        };
        std::vector<RootGroup> groups;
        for (size_t rootIndex = 0; rootIndex < roots.size();)
        {
            const SourceFile* sourceFile = roots[rootIndex].file;
            size_t            nextIndex  = rootIndex + 1;
            while (nextIndex < roots.size() && roots[nextIndex].file == sourceFile)
                ++nextIndex;
            groups.push_back({rootIndex, nextIndex - rootIndex});
            rootIndex = nextIndex;
        }

        // Build each group's content in parallel. Each group uses its own validation stack;
        // the snippet *bytes* don't depend on cross-group validation state (it only drives
        // diagnostics), and preamble/forward-decl deduplication is handled below by the
        // sequential merge through `emittedPreambleLines`.
        std::vector<Utf8> groupContents(groups.size());
        std::vector       groupResults(groups.size(), Result::Continue);
        parallelForIndexed(ctx, static_cast<uint32_t>(groups.size()), [&](TaskContext& workerCtx, uint32_t g) {
            ModuleApiValidationStack groupValidationStack;
            groupResults[g] = buildGeneratedModuleApiContent(workerCtx, roots.subspan(groups[g].start, groups[g].count), moduleNamespace, eol, groupContents[g], groupValidationStack);
        });

        bool appendedBlock = false;
        for (size_t g = 0; g < groups.size(); ++g)
        {
            SWC_RESULT(groupResults[g]);
            Utf8& fileContent = groupContents[g];
            SWC_RESULT(removeGeneratedModuleApiHeader(fileContent, moduleNamespace, eol));
            trimLeadingGeneratedModulePreamble(fileContent, emittedPreambleLines, eol);
            if (!fileContent.empty())
            {
                outContent += eol;
                if (appendedBlock && !outContent.ends_with(eol))
                    outContent += eol;
                outContent += fileContent;
                appendedBlock = true;
            }
        }

        const Utf8 tripleBreak = std::format("{}{}{}", eol, eol, eol);
        const Utf8 doubleBreak = std::format("{}{}", eol, eol);
        outContent.replace_loop(tripleBreak.view(), doubleBreak.view());
        return formatGeneratedModuleApiContent(ctx, outContent);
    }
}

SWC_END_NAMESPACE();
