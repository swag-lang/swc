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
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
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
    static constexpr std::string_view SOURCE     = R"(#global fileprivate
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
    char        arg0[] = "swc_devmode";
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

SWC_END_NAMESPACE();

#endif
