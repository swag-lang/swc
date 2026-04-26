#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/RuntimeName.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandPrint.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using CommandPrint::addBoolEntry;
    using CommandPrint::addInfoEntry;
    using CommandPrint::addPathSet;
    using CommandPrint::addUtf8Set;
    using CommandPrint::nextInfoGroupStyle;

    void printCommandLineOptions(const TaskContext& ctx, bool& hasPrintedGroup)
    {
        const CommandLine&              cmdLine  = ctx.cmdLine();
        const Runtime::BuildCfg&        buildCfg = cmdLine.defaultBuildCfg;
        std::vector<Logger::FieldEntry> entries;

        addInfoEntry(entries, "Command", COMMANDS[static_cast<int>(cmdLine.command)].name, LogColor::BrightYellow);
        addInfoEntry(entries, "Target OS", targetOsName(cmdLine.targetOs));
        addInfoEntry(entries, "Target architecture", targetArchName(cmdLine.targetArch));
        addInfoEntry(entries, "Target CPU", cmdLine.targetCpu);
        addInfoEntry(entries, "Build config", cmdLine.buildCfg);
        addInfoEntry(entries, "Backend", backendKindName(buildCfg.backendKind));
        addInfoEntry(entries, "Name", Utf8(buildCfg.name));
        addInfoEntry(entries, "Module namespace", Utf8(buildCfg.moduleNamespace));
        addInfoEntry(entries, "Work directory", Utf8(buildCfg.workDir));
        addBoolEntry(entries, "Backend optimize", buildCfg.backend.optimize);
        Logger::printFieldGroup(ctx, "Command Line", entries, nextInfoGroupStyle(hasPrintedGroup));

        entries.clear();
        addBoolEntry(entries, "Log colors", cmdLine.logColor);
        addBoolEntry(entries, "ASCII logs", cmdLine.logAscii);
        addBoolEntry(entries, "Syntax colors", cmdLine.syntaxColor);
        addBoolEntry(entries, "One-line diagnostics", cmdLine.diagOneLine);
        addBoolEntry(entries, "Error ids", cmdLine.errorId);
        addBoolEntry(entries, "Silent", cmdLine.silent);
        addBoolEntry(entries, "Stats", cmdLine.stats);
        addBoolEntry(entries, "Clear screen", cmdLine.clear);
        addBoolEntry(entries, "Dry run", cmdLine.dryRun);
        addBoolEntry(entries, "Show config", cmdLine.showConfig);
        addBoolEntry(entries, "Verbose verify", cmdLine.verboseVerify);
        addBoolEntry(entries, "Source-driven tests", cmdLine.sourceDrivenTest);
        addBoolEntry(entries, "Test native", cmdLine.testNative);
        addBoolEntry(entries, "Test JIT", cmdLine.testJit);
        addBoolEntry(entries, "Lexer only", cmdLine.lexOnly);
        addBoolEntry(entries, "Syntax only", cmdLine.syntaxOnly);
        addBoolEntry(entries, "Sema only", cmdLine.semaOnly);
        addBoolEntry(entries, "Emit output", cmdLine.output);
        addBoolEntry(entries, "Runtime", cmdLine.runtime);
        addBoolEntry(entries, "Dev full", cmdLine.devFull);

#if SWC_HAS_UNITTEST
        addBoolEntry(entries, "Unittest", cmdLine.unittest);
        addBoolEntry(entries, "Verbose unittest", cmdLine.verboseUnittest);
#endif

#if SWC_HAS_VALIDATE_MICRO
        addBoolEntry(entries, "Validate micro", cmdLine.validateMicro);
#endif

#if SWC_HAS_VALIDATE_NATIVE
        addBoolEntry(entries, "Validate native", cmdLine.validateNative);
#endif

#if SWC_DEV_MODE
        addBoolEntry(entries, "Randomize", cmdLine.randomize);
        addInfoEntry(entries, "Random seed", std::to_string(cmdLine.randSeed));
#endif

        addInfoEntry(entries, "Syntax color luminance", std::to_string(cmdLine.syntaxColorLum));
        addInfoEntry(entries, "Core count", std::to_string(cmdLine.numCores));
        addInfoEntry(entries, "Tab size", std::to_string(cmdLine.tabSize));
        addInfoEntry(entries, "Diagnostic max column", std::to_string(cmdLine.diagMaxColumn));
        addInfoEntry(entries, "File path display", FileSystem::filePathDisplayModeName(cmdLine.filePathDisplay));
        addInfoEntry(entries, "Verify filter", cmdLine.verboseVerifyFilter);
        Logger::printFieldGroup(ctx, "Modes & Diagnostics", entries, nextInfoGroupStyle(hasPrintedGroup, 26));

        entries.clear();
        addInfoEntry(entries, "Config file", cmdLine.configFile);
        addInfoEntry(entries, "Module path", cmdLine.modulePath);
        addInfoEntry(entries, "Export API directory", cmdLine.exportApiDir);
        addInfoEntry(entries, "Output directory", Utf8(buildCfg.outDir));
        addPathSet(entries, "Source directories", cmdLine.directories);
        addPathSet(entries, "Source files", cmdLine.files);
        addPathSet(entries, "Import API directories", cmdLine.importApiDirs);
        addPathSet(entries, "Import API files", cmdLine.importApiFiles);
        addUtf8Set(entries, "File filters", cmdLine.fileFilter);
        Logger::printFieldGroup(ctx, "Inputs", entries, nextInfoGroupStyle(hasPrintedGroup, 24));
    }

    void printProcessConfig(const TaskContext& ctx, bool& hasPrintedGroup)
    {
        std::error_code                 ec;
        const fs::path                  currentDir = fs::current_path(ec);
        const fs::path                  tempPath   = Os::getTemporaryPath();
        std::vector<Logger::FieldEntry> entries;

        addInfoEntry(entries, "Host OS", Os::hostOsName());
        addInfoEntry(entries, "Host CPU", Os::hostCpuName());
        addInfoEntry(entries, "Executable", Os::getExeFullName());
        addInfoEntry(entries, "Temp path", tempPath);
        if (!ec)
            addInfoEntry(entries, "Current directory", currentDir);
        Logger::printFieldGroup(ctx, "Process", entries, nextInfoGroupStyle(hasPrintedGroup));
    }

    void printNativeConfig(const TaskContext& ctx, CompilerInstance& compiler, bool& hasPrintedGroup)
    {
        if (!Runtime::backendKindProducesNativeArtifact(compiler.buildCfg().backendKind))
            return;

        NativeBackendBuilder            nativeBuilder(compiler, false);
        const NativeArtifactBuilder     artifactBuilder(nativeBuilder);
        NativeArtifactPaths             nativePaths;
        Os::WindowsToolchainPaths       toolchain;
        const auto                      toolchainResult = NativeLinker::queryToolchainPaths(nativeBuilder, toolchain);
        std::vector<Logger::FieldEntry> entries;

        artifactBuilder.queryPaths(nativePaths);

        addInfoEntry(entries, "Name", nativePaths.name, LogColor::BrightYellow);
        addInfoEntry(entries, "Work directory", nativePaths.workDir);
        if (!nativePaths.buildDir.empty())
            addInfoEntry(entries, "Build directory", nativePaths.buildDir);
        addInfoEntry(entries, "Output directory", nativePaths.outDir);
        addInfoEntry(entries, "Artifact path", nativePaths.artifactPath);
        addInfoEntry(entries, "PDB path", nativePaths.pdbPath);
        Logger::printFieldGroup(ctx, "Native Paths", entries, nextInfoGroupStyle(hasPrintedGroup));

        entries.clear();
        switch (toolchainResult)
        {
            case Os::WindowsToolchainDiscoveryResult::Ok:
                addInfoEntry(entries, "Status", "ready", LogColor::BrightGreen);
                addInfoEntry(entries, "Linker", toolchain.linkExe);
                addInfoEntry(entries, "Librarian", toolchain.libExe);
                addInfoEntry(entries, "MSVC library path", toolchain.vcLibPath);
                addInfoEntry(entries, "Windows SDK UM libs", toolchain.sdkUmLibPath);
                addInfoEntry(entries, "Windows SDK UCRT libs", toolchain.sdkUcrtLibPath);
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
    void showConfig(CompilerInstance& compiler)
    {
        const TaskContext        ctx(compiler);
        const Logger::ScopedLock loggerLock{ctx.global().logger()};
        bool                     hasPrintedGroup = false;

        printCommandLineOptions(ctx, hasPrintedGroup);
        printProcessConfig(ctx, hasPrintedGroup);
        printNativeConfig(ctx, compiler, hasPrintedGroup);
    }
}

SWC_END_NAMESPACE();
