#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct RestoreErrorCount
    {
        uint64_t saved = 0;

        ~RestoreErrorCount()
        {
            Stats::get().numErrors.store(saved, std::memory_order_relaxed);
        }
    };

    constexpr std::string_view GENERIC_UNION_DEDUCTION_SOURCE = R"(#global private

union(T) ValueOrPtr
{
    value: T
    ptr:   *T
}

func(T) takeValue(boxed: ValueOrPtr'T)->T
{
    return boxed.value
}

func validate()
{
    let value = takeValue({value: 10's32})
    #assert(#typeof(value) == s32)
}
)";

    Result runGenericUnionDeductionRandomizedSeed(const TaskContext& ctx, uint32_t seed)
    {
        const fs::path sourcePath = Unittest::makeTestSourcePath("Compiler", std::format("GenericUnionDeductionRandomizedSeed_{}", seed));

        CommandLine cmdLine;
        cmdLine.command   = CommandKind::Sema;
        cmdLine.name      = std::format("compiler_generic_union_deduction_randomized_{}", seed);
        cmdLine.silent    = true;
        cmdLine.numCores  = 1;
        cmdLine.randomize = true;
        cmdLine.randSeed  = seed;
        cmdLine.files.insert(sourcePath);
        CommandLineParser::refreshBuildCfg(cmdLine);

        const uint64_t    errorsBefore = Stats::getNumErrors();
        RestoreErrorCount restoreErrors{errorsBefore};
        CompilerInstance  compiler(ctx.global(), cmdLine);
        Unittest::registerTestSource(compiler, sourcePath, GENERIC_UNION_DEDUCTION_SOURCE);
        Command::sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
        {
            std::println(stderr, "Compiler_GenericUnionDeductionRandomizedSeed: seed {} error count changed", seed);
            return Result::Error;
        }

        return Result::Continue;
    }
}

SWC_TEST_BEGIN(Compiler_InMemorySourceRunsSemaWithoutDiskIO)
{
    static constexpr std::string_view SOURCE     = R"(func A() {}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "InMemorySourceRunsSemaWithoutDiskIO");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_in_memory_source";

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    TaskContext compilerCtx(compiler);

    SourceFile& sourceFile = compiler.addFile(sourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(compilerCtx));

    Lexer lexer;
    lexer.tokenize(compilerCtx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (sourceFile.ast().srcView().mustSkip())
        return Result::Error;

    Parser parser;
    parser.parse(compilerCtx, sourceFile.ast());

    const auto files = compiler.files();
    if (files.size() != 1)
        return Result::Error;

    const SourceFile* file = files.front();
    if (!file)
        return Result::Error;
    if (!FileSystem::pathEquals(file->path(), sourcePath))
        return Result::Error;
    if (!file->ast().hasSourceView() || file->ast().root().isInvalid())
        return Result::Error;

    const SourceView* srcView = compiler.findSourceViewByFileName(sourcePath.string());
    if (!srcView)
        return Result::Error;
    if (srcView->file() != file)
        return Result::Error;
    if (srcView->tokens().empty() || srcView->lines().empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_InMemorySourceKeepsFormatCommandGlobalIfDuringFormat)
{
    static constexpr std::string_view SOURCE     = R"(#global #if #command == Swag.CompilerCommand.Format
func A() {}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "InMemorySourceKeepsFormatCommandGlobalIfDuringFormat");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Format;
    cmdLine.name    = "compiler_in_memory_source_global_if_format";

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    TaskContext compilerCtx(compiler);

    SourceFile& sourceFile = compiler.addFile(sourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(compilerCtx));

    Lexer lexer;
    lexer.tokenize(compilerCtx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (sourceFile.ast().srcView().mustSkip())
        return Result::Error;

    Parser parser;
    parser.parse(compilerCtx, sourceFile.ast());
    if (compilerCtx.hasError())
        return Result::Error;
    if (sourceFile.ast().root().isInvalid())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_InMemorySourceSkipsFalseGlobalIf)
{
    static constexpr std::string_view SOURCE     = R"(#global #if false
#invalid_after_skip
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "InMemorySourceSkipsFalseGlobalIf");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_in_memory_source_global_if_false";

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    TaskContext compilerCtx(compiler);

    SourceFile& sourceFile = compiler.addFile(sourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(compilerCtx));

    Lexer lexer;
    lexer.tokenize(compilerCtx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (!sourceFile.ast().srcView().mustSkip())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_InMemorySourceSkipsTestCommandGlobalIfOutsideTests)
{
    static constexpr std::string_view SOURCE     = R"(#global #if #command == Swag.CompilerCommand.Test
#invalid_after_skip
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "InMemorySourceSkipsTestCommandGlobalIfOutsideTests");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_in_memory_source_global_if_test_normal";

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    TaskContext compilerCtx(compiler);

    SourceFile& sourceFile = compiler.addFile(sourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(compilerCtx));

    Lexer lexer;
    lexer.tokenize(compilerCtx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (!sourceFile.ast().srcView().mustSkip())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_InMemorySourceKeepsTestCommandGlobalIfDuringTests)
{
    static constexpr std::string_view SOURCE     = R"(#global #if #command == Swag.CompilerCommand.Test
func A() {}
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "InMemorySourceKeepsTestCommandGlobalIfDuringTests");

    CommandLine cmdLine;
    cmdLine.command          = CommandKind::Test;
    cmdLine.name             = "compiler_in_memory_source_global_if_test";
    cmdLine.sourceDrivenTest = true;

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    TaskContext compilerCtx(compiler);

    SourceFile& sourceFile = compiler.addFile(sourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(compilerCtx));

    Lexer lexer;
    lexer.tokenize(compilerCtx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (sourceFile.ast().srcView().mustSkip())
        return Result::Error;

    Parser parser;
    parser.parse(compilerCtx, sourceFile.ast());
    if (compilerCtx.hasError())
        return Result::Error;
    if (sourceFile.ast().root().isInvalid())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GenericUnionDeductionRemainsStableForHistoricalRandomSeed1002)
{
    return runGenericUnionDeductionRandomizedSeed(ctx, 1002);
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GenericUnionDeductionRemainsStableForHistoricalRandomSeed1009)
{
    return runGenericUnionDeductionRandomizedSeed(ctx, 1009);
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GenericUnionDeductionRemainsStableForHistoricalRandomSeed1032)
{
    return runGenericUnionDeductionRandomizedSeed(ctx, 1032);
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_GenericUnionDeductionRemainsStableForHistoricalRandomSeed1143)
{
    return runGenericUnionDeductionRandomizedSeed(ctx, 1143);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
