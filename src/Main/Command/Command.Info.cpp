#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeLinker.h"
#include "Backend/Runtime.h"
#include "Main/Command/CommandLine.h"
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
    Utf8 boolToUtf8(const bool value)
    {
        return value ? "true" : "false";
    }

    Utf8 targetOsName(const Runtime::TargetOs value)
    {
        switch (value)
        {
            case Runtime::TargetOs::Windows:
                return "Windows";
        }

        SWC_UNREACHABLE();
    }

    Utf8 targetArchName(const Runtime::TargetArch value)
    {
        switch (value)
        {
            case Runtime::TargetArch::X86_64:
                return "X86_64";
        }

        SWC_UNREACHABLE();
    }

    Utf8 buildCfgBackendKindName(const Runtime::BuildCfgBackendKind value)
    {
        switch (value)
        {
            case Runtime::BuildCfgBackendKind::Executable:
                return "exe";
            case Runtime::BuildCfgBackendKind::Library:
                return "dll";
            case Runtime::BuildCfgBackendKind::Export:
                return "lib";
            case Runtime::BuildCfgBackendKind::None:
                return "none";
        }

        SWC_UNREACHABLE();
    }

    Utf8 filePathDisplayModeName(const FileSystem::FilePathDisplayMode value)
    {
        switch (value)
        {
            case FileSystem::FilePathDisplayMode::AsIs:
                return "AsIs";
            case FileSystem::FilePathDisplayMode::BaseName:
                return "BaseName";
            case FileSystem::FilePathDisplayMode::Absolute:
                return "Absolute";
        }

        SWC_UNREACHABLE();
    }

    void printGroupHeader(const TaskContext& ctx, const char* title)
    {
        Logger::print(ctx, "\n");
        Logger::print(ctx, "[Info] ");
        Logger::print(ctx, title);
        Logger::print(ctx, "\n");
    }

    void printInfoLine(const TaskContext& ctx, const char* name, const Utf8& value, const LogColor color = LogColor::White)
    {
        Logger::printHeaderDot(ctx, LogColor::Cyan, name, color, value.empty() ? "<empty>" : value);
    }

    void printInfoLine(const TaskContext& ctx, const Utf8& name, const Utf8& value, const LogColor color = LogColor::White)
    {
        Logger::printHeaderDot(ctx, LogColor::Cyan, name, color, value.empty() ? "<empty>" : value);
    }

    void printInfoLine(const TaskContext& ctx, const Utf8& name, const fs::path& value, const LogColor color = LogColor::White)
    {
        printInfoLine(ctx, name, Utf8(value), color);
    }

    void printInfoLine(const TaskContext& ctx, const char* name, const char* value, const LogColor color = LogColor::White)
    {
        printInfoLine(ctx, name, Utf8(value), color);
    }

    void printInfoLine(const TaskContext& ctx, const char* name, const std::string& value, const LogColor color = LogColor::White)
    {
        printInfoLine(ctx, name, Utf8(value), color);
    }

    void printInfoLine(const TaskContext& ctx, const char* name, const fs::path& value, const LogColor color = LogColor::White)
    {
        printInfoLine(ctx, name, Utf8(value), color);
    }

    void printStringSet(const TaskContext& ctx, const char* name, const std::set<Utf8>& values)
    {
        if (values.empty())
        {
            printInfoLine(ctx, name, "<empty>");
            return;
        }

        uint32_t index = 0;
        for (const Utf8& value : values)
        {
            const Utf8 label = std::format("{}[{}]", name, index++);
            printInfoLine(ctx, label, value);
        }
    }

    void printPathSet(const TaskContext& ctx, const char* name, const std::set<fs::path>& values)
    {
        if (values.empty())
        {
            printInfoLine(ctx, name, "<empty>");
            return;
        }

        uint32_t index = 0;
        for (const fs::path& value : values)
        {
            const Utf8 label = std::format("{}[{}]", name, index++);
            printInfoLine(ctx, label, value);
        }
    }

    void printCommandLineOptions(const TaskContext& ctx)
    {
        const CommandLine&       cmdLine  = ctx.cmdLine();
        const Runtime::BuildCfg& buildCfg = cmdLine.defaultBuildCfg;

        printInfoLine(ctx, "command", COMMANDS[static_cast<int>(cmdLine.command)].name, LogColor::Yellow);
        printInfoLine(ctx, "targetOs", targetOsName(cmdLine.targetOs));
        printInfoLine(ctx, "targetArch", targetArchName(cmdLine.targetArch));
        printInfoLine(ctx, "targetCpu", cmdLine.targetCpu);
        printInfoLine(ctx, "buildCfg", cmdLine.buildCfg);
        printInfoLine(ctx, "targetArchName", cmdLine.targetArchName);
        printInfoLine(ctx, "backendKind", buildCfgBackendKindName(buildCfg.backendKind));
        printInfoLine(ctx, "name", Utf8(buildCfg.name));
        printInfoLine(ctx, "workDir", Utf8(buildCfg.workDir));
        printInfoLine(ctx, "backendOptimize", boolToUtf8(buildCfg.backend.optimize));
        printInfoLine(ctx, "logColor", boolToUtf8(cmdLine.logColor));
        printInfoLine(ctx, "logAscii", boolToUtf8(cmdLine.logAscii));
        printInfoLine(ctx, "syntaxColor", boolToUtf8(cmdLine.syntaxColor));
        printInfoLine(ctx, "diagOneLine", boolToUtf8(cmdLine.diagOneLine));
        printInfoLine(ctx, "errorId", boolToUtf8(cmdLine.errorId));
        printInfoLine(ctx, "silent", boolToUtf8(cmdLine.silent));
        printInfoLine(ctx, "stats", boolToUtf8(cmdLine.stats));
        printInfoLine(ctx, "clear", boolToUtf8(cmdLine.clear));
        printInfoLine(ctx, "verboseInfo", boolToUtf8(cmdLine.verboseInfo));
        printInfoLine(ctx, "verboseVerify", boolToUtf8(cmdLine.verboseVerify));
        printInfoLine(ctx, "sourceDrivenTest", boolToUtf8(cmdLine.isTestMode()));
        printInfoLine(ctx, "testNative", boolToUtf8(cmdLine.testNative));
        printInfoLine(ctx, "testJit", boolToUtf8(cmdLine.testJit));
        printInfoLine(ctx, "lexOnly", boolToUtf8(cmdLine.lexOnly));
        printInfoLine(ctx, "syntaxOnly", boolToUtf8(cmdLine.syntaxOnly));
        printInfoLine(ctx, "semaOnly", boolToUtf8(cmdLine.semaOnly));
        printInfoLine(ctx, "output", boolToUtf8(cmdLine.output));
        printInfoLine(ctx, "unittest", boolToUtf8(cmdLine.unittest));
        printInfoLine(ctx, "verboseUnittest", boolToUtf8(cmdLine.verboseUnittest));
        printInfoLine(ctx, "runtime", boolToUtf8(cmdLine.runtime));
#ifdef SWC_DEV_MODE
        printInfoLine(ctx, "randomize", boolToUtf8(cmdLine.randomize));
        printInfoLine(ctx, "randSeed", std::to_string(cmdLine.randSeed));
#endif
        printInfoLine(ctx, "syntaxColorLum", std::to_string(cmdLine.syntaxColorLum));
        printInfoLine(ctx, "numCores", std::to_string(cmdLine.numCores));
        printInfoLine(ctx, "tabSize", std::to_string(cmdLine.tabSize));
        printInfoLine(ctx, "diagMaxColumn", std::to_string(cmdLine.diagMaxColumn));
        printInfoLine(ctx, "filePathDisplay", filePathDisplayModeName(cmdLine.filePathDisplay));
        printInfoLine(ctx, "verboseVerifyFilter", cmdLine.verboseVerifyFilter);
        printStringSet(ctx, "fileFilter", cmdLine.fileFilter);
        printPathSet(ctx, "directories", cmdLine.directories);
        printPathSet(ctx, "files", cmdLine.files);
        printInfoLine(ctx, "modulePath", cmdLine.modulePath);
        printInfoLine(ctx, "outDir", Utf8(buildCfg.outDir));
        printInfoLine(ctx, "workDir", Utf8(buildCfg.workDir));
    }
}

namespace Command
{
    void verboseInfo(CompilerInstance& compiler)
    {
        const TaskContext           ctx(compiler);
        const Logger::ScopedLock    loggerLock{ctx.global().logger()};
        NativeBackendBuilder        nativeBuilder(compiler, false);
        const NativeArtifactBuilder artifactBuilder(nativeBuilder);
        NativeArtifactPaths         nativePaths;

        std::error_code           ec;
        const fs::path            currentDir = fs::current_path(ec);
        const fs::path            tempPath   = Os::getTemporaryPath();
        Os::WindowsToolchainPaths toolchain;
        const auto                toolchainResult = NativeLinker::queryToolchainPaths(nativeBuilder, toolchain);
        artifactBuilder.queryPaths(nativePaths);

        printGroupHeader(ctx, "Command Line");
        printCommandLineOptions(ctx);

        printGroupHeader(ctx, "Process");
        printInfoLine(ctx, "hostOs", Os::hostOsName());
        printInfoLine(ctx, "hostCpu", Os::hostCpuName());
        printInfoLine(ctx, "exePath", Os::getExeFullName());
        printInfoLine(ctx, "tempPath", tempPath);
        if (!ec)
            printInfoLine(ctx, "currentDir", currentDir);

        printGroupHeader(ctx, "Native Paths");
        printInfoLine(ctx, "name", nativePaths.name, LogColor::Yellow);
        printInfoLine(ctx, "workDir", nativePaths.workDir, LogColor::Yellow);
        if (!nativePaths.buildDir.empty())
            printInfoLine(ctx, "buildDir", nativePaths.buildDir, LogColor::Yellow);
        printInfoLine(ctx, "outDir", nativePaths.outDir, LogColor::Yellow);
        printInfoLine(ctx, "artifactPath", nativePaths.artifactPath, LogColor::Yellow);
        printInfoLine(ctx, "pdbPath", nativePaths.pdbPath, LogColor::Yellow);

        printGroupHeader(ctx, "Native Toolchain");
        switch (toolchainResult)
        {
            case Os::WindowsToolchainDiscoveryResult::Ok:
                printInfoLine(ctx, "native.linkExe", toolchain.linkExe, LogColor::Green);
                printInfoLine(ctx, "native.libExe", toolchain.libExe, LogColor::Green);
                printInfoLine(ctx, "native.vcLibPath", toolchain.vcLibPath, LogColor::Green);
                printInfoLine(ctx, "native.sdkUmLibPath", toolchain.sdkUmLibPath, LogColor::Green);
                printInfoLine(ctx, "native.sdkUcrtLibPath", toolchain.sdkUcrtLibPath, LogColor::Green);
                break;

            case Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain:
                printInfoLine(ctx, "native.toolchain", "missing msvc toolchain", LogColor::BrightRed);
                break;

            case Os::WindowsToolchainDiscoveryResult::MissingWindowsSdk:
                printInfoLine(ctx, "native.toolchain", "missing windows sdk", LogColor::BrightRed);
                break;
        }
    }
}

SWC_END_NAMESPACE();
