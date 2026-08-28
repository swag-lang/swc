#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/ModuleApi/ModuleApi.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Main/Version.h"
#include "Main/WorkspaceLayout.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Sha256.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedLog.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void ownBuildCfgString(Runtime::String& value, std::vector<std::unique_ptr<Utf8>>& ownedStrings)
    {
        if (!value.ptr || !value.length)
        {
            value = {};
            return;
        }

        auto owned   = std::make_unique<Utf8>(value);
        value.ptr    = owned->data();
        value.length = owned->size();
        ownedStrings.push_back(std::move(owned));
    }

    size_t pathNativeLength(const fs::path& path)
    {
        return path.native().size();
    }

    void reapplyBuildCfgPresetOverrides(Runtime::BuildCfg& buildCfg, const Runtime::BuildCfg& explicitBuildCfg)
    {
        buildCfg.safetyGuards               = explicitBuildCfg.safetyGuards;
        buildCfg.sanityGuards               = explicitBuildCfg.sanityGuards;
        buildCfg.allocatorCaptureStack      = explicitBuildCfg.allocatorCaptureStack;
        buildCfg.allocatorLeaks             = explicitBuildCfg.allocatorLeaks;
        buildCfg.allocatorTrackAllocations  = explicitBuildCfg.allocatorTrackAllocations;
        buildCfg.allocatorElectricMode      = explicitBuildCfg.allocatorElectricMode;
        buildCfg.allocatorFillMemory        = explicitBuildCfg.allocatorFillMemory;
        buildCfg.errorStackTrace            = explicitBuildCfg.errorStackTrace;
        buildCfg.backend.optimize           = explicitBuildCfg.backend.optimize;
        buildCfg.backend.vectorize          = explicitBuildCfg.backend.vectorize;
        buildCfg.backend.inlineMode         = explicitBuildCfg.backend.inlineMode;
        buildCfg.backend.debugInfo          = explicitBuildCfg.backend.debugInfo;
        buildCfg.backend.fpMathFma          = explicitBuildCfg.backend.fpMathFma;
        buildCfg.backend.fpMathNoNaN        = explicitBuildCfg.backend.fpMathNoNaN;
        buildCfg.backend.fpMathNoInf        = explicitBuildCfg.backend.fpMathNoInf;
        buildCfg.backend.fpMathNoSignedZero = explicitBuildCfg.backend.fpMathNoSignedZero;
    }

    void reapplyExplicitBuildCfgOverrides(Runtime::BuildCfg& buildCfg, const CommandLine& cmdLine)
    {
        if (cmdLine.buildCfgExplicit)
            reapplyBuildCfgPresetOverrides(buildCfg, cmdLine.defaultBuildCfg);

        buildCfg.backendKind = effectiveBackendKind(cmdLine, buildCfg.backendKind);
        if (cmdLine.backendOptimize.has_value())
            buildCfg.backend.optimize = cmdLine.backendOptimize.value();
        if (cmdLine.debugInfo)
            buildCfg.backend.debugInfo = true;

        if (cmdLine.artifactNameExplicit)
            buildCfg.name = cmdLine.defaultBuildCfg.name;
        if (cmdLine.moduleNamespaceExplicit)
            buildCfg.moduleNamespace = cmdLine.defaultBuildCfg.moduleNamespace;
        if (cmdLine.outDirExplicit)
            buildCfg.outDir = cmdLine.defaultBuildCfg.outDir;
        if (cmdLine.workDirExplicit)
            buildCfg.workDir = cmdLine.defaultBuildCfg.workDir;
    }

    void ownBuildCfgStrings(Runtime::BuildCfg& buildCfg, std::vector<std::unique_ptr<Utf8>>& ownedStrings)
    {
        std::vector<std::unique_ptr<Utf8>> newOwnedStrings;

        ownBuildCfgString(buildCfg.moduleNamespace, newOwnedStrings);
        ownBuildCfgString(buildCfg.warnings.asErrors, newOwnedStrings);
        ownBuildCfgString(buildCfg.warnings.asWarnings, newOwnedStrings);
        ownBuildCfgString(buildCfg.warnings.disabled, newOwnedStrings);
        ownBuildCfgString(buildCfg.name, newOwnedStrings);
        ownBuildCfgString(buildCfg.outDir, newOwnedStrings);
        ownBuildCfgString(buildCfg.workDir, newOwnedStrings);
        ownBuildCfgString(buildCfg.repoPath, newOwnedStrings);
        ownBuildCfgString(buildCfg.resAppIcoFileName, newOwnedStrings);
        ownBuildCfgString(buildCfg.resAppName, newOwnedStrings);
        ownBuildCfgString(buildCfg.resAppDescription, newOwnedStrings);
        ownBuildCfgString(buildCfg.resAppCompany, newOwnedStrings);
        ownBuildCfgString(buildCfg.resAppCopyright, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.outputName, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.titleToc, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.titleContent, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.css, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.icon, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.morePages, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteIconNote, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteIconTip, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteIconWarning, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteIconAttention, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteIconExample, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteTitleNote, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteTitleTip, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteTitleWarning, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteTitleAttention, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.quoteTitleExample, newOwnedStrings);
        ownBuildCfgString(buildCfg.registeredConfigs, newOwnedStrings);
        ownedStrings.swap(newOwnedStrings);
    }

    Utf8 buildModuleNamespaceName(const CompilerInstance& compiler)
    {
        Utf8                   moduleNamespaceName;
        const Runtime::String& moduleNamespace = compiler.buildCfg().moduleNamespace;
        if (moduleNamespace.ptr && moduleNamespace.length)
            moduleNamespaceName = Utf8{moduleNamespace};
        if (!moduleNamespaceName.empty())
            return moduleNamespaceName;

        Utf8                   artifactName;
        const Runtime::String& artifact = compiler.buildCfg().name;
        if (artifact.ptr && artifact.length)
            artifactName = Utf8{artifact};
        if (artifactName.empty())
            artifactName = defaultArtifactName(compiler.cmdLine());
        return defaultModuleNamespace(artifactName);
    }

    fs::path workspaceModulesDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / "modules").lexically_normal();
    }

    fs::path workspaceModuleDirectory(const fs::path& workspacePath, std::string_view moduleName)
    {
        return (workspaceModulesDirectory(workspacePath) / fs::path(std::string(moduleName))).lexically_normal();
    }

    fs::path workspaceModuleOutputDirectory(const fs::path& workspacePath, const Utf8& moduleName, const CommandLine& cmdLine, const Runtime::BuildCfgBackendKind backendKind, const bool workDirectory)
    {
        fs::path result = workDirectory ? WorkspaceLayout::workspaceWorkDirectory(workspacePath) : WorkspaceLayout::workspaceOutputDirectory(workspacePath);
        result /= fs::path(moduleName.c_str());
        if (cmdLine.command == CommandKind::Test && backendKind == Runtime::BuildCfgBackendKind::Executable)
            result /= "test";
        else
            result /= fs::path(backendKindName(backendKind).c_str());
        result /= fs::path(cmdLine.buildCfg.c_str());
        result /= fs::path(targetArchName(cmdLine.targetArch).c_str());
        return result.lexically_normal();
    }

    fs::path dependencyModuleDirectory(const fs::path& dependencyRoot, std::string_view moduleName)
    {
        return (dependencyRoot / fs::path(std::string(moduleName))).lexically_normal();
    }

    Result reportInvalidFolder(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    // Answers where the standard library workspace lives.
    //
    // A standard library sitting beside the compiler wins, and `SWAG_PATH` answers only for a
    // compiler installed without one. A compiler and its library are built together and are one
    // thing: `collectFiles` already takes `runtime` from the compiler's own directory
    // unconditionally, so taking `std` from anywhere else pairs one checkout's runtime with
    // another checkout's library. That is what a second working tree hits — `SWAG_PATH` still
    // names the first one — and it fails as an unknown symbol in a library that looks present.
    //
    // It is also what lets a fresh checkout run `bin\swc.exe tools\setup.swgs`, the script that
    // sets `SWAG_PATH` in the first place, before anything has been configured.
    Result resolveSwagStdWorkspaceRoot(fs::path& outRoot, TaskContext& ctx)
    {
        outRoot = (FileSystem::compilerResourceRoot(Os::getExeFullName()) / "std").lexically_normal();

        std::error_code ec;
        if (fs::is_directory(outRoot, ec))
            return Result::Continue;

        outRoot.clear();
        const std::optional<Utf8> installRoot = Os::readEnvironmentVariable("SWAG_PATH");
        if (!installRoot.has_value() || installRoot->empty())
            return reportInvalidFolder(ctx, "SWAG_PATH", "environment variable is not defined, and no standard library sits beside the compiler");

        outRoot = fs::path(installRoot->c_str());
        SWC_RESULT(FileSystem::resolveFolder(ctx, outRoot));
        outRoot = (outRoot / "std").lexically_normal();
        return Result::Continue;
    }

    Result resolveSwagStdOutputRoot(fs::path& outRoot, TaskContext& ctx)
    {
        SWC_RESULT(resolveSwagStdWorkspaceRoot(outRoot, ctx));
        outRoot = (outRoot / ".output").lexically_normal();
        return Result::Continue;
    }

    Result reportWorkspaceDependencySyncFailure(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_dependency_sync_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, FileSystem::appendFileUsers(because, path));
        diag.report(ctx);
        return Result::Error;
    }

    bool pathIsCurrentOrParentDirectory(const fs::path& path)
    {
        return path == "." || path == "..";
    }

    Utf8 describeStatAnswer(const std::string_view what, const std::error_code& ec)
    {
        return std::format("{} answered '{}' (code {})", what, FileSystem::normalizeSystemMessage(ec).c_str(), ec.value());
    }

    // Answers whether the mirror at `dstPath` has to be refreshed from `srcPath`, and fills
    // `outReason` with the check that asked for the copy. The reason is kept because a copy can
    // later prove needless — the replace in copyWorkspaceDependencyFile loses its race while the
    // destination matches the source anyway — and by then these stats cannot be replayed.
    bool shouldCopyWorkspaceDependencyFile(Utf8& outReason, const fs::path& srcPath, const fs::path& dstPath)
    {
        outReason.clear();

        std::error_code ec;
        const bool      dstExists = fs::exists(dstPath, ec);
        if (ec)
        {
            outReason = describeStatAnswer("testing the destination presence", ec);
            return true;
        }

        if (!dstExists)
        {
            outReason = "the destination does not exist";
            return true;
        }

        ec.clear();
        const bool dstRegular = fs::is_regular_file(dstPath, ec);
        if (ec)
        {
            outReason = describeStatAnswer("testing the destination kind", ec);
            return true;
        }

        if (!dstRegular)
        {
            outReason = "the destination is not a regular file";
            return true;
        }

        ec.clear();
        const uintmax_t srcSize = fs::file_size(srcPath, ec);
        if (ec)
        {
            outReason = describeStatAnswer("reading the source size", ec);
            return true;
        }

        ec.clear();
        const uintmax_t dstSize = fs::file_size(dstPath, ec);
        if (ec)
        {
            outReason = describeStatAnswer("reading the destination size", ec);
            return true;
        }

        if (srcSize != dstSize)
        {
            outReason = std::format("sizes differ (source {}, destination {})", srcSize, dstSize);
            return true;
        }

        ec.clear();
        const auto srcTime = fs::last_write_time(srcPath, ec);
        if (ec)
        {
            outReason = describeStatAnswer("reading the source time", ec);
            return true;
        }

        ec.clear();
        const auto dstTime = fs::last_write_time(dstPath, ec);
        if (ec)
        {
            outReason = describeStatAnswer("reading the destination time", ec);
            return true;
        }

        // Matching size and modification time is a strong, cheap signal that the file is unchanged
        // (the sync copies preserve the source mtime, so an unchanged dependency reproduces it
        // exactly). Reading both files in full just to byte-compare them on every run defeats the
        // purpose of the timestamp check and dominated script-mode setup time, so trust it here.
        if (srcTime == dstTime)
            return false;

        outReason = std::format("modification times differ (source {}, destination {})", srcTime.time_since_epoch().count(), dstTime.time_since_epoch().count());
        return true;
    }

    Result ensureWorkspaceDependencyDirectory(TaskContext& ctx, std::unordered_set<fs::path>& ensuredDirs, const fs::path& dir)
    {
        if (dir.empty())
            return Result::Continue;

        const fs::path normalizedDir = dir.lexically_normal();
        if (!ensuredDirs.insert(normalizedDir).second)
            return Result::Continue;

        std::error_code ec;
        fs::create_directories(normalizedDir, ec);
        if (ec)
            return reportWorkspaceDependencySyncFailure(ctx, normalizedDir, FileSystem::normalizeSystemMessage(ec));

        return Result::Continue;
    }

    bool tryFindDependencyArtifactStem(Utf8& outStem, const fs::path& dir, std::string_view preferredStem, std::string_view extension)
    {
        outStem.clear();
        if (dir.empty())
            return false;

        Utf8 preferredStemKey = preferredStem;
        preferredStemKey.make_lower();

        std::vector<Utf8> candidates;
        std::error_code   ec;
        for (fs::directory_iterator it(dir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return false;

            ec.clear();
            if (!it->is_regular_file(ec) || ec)
                continue;
            if (it->path().extension() != extension)
                continue;

            Utf8 candidate = it->path().stem().string();
            if (candidate.empty())
                continue;

            Utf8 candidateKey = candidate;
            candidateKey.make_lower();
            if (candidateKey == preferredStemKey)
            {
                outStem = std::move(candidate);
                return true;
            }

            candidates.push_back(std::move(candidate));
        }

        if (candidates.size() != 1)
            return false;

        outStem = std::move(candidates.front());
        return true;
    }

    Utf8 resolveDependencyLinkModuleName(const fs::path& linkDir, const std::string_view fallbackStem)
    {
        Utf8 result;
        if (tryFindDependencyArtifactStem(result, linkDir, fallbackStem, ".lib"))
            return result;
        if (tryFindDependencyArtifactStem(result, linkDir, fallbackStem, ".dll"))
            return result;
        return Utf8{fallbackStem};
    }

    // Extension of a dependency copy still being written. It belongs to the process whose id it
    // carries, so every other process leaves it alone: pruning one would break the rename it is
    // waiting for. One survives only a compiler killed mid-copy, and '--rebuild' or `swc clean`
    // takes it from there.
    constexpr std::string_view K_WORKSPACE_DEPENDENCY_TEMP_EXTENSION = ".swctmp";

    bool isWorkspaceDependencyTempPath(const fs::path& path)
    {
        return path.extension() == K_WORKSPACE_DEPENDENCY_TEMP_EXTENSION;
    }

    // Copies one dependency file so that the destination path never names a partial one.
    //
    // Two compilers can mirror the same dependency at the same time — two scripts sharing a set of
    // imports share their mirror — and a reader of a half-written file has no way to tell. So the
    // copy lands beside its destination under a name only this process uses, takes the source
    // modification time there (it is what the next run compares), and is moved into place by a
    // rename, which either happened or did not.
    Result copyWorkspaceDependencyFile(TaskContext& ctx, const fs::path& srcPath, const fs::path& dstPath, const Utf8& copyReason)
    {
        fs::path tempPath = dstPath;
        tempPath += std::format(".{}{}", Os::currentProcessId(), K_WORKSPACE_DEPENDENCY_TEMP_EXTENSION);

        std::error_code ec;
        fs::copy_file(srcPath, tempPath, fs::copy_options::overwrite_existing, ec);
        if (ec)
            return reportWorkspaceDependencySyncFailure(ctx, tempPath, FileSystem::normalizeSystemMessage(ec));

        ec.clear();
        const auto srcTime = fs::last_write_time(srcPath, ec);
        if (!ec)
        {
            ec.clear();
            fs::last_write_time(tempPath, srcTime, ec);
        }

        if (!ec)
        {
            ec.clear();
            fs::rename(tempPath, dstPath, ec);
        }

        if (ec)
        {
            std::error_code removeEc;
            fs::remove(tempPath, removeEc);

            // The replace can lose a race it did not need to win. This process maps the previous
            // copy for JIT execution while a background link still reads beside it, and the copy
            // being installed may carry the very bytes the destination already holds. A mirror
            // whose destination matches the source is correct however the rename fared, so only
            // a real difference is worth an error.
            Utf8 recheckReason;
            if (!shouldCopyWorkspaceDependencyFile(recheckReason, srcPath, dstPath))
            {
                // The needless copy is harmless, but it is also the whole mystery: the compare
                // had matched this very pair moments before it asked for the copy, and neither
                // answer can be replayed post-mortem. So the trace is written now, where the
                // race actually happened.
                Logger::printDim(ctx, std::format("[sync] '{}' was mirrored while it already matched its source; the copy fired because {}; the replace answered '{}'\n", Utf8(dstPath).c_str(), copyReason.c_str(), FileSystem::normalizeSystemMessage(ec).c_str()));
                return Result::Continue;
            }

            return reportWorkspaceDependencySyncFailure(ctx, dstPath, FileSystem::normalizeSystemMessage(ec));
        }

        return Result::Continue;
    }

    Result syncWorkspaceDependencyDirectory(TaskContext& ctx, const fs::path& srcDir, const fs::path& dstDir)
    {
        if (srcDir.empty() || dstDir.empty())
            return Result::Continue;

        const fs::path normalizedSrcDir = FileSystem::normalizePath(srcDir);
        const fs::path normalizedDstDir = FileSystem::normalizePath(dstDir);
        if (FileSystem::pathEquals(normalizedSrcDir, normalizedDstDir))
            return Result::Continue;

        Utf8     because;
        fs::path resolvedSrcDir = normalizedSrcDir;
        if (FileSystem::resolveExistingFolder(resolvedSrcDir, because) != Result::Continue)
            return reportWorkspaceDependencySyncFailure(ctx, resolvedSrcDir, because);

        std::error_code              ec;
        std::unordered_set<fs::path> ensuredDirs;
        SWC_RESULT(ensureWorkspaceDependencyDirectory(ctx, ensuredDirs, normalizedDstDir));

        for (fs::recursive_directory_iterator it(resolvedSrcDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return reportWorkspaceDependencySyncFailure(ctx, resolvedSrcDir, FileSystem::normalizeSystemMessage(ec));

            const fs::path relativePath = it->path().lexically_relative(resolvedSrcDir);
            if (relativePath.empty())
                continue;

            fs::path dstPath = (normalizedDstDir / relativePath).lexically_normal();
            ec.clear();
            if (it->is_directory(ec))
            {
                SWC_RESULT(ensureWorkspaceDependencyDirectory(ctx, ensuredDirs, dstPath));
                continue;
            }

            if (ec)
                return reportWorkspaceDependencySyncFailure(ctx, it->path(), FileSystem::normalizeSystemMessage(ec));

            ec.clear();
            if (!it->is_regular_file(ec))
            {
                if (ec)
                    return reportWorkspaceDependencySyncFailure(ctx, it->path(), FileSystem::normalizeSystemMessage(ec));
                continue;
            }

            Utf8 copyReason;
            if (!shouldCopyWorkspaceDependencyFile(copyReason, it->path(), dstPath))
                continue;

            const fs::path dstParent = dstPath.parent_path();
            if (!dstParent.empty())
                SWC_RESULT(ensureWorkspaceDependencyDirectory(ctx, ensuredDirs, dstParent));

            SWC_RESULT(copyWorkspaceDependencyFile(ctx, it->path(), dstPath, copyReason));
        }

        std::vector<fs::path> stalePaths;
        for (fs::recursive_directory_iterator it(normalizedDstDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return reportWorkspaceDependencySyncFailure(ctx, normalizedDstDir, FileSystem::normalizeSystemMessage(ec));

            const fs::path relativePath = it->path().lexically_relative(normalizedDstDir);
            if (relativePath.empty() || pathIsCurrentOrParentDirectory(relativePath))
                continue;
            if (isWorkspaceDependencyTempPath(it->path()))
                continue;

            const fs::path srcPath = (resolvedSrcDir / relativePath).lexically_normal();
            ec.clear();
            if (!fs::exists(srcPath, ec))
            {
                if (ec)
                    return reportWorkspaceDependencySyncFailure(ctx, srcPath, FileSystem::normalizeSystemMessage(ec));
                stalePaths.push_back(it->path());
            }
        }

        std::ranges::sort(stalePaths, std::ranges::greater{}, pathNativeLength);
        stalePaths.erase(std::ranges::unique(stalePaths).begin(), stalePaths.end());
        for (const fs::path& stalePath : stalePaths)
        {
            ec.clear();
            fs::remove_all(stalePath, ec);
            if (ec)
                return reportWorkspaceDependencySyncFailure(ctx, stalePath, FileSystem::normalizeSystemMessage(ec));
        }

        return Result::Continue;
    }

    Utf8 dependencyConfigurationLabel(const CommandLine& cmdLine)
    {
        return std::format("build-cfg '{}' and arch '{}'", cmdLine.buildCfg.c_str(), targetArchName(cmdLine.targetArch).c_str());
    }

    struct DependencyConfigCandidate
    {
        fs::path                     path;
        Runtime::BuildCfgBackendKind backendKind = Runtime::BuildCfgBackendKind::None;
    };

    Runtime::BuildCfgBackendKind dependencyBackendKindFromFolderName(const std::string_view name)
    {
        if (name == backendKindName(Runtime::BuildCfgBackendKind::Executable).view())
            return Runtime::BuildCfgBackendKind::Executable;
        if (name == backendKindName(Runtime::BuildCfgBackendKind::SharedLibrary).view())
            return Runtime::BuildCfgBackendKind::SharedLibrary;
        if (name == backendKindName(Runtime::BuildCfgBackendKind::StaticLibrary).view())
            return Runtime::BuildCfgBackendKind::StaticLibrary;
        if (name == backendKindName(Runtime::BuildCfgBackendKind::Export).view())
            return Runtime::BuildCfgBackendKind::Export;
        return Runtime::BuildCfgBackendKind::None;
    }

    bool isSharedDependencyBackendKind(const Runtime::BuildCfgBackendKind backendKind)
    {
        return backendKind == Runtime::BuildCfgBackendKind::SharedLibrary;
    }

    bool isStaticDependencyBackendKind(const Runtime::BuildCfgBackendKind backendKind)
    {
        return backendKind == Runtime::BuildCfgBackendKind::StaticLibrary;
    }

    bool isImportOnlyDependencyBackendKind(const Runtime::BuildCfgBackendKind backendKind)
    {
        return backendKind == Runtime::BuildCfgBackendKind::Export;
    }

    Utf8 joinDependencyPaths(const std::vector<fs::path>& paths)
    {
        Utf8 result;
        for (const fs::path& path : paths)
        {
            if (!result.empty())
                result += ", ";
            result += Utf8(path);
        }

        return result;
    }

    bool selectUniqueDependencyConfigMatch(fs::path& outPath, Runtime::BuildCfgBackendKind& outBackendKind, std::span<const DependencyConfigCandidate> matches, bool (*predicate)(Runtime::BuildCfgBackendKind))
    {
        outPath.clear();
        outBackendKind = Runtime::BuildCfgBackendKind::None;

        for (const DependencyConfigCandidate& match : matches)
        {
            if (!predicate(match.backendKind))
                continue;

            if (outPath.empty())
            {
                outPath        = match.path;
                outBackendKind = match.backendKind;
                continue;
            }

            outPath.clear();
            outBackendKind = Runtime::BuildCfgBackendKind::None;
            return false;
        }

        return !outPath.empty();
    }

    Result collectDependencyConfigurationMatches(std::vector<DependencyConfigCandidate>& outMatches, Utf8& outBecause, const fs::path& dependencyRoot, std::string_view moduleName, const CommandLine& cmdLine)
    {
        outMatches.clear();
        outBecause.clear();

        const fs::path moduleDir         = dependencyModuleDirectory(dependencyRoot, moduleName);
        fs::path       resolvedModuleDir = moduleDir;
        if (FileSystem::resolveExistingFolder(resolvedModuleDir, outBecause) != Result::Continue)
            return Result::Error;

        const auto      buildCfgDir = fs::path(cmdLine.buildCfg.c_str());
        const auto      archDir     = fs::path(targetArchName(cmdLine.targetArch).c_str());
        std::error_code ec;
        for (fs::directory_iterator it(resolvedModuleDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
            {
                outBecause = FileSystem::normalizeSystemMessage(ec);
                return Result::Error;
            }

            ec.clear();
            if (!it->is_directory(ec) || ec)
                continue;

            fs::path candidate = (it->path() / buildCfgDir / archDir).lexically_normal();
            ec.clear();
            if (!fs::is_directory(candidate, ec) || ec)
                continue;

            outMatches.push_back({.path        = FileSystem::normalizePath(candidate),
                                  .backendKind = dependencyBackendKindFromFolderName(it->path().filename().string())});
        }

        if (outMatches.empty())
        {
            outBecause = std::format("no configuration folder matches {}", dependencyConfigurationLabel(cmdLine).c_str());
            return Result::Error;
        }

        std::ranges::sort(outMatches, {}, &DependencyConfigCandidate::path);
        outMatches.erase(std::ranges::unique(outMatches, {}, &DependencyConfigCandidate::path).begin(), outMatches.end());
        return Result::Continue;
    }

    Result findDependencyConfigurationDirectory(fs::path& outDir, Utf8& outBecause, const fs::path& dependencyRoot, std::string_view moduleName, const CommandLine& cmdLine, Runtime::BuildCfgBackendKind* outBackendKind = nullptr)
    {
        outDir.clear();
        if (outBackendKind)
            *outBackendKind = Runtime::BuildCfgBackendKind::None;

        std::vector<DependencyConfigCandidate> matches;
        SWC_RESULT(collectDependencyConfigurationMatches(matches, outBecause, dependencyRoot, moduleName, cmdLine));
        fs::path selectedPath;
        auto     selectedBackendKind = Runtime::BuildCfgBackendKind::None;
        if (selectUniqueDependencyConfigMatch(selectedPath, selectedBackendKind, matches, isSharedDependencyBackendKind))
        {
            if (outBackendKind)
                *outBackendKind = selectedBackendKind;
            outDir = std::move(selectedPath);
            return Result::Continue;
        }

        if (selectUniqueDependencyConfigMatch(selectedPath, selectedBackendKind, matches, isImportOnlyDependencyBackendKind))
        {
            if (outBackendKind)
                *outBackendKind = selectedBackendKind;
            outDir = std::move(selectedPath);
            return Result::Continue;
        }

        if (selectUniqueDependencyConfigMatch(selectedPath, selectedBackendKind, matches, isStaticDependencyBackendKind))
        {
            if (outBackendKind)
                *outBackendKind = selectedBackendKind;
            outDir = std::move(selectedPath);
            return Result::Continue;
        }

        if (matches.size() != 1)
        {
            std::vector<fs::path> paths;
            paths.reserve(matches.size());
            for (const DependencyConfigCandidate& match : matches)
                paths.push_back(match.path);

            outBecause = std::format("multiple configuration folders match {} ({})", dependencyConfigurationLabel(cmdLine).c_str(), joinDependencyPaths(paths).c_str());
            return Result::Error;
        }

        if (matches.front().backendKind == Runtime::BuildCfgBackendKind::Executable)
        {
            outBecause = std::format("no importable dependency backend matches {} (found executable output only)", dependencyConfigurationLabel(cmdLine).c_str());
            return Result::Error;
        }

        outDir = matches.front().path;
        if (outBackendKind)
            *outBackendKind = matches.front().backendKind;
        return Result::Continue;
    }

    Result findDependencyConfigurationDirectoryForBackend(fs::path& outDir, Utf8& outBecause, const fs::path& dependencyRoot, std::string_view moduleName, const CommandLine& cmdLine, const Runtime::BuildCfgBackendKind expectedBackendKind)
    {
        outDir.clear();

        std::vector<DependencyConfigCandidate> matches;
        SWC_RESULT(collectDependencyConfigurationMatches(matches, outBecause, dependencyRoot, moduleName, cmdLine));

        const auto it = std::ranges::find(matches, expectedBackendKind, &DependencyConfigCandidate::backendKind);
        if (it == matches.end())
        {
            outBecause = std::format("no '{}' dependency backend matches {}", backendKindName(expectedBackendKind).c_str(), dependencyConfigurationLabel(cmdLine).c_str());
            return Result::Error;
        }

        outDir = it->path;
        return Result::Continue;
    }

    fs::path dependencyRootFromConfigurationDir(const fs::path& configDir)
    {
        fs::path result = configDir;
        for (uint32_t i = 0; i < 4 && result.has_parent_path(); ++i)
            result = result.parent_path();
        return result.lexically_normal();
    }

    fs::path dependencyImportMetadataPath(const fs::path& apiDir)
    {
        return (apiDir / ".swc-deps").lexically_normal();
    }

    bool shouldSkipWorkspaceEntry(const fs::directory_entry& entry)
    {
        std::error_code ec;
        if (!entry.is_directory(ec) || ec)
            return true;

        const std::string name = entry.path().filename().string();
        return !name.empty() && name[0] == '.';
    }

    Utf8 formatWorkspaceStageStat(const TaskContext& ctx, const CompilerInstance::WorkspaceBuildLogState& workspaceLogState)
    {
        std::vector<Utf8> parts;
        if (ctx.cmdLine().workspaceDependencyBuild && workspaceLogState.builtModules == workspaceLogState.activeModules)
        {
            if (workspaceLogState.compiledModules)
                parts.push_back(ScopedTimedLog::formatStatCount(ctx, workspaceLogState.compiledModules, "module"));
            return ScopedTimedLog::joinStatItems(ctx, parts);
        }

        if (workspaceLogState.activeModules)
        {
            if (workspaceLogState.builtModules < workspaceLogState.activeModules)
                parts.push_back(ScopedTimedLog::formatStatRatio(ctx, workspaceLogState.builtModules, workspaceLogState.activeModules, "module"));
            else
                parts.push_back(ScopedTimedLog::formatStatCount(ctx, workspaceLogState.activeModules, "module"));
        }
        else if (workspaceLogState.discoveredModules)
        {
            parts.push_back(ScopedTimedLog::formatStatCount(ctx, workspaceLogState.discoveredModules, "module"));
        }

        return ScopedTimedLog::joinStatItems(ctx, parts);
    }

    Utf8 formatWorkspaceModuleStageStat(const TaskContext& ctx, const CompilerInstance& compiler, const ScopedTimedLog::StatsSnapshot& deltaSnapshot)
    {
        std::vector<Utf8> parts;
        if (deltaSnapshot.numFiles)
            parts.push_back(ScopedTimedLog::formatStatCount(ctx, deltaSnapshot.numFiles, "file"));

        if (ctx.cmdLine().command == CommandKind::Test)
            ScopedTimedLog::appendTestStats(ctx, parts, deltaSnapshot.numTests, deltaSnapshot.numTestsFailed);

        const Utf8& artifactLabel = compiler.lastArtifactLabel();
        if (!artifactLabel.empty())
            parts.push_back(ScopedTimedLog::formatStatName(ctx, artifactLabel));

        return ScopedTimedLog::joinStatItems(ctx, parts);
    }

    void collectSwagFilesRec(const CommandLine& cmdLine, const fs::path& folder, std::vector<fs::path>& files, const bool canFilter = true)
    {
        std::error_code ec;
        for (fs::recursive_directory_iterator it(folder, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
            {
                ec.clear();
                continue;
            }

            const fs::directory_entry& entry = *it;
            if (!entry.is_regular_file(ec))
            {
                ec.clear();
                continue;
            }

            const fs::path&   path = entry.path();
            const std::string ext  = path.extension().string();
            if (ext != ".swg" && ext != ".swgs")
                continue;

            if (canFilter && !cmdLine.fileFilter.empty())
            {
                const std::string pathString = path.string();
                bool              ignore     = false;
                for (const Utf8& filter : cmdLine.fileFilter)
                {
                    if (!pathString.contains(filter))
                    {
                        ignore = true;
                        break;
                    }
                }

                if (ignore)
                    continue;
            }

            files.push_back(path);
        }
    }

    constexpr std::string_view K_WORKSPACE_ARTIFACT_MANIFEST_FILE = ".swc-artifacts";

    struct WorkspaceArtifactManifest
    {
        std::vector<fs::path> inputs;
        std::vector<fs::path> dependencyDirs;
        std::vector<fs::path> artifacts;
        bool                  debugInfo = false;
    };

    // Each build mode keeps its own manifest, so alternating `test` and `run` does
    // not make each one look stale to the other and force a rebuild every time.
    fs::path workspaceArtifactManifestPath(const fs::path& outDir, const CommandLine& cmdLine)
    {
        return (outDir / std::format("{}{}", K_WORKSPACE_ARTIFACT_MANIFEST_FILE, artifactModeSuffix(cmdLine))).lexically_normal();
    }

    bool workspacePathIsArtifactManifest(const fs::path& path)
    {
        return path.filename().string().starts_with(K_WORKSPACE_ARTIFACT_MANIFEST_FILE);
    }

    void normalizeWorkspacePaths(std::vector<fs::path>& paths)
    {
        for (fs::path& path : paths)
            path = FileSystem::normalizePath(path);

        std::ranges::sort(paths, {}, [](const fs::path& path) { return path.native(); });
        paths.erase(std::ranges::unique(paths).begin(), paths.end());
    }

    void normalizeWorkspaceRelativePaths(std::vector<fs::path>& paths)
    {
        for (fs::path& path : paths)
            path = path.lexically_normal();

        std::ranges::sort(paths, {}, [](const fs::path& path) { return path.native(); });
        paths.erase(std::ranges::unique(paths).begin(), paths.end());
    }

    bool sameWorkspacePathList(std::span<const fs::path> lhs, std::span<const fs::path> rhs)
    {
        return lhs.size() == rhs.size() && std::ranges::equal(lhs, rhs);
    }

    bool workspacePathListContainsAll(std::span<const fs::path> paths, std::span<const fs::path> expectedPaths)
    {
        return std::ranges::includes(paths, expectedPaths, {}, [](const fs::path& path) { return path.native(); }, [](const fs::path& path) { return path.native(); });
    }

    bool tryGetWorkspacePathWriteTime(fs::file_time_type& outTime, const fs::path& path)
    {
        std::error_code ec;
        outTime = fs::last_write_time(path, ec);
        return !ec;
    }

    bool tryCollectLatestWorkspaceTreeWriteTime(fs::file_time_type& outTime, const fs::path& root)
    {
        if (!tryGetWorkspacePathWriteTime(outTime, root))
            return false;

        std::error_code ec;
        for (fs::recursive_directory_iterator it(root, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return false;

            fs::file_time_type entryTime;
            if (!tryGetWorkspacePathWriteTime(entryTime, it->path()))
                return false;
            if (entryTime > outTime)
                outTime = entryTime;
        }

        return true;
    }

    bool tryGetWorkspaceDependencyBuildTime(fs::file_time_type& outTime, const fs::path& dependencyDir, const fs::path& consumerManifestPath)
    {
        // A dependency output directory can hold normal and test artifacts side by side. Use the
        // manifest for the consuming mode so rebuilding one mode does not invalidate the other.
        const fs::path dependencyManifestPath = dependencyDir / consumerManifestPath.filename();
        if (tryGetWorkspacePathWriteTime(outTime, dependencyManifestPath))
            return true;

        // Published or hand-copied dependencies have no manifest; their newest entry is the only
        // build date available.
        return tryCollectLatestWorkspaceTreeWriteTime(outTime, dependencyDir);
    }

    // Dates the compiler that is about to consume a build.
    //
    // The embedded runtime sources (<resource root>/runtime/*.swg) are compiled into every
    // module, so a change there must invalidate a build exactly like a new compiler binary.
    bool tryGetCompilerBuildTime(fs::file_time_type& outTime, const fs::path& compilerPath)
    {
        if (!tryGetWorkspacePathWriteTime(outTime, compilerPath))
            return false;

        fs::file_time_type runtimeTime{};
        if (!tryCollectLatestWorkspaceTreeWriteTime(runtimeTime, FileSystem::compilerResourceRoot(compilerPath) / "runtime"))
            return false;

        outTime = std::max(outTime, runtimeTime);
        return true;
    }

    void appendWorkspaceInputFiles(std::vector<fs::path>& outInputs, const std::set<fs::path>& inputFiles)
    {
        outInputs.reserve(outInputs.size() + inputFiles.size());
        for (const fs::path& filePath : inputFiles)
            outInputs.push_back(filePath);
    }

    void collectWorkspaceModuleInputs(std::vector<fs::path>& outInputs, const CommandLine& cmdLine, const fs::path& moduleFile, const fs::path& sourceDir, const std::set<fs::path>& loadedFiles, const std::set<fs::path>& setupCompilerInputFiles, const std::set<fs::path>& buildCompilerInputFiles)
    {
        outInputs.clear();
        if (!moduleFile.empty())
            outInputs.push_back(moduleFile);

        if (!sourceDir.empty())
            collectSwagFilesRec(cmdLine, sourceDir, outInputs, true);

        appendWorkspaceInputFiles(outInputs, loadedFiles);
        appendWorkspaceInputFiles(outInputs, setupCompilerInputFiles);
        appendWorkspaceInputFiles(outInputs, buildCompilerInputFiles);

        normalizeWorkspacePaths(outInputs);
    }

    void collectWorkspaceOutputArtifacts(std::vector<fs::path>& outArtifacts, const fs::path& outDir)
    {
        outArtifacts.clear();
        if (outDir.empty())
            return;

        std::error_code ec;
        for (fs::recursive_directory_iterator it(outDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return;

            ec.clear();
            if (!it->is_regular_file(ec) || ec)
                continue;

            const fs::path normalizedPath = FileSystem::normalizePath(it->path());

            // Skip every mode's manifest, not just this one: a manifest that listed
            // another manifest would go stale the moment that mode was rebuilt.
            if (workspacePathIsArtifactManifest(normalizedPath))
                continue;

            fs::path relativePath = normalizedPath.lexically_relative(outDir);
            if (relativePath.empty())
                relativePath = normalizedPath.filename();
            outArtifacts.push_back(relativePath.lexically_normal());
        }

        normalizeWorkspaceRelativePaths(outArtifacts);
    }

    bool readWorkspaceArtifactManifest(WorkspaceArtifactManifest& outManifest, const fs::path& manifestPath)
    {
        outManifest = {};

        FileSystem::IoErrorInfo ioError;
        std::string             content;
        if (FileSystem::readTextFile(manifestPath, content, ioError) != Result::Continue)
            return false;

        enum class Section : uint8_t
        {
            None,
            Inputs,
            Dependencies,
            Artifacts,
        };

        auto   currentSection = Section::None;
        bool   validVersion   = false;
        bool   hasDebugInfo   = false;
        size_t start          = 0;
        while (start <= content.size())
        {
            size_t end = content.find('\n', start);
            if (end == std::string::npos)
                end = content.size();

            std::string_view line(content.data() + start, end - start);
            if (!line.empty() && line.back() == '\r')
                line.remove_suffix(1);

            if (line.empty())
            {
                if (end == content.size())
                    break;
                start = end + 1;
                continue;
            }

            if (line == "version=3")
            {
                validVersion = true;
                if (end == content.size())
                    break;
                start = end + 1;
                continue;
            }

            if (line == "debug-info=0" || line == "debug-info=1")
            {
                outManifest.debugInfo = line.back() == '1';
                hasDebugInfo           = true;
                if (end == content.size())
                    break;
                start = end + 1;
                continue;
            }

            if (line == "[inputs]")
                currentSection = Section::Inputs;
            else if (line == "[dependencies]")
                currentSection = Section::Dependencies;
            else if (line == "[artifacts]")
                currentSection = Section::Artifacts;
            else
            {
                if (currentSection == Section::None)
                    return false;

                fs::path parsedPath{std::string(line)};
                switch (currentSection)
                {
                    case Section::Inputs:
                        outManifest.inputs.push_back(std::move(parsedPath));
                        break;
                    case Section::Dependencies:
                        outManifest.dependencyDirs.push_back(std::move(parsedPath));
                        break;
                    case Section::Artifacts:
                        outManifest.artifacts.push_back(std::move(parsedPath));
                        break;
                    case Section::None:
                        break;
                }
            }

            if (end == content.size())
                break;
            start = end + 1;
        }

        normalizeWorkspacePaths(outManifest.inputs);
        normalizeWorkspacePaths(outManifest.dependencyDirs);
        normalizeWorkspaceRelativePaths(outManifest.artifacts);
        return validVersion && hasDebugInfo;
    }

    Result writeWorkspaceArtifactManifest(TaskContext& ctx, const WorkspaceArtifactManifest& manifest, const fs::path& manifestPath)
    {
        Utf8 content = std::format("version=3\ndebug-info={}\n[inputs]\n", manifest.debugInfo ? 1 : 0);
        for (const fs::path& path : manifest.inputs)
        {
            content += Utf8(path);
            content += '\n';
        }

        content += "[dependencies]\n";
        for (const fs::path& path : manifest.dependencyDirs)
        {
            content += Utf8(path);
            content += '\n';
        }

        content += "[artifacts]\n";
        for (const fs::path& path : manifest.artifacts)
        {
            content += Utf8(path);
            content += '\n';
        }

        std::error_code ec;
        fs::create_directories(manifestPath.parent_path(), ec);
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_file_write_failed);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, manifestPath, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return Result::Error;
        }

        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(manifestPath, content.data(), content.size(), ioError) == Result::Continue)
            return Result::Continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_file_write_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, manifestPath, FileSystem::describeIoFailure(ioError));
        diag.report(ctx);
        return Result::Error;
    }

    bool workspaceManifestContainsArtifact(const WorkspaceArtifactManifest& manifest, const fs::path& outDir, const fs::path& artifactPath)
    {
        const fs::path normalizedArtifactPath = FileSystem::normalizePath(artifactPath);
        for (const fs::path& relativePath : manifest.artifacts)
        {
            if (FileSystem::pathEquals(FileSystem::normalizePath(outDir / relativePath), normalizedArtifactPath))
                return true;
        }

        return false;
    }

    bool workspaceArtifactsAreUpToDate(const WorkspaceArtifactManifest& manifest, const fs::path& outDir, const fs::path& manifestPath, const fs::path& compilerPath, const std::span<const fs::path> currentInputs, const std::span<const fs::path> currentDependencyDirs, const std::span<const fs::path> requiredArtifacts, const bool debugInfo)
    {
        if (manifest.debugInfo != debugInfo)
            return false;
        if (!workspacePathListContainsAll(manifest.inputs, currentInputs))
            return false;
        if (!sameWorkspacePathList(manifest.dependencyDirs, currentDependencyDirs))
            return false;

        fs::file_time_type latestInputTime{};
        bool               hasInputTime = false;
        for (const fs::path& path : manifest.inputs)
        {
            fs::file_time_type pathTime;
            if (!tryGetWorkspacePathWriteTime(pathTime, path))
                return false;
            if (!hasInputTime || pathTime > latestInputTime)
            {
                latestInputTime = pathTime;
                hasInputTime    = true;
            }
        }

        fs::file_time_type compilerTime{};
        if (!tryGetCompilerBuildTime(compilerTime, compilerPath))
            return false;

        fs::file_time_type latestDependencyTime{};
        bool               hasDependencyTime = false;
        for (const fs::path& dependencyDir : currentDependencyDirs)
        {
            fs::file_time_type dependencyTime;
            if (!tryGetWorkspaceDependencyBuildTime(dependencyTime, dependencyDir, manifestPath))
                return false;
            if (!hasDependencyTime || dependencyTime > latestDependencyTime)
            {
                latestDependencyTime = dependencyTime;
                hasDependencyTime    = true;
            }
        }

        std::vector<fs::path> absoluteArtifactPaths;
        absoluteArtifactPaths.reserve(manifest.artifacts.size() + requiredArtifacts.size());
        for (const fs::path& relativeArtifactPath : manifest.artifacts)
        {
            absoluteArtifactPaths.push_back((outDir / relativeArtifactPath).lexically_normal());
        }

        for (const fs::path& artifactPath : requiredArtifacts)
            absoluteArtifactPaths.push_back(artifactPath);

        normalizeWorkspacePaths(absoluteArtifactPaths);

        // Every recorded artifact must still exist, but we deliberately do not use the
        // earliest artifact mtime as the build timestamp. Some artifacts (notably the
        // linker-generated import library) are preserved as-is across rebuilds when their
        // contents are unchanged, so their mtime lags far behind the actual build. Using
        // that lagging mtime would make the module appear permanently stale.
        for (const fs::path& artifactPath : absoluteArtifactPaths)
        {
            fs::file_time_type artifactTime;
            if (!tryGetWorkspacePathWriteTime(artifactTime, artifactPath))
                return false;
        }

        // The manifest is rewritten at the end of every successful build, so its write time
        // reliably reflects when this module was last produced by the compiler.
        fs::file_time_type buildTime{};
        if (!tryGetWorkspacePathWriteTime(buildTime, manifestPath))
            return false;

        // Backstop for an artifact replaced behind the compiler's back. Build modes no
        // longer share an artifact name, so this no longer covers test-versus-run.
        for (const fs::path& artifactPath : requiredArtifacts)
        {
            fs::file_time_type artifactTime;
            if (!tryGetWorkspacePathWriteTime(artifactTime, artifactPath) || artifactTime > buildTime)
                return false;
        }

        if (hasInputTime && buildTime < latestInputTime)
            return false;
        if (hasDependencyTime && buildTime < latestDependencyTime)
            return false;
        return buildTime >= compilerTime;
    }

    bool shouldTryReuseWorkspaceArtifacts(const CommandLine& cmdLine)
    {
        if (cmdLine.rebuild || cmdLine.dryRun || cmdLine.showConfig)
            return false;

        if (cmdLine.command == CommandKind::Test)
        {
            // A focused executable contains only the selected #test entry points. It must neither
            // reuse an unfiltered test artifact nor stand in for one on the next invocation.
            if (!cmdLine.testFileFilter.empty())
                return false;
            return !cmdLine.testJit && cmdLine.testNative && cmdLine.output;
        }

        return cmdLine.command != CommandKind::Doc;
    }

    bool hasWorkspaceVerifyDirectives(const CompilerInstance& compiler)
    {
        for (const SourceFile* file : compiler.files())
        {
            if (file && file->unitTest().hasExpectedDirectives())
                return true;
        }

        return false;
    }

    bool shouldWriteWorkspaceArtifactManifest(const CompilerInstance& compiler)
    {
        const CommandLine& cmdLine = compiler.cmdLine();
        if (cmdLine.dryRun || cmdLine.showConfig || cmdLine.command == CommandKind::Doc)
            return false;
        if (cmdLine.command != CommandKind::Test)
            return true;

        // Focused artifacts have their own mode suffix and are never reused. Leaving no manifest
        // keeps every distinct filter set honest without turning the filter into a cache key.
        if (!cmdLine.testFileFilter.empty())
            return false;

        // A cached test has no AST against which source-driven expectations can be checked.
        // Keep compiling those inputs so every Verify directive is evaluated on every run.
        return cmdLine.testNative && cmdLine.output && !hasWorkspaceVerifyDirectives(compiler);
    }

    Utf8 formatWorkspaceReuseStat(const TaskContext& ctx, const CompilerInstance& compiler)
    {
        std::vector<Utf8> parts;
        parts.push_back(ScopedTimedLog::formatStatName(ctx, "up-to-date"));
        if (!compiler.lastArtifactLabel().empty())
            parts.push_back(ScopedTimedLog::formatStatName(ctx, compiler.lastArtifactLabel()));
        return ScopedTimedLog::joinStatItems(ctx, parts);
    }

    Utf8 bytesToLowerHex(const std::span<const uint8_t> bytes)
    {
        Utf8 result;
        result.reserve(bytes.size() * 2);
        for (const uint8_t b : bytes)
            result += std::format("{:02x}", b);
        return result;
    }

    // Where a dependency directory sits inside the root it was found through. A copy keeps that
    // shape — '<module>/<backend>/<build-cfg>/<arch>' — so a path in a diagnostic still says which
    // module and which configuration the compiler was reading.
    Result resolveDependencyMirrorRelativePath(fs::path& outRelativePath, TaskContext& ctx, const fs::path& normalizedSourceDir, const fs::path& normalizedSourceRoot)
    {
        if (!FileSystem::pathStartsWith(normalizedSourceDir, normalizedSourceRoot))
        {
            const Utf8 because = std::format("dependency folder '{}' is not under root '{}'", Utf8(normalizedSourceDir).c_str(), Utf8(normalizedSourceRoot).c_str());
            return reportWorkspaceDependencySyncFailure(ctx, normalizedSourceDir, because);
        }

        outRelativePath = normalizedSourceDir.lexically_relative(normalizedSourceRoot);
        if (outRelativePath.empty() || pathIsCurrentOrParentDirectory(outRelativePath))
        {
            const Utf8 because = std::format("cannot mirror dependency folder '{}' from root '{}'", Utf8(normalizedSourceDir).c_str(), Utf8(normalizedSourceRoot).c_str());
            return reportWorkspaceDependencySyncFailure(ctx, normalizedSourceDir, because);
        }

        return Result::Continue;
    }

    // What identifies one build of a dependency: every file it holds, with its size and its
    // modification time. It is the same evidence a copy already trusted to decide a file was
    // unchanged, read once for the whole directory instead of once per file, and it costs one
    // stat per file where hashing the bytes would cost a read.
    bool tryCollectDependencyCacheSignature(Utf8& outSignature, const fs::path& srcDir)
    {
        std::vector<Utf8> entries;
        std::error_code   ec;
        for (fs::recursive_directory_iterator it(srcDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return false;

            ec.clear();
            if (!it->is_regular_file(ec) || ec)
                continue;

            ec.clear();
            const uintmax_t fileSize = it->file_size(ec);
            if (ec)
                return false;

            ec.clear();
            const auto writeTime = it->last_write_time(ec);
            if (ec)
                return false;

            entries.emplace_back(std::format("{}\t{}\t{}", Utf8(it->path().lexically_relative(srcDir)).c_str(), fileSize, writeTime.time_since_epoch().count()));
        }

        // The order a directory is walked in is not part of what it holds.
        std::ranges::sort(entries);
        outSignature = Utf8Helper::join(entries, "\n");
        return true;
    }

    fs::path dependencyCacheEntryDirectory(const fs::path& srcDir, const Utf8& signature)
    {
        // The source path belongs in the name: two dependencies can hold the same bytes and still
        // be different answers to where a module comes from, which is what a diagnostic naming the
        // copy has to stay able to say.
        Utf8 identity = "version=1\nsource=";
        identity += Utf8(srcDir);
        identity += '\n';
        identity += signature;

        const std::string_view identityView = identity.view();
        const auto             digest       = sha256(std::span{reinterpret_cast<const std::byte*>(identityView.data()), identityView.size()});
        return (WorkspaceLayout::dependencyCacheRoot() / fs::path(bytesToLowerHex(digest).c_str())).lexically_normal();
    }

    fs::path dependencyCacheUsedMarkerPath(const fs::path& entryDir)
    {
        return (entryDir / fs::path(std::string(WorkspaceLayout::DEPENDENCY_CACHE_USED_MARKER))).lexically_normal();
    }

    // Re-dates the entry, so that a trim can tell what is still in use from what nothing has asked
    // for in weeks. It is the one thing ever written to a published entry, it says nothing about
    // the copy, and a cache that fails to record it still answers every question correctly.
    void touchDependencyCacheEntry(const fs::path& entryDir)
    {
        std::error_code ec;
        fs::last_write_time(dependencyCacheUsedMarkerPath(entryDir), fs::file_time_type::clock::now(), ec);
    }

    Result writeDependencyCacheUsedMarker(TaskContext& ctx, const fs::path& entryDir, const fs::path& srcDir)
    {
        const fs::path          markerPath = dependencyCacheUsedMarkerPath(entryDir);
        const Utf8              content    = std::format("{}\n", Utf8(srcDir).c_str());
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(markerPath, content.data(), content.size(), ioError) == Result::Continue)
            return Result::Continue;

        return reportWorkspaceDependencySyncFailure(ctx, markerPath, FileSystem::describeIoFailure(ioError));
    }

    // Days a copy may go unused before a newly published one takes it. Long enough that a
    // configuration returned to after a weekend is still there, short enough that a week of
    // rebuilding the library does not keep every intermediate state of it.
    constexpr uint32_t K_DEPENDENCY_CACHE_UNUSED_DAYS = 7;

    // Removes what nothing has used in a while, and only right after a new entry is published:
    // that is exactly when the cache grew, and it is rare enough for one directory scan to cost
    // nothing. Everything here is a cache operation, so a failure is not reported — it only means
    // the disk is given back later, by the next publication or by `swc clean --cache`.
    //
    // An entry is renamed out of the way before it is removed, because a copy in use cannot be
    // renamed — Windows holds the directory of a library it has loaded — while a removal that
    // failed halfway would leave a gutted entry that still looks complete to the next run.
    void trimUnusedDependencyCacheEntries(const fs::path& publishedEntryDir)
    {
        const auto            maxAge = std::chrono::seconds(86400ULL * K_DEPENDENCY_CACHE_UNUSED_DAYS);
        const auto            now    = fs::file_time_type::clock::now();
        std::vector<fs::path> unusedEntryDirs;
        std::error_code       ec;
        for (fs::directory_iterator it(WorkspaceLayout::dependencyCacheRoot(), fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return;

            ec.clear();
            if (!it->is_directory(ec) || ec)
                continue;
            if (FileSystem::pathEquals(it->path(), publishedEntryDir))
                continue;

            ec.clear();
            const auto usedTime = fs::last_write_time(dependencyCacheUsedMarkerPath(it->path()), ec);
            if (ec || std::chrono::duration_cast<std::chrono::seconds>(now - usedTime) < maxAge)
                continue;

            unusedEntryDirs.push_back(it->path());
        }

        for (const fs::path& entryDir : unusedEntryDirs)
        {
            const Utf8     retiredName = std::format("{}.retired.{}", entryDir.filename().string(), Os::currentProcessId());
            const fs::path retiredDir  = (WorkspaceLayout::dependencyCacheStagingRoot() / fs::path(retiredName.c_str())).lexically_normal();

            ec.clear();
            fs::rename(entryDir, retiredDir, ec);
            if (ec)
                continue;

            ec.clear();
            fs::remove_all(retiredDir, ec);
        }
    }

    Result copyDependencyCacheTree(TaskContext& ctx, const fs::path& srcDir, const fs::path& dstDir)
    {
        std::error_code ec;
        for (fs::recursive_directory_iterator it(srcDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return reportWorkspaceDependencySyncFailure(ctx, srcDir, FileSystem::normalizeSystemMessage(ec));

            const fs::path relativePath = it->path().lexically_relative(srcDir);
            if (relativePath.empty())
                continue;

            const fs::path dstPath = (dstDir / relativePath).lexically_normal();
            ec.clear();
            if (it->is_directory(ec))
            {
                ec.clear();
                fs::create_directories(dstPath, ec);
                if (ec)
                    return reportWorkspaceDependencySyncFailure(ctx, dstPath, FileSystem::normalizeSystemMessage(ec));
                continue;
            }

            ec.clear();
            if (!it->is_regular_file(ec) || ec)
                continue;

            ec.clear();
            fs::copy_file(it->path(), dstPath, fs::copy_options::overwrite_existing, ec);
            if (ec)
                return reportWorkspaceDependencySyncFailure(ctx, dstPath, FileSystem::normalizeSystemMessage(ec));

            // The copy keeps the date of its source, so what an entry holds stays recognizable as
            // what it was made from.
            ec.clear();
            const auto srcTime = fs::last_write_time(it->path(), ec);
            if (!ec)
            {
                ec.clear();
                fs::last_write_time(dstPath, srcTime, ec);
            }
        }

        return Result::Continue;
    }

    // Fills an entry, and makes it exist for everyone else in one step.
    //
    // The copy is assembled under a name only this process uses and moved into place by a single
    // rename, so no other compiler can find a directory that is still being written. Losing that
    // rename is the ordinary outcome of two scripts starting at once rather than a failure: the
    // entry the other one published holds the same bytes, and this copy is dropped.
    Result publishDependencyCacheEntry(TaskContext& ctx, const fs::path& entryDir, const fs::path& srcDir, const fs::path& relativePath)
    {
        const Utf8     stagingName = std::format("{}.{}", entryDir.filename().string(), Os::currentProcessId());
        const fs::path stagingDir  = (WorkspaceLayout::dependencyCacheStagingRoot() / fs::path(stagingName.c_str())).lexically_normal();

        std::error_code ec;
        fs::remove_all(stagingDir, ec);

        ec.clear();
        fs::create_directories(stagingDir / relativePath, ec);
        if (ec)
            return reportWorkspaceDependencySyncFailure(ctx, stagingDir, FileSystem::normalizeSystemMessage(ec));

        Result result = copyDependencyCacheTree(ctx, srcDir, (stagingDir / relativePath).lexically_normal());
        if (result == Result::Continue)
            result = writeDependencyCacheUsedMarker(ctx, stagingDir, srcDir);

        if (result == Result::Continue)
        {
            ec.clear();
            fs::create_directories(entryDir.parent_path(), ec);
            ec.clear();
            fs::rename(stagingDir, entryDir, ec);
            if (ec && !fs::is_directory(entryDir))
                result = reportWorkspaceDependencySyncFailure(ctx, entryDir, FileSystem::normalizeSystemMessage(ec));
        }

        ec.clear();
        fs::remove_all(stagingDir, ec);

        if (result == Result::Continue)
            trimUnusedDependencyCacheEntries(entryDir);
        return result;
    }

    // Answers with a directory holding the same files as `srcDir`, that nothing will rewrite.
    //
    // A script consumes its dependencies from a copy rather than from where they were built,
    // because the compiler loads their shared libraries into its own process: pointed at the build
    // output, `swc tools/std.swgs` — a script that rebuilds the very library it runs on — would be
    // asked to replace a DLL Windows has locked. Naming the copy after what it holds is what makes
    // the copy affordable: every script importing the same build shares one, and a rebuilt
    // dependency lands in a new entry beside the one a running script is still reading.
    Result resolveDependencyCacheEntry(fs::path& outMirroredDir, TaskContext& ctx, const fs::path& srcDir, const fs::path& relativePath)
    {
        Utf8 signature;
        if (!tryCollectDependencyCacheSignature(signature, srcDir))
            return reportWorkspaceDependencySyncFailure(ctx, srcDir, "cannot read what the dependency holds");

        const fs::path  entryDir = dependencyCacheEntryDirectory(srcDir, signature);
        std::error_code ec;
        if (!fs::is_directory(entryDir, ec))
            SWC_RESULT(publishDependencyCacheEntry(ctx, entryDir, srcDir, relativePath));

        touchDependencyCacheEntry(entryDir);
        outMirroredDir = (entryDir / relativePath).lexically_normal();
        return Result::Continue;
    }

}

struct DependencyPlanBuilder
{
    explicit DependencyPlanBuilder(CompilerInstance& compilerInstance, TaskContext& taskContext);

    Result build(CompilerInstance::DependencyPlan& outPlan, std::span<const CompilerInstance::ModuleSetupImport> imports);
    Result resolveExplicitDependencyRoot(fs::path& outRoot, const CompilerInstance::ModuleSetupImport& importRequest) const;
    Result resolveLinkAndSharedDirs(CompilerInstance::ResolvedDependencyPaths& outPaths, const fs::path& dependencyRoot, const CompilerInstance::ModuleSetupImport& importRequest) const;
    bool   mirrorsDependencies() const;
    Result mirrorDependencyDir(fs::path& ioDir, const fs::path& sourceDependencyRoot);
    Result mirrorWorkspaceDependencyDir(fs::path& ioDir, const fs::path& sourceDependencyRoot);
    Result mirrorScriptDependencyDir(fs::path& ioDir, const fs::path& sourceDependencyRoot);
    bool   tryResolveDependencyApiDir(CompilerInstance::ResolvedDependencyPaths& outPaths, Utf8& outBecause, const fs::path& dependencyRoot, const CompilerInstance::ModuleSetupImport& importRequest) const;
    Result resolveDependencyImportDir(CompilerInstance::ResolvedDependencyPaths& outPaths, const CompilerInstance::ModuleSetupImport& importRequest, const fs::path* preferredDependencyRoot);
    Result captureDependencyImportSnapshot(const fs::path& depsFile, CompilerInstance::ModuleSetupSnapshot& outSnapshot) const;
    // Parsing and checking dependency metadata is expensive, and several roots can reach the same
    // file. Cache its import list so the global resolution visits it once.
    Result captureDependencyImports(const fs::path& depsFile, const std::vector<CompilerInstance::ModuleSetupImport>** outImports);
    bool   tryCaptureGeneratedDependencyImports(const fs::path& depsFile, std::vector<CompilerInstance::ModuleSetupImport>& outImports) const;
    Result resolveNode(size_t& outIndex, CompilerInstance::DependencyPlan& plan, const CompilerInstance::ModuleSetupImport& importRequest, const fs::path* preferredDependencyRoot);
    void   collectClosure(std::vector<size_t>& outClosure, std::vector<Utf8>& outModules, const CompilerInstance::DependencyPlan& plan, size_t nodeIndex) const;

    CompilerInstance& instance() const
    {
        SWC_ASSERT(compiler);
        return *compiler;
    }

    TaskContext& taskCtx() const
    {
        SWC_ASSERT(ctx);
        return *ctx;
    }

    CompilerInstance*                                                          compiler = nullptr;
    TaskContext*                                                               ctx      = nullptr;
    fs::path                                                                   workspaceOutputRoot;
    fs::path                                                                   workspaceDependencyRoot;
    std::unordered_set<Utf8>                                                   mirroredDependencyDirs;
    std::unordered_map<Utf8, fs::path>                                         scriptDependencyEntries;
    std::unordered_map<Utf8, size_t>                                           nodeIndices;
    std::unordered_map<Utf8, std::vector<CompilerInstance::ModuleSetupImport>> dependencyImportsCache;
};

struct ModuleSetupInputApplier
{
    explicit ModuleSetupInputApplier(CompilerInstance& compilerInstance, TaskContext& taskContext);

    Result apply(const CompilerInstance::ModuleSetupSnapshot& setupSnapshot, const CompilerInstance::DependencyPlan& dependencyPlan);

    CompilerInstance& instance() const
    {
        SWC_ASSERT(compiler);
        return *compiler;
    }

    TaskContext& taskCtx() const
    {
        SWC_ASSERT(ctx);
        return *ctx;
    }

    CompilerInstance* compiler = nullptr;
    TaskContext*      ctx      = nullptr;
};

DependencyPlanBuilder::DependencyPlanBuilder(CompilerInstance& compilerInstance, TaskContext& taskContext)
{
    compiler = &compilerInstance;
    ctx      = &taskContext;
    if (!instance().cmdLine().workspacePath.empty())
    {
        workspaceOutputRoot     = FileSystem::normalizePath(WorkspaceLayout::workspaceOutputDirectory(instance().cmdLine().workspacePath));
        workspaceDependencyRoot = FileSystem::normalizePath(WorkspaceLayout::workspaceDependencyDirectory(instance().cmdLine().workspacePath));
    }
}

ModuleSetupInputApplier::ModuleSetupInputApplier(CompilerInstance& compilerInstance, TaskContext& taskContext)
{
    compiler = &compilerInstance;
    ctx      = &taskContext;
}

Result ModuleSetupInputApplier::apply(const CompilerInstance::ModuleSetupSnapshot& setupSnapshot, const CompilerInstance::DependencyPlan& dependencyPlan)
{
    instance().moduleSetupImports_ = setupSnapshot.imports;
    instance().nativeRuntimeImports_.clear();
    instance().moduleSetupLoadedFiles_ = setupSnapshot.loadedFiles;

    for (const CompilerInstance::ModuleSetupImport& importRequest : setupSnapshot.imports)
    {
        const CompilerInstance::ResolvedDependencyBinding* binding = nullptr;
        for (const CompilerInstance::ResolvedDependencyBinding& candidate : dependencyPlan.bindings)
        {
            if (candidate.request.moduleName == importRequest.moduleName &&
                candidate.request.location == importRequest.location &&
                candidate.request.version == importRequest.version &&
                FileSystem::pathEquals(candidate.request.baseDir, importRequest.baseDir) &&
                candidate.request.linkBackendKind == importRequest.linkBackendKind)
            {
                binding = &candidate;
                break;
            }
        }

        // Workspace-local imports become resolvable in build order, after their producer has
        // published its artifacts. External imports are always present in the command-wide plan.
        CompilerInstance::DependencyPlan localPlan;
        if (!binding)
        {
            DependencyPlanBuilder builder(instance(), taskCtx());
            SWC_RESULT(builder.build(localPlan, std::span{&importRequest, 1}));
            SWC_ASSERT(localPlan.bindings.size() == 1);
            binding = &localPlan.bindings.front();
        }

        const CompilerInstance::DependencyPlan& bindingPlan = localPlan.bindings.empty() ? dependencyPlan : localPlan;
        for (const size_t nodeIndex : binding->closure)
        {
            const CompilerInstance::ResolvedDependencyNode& node = bindingPlan.nodes[nodeIndex];
            instance().collectImportedApiFolderFiles(node.paths.apiDir, node.moduleName.view());
            instance().registerImportedDependencyLinkDir(node.paths.linkDir);
            instance().registerImportedSharedModuleDir(node.paths.sharedDir);
        }

        const CompilerInstance::ResolvedDependencyNode& directNode = bindingPlan.nodes[binding->nodeIndex];
        if (!directNode.paths.linkDir.empty())
        {
            CompilerInstance::NativeRuntimeImport runtimeImport;
            runtimeImport.moduleName           = importRequest.moduleName;
            runtimeImport.linkModuleName       = resolveDependencyLinkModuleName(directNode.paths.linkDir, importRequest.moduleName.view());
            runtimeImport.transitiveImports    = binding->transitiveImports;
            runtimeImport.hasSharedRuntimeHook = !directNode.paths.sharedDir.empty();
            instance().nativeRuntimeImports_.push_back(std::move(runtimeImport));
        }
    }

    for (const fs::path& filePath : setupSnapshot.loadedFiles)
    {
        fs::path resolvedPath = filePath;
        SWC_RESULT(FileSystem::resolveFile(taskCtx(), resolvedPath));
        if (instance().hasResolvedFilePath(resolvedPath))
            continue;

        // 'SetupLoaded' is what tells the regular pass to skip the module setup directives this
        // file states: the setup pass has already read them, and reading them again here would
        // report them as directives outside a module setup file.
        instance().addResolvedFile(resolvedPath, FileFlagsE::ModuleSrc | FileFlagsE::SetupLoaded);
    }

    return Result::Continue;
}

Result DependencyPlanBuilder::resolveExplicitDependencyRoot(fs::path& outRoot, const CompilerInstance::ModuleSetupImport& importRequest) const
{
    if (importRequest.location == "swag@std")
        return resolveSwagStdOutputRoot(outRoot, taskCtx());

    outRoot = fs::path(importRequest.location.c_str());
    if (outRoot.is_relative())
    {
        const fs::path baseDir = !importRequest.baseDir.empty() ? importRequest.baseDir : (instance().cmdLine().moduleFilePath.empty() ? FileSystem::currentPathNoThrow() : instance().cmdLine().moduleFilePath.parent_path());
        if (!baseDir.empty())
            outRoot = (baseDir / outRoot).lexically_normal();
    }

    SWC_RESULT(FileSystem::resolveFolder(taskCtx(), outRoot));
    return Result::Continue;
}

Result DependencyPlanBuilder::resolveLinkAndSharedDirs(CompilerInstance::ResolvedDependencyPaths& outPaths, const fs::path& dependencyRoot, const CompilerInstance::ModuleSetupImport& importRequest) const
{
    outPaths.linkDir.clear();
    outPaths.sharedDir.clear();
    outPaths.sourceRoot = FileSystem::normalizePath(dependencyRoot);

    Utf8     because;
    fs::path sharedDir;
    if (findDependencyConfigurationDirectoryForBackend(sharedDir, because, dependencyRoot, importRequest.moduleName.view(), instance().cmdLine(), Runtime::BuildCfgBackendKind::SharedLibrary) == Result::Continue)
        outPaths.sharedDir = std::move(sharedDir);

    if (importRequest.linkBackendKind != Runtime::BuildCfgBackendKind::None)
    {
        if (findDependencyConfigurationDirectoryForBackend(outPaths.linkDir, because, dependencyRoot, importRequest.moduleName.view(), instance().cmdLine(), importRequest.linkBackendKind) != Result::Continue)
            return reportInvalidFolder(taskCtx(), dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);
        return Result::Continue;
    }

    if (!outPaths.sharedDir.empty())
    {
        outPaths.linkDir = outPaths.sharedDir;
        return Result::Continue;
    }

    if (outPaths.apiBackendKind == Runtime::BuildCfgBackendKind::StaticLibrary)
        outPaths.linkDir = outPaths.apiDir;
    return Result::Continue;
}

// Whether the compiler reads its dependencies from a copy instead of from where they were built.
//
// A workspace vendors them into a '.dep' directory it owns. A script has no directory of its own
// and shares the content-addressed cache. Everything else reads them where they are: only these
// two run a program whose libraries may be rebuilt underneath it by the very run that loaded them.
bool DependencyPlanBuilder::mirrorsDependencies() const
{
    return !workspaceDependencyRoot.empty() || instance().cmdLine().scriptMode;
}

Result DependencyPlanBuilder::mirrorDependencyDir(fs::path& ioDir, const fs::path& sourceDependencyRoot)
{
    if (ioDir.empty())
        return Result::Continue;
    if (!workspaceDependencyRoot.empty())
        return mirrorWorkspaceDependencyDir(ioDir, sourceDependencyRoot);
    return mirrorScriptDependencyDir(ioDir, sourceDependencyRoot);
}

Result DependencyPlanBuilder::mirrorWorkspaceDependencyDir(fs::path& ioDir, const fs::path& sourceDependencyRoot)
{
    const fs::path normalizedSourceDir  = FileSystem::normalizePath(ioDir);
    const fs::path normalizedSourceRoot = FileSystem::normalizePath(sourceDependencyRoot);
    if (FileSystem::pathEquals(normalizedSourceRoot, workspaceOutputRoot) || FileSystem::pathEquals(normalizedSourceRoot, workspaceDependencyRoot))
    {
        ioDir = normalizedSourceDir;
        return Result::Continue;
    }

    fs::path relativePath;
    SWC_RESULT(resolveDependencyMirrorRelativePath(relativePath, taskCtx(), normalizedSourceDir, normalizedSourceRoot));

    fs::path   destinationDir = (workspaceDependencyRoot / relativePath).lexically_normal();
    const Utf8 mirrorKey      = std::format("{}|{}", Utf8(normalizedSourceDir).c_str(), Utf8(destinationDir).c_str());
    if (mirroredDependencyDirs.insert(mirrorKey).second)
        SWC_RESULT(syncWorkspaceDependencyDirectory(taskCtx(), normalizedSourceDir, destinationDir));

    ioDir = std::move(destinationDir);
    return Result::Continue;
}

Result DependencyPlanBuilder::mirrorScriptDependencyDir(fs::path& ioDir, const fs::path& sourceDependencyRoot)
{
    const fs::path normalizedSourceDir = FileSystem::normalizePath(ioDir);

    // What already lives in the cache is never copied into it again.
    if (FileSystem::pathStartsWith(normalizedSourceDir, FileSystem::normalizePath(WorkspaceLayout::dependencyCacheRoot())))
    {
        ioDir = normalizedSourceDir;
        return Result::Continue;
    }

    // One directory is asked for as many times as it answers for — an API directory that is also
    // the link directory, a module two others import — and reading what it holds is the expensive
    // half of the answer.
    const auto entryKey = Utf8(normalizedSourceDir);
    const auto it       = scriptDependencyEntries.find(entryKey);
    if (it != scriptDependencyEntries.end())
    {
        ioDir = it->second;
        return Result::Continue;
    }

    fs::path relativePath;
    SWC_RESULT(resolveDependencyMirrorRelativePath(relativePath, taskCtx(), normalizedSourceDir, FileSystem::normalizePath(sourceDependencyRoot)));

    fs::path mirroredDir;
    SWC_RESULT(resolveDependencyCacheEntry(mirroredDir, taskCtx(), normalizedSourceDir, relativePath));
    scriptDependencyEntries.emplace(entryKey, mirroredDir);
    ioDir = std::move(mirroredDir);
    return Result::Continue;
}

bool DependencyPlanBuilder::tryResolveDependencyApiDir(CompilerInstance::ResolvedDependencyPaths& outPaths, Utf8& outBecause, const fs::path& dependencyRoot, const CompilerInstance::ModuleSetupImport& importRequest) const
{
    return findDependencyConfigurationDirectory(outPaths.apiDir, outBecause, dependencyRoot, importRequest.moduleName.view(), instance().cmdLine(), &outPaths.apiBackendKind) == Result::Continue;
}

Result DependencyPlanBuilder::resolveDependencyImportDir(CompilerInstance::ResolvedDependencyPaths& outPaths, const CompilerInstance::ModuleSetupImport& importRequest, const fs::path* preferredDependencyRoot)
{
    outPaths = {};

    if (!importRequest.location.empty())
    {
        fs::path dependencyRoot;
        SWC_RESULT(resolveExplicitDependencyRoot(dependencyRoot, importRequest));

        Utf8 because;
        if (!tryResolveDependencyApiDir(outPaths, because, dependencyRoot, importRequest))
            return reportInvalidFolder(taskCtx(), dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);

        return resolveLinkAndSharedDirs(outPaths, dependencyRoot, importRequest);
    }

    if (preferredDependencyRoot && !preferredDependencyRoot->empty())
    {
        Utf8 because;
        if (findDependencyConfigurationDirectory(outPaths.apiDir, because, *preferredDependencyRoot, importRequest.moduleName.view(), instance().cmdLine(), &outPaths.apiBackendKind) == Result::Continue)
            return resolveLinkAndSharedDirs(outPaths, *preferredDependencyRoot, importRequest);
    }

    if (!instance().cmdLine().workspacePath.empty())
    {
        fs::path        workspaceModuleDir = workspaceModuleDirectory(instance().cmdLine().workspacePath, importRequest.moduleName.view());
        std::error_code ec;
        if (fs::is_directory(workspaceModuleDir, ec))
        {
            const fs::path dependencyRoot = WorkspaceLayout::workspaceOutputDirectory(instance().cmdLine().workspacePath);
            Utf8           because;
            if (findDependencyConfigurationDirectory(outPaths.apiDir, because, dependencyRoot, importRequest.moduleName.view(), instance().cmdLine(), &outPaths.apiBackendKind) != Result::Continue)
                return reportInvalidFolder(taskCtx(), dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);
            return resolveLinkAndSharedDirs(outPaths, dependencyRoot, importRequest);
        }
    }

    std::vector<DependencyConfigCandidate> matches;
    for (const fs::path& dependencyRoot : instance().cmdLine().importApiDirs)
    {
        DependencyConfigCandidate match;
        Utf8                      because;
        if (findDependencyConfigurationDirectory(match.path, because, dependencyRoot, importRequest.moduleName.view(), instance().cmdLine(), &match.backendKind) != Result::Continue)
            continue;

        matches.push_back(std::move(match));
    }

    if (matches.empty())
    {
        if (instance().cmdLine().importApiDirs.empty())
            return reportInvalidFolder(taskCtx(), importRequest.moduleName.c_str(), "no workspace dependency was found and no --import-api-dir root was provided");

        const Utf8 because = std::format("module '{}' was not found in any dependency root for {}", importRequest.moduleName.c_str(), dependencyConfigurationLabel(instance().cmdLine()).c_str());
        return reportInvalidFolder(taskCtx(), importRequest.moduleName.c_str(), because);
    }

    std::ranges::sort(matches, {}, &DependencyConfigCandidate::path);
    matches.erase(std::ranges::unique(matches, {}, &DependencyConfigCandidate::path).begin(), matches.end());
    if (matches.size() != 1)
    {
        std::vector<fs::path> paths;
        paths.reserve(matches.size());
        for (const DependencyConfigCandidate& match : matches)
            paths.push_back(match.path);

        const Utf8 because = std::format("multiple dependency roots match {} ({})", dependencyConfigurationLabel(instance().cmdLine()).c_str(), joinDependencyPaths(paths).c_str());
        return reportInvalidFolder(taskCtx(), importRequest.moduleName.c_str(), because);
    }

    outPaths.apiDir         = matches.front().path;
    outPaths.apiBackendKind = matches.front().backendKind;
    return resolveLinkAndSharedDirs(outPaths, dependencyRootFromConfigurationDir(outPaths.apiDir), importRequest);
}

Result DependencyPlanBuilder::captureDependencyImportSnapshot(const fs::path& depsFile, CompilerInstance::ModuleSetupSnapshot& outSnapshot) const
{
    CommandLine setupCmdLine = instance().cmdLine();
    setupCmdLine.directories.clear();
    setupCmdLine.files.clear();
    setupCmdLine.importApiModules.clear();
    setupCmdLine.importApiFiles.clear();
    setupCmdLine.exportApiDir.clear();
    setupCmdLine.modulePath.clear();
    setupCmdLine.moduleFilePath = depsFile;
    CommandLineParser::refreshBuildCfg(setupCmdLine);
    return instance().captureModuleSetupSnapshot(taskCtx(), setupCmdLine, outSnapshot);
}

bool DependencyPlanBuilder::tryCaptureGeneratedDependencyImports(const fs::path& depsFile, std::vector<CompilerInstance::ModuleSetupImport>& outImports) const
{
    std::string             content;
    FileSystem::IoErrorInfo ioError;
    if (FileSystem::readTextFile(depsFile, content, ioError) != Result::Continue)
        return false;

    const auto skipSpaces = [](const std::string_view line, size_t& pos) {
        while (pos < line.size() && (line[pos] == ' ' || line[pos] == '\t'))
            pos++;
    };
    const auto readQuoted = [](Utf8& outValue, const std::string_view line, size_t& pos) {
        if (pos >= line.size() || line[pos] != '"')
            return false;
        const size_t end = line.find('"', ++pos);
        if (end == std::string_view::npos)
            return false;
        outValue = line.substr(pos, end - pos);
        pos      = end + 1;
        return true;
    };

    size_t contentPos = 0;
    while (contentPos < content.size())
    {
        const size_t                        lineEnd = content.find('\n', contentPos);
        std::string_view                    line{content.data() + contentPos, (lineEnd == std::string::npos ? content.size() : lineEnd) - contentPos};
        CompilerInstance::ModuleSetupImport importRequest;
        contentPos = lineEnd == std::string::npos ? content.size() : lineEnd + 1;
        if (!line.empty() && line.back() == '\r')
            line.remove_suffix(1);

        size_t pos = 0;
        skipSpaces(line, pos);
        constexpr std::string_view prefix = "#import(";
        if (!line.substr(pos).starts_with(prefix))
            return false;
        pos += prefix.size();
        if (!readQuoted(importRequest.moduleName, line, pos))
            return false;

        while (true)
        {
            skipSpaces(line, pos);
            if (pos < line.size() && line[pos] == ')')
            {
                pos++;
                break;
            }
            if (pos >= line.size() || line[pos++] != ',')
                return false;
            skipSpaces(line, pos);

            Utf8* target = nullptr;
            if (line.substr(pos).starts_with("location:"))
            {
                pos += 9;
                target = &importRequest.location;
            }
            else if (line.substr(pos).starts_with("version:"))
            {
                pos += 8;
                target = &importRequest.version;
            }
            else if (line.substr(pos).starts_with("link:"))
            {
                pos += 5;
                Utf8 link;
                skipSpaces(line, pos);
                if (!readQuoted(link, line, pos))
                    return false;
                if (link == backendKindName(Runtime::BuildCfgBackendKind::SharedLibrary))
                    importRequest.linkBackendKind = Runtime::BuildCfgBackendKind::SharedLibrary;
                else if (link == backendKindName(Runtime::BuildCfgBackendKind::StaticLibrary))
                    importRequest.linkBackendKind = Runtime::BuildCfgBackendKind::StaticLibrary;
                else
                    return false;
                continue;
            }
            else
            {
                return false;
            }

            skipSpaces(line, pos);
            if (!readQuoted(*target, line, pos))
                return false;
        }

        skipSpaces(line, pos);
        if (pos != line.size() || importRequest.moduleName.empty())
            return false;
        importRequest.baseDir = depsFile.parent_path();
        outImports.push_back(std::move(importRequest));
    }

    return true;
}

Result DependencyPlanBuilder::captureDependencyImports(const fs::path& depsFile, const std::vector<CompilerInstance::ModuleSetupImport>** outImports)
{
    // depsFile has already been resolved to an absolute path by the caller, so a lexical key is
    // enough to identify it without paying for another weakly_canonical() disk round-trip.
    const auto key = Utf8(depsFile.lexically_normal().string());
    const auto it  = dependencyImportsCache.find(key);
    if (it != dependencyImportsCache.end())
    {
        *outImports = &it->second;
        return Result::Continue;
    }

    std::vector<CompilerInstance::ModuleSetupImport> imports;
    if (!tryCaptureGeneratedDependencyImports(depsFile, imports))
    {
        CompilerInstance::ModuleSetupSnapshot snapshot;
        SWC_RESULT(captureDependencyImportSnapshot(depsFile, snapshot));
        imports = std::move(snapshot.imports);
    }

    const auto [insertedIt, inserted] = dependencyImportsCache.emplace(key, std::move(imports));
    SWC_UNUSED(inserted);
    *outImports = &insertedIt->second;
    return Result::Continue;
}

Result DependencyPlanBuilder::resolveNode(size_t& outIndex, CompilerInstance::DependencyPlan& plan, const CompilerInstance::ModuleSetupImport& importRequest, const fs::path* preferredDependencyRoot)
{
    CompilerInstance::ResolvedDependencyPaths paths;
    SWC_RESULT(resolveDependencyImportDir(paths, importRequest, preferredDependencyRoot));

    const fs::path sourceApiDir = FileSystem::normalizePath(paths.apiDir);
    const Utf8     nodeKey      = std::format("{}|{}|{}", Utf8(sourceApiDir).c_str(), importRequest.moduleName.c_str(), importRequest.version.c_str());
    const auto     existingIt   = nodeIndices.find(nodeKey);
    if (existingIt != nodeIndices.end())
    {
        outIndex = existingIt->second;
        return Result::Continue;
    }

    const fs::path sourceRoot = paths.sourceRoot;
    if (mirrorsDependencies())
    {
        SWC_RESULT(mirrorDependencyDir(paths.apiDir, sourceRoot));
        SWC_RESULT(mirrorDependencyDir(paths.linkDir, sourceRoot));
        SWC_RESULT(mirrorDependencyDir(paths.sharedDir, sourceRoot));
    }

    outIndex = plan.nodes.size();
    nodeIndices.emplace(nodeKey, outIndex);

    CompilerInstance::ResolvedDependencyNode node;
    node.moduleName      = importRequest.moduleName;
    node.location        = importRequest.location;
    node.version         = importRequest.version;
    node.linkBackendKind = importRequest.linkBackendKind;
    node.paths           = std::move(paths);
    plan.nodes.push_back(std::move(node));

    fs::path depsFile = dependencyImportMetadataPath(plan.nodes[outIndex].paths.apiDir);
    Utf8     because;
    if (FileSystem::resolveExistingFile(depsFile, because) != Result::Continue)
        return Result::Continue;

    const std::vector<CompilerInstance::ModuleSetupImport>* nestedImports = nullptr;
    SWC_RESULT(captureDependencyImports(depsFile, &nestedImports));
    for (const CompilerInstance::ModuleSetupImport& nestedImport : *nestedImports)
    {
        size_t dependencyIndex = 0;
        SWC_RESULT(resolveNode(dependencyIndex, plan, nestedImport, &sourceRoot));
        plan.nodes[outIndex].dependencies.push_back(dependencyIndex);
    }

    return Result::Continue;
}

void DependencyPlanBuilder::collectClosure(std::vector<size_t>& outClosure, std::vector<Utf8>& outModules, const CompilerInstance::DependencyPlan& plan, const size_t nodeIndex) const
{
    if (std::ranges::find(outClosure, nodeIndex) != outClosure.end())
        return;

    outClosure.push_back(nodeIndex);
    const CompilerInstance::ResolvedDependencyNode& node = plan.nodes[nodeIndex];
    for (const size_t dependencyIndex : node.dependencies)
    {
        if (std::ranges::find(outClosure, dependencyIndex) != outClosure.end())
            continue;

        const CompilerInstance::ResolvedDependencyNode& dependency = plan.nodes[dependencyIndex];
        if (std::ranges::find(outModules, dependency.moduleName) == outModules.end())
            outModules.push_back(dependency.moduleName);
        collectClosure(outClosure, outModules, plan, dependencyIndex);
    }
}

Result DependencyPlanBuilder::build(CompilerInstance::DependencyPlan& outPlan, const std::span<const CompilerInstance::ModuleSetupImport> imports)
{
    outPlan = {};
    for (const CompilerInstance::ModuleSetupImport& importRequest : imports)
    {
        bool alreadyBound = false;
        for (const CompilerInstance::ResolvedDependencyBinding& binding : outPlan.bindings)
        {
            if (binding.request.moduleName == importRequest.moduleName &&
                binding.request.location == importRequest.location &&
                binding.request.version == importRequest.version &&
                FileSystem::pathEquals(binding.request.baseDir, importRequest.baseDir) &&
                binding.request.linkBackendKind == importRequest.linkBackendKind)
            {
                alreadyBound = true;
                break;
            }
        }
        if (alreadyBound)
            continue;

        CompilerInstance::ResolvedDependencyBinding binding;
        binding.request = importRequest;
        SWC_RESULT(resolveNode(binding.nodeIndex, outPlan, importRequest, nullptr));
        collectClosure(binding.closure, binding.transitiveImports, outPlan, binding.nodeIndex);
        outPlan.bindings.push_back(std::move(binding));
    }

    return Result::Continue;
}

Result CompilerInstance::prepareDependencyPlan(TaskContext& ctx, DependencyPlan& outPlan, const std::span<const ModuleSetupImport> imports)
{
    // Materialization precedes resolution. The compiler distribution already owns swag@std's
    // sources, so its provider only has to build the requested roots. A future repository provider
    // can fetch and build its source here, then hand the same flat resolver an output root.
    std::set<Utf8> stdModules;
    for (const ModuleSetupImport& importRequest : imports)
    {
        if (importRequest.location == "swag@std")
            stdModules.insert(importRequest.moduleName);
    }

    if (!stdModules.empty())
    {
        fs::path workspacePath;
        SWC_RESULT(resolveSwagStdWorkspaceRoot(workspacePath, ctx));

        CommandLine stdCmdLine              = cmdLine();
        stdCmdLine.command                  = CommandKind::Build;
        stdCmdLine.commandExplicit          = true;
        stdCmdLine.scriptMode               = false;
        stdCmdLine.sourceDrivenTest         = false;
        stdCmdLine.workspaceDependencyBuild = true;
        stdCmdLine.workspacePath            = workspacePath;
        stdCmdLine.workspaceModuleFilter.clear();
        stdCmdLine.workspaceModuleSelection = std::move(stdModules);
        stdCmdLine.moduleFilePath.clear();
        stdCmdLine.modulePath.clear();
        stdCmdLine.directories.clear();
        stdCmdLine.files.clear();
        stdCmdLine.importApiModules.clear();
        stdCmdLine.importApiDirs.clear();
        stdCmdLine.importApiFiles.clear();
        stdCmdLine.exportApiDir.clear();
        stdCmdLine.outDir.clear();
        stdCmdLine.workDir.clear();
        stdCmdLine.outDirStorage.clear();
        stdCmdLine.workDirStorage.clear();
        stdCmdLine.outDirExplicit  = false;
        stdCmdLine.workDirExplicit = false;
        stdCmdLine.name.clear();
        stdCmdLine.artifactNameExplicit = false;
        stdCmdLine.backendKind          = Runtime::BuildCfgBackendKind::Executable;
        stdCmdLine.artifactKindExplicit = false;
        stdCmdLine.moduleNamespace.clear();
        stdCmdLine.moduleNamespaceStorage.clear();
        stdCmdLine.moduleNamespaceExplicit = false;
        stdCmdLine.runArgs                 = effectiveGeneratedArtifactRunArgs(cmdLine());
        CommandLineParser::refreshBuildCfg(stdCmdLine);

        CompilerInstance stdCompiler(global(), stdCmdLine);
        if (stdCompiler.runWorkspace() != ExitCode::Success)
            return Result::Error;
    }

    DependencyPlanBuilder builder(*this, ctx);
    return builder.build(outPlan, imports);
}

bool CompilerInstance::isWorkspaceModuleActive(const WorkspaceModuleBuild& moduleBuild)
{
    return !moduleBuild.ignoreInWorkspace && !moduleBuild.filteredOut;
}

// A module's native link, run as a normal job on the shared JobManager. The owned CommandLine,
// CompilerInstance and NativeBackendBuilder must stay alive until the link job is joined and finished:
// the compiler is referenced (by pointer) by the builder, and the CommandLine is referenced (by
// pointer) by the compiler. Declaration order matters for teardown: the job is drained first, then
// the builder, then the compiler, then the CommandLine.
//
// The link runs on its own job client so the next module's (CPU-bound) compilation, which waits only
// on its own client, can overlap it instead of stalling. The job object is owned here so it outlives
// its execution and is torn down with the rest of the retained module state.
struct WorkspaceModuleLink
{
    Utf8                                  moduleName;
    std::unique_ptr<CommandLine>          cmdLine;
    std::unique_ptr<CompilerInstance>     compiler;
    std::unique_ptr<NativeBackendBuilder> builder;
    bool                                  writeManifest = false;
    WorkspaceArtifactManifest             manifest;
    fs::path                              manifestPath;
    fs::path                              outDir;
    std::unique_ptr<NativeLinkJob>        linkJob;
    JobClientId                           linkClientId = 0;
    bool                                  linkInFlight = false;

    // Enqueue the prepared link on the shared JobManager under a fresh client, then return so the
    // caller can move on to the next module while a worker thread runs the link.
    void launchLink()
    {
        JobManager& jobMgr = builder->ctx().global().jobMgr();
        linkClientId       = jobMgr.newClientId();
        linkJob            = std::make_unique<NativeLinkJob>(builder->ctx(), builder->deferredToolRun());
        linkInFlight       = true;
        jobMgr.enqueue(*linkJob, JobPriority::Normal, linkClientId);
    }

    // Block until the link job has run to completion (a no-op if it was never launched or already
    // joined). Required before the retained builder/compiler/cmdLine the job references are destroyed.
    void joinLink()
    {
        if (!linkInFlight)
            return;
        builder->ctx().global().jobMgr().waitAll(linkClientId);
        linkInFlight = false;
    }

    ~WorkspaceModuleLink()
    {
        // Defensive drain: an early/error return may drop a link without finalizing it. The job
        // references this object's retained builder, so it must complete before teardown.
        joinLink();
    }
};

namespace
{
    // Foreground completion of a backgrounded module link: drain the link job, interpret its result
    // and report any diagnostics in order, then record the artifact manifest now that the output exists.
    Result finalizeWorkspaceModuleLink(WorkspaceModuleLink& link)
    {
        link.joinLink();

        SWC_RESULT(link.builder->finishDeferredLink());

        if (link.writeManifest)
        {
            collectWorkspaceOutputArtifacts(link.manifest.artifacts, link.outDir);
            SWC_RESULT(writeWorkspaceArtifactManifest(link.builder->ctx(), link.manifest, link.manifestPath));
        }

        return Result::Continue;
    }
}

Result CompilerInstance::collectWorkspaceModuleDependencyDirs(TaskContext& ctx, std::vector<fs::path>& outDirs, const DependencyPlan& dependencyPlan, const std::span<const ModuleSetupImport> imports)
{
    outDirs.clear();
    outDirs.reserve(imports.size() * 3);
    for (const ModuleSetupImport& importRequest : imports)
    {
        const DependencyPlan*            selectedPlan = &dependencyPlan;
        const ResolvedDependencyBinding* binding      = nullptr;
        for (const ResolvedDependencyBinding& candidate : dependencyPlan.bindings)
        {
            if (candidate.request.moduleName == importRequest.moduleName &&
                candidate.request.location == importRequest.location &&
                candidate.request.version == importRequest.version &&
                FileSystem::pathEquals(candidate.request.baseDir, importRequest.baseDir) &&
                candidate.request.linkBackendKind == importRequest.linkBackendKind)
            {
                binding = &candidate;
                break;
            }
        }

        DependencyPlan localPlan;
        if (!binding)
        {
            DependencyPlanBuilder builder(*this, ctx);
            SWC_RESULT(builder.build(localPlan, std::span{&importRequest, 1}));
            SWC_ASSERT(localPlan.bindings.size() == 1);
            selectedPlan = &localPlan;
            binding      = &localPlan.bindings.front();
        }

        const ResolvedDependencyPaths& paths = selectedPlan->nodes[binding->nodeIndex].paths;
        if (!paths.apiDir.empty())
            outDirs.push_back(paths.apiDir);
        if (!paths.linkDir.empty())
            outDirs.push_back(paths.linkDir);
        if (!paths.sharedDir.empty())
            outDirs.push_back(paths.sharedDir);
    }

    normalizeWorkspacePaths(outDirs);
    return Result::Continue;
}

// Builds the same workspace selection this consuming command covers, so every imported module has
// published its interface and link artifacts before tests or documentation are compiled. The
// nested run is an ordinary build, so it cannot come back here.
ExitCode CompilerInstance::runWorkspacePublishPass(const DependencyPlan& dependencies) const
{
    // `publish` is deliberately inherited: this is a build of the workspace the consuming command
    // requested, and a link that does not publish removes runtime files a previous link placed
    // beside the artifact.
    CommandLine buildCmdLine      = cmdLine();
    buildCmdLine.command          = CommandKind::Build;
    buildCmdLine.commandExplicit  = true;
    buildCmdLine.sourceDrivenTest = false;
    buildCmdLine.outDir.clear();
    buildCmdLine.workDir.clear();
    buildCmdLine.outDirStorage.clear();
    buildCmdLine.workDirStorage.clear();
    buildCmdLine.outDirExplicit  = false;
    buildCmdLine.workDirExplicit = false;
    // This pass can be the first code in the process to load and initialize a shared module, and
    // those lifecycle hooks are process-wide: they must close over the arguments of the command
    // that asked for the build, not over a plain build's. In particular, test isolation must not be
    // decided once by a build that is not under test.
    buildCmdLine.runArgs = effectiveGeneratedArtifactRunArgs(cmdLine());
    CommandLineParser::refreshBuildCfg(buildCmdLine);

    CompilerInstance buildCompiler(global(), buildCmdLine);
    return buildCompiler.runWorkspace(&dependencies);
}

ExitCode CompilerInstance::runWorkspace(const DependencyPlan* preparedDependencies)
{
    TaskContext    ctx(*this);
    ScopedTimedLog workspaceStage(ctx, ScopedTimedLog::Stage::Workspace);
    fs::path       workspacePath = cmdLine().workspacePath;
    fs::path       modulesPath   = workspaceModulesDirectory(workspacePath);
    Utf8           because;

    workspaceBuildLogState_  = {};
    const size_t testsBefore = Stats::get().numTests.load(std::memory_order_relaxed);

    if (FileSystem::resolveExistingFolder(modulesPath, because) != Result::Continue)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_modules_missing);
        FileSystem::setDiagnosticPath(diag, &ctx, workspacePath);
        diag.report(ctx);
        return ExitCode::CompileError;
    }

    std::vector<WorkspaceModuleBuild> modules;
    std::error_code                   ec;
    for (fs::directory_iterator it(modulesPath, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
    {
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_folder);
            FileSystem::setDiagnosticPathAndBecause(diag, &ctx, modulesPath, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        const fs::directory_entry& entry = *it;
        if (shouldSkipWorkspaceEntry(entry))
            continue;

        WorkspaceModuleBuild moduleBuild;
        moduleBuild.moduleDir  = FileSystem::normalizePath(entry.path());
        moduleBuild.moduleFile = (moduleBuild.moduleDir / "module.swg").lexically_normal();
        moduleBuild.sourceDir  = (moduleBuild.moduleDir / "src").lexically_normal();
        moduleBuild.name       = moduleBuild.moduleDir.filename().string();

        if (FileSystem::resolveExistingFile(moduleBuild.moduleFile, because) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_module_file_missing);
            FileSystem::setDiagnosticPath(diag, &ctx, moduleBuild.moduleDir);
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        if (FileSystem::resolveExistingFolder(moduleBuild.sourceDir, because) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_module_src_missing);
            FileSystem::setDiagnosticPath(diag, &ctx, moduleBuild.moduleDir);
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        modules.push_back(std::move(moduleBuild));
    }

    std::ranges::sort(modules, {}, &WorkspaceModuleBuild::name);
    if (modules.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return ExitCode::CompileError;
    }

    std::unordered_map<Utf8, size_t> moduleIndices;
    moduleIndices.reserve(modules.size());
    for (size_t i = 0; i < modules.size(); ++i)
        moduleIndices.emplace(modules[i].name, i);

    // Running a module's setup means parsing and sema'ing its module.swg, including its
    // #run build-configuration block on the main JIT thread. That is the dominant cost of a
    // workspace command, so when a module filter is active we only snapshot the requested
    // module and the transitive closure of its workspace dependencies, discovered lazily by
    // following each module's imports as it is snapshotted. Every other module stays
    // filtered out and is never set up.
    std::set<Utf8> requestedModules = cmdLine().workspaceModuleSelection;
    if (!cmdLine().workspaceModuleFilter.empty())
        requestedModules.insert(cmdLine().workspaceModuleFilter);

    const bool          hasFilter = !requestedModules.empty();
    std::vector<size_t> requestedModuleIndices;
    std::vector<size_t> snapshotOrder;
    std::vector         snapshotQueued(modules.size(), false);
    if (hasFilter)
    {
        for (const Utf8& requestedModule : requestedModules)
        {
            const auto it = moduleIndices.find(requestedModule);
            if (it == moduleIndices.end())
            {
                Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_requested_module_missing);
                FileSystem::setDiagnosticPath(diag, &ctx, cmdLine().workspacePath);
                diag.addArgument(Diagnostic::ARG_SYM, requestedModule);
                diag.report(ctx);
                return ExitCode::CompileError;
            }

            requestedModuleIndices.push_back(it->second);
            snapshotOrder.push_back(it->second);
            snapshotQueued[it->second] = true;
        }

        for (auto& module : modules)
            module.filteredOut = true;
    }
    else
    {
        snapshotOrder.reserve(modules.size());
        for (size_t i = 0; i < modules.size(); ++i)
        {
            snapshotOrder.push_back(i);
            snapshotQueued[i] = true;
        }
    }

    for (size_t cursor = 0; cursor < snapshotOrder.size(); ++cursor)
    {
        WorkspaceModuleBuild& moduleBuild = modules[snapshotOrder[cursor]];
        if (hasFilter)
            moduleBuild.filteredOut = false;

        CommandLine setupCmdLine = cmdLine();
        setupCmdLine.workspacePath.clear();
        setupCmdLine.modulePath     = moduleBuild.moduleDir;
        setupCmdLine.moduleFilePath = moduleBuild.moduleFile;
        setupCmdLine.directories.clear();
        setupCmdLine.files.clear();
        CommandLineParser::refreshBuildCfg(setupCmdLine);

        if (captureModuleSetupSnapshot(ctx, setupCmdLine, moduleBuild.setup) != Result::Continue)
            return ExitCode::CompileError;

        moduleBuild.ignoreInWorkspace = moduleBuild.setup.buildCfg.ignoreInWorkspace;
        for (const ModuleSetupImport& importRequest : moduleBuild.setup.imports)
        {
            if (!importRequest.location.empty())
                continue;

            const auto depIt = moduleIndices.find(importRequest.moduleName);
            if (depIt == moduleIndices.end())
                continue;

            moduleBuild.workspaceDependencies.push_back(importRequest.moduleName);
            if (hasFilter && !snapshotQueued[depIt->second])
            {
                snapshotQueued[depIt->second] = true;
                snapshotOrder.push_back(depIt->second);
            }
        }
    }

    for (const size_t requestedModuleIndex : requestedModuleIndices)
    {
        if (!modules[requestedModuleIndex].ignoreInWorkspace)
            continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_requested_module_ignored);
        diag.addArgument(Diagnostic::ARG_SYM, modules[requestedModuleIndex].name);
        diag.report(ctx);
        return ExitCode::CompileError;
    }

    for (const WorkspaceModuleBuild& moduleBuild : modules)
    {
        if (!isWorkspaceModuleActive(moduleBuild))
            continue;

        for (const Utf8& dependency : moduleBuild.workspaceDependencies)
        {
            const WorkspaceModuleBuild& dependencyModule = modules[moduleIndices.at(dependency)];
            if (!dependencyModule.ignoreInWorkspace)
                continue;

            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_ignored_dependency);
            diag.addArgument(Diagnostic::ARG_SYM, moduleBuild.name);
            diag.addArgument(Diagnostic::ARG_TARGET, dependency);
            diag.report(ctx);
            return ExitCode::CompileError;
        }
    }

    std::vector<uint32_t>            indegree(modules.size(), 0);
    std::vector<std::vector<size_t>> dependents(modules.size());
    size_t                           activeModuleCount   = 0;
    size_t                           filteredModuleCount = 0;
    size_t                           ignoredModuleCount  = 0;
    for (size_t i = 0; i < modules.size(); ++i)
    {
        if (modules[i].ignoreInWorkspace)
        {
            ignoredModuleCount++;
            continue;
        }
        if (modules[i].filteredOut)
        {
            filteredModuleCount++;
            continue;
        }

        activeModuleCount++;
        for (const Utf8& dependency : modules[i].workspaceDependencies)
        {
            const size_t dependencyIndex = moduleIndices.at(dependency);
            if (modules[dependencyIndex].ignoreInWorkspace)
                continue;

            indegree[i]++;
            dependents[dependencyIndex].push_back(i);
        }
    }

    workspaceBuildLogState_.discoveredModules = modules.size();
    workspaceBuildLogState_.activeModules     = activeModuleCount;
    workspaceBuildLogState_.filteredModules   = filteredModuleCount;
    workspaceBuildLogState_.ignoredModules    = ignoredModuleCount;
    workspaceStage.setStat(formatWorkspaceStageStat(ctx, workspaceBuildLogState_));

    DependencyPlan ownedDependencies;
    if (!preparedDependencies)
    {
        std::vector<ModuleSetupImport> externalImports;
        for (const WorkspaceModuleBuild& moduleBuild : modules)
        {
            if (!isWorkspaceModuleActive(moduleBuild))
                continue;
            for (const ModuleSetupImport& importRequest : moduleBuild.setup.imports)
            {
                if (!importRequest.location.empty())
                    externalImports.push_back(importRequest);
            }
        }

        if (prepareDependencyPlan(ctx, ownedDependencies, externalImports) != Result::Continue)
            return ExitCode::CompileError;
        preparedDependencies = &ownedDependencies;
    }
    SWC_ASSERT(preparedDependencies);

    // Test and documentation compiles consume native dependency artifacts without publishing their
    // own. Build the selected workspace first so both commands read complete artifacts from
    // '.output'. The build is artifact-cached, and a workspace whose active modules do not import
    // one another skips it.
    if (cmdLine().command == CommandKind::Test || cmdLine().command == CommandKind::Doc)
    {
        bool hasActiveWorkspaceDependency = false;
        for (size_t i = 0; i < modules.size() && !hasActiveWorkspaceDependency; ++i)
        {
            if (!isWorkspaceModuleActive(modules[i]))
                continue;
            for (const size_t dependentIndex : dependents[i])
                hasActiveWorkspaceDependency = hasActiveWorkspaceDependency || isWorkspaceModuleActive(modules[dependentIndex]);
        }

        if (hasActiveWorkspaceDependency)
        {
            const ExitCode buildExitCode = runWorkspacePublishPass(*preparedDependencies);
            if (buildExitCode != ExitCode::Success)
                return buildExitCode;
        }
    }

    // A workspace narrowed down to a single module reads like a plain build, so it gets the same
    // phase-by-phase report. Any wider selection keeps one summary line per module. The choice is
    // scoped because this function nests: a standard-library dependency built on demand runs a
    // whole workspace build in the middle of an enclosing command, and its verbosity must not
    // leak into the run that triggered it.
    const Logger::ScopedStagesDetailed stagesDetailedScope(global().logger(), activeModuleCount == 1);

    std::vector<size_t> buildOrder;
    buildOrder.reserve(activeModuleCount);
    std::vector scheduled(modules.size(), false);
    while (buildOrder.size() < activeModuleCount)
    {
        size_t nextIndex = static_cast<size_t>(-1);
        for (size_t i = 0; i < modules.size(); ++i)
        {
            if (!isWorkspaceModuleActive(modules[i]) || scheduled[i] || indegree[i] != 0)
                continue;

            nextIndex = i;
            break;
        }

        if (std::cmp_equal(nextIndex, -1))
        {
            for (size_t i = 0; i < modules.size(); ++i)
            {
                if (!isWorkspaceModuleActive(modules[i]) || scheduled[i])
                    continue;

                Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_dependency_cycle);
                diag.addArgument(Diagnostic::ARG_SYM, modules[i].name);
                diag.report(ctx);
                return ExitCode::CompileError;
            }

            break;
        }

        scheduled[nextIndex] = true;
        buildOrder.push_back(nextIndex);
        for (const size_t dependentIndex : dependents[nextIndex])
        {
            SWC_ASSERT(indegree[dependentIndex] > 0);
            indegree[dependentIndex]--;
        }
    }

    // Module compilation runs serially in dependency order, but each module's link is launched on a
    // background thread so it overlaps the next module's compilation. A module reads its dependencies'
    // link artifacts while resolving imports during setup, so a pending dependency link is joined
    // before its dependent starts. This is a depth-1 pipeline: at most one link is in flight, which
    // bounds the extra peak memory to a single retained module compiler.
    std::unique_ptr<WorkspaceModuleLink> pendingLink;

    const auto joinPendingLink = [&]() -> Result {
        if (!pendingLink)
            return Result::Continue;
        const std::unique_ptr<WorkspaceModuleLink> link = std::move(pendingLink);
        return finalizeWorkspaceModuleLink(*link);
    };

    const uint32_t buildCount = static_cast<uint32_t>(buildOrder.size());
    for (uint32_t buildIndex = 0; buildIndex < buildCount; ++buildIndex)
    {
        const size_t                moduleIndex = buildOrder[buildIndex];
        const WorkspaceModuleBuild& moduleBuild = modules[moduleIndex];

        if (pendingLink &&
            std::ranges::find(moduleBuild.workspaceDependencies, pendingLink->moduleName) != moduleBuild.workspaceDependencies.end() &&
            joinPendingLink() != Result::Continue)
            return ExitCode::CompileError;

        // A documentation leaf renders directly from its in-memory symbols. Only modules with
        // active dependents need an API file for a later module to import.
        const bool                           importableArtifact = moduleBuild.setup.buildCfg.backendKind != Runtime::BuildCfgBackendKind::Executable;
        const bool                           writeModuleApi      = importableArtifact && (cmdLine().command != CommandKind::Doc || !dependents[moduleIndex].empty());
        std::unique_ptr<WorkspaceModuleLink> modulePending;
        bool                                 compiled = false;
        if (runWorkspaceModule(moduleBuild, *preparedDependencies, buildIndex + 1, buildCount, writeModuleApi, compiled, modulePending) != Result::Continue)
            return ExitCode::CompileError;

        if (modulePending)
        {
            // Drain the previous in-flight link (it overlapped this module's compilation) before
            // launching this one, keeping the pipeline depth at one.
            if (joinPendingLink() != Result::Continue)
                return ExitCode::CompileError;

            modulePending->launchLink();
            pendingLink = std::move(modulePending);
        }

        workspaceBuildLogState_.builtModules++;
        if (compiled)
            workspaceBuildLogState_.compiledModules++;
        workspaceStage.setStat(formatWorkspaceStageStat(ctx, workspaceBuildLogState_));
    }

    if (joinPendingLink() != Result::Continue)
        return ExitCode::CompileError;

    if (cmdLine().command == CommandKind::Test && !cmdLine().testFileFilter.empty() && Stats::get().numTests.load(std::memory_order_relaxed) == testsBefore)
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_test_file_filter_no_match);
        diag.report(ctx);
        return ExitCode::CompileError;
    }

    if (cmdLine().workspaceDependencyBuild && workspaceBuildLogState_.compiledModules == 0)
        workspaceStage.dismiss();

    return Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
}

Result CompilerInstance::runWorkspaceModule(const WorkspaceModuleBuild& moduleBuild, const DependencyPlan& dependencies, const uint32_t moduleOrdinal, const uint32_t moduleCount, const bool writeModuleApi, bool& outCompiled, std::unique_ptr<WorkspaceModuleLink>& outPending) const
{
    outPending.reset();
    outCompiled = false;

    CommandLine moduleCmdLine    = cmdLine();
    moduleCmdLine.modulePath     = moduleBuild.moduleDir;
    moduleCmdLine.moduleFilePath = moduleBuild.moduleFile;
    moduleCmdLine.directories.clear();
    moduleCmdLine.directories.insert(moduleBuild.sourceDir);
    moduleCmdLine.files.clear();
    moduleCmdLine.outDir  = workspaceModuleOutputDirectory(cmdLine().workspacePath, moduleBuild.name, moduleCmdLine, moduleBuild.setup.buildCfg.backendKind, false);
    moduleCmdLine.workDir = workspaceModuleOutputDirectory(cmdLine().workspacePath, moduleBuild.name, moduleCmdLine, moduleBuild.setup.buildCfg.backendKind, true);
    // Executables do not publish an API. Keeping their output directory here lets the module API
    // pass remove files left by an older compiler before suppressing the export.
    if (writeModuleApi || moduleBuild.setup.buildCfg.backendKind == Runtime::BuildCfgBackendKind::Executable)
        moduleCmdLine.exportApiDir = moduleCmdLine.outDir;
    else
        moduleCmdLine.exportApiDir.clear();
    moduleCmdLine.outDirExplicit  = true;
    moduleCmdLine.workDirExplicit = true;
    moduleCmdLine.outDirStorage   = Utf8(moduleCmdLine.outDir);
    moduleCmdLine.workDirStorage  = Utf8(moduleCmdLine.workDir);
    CommandLineParser::refreshBuildCfg(moduleCmdLine);

    const WorkspaceModuleLogState workspaceLogState = {
        .name    = moduleBuild.name,
        .ordinal = moduleOrdinal,
        .total   = moduleCount,
    };

    if (shouldTryReuseWorkspaceArtifacts(moduleCmdLine))
    {
        std::vector<fs::path> currentInputs;
        collectWorkspaceModuleInputs(currentInputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles, moduleBuild.setup.compilerInputFiles, {});

        CompilerInstance probeCompiler(global(), moduleCmdLine);
        probeCompiler.precomputedModuleSetup_    = &moduleBuild.setup;
        probeCompiler.precomputedDependencyPlan_ = &dependencies;
        probeCompiler.workspaceModuleLogState_   = workspaceLogState;

        TaskContext probeCtx(probeCompiler);
        if (probeCompiler.prepareModuleBuildConfig(probeCtx) != Result::Continue)
            return Result::Error;

        std::vector<fs::path> requiredArtifacts;
        fs::path              testArtifactPath;
        fs::path              unexpectedPdbPath;
        const bool            needsRequiredArtifact  = moduleCmdLine.command == CommandKind::Build || isRunLikeCommand(moduleCmdLine.command);
        const bool            needsTestArtifactProbe = moduleCmdLine.command == CommandKind::Test && probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable;
        if ((needsRequiredArtifact || needsTestArtifactProbe) &&
            Runtime::backendKindProducesNativeArtifact(probeCompiler.buildCfg().backendKind))
        {
            NativeBackendBuilder        nativeProbeBuilder(probeCompiler, false);
            const NativeArtifactBuilder artifactProbeBuilder(nativeProbeBuilder);
            NativeArtifactPaths         artifactPaths;
            artifactProbeBuilder.queryPaths(artifactPaths);
            if (!probeCompiler.buildCfg().backend.debugInfo &&
                (probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable ||
                 probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::SharedLibrary))
                unexpectedPdbPath = artifactPaths.pdbPath;
            if (needsRequiredArtifact)
            {
                requiredArtifacts.push_back(artifactPaths.artifactPath);
                if (probeCompiler.buildCfg().backend.debugInfo &&
                    (probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable ||
                     probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::SharedLibrary))
                    requiredArtifacts.push_back(artifactPaths.pdbPath);
                probeCompiler.setLastArtifactLabel(artifactPaths.artifactPath.filename().empty() ? Utf8(artifactPaths.artifactPath) : Utf8(artifactPaths.artifactPath.filename()));
            }
            else
            {
                testArtifactPath = artifactPaths.artifactPath;
            }
        }

        std::vector<fs::path> currentDependencyDirs;
        if (probeCompiler.collectWorkspaceModuleDependencyDirs(probeCtx, currentDependencyDirs, dependencies, moduleBuild.setup.imports) != Result::Continue)
            return Result::Error;

        WorkspaceArtifactManifest manifest;
        const fs::path            manifestPath = workspaceArtifactManifestPath(moduleCmdLine.outDir, moduleCmdLine);
        std::error_code           unexpectedPdbError;
        const bool                hasUnexpectedPdb = !unexpectedPdbPath.empty() && fs::exists(unexpectedPdbPath, unexpectedPdbError);
        if (!hasUnexpectedPdb && !unexpectedPdbError &&
            readWorkspaceArtifactManifest(manifest, manifestPath) &&
            workspaceArtifactsAreUpToDate(manifest, moduleCmdLine.outDir, manifestPath, exeFullName_, currentInputs, currentDependencyDirs, requiredArtifacts, probeCompiler.buildCfg().backend.debugInfo))
        {
            const bool     runReusedTestArtifact = !testArtifactPath.empty() && workspaceManifestContainsArtifact(manifest, moduleCmdLine.outDir, testArtifactPath);
            ScopedTimedLog moduleStage(probeCtx, ScopedTimedLog::Stage::Module);
            bool           moduleSetupApplied = false;
            if (moduleBuild.setup.buildCfg.publishDependencies && probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
            {
                if (probeCompiler.applyModuleSetupInputs(probeCtx, moduleBuild.setup) != Result::Continue)
                    return Result::Error;
                moduleSetupApplied = true;

                NativeBackendBuilder publishBuilder(probeCompiler, false);
                if (publishBuilder.publishExistingArtifact() != Result::Continue)
                    return Result::Error;
            }

            if (isRunLikeCommand(moduleCmdLine.command))
            {
                if (probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
                {
                    if (!moduleSetupApplied && probeCompiler.applyModuleSetupInputs(probeCtx, moduleBuild.setup) != Result::Continue)
                        return Result::Error;

                    NativeBackendBuilder runBuilder(probeCompiler, true);
                    if (runBuilder.runExistingArtifact() != Result::Continue)
                        return Result::Error;
                }
            }

            if (runReusedTestArtifact)
            {
                if (!moduleSetupApplied && probeCompiler.applyModuleSetupInputs(probeCtx, moduleBuild.setup) != Result::Continue)
                    return Result::Error;

                NativeBackendBuilder testBuilder(probeCompiler, true);
                const Result         testResult = testBuilder.runExistingArtifact();

                // The successful compile that wrote the manifest already checked the static
                // test count. The reused artifact's fresh tally proves that it ran again.
                Stats::get().numTests.fetch_add(testBuilder.nativeTestsExecuted, std::memory_order_relaxed);
                Stats::get().numTestsFailed.fetch_add(testBuilder.nativeTestsFailed, std::memory_order_relaxed);
                if (testResult != Result::Continue)
                    return Result::Error;
            }

            if (moduleCmdLine.workspaceDependencyBuild)
                moduleStage.dismiss();
            else
            {
                moduleStage.markUpToDate();
                moduleStage.setStat(formatWorkspaceReuseStat(probeCtx, probeCompiler));
            }
            return Result::Continue;
        }
    }

    const uint64_t errorsBefore = Stats::getNumErrors();

    // The compiler outlives this call when its link is deferred (the builder holds a pointer to it,
    // and the compiler holds a pointer to the CommandLine), so both are heap-owned and handed to the
    // caller in the pending link. Native-artifact builds run only the build half here and leave a
    // prepared link to be executed off the main thread.
    auto moduleCmdLineOwned                    = std::make_unique<CommandLine>(moduleCmdLine);
    auto moduleCompiler                        = std::make_unique<CompilerInstance>(global(), *moduleCmdLineOwned);
    moduleCompiler->precomputedModuleSetup_    = &moduleBuild.setup;
    moduleCompiler->precomputedDependencyPlan_ = &dependencies;
    moduleCompiler->workspaceModuleLogState_   = workspaceLogState;
    moduleCompiler->setDeferNativeLink(true);
    outCompiled = true;

    std::unique_ptr<NativeBackendBuilder> deferredBuilder;
    {
        TaskContext    moduleCtx(*moduleCompiler);
        ScopedTimedLog moduleStage(moduleCtx, ScopedTimedLog::Stage::Module);
        moduleCompiler->processCommand();
        if (moduleCompiler->flushGeneratedSourceDumps(moduleCtx) != Result::Continue)
            return Result::Error;
        moduleStage.setStat(formatWorkspaceModuleStageStat(moduleCtx, *moduleCompiler, moduleStage.delta()));
        const bool commandFailed = Stats::getNumErrors() != errorsBefore;

        deferredBuilder = moduleCompiler->takeDeferredBuilder();
        if (!deferredBuilder)
        {
            // No deferred link to finalize (non-native backend, or a test run): finalize synchronously,
            // exactly as before. The artifacts, if any, were already produced by processCommand.
            // A test executable is a successful build even when running it reports a failing
            // test. Persist that build manifest so the next test run reuses and re-executes the
            // same artifact, exactly as `run` reuses an executable whose program returned nonzero.
            if (shouldWriteWorkspaceArtifactManifest(*moduleCompiler) && (!commandFailed || moduleCompiler->nativeArtifactBuilt()))
            {
                WorkspaceArtifactManifest manifest;
                manifest.debugInfo = moduleCompiler->buildCfg().backend.debugInfo;
                collectWorkspaceModuleInputs(manifest.inputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles, moduleBuild.setup.compilerInputFiles, moduleCompiler->compilerInputFiles_);
                if (moduleCompiler->collectWorkspaceModuleDependencyDirs(moduleCtx, manifest.dependencyDirs, dependencies, moduleBuild.setup.imports) != Result::Continue)
                    return Result::Error;
                collectWorkspaceOutputArtifacts(manifest.artifacts, moduleCmdLine.outDir);
                if (writeWorkspaceArtifactManifest(moduleCtx, manifest, workspaceArtifactManifestPath(moduleCmdLine.outDir, moduleCmdLine)) != Result::Continue)
                    return Result::Error;
            }

            return commandFailed ? Result::Error : Result::Continue;
        }

        if (commandFailed)
            return Result::Error;

        // Capture the manifest inputs now, while the compiler state is fully available; the artifact
        // list and the manifest write happen once the background link finishes (finalizeWorkspaceModuleLink).
        auto link           = std::make_unique<WorkspaceModuleLink>();
        link->moduleName    = moduleBuild.name;
        link->outDir        = moduleCmdLine.outDir;
        link->manifestPath  = workspaceArtifactManifestPath(moduleCmdLine.outDir, moduleCmdLine);
        link->writeManifest = shouldWriteWorkspaceArtifactManifest(*moduleCompiler);
        if (link->writeManifest)
        {
            link->manifest.debugInfo = moduleCompiler->buildCfg().backend.debugInfo;
            collectWorkspaceModuleInputs(link->manifest.inputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles, moduleBuild.setup.compilerInputFiles, moduleCompiler->compilerInputFiles_);
            if (moduleCompiler->collectWorkspaceModuleDependencyDirs(moduleCtx, link->manifest.dependencyDirs, dependencies, moduleBuild.setup.imports) != Result::Continue)
                return Result::Error;
        }

        link->builder  = std::move(deferredBuilder);
        link->compiler = std::move(moduleCompiler);
        link->cmdLine  = std::move(moduleCmdLineOwned);
        outPending     = std::move(link);
    }

    return Result::Continue;
}

Result CompilerInstance::registerModuleSetupImport(const std::string_view moduleName, const std::string_view location, const std::string_view version, const Runtime::BuildCfgBackendKind linkBackendKind)
{
    if (moduleName.empty())
        return Result::Continue;

    fs::path baseDir;
    if (!modulePathFile_.empty())
        baseDir = modulePathFile_.parent_path();
    else if (!cmdLine().moduleFilePath.empty())
        baseDir = cmdLine().moduleFilePath.parent_path();
    else
        baseDir = FileSystem::currentPathNoThrow();

    if (!baseDir.empty())
        baseDir = FileSystem::normalizePath(baseDir);

    for (const ModuleSetupImport& existingImport : moduleSetupImports_)
    {
        if (existingImport.moduleName == moduleName &&
            existingImport.location == location &&
            existingImport.version == version &&
            FileSystem::pathEquals(existingImport.baseDir, baseDir) &&
            existingImport.linkBackendKind == linkBackendKind)
            return Result::Continue;
    }

    ModuleSetupImport importRequest;
    importRequest.moduleName      = moduleName;
    importRequest.location        = location;
    importRequest.version         = version;
    importRequest.baseDir         = std::move(baseDir);
    importRequest.linkBackendKind = linkBackendKind;
    moduleSetupImports_.push_back(std::move(importRequest));
    return Result::Continue;
}

Result CompilerInstance::registerModuleSetupLoad(const fs::path& filePath)
{
    if (filePath.empty())
        return Result::Continue;

    moduleSetupLoadedFiles_.insert(FileSystem::normalizePath(filePath));
    return Result::Continue;
}

void CompilerInstance::registerCompilerInputFile(const fs::path& filePath)
{
    if (filePath.empty())
        return;

    compilerInputFiles_.insert(FileSystem::normalizePath(filePath));
}

void CompilerInstance::registerImportedDependencyLinkDir(const fs::path& path)
{
    if (path.empty())
        return;

    const fs::path normalizedPath = FileSystem::normalizePath(path);
    if (!importedDependencyLinkDirSet_.insert(normalizedPath).second)
        return;

    importedDependencyLinkDirs_.push_back(normalizedPath);
}

void CompilerInstance::registerImportedSharedModuleDir(const fs::path& path)
{
    if (path.empty())
        return;

    externalModuleMgr().registerSearchPath(FileSystem::normalizePath(path));
}

// Imported interfaces name their origin module ('core'); dependency resolution may have
// selected a differently named artifact for it — 'core.test' when a test compile binds
// the test variants of its dependencies. Names that are not imports answer unchanged,
// so foreign system modules ('kernel32') pass through.
std::string_view CompilerInstance::runtimeImportLinkName(const std::string_view moduleName) const
{
    for (const NativeRuntimeImport& runtimeImport : nativeRuntimeImports_)
    {
        if (runtimeImport.moduleName.view() == moduleName)
            return runtimeImport.linkModuleName.view();
    }

    return moduleName;
}

void CompilerInstance::adoptBuildCfg(const Runtime::BuildCfg& buildCfg)
{
    buildCfg_ = buildCfg;
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
}

Result CompilerInstance::adoptModuleBuildCfg(TaskContext& ctx, const Runtime::BuildCfg& buildCfg)
{
    adoptBuildCfg(buildCfg);
    reapplyExplicitBuildCfgOverrides(buildCfg_, cmdLine());
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);

    struct WarningField
    {
        const Runtime::String* value;
        WarningLevel           level;
        std::string_view       name;
    };

    // Read in this order, so the last field that names a warning decides it.
    const WarningField fields[] = {
        {&buildCfg_.warnings.asErrors, WarningLevel::Error, "asErrors"},
        {&buildCfg_.warnings.asWarnings, WarningLevel::Warning, "asWarnings"},
        {&buildCfg_.warnings.disabled, WarningLevel::Disable, "disabled"},
    };

    warningPolicy_.reset();

    for (const WarningField& field : fields)
    {
        if (!field.value->ptr || !field.value->length)
            continue;

        const std::string_view    names   = {field.value->ptr, field.value->length};
        const std::optional<Utf8> unknown = warningPolicy_.addList(names, field.level);
        if (!unknown.has_value())
            continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_build_cfg_unknown_warning);
        diag.addArgument(Diagnostic::ARG_ARG, field.name);
        diag.addArgument(Diagnostic::ARG_VALUE, unknown.value());
        diag.addDidYouMeanNote(Utf8Helper::bestMatch(unknown.value(), WarningPolicy::allIdNames()));
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

// Adds the files a setup '#load' named and that have not been read yet, parses them, and returns
// them ready for semantic analysis.
//
// They are flagged like the setup file itself, so their own '#import' and '#load' are directives
// the setup pass acts on rather than statements it refuses.
Result CompilerInstance::collectModuleSetupLoadedFiles(TaskContext& ctx, const std::set<fs::path>& alreadyRead, std::vector<SourceFile*>& outFiles)
{
    const Global&     global   = ctx.global();
    JobManager&       jobMgr   = global.jobMgr();
    const JobClientId clientId = jobClientId();

    std::vector<SourceFile*> added;
    for (const fs::path& filePath : moduleSetupLoadedFiles_)
    {
        const fs::path normalizedPath = FileSystem::normalizePath(filePath);
        if (alreadyRead.contains(normalizedPath) || hasResolvedFilePath(normalizedPath))
            continue;

        SourceFile& file = addResolvedFile(normalizedPath, FileFlagsE::Module | FileFlagsE::SetupLoaded);
        added.push_back(&file);
    }

    if (added.empty())
        return Result::Continue;

    const uint64_t errorsBefore = Stats::getNumErrors();
    for (SourceFile* file : added)
    {
        auto* job = makeJob<ParserJob>(ctx, file);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    jobMgr.waitAll(clientId);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    for (SourceFile* file : added)
    {
        const SourceView& srcView = file->ast().srcView();
        if (srcView.mustSkip() || !srcView.runsSema() || file->hasError())
            continue;
        outFiles.push_back(file);
    }

    return Result::Continue;
}

Result CompilerInstance::captureModuleSetupSnapshot(const TaskContext& ctx, const CommandLine& setupCmdLine, ModuleSetupSnapshot& outSnapshot) const
{
    SWC_UNUSED(ctx);
    outSnapshot = {};
    CompilerInstance setupCompiler(global(), setupCmdLine);
    setupCompiler.moduleSetupMode_ = true;
    struct ConstCallCacheResetGuard
    {
        ~ConstCallCacheResetGuard()
        {
            SemaJIT::clearConstCallCache();
        }
    } constCallCacheResetGuard;

    TaskContext setupCtx(setupCompiler);
    SWC_RESULT(setupCompiler.collectFiles(setupCtx));

    const Global&     global       = setupCtx.global();
    JobManager&       jobMgr       = global.jobMgr();
    const JobClientId clientId     = setupCompiler.jobClientId();
    const uint64_t    errorsBefore = Stats::getNumErrors();

    for (SourceFile* file : setupCompiler.files())
    {
        auto* job = setupCompiler.makeJob<ParserJob>(setupCtx, file);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    jobMgr.waitAll(clientId);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    std::vector<SourceFile*> files;
    files.reserve(setupCompiler.files().size());
    for (SourceFile* file : setupCompiler.files())
    {
        const SourceView& srcView = file->ast().srcView();
        if (srcView.mustSkip())
            continue;
        if (!srcView.runsSema())
            continue;
        if (file->hasError())
            continue;
        files.push_back(file);
    }

    if (files.empty())
    {
        outSnapshot.buildCfg           = setupCompiler.buildCfg();
        outSnapshot.imports            = setupCompiler.moduleSetupImports_;
        outSnapshot.loadedFiles        = setupCompiler.moduleSetupLoadedFiles_;
        outSnapshot.compilerInputFiles = setupCompiler.compilerInputFiles_;
        ownBuildCfgStrings(outSnapshot.buildCfg, outSnapshot.ownedStrings);
        return Result::Continue;
    }

    SWC_RESULT(setupCompiler.setupSema(setupCtx));

    auto*      symModule           = Symbol::make<SymbolModule>(setupCtx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    const Utf8 moduleNamespaceName = buildModuleNamespaceName(setupCompiler);

    constexpr SymbolFlags namespaceFlags  = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
    const IdentifierRef   idRef           = setupCtx.idMgr().addIdentifierOwned(moduleNamespaceName, Math::hash(moduleNamespaceName));
    auto*                 moduleNamespace = Symbol::make<SymbolNamespace>(setupCtx, nullptr, TokenRef::invalid(), idRef, namespaceFlags);
    symModule->addSingleSymbol(setupCtx, moduleNamespace);
    setupCompiler.setSymModule(symModule);

    // Empty-named root namespace hosting symbols imported from other modules (see importRootNamespace).
    // Owned by the module symbol (like the module namespace) so it is treated as a module-root when
    // collecting namespace paths (collectSymbolMapNamespacePath) and contributes no name prefix.
    auto* importRootNamespace = Symbol::make<SymbolNamespace>(setupCtx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), namespaceFlags);
    importRootNamespace->setOwnerSymMap(symModule);
    setupCompiler.setImportRootNamespace(importRootNamespace);

    // '#load' nests: a loaded file states its own imports and loads, and they are only known once
    // that file has been read. So each round sema's what is known and then looks at what it
    // discovered; a round that discovers nothing new ends the walk. A file is added once, which is
    // what makes a cycle between two files that load each other terminate rather than spin.
    std::set<fs::path> semaDone;
    while (!files.empty())
    {
        for (SourceFile* file : files)
        {
            semaDone.insert(FileSystem::normalizePath(file->path()));
            file->setModuleNamespace(*moduleNamespace);
            auto* job = setupCompiler.makeJob<SemaJob>(setupCtx, file->nodePayloadContext(), true);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        for (SourceFile* file : files)
        {
            auto* job = setupCompiler.makeJob<SemaJob>(setupCtx, file->nodePayloadContext(), false);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        Sema::waitDone(setupCtx, clientId);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        files.clear();
        SWC_RESULT(setupCompiler.collectModuleSetupLoadedFiles(setupCtx, semaDone, files));
    }

    outSnapshot.buildCfg           = setupCompiler.buildCfg();
    outSnapshot.imports            = setupCompiler.moduleSetupImports_;
    outSnapshot.loadedFiles        = setupCompiler.moduleSetupLoadedFiles_;
    outSnapshot.compilerInputFiles = setupCompiler.compilerInputFiles_;
    ownBuildCfgStrings(outSnapshot.buildCfg, outSnapshot.ownedStrings);
    return Result::Continue;
}

Result CompilerInstance::applyModuleSetupInputs(TaskContext& ctx, const ModuleSetupSnapshot& setupSnapshot)
{
    SWC_ASSERT(precomputedDependencyPlan_);
    ModuleSetupInputApplier applier(*this, ctx);
    return applier.apply(setupSnapshot, *precomputedDependencyPlan_);
}

Result CompilerInstance::resolveModuleInputPaths(TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();
    if (!cmdLine.moduleFilePath.empty())
    {
        if (modulePathFile_.empty())
        {
            modulePathFile_ = cmdLine.moduleFilePath;
            SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        }

        return Result::Continue;
    }

    if (cmdLine.modulePath.empty())
        return Result::Continue;

    if (modulePathFile_.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
    }

    if (modulePathSrc_.empty())
    {
        modulePathSrc_ = cmdLine.modulePath / "src";
        Utf8 because;
        if (FileSystem::resolveExistingFolder(modulePathSrc_, because) != Result::Continue)
            modulePathSrc_.clear();
    }

    return Result::Continue;
}

Result CompilerInstance::runModuleSetup(TaskContext& ctx)
{
    SWC_RESULT(resolveModuleInputPaths(ctx));
    if (modulePathFile_.empty() || cmdLine().moduleFilePath.empty())
        return Result::Continue;

    if (precomputedModuleSetup_)
    {
        SWC_RESULT(adoptModuleBuildCfg(ctx, precomputedModuleSetup_->buildCfg));
        return applyModuleSetupInputs(ctx, *precomputedModuleSetup_);
    }

    CommandLine setupCmdLine = cmdLine();
    setupCmdLine.directories.clear();
    setupCmdLine.files.clear();
    setupCmdLine.importApiModules.clear();
    setupCmdLine.importApiDirs.clear();
    setupCmdLine.importApiFiles.clear();
    setupCmdLine.exportApiDir.clear();
    setupCmdLine.moduleFilePath = modulePathFile_;
    setupCmdLine.modulePath     = modulePathFile_.parent_path();
    CommandLineParser::refreshBuildCfg(setupCmdLine);

    ModuleSetupSnapshot setupSnapshot;
    SWC_RESULT(captureModuleSetupSnapshot(ctx, setupCmdLine, setupSnapshot));
    SWC_RESULT(adoptModuleBuildCfg(ctx, setupSnapshot.buildCfg));
    ownedDependencyPlan_ = std::make_unique<DependencyPlan>();
    SWC_RESULT(prepareDependencyPlan(ctx, *ownedDependencyPlan_, setupSnapshot.imports));
    precomputedDependencyPlan_ = ownedDependencyPlan_.get();
    return applyModuleSetupInputs(ctx, setupSnapshot);
}

// Adopts the module build configuration without applying its input set. This is the cheap
// half of runModuleSetup: it makes buildCfg() (backend kind, debug info, artifact naming)
// available so the workspace up-to-date probe can compute artifact paths, but it skips
// applyModuleSetupInputs/processImports, which would recursively re-parse and sema every
// transitive dependency's metadata file just to register imports the probe never uses.
Result CompilerInstance::prepareModuleBuildConfig(TaskContext& ctx)
{
    SWC_RESULT(resolveModuleInputPaths(ctx));
    if (modulePathFile_.empty() || cmdLine().moduleFilePath.empty())
        return Result::Continue;

    SWC_ASSERT(precomputedModuleSetup_ != nullptr);
    return adoptModuleBuildCfg(ctx, precomputedModuleSetup_->buildCfg);
}

void CompilerInstance::appendResolvedFiles(std::vector<fs::path>& paths, FileFlags flags, const std::string_view apiModuleName)
{
    if (paths.empty())
        return;

    files_.reserve(files_.size() + paths.size());
    for (fs::path& path : paths)
    {
        if (hasResolvedFilePath(path))
            continue;
        addResolvedFile(std::move(path), flags).setApiModuleName(apiModuleName);
    }
}

void CompilerInstance::collectFolderFiles(const fs::path& folder, FileFlags flags, const bool canFilter)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, canFilter);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, flags);
}

// A generated public API file sits at '<module>/<backend>/<build-cfg>/<arch>/<file>', so the
// module it describes is the fourth directory above it. An explicit '--import-api-file' carries
// no import request to read that name from, and every entry of a module API resolves its foreign
// module through it.
Utf8 CompilerInstance::apiModuleNameFromPath(const fs::path& file)
{
    fs::path dir = file.parent_path();
    for (uint32_t level = 0; level < 3; ++level)
        dir = dir.parent_path();

    return dir.has_filename() ? Utf8(dir.filename().string().c_str()) : Utf8{};
}

void CompilerInstance::collectImportedApiFolderFiles(const fs::path& folder, const std::string_view moduleName)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, false);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, FileFlagsE::ImportedApi, moduleName);
}

Result CompilerInstance::collectImportedApiFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();

    if (!cmdLine.importApiModules.empty())
    {
        fs::path dependencyRoot;
        SWC_RESULT(resolveSwagStdOutputRoot(dependencyRoot, ctx));
        dependencyRoot = (dependencyRoot / "dep").lexically_normal();
        for (const Utf8& moduleName : cmdLine.importApiModules)
        {
            fs::path importDir;
            auto     importBackendKind = Runtime::BuildCfgBackendKind::None;
            Utf8     because;
            if (findDependencyConfigurationDirectory(importDir, because, dependencyRoot, moduleName.view(), cmdLine, &importBackendKind) != Result::Continue)
                return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, moduleName.view()), because);

            collectImportedApiFolderFiles(importDir, moduleName.view());
            fs::path sharedDir;
            if (findDependencyConfigurationDirectoryForBackend(sharedDir, because, dependencyRoot, moduleName.view(), cmdLine, Runtime::BuildCfgBackendKind::SharedLibrary) == Result::Continue)
            {
                registerImportedSharedModuleDir(sharedDir);
                registerImportedDependencyLinkDir(sharedDir);
            }
            else if (importBackendKind == Runtime::BuildCfgBackendKind::StaticLibrary)
            {
                registerImportedDependencyLinkDir(importDir);
            }
        }
    }

    if (cmdLine.importApiFiles.empty())
        return Result::Continue;

    files_.reserve(files_.size() + cmdLine.importApiFiles.size());
    for (const fs::path& file : cmdLine.importApiFiles)
    {
        if (hasResolvedFilePath(file))
            continue;
        addResolvedFile(file, FileFlagsE::ImportedApi).setApiModuleName(apiModuleNameFromPath(file).view());
        if (file.has_parent_path())
            registerImportedDependencyLinkDir(file.parent_path());
    }

    return Result::Continue;
}

Result CompilerInstance::collectFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine        = ctx.cmdLine();
    const FileFlags    directSrcFlags = cmdLine.moduleFilePath.empty() ? FileFlagsE::CustomSrc : FileFlagsE::ModuleSrc;

    // Collect direct folders from the command line
    for (const fs::path& folder : cmdLine.directories)
        collectFolderFiles(folder, directSrcFlags, true);

    // Collect direct files from the command line
    if (!cmdLine.files.empty())
    {
        files_.reserve(files_.size() + cmdLine.files.size());
        for (const fs::path& file : cmdLine.files)
        {
            if (hasResolvedFilePath(file))
                continue;
            addResolvedFile(file, directSrcFlags);
        }
    }

    // Collect files for the module
    SWC_RESULT(resolveModuleInputPaths(ctx));
    if (!modulePathFile_.empty())
    {
        if (!hasResolvedFilePath(modulePathFile_))
            addResolvedFile(modulePathFile_, FileFlagsE::Module);
    }
    if (!cmdLine.modulePath.empty())
    {
        if (!modulePathSrc_.empty())
            collectFolderFiles(modulePathSrc_, FileFlagsE::ModuleSrc, true);
    }

    SWC_RESULT(collectImportedApiFiles(ctx));

    // Collect runtime files. The runtime bootstrap (which declares compiler intrinsics such
    // as `@compiler`) must always be part of the input set, including the module-setup pass
    // that runs module-setup directives and `#run` blocks, so those blocks can reach it too.
    {
        fs::path runtimePath = FileSystem::compilerResourceRoot(exeFullName_) / "runtime";
        SWC_RESULT(FileSystem::resolveFolder(ctx, runtimePath));
        collectFolderFiles(runtimePath, FileFlagsE::Runtime, false);
    }

    srcViews_.reserve(files_.size());

    if (files_.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

Result CompilerInstance::exportModuleApi(TaskContext& ctx)
{
    return ModuleApi::exportFiles(ctx);
}

SWC_END_NAMESPACE();
