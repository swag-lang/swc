#include "pch.h"
#include "Main/CompilerInstance.h"
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
    void reapplyBuildCfgPresetOverrides(Runtime::BuildCfg& buildCfg, const Runtime::BuildCfg& explicitBuildCfg)
    {
        buildCfg.safetyGuards               = explicitBuildCfg.safetyGuards;
        buildCfg.sanity                     = explicitBuildCfg.sanity;
        buildCfg.debugAllocator             = explicitBuildCfg.debugAllocator;
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

        auto copyString = [&](Runtime::String& value) {
            if (!value.ptr || !value.length)
            {
                value = {};
                return;
            }

            auto owned   = std::make_unique<Utf8>(value);
            value.ptr    = owned->data();
            value.length = owned->size();
            newOwnedStrings.push_back(std::move(owned));
        };

        copyString(buildCfg.moduleNamespace);
        copyString(buildCfg.warnAsErrors);
        copyString(buildCfg.warnAsWarning);
        copyString(buildCfg.warnAsDisabled);
        copyString(buildCfg.linkerArgs);
        copyString(buildCfg.name);
        copyString(buildCfg.outDir);
        copyString(buildCfg.workDir);
        copyString(buildCfg.repoPath);
        copyString(buildCfg.resAppIcoFileName);
        copyString(buildCfg.resAppName);
        copyString(buildCfg.resAppDescription);
        copyString(buildCfg.resAppCompany);
        copyString(buildCfg.resAppCopyright);
        copyString(buildCfg.genDoc.outputName);
        copyString(buildCfg.genDoc.outputExtension);
        copyString(buildCfg.genDoc.titleToc);
        copyString(buildCfg.genDoc.titleContent);
        copyString(buildCfg.genDoc.css);
        copyString(buildCfg.genDoc.icon);
        copyString(buildCfg.genDoc.startHead);
        copyString(buildCfg.genDoc.endHead);
        copyString(buildCfg.genDoc.startBody);
        copyString(buildCfg.genDoc.endBody);
        copyString(buildCfg.genDoc.morePages);
        copyString(buildCfg.genDoc.quoteIconNote);
        copyString(buildCfg.genDoc.quoteIconTip);
        copyString(buildCfg.genDoc.quoteIconWarning);
        copyString(buildCfg.genDoc.quoteIconAttention);
        copyString(buildCfg.genDoc.quoteIconExample);
        copyString(buildCfg.genDoc.quoteTitleNote);
        copyString(buildCfg.genDoc.quoteTitleTip);
        copyString(buildCfg.genDoc.quoteTitleWarning);
        copyString(buildCfg.genDoc.quoteTitleAttention);
        copyString(buildCfg.genDoc.quoteTitleExample);
        copyString(buildCfg.registeredConfigs);
        ownedStrings.swap(newOwnedStrings);
    }

    Utf8 buildModuleNamespaceName(const CompilerInstance& compiler)
    {
        Utf8 moduleNamespaceName;
        const Runtime::String& moduleNamespace = compiler.buildCfg().moduleNamespace;
        if (moduleNamespace.ptr && moduleNamespace.length)
            moduleNamespaceName = Utf8{moduleNamespace};
        if (!moduleNamespaceName.empty())
            return moduleNamespaceName;

        Utf8 artifactName;
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

        std::ranges::sort(outMatches, [](const DependencyConfigCandidate& lhs, const DependencyConfigCandidate& rhs) { return lhs.path < rhs.path; });
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
        const auto selectUniqueMatch = [&](const auto& predicate, fs::path& selectedPath) -> bool {
            fs::path candidatePath;
            auto     candidateBackendKind = Runtime::BuildCfgBackendKind::None;
            for (const DependencyConfigCandidate& match : matches)
            {
                if (!predicate(match.backendKind))
                    continue;

                if (candidatePath.empty())
                {
                    candidatePath        = match.path;
                    candidateBackendKind = match.backendKind;
                    continue;
                }

                selectedPath.clear();
                return false;
            }

            if (candidatePath.empty())
                return false;

            selectedPath = std::move(candidatePath);
            if (outBackendKind)
                *outBackendKind = candidateBackendKind;
            return true;
        };

        fs::path selectedPath;
        if (selectUniqueMatch(isSharedDependencyBackendKind, selectedPath))
        {
            outDir = std::move(selectedPath);
            return Result::Continue;
        }

        if (selectUniqueMatch(isImportOnlyDependencyBackendKind, selectedPath))
        {
            outDir = std::move(selectedPath);
            return Result::Continue;
        }

        if (selectUniqueMatch(isStaticDependencyBackendKind, selectedPath))
        {
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

        if (workspaceLogState.ignoredModules)
            parts.push_back(TimedActionLog::formatStatCount(ctx, workspaceLogState.ignoredModules, "ignored module", nullptr, LogColor::Gray));

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

    std::ranges::sort(modules, [](const WorkspaceModuleBuild& lhs, const WorkspaceModuleBuild& rhs) { return lhs.name < rhs.name; });
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

    for (WorkspaceModuleBuild& moduleBuild : modules)
    {
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

            if (moduleIndices.contains(importRequest.moduleName))
                moduleBuild.workspaceDependencies.push_back(importRequest.moduleName);
        }
    }

    for (const WorkspaceModuleBuild& moduleBuild : modules)
    {
        if (moduleBuild.ignoreInWorkspace)
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
    size_t                           activeModuleCount = 0;
    for (size_t i = 0; i < modules.size(); ++i)
    {
        if (modules[i].ignoreInWorkspace)
            continue;

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
    workspaceBuildLogState_.ignoredModules    = modules.size() - activeModuleCount;
    workspaceStage.setStat(formatWorkspaceStageStat(ctx, workspaceBuildLogState_));

    std::vector<size_t> buildOrder;
    buildOrder.reserve(activeModuleCount);
    std::vector scheduled(modules.size(), false);
    while (buildOrder.size() < activeModuleCount)
    {
        size_t nextIndex = static_cast<size_t>(-1);
        for (size_t i = 0; i < modules.size(); ++i)
        {
            if (modules[i].ignoreInWorkspace || scheduled[i] || indegree[i] != 0)
                continue;

            nextIndex = i;
            break;
        }

        if (std::cmp_equal(nextIndex, -1))
        {
            for (size_t i = 0; i < modules.size(); ++i)
            {
                if (modules[i].ignoreInWorkspace || scheduled[i])
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

    const uint32_t buildCount = static_cast<uint32_t>(buildOrder.size());
    for (uint32_t buildIndex = 0; buildIndex < buildCount; ++buildIndex)
    {
        const size_t moduleIndex = buildOrder[buildIndex];
        if (runWorkspaceModule(modules[moduleIndex], buildIndex + 1, buildCount) != Result::Continue)
            return ExitCode::CompileError;

        workspaceBuildLogState_.builtModules++;
        workspaceStage.setStat(formatWorkspaceStageStat(ctx, workspaceBuildLogState_));
    }

    return Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
}

Result CompilerInstance::runWorkspaceModule(const WorkspaceModuleBuild& moduleBuild, const uint32_t moduleIndex, const uint32_t moduleCount) const
{
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

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance moduleCompiler(global(), moduleCmdLine);
    moduleCompiler.precomputedModuleSetup_  = &moduleBuild.setup;
    moduleCompiler.workspaceModuleLogState_ = WorkspaceModuleLogState{
        .name  = moduleBuild.name,
        .index = moduleIndex,
        .total = moduleCount,
    };

    const TaskContext           moduleCtx(moduleCompiler);
    TimedActionLog::ScopedStage moduleStage(moduleCtx, TimedActionLog::Stage::Module);
    moduleCompiler.processCommand();
    moduleStage.setStat(formatWorkspaceModuleStageStat(moduleCtx, moduleCompiler, moduleStage.delta()));
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    return Result::Continue;
}

Result CompilerInstance::registerModuleSetupImport(const std::string_view moduleName, const std::string_view location, const std::string_view version, const Runtime::BuildCfgBackendKind linkBackendKind)
{
    if (moduleName.empty())
        return Result::Continue;

    for (const ModuleSetupImport& existingImport : moduleSetupImports_)
    {
        if (existingImport.moduleName == moduleName &&
            existingImport.location == location &&
            existingImport.version == version &&
            existingImport.linkBackendKind == linkBackendKind)
            return Result::Continue;
    }

    ModuleSetupImport importRequest;
    importRequest.moduleName      = moduleName;
    importRequest.location        = location;
    importRequest.version         = version;
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
    if (std::ranges::find(importedDependencyLinkDirs_, normalizedPath) != importedDependencyLinkDirs_.end())
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
#if SWC_DEV_MODE
    jobMgr.assertNoWaitingJobs(clientId, "CompilerInstance::runModuleSetup parser waitAll");
#endif
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

    for (SourceFile* file : files)
    {
        file->setModuleNamespace(*moduleNamespace);
        auto* job = heapNew<SemaJob>(setupCtx, file->nodePayloadContext(), true);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    jobMgr.waitAll(clientId);
#if SWC_DEV_MODE
    jobMgr.assertNoWaitingJobs(clientId, "CompilerInstance::runModuleSetup decl waitAll");
#endif
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    for (SourceFile* file : files)
    {
        auto* job = heapNew<SemaJob>(setupCtx, file->nodePayloadContext(), false);
        jobMgr.enqueue(*job, JobPriority::Normal, clientId);
    }

    Sema::waitDone(setupCtx, clientId);
#if SWC_DEV_MODE
    jobMgr.assertNoWaitingJobs(clientId, "CompilerInstance::runModuleSetup full waitDone");
#endif
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
    moduleSetupImports_     = setupSnapshot.imports;
    moduleSetupLoadedFiles_ = setupSnapshot.loadedFiles;

    struct ResolvedModuleImportPaths
    {
        fs::path                     apiDir;
        Runtime::BuildCfgBackendKind apiBackendKind = Runtime::BuildCfgBackendKind::None;
        fs::path                     linkDir;
        fs::path                     sharedDir;
        fs::path                     dependencyRoot;
    };

    const auto resolveExplicitDependencyRoot = [&](fs::path& outRoot, const ModuleSetupImport& importRequest) -> Result {
        if (importRequest.location == "swag@std")
        {
            const std::optional<Utf8> installRoot = Os::readEnvironmentVariable("SWAG_PATH");
            if (!installRoot.has_value() || installRoot->empty())
                return reportInvalidFolder(ctx, "SWAG_PATH", "environment variable is not defined");

            outRoot = fs::path(installRoot->c_str());
            SWC_RESULT(FileSystem::resolveFolder(ctx, outRoot));
            outRoot = (outRoot / "std" / ".output").lexically_normal();
            return Result::Continue;
        }

        outRoot = fs::path(importRequest.location.c_str());
        if (outRoot.is_relative())
        {
            const fs::path baseDir = cmdLine().moduleFilePath.empty() ? FileSystem::currentPathNoThrow() : cmdLine().moduleFilePath.parent_path();
            if (!baseDir.empty())
                outRoot = (baseDir / outRoot).lexically_normal();
        }

        SWC_RESULT(FileSystem::resolveFolder(ctx, outRoot));
        return Result::Continue;
    };

    const auto resolveLinkAndSharedDirs = [&](ResolvedModuleImportPaths& outPaths, const fs::path& dependencyRoot, const ModuleSetupImport& importRequest) -> Result {
        outPaths.linkDir.clear();
        outPaths.sharedDir.clear();
        outPaths.dependencyRoot = FileSystem::normalizePath(dependencyRoot);

        Utf8     because;
        fs::path sharedDir;
        if (findDependencyConfigurationDirectoryForBackend(sharedDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), Runtime::BuildCfgBackendKind::SharedLibrary) == Result::Continue)
            outPaths.sharedDir = std::move(sharedDir);

        if (importRequest.linkBackendKind != Runtime::BuildCfgBackendKind::None)
        {
            if (findDependencyConfigurationDirectoryForBackend(outPaths.linkDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), importRequest.linkBackendKind) != Result::Continue)
                return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);
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
    };

    const auto resolveDependencyImportDir = [&](ResolvedModuleImportPaths& outPaths, const ModuleSetupImport& importRequest, const fs::path* preferredDependencyRoot) -> Result {
        outPaths = {};

        if (!importRequest.location.empty())
        {
            fs::path dependencyRoot;
            SWC_RESULT(resolveExplicitDependencyRoot(dependencyRoot, importRequest));

            Utf8 because;
            if (findDependencyConfigurationDirectory(outPaths.apiDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), &outPaths.apiBackendKind) != Result::Continue)
                return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);
            return resolveLinkAndSharedDirs(outPaths, dependencyRoot, importRequest);
        }

        if (preferredDependencyRoot && !preferredDependencyRoot->empty())
        {
            Utf8 because;
            if (findDependencyConfigurationDirectory(outPaths.apiDir, because, *preferredDependencyRoot, importRequest.moduleName.view(), cmdLine(), &outPaths.apiBackendKind) == Result::Continue)
                return resolveLinkAndSharedDirs(outPaths, *preferredDependencyRoot, importRequest);
        }

        if (!cmdLine().workspacePath.empty())
        {
            fs::path        workspaceModuleDir = workspaceModuleDirectory(cmdLine().workspacePath, importRequest.moduleName.view());
            std::error_code ec;
            if (fs::is_directory(workspaceModuleDir, ec))
            {
                const fs::path dependencyRoot = workspaceOutputDirectory(cmdLine().workspacePath);
                Utf8           because;
                if (findDependencyConfigurationDirectory(outPaths.apiDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), &outPaths.apiBackendKind) != Result::Continue)
                    return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, importRequest.moduleName.view()), because);
                return resolveLinkAndSharedDirs(outPaths, dependencyRoot, importRequest);
            }
        }

        std::vector<fs::path>                     matches;
        std::vector<Runtime::BuildCfgBackendKind> matchKinds;
        for (const fs::path& dependencyRoot : cmdLine().importApiDirs)
        {
            fs::path configDir;
            Utf8     because;
            auto     backendKind = Runtime::BuildCfgBackendKind::None;
            if (findDependencyConfigurationDirectory(configDir, because, dependencyRoot, importRequest.moduleName.view(), cmdLine(), &backendKind) != Result::Continue)
                continue;

            matches.push_back(std::move(configDir));
            matchKinds.push_back(backendKind);
        }

        std::vector<size_t> order(matches.size());
        std::iota(order.begin(), order.end(), 0);
        std::ranges::sort(order, [&](const size_t lhs, const size_t rhs) { return matches[lhs] < matches[rhs]; });

        std::vector<fs::path>                     uniqueMatches;
        std::vector<Runtime::BuildCfgBackendKind> uniqueMatchKinds;
        uniqueMatches.reserve(matches.size());
        uniqueMatchKinds.reserve(matchKinds.size());
        for (const size_t index : order)
        {
            if (!uniqueMatches.empty() && uniqueMatches.back() == matches[index])
                continue;

            uniqueMatches.push_back(matches[index]);
            uniqueMatchKinds.push_back(matchKinds[index]);
        }

        if (matches.empty())
        {
            if (cmdLine().importApiDirs.empty())
                return reportInvalidFolder(ctx, importRequest.moduleName.c_str(), "no workspace dependency was found and no --import-api-dir root was provided");

            const Utf8 because = std::format("module '{}' was not found in any dependency root for {}", importRequest.moduleName.c_str(), dependencyConfigurationLabel(cmdLine()).c_str());
            return reportInvalidFolder(ctx, importRequest.moduleName.c_str(), because);
        }

        if (uniqueMatches.size() != 1)
        {
            const Utf8 because = std::format("multiple dependency roots match {} ({})", dependencyConfigurationLabel(cmdLine()).c_str(), joinDependencyPaths(uniqueMatches).c_str());
            return reportInvalidFolder(ctx, importRequest.moduleName.c_str(), because);
        }

        outPaths.apiDir         = uniqueMatches.front();
        outPaths.apiBackendKind = uniqueMatchKinds.front();
        return resolveLinkAndSharedDirs(outPaths, dependencyRootFromConfigurationDir(outPaths.apiDir), importRequest);
    };

    const auto captureDependencyImportSnapshot = [&](const fs::path& depsFile, ModuleSetupSnapshot& outSnapshot) -> Result {
        CommandLine setupCmdLine = cmdLine();
        setupCmdLine.directories.clear();
        setupCmdLine.files.clear();
        setupCmdLine.importApiModules.clear();
        setupCmdLine.importApiFiles.clear();
        setupCmdLine.exportApiDir.clear();
        setupCmdLine.modulePath.clear();
        setupCmdLine.moduleFilePath = depsFile;
        CommandLineParser::refreshBuildCfg(setupCmdLine);
        return captureModuleSetupSnapshot(ctx, setupCmdLine, outSnapshot);
    };

    std::unordered_set<Utf8> processedDependencyApis;
    const auto               processImports = [&](auto&& self, std::span<const ModuleSetupImport> imports, const fs::path* preferredDependencyRoot) -> Result {
        for (const ModuleSetupImport& importRequest : imports)
        {
            ResolvedModuleImportPaths importPaths;
            SWC_RESULT(resolveDependencyImportDir(importPaths, importRequest, preferredDependencyRoot));
            collectFolderFiles(importPaths.apiDir, FileFlagsE::ImportedApi, false);
            registerImportedDependencyLinkDir(importPaths.linkDir);
            registerImportedSharedModuleDir(importPaths.sharedDir);

            const auto apiDirKey = Utf8(FileSystem::normalizePath(importPaths.apiDir));
            if (!processedDependencyApis.insert(apiDirKey).second)
                continue;

            fs::path            depsFile = dependencyImportMetadataPath(importPaths.apiDir, importRequest.moduleName.view());
            Utf8                because;
            ModuleSetupSnapshot nestedSnapshot;
            if (FileSystem::resolveExistingFile(depsFile, because) != Result::Continue)
                continue;

            SWC_RESULT(captureDependencyImportSnapshot(depsFile, nestedSnapshot));
            SWC_RESULT(self(self, nestedSnapshot.imports, &importPaths.dependencyRoot));
        }

        return Result::Continue;
    };

    SWC_RESULT(processImports(processImports, setupSnapshot.imports, nullptr));

    for (const fs::path& filePath : setupSnapshot.loadedFiles)
    {
        fs::path resolvedPath = filePath;
        SWC_RESULT(FileSystem::resolveFile(ctx, resolvedPath));
        if (hasResolvedFilePath(resolvedPath))
            continue;

        addResolvedFile(resolvedPath, FileFlagsE::ModuleSrc);
    }

    return Result::Continue;
}

Result CompilerInstance::runModuleSetup(TaskContext& ctx)
{
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

Result CompilerInstance::collectImportedApiFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();

    if (!cmdLine.importApiModules.empty())
    {
        const fs::path dependencyRoot = (FileSystem::compilerResourceRoot(exeFullName_) / "std" / ".output" / "dep").lexically_normal();
        for (const Utf8& moduleName : cmdLine.importApiModules)
        {
            fs::path importDir;
            auto     importBackendKind = Runtime::BuildCfgBackendKind::None;
            Utf8     because;
            if (findDependencyConfigurationDirectory(importDir, because, dependencyRoot, moduleName.view(), cmdLine, &importBackendKind) != Result::Continue)
                return reportInvalidFolder(ctx, dependencyModuleDirectory(dependencyRoot, moduleName.view()), because);

            collectFolderFiles(importDir, FileFlagsE::ImportedApi, false);
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
    if (!cmdLine.moduleFilePath.empty())
    {
        modulePathFile_ = cmdLine.moduleFilePath;
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        if (!hasResolvedFilePath(modulePathFile_))
            addResolvedFile(modulePathFile_, FileFlagsE::Module);
    }
    else if (!cmdLine.modulePath.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        if (!hasResolvedFilePath(modulePathFile_))
            addResolvedFile(modulePathFile_, FileFlagsE::Module);

        modulePathSrc_ = cmdLine.modulePath / "src";
        Utf8 because;
        if (FileSystem::resolveExistingFolder(modulePathSrc_, because) == Result::Continue)
            collectFolderFiles(modulePathSrc_, FileFlagsE::ModuleSrc, true);
        else
            modulePathSrc_.clear();
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

