#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Main/CommandLine.h"
#include "Main/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    fs::path fallbackInputRoot()
    {
        std::error_code ec;
        fs::path        currentDir = fs::current_path(ec);
        if (ec)
            return {};
        return currentDir.lexically_normal();
    }

    fs::path inputRootForTest(const CommandLine& cmdLine)
    {
        if (!cmdLine.directories.empty())
            return cmdLine.directories.begin()->lexically_normal();
        if (!cmdLine.files.empty())
            return cmdLine.files.begin()->parent_path().lexically_normal();
        if (!cmdLine.modulePath.empty())
            return cmdLine.modulePath.parent_path().lexically_normal();
        return fallbackInputRoot();
    }

    CommandLine makeNativeArtifactCmdLine(const TaskContext& ctx)
    {
        CommandLine cmdLine = ctx.cmdLine();
        const fs::path root = inputRootForTest(cmdLine);

        cmdLine.command = CommandKind::Build;
        cmdLine.test    = false;
        cmdLine.name    = "native_paths";
        cmdLine.directories.clear();
        cmdLine.files.clear();
        cmdLine.originalDirectories.clear();
        cmdLine.originalFiles.clear();
        cmdLine.modulePath.clear();
        cmdLine.originalModulePath.clear();
        cmdLine.outDir.clear();
        cmdLine.workDir.clear();
        cmdLine.outDirStorage.clear();
        cmdLine.workDirStorage.clear();
        cmdLine.backendKindName = "exe";

        if (!root.empty())
            cmdLine.directories.insert(root);

        CommandLineParser::refreshBuildCfg(cmdLine);
        return cmdLine;
    }
}

SWC_TEST_BEGIN(NativeArtifact_DefaultsToLocalOutputTree)
    const CommandLine cmdLine   = makeNativeArtifactCmdLine(ctx);
    const fs::path    inputRoot = inputRootForTest(cmdLine);
    if (inputRoot.empty())
        return Result::Error;

    CompilerInstance          compiler(ctx.global(), cmdLine);
    NativeBackendBuilder      nativeBuilder(compiler, false);
    const NativeArtifactBuilder artifactBuilder(nativeBuilder);

    NativeArtifactPaths firstPaths;
    artifactBuilder.queryPaths(firstPaths, 3);

    NativeArtifactPaths secondPaths;
    artifactBuilder.queryPaths(secondPaths, 1);

    const fs::path expectedOutputRoot = inputRoot / ".output";
    if (!FileSystem::pathEquals(firstPaths.workDir.parent_path(), expectedOutputRoot))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.outDir, firstPaths.workDir))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.buildDir, firstPaths.workDir))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.artifactPath.parent_path(), firstPaths.workDir))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.pdbPath.parent_path(), firstPaths.workDir))
        return Result::Error;
    if (firstPaths.pdbPath.filename() != fs::path("native_paths.pdb"))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.workDir, secondPaths.workDir))
        return Result::Error;
    if (!FileSystem::pathEquals(firstPaths.buildDir, secondPaths.buildDir))
        return Result::Error;
    if (firstPaths.objectPaths.size() != 3)
        return Result::Error;
    if (secondPaths.objectPaths.size() != 1)
        return Result::Error;

    for (const fs::path& objectPath : firstPaths.objectPaths)
    {
        if (!FileSystem::pathEquals(objectPath.parent_path(), firstPaths.buildDir))
            return Result::Error;
    }

    if (!FileSystem::pathEquals(secondPaths.objectPaths.front().parent_path(), secondPaths.buildDir))
        return Result::Error;
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
