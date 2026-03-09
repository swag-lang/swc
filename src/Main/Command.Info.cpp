#include "pch.h"
#include "Main/Command.h"
#include "Backend/Runtime.h"
#include "Main/CommandLine.h"
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
    Utf8 configuredArtifactBaseName(const CompilerInstance& compiler, const TaskContext& ctx)
    {
        const Utf8& cmdLineName = ctx.cmdLine().nativeArtifactBaseName;
        if (!cmdLineName.empty())
            return FileSystem::sanitizeFileName(cmdLineName);

        const Runtime::String& buildCfgName = compiler.buildCfg().nativeArtifactBaseName;
        if (buildCfgName.ptr && buildCfgName.length)
            return FileSystem::sanitizeFileName(Utf8(std::string_view(buildCfgName.ptr, buildCfgName.length)));

        return {};
    }

    Utf8 artifactBaseName(const CompilerInstance& compiler, const TaskContext& ctx)
    {
        const Utf8 configuredName = configuredArtifactBaseName(compiler, ctx);
        if (!configuredName.empty())
            return configuredName;

        if (!ctx.cmdLine().modulePath.empty())
            return FileSystem::sanitizeFileName(Utf8(ctx.cmdLine().modulePath.filename().string()));
        if (ctx.cmdLine().files.size() == 1)
            return FileSystem::sanitizeFileName(Utf8(ctx.cmdLine().files.begin()->stem().string()));
        if (ctx.cmdLine().directories.size() == 1)
            return FileSystem::sanitizeFileName(Utf8(ctx.cmdLine().directories.begin()->filename().string()));
        return "native_test";
    }

    Utf8 configuredWorkDirectoryName(const CompilerInstance& compiler, const TaskContext& ctx)
    {
        const Utf8& cmdLineName = ctx.cmdLine().nativeWorkDirName;
        if (!cmdLineName.empty())
            return FileSystem::sanitizeFileName(cmdLineName);

        const Runtime::String& buildCfgName = compiler.buildCfg().nativeWorkDirName;
        if (buildCfgName.ptr && buildCfgName.length)
            return FileSystem::sanitizeFileName(Utf8(std::string_view(buildCfgName.ptr, buildCfgName.length)));

        return {};
    }

    Utf8 automaticWorkDirectoryName(const CompilerInstance& compiler, const TaskContext& ctx, const Utf8& baseName)
    {
        Utf8 key;
        key += std::format("cmd={};os={};arch={};backend={};sub={};base={};", static_cast<int>(ctx.cmdLine().command), static_cast<int>(ctx.cmdLine().targetOs), static_cast<int>(ctx.cmdLine().targetArch), static_cast<int>(compiler.buildCfg().backendKind), static_cast<int>(compiler.buildCfg().backendSubKind), baseName);

        if (!ctx.cmdLine().modulePath.empty())
        {
            key += "module=";
            key += FileSystem::toUtf8Path(ctx.cmdLine().modulePath);
            key += ";";
        }

        for (const fs::path& file : ctx.cmdLine().files)
        {
            key += "file=";
            key += FileSystem::toUtf8Path(file);
            key += ";";
        }

        for (const fs::path& directory : ctx.cmdLine().directories)
        {
            key += "directory=";
            key += FileSystem::toUtf8Path(directory);
            key += ";";
        }

        const uint32_t hash = static_cast<uint32_t>(std::hash<std::string_view>{}(key.view()));
        return std::format("swc_native_{}_{:08x}", FileSystem::sanitizeFileName(baseName), hash);
    }

    fs::path artifactOutputDirectory(const CompilerInstance& compiler, const TaskContext& ctx)
    {
        if (!ctx.cmdLine().nativeArtifactOutputDir.empty())
            return ctx.cmdLine().nativeArtifactOutputDir;

        const Runtime::String& buildCfgDir = compiler.buildCfg().nativeArtifactOutputDir;
        if (buildCfgDir.ptr && buildCfgDir.length)
            return fs::absolute(fs::path(std::string(buildCfgDir.ptr, buildCfgDir.length)));

        return {};
    }

    Utf8 artifactExtension(const CompilerInstance& compiler, const TaskContext& ctx)
    {
        switch (ctx.cmdLine().targetOs)
        {
            case Runtime::TargetOs::Windows:
                switch (compiler.buildCfg().backendKind)
                {
                    case Runtime::BuildCfgBackendKind::Executable:
                        return ".exe";
                    case Runtime::BuildCfgBackendKind::Library:
                        return ".dll";
                    case Runtime::BuildCfgBackendKind::Export:
                        return ".lib";
                    case Runtime::BuildCfgBackendKind::None:
                        break;
                }

                break;
        }

        SWC_UNREACHABLE();
    }

    void printInfoLine(const TaskContext& ctx, const char* name, const Utf8& value, const LogColor color = LogColor::White)
    {
        Logger::printHeaderDot(ctx, LogColor::Cyan, name, color, value.empty() ? "<empty>" : value);
    }

    void printInfoLine(const TaskContext& ctx, const char* name, const char* value, const LogColor color = LogColor::White)
    {
        printInfoLine(ctx, name, Utf8(value), color);
    }

    void printInfoLine(const TaskContext& ctx, const char* name, const fs::path& value, const LogColor color = LogColor::White)
    {
        printInfoLine(ctx, name, FileSystem::toUtf8Path(value), color);
    }
}

namespace Command
{
    void info(CompilerInstance& compiler)
    {
        const TaskContext ctx(compiler);
        const Logger::ScopedLock loggerLock{ctx.global().logger()};

        std::error_code ec;
        const fs::path  currentDir      = fs::current_path(ec);
        const Utf8      baseName        = artifactBaseName(compiler, ctx);
        Utf8            workDirRootName = configuredWorkDirectoryName(compiler, ctx);
        if (workDirRootName.empty())
            workDirRootName = automaticWorkDirectoryName(compiler, ctx, baseName);

        const fs::path tempPath             = Os::getTemporaryPath();
        const fs::path workDirRoot          = tempPath / workDirRootName.c_str();
        const fs::path workDirSample        = workDirRoot / "00000000";
        fs::path       outputDir            = artifactOutputDirectory(compiler, ctx);
        if (outputDir.empty())
            outputDir = workDirSample;
        const fs::path artifactPath = outputDir / std::format("{}{}", baseName, artifactExtension(compiler, ctx));

        Os::WindowsToolchainPaths toolchain;
        const auto                toolchainResult = Os::discoverWindowsToolchainPaths(toolchain);

        Logger::print(ctx, "\n");
        printInfoLine(ctx, "command", COMMANDS[static_cast<int>(ctx.cmdLine().command)].name, LogColor::Yellow);
        printInfoLine(ctx, "hostOs", Os::hostOsName());
        printInfoLine(ctx, "hostCpu", Os::hostCpuName());
        printInfoLine(ctx, "targetCpu", ctx.cmdLine().targetCpu);
        printInfoLine(ctx, "exePath", Os::getExeFullName());
        printInfoLine(ctx, "tempPath", tempPath);
        if (!ec)
            printInfoLine(ctx, "currentDir", currentDir);
        if (!ctx.cmdLine().modulePath.empty())
            printInfoLine(ctx, "modulePath", ctx.cmdLine().modulePath);
        for (const fs::path& directory : ctx.cmdLine().directories)
            printInfoLine(ctx, "inputDir", directory);
        for (const fs::path& file : ctx.cmdLine().files)
            printInfoLine(ctx, "inputFile", file);

        Logger::print(ctx, "\n");
        printInfoLine(ctx, "native.baseName", baseName, LogColor::Yellow);
        printInfoLine(ctx, "native.workDirRoot", workDirRoot, LogColor::Yellow);
        printInfoLine(ctx, "native.workDirSample", workDirSample, LogColor::Yellow);
        printInfoLine(ctx, "native.outputDir", outputDir, LogColor::Yellow);
        printInfoLine(ctx, "native.artifactPath", artifactPath, LogColor::Yellow);

        Logger::print(ctx, "\n");
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
