#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/ModuleApi.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/ScopedTimedAction.h"
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
        buildCfg.sanity                     = explicitBuildCfg.sanity;
        buildCfg.allocatorCaptureStack      = explicitBuildCfg.allocatorCaptureStack;
        buildCfg.allocatorLeaks             = explicitBuildCfg.allocatorLeaks;
        buildCfg.allocatorTrackAllocations  = explicitBuildCfg.allocatorTrackAllocations;
        buildCfg.allocatorElectricMode      = explicitBuildCfg.allocatorElectricMode;
        buildCfg.allocatorFillMemory        = explicitBuildCfg.allocatorFillMemory;
        buildCfg.errorStackTrace            = explicitBuildCfg.errorStackTrace;
        buildCfg.backend.optimize           = explicitBuildCfg.backend.optimize;
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
        ownBuildCfgString(buildCfg.warnAsErrors, newOwnedStrings);
        ownBuildCfgString(buildCfg.warnAsWarning, newOwnedStrings);
        ownBuildCfgString(buildCfg.warnAsDisabled, newOwnedStrings);
        ownBuildCfgString(buildCfg.linkerArgs, newOwnedStrings);
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
        ownBuildCfgString(buildCfg.genDoc.outputExtension, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.titleToc, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.titleContent, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.css, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.icon, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.startHead, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.endHead, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.startBody, newOwnedStrings);
        ownBuildCfgString(buildCfg.genDoc.endBody, newOwnedStrings);
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

    fs::path workspaceOutputDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".output").lexically_normal();
    }

    fs::path workspaceDependencyDirectory(const fs::path& workspacePath)
    {
        return (workspacePath / ".dep").lexically_normal();
    }

    fs::path workspaceModuleOutputDirectory(const fs::path& workspacePath, const Utf8& moduleName, const CommandLine& cmdLine, const Runtime::BuildCfgBackendKind backendKind, const bool workDirectory)
    {
        fs::path result = workDirectory ? (workspacePath / ".tmp") : workspaceOutputDirectory(workspacePath);
        result /= fs::path(moduleName.c_str());
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

    Result resolveSwagStdOutputRoot(fs::path& outRoot, TaskContext& ctx)
    {
        outRoot.clear();

        const std::optional<Utf8> installRoot = Os::readEnvironmentVariable("SWAG_PATH");
        if (!installRoot.has_value() || installRoot->empty())
            return reportInvalidFolder(ctx, "SWAG_PATH", "environment variable is not defined");

        outRoot = fs::path(installRoot->c_str());
        SWC_RESULT(FileSystem::resolveFolder(ctx, outRoot));
        outRoot = (outRoot / "std" / ".output").lexically_normal();
        return Result::Continue;
    }

    Result reportWorkspaceDependencySyncFailure(TaskContext& ctx, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_dependency_sync_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, path, because);
        diag.report(ctx);
        return Result::Error;
    }

    bool pathIsCurrentOrParentDirectory(const fs::path& path)
    {
        return path == "." || path == "..";
    }

    bool workspaceDependencyFilesHaveSameContent(const fs::path& lhsPath, const fs::path& rhsPath)
    {
        FileSystem::IoErrorInfo ioError;
        std::vector<std::byte>  lhsData;
        if (FileSystem::readBinaryFile(lhsPath, lhsData, ioError) != Result::Continue)
            return false;

        std::vector<std::byte> rhsData;
        if (FileSystem::readBinaryFile(rhsPath, rhsData, ioError) != Result::Continue)
            return false;

        return lhsData == rhsData;
    }

    bool shouldCopyWorkspaceDependencyFile(const fs::path& srcPath, const fs::path& dstPath)
    {
        std::error_code ec;
        const bool      dstExists = fs::exists(dstPath, ec);
        if (ec || !dstExists)
            return true;

        ec.clear();
        if (!fs::is_regular_file(dstPath, ec) || ec)
            return true;

        ec.clear();
        const uintmax_t srcSize = fs::file_size(srcPath, ec);
        if (ec)
            return true;

        ec.clear();
        const uintmax_t dstSize = fs::file_size(dstPath, ec);
        if (ec || srcSize != dstSize)
            return true;

        ec.clear();
        const auto srcTime = fs::last_write_time(srcPath, ec);
        if (ec)
            return true;

        ec.clear();
        const auto dstTime = fs::last_write_time(dstPath, ec);
        if (ec)
            return true;

        if (srcTime != dstTime)
            return true;

        return !workspaceDependencyFilesHaveSameContent(srcPath, dstPath);
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

            if (!shouldCopyWorkspaceDependencyFile(it->path(), dstPath))
                continue;

            const fs::path dstParent = dstPath.parent_path();
            if (!dstParent.empty())
                SWC_RESULT(ensureWorkspaceDependencyDirectory(ctx, ensuredDirs, dstParent));

            fs::copy_file(it->path(), dstPath, fs::copy_options::overwrite_existing, ec);
            if (ec)
                return reportWorkspaceDependencySyncFailure(ctx, dstPath, FileSystem::normalizeSystemMessage(ec));

            ec.clear();
            const auto srcTime = fs::last_write_time(it->path(), ec);
            if (!ec)
            {
                ec.clear();
                fs::last_write_time(dstPath, srcTime, ec);
                if (ec)
                    return reportWorkspaceDependencySyncFailure(ctx, dstPath, FileSystem::normalizeSystemMessage(ec));
            }
        }

        std::vector<fs::path> stalePaths;
        for (fs::recursive_directory_iterator it(normalizedDstDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return reportWorkspaceDependencySyncFailure(ctx, normalizedDstDir, FileSystem::normalizeSystemMessage(ec));

            const fs::path relativePath = it->path().lexically_relative(normalizedDstDir);
            if (relativePath.empty() || pathIsCurrentOrParentDirectory(relativePath))
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

    void appendUniqueModules(std::vector<Utf8>& outModules, std::unordered_set<Utf8>& ioSeenModules, std::span<const Utf8> modules)
    {
        for (const Utf8& moduleName : modules)
        {
            if (!ioSeenModules.insert(moduleName).second)
                continue;
            outModules.push_back(moduleName);
        }
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

    fs::path dependencyImportMetadataPath(const fs::path& apiDir, std::string_view moduleName)
    {
        fs::path result = apiDir / fs::path(std::string(moduleName));
        result.replace_extension(".deps");
        return result.lexically_normal();
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
        if (workspaceLogState.activeModules)
        {
            if (workspaceLogState.builtModules < workspaceLogState.activeModules)
                parts.push_back(TimedActionLog::formatStatRatio(ctx, workspaceLogState.builtModules, workspaceLogState.activeModules, "module"));
            else
                parts.push_back(TimedActionLog::formatStatCount(ctx, workspaceLogState.activeModules, "module"));
        }
        else if (workspaceLogState.discoveredModules)
        {
            parts.push_back(TimedActionLog::formatStatCount(ctx, workspaceLogState.discoveredModules, "module"));
        }

        return TimedActionLog::joinStatItems(ctx, parts);
    }

    Utf8 formatWorkspaceModuleStageStat(const TaskContext& ctx, const CompilerInstance& compiler, const TimedActionLog::StatsSnapshot& deltaSnapshot)
    {
        std::vector<Utf8> parts;
        if (deltaSnapshot.numFiles)
            parts.push_back(TimedActionLog::formatStatCount(ctx, deltaSnapshot.numFiles, "file"));

        const Utf8& artifactLabel = compiler.lastArtifactLabel();
        if (!artifactLabel.empty())
            parts.push_back(TimedActionLog::formatStatName(ctx, artifactLabel));

        return TimedActionLog::joinStatItems(ctx, parts);
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
    };

    fs::path workspaceArtifactManifestPath(const fs::path& outDir)
    {
        return (outDir / fs::path(std::string(K_WORKSPACE_ARTIFACT_MANIFEST_FILE))).lexically_normal();
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

    void collectWorkspaceModuleInputs(std::vector<fs::path>& outInputs, const CommandLine& cmdLine, const fs::path& moduleFile, const fs::path& sourceDir, const std::set<fs::path>& loadedFiles)
    {
        outInputs.clear();
        if (!moduleFile.empty())
            outInputs.push_back(moduleFile);

        if (!sourceDir.empty())
            collectSwagFilesRec(cmdLine, sourceDir, outInputs, true);

        outInputs.reserve(outInputs.size() + loadedFiles.size());
        for (const fs::path& filePath : loadedFiles)
            outInputs.push_back(filePath);

        normalizeWorkspacePaths(outInputs);
    }

    void collectWorkspaceOutputArtifacts(std::vector<fs::path>& outArtifacts, const fs::path& outDir)
    {
        outArtifacts.clear();
        if (outDir.empty())
            return;

        const fs::path  manifestPath = workspaceArtifactManifestPath(outDir);
        std::error_code ec;
        for (fs::recursive_directory_iterator it(outDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return;

            ec.clear();
            if (!it->is_regular_file(ec) || ec)
                continue;

            const fs::path normalizedPath = FileSystem::normalizePath(it->path());
            if (FileSystem::pathEquals(normalizedPath, manifestPath))
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

            if (line == "version=1")
            {
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
        return true;
    }

    Result writeWorkspaceArtifactManifest(TaskContext& ctx, const WorkspaceArtifactManifest& manifest, const fs::path& manifestPath)
    {
        Utf8 content = "version=1\n[inputs]\n";
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

        FileSystem::IoErrorInfo ioError;
        if (FileSystem::writeBinaryFile(manifestPath, content.data(), content.size(), ioError) == Result::Continue)
            return Result::Continue;

        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_api_file_write_failed);
        FileSystem::setDiagnosticPathAndBecause(diag, &ctx, manifestPath, FileSystem::describeIoFailure(ioError));
        diag.report(ctx);
        return Result::Error;
    }

    bool workspaceArtifactsAreUpToDate(const WorkspaceArtifactManifest& manifest, const fs::path& outDir, const fs::path& compilerPath, const std::span<const fs::path> currentInputs, const std::span<const fs::path> currentDependencyDirs, const std::span<const fs::path> requiredArtifacts)
    {
        if (!sameWorkspacePathList(manifest.inputs, currentInputs))
            return false;
        if (!sameWorkspacePathList(manifest.dependencyDirs, currentDependencyDirs))
            return false;

        fs::file_time_type latestInputTime{};
        bool               hasInputTime = false;
        for (const fs::path& path : currentInputs)
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
        if (!tryGetWorkspacePathWriteTime(compilerTime, compilerPath))
            return false;

        fs::file_time_type latestDependencyTime{};
        bool               hasDependencyTime = false;
        for (const fs::path& dependencyDir : currentDependencyDirs)
        {
            fs::file_time_type dependencyTime;
            if (!tryCollectLatestWorkspaceTreeWriteTime(dependencyTime, dependencyDir))
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
        const fs::path     manifestPath = workspaceArtifactManifestPath(outDir);
        if (!tryGetWorkspacePathWriteTime(buildTime, manifestPath))
            return false;

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

        return cmdLine.command != CommandKind::Test;
    }

    Utf8 formatWorkspaceReuseStat(const TaskContext& ctx, const CompilerInstance& compiler)
    {
        std::vector<Utf8> parts;
        parts.push_back(TimedActionLog::formatStatName(ctx, "up-to-date"));
        if (!compiler.lastArtifactLabel().empty())
            parts.push_back(TimedActionLog::formatStatName(ctx, compiler.lastArtifactLabel()));
        return TimedActionLog::joinStatItems(ctx, parts);
    }
}

struct ModuleSetupInputApplier
{
    struct ResolvedModuleImportPaths
    {
        fs::path                     apiDir;
        Runtime::BuildCfgBackendKind apiBackendKind = Runtime::BuildCfgBackendKind::None;
        fs::path                     linkDir;
        fs::path                     sharedDir;
        fs::path                     dependencyRoot;
    };

    explicit ModuleSetupInputApplier(CompilerInstance& compilerInstance, TaskContext& taskContext);

    Result apply(const CompilerInstance::ModuleSetupSnapshot& setupSnapshot);
    Result resolveExplicitDependencyRoot(fs::path& outRoot, const CompilerInstance::ModuleSetupImport& importRequest) const;
    Result resolveLinkAndSharedDirs(ResolvedModuleImportPaths& outPaths, const fs::path& dependencyRoot, const CompilerInstance::ModuleSetupImport& importRequest) const;
    Result mirrorWorkspaceDependencyDir(fs::path& ioDir, const fs::path& sourceDependencyRoot);
    Result resolveDependencyImportDir(ResolvedModuleImportPaths& outPaths, const CompilerInstance::ModuleSetupImport& importRequest, const fs::path* preferredDependencyRoot);
    Result captureDependencyImportSnapshot(const fs::path& depsFile, CompilerInstance::ModuleSetupSnapshot& outSnapshot) const;
    Result collectDependencyClosure(std::vector<Utf8>& outModules, std::span<const CompilerInstance::ModuleSetupImport> imports, const fs::path* preferredDependencyRoot);
    Result processImports(std::span<const CompilerInstance::ModuleSetupImport> imports, const fs::path* preferredDependencyRoot, bool recordDirectImports);

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

    CompilerInstance*                           compiler = nullptr;
    TaskContext*                                ctx      = nullptr;
    fs::path                                    workspaceDependencyRoot;
    std::unordered_set<Utf8>                    mirroredDependencyDirs;
    std::unordered_map<Utf8, std::vector<Utf8>> dependencyClosureCache;
    std::unordered_set<Utf8>                    processedDependencyApis;
};

ModuleSetupInputApplier::ModuleSetupInputApplier(CompilerInstance& compilerInstance, TaskContext& taskContext)
{
    compiler = &compilerInstance;
    ctx      = &taskContext;
    if (!instance().cmdLine().workspacePath.empty())
        workspaceDependencyRoot = FileSystem::normalizePath(workspaceDependencyDirectory(instance().cmdLine().workspacePath));
}

Result ModuleSetupInputApplier::apply(const CompilerInstance::ModuleSetupSnapshot& setupSnapshot)
{
    instance().moduleSetupImports_ = setupSnapshot.imports;
    instance().nativeRuntimeImports_.clear();
    instance().moduleSetupLoadedFiles_ = setupSnapshot.loadedFiles;

    SWC_RESULT(processImports(setupSnapshot.imports, nullptr, true));

    for (const fs::path& filePath : setupSnapshot.loadedFiles)
    {
        fs::path resolvedPath = filePath;
        SWC_RESULT(FileSystem::resolveFile(taskCtx(), resolvedPath));
        if (instance().hasResolvedFilePath(resolvedPath))
            continue;

        instance().addResolvedFile(resolvedPath, FileFlagsE::ModuleSrc);
    }

    return Result::Continue;
}

Result ModuleSetupInputApplier::resolveExplicitDependencyRoot(fs::path& outRoot, const CompilerInstance::ModuleSetupImport& importRequest) const
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

Result ModuleSetupInputApplier::resolveLinkAndSharedDirs(ResolvedModuleImportPaths& outPaths, const fs::path& dependencyRoot, const CompilerInstance::ModuleSetupImport& importRequest) const
{
    outPaths.linkDir.clear();
    outPaths.sharedDir.clear();
    outPaths.dependencyRoot = FileSystem::normalizePath(dependencyRoot);

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

Result ModuleSetupInputApplier::mirrorWorkspaceDependencyDir(fs::path& ioDir, const fs::path& sourceDependencyRoot)
{
    if (workspaceDependencyRoot.empty() || ioDir.empty())
        return Result::Continue;

    const fs::path normalizedSourceDir  = FileSystem::normalizePath(ioDir);
    const fs::path normalizedSourceRoot = FileSystem::normalizePath(sourceDependencyRoot);
    if (FileSystem::pathEquals(normalizedSourceRoot, workspaceDependencyRoot))
    {
        ioDir = normalizedSourceDir;
        return Result::Continue;
    }

    if (!FileSystem::pathStartsWith(normalizedSourceDir, normalizedSourceRoot))
    {
        const Utf8 because = std::format("dependency folder '{}' is not under root '{}'", Utf8(normalizedSourceDir).c_str(), Utf8(normalizedSourceRoot).c_str());
        return reportWorkspaceDependencySyncFailure(taskCtx(), normalizedSourceDir, because);
    }

    const fs::path relativePath = normalizedSourceDir.lexically_relative(normalizedSourceRoot);
    if (relativePath.empty() || pathIsCurrentOrParentDirectory(relativePath))
    {
        const Utf8 because = std::format("cannot mirror dependency folder '{}' from root '{}'", Utf8(normalizedSourceDir).c_str(), Utf8(normalizedSourceRoot).c_str());
        return reportWorkspaceDependencySyncFailure(taskCtx(), normalizedSourceDir, because);
    }

    fs::path   destinationDir = (workspaceDependencyRoot / relativePath).lexically_normal();
    const Utf8 mirrorKey      = std::format("{}|{}", Utf8(normalizedSourceDir).c_str(), Utf8(destinationDir).c_str());
    if (mirroredDependencyDirs.insert(mirrorKey).second)
        SWC_RESULT(syncWorkspaceDependencyDirectory(taskCtx(), normalizedSourceDir, destinationDir));

    ioDir = std::move(destinationDir);
    return Result::Continue;
}

Result ModuleSetupInputApplier::resolveDependencyImportDir(ResolvedModuleImportPaths& outPaths, const CompilerInstance::ModuleSetupImport& importRequest, const fs::path* preferredDependencyRoot)
{
    outPaths = {};

    if (!importRequest.location.empty())
    {
        fs::path dependencyRoot;
        SWC_RESULT(resolveExplicitDependencyRoot(dependencyRoot, importRequest));

        Utf8 because;
        if (findDependencyConfigurationDirectory(outPaths.apiDir, because, dependencyRoot, importRequest.moduleName.view(), instance().cmdLine(), &outPaths.apiBackendKind) != Result::Continue)
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
            const fs::path dependencyRoot = workspaceOutputDirectory(instance().cmdLine().workspacePath);
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

Result ModuleSetupInputApplier::captureDependencyImportSnapshot(const fs::path& depsFile, CompilerInstance::ModuleSetupSnapshot& outSnapshot) const
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

Result ModuleSetupInputApplier::collectDependencyClosure(std::vector<Utf8>& outModules, std::span<const CompilerInstance::ModuleSetupImport> imports, const fs::path* preferredDependencyRoot)
{
    std::unordered_set seenModules(outModules.begin(), outModules.end());
    for (const CompilerInstance::ModuleSetupImport& importRequest : imports)
    {
        if (seenModules.insert(importRequest.moduleName).second)
            outModules.push_back(importRequest.moduleName);

        ResolvedModuleImportPaths importPaths;
        SWC_RESULT(resolveDependencyImportDir(importPaths, importRequest, preferredDependencyRoot));
        if (importPaths.apiDir.empty())
            continue;

        const auto cacheKey = Utf8(FileSystem::normalizePath(importPaths.apiDir));
        const auto cacheIt  = dependencyClosureCache.find(cacheKey);
        if (cacheIt != dependencyClosureCache.end())
        {
            appendUniqueModules(outModules, seenModules, cacheIt->second);
            continue;
        }

        fs::path depsFile = dependencyImportMetadataPath(importPaths.apiDir, importRequest.moduleName.view());
        Utf8     because;
        if (FileSystem::resolveExistingFile(depsFile, because) != Result::Continue)
        {
            dependencyClosureCache.emplace(cacheKey, std::vector<Utf8>{});
            continue;
        }

        CompilerInstance::ModuleSetupSnapshot nestedSnapshot;
        SWC_RESULT(captureDependencyImportSnapshot(depsFile, nestedSnapshot));

        std::vector<Utf8> nestedModules;
        const fs::path    sourceDependencyRoot = importPaths.dependencyRoot;
        SWC_RESULT(collectDependencyClosure(nestedModules, nestedSnapshot.imports, &sourceDependencyRoot));
        const auto [insertedIt, inserted] = dependencyClosureCache.emplace(cacheKey, std::move(nestedModules));
        appendUniqueModules(outModules, seenModules, insertedIt->second);
        SWC_UNUSED(inserted);
    }

    return Result::Continue;
}

Result ModuleSetupInputApplier::processImports(std::span<const CompilerInstance::ModuleSetupImport> imports, const fs::path* preferredDependencyRoot, const bool recordDirectImports)
{
    for (const CompilerInstance::ModuleSetupImport& importRequest : imports)
    {
        ResolvedModuleImportPaths importPaths;
        SWC_RESULT(resolveDependencyImportDir(importPaths, importRequest, preferredDependencyRoot));
        const fs::path sourceDependencyRoot = importPaths.dependencyRoot;
        if (!workspaceDependencyRoot.empty())
        {
            SWC_RESULT(mirrorWorkspaceDependencyDir(importPaths.apiDir, importPaths.dependencyRoot));
            SWC_RESULT(mirrorWorkspaceDependencyDir(importPaths.linkDir, importPaths.dependencyRoot));
            SWC_RESULT(mirrorWorkspaceDependencyDir(importPaths.sharedDir, importPaths.dependencyRoot));
            importPaths.dependencyRoot = workspaceDependencyRoot;
        }

        instance().collectImportedApiFolderFiles(importPaths.apiDir);
        instance().registerImportedDependencyLinkDir(importPaths.linkDir);
        instance().registerImportedSharedModuleDir(importPaths.sharedDir);

        fs::path                              depsFile = dependencyImportMetadataPath(importPaths.apiDir, importRequest.moduleName.view());
        Utf8                                  because;
        CompilerInstance::ModuleSetupSnapshot nestedSnapshot;
        const bool                            hasDepsFile = FileSystem::resolveExistingFile(depsFile, because) == Result::Continue;
        if (hasDepsFile)
            SWC_RESULT(captureDependencyImportSnapshot(depsFile, nestedSnapshot));

        if (recordDirectImports && !importPaths.linkDir.empty())
        {
            CompilerInstance::NativeRuntimeImport runtimeImport;
            runtimeImport.moduleName           = importRequest.moduleName;
            runtimeImport.linkModuleName       = resolveDependencyLinkModuleName(importPaths.linkDir, importRequest.moduleName.view());
            runtimeImport.hasSharedRuntimeHook = !importPaths.sharedDir.empty();
            if (hasDepsFile)
                SWC_RESULT(collectDependencyClosure(runtimeImport.transitiveImports, nestedSnapshot.imports, &sourceDependencyRoot));
            instance().nativeRuntimeImports_.push_back(std::move(runtimeImport));
        }

        const auto apiDirKey = Utf8(FileSystem::normalizePath(importPaths.apiDir));
        if (!processedDependencyApis.insert(apiDirKey).second)
            continue;
        if (!hasDepsFile)
            continue;

        SWC_RESULT(processImports(nestedSnapshot.imports, &sourceDependencyRoot, false));
    }

    return Result::Continue;
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
    Result collectWorkspaceModuleDependencyDirs(std::vector<fs::path>& outDirs, CompilerInstance& compiler, TaskContext& ctx, std::span<const CompilerInstance::ModuleSetupImport> imports)
    {
        outDirs.clear();
        ModuleSetupInputApplier applier(compiler, ctx);
        outDirs.reserve(imports.size() * 3);
        for (const CompilerInstance::ModuleSetupImport& importRequest : imports)
        {
            ModuleSetupInputApplier::ResolvedModuleImportPaths importPaths;
            if (applier.resolveDependencyImportDir(importPaths, importRequest, nullptr) != Result::Continue)
                return Result::Error;

            if (!importPaths.apiDir.empty())
                outDirs.push_back(importPaths.apiDir);
            if (!importPaths.linkDir.empty())
                outDirs.push_back(importPaths.linkDir);
            if (!importPaths.sharedDir.empty())
                outDirs.push_back(importPaths.sharedDir);
        }

        normalizeWorkspacePaths(outDirs);
        return Result::Continue;
    }

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

ExitCode CompilerInstance::runWorkspace()
{
    TaskContext                 ctx(*this);
    TimedActionLog::ScopedStage workspaceStage(ctx, TimedActionLog::Stage::Workspace);
    fs::path                    workspacePath = cmdLine().workspacePath;
    fs::path                    modulesPath   = workspaceModulesDirectory(workspacePath);
    Utf8                        because;

    workspaceBuildLogState_ = {};

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
    const bool          hasFilter         = !cmdLine().workspaceModuleFilter.empty();
    size_t              filterTargetIndex = static_cast<size_t>(-1);
    std::vector<size_t> snapshotOrder;
    std::vector         snapshotQueued(modules.size(), false);
    if (hasFilter)
    {
        const auto it = moduleIndices.find(cmdLine().workspaceModuleFilter);
        if (it == moduleIndices.end())
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_requested_module_missing);
            FileSystem::setDiagnosticPath(diag, &ctx, cmdLine().workspacePath);
            diag.addArgument(Diagnostic::ARG_SYM, cmdLine().workspaceModuleFilter);
            diag.report(ctx);
            return ExitCode::CompileError;
        }

        filterTargetIndex = it->second;
        snapshotOrder.push_back(it->second);
        snapshotQueued[it->second] = true;
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

    if (hasFilter && modules[filterTargetIndex].ignoreInWorkspace)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_workspace_requested_module_ignored);
        diag.addArgument(Diagnostic::ARG_SYM, modules[filterTargetIndex].name);
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

    // Module compilation runs serially in dependency order, but each module's external link is
    // launched on a background thread so it overlaps the next module's (CPU-bound) compilation
    // instead of stalling every worker while link.exe runs. A module reads its dependencies' link
    // artifacts while resolving imports during setup, so a pending dependency link is joined before
    // its dependent starts. This is a depth-1 pipeline: at most one link is in flight, which bounds
    // the extra peak memory to a single retained module compiler.
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

        std::unique_ptr<WorkspaceModuleLink> modulePending;
        if (runWorkspaceModule(moduleBuild, buildIndex + 1, buildCount, modulePending) != Result::Continue)
            return ExitCode::CompileError;

        if (modulePending)
        {
            // Drain the previous in-flight link (it overlapped this module's compilation) before
            // launching this one, keeping the pipeline depth at one.
            if (joinPendingLink() != Result::Continue)
                return ExitCode::CompileError;

            modulePending->launchLink();
            pendingLink = std::move(modulePending);

            // The external toolchain (--external-link) shells out to link.exe, whose PDB engine
            // (mspdbsrv) is unreliable when several links run at once or overlap the next module's
            // codegen. Force a strictly serial, one-at-a-time link by draining it before continuing.
            if (cmdLine().externalLink && joinPendingLink() != Result::Continue)
                return ExitCode::CompileError;
        }

        workspaceBuildLogState_.builtModules++;
        workspaceStage.setStat(formatWorkspaceStageStat(ctx, workspaceBuildLogState_));
    }

    if (joinPendingLink() != Result::Continue)
        return ExitCode::CompileError;

    return Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
}

Result CompilerInstance::runWorkspaceModule(const WorkspaceModuleBuild& moduleBuild, const uint32_t moduleIndex, const uint32_t moduleCount, std::unique_ptr<WorkspaceModuleLink>& outPending) const
{
    outPending.reset();

    CommandLine moduleCmdLine    = cmdLine();
    moduleCmdLine.modulePath     = moduleBuild.moduleDir;
    moduleCmdLine.moduleFilePath = moduleBuild.moduleFile;
    moduleCmdLine.directories.clear();
    moduleCmdLine.directories.insert(moduleBuild.sourceDir);
    moduleCmdLine.files.clear();
    moduleCmdLine.outDir          = workspaceModuleOutputDirectory(cmdLine().workspacePath, moduleBuild.name, moduleCmdLine, moduleBuild.setup.buildCfg.backendKind, false);
    moduleCmdLine.workDir         = workspaceModuleOutputDirectory(cmdLine().workspacePath, moduleBuild.name, moduleCmdLine, moduleBuild.setup.buildCfg.backendKind, true);
    moduleCmdLine.exportApiDir    = moduleCmdLine.outDir;
    moduleCmdLine.outDirExplicit  = true;
    moduleCmdLine.workDirExplicit = true;
    moduleCmdLine.outDirStorage   = Utf8(moduleCmdLine.outDir);
    moduleCmdLine.workDirStorage  = Utf8(moduleCmdLine.workDir);
    CommandLineParser::refreshBuildCfg(moduleCmdLine);

    const WorkspaceModuleLogState workspaceLogState = {
        .name  = moduleBuild.name,
        .index = moduleIndex,
        .total = moduleCount,
    };

    if (shouldTryReuseWorkspaceArtifacts(moduleCmdLine))
    {
        std::vector<fs::path> currentInputs;
        collectWorkspaceModuleInputs(currentInputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles);

        CompilerInstance probeCompiler(global(), moduleCmdLine);
        probeCompiler.precomputedModuleSetup_  = &moduleBuild.setup;
        probeCompiler.workspaceModuleLogState_ = workspaceLogState;

        TaskContext probeCtx(probeCompiler);
        if (probeCompiler.prepareModuleBuildConfig(probeCtx) != Result::Continue)
            return Result::Error;

        std::vector<fs::path> requiredArtifacts;
        if ((moduleCmdLine.command == CommandKind::Build || moduleCmdLine.command == CommandKind::Run) &&
            Runtime::backendKindProducesNativeArtifact(probeCompiler.buildCfg().backendKind))
        {
            NativeBackendBuilder        nativeProbeBuilder(probeCompiler, false);
            const NativeArtifactBuilder artifactProbeBuilder(nativeProbeBuilder);
            NativeArtifactPaths         artifactPaths;
            artifactProbeBuilder.queryPaths(artifactPaths);
            requiredArtifacts.push_back(artifactPaths.artifactPath);
            // Note: we deliberately do not require artifactPaths.pdbPath here. Debug info is embedded
            // directly into the PE image by the linker (see PELinker / DebugInfo::buildObject); no
            // standalone .pdb file is ever produced, even for debug build configs. Requiring one would
            // make every native module appear permanently stale and force a full rebuild every time.
            probeCompiler.setLastArtifactLabel(artifactPaths.artifactPath.filename().empty() ? Utf8(artifactPaths.artifactPath) : Utf8(artifactPaths.artifactPath.filename()));
        }

        std::vector<fs::path> currentDependencyDirs;
        if (collectWorkspaceModuleDependencyDirs(currentDependencyDirs, probeCompiler, probeCtx, moduleBuild.setup.imports) != Result::Continue)
            return Result::Error;

        WorkspaceArtifactManifest manifest;
        const fs::path            manifestPath = workspaceArtifactManifestPath(moduleCmdLine.outDir);
        if (readWorkspaceArtifactManifest(manifest, manifestPath) &&
            workspaceArtifactsAreUpToDate(manifest, moduleCmdLine.outDir, exeFullName_, currentInputs, currentDependencyDirs, requiredArtifacts))
        {
            TimedActionLog::ScopedStage moduleStage(probeCtx, TimedActionLog::Stage::Module);
            if (moduleCmdLine.publish && probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
            {
                if (probeCompiler.applyModuleSetupInputs(probeCtx, moduleBuild.setup) != Result::Continue)
                    return Result::Error;

                NativeBackendBuilder publishBuilder(probeCompiler, false);
                if (publishBuilder.publishExistingArtifact() != Result::Continue)
                    return Result::Error;
            }

            if (moduleCmdLine.command == CommandKind::Run)
            {
                if (probeCompiler.buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
                {
                    if (!moduleCmdLine.publish && probeCompiler.applyModuleSetupInputs(probeCtx, moduleBuild.setup) != Result::Continue)
                        return Result::Error;

                    NativeBackendBuilder runBuilder(probeCompiler, true);
                    if (runBuilder.runExistingArtifact() != Result::Continue)
                        return Result::Error;
                }
            }

            moduleStage.setStat(formatWorkspaceReuseStat(probeCtx, probeCompiler));
            return Result::Continue;
        }
    }

    const uint64_t errorsBefore = Stats::getNumErrors();

    // The compiler outlives this call when its link is deferred (the builder holds a pointer to it,
    // and the compiler holds a pointer to the CommandLine), so both are heap-owned and handed to the
    // caller in the pending link. Native-artifact builds run only the build half here and leave a
    // prepared link to be executed off the main thread.
    auto moduleCmdLineOwned                  = std::make_unique<CommandLine>(moduleCmdLine);
    auto moduleCompiler                      = std::make_unique<CompilerInstance>(global(), *moduleCmdLineOwned);
    moduleCompiler->precomputedModuleSetup_  = &moduleBuild.setup;
    moduleCompiler->workspaceModuleLogState_ = workspaceLogState;
    moduleCompiler->setDeferNativeLink(true);

    std::unique_ptr<NativeBackendBuilder> deferredBuilder;
    {
        TaskContext                 moduleCtx(*moduleCompiler);
        TimedActionLog::ScopedStage moduleStage(moduleCtx, TimedActionLog::Stage::Module);
        moduleCompiler->processCommand();
        if (moduleCompiler->flushGeneratedSourceDumps(moduleCtx) != Result::Continue)
            return Result::Error;
        moduleStage.setStat(formatWorkspaceModuleStageStat(moduleCtx, *moduleCompiler, moduleStage.delta()));
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        deferredBuilder = moduleCompiler->takeDeferredBuilder();
        if (!deferredBuilder)
        {
            // No external link to defer (non-native backend, or a test run): finalize synchronously,
            // exactly as before. The artifacts, if any, were already produced by processCommand.
            if (moduleCmdLine.command != CommandKind::Test)
            {
                WorkspaceArtifactManifest manifest;
                collectWorkspaceModuleInputs(manifest.inputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles);
                if (collectWorkspaceModuleDependencyDirs(manifest.dependencyDirs, *moduleCompiler, moduleCtx, moduleBuild.setup.imports) != Result::Continue)
                    return Result::Error;
                collectWorkspaceOutputArtifacts(manifest.artifacts, moduleCmdLine.outDir);
                if (writeWorkspaceArtifactManifest(moduleCtx, manifest, workspaceArtifactManifestPath(moduleCmdLine.outDir)) != Result::Continue)
                    return Result::Error;
            }

            return Result::Continue;
        }

        // Capture the manifest inputs now, while the compiler state is fully available; the artifact
        // list and the manifest write happen once the background link finishes (finalizeWorkspaceModuleLink).
        auto link           = std::make_unique<WorkspaceModuleLink>();
        link->moduleName    = moduleBuild.name;
        link->outDir        = moduleCmdLine.outDir;
        link->manifestPath  = workspaceArtifactManifestPath(moduleCmdLine.outDir);
        link->writeManifest = moduleCmdLine.command != CommandKind::Test;
        if (link->writeManifest)
        {
            collectWorkspaceModuleInputs(link->manifest.inputs, moduleCmdLine, moduleBuild.moduleFile, moduleBuild.sourceDir, moduleBuild.setup.loadedFiles);
            if (collectWorkspaceModuleDependencyDirs(link->manifest.dependencyDirs, *moduleCompiler, moduleCtx, moduleBuild.setup.imports) != Result::Continue)
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

void CompilerInstance::adoptBuildCfg(const Runtime::BuildCfg& buildCfg)
{
    buildCfg_ = buildCfg;
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
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
        auto* job = heapNew<ParserJob>(setupCtx, file);
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
        outSnapshot.buildCfg    = setupCompiler.buildCfg();
        outSnapshot.imports     = setupCompiler.moduleSetupImports_;
        outSnapshot.loadedFiles = setupCompiler.moduleSetupLoadedFiles_;
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

    for (SourceFile* file : files)
    {
        file->setModuleNamespace(*moduleNamespace);
        auto* job = heapNew<SemaJob>(setupCtx, file->nodePayloadContext(), true);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    jobMgr.waitAll(clientId);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    for (SourceFile* file : files)
    {
        auto* job = heapNew<SemaJob>(setupCtx, file->nodePayloadContext(), false);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    Sema::waitDone(setupCtx, clientId);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    outSnapshot.buildCfg    = setupCompiler.buildCfg();
    outSnapshot.imports     = setupCompiler.moduleSetupImports_;
    outSnapshot.loadedFiles = setupCompiler.moduleSetupLoadedFiles_;
    ownBuildCfgStrings(outSnapshot.buildCfg, outSnapshot.ownedStrings);
    return Result::Continue;
}

Result CompilerInstance::applyModuleSetupInputs(TaskContext& ctx, const ModuleSetupSnapshot& setupSnapshot)
{
    ModuleSetupInputApplier applier(*this, ctx);
    return applier.apply(setupSnapshot);
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
        adoptBuildCfg(precomputedModuleSetup_->buildCfg);
        reapplyExplicitBuildCfgOverrides(buildCfg_, cmdLine());
        ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
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
    setupCmdLine.runtime        = true;
    CommandLineParser::refreshBuildCfg(setupCmdLine);

    ModuleSetupSnapshot setupSnapshot;
    SWC_RESULT(captureModuleSetupSnapshot(ctx, setupCmdLine, setupSnapshot));
    adoptBuildCfg(setupSnapshot.buildCfg);
    reapplyExplicitBuildCfgOverrides(buildCfg_, cmdLine());
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
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
    adoptBuildCfg(precomputedModuleSetup_->buildCfg);
    reapplyExplicitBuildCfgOverrides(buildCfg_, cmdLine());
    ownBuildCfgStrings(buildCfg_, ownedBuildCfgStrings_);
    return Result::Continue;
}

void CompilerInstance::appendResolvedFiles(std::vector<fs::path>& paths, FileFlags flags)
{
    if (paths.empty())
        return;

    files_.reserve(files_.size() + paths.size());
    for (fs::path& path : paths)
    {
        if (hasResolvedFilePath(path))
            continue;
        addResolvedFile(std::move(path), flags);
    }
}

void CompilerInstance::collectFolderFiles(const fs::path& folder, FileFlags flags, const bool canFilter)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, canFilter);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, flags);
}

void CompilerInstance::collectImportedApiFolderFiles(const fs::path& folder)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, false);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, FileFlagsE::ImportedApi);
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

            collectImportedApiFolderFiles(importDir);
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
        addResolvedFile(file, FileFlagsE::ImportedApi);
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

    // Collect runtime files
    if (cmdLine.runtime)
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
