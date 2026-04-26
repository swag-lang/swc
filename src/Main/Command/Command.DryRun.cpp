#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/RuntimeName.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/Command/CommandPrint.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using CommandPrint::addInfoEntry;
    using CommandPrint::addInfoEntryParts;
    using CommandPrint::addPathSet;
    using CommandPrint::nextInfoGroupStyle;

    void addPlanEntry(std::vector<Logger::FieldEntry>& entries, const uint32_t index, const std::string_view status, const LogColor statusColor, Utf8 detail)
    {
        std::vector<Logger::FieldValuePart> valueParts;
        valueParts.push_back({Utf8(status), statusColor});
        valueParts.push_back({Utf8(" "), LogColor::White});
        valueParts.push_back({std::move(detail), LogColor::White});
        addInfoEntryParts(entries, std::format("[{}]", index), std::move(valueParts));
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
        bool                                enabled        = false;
        bool                                mayRunArtifact = false;
        Runtime::BuildCfgBackendKind        backendKind    = Runtime::BuildCfgBackendKind::None;
        NativeArtifactPaths                 paths;
        Os::WindowsToolchainPaths           toolchain;
        Os::WindowsToolchainDiscoveryResult toolchainResult = Os::WindowsToolchainDiscoveryResult::Ok;
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
            case CommandKind::Format:
            case CommandKind::Syntax:
            case CommandKind::Sema:
                return result;

            case CommandKind::Build:
            case CommandKind::Run:
                break;

            case CommandKind::Test:
                if (!cmdLine.output || !cmdLine.testNative)
                    return result;
                break;

            default:
                SWC_UNREACHABLE();
        }

        result.enabled        = true;
        result.backendKind    = effectiveBackendKind(cmdLine, compiler.buildCfg().backendKind);
        result.mayRunArtifact = (cmdLine.command == CommandKind::Test && result.backendKind == Runtime::BuildCfgBackendKind::Executable) ||
                                (cmdLine.command == CommandKind::Run && result.backendKind == Runtime::BuildCfgBackendKind::Executable);

        NativeBackendBuilder        nativeBuilder(compiler, false);
        const NativeArtifactBuilder artifactBuilder(nativeBuilder);
        artifactBuilder.queryPaths(result.paths);
        result.toolchainResult = NativeLinker::queryToolchainPaths(nativeBuilder, result.toolchain);
        return result;
    }

    std::vector<Utf8> buildLinkPreviewArgs(const DryRunNativePreview& preview, const Runtime::BuildCfg& buildCfg)
    {
        std::vector<Utf8> args;
        switch (preview.backendKind)
        {
            case Runtime::BuildCfgBackendKind::Executable:
            case Runtime::BuildCfgBackendKind::SharedLibrary:
            {
                const bool dll = preview.backendKind == Runtime::BuildCfgBackendKind::SharedLibrary;
                args.emplace_back("/NOLOGO");
                args.emplace_back("/NODEFAULTLIB");
                args.emplace_back("/INCREMENTAL:NO");
                args.emplace_back("/MACHINE:X64");
                if (buildCfg.backend.debugInfo)
                {
                    args.emplace_back("/DEBUG:FULL");
                    args.emplace_back(std::format("/PDB:{}", Utf8(preview.paths.pdbPath)));
                }

                if (dll)
                {
                    args.emplace_back("/DLL");
                    args.emplace_back("/NOENTRY");
                }
                else
                {
                    args.emplace_back("/SUBSYSTEM:CONSOLE");
                    args.emplace_back("/ENTRY:mainCRTStartup");
                }

                args.emplace_back(std::format("/OUT:{}", Utf8(preview.paths.artifactPath)));
                if (!preview.toolchain.vcLibPath.empty())
                    args.emplace_back(std::format("/LIBPATH:{}", Utf8(preview.toolchain.vcLibPath)));
                if (!preview.toolchain.sdkUmLibPath.empty())
                    args.emplace_back(std::format("/LIBPATH:{}", Utf8(preview.toolchain.sdkUmLibPath)));
                if (!preview.toolchain.sdkUcrtLibPath.empty())
                    args.emplace_back(std::format("/LIBPATH:{}", Utf8(preview.toolchain.sdkUcrtLibPath)));

                args.emplace_back("<object-files>");
                args.emplace_back("<libraries from command line and source>");
                if (dll)
                    args.emplace_back("<exports discovered during semantic/codegen>");
                break;
            }

            case Runtime::BuildCfgBackendKind::StaticLibrary:
                args.emplace_back("/NOLOGO");
                args.emplace_back("/MACHINE:X64");
                args.emplace_back(std::format("/OUT:{}", Utf8(preview.paths.artifactPath)));
                args.emplace_back("<object-files>");
                break;

            case Runtime::BuildCfgBackendKind::None:
                break;
        }

        return args;
    }

    void printDryRunOverview(const TaskContext& ctx, const DryRunInputSummary& inputSummary, const DryRunNativePreview& nativePreview, bool& hasPrintedGroup)
    {
        const CommandLine&              cmdLine = ctx.cmdLine();
        std::vector<Logger::FieldEntry> entries;

        addInfoEntry(entries, "Command", COMMANDS[static_cast<int>(cmdLine.command)].name, LogColor::BrightYellow);
        addInfoEntry(entries, "Build config", cmdLine.buildCfg);
        addInfoEntry(entries, "Resolved inputs", Utf8Helper::countWithLabel(inputSummary.totalFiles, "file"), LogColor::BrightGreen);
        if (nativePreview.enabled)
            addInfoEntry(entries, "Backend", backendKindName(nativePreview.backendKind));
        addInfoEntry(entries, "Compile-time execution", "suppressed", LogColor::BrightGreen);
        addInfoEntry(entries, "Filesystem mutation", "suppressed", LogColor::BrightGreen);
        addInfoEntry(entries, "External processes", "suppressed", LogColor::BrightGreen);
        if (nativePreview.enabled)
            addInfoEntry(entries, "Native command detail", "stable flags are exact; source-driven inputs are shown as placeholders", LogColor::BrightYellow);
        Logger::printFieldGroup(ctx, "Dry Run", entries, nextInfoGroupStyle(hasPrintedGroup, 28));
    }

    void printDryRunInputs(const TaskContext& ctx, const DryRunInputSummary& inputSummary, bool& hasPrintedGroup)
    {
        const CommandLine&              cmdLine = ctx.cmdLine();
        std::vector<Logger::FieldEntry> entries;

        addInfoEntry(entries, "Total files", Utf8Helper::countWithLabel(inputSummary.totalFiles, "file"), LogColor::BrightGreen);
        addInfoEntry(entries, "Custom source files", Utf8Helper::countWithLabel(inputSummary.customFiles, "file"));
        addInfoEntry(entries, "Module files", Utf8Helper::countWithLabel(inputSummary.moduleFiles, "file"));
        addInfoEntry(entries, "Module source files", Utf8Helper::countWithLabel(inputSummary.moduleSrc, "file"));
        addInfoEntry(entries, "Imported API files", Utf8Helper::countWithLabel(inputSummary.importedApiFiles, "file"));
        addInfoEntry(entries, "Runtime files", Utf8Helper::countWithLabel(inputSummary.runtimeFiles, "file"));
        addInfoEntry(entries, "Module path", cmdLine.modulePath);
        addInfoEntry(entries, "Export API directory", cmdLine.exportApiDir);
        addPathSet(entries, "Source directories", cmdLine.directories);
        addPathSet(entries, "Source files", cmdLine.files);
        addPathSet(entries, "Import API directories", cmdLine.importApiDirs);
        addPathSet(entries, "Import API files", cmdLine.importApiFiles);
        Logger::printFieldGroup(ctx, "Resolved Inputs", entries, nextInfoGroupStyle(hasPrintedGroup, 24));
    }

    void printDryRunPlan(const TaskContext& ctx, const DryRunInputSummary& inputSummary, const DryRunNativePreview& nativePreview, bool& hasPrintedGroup)
    {
        const CommandLine&              cmdLine = ctx.cmdLine();
        std::vector<Logger::FieldEntry> entries;
        uint32_t                        index       = 1;
        const Utf8                      inputCount  = Utf8Helper::countWithLabel(inputSummary.totalFiles, "input file");
        Utf8                            objectFiles = "<object-files>";
        if (!nativePreview.paths.buildDir.empty() && !nativePreview.paths.name.empty())
            objectFiles = Utf8(nativePreview.paths.buildDir / std::format("{}_<NN>.obj", nativePreview.paths.name).c_str());

#if SWC_HAS_UNITTEST
        if (cmdLine.unittest)
            addPlanEntry(entries, index++, "Skip", LogColor::Gray, "internal C++ unittests enabled by the active mode");
#endif

        addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("collect and classify {}", inputCount));

        switch (cmdLine.command)
        {
            case CommandKind::Format:
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("parse {}", inputCount));
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, "validate the parsed AST can be written back as source");
                addPlanEntry(entries, index, "Would", LogColor::BrightGreen, "rewrite source files in place when formatted output differs");
                break;

            case CommandKind::Syntax:
                addPlanEntry(entries, index, "Would", LogColor::BrightGreen, std::format("parse {} and stop after syntax", inputCount));
                break;

            case CommandKind::Sema:
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("parse {}", inputCount));
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, "run semantic analysis, including compile-time evaluation when required");
                if (!cmdLine.exportApiDir.empty())
                    addPlanEntry(entries, index, "Would", LogColor::BrightGreen, std::format("write generated module API files under {}", Utf8(cmdLine.exportApiDir)));
                break;

            case CommandKind::Build:
            case CommandKind::Run:
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("parse {}", inputCount));
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, "run semantic analysis, including compile-time evaluation when required");
                if (!cmdLine.exportApiDir.empty())
                    addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("write generated module API files under {}", Utf8(cmdLine.exportApiDir)));
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("generate native {}", backendKindName(nativePreview.backendKind)));
                if (cmdLine.clear)
                    addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("clear native outputs under {}", Utf8(nativePreview.paths.workDir)));
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("write object files matching {}", objectFiles));
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("invoke the native toolchain to produce {}", Utf8(nativePreview.paths.artifactPath)));
                if (cmdLine.command == CommandKind::Run && nativePreview.backendKind == Runtime::BuildCfgBackendKind::Executable)
                    addPlanEntry(entries, index, "Would", LogColor::BrightGreen, std::format("run {}", Utf8(nativePreview.paths.artifactPath)));
                break;

            case CommandKind::Test:
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, std::format("parse {}", inputCount));
                addPlanEntry(entries, index++, "Would", LogColor::BrightGreen, "run semantic analysis, including compile-time evaluation when required");
                if (cmdLine.testJit)
                    addPlanEntry(entries, index++, "May", LogColor::BrightYellow, "compile and execute eligible JIT #test functions discovered during semantic analysis");
                if (nativePreview.enabled)
                {
                    addPlanEntry(entries, index++, "May", LogColor::BrightYellow, std::format("build a native {} test artifact when eligible entry points are discovered", backendKindName(nativePreview.backendKind)));
                    if (cmdLine.clear)
                        addPlanEntry(entries, index++, "May", LogColor::BrightYellow, std::format("clear native outputs under {}", Utf8(nativePreview.paths.workDir)));
                    addPlanEntry(entries, index++, "May", LogColor::BrightYellow, std::format("write object files matching {}", objectFiles));
                    addPlanEntry(entries, index++, "May", LogColor::BrightYellow, std::format("invoke the native toolchain to produce {}", Utf8(nativePreview.paths.artifactPath)));
                    if (nativePreview.mayRunArtifact)
                        addPlanEntry(entries, index++, "May", LogColor::BrightYellow, std::format("run {}", Utf8(nativePreview.paths.artifactPath)));
                }
                else if (cmdLine.testNative && !cmdLine.output)
                    addPlanEntry(entries, index++, "Skip", LogColor::Gray, "native test artifact generation because output is disabled");

                addPlanEntry(entries, index, "Would", LogColor::BrightGreen, "verify expected diagnostics and untouched markers");
                break;

            default:
                SWC_UNREACHABLE();
        }

        Logger::FieldGroupStyle style = nextInfoGroupStyle(hasPrintedGroup, 10);
        style.minLabelWidth           = 4;
        Logger::printFieldGroup(ctx, "Plan", entries, style);
    }

    void printDryRunNativeOutputs(const TaskContext& ctx, const DryRunNativePreview& nativePreview, bool& hasPrintedGroup)
    {
        if (!nativePreview.enabled)
            return;

        std::vector<Logger::FieldEntry> entries;
        Utf8                            objectFiles = "<object-files>";
        if (!nativePreview.paths.buildDir.empty() && !nativePreview.paths.name.empty())
            objectFiles = Utf8(nativePreview.paths.buildDir / std::format("{}_<NN>.obj", nativePreview.paths.name).c_str());

        addInfoEntry(entries, "Backend", backendKindName(nativePreview.backendKind), LogColor::BrightYellow);
        addInfoEntry(entries, "Work directory", nativePreview.paths.workDir);
        addInfoEntry(entries, "Build directory", nativePreview.paths.buildDir);
        addInfoEntry(entries, "Output directory", nativePreview.paths.outDir);
        addInfoEntry(entries, "Artifact path", nativePreview.paths.artifactPath);
        if (!nativePreview.paths.pdbPath.empty())
            addInfoEntry(entries, "PDB path", nativePreview.paths.pdbPath);
        addInfoEntry(entries, "Object files", objectFiles);
        Logger::printFieldGroup(ctx, "Native Outputs", entries, nextInfoGroupStyle(hasPrintedGroup, 24));
    }

    void printDryRunNativeCommands(const TaskContext& ctx, const DryRunNativePreview& nativePreview, bool& hasPrintedGroup)
    {
        if (!nativePreview.enabled)
            return;

        std::vector<Logger::FieldEntry> entries;
        const fs::path*                 exePath = nullptr;
        switch (nativePreview.backendKind)
        {
            case Runtime::BuildCfgBackendKind::Executable:
            case Runtime::BuildCfgBackendKind::SharedLibrary:
                exePath = &nativePreview.toolchain.linkExe;
                break;
            case Runtime::BuildCfgBackendKind::StaticLibrary:
                exePath = &nativePreview.toolchain.libExe;
                break;
            case Runtime::BuildCfgBackendKind::None:
                break;
        }

        if (exePath)
        {
            addInfoEntry(entries, "Native tool", *exePath);
            addInfoEntry(entries, "Tool working dir", nativePreview.paths.buildDir);
            if (nativePreview.toolchainResult == Os::WindowsToolchainDiscoveryResult::Ok)
            {
                const Utf8 commandLine = Os::formatProcessCommandLine(*exePath, buildLinkPreviewArgs(nativePreview, ctx.compiler().buildCfg()));
                addInfoEntry(entries, "Tool command", commandLine);
            }
        }

        if (nativePreview.mayRunArtifact)
        {
            addInfoEntry(entries, "Artifact working dir", nativePreview.paths.artifactPath.parent_path());
            constexpr std::span<const Utf8> noArguments;
            addInfoEntry(entries, "Artifact command", Os::formatProcessCommandLine(nativePreview.paths.artifactPath, noArguments));
        }

        if (entries.empty())
            return;

        Logger::printFieldGroup(ctx, "External Commands", entries, nextInfoGroupStyle(hasPrintedGroup, 24));
    }

    void printDryRunNativeToolchain(const TaskContext& ctx, const DryRunNativePreview& nativePreview, bool& hasPrintedGroup)
    {
        if (!nativePreview.enabled)
            return;

        std::vector<Logger::FieldEntry> entries;

        switch (nativePreview.toolchainResult)
        {
            case Os::WindowsToolchainDiscoveryResult::Ok:
                addInfoEntry(entries, "Status", "ready", LogColor::BrightGreen);
                addInfoEntry(entries, "Linker", nativePreview.toolchain.linkExe);
                addInfoEntry(entries, "Librarian", nativePreview.toolchain.libExe);
                addInfoEntry(entries, "MSVC library path", nativePreview.toolchain.vcLibPath);
                addInfoEntry(entries, "Windows SDK UM libs", nativePreview.toolchain.sdkUmLibPath);
                addInfoEntry(entries, "Windows SDK UCRT libs", nativePreview.toolchain.sdkUcrtLibPath);
                break;

            case Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain:
                addInfoEntry(entries, "Status", "missing MSVC toolchain", LogColor::BrightRed);
                break;

            case Os::WindowsToolchainDiscoveryResult::MissingWindowsSdk:
                addInfoEntry(entries, "Status", "missing Windows SDK", LogColor::BrightRed);
                break;
        }

        Logger::printFieldGroup(ctx, "Native Toolchain", entries, nextInfoGroupStyle(hasPrintedGroup, 26));
    }
}

namespace Command
{
    void dryRun(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);
        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        const Logger::ScopedLock loggerLock{ctx.global().logger()};
        DryRunInputSummary       inputSummary;
        bool                     hasPrintedGroup = false;
        collectDryRunInputSummary(inputSummary, compiler);
        const DryRunNativePreview nativePreview = buildDryRunNativePreview(compiler);

        printDryRunOverview(ctx, inputSummary, nativePreview, hasPrintedGroup);
        printDryRunInputs(ctx, inputSummary, hasPrintedGroup);
        printDryRunPlan(ctx, inputSummary, nativePreview, hasPrintedGroup);
        printDryRunNativeOutputs(ctx, nativePreview, hasPrintedGroup);
        printDryRunNativeCommands(ctx, nativePreview, hasPrintedGroup);
        printDryRunNativeToolchain(ctx, nativePreview, hasPrintedGroup);
    }
}

SWC_END_NAMESPACE();
