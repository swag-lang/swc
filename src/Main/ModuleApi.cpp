#include "pch.h"
#include "Main/ModuleApi.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Format/Formatter.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ModuleApiFileInfo
    {
        bool legacyExported     = false;
        bool hasModuleNamespace = false;
    };

    struct ModuleApiGeneratedRoot
    {
        const SourceFile* file    = nullptr;
        AstNodeRef        nodeRef = AstNodeRef::invalid();
    };

    const SourceFile* sourceFileFromRef(const CompilerInstance& compiler, const SourceViewRef srcViewRef)
    {
        if (!srcViewRef.isValid())
            return nullptr;

        const SourceView& srcView = compiler.srcView(srcViewRef);
        return srcView.file();
    }

    Utf8 buildCfgString(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};

        return Utf8{value};
    }

    Utf8 buildModuleNamespaceName(const CompilerInstance& compiler)
    {
        Utf8 moduleNamespaceName = buildCfgString(compiler.buildCfg().moduleNamespace);
        if (!moduleNamespaceName.empty())
            return moduleNamespaceName;

        Utf8 artifactName = buildCfgString(compiler.buildCfg().name);
        if (artifactName.empty())
            artifactName = defaultArtifactName(compiler.cmdLine());
        return defaultModuleNamespace(artifactName);
    }

    bool isSupportedPublicDeclSymbol(const Symbol& symbol)
    {
        if (!symbol.isConstant())
            return false;
        if (!symbol.decl())
            return false;

        return symbol.decl()->is(AstNodeId::SingleVarDecl) || symbol.decl()->is(AstNodeId::MultiVarDecl);
    }

    void mergeFileEntry(ModuleApiFileEntry& outEntry, const ModuleApiFileEntry& threadEntry)
    {
        for (const AstNodeRef rootRef : threadEntry.publicRootRefs)
        {
            if (std::ranges::find(outEntry.publicRootRefs, rootRef) == outEntry.publicRootRefs.end())
                outEntry.publicRootRefs.push_back(rootRef);
        }
    }

    void mergeThreadData(std::unordered_map<SourceViewRef, ModuleApiFileEntry>& outEntries, const ModuleApiPerThreadData& threadData)
    {
        for (const auto& [srcViewRef, threadEntry] : threadData.files)
            mergeFileEntry(outEntries[srcViewRef], threadEntry);
    }

    void recordPublicRoot(ModuleApiPerThreadData& state, const SourceViewRef srcViewRef, const AstNodeRef rootRef)
    {
        if (!srcViewRef.isValid() || rootRef.isInvalid())
            return;

        ModuleApiFileEntry& entry = state.files[srcViewRef];
        if (std::ranges::find(entry.publicRootRefs, rootRef) == entry.publicRootRefs.end())
            entry.publicRootRefs.push_back(rootRef);
    }

    ModuleApiFileInfo analyzeModuleApiFile(const SourceFile& file, std::string_view moduleNamespace)
    {
        ModuleApiFileInfo result;
        const AstNodeRef  rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return result;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return result;

        const auto& fileNode = rootNode.cast<AstFile>();

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, fileNode.spanGlobalsRef);
        for (uint32_t i = 0; i < globalRefs.size(); ++i)
        {
            const AstNodeRef globalRef = globalRefs[i];
            if (globalRef.isInvalid())
                continue;

            const AstNode& globalNode = file.ast().node(globalRef);
            if (globalNode.isNot(AstNodeId::CompilerGlobal))
                continue;

            const auto& global = globalNode.cast<AstCompilerGlobal>();
            if (i == 0 && global.mode == AstCompilerGlobal::Mode::Export)
                result.legacyExported = true;

            if (global.mode != AstCompilerGlobal::Mode::Namespace)
                continue;

            SmallVector<TokenRef> nameRefs;
            file.ast().appendTokens(nameRefs, global.spanNameRef);
            if (nameRefs.size() != 1)
                continue;

            const std::string_view namespaceName = file.ast().srcView().tokenString(nameRefs[0]);
            if (namespaceName == moduleNamespace)
                result.hasModuleNamespace = true;
        }

        return result;
    }

    std::string_view preferredLineEnding(const SourceFile& file)
    {
        const std::string_view content = file.sourceView();
        if (content.find("\r\n") != std::string_view::npos)
            return "\r\n";
        if (content.find('\n') != std::string_view::npos)
            return "\n";
        return "\r\n";
    }

    uint32_t sourceTokenByteStart(const SourceView& srcView, const Token& token)
    {
        if (token.id == TokenId::Identifier)
            return srcView.identifiers()[token.byteStart].byteStart;

        return token.byteStart;
    }

    TokenRef moduleApiSnippetStartTokRef(const Ast& ast, const AstNode& node)
    {
        if (node.is(AstNodeId::VarDeclList))
        {
            SmallVector<AstNodeRef> childRefs;
            ast.appendNodes(childRefs, node.cast<AstVarDeclList>().spanChildrenRef);
            if (!childRefs.empty() && childRefs.front().isValid() && ast.hasNode(childRefs.front()))
                return moduleApiSnippetStartTokRef(ast, ast.node(childRefs.front()));
        }

        if (ast.hasSourceView() && node.tokRef().isValid() && node.tokRef().get() > 0)
        {
            const TokenRef prevTokRef(node.tokRef().get() - 1);
            const TokenId  prevId = ast.srcView().token(prevTokRef).id;
            switch (node.id())
            {
                case AstNodeId::FunctionDecl:
                    if (prevId == TokenId::KwdFunc || prevId == TokenId::KwdMtd)
                        return prevTokRef;
                    break;

                case AstNodeId::StructDecl:
                    if (prevId == TokenId::KwdStruct)
                        return prevTokRef;
                    break;

                case AstNodeId::EnumDecl:
                    if (prevId == TokenId::KwdEnum)
                        return prevTokRef;
                    break;

                case AstNodeId::InterfaceDecl:
                    if (prevId == TokenId::KwdInterface)
                        return prevTokRef;
                    break;

                case AstNodeId::Impl:
                    if (prevId == TokenId::KwdImpl)
                        return prevTokRef;
                    break;

                default:
                    break;
            }
        }

        return node.tokRef();
    }

    bool tryGetModuleApiSnippetStartOffset(const SourceFile& file, AstNodeRef nodeRef, uint32_t& outStartOffset);

    constexpr uint32_t moduleApiInvalidByte = 0xFFFFFFFFu;

    uint32_t moduleApiNodeSortByte(const Ast& ast, const SourceView& srcView, const AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid() || ast.isAdditionalNode(nodeRef))
            return moduleApiInvalidByte;

        const AstNode& node = ast.node(nodeRef);
        if (const TokenRef tokRef = node.tokRef(); tokRef.isValid())
        {
            const Token& tok = srcView.token(tokRef);
            if (tok.isNot(TokenId::EndOfFile))
                return sourceTokenByteStart(srcView, tok);
        }

        SmallVector<AstNodeRef> children;
        Ast::nodeIdInfos(node.id()).collectChildren(children, ast, node);

        uint32_t result = moduleApiInvalidByte;
        for (const AstNodeRef childRef : children)
            result = std::min(result, moduleApiNodeSortByte(ast, srcView, childRef));
        return result;
    }

    void collectModuleApiSourceOrderedChildren(const Ast& ast, const SourceView& srcView, const AstNode& node, SmallVector<AstNodeRef>& outChildren)
    {
        outChildren.clear();
        Ast::nodeIdInfos(node.id()).collectChildren(outChildren, ast, node);
        std::ranges::stable_sort(outChildren, [&](const AstNodeRef left, const AstNodeRef right) { return moduleApiNodeSortByte(ast, srcView, left) < moduleApiNodeSortByte(ast, srcView, right); });
    }

    void findNextSiblingSnippetStartOffsetRec(const SourceFile& file, const AstNodeRef currentRef, const AstNodeRef targetRef, bool& ioFoundTarget, uint32_t& ioNextOffset)
    {
        if (currentRef.isInvalid() || ioNextOffset != moduleApiInvalidByte)
            return;

        const Ast&        ast     = file.ast();
        const SourceView& srcView = ast.srcView();
        if (ast.isAdditionalNode(currentRef))
            return;

        const AstNode& currentNode = ast.node(currentRef);
        SmallVector<AstNodeRef> children;
        collectModuleApiSourceOrderedChildren(ast, srcView, currentNode, children);
        for (size_t i = 0; i < children.size(); ++i)
        {
            const AstNodeRef childRef = children[i];
            if (childRef.isInvalid() || ast.isAdditionalNode(childRef))
                continue;

            if (childRef == targetRef)
                ioFoundTarget = true;
            else
                findNextSiblingSnippetStartOffsetRec(file, childRef, targetRef, ioFoundTarget, ioNextOffset);

            if (ioNextOffset != moduleApiInvalidByte)
                return;

            if (!ioFoundTarget)
                continue;

            for (size_t j = i + 1; j < children.size(); ++j)
            {
                uint32_t siblingStartOffset = 0;
                if (!tryGetModuleApiSnippetStartOffset(file, children[j], siblingStartOffset))
                    continue;

                ioNextOffset = siblingStartOffset;
                return;
            }

            return;
        }
    }

    uint32_t findNextSiblingSnippetStartOffset(const SourceFile& file, const AstNodeRef targetRef)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return moduleApiInvalidByte;

        bool     foundTarget = false;
        uint32_t nextOffset  = moduleApiInvalidByte;
        findNextSiblingSnippetStartOffsetRec(file, rootRef, targetRef, foundTarget, nextOffset);
        return nextOffset;
    }

    bool tryGetModuleApiSnippetStartOffset(const SourceFile& file, const AstNodeRef nodeRef, uint32_t& outStartOffset)
    {
        outStartOffset = 0;
        if (nodeRef.isInvalid())
            return false;

        const Ast& ast = file.ast();
        if (!ast.hasSourceView())
            return false;

        const AstNode& node        = ast.node(nodeRef);
        const TokenRef startTokRef = moduleApiSnippetStartTokRef(ast, node);
        if (!startTokRef.isValid())
            return false;

        const SourceView& srcView = ast.srcView();
        outStartOffset            = sourceTokenByteStart(srcView, srcView.token(startTokRef));
        return true;
    }

    bool tryGetModuleApiSnippet(const SourceFile& file, const AstNodeRef nodeRef, const uint32_t maxEndOffset, std::string_view& outSnippet)
    {
        outSnippet = {};
        const Ast& ast = file.ast();
        uint32_t   startOffset = 0;
        if (!tryGetModuleApiSnippetStartOffset(file, nodeRef, startOffset))
            return false;

        const SourceView&      srcView   = ast.srcView();
        const std::string_view source    = file.sourceView();
        uint32_t               endOffset = static_cast<uint32_t>(source.size());
        endOffset = std::min(endOffset, findNextSiblingSnippetStartOffset(file, nodeRef));

        endOffset = std::min(endOffset, maxEndOffset);
        while (endOffset > startOffset && std::isspace(static_cast<unsigned char>(source[endOffset - 1])))
            endOffset--;

        if (startOffset >= endOffset || endOffset > source.size())
            return false;

        outSnippet = source.substr(startOffset, endOffset - startOffset);
        return true;
    }

    bool containsExportRootDecl(const Ast& ast, const AstNodeRef nodeRef, const AstNodeRef declRef)
    {
        if (!nodeRef.isValid() || !declRef.isValid())
            return false;

        if (nodeRef == declRef)
            return true;

        const AstNode& node = ast.node(nodeRef);
        if (node.is(AstNodeId::AccessModifier))
            return containsExportRootDecl(ast, node.cast<AstAccessModifier>().nodeWhatRef, declRef);

        if (node.is(AstNodeId::AttributeList))
            return containsExportRootDecl(ast, node.cast<AstAttributeList>().nodeBodyRef, declRef);

        if (node.is(AstNodeId::VarDeclList))
        {
            SmallVector<AstNodeRef> childRefs;
            ast.appendNodes(childRefs, node.cast<AstVarDeclList>().spanChildrenRef);
            for (const AstNodeRef childRef : childRefs)
            {
                if (containsExportRootDecl(ast, childRef, declRef))
                    return true;
            }
        }

        return false;
    }

    AstNodeRef findTopLevelExportRoot(const SourceFile& file, const AstNodeRef declRef)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return AstNodeRef::invalid();

        SmallVector<AstNodeRef> childRefs;
        file.ast().appendNodes(childRefs, rootNode.cast<AstFile>().spanChildrenRef);
        for (const AstNodeRef childRef : childRefs)
        {
            if (containsExportRootDecl(file.ast(), childRef, declRef))
                return childRef;
        }

        return AstNodeRef::invalid();
    }

    void appendGeneratedRootsForFile(const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<ModuleApiGeneratedRoot>& outRoots)
    {
        if (fileEntry.publicRootRefs.empty())
            return;

        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return;

        SmallVector<AstNodeRef> childRefs;
        file.ast().appendNodes(childRefs, rootNode.cast<AstFile>().spanChildrenRef);
        for (const AstNodeRef childRef : childRefs)
        {
            if (std::ranges::find(fileEntry.publicRootRefs, childRef) == fileEntry.publicRootRefs.end())
                continue;

            const AstNode& childNode    = file.ast().node(childRef);
            const TokenRef startTokRef  = moduleApiSnippetStartTokRef(file.ast(), childNode);
            const bool     canMergeRoot = startTokRef.isValid() && !outRoots.empty() && outRoots.back().file == &file;
            if (canMergeRoot)
            {
                const AstNode& previousNode      = file.ast().node(outRoots.back().nodeRef);
                const TokenRef previousStartTok  = moduleApiSnippetStartTokRef(file.ast(), previousNode);
                if (previousStartTok == startTokRef)
                {
                    outRoots.back().nodeRef = childRef;
                    continue;
                }
            }

            outRoots.push_back({.file = &file, .nodeRef = childRef});
        }
    }

    fs::path buildGeneratedModuleApiPath(const CompilerInstance& compiler, const fs::path& exportApiDir)
    {
        Utf8 moduleName = defaultArtifactName(compiler.cmdLine());
        if (moduleName.empty())
            moduleName = "module";

        fs::path result = exportApiDir / fs::path(moduleName.c_str());
        result.replace_extension(".swg");
        return result.lexically_normal();
    }

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

    Result formatGeneratedModuleApiContent(const TaskContext& ctx, Utf8& outContent)
    {
        Formatter formatter;
        SWC_RESULT(formatter.prepare(ctx.global(), outContent.view()));
        outContent = formatter.text();
        return Result::Continue;
    }

    Result buildGeneratedModuleApiContent(const TaskContext& ctx, std::span<const ModuleApiGeneratedRoot> roots, std::string_view moduleNamespace, std::string_view eol, Utf8& outContent)
    {
        outContent.clear();
        outContent += "#global namespace ";
        outContent += moduleNamespace;
        outContent += eol;
        outContent += "#global public";
        outContent += eol;

        bool wroteSnippet = false;
        std::vector<std::pair<fs::path, std::string_view>> seenSnippets;
        seenSnippets.reserve(roots.size());
        for (size_t i = 0; i < roots.size(); ++i)
        {
            const ModuleApiGeneratedRoot& root = roots[i];
            if (!root.file)
                continue;

            uint32_t nextRootStart = std::numeric_limits<uint32_t>::max();
            for (size_t j = i + 1; j < roots.size(); ++j)
            {
                if (roots[j].file != root.file || !roots[j].file)
                    break;

                if (tryGetModuleApiSnippetStartOffset(*roots[j].file, roots[j].nodeRef, nextRootStart))
                    break;
            }

            std::string_view snippetText;
            if (!tryGetModuleApiSnippet(*root.file, root.nodeRef, nextRootStart, snippetText))
                continue;
            if (std::ranges::any_of(seenSnippets, [&](const auto& seen) { return seen.first == root.file->path() && seen.second == snippetText; }))
                continue;
            seenSnippets.emplace_back(root.file->path(), snippetText);

            outContent += eol;
            outContent += snippetText;
            if (!snippetText.empty() && snippetText.back() != '\n' && snippetText.back() != '\r')
                outContent += eol;
            wroteSnippet = true;
        }

        if (!wroteSnippet)
            outContent += eol;

        return formatGeneratedModuleApiContent(ctx, outContent);
    }

    Result writeModuleApiFile(TaskContext& ctx, const fs::path& dstPath, std::string_view content)
    {
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(dstPath, content.data(), content.size(), ioError) == Result::Continue)
            return Result::Continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_file_write_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, dstPath, FileSystem::describeIoFailure(ioError));
        diag.report(ctx);
        return Result::Error;
    }

    Result ensureModuleApiDirectory(TaskContext& ctx, const fs::path& path)
    {
        if (path.empty())
            return Result::Continue;

        std::error_code ec;
        fs::create_directories(path, ec);
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_dir_create_failed);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return Result::Error;
        }

        return Result::Continue;
    }

    Result reportInvalidFolder(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }
}

namespace ModuleApi
{
    void onSymbolSemaCompleted(ModuleApiPerThreadData& state, TaskContext& ctx, const Symbol& symbol)
    {
        if (!symbol.isPublic())
            return;

        const SourceFile* sourceFile = sourceFileFromRef(ctx.compiler(), symbol.srcViewRef());
        if (!sourceFile || !sourceFile->hasFlag(FileFlagsE::ModuleSrc) || sourceFile->isImportedApi())
            return;

        if (!isSupportedPublicDeclSymbol(symbol))
            return;

        const AstNodeRef declRef = symbol.decl()->nodeRef(sourceFile->ast());
        if (declRef.isInvalid())
            return;

        const AstNodeRef rootRef = findTopLevelExportRoot(*sourceFile, declRef);
        if (rootRef.isInvalid())
            return;

        recordPublicRoot(state, symbol.srcViewRef(), rootRef);
    }

    Result exportFiles(TaskContext& ctx)
    {
        CompilerInstance& compiler     = ctx.compiler();
        const fs::path&   exportApiDir = compiler.cmdLine().exportApiDir;
        if (exportApiDir.empty())
            return Result::Continue;

        std::unordered_map<SourceViewRef, ModuleApiFileEntry> collectedEntries;
        for (size_t i = 0; i < compiler.numPerThreadData(); ++i)
            mergeThreadData(collectedEntries, compiler.moduleApiPerThreadData(i));

        const Utf8                          moduleNamespace      = buildModuleNamespaceName(compiler);
        const SourceFile*                   firstSourceFile      = nullptr;
        bool                                hasModuleSources     = false;
        std::vector<ModuleApiGeneratedRoot> generatedRoots;

        for (const SourceFile* file : compiler.files())
        {
            if (!file || !file->hasFlag(FileFlagsE::ModuleSrc))
                continue;

            hasModuleSources = true;
            if (!firstSourceFile)
                firstSourceFile = file;

            const ModuleApiFileInfo fileInfo = analyzeModuleApiFile(*file, moduleNamespace.view());
            if (fileInfo.legacyExported)
                continue;

            const auto fileEntryIt = collectedEntries.find(file->ast().srcView().ref());
            if (fileEntryIt == collectedEntries.end())
                continue;
            const ModuleApiFileEntry& fileEntry = fileEntryIt->second;

            appendGeneratedRootsForFile(*file, fileEntry, generatedRoots);
        }

        if (!hasModuleSources)
            return Result::Continue;

        SWC_RESULT(ensureModuleApiDirectory(ctx, exportApiDir));
        SWC_RESULT(FileSystem::clearDirectoryContents(ctx, exportApiDir, DiagnosticId::cmd_err_api_dir_clear_failed));

        std::unordered_map<Utf8, fs::path> exportedFileNames;
        for (const SourceFile* file : compiler.files())
        {
            if (!file || !file->hasFlag(FileFlagsE::ModuleSrc))
                continue;

            const ModuleApiFileInfo fileInfo = analyzeModuleApiFile(*file, moduleNamespace.view());
            if (!fileInfo.legacyExported)
                continue;

            const fs::path dstPath  = (exportApiDir / file->path().filename()).lexically_normal();
            const Utf8     fileName = dstPath.filename().string();
            const auto     inserted = exportedFileNames.emplace(fileName, file->path());
            if (!inserted.second)
            {
                const Utf8 because = std::format("duplicate exported API file name from '{}' and '{}'", inserted.first->second.string(), file->path().string());
                return reportInvalidFolder(ctx, dstPath, because);
            }

            const Utf8 content = buildExportedModuleApiContent(*file, moduleNamespace.view(), fileInfo.hasModuleNamespace);
            if (writeModuleApiFile(ctx, dstPath, content.view()) != Result::Continue)
                return Result::Error;
        }

        if (!firstSourceFile)
            return Result::Continue;

        const fs::path generatedDstPath  = buildGeneratedModuleApiPath(compiler, exportApiDir);
        const Utf8     generatedFileName = generatedDstPath.filename().string();
        if (exportedFileNames.contains(generatedFileName))
            return Result::Continue;

        Utf8 content;
        SWC_RESULT(buildGeneratedModuleApiContent(ctx, generatedRoots, moduleNamespace.view(), preferredLineEnding(*firstSourceFile), content));
        if (writeModuleApiFile(ctx, generatedDstPath, content.view()) != Result::Continue)
            return Result::Error;

        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
