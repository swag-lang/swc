#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/RuntimeName.h"
#include "Compiler/SourceFile.h"
#include "Doc/DocGenerator.h"
#include "Format/FormatJob.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using CommandPrint::addInfoEntry;
    using CommandPrint::addSetEntries;

    void addPlanEntry(std::vector<Logger::FieldEntry>& entries, const uint32_t index, const std::string_view status, const Utf8& detail)
    {
        addInfoEntry(entries, std::format("[{}]", index), Utf8(status) + " " + detail);
    }

    struct DryRunInputSummary
    {
        uint32_t totalFiles       = 0;
        uint32_t customFiles      = 0;
        uint32_t moduleFiles      = 0;
        uint32_t moduleSrc        = 0;
        uint32_t importedApiFiles = 0;
        uint32_t runtimeFiles     = 0;
    };

    struct DryRunNativePreview
    {
        bool enabled        = false;
        bool mayRunArtifact = false;

        Runtime::BuildCfgBackendKind backendKind = Runtime::BuildCfgBackendKind::None;
        NativeArtifactPaths          paths;

        Os::WindowsToolchainPaths           toolchain;
        Os::WindowsToolchainDiscoveryResult toolchainResult = Os::WindowsToolchainDiscoveryResult::Ok;
    };

    struct DryRunFormatPreview
    {
        bool enabled = false;

        size_t totalFiles          = 0;
        size_t rewrittenFiles      = 0;
        size_t unchangedFiles      = 0;
        size_t skippedFmtFiles     = 0;
        size_t skippedInvalidFiles = 0;
    };

    void collectDryRunInputSummary(DryRunInputSummary& outSummary, const CompilerInstance& compiler)
    {
        outSummary = {};
        for (const SourceFile* file : compiler.files())
        {
            if (!file)
                continue;

            outSummary.totalFiles++;
            if (file->hasFlag(FileFlagsE::CustomSrc))
                outSummary.customFiles++;
            else if (file->hasFlag(FileFlagsE::Module))
                outSummary.moduleFiles++;
            else if (file->hasFlag(FileFlagsE::ModuleSrc))
                outSummary.moduleSrc++;
            else if (file->hasFlag(FileFlagsE::ImportedApi))
                outSummary.importedApiFiles++;
            else if (file->hasFlag(FileFlagsE::Runtime))
                outSummary.runtimeFiles++;
        }
    }

    DryRunNativePreview buildDryRunNativePreview(CompilerInstance& compiler)
    {
        DryRunNativePreview result  = {};
        const CommandLine&  cmdLine = compiler.cmdLine();
        switch (cmdLine.command)
        {
            case CommandKind::New:
            case CommandKind::Format:
            case CommandKind::Syntax:
            case CommandKind::Sema:
            case CommandKind::Doc:
            case CommandKind::Unittest:
                return result;

            case CommandKind::Build:
            case CommandKind::Run:
            case CommandKind::Smoke:
                break;

            case CommandKind::Test:
                if (!cmdLine.output || !cmdLine.testNative)
                    return result;
                break;

            default:
                SWC_UNREACHABLE();
        }

        result.enabled     = true;
        result.backendKind = effectiveBackendKind(cmdLine, compiler.buildCfg().backendKind);
        if (!Runtime::backendKindProducesNativeArtifact(result.backendKind))
        {
            result.enabled = false;
            return result;
        }

        result.mayRunArtifact = (cmdLine.command == CommandKind::Test && result.backendKind == Runtime::BuildCfgBackendKind::Executable) ||
                                (isRunLikeCommand(cmdLine.command) && result.backendKind == Runtime::BuildCfgBackendKind::Executable);

        NativeBackendBuilder        nativeBuilder(compiler, false);
        const NativeArtifactBuilder artifactBuilder(nativeBuilder);
        artifactBuilder.queryPaths(result.paths);
        if (cmdLine.targetOs == Runtime::TargetOs::Windows)
            result.toolchainResult = Linker::queryToolchainPaths(nativeBuilder, result.toolchain);
        return result;
    }

    Result buildDryRunFormatPreview(DryRunFormatPreview& outPreview, const CompilerInstance& compiler, TaskContext& ctx)
    {
        outPreview = {};
        if (ctx.cmdLine().command != CommandKind::Format)
            return Result::Continue;

        outPreview.enabled = true;

        const Global&     global       = ctx.global();
        JobManager&       jobMgr       = global.jobMgr();
        const JobClientId clientId     = compiler.jobClientId();
        const uint64_t    errorsBefore = Stats::getNumErrors();

        // The preview runs the real command's selection so its counts cannot drift from what
        // `format` would do; FormatJob itself suppresses the disk write under --dry-run.
        std::vector<FormatJob*> jobs;
        SWC_RESULT(Command::enqueueFormatJobs(ctx, compiler, jobs));

        jobMgr.waitAll(clientId);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;

        outPreview.totalFiles = jobs.size();
        for (const FormatJob* job : jobs)
        {
            if (job->rewritten())
                outPreview.rewrittenFiles++;
            else if (job->skippedFmt())
                outPreview.skippedFmtFiles++;
            else if (job->skippedInvalid())
                outPreview.skippedInvalidFiles++;
            else
                outPreview.unchangedFiles++;
        }

        return Result::Continue;
    }

    Utf8 formatFileCountWithSuffix(const size_t count, const std::string_view suffix)
    {
        Utf8 result = Utf8Helper::countWithLabel(count, "file");
        result += suffix;
        return result;
    }

    void printDryRunOverview(const TaskContext& ctx, const DryRunInputSummary& inputSummary, const DryRunNativePreview& nativePreview)
    {
        const CommandLine&              cmdLine = ctx.cmdLine();
        std::vector<Logger::FieldEntry> entries;

        addInfoEntry(entries, "Command", commandName(cmdLine.command));
        addInfoEntry(entries, "Build config", cmdLine.buildCfg);
        addInfoEntry(entries, "Resolved inputs", Utf8Helper::countWithLabel(inputSummary.totalFiles, "file"));
        if (nativePreview.enabled || nativePreview.backendKind != Runtime::BuildCfgBackendKind::None)
            addInfoEntry(entries, "Backend", backendKindName(nativePreview.backendKind));

        addInfoEntry(entries, "Compile-time execution", "suppressed");
        addInfoEntry(entries, "Filesystem mutation", "suppressed");
        addInfoEntry(entries, "External processes", "suppressed");
        if (nativePreview.enabled)
            addInfoEntry(entries, "Native command detail", "stable flags are exact; source-driven inputs are shown as placeholders");

        Logger::printFieldGroup(ctx, "Dry Run", entries);
    }

    void printDryRunInputs(const TaskContext& ctx, const DryRunInputSummary& inputSummary)
    {
        const CommandLine&              cmdLine = ctx.cmdLine();
        std::vector<Logger::FieldEntry> entries;

        addInfoEntry(entries, "Total files", Utf8Helper::countWithLabel(inputSummary.totalFiles, "file"));
        addInfoEntry(entries, "Custom source files", Utf8Helper::countWithLabel(inputSummary.customFiles, "file"));
        addInfoEntry(entries, "Module files", Utf8Helper::countWithLabel(inputSummary.moduleFiles, "file"));
        addInfoEntry(entries, "Module source files", Utf8Helper::countWithLabel(inputSummary.moduleSrc, "file"));
        addInfoEntry(entries, "Imported API files", Utf8Helper::countWithLabel(inputSummary.importedApiFiles, "file"));
        addInfoEntry(entries, "Runtime files", Utf8Helper::countWithLabel(inputSummary.runtimeFiles, "file"));

        addInfoEntry(entries, "Workspace path", cmdLine.workspacePath);
        addInfoEntry(entries, "Workspace module", cmdLine.workspaceModuleFilter);
        addInfoEntry(entries, "Module path", cmdLine.modulePath);
        addInfoEntry(entries, "Export API directory", cmdLine.exportApiDir);
        if (cmdLine.command == CommandKind::Doc)
            addInfoEntry(entries, "Documentation directory", DocGenerator::outputDirectory(ctx.compiler()));

        addSetEntries(entries, "Source directories", cmdLine.directories);
        addSetEntries(entries, "Source files", cmdLine.files);
        addSetEntries(entries, "Import API modules", cmdLine.importApiModules);
        addSetEntries(entries, "Import API directories", cmdLine.importApiDirs);
        addSetEntries(entries, "Import API files", cmdLine.importApiFiles);

        Logger::printFieldGroup(ctx, "Resolved Inputs", entries);
    }

    void printDryRunPlan(const TaskContext& ctx, const DryRunInputSummary& inputSummary, const DryRunFormatPreview& formatPreview, const DryRunNativePreview& nativePreview)
    {
        const CommandLine&              cmdLine = ctx.cmdLine();
        std::vector<Logger::FieldEntry> entries;
        uint32_t                        index      = 1;
        const Utf8                      inputCount = Utf8Helper::countWithLabel(inputSummary.totalFiles, "input file");

        if (cmdLine.command != CommandKind::Unittest)
            addPlanEntry(entries, index++, "Would", std::format("collect and classify {}", inputCount));

        switch (cmdLine.command)
        {
            case CommandKind::Unittest:
                addPlanEntry(entries, index++, "Would", "run fast internal C++ unit tests");
                if (cmdLine.devFull)
                    addPlanEntry(entries, index, "Would", "also run filesystem-heavy internal C++ unit tests");
                else
                    addPlanEntry(entries, index, "Skip", "filesystem-heavy internal C++ unit tests unless --dev-full is set");
                break;

            case CommandKind::Format:
                if (formatPreview.enabled)
                {
                    // The preview counts come from the real command's selection, which excludes
                    // implicit runtime inputs and generated caches; say so when inputs were dropped.
                    if (inputSummary.totalFiles > formatPreview.totalFiles)
                        addPlanEntry(entries, index++, "Would", std::format("ignore {}", formatFileCountWithSuffix(inputSummary.totalFiles - formatPreview.totalFiles, " outside the format selection (runtime or generated)")));

                    addPlanEntry(entries, index++, "Would", std::format("parse and format {}", formatFileCountWithSuffix(formatPreview.totalFiles, "")));
                    addPlanEntry(entries, index++, "Would", std::format("rewrite {}", formatFileCountWithSuffix(formatPreview.rewrittenFiles, " whose formatted output differs")));
                    addPlanEntry(entries, index++, "Would", std::format("skip {}", formatFileCountWithSuffix(formatPreview.unchangedFiles, " because formatted output is unchanged")));
                    addPlanEntry(entries, index++, "Would", std::format("ignore {}", formatFileCountWithSuffix(formatPreview.skippedFmtFiles, " marked format-skipped")));
                    addPlanEntry(entries, index, "Would", std::format("ignore {}", formatFileCountWithSuffix(formatPreview.skippedInvalidFiles, " after parse errors")));
                }
                else
                {
                    addPlanEntry(entries, index++, "Would", std::format("parse and format {}", inputCount));
                    addPlanEntry(entries, index, "Would", "rewrite only files whose formatted output differs");
                }
                break;

            case CommandKind::Syntax:
                addPlanEntry(entries, index, "Would", std::format("parse {} and stop after syntax", inputCount));
                break;

            case CommandKind::Sema:
                addPlanEntry(entries, index++, "Would", std::format("parse {}", inputCount));
                addPlanEntry(entries, index++, "Would", "run semantic analysis, including compile-time evaluation when required");
                if (!cmdLine.exportApiDir.empty())
                    addPlanEntry(entries, index, "Would", std::format("write generated module API files under {}", Utf8(cmdLine.exportApiDir)));
                break;

            case CommandKind::Doc:
                addPlanEntry(entries, index++, "Would", std::format("parse {}", inputCount));
                addPlanEntry(entries, index++, "Would", "run semantic analysis, including compile-time evaluation when required");
                addPlanEntry(entries, index, "Would", std::format("write documentation under {}", Utf8(DocGenerator::outputDirectory(ctx.compiler()))));
                break;

            case CommandKind::Build:
            case CommandKind::Run:
            case CommandKind::Smoke:
                addPlanEntry(entries, index++, "Would", std::format("parse {}", inputCount));
                addPlanEntry(entries, index++, "Would", "run semantic analysis, including compile-time evaluation when required");
                if (!cmdLine.exportApiDir.empty())
                    addPlanEntry(entries, index++, "Would", std::format("write generated module API files under {}", Utf8(cmdLine.exportApiDir)));

                if (nativePreview.enabled)
                {
                    addPlanEntry(entries, index++, "Would", std::format("generate native {}", backendKindName(nativePreview.backendKind)));
                    addPlanEntry(entries, index++, "Would", "prepare native link inputs in memory");
                    addPlanEntry(entries, index++, "Would", std::format("link {} with the integrated linker", Utf8(nativePreview.paths.artifactPath)));

                    if (nativePreview.backendKind == Runtime::BuildCfgBackendKind::Executable)
                        addPlanEntry(entries, index++, "May", std::format("copy dependency DLLs/PDBs into {} when the module sets 'publishDependencies'", Utf8(nativePreview.paths.artifactPath.parent_path())));

                    if (isRunLikeCommand(cmdLine.command) && nativePreview.backendKind == Runtime::BuildCfgBackendKind::Executable)
                        addPlanEntry(entries, index, "Would", std::format("run {}", Utf8(nativePreview.paths.artifactPath)));
                }
                else
                {
                    addPlanEntry(entries, index, "Skip", std::format("native artifact generation for {} backend", backendKindName(nativePreview.backendKind)));
                }
                break;

            case CommandKind::Test:
                addPlanEntry(entries, index++, "Would", std::format("parse {}", inputCount));
                addPlanEntry(entries, index++, "Would", "run semantic analysis, including compile-time evaluation when required");
                if (cmdLine.testJit)
                    addPlanEntry(entries, index++, "May", "compile and execute eligible JIT #test functions discovered during semantic analysis");

                if (nativePreview.enabled)
                {
                    addPlanEntry(entries, index++, "May", std::format("build a native {} test artifact when eligible entry points are discovered", backendKindName(nativePreview.backendKind)));
                    addPlanEntry(entries, index++, "May", "prepare native link inputs in memory");
                    addPlanEntry(entries, index++, "May", std::format("link {} with the integrated linker", Utf8(nativePreview.paths.artifactPath)));

                    if (nativePreview.backendKind == Runtime::BuildCfgBackendKind::Executable)
                        addPlanEntry(entries, index++, "May", std::format("copy dependency DLLs/PDBs into {} when the module sets 'publishDependencies'", Utf8(nativePreview.paths.artifactPath.parent_path())));

                    if (nativePreview.mayRunArtifact)
                        addPlanEntry(entries, index++, "May", std::format("run {}", Utf8(nativePreview.paths.artifactPath)));
                }
                else if (cmdLine.testNative && !cmdLine.output)
                    addPlanEntry(entries, index++, "Skip", "native test artifact generation because output is disabled");
                else if (cmdLine.testNative && nativePreview.backendKind != Runtime::BuildCfgBackendKind::None)
                    addPlanEntry(entries, index++, "Skip", std::format("native test artifact generation for {} backend", backendKindName(nativePreview.backendKind)));

                addPlanEntry(entries, index, "Would", "verify expected diagnostics and untouched markers");
                break;

            default:
                SWC_UNREACHABLE();
        }

        Logger::printFieldGroup(ctx, "Plan", entries);
    }

    void printDryRunNativeOutputs(const TaskContext& ctx, const DryRunNativePreview& nativePreview)
    {
        if (!nativePreview.enabled)
            return;

        std::vector<Logger::FieldEntry> entries;
        addInfoEntry(entries, "Backend", backendKindName(nativePreview.backendKind));
        addInfoEntry(entries, "Work directory", nativePreview.paths.workDir);
        addInfoEntry(entries, "Build directory", nativePreview.paths.buildDir);
        addInfoEntry(entries, "Output directory", nativePreview.paths.outDir);
        addInfoEntry(entries, "Artifact path", nativePreview.paths.artifactPath);
        if (!nativePreview.paths.pdbPath.empty())
            addInfoEntry(entries, "PDB path", nativePreview.paths.pdbPath);
        addInfoEntry(entries, "Link inputs", ctx.cmdLine().targetOs == Runtime::TargetOs::Linux ? "ELF objects in a temporary link directory" : "in memory");

        Logger::printFieldGroup(ctx, "Native Outputs", entries);
    }

    void printDryRunNativeCommands(const TaskContext& ctx, const DryRunNativePreview& nativePreview)
    {
        if (!nativePreview.enabled)
            return;

        std::vector<Logger::FieldEntry> entries;

        if (ctx.cmdLine().targetOs == Runtime::TargetOs::Linux)
            addInfoEntry(entries, "Linker", nativePreview.backendKind == Runtime::BuildCfgBackendKind::StaticLibrary ? "ar @arguments.rsp" : "cc @arguments.rsp");
        else
            addInfoEntry(entries, "Linker", "integrated (in-process)");

        if (nativePreview.mayRunArtifact)
        {
            addInfoEntry(entries, "Artifact working dir", nativePreview.paths.artifactPath.parent_path());
            const std::vector<Utf8> runArgs = effectiveGeneratedArtifactRunArgs(ctx.cmdLine());
            addInfoEntry(entries, "Artifact command", Os::formatProcessCommandLine(nativePreview.paths.artifactPath, runArgs));
        }

        if (entries.empty())
            return;

        Logger::printFieldGroup(ctx, "External Commands", entries);
    }

    void printDryRunNativeToolchain(const TaskContext& ctx, const DryRunNativePreview& nativePreview)
    {
        if (!nativePreview.enabled)
            return;

        std::vector<Logger::FieldEntry> entries;

        if (ctx.cmdLine().targetOs == Runtime::TargetOs::Linux)
        {
            CommandPrint::addLinuxNativeToolchainEntries(entries);
        }
        else
            CommandPrint::addNativeToolchainEntries(entries, nativePreview.toolchainResult, nativePreview.toolchain);

        Logger::printFieldGroup(ctx, "Native Toolchain", entries);
    }
}

namespace Command
{
    void dryRun(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);
        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        DryRunInputSummary inputSummary;
        collectDryRunInputSummary(inputSummary, compiler);

        DryRunFormatPreview formatPreview;
        if (buildDryRunFormatPreview(formatPreview, compiler, ctx) != Result::Continue)
            return;

        const DryRunNativePreview nativePreview = buildDryRunNativePreview(compiler);
        const Logger::ScopedLock  loggerLock{ctx.global().logger()};

        printDryRunOverview(ctx, inputSummary, nativePreview);
        printDryRunInputs(ctx, inputSummary);
        printDryRunPlan(ctx, inputSummary, formatPreview, nativePreview);
        printDryRunNativeOutputs(ctx, nativePreview);
        printDryRunNativeCommands(ctx, nativePreview);
        printDryRunNativeToolchain(ctx, nativePreview);
    }
}

SWC_END_NAMESPACE();
