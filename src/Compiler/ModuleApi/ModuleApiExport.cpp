#include "pch.h"
#include "Compiler/ModuleApi/ModuleApiExport.Internal.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ModuleApiFileInfo
    {
        bool wholeFileExported  = false;
        bool hasModuleNamespace = false;
    };

    Utf8 buildCfgString(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};

        return Utf8{value};
    }

    bool isWholeFileExported(const SourceFile& file)
    {
        const AstNodeRef rootRef = file.ast().root();
        if (rootRef.isInvalid())
            return false;

        const AstNode& rootNode = file.ast().node(rootRef);
        if (rootNode.isNot(AstNodeId::File))
            return false;

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, rootNode.cast<AstFile>().spanGlobalsRef);
        if (globalRefs.empty() || globalRefs.front().isInvalid())
            return false;

        const AstNode& globalNode = file.ast().node(globalRefs.front());
        if (globalNode.isNot(AstNodeId::CompilerGlobal))
            return false;

        return globalNode.cast<AstCompilerGlobal>().mode == AstCompilerGlobal::Mode::Export;
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

        result.wholeFileExported = isWholeFileExported(file);
        const auto& fileNode     = rootNode.cast<AstFile>();

        SmallVector<AstNodeRef> globalRefs;
        file.ast().appendNodes(globalRefs, fileNode.spanGlobalsRef);
        for (auto globalRef : globalRefs)
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
            if (nameRefs.size() != 1)
                continue;

            const std::string_view namespaceName = file.ast().srcView().tokenString(nameRefs[0]);
            if (namespaceName == moduleNamespace)
                result.hasModuleNamespace = true;
        }

        return result;
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

    bool isGeneratedModuleApiFile(const fs::path& path)
    {
        const fs::path extension = path.extension();
        return extension == ".swg" || extension == ".deps";
    }

    Result reportModuleApiDirectoryClearError(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_dir_clear_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    Result clearGeneratedModuleApiFiles(TaskContext& ctx, const fs::path& path)
    {
        if (path.empty())
            return Result::Continue;

        std::error_code ec;
        const bool      exists = fs::exists(path, ec);
        if (ec)
            return reportModuleApiDirectoryClearError(ctx, path, FileSystem::normalizeSystemMessage(ec));
        if (!exists)
            return Result::Continue;

        const bool isDirectory = fs::is_directory(path, ec);
        if (ec)
            return reportModuleApiDirectoryClearError(ctx, path, FileSystem::normalizeSystemMessage(ec));
        if (!isDirectory)
            return reportModuleApiDirectoryClearError(ctx, path, FileSystem::describePathProblem(FileSystem::PathProblem::NotDirectory));

        for (fs::directory_iterator it(path, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return reportModuleApiDirectoryClearError(ctx, path, FileSystem::normalizeSystemMessage(ec));

            const fs::path entryPath = it->path();
            if (!isGeneratedModuleApiFile(entryPath))
                continue;

            std::error_code removeEc;
            fs::remove(entryPath, removeEc);
            if (removeEc)
                return reportModuleApiDirectoryClearError(ctx, entryPath, FileSystem::normalizeSystemMessage(removeEc));
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

namespace ModuleApiExport
{
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

    Utf8 buildModuleArtifactName(const CompilerInstance& compiler)
    {
        Utf8 artifactName = buildCfgString(compiler.buildCfg().name);
        if (!artifactName.empty())
            return artifactName;

        artifactName = defaultArtifactName(compiler.cmdLine());
        if (!artifactName.empty())
            return artifactName;
        return "module";
    }

    bool isCurrentModuleSymbol(const CompilerInstance& compiler, const Symbol& symbol)
    {
        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        if (!sourceFile)
            return false;

        return isCurrentModuleSourceFile(*sourceFile);
    }

    bool isWholeFileExportedSymbol(const CompilerInstance& compiler, const Symbol& symbol)
    {
        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        return sourceFile && isWholeFileExported(*sourceFile);
    }

    bool sameNamespacePath(std::span<const IdentifierRef> lhs, std::span<const IdentifierRef> rhs)
    {
        return lhs.size() == rhs.size() && std::equal(lhs.begin(), lhs.end(), rhs.begin());
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
}

namespace ModuleApi
{
    Result exportFiles(TaskContext& ctx)
    {
        using ModuleApiExport::appendGeneratedRootUnique;
        using ModuleApiExport::appendGeneratedRootsForFile;
        using ModuleApiExport::buildExportedModuleApiContent;
        using ModuleApiExport::buildGeneratedModuleApiSingleFileContent;
        using ModuleApiExport::buildModuleNamespaceName;
        using ModuleApiExport::ModuleApiGeneratedRoot;
        using ModuleApiExport::preferredLineEnding;
        using ModuleApiExport::sortGeneratedModuleApiRoots;
        using ModuleApiExport::writeGeneratedModuleImports;
        using ModuleApiExport::writeModuleApiFile;

        CompilerInstance& compiler     = ctx.compiler();
        const fs::path&   exportApiDir = compiler.cmdLine().exportApiDir;
        JobManager&       jobMgr       = ctx.global().jobMgr();

        ModuleApiFileEntries localEntries;
        // Documentation consumes the same resolved entries immediately after sema. Retain
        // them on the compiler so the renderer does not repeat the AST classification pass.
        ModuleApiFileEntries& collectedEntries = compiler.cmdLine().command == CommandKind::Doc ? compiler.prepareModuleApiPublicEntries() : localEntries;
        // Sema is done here, so walking the ASTs is safe now. Without an export
        // directory, only diagnostics such as public global variables are needed.
        const bool diagnosticsOnly = exportApiDir.empty() && compiler.cmdLine().command != CommandKind::Doc;
        SWC_RESULT(collectPublicEntries(ctx, collectedEntries, diagnosticsOnly));

        if (exportApiDir.empty())
            return Result::Continue;

        const Utf8        moduleNamespace  = buildModuleNamespaceName(compiler);
        const SourceFile* firstSourceFile  = nullptr;
        bool              hasModuleSources = false;

        // Cheap sequential pass: gather the module's source files and the reduction values.
        std::vector<const SourceFile*> moduleFiles;
        for (const SourceFile* file : compiler.files())
        {
            if (!file || !isCurrentModuleSourceFile(*file))
                continue;

            if (file->hasFlag(FileFlagsE::ModuleSrc))
            {
                hasModuleSources = true;
                if (!firstSourceFile)
                    firstSourceFile = file;
            }

            moduleFiles.push_back(file);
        }

        if (!hasModuleSources)
            return Result::Continue;

        // Extract each file's generated roots in parallel (independent per file), then merge
        // sequentially in file order. The merge feeds appendGeneratedRootUnique in exactly the
        // same order as the linear path, so the deduplicated result is identical.
        const auto&                                      entries = collectedEntries;
        std::vector<std::vector<ModuleApiGeneratedRoot>> perFileRoots(moduleFiles.size());
        jobMgr.parallelForIndexed(ctx, static_cast<uint32_t>(moduleFiles.size()), JobKind::ModuleApiExport, compiler.jobClientId(), [&](TaskContext& workerCtx, uint32_t i) {
            const SourceFile*       file     = moduleFiles[i];
            const ModuleApiFileInfo fileInfo = analyzeModuleApiFile(*file, moduleNamespace.view());
            if (fileInfo.wholeFileExported)
                return;

            const auto fileEntryIt = entries.find(file->ast().srcView().ref());
            if (fileEntryIt == entries.end())
                return;

            appendGeneratedRootsForFile(workerCtx, *file, fileEntryIt->second, perFileRoots[i]);
        });

        std::vector<ModuleApiGeneratedRoot> generatedRoots;
        for (auto& fileRoots : perFileRoots)
            for (ModuleApiGeneratedRoot& root : fileRoots)
                appendGeneratedRootUnique(generatedRoots, std::move(root));

        SWC_RESULT(ensureModuleApiDirectory(ctx, exportApiDir));
        SWC_RESULT(clearGeneratedModuleApiFiles(ctx, exportApiDir));

        // Sequential pass: resolve destination paths and detect duplicate names (needs the
        // shared name map). The expensive content build + disk write is dispatched afterwards.
        struct WholeFileExport
        {
            const SourceFile* file;
            fs::path          dstPath;
            bool              hasModuleNamespace;
        };
        std::vector<WholeFileExport>       wholeExports;
        std::unordered_map<Utf8, fs::path> wholeFileExportNames;
        for (const SourceFile* file : compiler.files())
        {
            if (!file || !file->hasFlag(FileFlagsE::ModuleSrc))
                continue;

            const ModuleApiFileInfo fileInfo = analyzeModuleApiFile(*file, moduleNamespace.view());
            if (!fileInfo.wholeFileExported)
                continue;

            fs::path   dstPath  = (exportApiDir / file->path().filename()).lexically_normal();
            const Utf8 fileName = dstPath.filename().string();
            const auto inserted = wholeFileExportNames.emplace(fileName, file->path());
            if (!inserted.second)
            {
                const Utf8 because = std::format("duplicate exported API file name from '{}' and '{}'", inserted.first->second.string(), file->path().string());
                return reportInvalidFolder(ctx, dstPath, because);
            }

            wholeExports.push_back({file, std::move(dstPath), fileInfo.hasModuleNamespace});
        }

        // Build + write each whole-file export in parallel (each targets a distinct file).
        std::vector wholeExportResults(wholeExports.size(), Result::Continue);
        jobMgr.parallelForIndexed(ctx, static_cast<uint32_t>(wholeExports.size()), JobKind::ModuleApiExport, compiler.jobClientId(), [&](TaskContext& workerCtx, uint32_t i) {
            const WholeFileExport& we      = wholeExports[i];
            const Utf8             content = buildExportedModuleApiContent(*we.file, moduleNamespace.view(), we.hasModuleNamespace);
            wholeExportResults[i]          = writeModuleApiFile(workerCtx, we.dstPath, content.view());
        });
        for (const Result r : wholeExportResults)
            if (r != Result::Continue)
                return Result::Error;

        if (!firstSourceFile)
            return Result::Continue;

        SWC_RESULT(writeGeneratedModuleImports(ctx, exportApiDir, preferredLineEnding(*firstSourceFile)));
        if (generatedRoots.empty())
            return Result::Continue;

        sortGeneratedModuleApiRoots(ctx, generatedRoots);

        const fs::path generatedDstPath  = buildGeneratedModuleApiPath(compiler, exportApiDir);
        const Utf8     generatedFileName = generatedDstPath.filename().string();
        if (const auto it = wholeFileExportNames.find(generatedFileName); it != wholeFileExportNames.end())
        {
            const Utf8 because = std::format("generated module API file name '{}' conflicts with exported file '{}'", generatedFileName.c_str(), it->second.string());
            return reportInvalidFolder(ctx, generatedDstPath, because);
        }

        Utf8 content;
        SWC_RESULT(buildGeneratedModuleApiSingleFileContent(ctx, generatedRoots, moduleNamespace.view(), preferredLineEnding(*firstSourceFile), content));
        if (writeModuleApiFile(ctx, generatedDstPath, content.view()) != Result::Continue)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
