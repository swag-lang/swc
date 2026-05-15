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

    void recordPublicDecl(ModuleApiState& state, const SourceViewRef srcViewRef, const AstNodeRef declRef)
    {
        if (!srcViewRef.isValid() || declRef.isInvalid())
            return;

        ModuleApiState::Shard& shard = state.shards[ModuleApiState::shardIndex(srcViewRef)];
        const std::unique_lock lock(shard.mutex);
        ModuleApiFileEntry&    entry = shard.files[srcViewRef];
        if (std::ranges::find(entry.publicDeclRefs, declRef) == entry.publicDeclRefs.end())
            entry.publicDeclRefs.push_back(declRef);
    }

    void markUnsupportedPublicDecl(ModuleApiState& state, const SourceViewRef srcViewRef)
    {
        if (!srcViewRef.isValid())
            return;

        ModuleApiState::Shard& shard = state.shards[ModuleApiState::shardIndex(srcViewRef)];
        const std::unique_lock lock(shard.mutex);
        shard.files[srcViewRef].hasUnsupportedPublicDecl = true;
    }

    bool snapshotFileEntry(const ModuleApiState& state, const SourceViewRef srcViewRef, ModuleApiFileEntry& outEntry)
    {
        outEntry = {};
        if (!srcViewRef.isValid())
            return false;

        const ModuleApiState::Shard& shard = state.shards[ModuleApiState::shardIndex(srcViewRef)];
        const std::shared_lock       lock(shard.mutex);
        const auto                   it = shard.files.find(srcViewRef);
        if (it == shard.files.end())
            return false;

        outEntry = it->second;
        return true;
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

    uint32_t sourceTokenByteEnd(const SourceView& srcView, const Token& token)
    {
        return sourceTokenByteStart(srcView, token) + token.byteLength;
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

        return node.tokRef();
    }

    bool tryGetModuleApiSnippet(const SourceFile& file, const AstNodeRef nodeRef, std::string_view& outSnippet)
    {
        outSnippet = {};
        if (nodeRef.isInvalid())
            return false;

        const Ast& ast = file.ast();
        if (!ast.hasSourceView())
            return false;

        const AstNode& node        = ast.node(nodeRef);
        const TokenRef startTokRef = moduleApiSnippetStartTokRef(ast, node);
        if (!startTokRef.isValid())
            return false;

        const SourceView& srcView   = ast.srcView();
        const TokenRef    endTokRef = node.tokRefEnd(ast);
        if (!endTokRef.isValid())
            return false;

        const std::string_view source      = file.sourceView();
        const uint32_t         startOffset = sourceTokenByteStart(srcView, srcView.token(startTokRef));
        uint32_t               endOffset   = sourceTokenByteEnd(srcView, srcView.token(endTokRef));

        if (endTokRef.get() + 1 < srcView.numTokens())
        {
            const Token& nextToken = srcView.token(TokenRef(endTokRef.get() + 1));
            if (nextToken.id == TokenId::SymSemiColon)
                endOffset = sourceTokenByteEnd(srcView, nextToken);
        }

        if (startOffset >= endOffset || endOffset > source.size())
            return false;

        outSnippet = source.substr(startOffset, endOffset - startOffset);
        return true;
    }

    bool matchVarDeclListRoot(const Ast& ast, const AstNode& node, std::unordered_set<AstNodeRef>& unmatchedDecls)
    {
        SmallVector<AstNodeRef> childRefs;
        ast.appendNodes(childRefs, node.cast<AstVarDeclList>().spanChildrenRef);
        if (childRefs.empty())
            return false;

        for (const AstNodeRef childRef : childRefs)
        {
            if (!childRef.isValid() || !unmatchedDecls.contains(childRef))
                return false;
        }

        for (const AstNodeRef childRef : childRefs)
            unmatchedDecls.erase(childRef);
        return true;
    }

    void collectGeneratedRootsForNode(const Ast& ast, const AstNodeRef nodeRef, AstNodeRef outerRef, std::unordered_set<AstNodeRef>& unmatchedDecls, std::vector<AstNodeRef>& outRootRefs)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = ast.node(nodeRef);
        if (!outerRef.isValid())
            outerRef = nodeRef;

        if (node.is(AstNodeId::AccessModifier))
        {
            collectGeneratedRootsForNode(ast, node.cast<AstAccessModifier>().nodeWhatRef, outerRef, unmatchedDecls, outRootRefs);
            return;
        }

        if (node.is(AstNodeId::AttributeList))
        {
            collectGeneratedRootsForNode(ast, node.cast<AstAttributeList>().nodeBodyRef, outerRef, unmatchedDecls, outRootRefs);
            return;
        }

        if (node.is(AstNodeId::VarDeclList))
        {
            if (matchVarDeclListRoot(ast, node, unmatchedDecls))
                outRootRefs.push_back(outerRef);
            return;
        }

        if (unmatchedDecls.erase(nodeRef))
            outRootRefs.push_back(outerRef);
    }

    bool collectGeneratedRootsForFile(const SourceFile& file, const ModuleApiFileEntry& fileEntry, std::vector<AstNodeRef>& outRootRefs)
    {
        outRootRefs.clear();
        if (fileEntry.publicDeclRefs.empty())
            return true;

        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return false;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return false;

        std::unordered_set<AstNodeRef> unmatchedDecls;
        unmatchedDecls.reserve(fileEntry.publicDeclRefs.size());
        for (const AstNodeRef declRef : fileEntry.publicDeclRefs)
            unmatchedDecls.insert(declRef);

        SmallVector<AstNodeRef> childRefs;
        file.ast().appendNodes(childRefs, rootNode.cast<AstFile>().spanChildrenRef);
        for (const AstNodeRef childRef : childRefs)
            collectGeneratedRootsForNode(file.ast(), childRef, AstNodeRef::invalid(), unmatchedDecls, outRootRefs);

        return unmatchedDecls.empty();
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
        for (const ModuleApiGeneratedRoot& root : roots)
        {
            if (!root.file)
                continue;

            std::string_view snippetText;
            if (!tryGetModuleApiSnippet(*root.file, root.nodeRef, snippetText))
                continue;

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
    void onSymbolSemaCompleted(ModuleApiState& state, TaskContext& ctx, const Symbol& symbol)
    {
        if (!symbol.isPublic())
            return;

        const SourceFile* sourceFile = sourceFileFromRef(ctx.compiler(), symbol.srcViewRef());
        if (!sourceFile || !sourceFile->hasFlag(FileFlagsE::ModuleSrc) || sourceFile->isImportedApi())
            return;

        if (!isSupportedPublicDeclSymbol(symbol))
        {
            markUnsupportedPublicDecl(state, symbol.srcViewRef());
            return;
        }

        const AstNodeRef declRef = symbol.decl()->nodeRef(sourceFile->ast());
        if (!declRef.isValid())
        {
            markUnsupportedPublicDecl(state, symbol.srcViewRef());
            return;
        }

        recordPublicDecl(state, symbol.srcViewRef(), declRef);
    }

    Result exportFiles(TaskContext& ctx, const ModuleApiState& state)
    {
        CompilerInstance& compiler     = ctx.compiler();
        const fs::path&   exportApiDir = compiler.cmdLine().exportApiDir;
        if (exportApiDir.empty())
            return Result::Continue;

        const Utf8                          moduleNamespace      = buildModuleNamespaceName(compiler);
        const SourceFile*                   firstSourceFile      = nullptr;
        bool                                hasModuleSources     = false;
        bool                                supportsGeneratedApi = true;
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

            ModuleApiFileEntry fileEntry;
            if (!snapshotFileEntry(state, file->ast().srcView().ref(), fileEntry))
                continue;

            if (fileEntry.hasUnsupportedPublicDecl)
            {
                supportsGeneratedApi = false;
                continue;
            }

            std::vector<AstNodeRef> fileRootRefs;
            if (!collectGeneratedRootsForFile(*file, fileEntry, fileRootRefs))
            {
                supportsGeneratedApi = false;
                continue;
            }

            for (const AstNodeRef rootRef : fileRootRefs)
                generatedRoots.push_back({.file = file, .nodeRef = rootRef});
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

        if (!supportsGeneratedApi || generatedRoots.empty() || !firstSourceFile)
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
