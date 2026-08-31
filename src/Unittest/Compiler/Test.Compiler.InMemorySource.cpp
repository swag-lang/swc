#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Lexer/LangSpec.h"
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
#include "Main/Global.h"
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
            std::println(stderr, "[generic-union-deduction] seed {} changed the error count", seed);
            return Result::Error;
        }

        return Result::Continue;
    }

    const AstFunctionDecl* findFunctionDecl(const Ast& ast, const std::string_view name)
    {
        const AstFunctionDecl* result = nullptr;
        Ast::visit(ast, ast.root(), [&](AstNodeRef, const AstNode& node) {
            const auto* decl = node.safeCast<AstFunctionDecl>();
            if (!decl || decl->tokNameRef.isInvalid() || ast.srcView().tokenString(decl->tokNameRef) != name)
                return Ast::VisitResult::Continue;

            result = decl;
            return Ast::VisitResult::Stop;
        });
        return result;
    }
}

SWC_TEST_BEGIN(Compiler_LegacyStaticControlDirectivesAreNotKeywords)
{
    const LangSpec& langSpec = ctx.global().langSpec();
    for (const std::string_view spelling : {"#if", "#elif", "#else"})
    {
        if (langSpec.keyword(spelling) != TokenId::Identifier)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AutoInlineCostPricesCallsAndRewardsOneModuleCallSite)
{
    static constexpr std::string_view SOURCE = R"(#global private

func leaf(value: s32)->s32 => value + 1

func cheapCall(value: s32)->s32 => leaf(value)

func addressTaken(value: s32)->s32 => leaf(value)

func singleCall(value: s32)->s32
{
    var result = value
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    result += 1
    return leaf(result)
}

func repeatedCall(value: s32)->s32
{
    var result = value
    result += leaf(value)
    result += leaf(value)
    result += leaf(value)
    result += leaf(value)
    result += leaf(value)
    result += leaf(value)
    result += leaf(value)
    result += leaf(value)
    result += leaf(value)
    return result
}

func recursiveFirst(value: s32)->s32
{
    if value == 0 do
        return 0
    return recursiveSecond(value - 1)
}

func recursiveSecond(value: s32)->s32
{
    if value == 0 do
        return 0
    return recursiveFirst(value - 1)
}

func managedFailure() fail
{
}

func errorManaged()
{
    catch
    {
        try managedFailure()
    }
}

#[Swag.Mixin]
func compilerMixin()
{
}

func wrapsMixin()
{
    compilerMixin()
}

func closureProvider(value: s32)->func||()->s32
{
    return func|value|()->s32 { return value }
}

func wrapsClosureProvider(value: s32)->s32
{
    let cb = closureProvider(value)
    return cb()
}

func useCandidates()
{
    let cheap = cheapCall(1)
    let callback = addressTaken
    let addressed = addressTaken(1)
    let once = singleCall(1)
    let first = repeatedCall(1)
    let second = repeatedCall(2)
    let recursive = recursiveFirst(2)
    errorManaged()
    wrapsMixin()
    let closureValue = wrapsClosureProvider(7)
}
)";
    // If call-graph names from separate Asts are merged, the first source's
    // singleCall -> leaf and useCandidates -> singleCall edges combine with this edge into a
    // false cycle. Cross-Ast calls never auto-inline, so their recursion graphs stay separate.
    static constexpr std::string_view OTHER_SOURCE    = R"(#global private

func leaf() => useCandidates()
)";
    const fs::path                    sourcePath      = Unittest::makeTestSourcePath("Compiler", "AutoInlineCostPricesCallsAndRewardsOneModuleCallSite");
    const fs::path                    otherSourcePath = Unittest::makeTestSourcePath("Compiler", "AutoInlineCostKeepsAstCallGraphsSeparate");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_auto_inline_cost";

    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Unittest::registerTestSource(compiler, otherSourcePath, OTHER_SOURCE);
    TaskContext compilerCtx(compiler);

    SourceFile& sourceFile      = compiler.addFile(sourcePath, FileFlagsE::CustomSrc);
    SourceFile& otherSourceFile = compiler.addFile(otherSourcePath, FileFlagsE::CustomSrc);
    SWC_RESULT(sourceFile.loadContent(compilerCtx));
    SWC_RESULT(otherSourceFile.loadContent(compilerCtx));

    Lexer lexer;
    lexer.tokenize(compilerCtx, sourceFile.ast().srcView(), LexerFlagsE::Default);
    if (sourceFile.ast().srcView().mustSkip())
        return Result::Error;
    lexer.tokenize(compilerCtx, otherSourceFile.ast().srcView(), LexerFlagsE::Default);
    if (otherSourceFile.ast().srcView().mustSkip())
        return Result::Error;

    Parser parser;
    parser.parse(compilerCtx, sourceFile.ast());
    parser.parse(compilerCtx, otherSourceFile.ast());
    std::array<Ast*, 2> moduleAsts = {&sourceFile.ast(), &otherSourceFile.ast()};
    Parser::finalizeAutoInlineCandidates(moduleAsts);

    const AstFunctionDecl* cheapCall       = findFunctionDecl(sourceFile.ast(), "cheapCall");
    const AstFunctionDecl* addressTaken    = findFunctionDecl(sourceFile.ast(), "addressTaken");
    const AstFunctionDecl* singleCall      = findFunctionDecl(sourceFile.ast(), "singleCall");
    const AstFunctionDecl* repeatedCall    = findFunctionDecl(sourceFile.ast(), "repeatedCall");
    const AstFunctionDecl* recursiveFirst  = findFunctionDecl(sourceFile.ast(), "recursiveFirst");
    const AstFunctionDecl* recursiveSecond = findFunctionDecl(sourceFile.ast(), "recursiveSecond");
    const AstFunctionDecl* errorManaged    = findFunctionDecl(sourceFile.ast(), "errorManaged");
    const AstFunctionDecl* wrapsMixin      = findFunctionDecl(sourceFile.ast(), "wrapsMixin");
    const AstFunctionDecl* wrapsClosure    = findFunctionDecl(sourceFile.ast(), "wrapsClosureProvider");
    if (!cheapCall || !addressTaken || !singleCall || !repeatedCall || !recursiveFirst || !recursiveSecond || !errorManaged || !wrapsMixin || !wrapsClosure)
        return Result::Error;
    if (!cheapCall->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (addressTaken->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (singleCall->autoInlineCost <= K_AUTO_INLINE_MAX_BODY_TOKENS || !singleCall->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (repeatedCall->autoInlineCost <= K_AUTO_INLINE_MAX_BODY_TOKENS || repeatedCall->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (recursiveFirst->hasFlag(AstFunctionFlagsE::AutoInlineBody) || recursiveSecond->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (errorManaged->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (wrapsMixin->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (wrapsClosure->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
}
SWC_TEST_END()

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
    static constexpr std::string_view SOURCE     = R"(#global if #command == Swag.CompilerCommand.Format
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
    static constexpr std::string_view SOURCE     = R"(#global if false
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
    static constexpr std::string_view SOURCE     = R"(#global if #command == Swag.CompilerCommand.Test
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
    static constexpr std::string_view SOURCE     = R"(#global if #command == Swag.CompilerCommand.Test
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
