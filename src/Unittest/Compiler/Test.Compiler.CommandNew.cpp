#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Os/Os.h"
#include "Unittest/Compiler/CompilerTestFile.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class NewCommandTestDirectory
    {
    public:
        explicit NewCommandTestDirectory(const std::string_view testName)
        {
            path_ = (Os::getTemporaryPath() / "swc_unittest" / "new" / std::format("{}_p{}", testName, Os::currentProcessId())).lexically_normal();
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        ~NewCommandTestDirectory()
        {
            std::error_code ec;
            fs::remove_all(path_, ec);
        }

        const fs::path& path() const { return path_; }

    private:
        fs::path path_;
    };

}

SWC_TEST_BEGIN(Compiler_NewScriptCommandParsesDefaultPath)
{
    CommandLine parserCmdLine;
    char        arg0[] = "swc.dm";
    char        arg1[] = "new";
    char        arg2[] = "script";
    char*       argv[] = {arg0, arg1, arg2};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;
    if (parserCmdLine.command != CommandKind::New)
        return Result::Error;
    if (parserCmdLine.newProjectKind != NewProjectKind::Script)
        return Result::Error;
    if (!parserCmdLine.newScriptPath.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CommandLineHelpStopsBeforeCompilation)
{
    CommandLine parserCmdLine;
    parserCmdLine.silent = true;
    char  arg0[]         = "swc.dm";
    char* argv[]         = {arg0};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;
    if (!parserCmdLine.helpPrinted)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_NewModuleCommandParsesWorkspace)
{
    CommandLine parserCmdLine;
    char        arg0[] = "swc.dm";
    char        arg1[] = "new";
    char        arg2[] = "module";
    char        arg3[] = "hello";
    char        arg4[] = "--workspace";
    char        arg5[] = "future-workspace";
    char*       argv[] = {arg0, arg1, arg2, arg3, arg4, arg5};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;
    if (parserCmdLine.command != CommandKind::New)
        return Result::Error;
    if (parserCmdLine.newProjectKind != NewProjectKind::Module)
        return Result::Error;
    if (parserCmdLine.newProjectName != "hello")
        return Result::Error;
    if (parserCmdLine.workspacePath != fs::path("future-workspace"))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_NewCommandCreatesRunnableScript)
{
    static constexpr std::string_view EXPECTED = "#main\n{\n    Swag.print(\"Hello, world!\\n\")\n}\n";

    NewCommandTestDirectory testDir("CreatesRunnableScript");
    CommandLine             cmdLine;
    cmdLine.command        = CommandKind::New;
    cmdLine.newProjectKind = NewProjectKind::Script;
    cmdLine.newScriptPath  = testDir.path() / "hello";

    TaskContext commandCtx(ctx.global(), cmdLine);
    commandCtx.setMuteOutput(true);
    if (Command::createProject(commandCtx) != Result::Continue)
        return Result::Error;

    std::string source;
    if (CompilerTestFile::readText(source, testDir.path() / "hello.swgs") != Result::Continue)
        return Result::Error;
    if (source != EXPECTED)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_NewCommandCreatesAndExtendsWorkspace)
{
    static constexpr std::string_view EXPECTED_MAIN   = "#main\n{\n    Swag.print(\"Hello, world!\\n\")\n}\n";
    static constexpr std::string_view EXPECTED_MODULE = "#run\n{\n    let itf = Swag.compiler()\n    let cfg = itf.getBuildCfg()!\n    cfg.backendKind = .Executable\n}\n";

    NewCommandTestDirectory testDir("CreatesAndExtendsWorkspace");
    const fs::path          workspacePath = testDir.path() / "workspace";

    for (const char* moduleName : {"app", "tools"})
    {
        CommandLine cmdLine;
        cmdLine.command        = CommandKind::New;
        cmdLine.newProjectKind = NewProjectKind::Module;
        cmdLine.newProjectName = moduleName;
        cmdLine.workspacePath  = workspacePath;

        TaskContext commandCtx(ctx.global(), cmdLine);
        commandCtx.setMuteOutput(true);
        if (Command::createProject(commandCtx) != Result::Continue)
            return Result::Error;

        const fs::path modulePath = workspacePath / "modules" / moduleName;
        std::string    moduleSource;
        std::string    mainSource;
        if (CompilerTestFile::readText(moduleSource, modulePath / "module.swg") != Result::Continue)
            return Result::Error;
        if (CompilerTestFile::readText(mainSource, modulePath / "src" / "main.swg") != Result::Continue)
            return Result::Error;
        if (moduleSource != EXPECTED_MODULE || mainSource != EXPECTED_MAIN)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_ModuleDirectoryRunsSetupAndDefaultSources)
{
    NewCommandTestDirectory directory("ModuleDirectorySetup");
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "module.swg", "#load(\"setup/loaded.swg\")\n"));
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "setup" / "loaded.swg", "const LoadedSetupValue = 37\n"));
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "src" / "probe.swg", "#assert(LoadedSetupValue == 37)\n"));

    const std::vector<Utf8> args = {"sema", "--module", Utf8(directory.path().string()), "--num-cores", "1", "--no-log-color"};
    std::string             output;
    Os::ProcessRunOptions   options;
    options.capturedOutput = &output;
    options.forwardOutput  = false;
    options.timeoutMs      = 15000;
    uint32_t exitCode      = UINT32_MAX;
    if (Os::runProcess(exitCode, Os::getExeFullName(), args, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode != 0)
    {
        std::println(stderr, "[module directory setup] {}", output);
        return Result::Error;
    }

    // A successful setup alone is insufficient: the conventional source directory must run.
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "src" / "probe.swg", "#assert(LoadedSetupValue == 38)\n"));
    output.clear();
    exitCode = UINT32_MAX;
    if (Os::runProcess(exitCode, Os::getExeFullName(), args, directory.path(), &options) != Os::ProcessRunResult::Ok || exitCode == 0)
        return Result::Error;
    if (output.find("compile-time assertion evaluated to false") == std::string::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_ModuleFilePreservesExplicitInputs)
{
    NewCommandTestDirectory directory("ModuleFileExplicitInputs");
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "custom.swg", ""));
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "selected.swg", "const Selected = 1\n"));
    SWC_RESULT(CompilerTestFile::writeText(directory.path() / "src" / "excluded.swg", "#assert(false)\n"));

    CommandLine parserCmdLine;
    parserCmdLine.silent    = true;
    char        arg0[]     = "swc.dm";
    char        arg1[]     = "sema";
    char        arg2[]     = "--module-file";
    std::string moduleFile = (directory.path() / "custom.swg").string();
    char        arg4[]     = "--file";
    char        arg5[]     = "selected.swg";
    char*       argv[]     = {arg0, arg1, arg2, moduleFile.data(), arg4, arg5};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    SWC_RESULT(parser.parse(std::size(argv), argv));
    if (!FileSystem::pathEquals(parserCmdLine.moduleFilePath, directory.path() / "custom.swg"))
        return Result::Error;
    if (!parserCmdLine.directories.empty() || parserCmdLine.files.size() != 1)
        return Result::Error;
    if (!FileSystem::pathEquals(*parserCmdLine.files.begin(), directory.path() / "selected.swg"))
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_CleanModuleDoesNotRequireSetupFile)
{
    NewCommandTestDirectory directory("CleanModuleWithoutSetup");
    std::error_code         ec;
    fs::create_directories(directory.path(), ec);
    if (ec)
        return Result::Error;

    CommandLine parserCmdLine;
    parserCmdLine.silent = true;
    char        arg0[]  = "swc.dm";
    char        arg1[]  = "clean";
    char        arg2[]  = "--module";
    std::string module = directory.path().string();
    char*       argv[]  = {arg0, arg1, arg2, module.data()};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    SWC_RESULT(parser.parse(std::size(argv), argv));
    if (!FileSystem::pathEquals(parserCmdLine.modulePath, directory.path()))
        return Result::Error;
    if (!parserCmdLine.moduleFilePath.empty() || !parserCmdLine.directories.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
