#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(Compiler_CommandLineTagsReachSema)
{
    static constexpr std::string_view SOURCE     = R"(#global private
#assert(#hastag("User.Flag"))
#assert(#gettag("User.Flag", bool, false))
#assert(#gettag("User.Count", u64, 0) == 42)
#assert(#typeof(#gettag("User.Count", u64, 0)) == u64)
#assert(#gettag("User.Name", string, "fallback") == "hello")
#assert(#gettag("User.Missing", string, "fallback") == "fallback")
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "CommandLineTagsReachSema");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Sema;
    cmdLine.name    = "compiler_command_line_tags";
    cmdLine.files.insert(sourcePath);
    cmdLine.tags.emplace_back("User.Flag");
    cmdLine.tags.emplace_back("User.Count: u64 = 42");
    cmdLine.tags.emplace_back("User.Name: string = hello");
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const auto* flagTag = compiler.findCompilerTag("User.Flag");
    if (!flagTag || !compiler.cstMgr().get(flagTag->cstRef).getBool())
        return Result::Error;

    const auto* countTag = compiler.findCompilerTag("User.Count");
    if (!countTag)
        return Result::Error;

    const ConstantValue& countValue = compiler.cstMgr().get(countTag->cstRef);
    if (!countValue.isInt() || !countValue.getInt().fits64() || countValue.getInt().asI64() != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_InternalTagPrecedesUserOverride)
{
    static constexpr std::string_view SOURCE     = R"(#global private
#assert(#gettag("Swag.Endian", string, "big") == "little")
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "InternalTagPrecedesUserOverride");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Sema;
    cmdLine.name    = "compiler_internal_tag_precedence";
    cmdLine.files.insert(sourcePath);
    cmdLine.tags.emplace_back("Swag.Endian: string = big");
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const auto* tag = compiler.findCompilerTag("Swag.Endian");
    if (!tag)
        return Result::Error;

    const ConstantValue& value = compiler.cstMgr().get(tag->cstRef);
    if (!value.isString() || value.getString() != "little")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_TestCommandEnablesSourceDrivenModeWhenParsed)
{
    CommandLine parserCmdLine;
    char        arg0[] = "swc.dm";
    char        arg1[] = "test";
    char*       argv[] = {arg0, arg1};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;

    if (parserCmdLine.command != CommandKind::Test)
        return Result::Error;
    if (!parserCmdLine.sourceDrivenTest)
        return Result::Error;
    if (!parserCmdLine.defaultBuildCfg.backend.enableExceptions)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_TestCommandRegistersSwagTestCompilerTag)
{
    static constexpr std::string_view SOURCE     = R"(#global private
#assert(#hastag("swag.test"))
#assert(#gettag("swag.test", bool, false))
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "TestCommandRegistersSwagTestCompilerTag");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Test;
    cmdLine.name    = "compiler_test_command_swag_test_tag";
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t   errorsBefore = Stats::getNumErrors();
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    const auto* tag = compiler.findCompilerTag("swag.test");
    if (!tag || !compiler.cstMgr().get(tag->cstRef).getBool())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_UnittestCommandKeepsSourceDrivenModeDisabledWhenParsed)
{
    CommandLine parserCmdLine;
    char        arg0[] = "swc.dm";
    char        arg1[] = "unittest";
    char        arg2[] = "--verbose-unittest";
    char*       argv[] = {arg0, arg1, arg2};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;

    if (parserCmdLine.command != CommandKind::Unittest)
        return Result::Error;
    if (parserCmdLine.sourceDrivenTest)
        return Result::Error;
    if (!parserCmdLine.verboseUnittest)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_RunCommandParsesRunArgs)
{
    CommandLine parserCmdLine;
    char        arg0[] = "swc.dm";
    char        arg1[] = "run";
    char        arg2[] = "--run-arg";
    char        arg3[] = "swag.test";
    char        arg4[] = "--run-arg=keep-open";
    char*       argv[] = {arg0, arg1, arg2, arg3, arg4};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;

    if (parserCmdLine.command != CommandKind::Run)
        return Result::Error;
    if (parserCmdLine.runArgs.size() != 2)
        return Result::Error;
    if (parserCmdLine.runArgs[0] != "swag.test")
        return Result::Error;
    if (parserCmdLine.runArgs[1] != "keep-open")
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_TestCommandForcesSwagTestRunArg)
{
    CommandLine parserCmdLine;
    char        arg0[] = "swc.dm";
    char        arg1[] = "test";
    char        arg2[] = "--run-arg";
    char        arg3[] = "custom";
    char*       argv[] = {arg0, arg1, arg2, arg3};

    CommandLineParser parser(const_cast<Global&>(ctx.global()), parserCmdLine);
    if (parser.parse(std::size(argv), argv) != Result::Continue)
        return Result::Error;

    if (parserCmdLine.command != CommandKind::Test)
        return Result::Error;
    if (parserCmdLine.runArgs.size() != 1 || parserCmdLine.runArgs[0] != "custom")
        return Result::Error;

    // The test command adds both markers: the one that turns the generated executable into a
    // test runner, and the one that isolates it from the machine it runs on.
    const std::vector<Utf8> runArgs = effectiveGeneratedArtifactRunArgs(parserCmdLine);
    if (runArgs.size() != 3)
        return Result::Error;
    if (runArgs[0] != "custom" || runArgs[1] != SWAG_TEST_RUN_ARG || runArgs[2] != SWAG_SANDBOX_RUN_ARG)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_TestCommandDoesNotDuplicateSwagTestRunArg)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Test;
    cmdLine.runArgs.emplace_back(SWAG_TEST_RUN_ARG);
    cmdLine.runArgs.emplace_back(SWAG_SANDBOX_RUN_ARG);

    const std::vector<Utf8> runArgs = effectiveGeneratedArtifactRunArgs(cmdLine);
    if (runArgs.size() != 2)
        return Result::Error;
    if (runArgs[0] != SWAG_TEST_RUN_ARG || runArgs[1] != SWAG_SANDBOX_RUN_ARG)
        return Result::Error;
}
SWC_TEST_END()

// A caller that pins its own sandbox root keeps it: the command only supplies one when the
// run does not already say where to be isolated.
SWC_TEST_BEGIN(Compiler_TestCommandKeepsExplicitSandboxRoot)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Test;
    cmdLine.runArgs.emplace_back("swag.sandbox=C:/scratch/here");

    const std::vector<Utf8> runArgs = effectiveGeneratedArtifactRunArgs(cmdLine);
    if (runArgs.size() != 2)
        return Result::Error;
    if (runArgs[0] != "swag.sandbox=C:/scratch/here" || runArgs[1] != SWAG_TEST_RUN_ARG)
        return Result::Error;
}
SWC_TEST_END()

// The sources under test are granted back to the isolated process, so a test can record the
// reference data that lives beside it. The module is the grant when there is one.
SWC_TEST_BEGIN(Compiler_TestCommandGrantsTheModuleAsCorpus)
{
    CommandLine cmdLine;
    cmdLine.command       = CommandKind::Test;
    cmdLine.workspacePath = fs::path("C:/repo/workspaces/sample");
    cmdLine.modulePath    = fs::path("C:/repo/workspaces/sample/modules/program");

    const Utf8              expected = std::format("{}={}", SWAG_SANDBOX_CORPUS_RUN_ARG, cmdLine.modulePath.string());
    const std::vector<Utf8> runArgs  = effectiveGeneratedArtifactRunArgs(cmdLine);
    if (runArgs.size() != 3)
        return Result::Error;
    if (runArgs[2] != expected)
        return Result::Error;
}
SWC_TEST_END()

// A whole workspace is tested in one run, so the grant widens to the workspace exactly when no
// single module was named.
SWC_TEST_BEGIN(Compiler_TestCommandGrantsTheWorkspaceWithoutAModule)
{
    CommandLine cmdLine;
    cmdLine.command       = CommandKind::Test;
    cmdLine.workspacePath = fs::path("C:/repo/workspaces/sample");

    const Utf8              expected = std::format("{}={}", SWAG_SANDBOX_CORPUS_RUN_ARG, cmdLine.workspacePath.string());
    const std::vector<Utf8> runArgs  = effectiveGeneratedArtifactRunArgs(cmdLine);
    if (runArgs.size() != 3)
        return Result::Error;
    if (runArgs[2] != expected)
        return Result::Error;
}
SWC_TEST_END()

// A smoke run is the real program: it records nothing, so it is granted nothing.
SWC_TEST_BEGIN(Compiler_SmokeCommandGrantsNoCorpus)
{
    CommandLine cmdLine;
    cmdLine.command    = CommandKind::Smoke;
    cmdLine.modulePath = fs::path("C:/repo/workspaces/sample/modules/program");

    const std::vector<Utf8> runArgs = effectiveGeneratedArtifactRunArgs(cmdLine);
    if (hasRunArgNamed(runArgs, SWAG_SANDBOX_CORPUS_RUN_ARG))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
