#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Os/Os.h"
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

    Result readText(std::string& result, const fs::path& path)
    {
        FileSystem::IoErrorInfo error;
        return FileSystem::readTextFile(path, result, error);
    }
}

SWC_TEST_BEGIN(Compiler_NewScriptCommandParsesDefaultPath)
{
    CommandLine parserCmdLine;
    char        arg0[] = "swc_devmode";
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
    char  arg0[]         = "swc_devmode";
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
    char        arg0[] = "swc_devmode";
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
    static constexpr std::string_view EXPECTED = "#main\n{\n    @print(\"Hello, world!\\n\")\n}\n";

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
    if (readText(source, testDir.path() / "hello.swgs") != Result::Continue)
        return Result::Error;
    if (source != EXPECTED)
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(Compiler_NewCommandCreatesAndExtendsWorkspace)
{
    static constexpr std::string_view EXPECTED_MAIN   = "#main\n{\n    @print(\"Hello, world!\\n\")\n}\n";
    static constexpr std::string_view EXPECTED_MODULE = "#run\n{\n    let itf = @compiler\n    let cfg = itf.getBuildCfg()!\n    cfg.backendKind = .Executable\n}\n";

    NewCommandTestDirectory testDir("CreatesAndExtendsWorkspace");
    const fs::path          workspacePath = testDir.path() / "workspace";

    for (const char* moduleName : {"app", "tools"})
    {
        CommandLine cmdLine;
        cmdLine.command         = CommandKind::New;
        cmdLine.newProjectKind  = NewProjectKind::Module;
        cmdLine.newProjectName  = moduleName;
        cmdLine.workspacePath   = workspacePath;

        TaskContext commandCtx(ctx.global(), cmdLine);
        commandCtx.setMuteOutput(true);
        if (Command::createProject(commandCtx) != Result::Continue)
            return Result::Error;

        const fs::path modulePath = workspacePath / "modules" / moduleName;
        std::string    moduleSource;
        std::string    mainSource;
        if (readText(moduleSource, modulePath / "module.swg") != Result::Continue)
            return Result::Error;
        if (readText(mainSource, modulePath / "src" / "main.swg") != Result::Continue)
            return Result::Error;
        if (moduleSource != EXPECTED_MODULE || mainSource != EXPECTED_MAIN)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
