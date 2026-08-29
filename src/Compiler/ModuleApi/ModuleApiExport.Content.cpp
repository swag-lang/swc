#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/ModuleApi/ModuleApiExport.Internal.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/SourceFile.h"
#include "Format/Formatter.h"
#include "Main/Command/CommandLine.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    static constexpr std::string_view NON_CONSUMER_ATTRIBUTES[] = {"Opaque", "NoDoc", "NoDuplicate", "PrintAst", "PrintMicro"};

    using ModuleApiExport::buildSanitizedModuleApiSnippet;
    using ModuleApiExport::findEnclosingImplRef;
    using ModuleApiExport::ModuleApiGeneratedRoot;
    using ModuleApiExport::sameNamespacePath;
    using ModuleApiExport::sourceTokenByteEnd;
    using ModuleApiExport::sourceTokenByteStart;
    using ModuleApiExport::tryBuildImplPrefix;
    using ModuleApiExport::tryFindSemanticImplRef;
    using ModuleApiExport::tryGetModuleApiSnippet;
    using ModuleApiExport::tryGetModuleApiSnippetOffsets;

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

    // A generated entry opens with its attribute list, and the plain 'Foreign' of an entry the
    // API reduced to a declaration says nothing its neighbours do not also say. Take it off the
    // entry so a run of them can state it once. A 'Foreign' that names a symbol stays where it
    // is: that one belongs to its own declaration.
    bool tryTakeBareForeignAttribute(Utf8& ioSnippet)
    {
        static constexpr std::string_view SOLE = "#[Foreign]";
        static constexpr std::string_view HEAD = "#[Foreign, ";

        if (ioSnippet.starts_with(HEAD))
        {
            ioSnippet.erase(2, HEAD.size() - 2);
            return true;
        }

        if (!ioSnippet.starts_with(SOLE))
            return false;

        size_t skip = SOLE.size();
        while (skip < ioSnippet.size() && (ioSnippet[skip] == '\r' || ioSnippet[skip] == '\n'))
            ++skip;
        ioSnippet.erase(0, skip);
        return true;
    }

    // States one attribute once for a run of entries instead of once per entry. A run of one is
    // written back as it came, because a block would cost more than it saves. The whole content
    // is formatted afterwards, so the braces need no indentation of their own.
    void appendForeignRun(Utf8& outContent, std::span<const Utf8> originals, std::span<const Utf8> stripped, const Utf8& indent, const std::string_view eol)
    {
        if (originals.empty())
            return;

        if (originals.size() == 1)
        {
            appendIndentedSnippet(outContent, originals.front().view(), indent.view(), eol);
            if (originals.front().back() != '\n' && originals.front().back() != '\r')
                outContent += eol;
            return;
        }

        Utf8 block = "#[Foreign]";
        block += eol;
        block += "{";
        block += eol;
        for (const Utf8& snippet : stripped)
        {
            appendIndentedSnippet(block, snippet.view(), "    ", eol);
            if (snippet.back() != '\n' && snippet.back() != '\r')
                block += eol;
        }

        block += "}";
        appendIndentedSnippet(outContent, block.view(), indent.view(), eol);
        outContent += eol;
    }

    void appendSnippetsGroupingForeign(Utf8& outContent, std::span<const Utf8> snippets, const Utf8& indent, const std::string_view eol)
    {
        std::vector<Utf8> originals;
        std::vector<Utf8> stripped;
        for (const Utf8& snippet : snippets)
        {
            Utf8 candidate = snippet;
            if (tryTakeBareForeignAttribute(candidate))
            {
                originals.push_back(snippet);
                stripped.push_back(std::move(candidate));
                continue;
            }

            appendForeignRun(outContent, originals, stripped, indent, eol);
            originals.clear();
            stripped.clear();
            appendIndentedSnippet(outContent, snippet.view(), indent.view(), eol);
            if (snippet.back() != '\n' && snippet.back() != '\r')
                outContent += eol;
        }

        appendForeignRun(outContent, originals, stripped, indent, eol);
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
        appendSnippetsGroupingForeign(outContent, entry.snippets, childIndent, eol);

        outContent += indent;
        outContent += "}";
        outContent += eol;
    }

    struct ModuleApiTextEdit
    {
        size_t start;
        size_t end;
        Utf8   replacement;
    };

    struct ModuleApiAttributeListSpan
    {
        size_t start;
        size_t end;
    };

    struct ModuleApiAttributeEntrySpan
    {
        size_t           start;
        size_t           end;
        std::string_view name;
    };

    bool isWhitespaceOnly(const std::string_view text)
    {
        return std::ranges::all_of(text, [](const char c) { return std::isspace(static_cast<unsigned char>(c)); });
    }

    bool containsModuleApiAttributeName(std::span<const std::string_view> attributeNames, const std::string_view name)
    {
        return std::ranges::find(attributeNames, name) != attributeNames.end();
    }

    std::string_view moduleApiAttributeEntryName(const SourceView& srcView, const std::span<const Token> tokens, const size_t firstTokenIndex, const size_t endTokenIndex)
    {
        if (firstTokenIndex >= endTokenIndex || tokens[firstTokenIndex].id != TokenId::Identifier)
            return {};

        const std::string_view firstName = tokens[firstTokenIndex].string(srcView);
        if (firstName != "Swag")
            return firstName;
        if (firstTokenIndex + 2 >= endTokenIndex || tokens[firstTokenIndex + 1].id != TokenId::SymDot || tokens[firstTokenIndex + 2].id != TokenId::Identifier)
            return firstName;
        return tokens[firstTokenIndex + 2].string(srcView);
    }

    void appendModuleApiAttributeEntry(std::vector<ModuleApiAttributeEntrySpan>& outEntries, const SourceView& srcView, const std::span<const Token> tokens, const size_t firstTokenIndex, const size_t endTokenIndex, const size_t separatorStart)
    {
        if (firstTokenIndex >= endTokenIndex)
            return;

        outEntries.push_back({
            .start = sourceTokenByteStart(srcView, tokens[firstTokenIndex]),
            .end   = separatorStart,
            .name  = moduleApiAttributeEntryName(srcView, tokens, firstTokenIndex, endTokenIndex),
        });
    }

    void removeNamedModuleApiAttributes(const SourceView& srcView, Utf8& ioContent, std::span<const std::string_view> attributeNames)
    {
        if (attributeNames.empty())
            return;

        std::vector<ModuleApiTextEdit> edits;
        const auto&                    tokens = srcView.tokens();
        for (size_t tokenIndex = 0; tokenIndex < tokens.size(); ++tokenIndex)
        {
            if (tokens[tokenIndex].id != TokenId::SymAttrStart)
                continue;

            const size_t                             listStart       = sourceTokenByteStart(srcView, tokens[tokenIndex]);
            size_t                                   entryTokenIndex = tokenIndex + 1;
            uint32_t                                 parenDepth      = 0;
            uint32_t                                 bracketDepth    = 1;
            uint32_t                                 curlyDepth      = 0;
            std::vector<ModuleApiAttributeEntrySpan> entries;
            for (size_t listTokenIndex = tokenIndex + 1; listTokenIndex < tokens.size(); ++listTokenIndex)
            {
                const Token& token = tokens[listTokenIndex];
                switch (token.id)
                {
                    case TokenId::SymLeftParen:
                        parenDepth++;
                        break;
                    case TokenId::SymRightParen:
                        parenDepth--;
                        break;
                    case TokenId::SymAttrStart:
                    case TokenId::SymLeftBracket:
                        bracketDepth++;
                        break;
                    case TokenId::SymRightBracket:
                        bracketDepth--;
                        break;
                    case TokenId::SymLeftCurly:
                        curlyDepth++;
                        break;
                    case TokenId::SymRightCurly:
                        curlyDepth--;
                        break;
                    default:
                        break;
                }

                const bool isSeparator = token.id == TokenId::SymComma && parenDepth == 0 && bracketDepth == 1 && curlyDepth == 0;
                const bool isListEnd   = token.id == TokenId::SymRightBracket && bracketDepth == 0;
                if (!isSeparator && !isListEnd)
                    continue;

                const size_t separatorStart = sourceTokenByteStart(srcView, token);
                appendModuleApiAttributeEntry(entries, srcView, tokens, entryTokenIndex, listTokenIndex, separatorStart);
                if (isSeparator)
                {
                    entryTokenIndex = listTokenIndex + 1;
                    continue;
                }

                bool hasRemovedEntry = false;
                Utf8 replacement     = "#[";
                bool hasKeptEntry    = false;
                for (const ModuleApiAttributeEntrySpan& entry : entries)
                {
                    if (containsModuleApiAttributeName(attributeNames, entry.name))
                    {
                        hasRemovedEntry = true;
                        continue;
                    }

                    std::string_view entryText = ioContent.subView(entry.start, entry.end - entry.start);
                    while (!entryText.empty() && std::isspace(static_cast<unsigned char>(entryText.front())))
                        entryText.remove_prefix(1);
                    while (!entryText.empty() && std::isspace(static_cast<unsigned char>(entryText.back())))
                        entryText.remove_suffix(1);
                    if (hasKeptEntry)
                        replacement += ", ";
                    replacement += entryText;
                    hasKeptEntry = true;
                }

                if (hasRemovedEntry)
                {
                    size_t editEnd = sourceTokenByteEnd(srcView, token);
                    if (hasKeptEntry)
                        replacement += "]";
                    else
                    {
                        replacement.clear();
                        while (editEnd < ioContent.size() && std::isspace(static_cast<unsigned char>(ioContent[editEnd])))
                            editEnd++;
                    }
                    edits.push_back({
                        .start       = listStart,
                        .end         = editEnd,
                        .replacement = std::move(replacement),
                    });
                }

                tokenIndex = listTokenIndex;
                break;
            }
        }

        for (auto it = edits.rbegin(); it != edits.rend(); ++it)
            ioContent.replace(it->start, it->end - it->start, it->replacement);
    }

    void tokenizeAndRemoveModuleApiAttributes(TaskContext& ctx, Utf8& ioContent, std::span<const std::string_view> attributeNames)
    {
        SourceFile lexFile(FileRef::invalid(), fs::path{}, FileFlagsE::CustomSrc);
        lexFile.setContent(ioContent.view());

        SourceView srcView(SourceViewRef::invalid(), &lexFile);
        Lexer      lexer;
        lexer.tokenize(ctx, srcView, LexerFlagsE::AllowReservedIdentifiers);
        removeNamedModuleApiAttributes(srcView, ioContent, attributeNames);
    }

    // Exported files always have the runtime prelude in scope. Normalize copied source attributes
    // to that context and fold adjacent lists before the formatter lays out the file.
    void normalizeModuleApiAttributes(const SourceView& srcView, Utf8& ioContent)
    {
        std::vector<ModuleApiAttributeListSpan> lists;
        std::vector<ModuleApiTextEdit>          edits;
        const auto&                             tokens = srcView.tokens();
        for (size_t tokenIndex = 0; tokenIndex < tokens.size(); ++tokenIndex)
        {
            if (tokens[tokenIndex].id != TokenId::SymAttrStart)
                continue;

            const size_t listStart = sourceTokenByteStart(srcView, tokens[tokenIndex]);
            uint32_t     depth     = 1;
            for (size_t listTokenIndex = tokenIndex + 1; listTokenIndex < tokens.size(); ++listTokenIndex)
            {
                const Token& token = tokens[listTokenIndex];
                if (token.id == TokenId::SymAttrStart || token.id == TokenId::SymLeftBracket)
                    depth++;
                else if (token.id == TokenId::SymRightBracket)
                    depth--;

                if (token.id == TokenId::Identifier && token.string(srcView) == "Swag" && listTokenIndex + 1 < tokens.size() && tokens[listTokenIndex + 1].id == TokenId::SymDot)
                {
                    edits.push_back({
                        .start = sourceTokenByteStart(srcView, token),
                        .end   = sourceTokenByteEnd(srcView, tokens[listTokenIndex + 1]),
                    });
                }

                if (depth)
                    continue;

                lists.push_back({listStart, sourceTokenByteEnd(srcView, token)});
                tokenIndex = listTokenIndex;
                break;
            }
        }

        for (size_t listIndex = 1; listIndex < lists.size(); ++listIndex)
        {
            const ModuleApiAttributeListSpan& previous = lists[listIndex - 1];
            const ModuleApiAttributeListSpan& current  = lists[listIndex];
            if (!isWhitespaceOnly(ioContent.subView(previous.end, current.start - previous.end)))
                continue;

            edits.push_back({
                .start       = previous.end - 1,
                .end         = current.start + 2,
                .replacement = ", ",
            });
        }

        std::ranges::sort(edits, {}, &ModuleApiTextEdit::start);
        for (auto it = edits.rbegin(); it != edits.rend(); ++it)
            ioContent.replace(it->start, it->end - it->start, it->replacement);
    }

    void normalizeModuleApiAttributes(TaskContext& ctx, Utf8& ioContent)
    {
        SourceFile lexFile(FileRef::invalid(), fs::path{}, FileFlagsE::CustomSrc);
        lexFile.setContent(ioContent.view());

        SourceView srcView(SourceViewRef::invalid(), &lexFile);
        Lexer      lexer;
        lexer.tokenize(ctx, srcView, LexerFlagsE::AllowReservedIdentifiers);
        normalizeModuleApiAttributes(srcView, ioContent);
    }

    Result formatGeneratedModuleApiContent(TaskContext& ctx, Utf8& outContent)
    {
        tokenizeAndRemoveModuleApiAttributes(ctx, outContent, NON_CONSUMER_ATTRIBUTES);
        normalizeModuleApiAttributes(ctx, outContent);

        FormatOptions options;
        options.insertFinalNewline         = true;
        options.trimTrailingNewlines       = true;
        options.preserveTrailingWhitespace = false;

        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(ctx.global(), outContent.view()));
        outContent = formatter.text();
        return Result::Continue;
    }

    fs::path buildGeneratedModuleApiImportPath(const fs::path& exportApiDir)
    {
        return (exportApiDir / ".swc-deps").lexically_normal();
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

        appendSnippetsGroupingForeign(outContent, entry.snippets, indent, eol);
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

    Result buildGeneratedModuleApiContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::span<Utf8> snippets, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent)
    {
        SWC_ASSERT(roots.size() == snippets.size());

        outContent.clear();
        outContent += "#global namespace ";
        outContent += moduleNamespace;
        outContent += eol;
        outContent += "#global public";
        outContent += eol;

        std::vector<ModuleApiOrderedEntry>    orderedEntries;
        std::unordered_set<Utf8>              emittedUsingKeys;
        std::unordered_set<const SourceFile*> usingFiles;

        for (size_t rootIndex = 0; rootIndex < roots.size(); ++rootIndex)
        {
            const ModuleApiGeneratedRoot& root             = roots[rootIndex];
            Utf8&                         sanitizedSnippet = snippets[rootIndex];
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
        return line.starts_with("using ");
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

namespace ModuleApiExport
{
    void removeModuleApiAttributes(TaskContext& ctx, Utf8& ioContent, std::span<const std::string_view> attributeNames)
    {
        tokenizeAndRemoveModuleApiAttributes(ctx, ioContent, attributeNames);
    }

    Utf8 buildExportedModuleApiContent(TaskContext& ctx, const SourceFile& file, std::string_view moduleNamespace, bool hasModuleNamespace)
    {
        const std::string_view source = file.sourceView();
        Utf8                   content;
        if (hasModuleNamespace)
        {
            content = source;
        }
        else
        {
            uint32_t insertOffset = file.ast().srcView().sourceStartOffset();
            if (file.ast().srcView().numTokens())
            {
                const Token& firstToken = file.ast().srcView().token(TokenRef(0));
                if (firstToken.id != TokenId::EndOfFile)
                    insertOffset = firstToken.byteStart;
            }

            insertOffset = std::min<uint32_t>(insertOffset, static_cast<uint32_t>(source.size()));

            content.reserve(source.size() + moduleNamespace.size() + 32);
            content.append(source.substr(0, insertOffset));
            content += "#global namespace ";
            content += moduleNamespace;
            content += preferredLineEnding(file);
            content.append(source.substr(insertOffset));
        }

        tokenizeAndRemoveModuleApiAttributes(ctx, content, NON_CONSUMER_ATTRIBUTES);
        normalizeModuleApiAttributes(ctx, content);
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
        return writeModuleApiFile(ctx, buildGeneratedModuleApiImportPath(exportApiDir), content.view());
    }

    Result buildGeneratedModuleApiSingleFileContent(TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent)
    {
        outContent.clear();
        outContent += "#global namespace ";
        outContent += moduleNamespace;
        outContent += eol;
        outContent += "#global public";
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

        // Build every sanitized snippet once; regenerating them for the per-file merge dominates
        // large generated modules such as ogl.
        std::vector<Utf8> rootSnippets(roots.size());
        std::vector       groupResults(groups.size(), Result::Continue);
        JobManager&       jobMgr = ctx.global().jobMgr();
        jobMgr.parallelForIndexed(ctx, static_cast<uint32_t>(groups.size()), JobKind::ModuleApiExport, ctx.compiler().jobClientId(), [&](TaskContext& workerCtx, uint32_t g) {
            ModuleApiValidationStack groupValidationStack;
            const size_t             groupEnd = groups[g].start + groups[g].count;
            for (size_t rootIndex = groups[g].start; rootIndex < groupEnd; ++rootIndex)
            {
                groupResults[g] = buildGeneratedRootSnippet(workerCtx, roots[rootIndex], eol, rootSnippets[rootIndex], groupValidationStack);
                if (groupResults[g] != Result::Continue)
                    break;
            }
        });

        for (const Result groupResult : groupResults)
            SWC_RESULT(groupResult);

        std::unordered_set<Utf8> emittedPreambleLines;

        // Build each group's content in parallel. Snippet bytes are moved into their final
        // ordered entries by one group.
        std::vector<Utf8> groupContents(groups.size());
        std::ranges::fill(groupResults, Result::Continue);
        jobMgr.parallelForIndexed(ctx, static_cast<uint32_t>(groups.size()), JobKind::ModuleApiExport, ctx.compiler().jobClientId(), [&](TaskContext& workerCtx, uint32_t g) {
            groupResults[g] = buildGeneratedModuleApiContent(workerCtx, roots.subspan(groups[g].start, groups[g].count), std::span{rootSnippets}.subspan(groups[g].start, groups[g].count), moduleNamespace, eol, groupContents[g]);
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
