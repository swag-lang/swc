#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Native/SymbolSort.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/Sema.h"
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
    struct LocationSortTestSymbol
    {
        SourceViewRef sourceRef;
        TokenRef      tokenRef;

        SourceViewRef srcViewRef() const { return sourceRef; }
        TokenRef      tokRef() const { return tokenRef; }
    };

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

SWC_TEST_BEGIN(Compiler_AutoInlineExpandsSameModuleCrossFileBody)
{
    static constexpr std::string_view PROVIDER = R"(#global public
func increment(value: s32)->s32 => value + 1
)";
    static constexpr std::string_view CALLER = R"(#global public
func useIncrement(value: s32)->s32 => increment(value)
)";
    const fs::path providerPath = Unittest::makeTestSourcePath("Compiler", "AutoInlineProvider");
    const fs::path callerPath   = Unittest::makeTestSourcePath("Compiler", "AutoInlineCaller");

    CommandLine cmdLine;
    cmdLine.command         = CommandKind::Sema;
    cmdLine.name            = "compiler_auto_inline_same_module_cross_file";
    cmdLine.moduleNamespace = "CompilerAutoInline";
    cmdLine.silent          = true;
    cmdLine.numCores        = 6;
    cmdLine.buildCfg        = "release";
    cmdLine.files.insert(providerPath);
    cmdLine.files.insert(callerPath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t    errorsBefore = Stats::getNumErrors();
    RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance  compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, providerPath, PROVIDER);
    Unittest::registerTestSource(compiler, callerPath, CALLER);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    TaskContext compilerCtx(compiler);
    for (SourceFile* file : compiler.files())
    {
        if (!FileSystem::pathEquals(file->path(), callerPath))
            continue;

        Sema   sema(compilerCtx, file->nodePayloadContext(), false);
        size_t calls    = 0;
        size_t expanded = 0;
        Ast::visit(file->ast(), file->ast().root(), [&](AstNodeRef ref, const AstNode& node) {
            if (!node.is(AstNodeId::CallExpr))
                return Ast::VisitResult::Continue;

            ++calls;
            if (sema.hasSubstitute(ref))
            {
                const AstNodeRef bodyRef = sema.viewZero(ref).nodeRef();
                if (sema.inlinePayload(bodyRef))
                    ++expanded;
            }
            return Ast::VisitResult::Continue;
        });
        if (calls != 1 || expanded != 1)
            return Result::Error;
        return Result::Continue;
    }

    return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ExplicitInlineExpandsCrossFileBody)
{
    static constexpr std::string_view PROVIDER     = R"(#[Swag.Inline]
private func increment(value: s32)->s32 => value + 1
#[Swag.Inline]
func nested(value: s32)->s32 => increment(value) * 2
#[Swag.Inline]
func(T) identity(value: T)->T => value
struct Buffer { value: *s32 }
impl Buffer
{
    #[Swag.Inline]
    mtd const opIndexPtr(index: s32)->*s32 => .value
}
)";
    static constexpr std::string_view CALLER       = R"(func checkNested(value: s32)->s32 => nested(value)
func checkGeneric(value: s32)->s32 => identity(value)
func checkIndex(value: *s32)->s32
{
    let buffer = Buffer{value}
    return buffer[0]
}
)";
    const fs::path                    providerPath = Unittest::makeTestSourcePath("Compiler", "ExplicitInlineProvider");
    const fs::path                    callerPath   = Unittest::makeTestSourcePath("Compiler", "ExplicitInlineCaller");
    CommandLine                       cmdLine;
    cmdLine.command  = CommandKind::Sema;
    cmdLine.name     = "compiler_explicit_inline_cross_file";
    cmdLine.silent   = true;
    cmdLine.numCores = 6;
    cmdLine.files.insert(providerPath);
    cmdLine.files.insert(callerPath);
    CommandLineParser::refreshBuildCfg(cmdLine);
    const uint64_t    errorsBefore = Stats::getNumErrors();
    RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance  compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, providerPath, PROVIDER);
    Unittest::registerTestSource(compiler, callerPath, CALLER);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    size_t      calls    = 0;
    size_t      expanded = 0;
    TaskContext compilerCtx(compiler);
    for (SourceFile* file : compiler.files())
    {
        if (!FileSystem::pathEquals(file->path(), callerPath))
            continue;
        Sema sema(compilerCtx, file->nodePayloadContext(), false);
        Ast::visit(file->ast(), file->ast().root(), [&](AstNodeRef ref, const AstNode& node) {
            if (node.is(AstNodeId::CallExpr) || node.is(AstNodeId::IndexExpr))
            {
                ++calls;
                if (sema.hasSubstitute(ref))
                {
                    AstNodeRef bodyRef = sema.viewZero(ref).nodeRef();
                    if (sema.node(bodyRef).is(AstNodeId::IndexExpr))
                        bodyRef = sema.node(bodyRef).cast<AstIndexExpr>().nodeExprRef;
                    if (sema.inlinePayload(bodyRef))
                        ++expanded;
                }
            }
            return Ast::VisitResult::Continue;
        });
    }
    // A written '#[Inline]' is a contract: a body that calls, a generic instance, and an index
    // operator are all expanded in the file that calls them.
    if (calls != 3 || expanded != 3)
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

SWC_TEST_BEGIN(Compiler_AstVisitPreservesSiblingsAcrossPauseSkipAndRestart)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "AstVisitPauseSkipRestart", "");
    Ast&             ast = source.ast();

    std::array<AstNodeRef, 8> refs;
    for (AstNodeRef& ref : refs)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    const auto [root, skipped, original, oldLeaf, replacement, nested, last, unvisited] = refs;
    const std::array rootChildren = {skipped, original, last};
    ast.node<AstNodeId::ArrayLiteral>(root)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(rootChildren));
    const std::array skippedChildren = {unvisited};
    ast.node<AstNodeId::ArrayLiteral>(skipped)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(skippedChildren));
    const std::array originalChildren = {oldLeaf};
    ast.node<AstNodeId::ArrayLiteral>(original)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(originalChildren));
    const std::array replacementChildren = {nested};
    ast.node<AstNodeId::ArrayLiteral>(replacement)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(replacementChildren));

    std::array<AstNodeRef, 32> leaves;
    for (AstNodeRef& ref : leaves)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    ast.node<AstNodeId::ArrayLiteral>(nested)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(leaves));

    AstVisit visit;
    std::vector<AstNodeRef> entered;
    bool pausedPreChild = false;
    bool pausedPreNode = false;
    bool pausedPostNode = false;
    bool pausedPostChild = false;
    visit.setPreNodeVisitor([&](AstNode&) {
        const AstNodeRef ref = visit.currentNodeRef();
        if (visit.enteringState())
            entered.push_back(ref);
        if (ref == skipped)
            return Result::SkipChildren;
        if (ref == oldLeaf && !pausedPreNode)
        {
            pausedPreNode = true;
            return Result::Pause;
        }
        return Result::Continue;
    });
    visit.setPreChildVisitor([&](AstNode&, AstNodeRef& childRef) {
        const auto children = visit.currentChildren();
        const uint32_t index = visit.preChildIndex();
        if (index >= children.size() || children[index] != childRef)
            return Result::Error;
        if (visit.currentNodeRef() == root && !std::ranges::equal(children, rootChildren))
            return Result::Error;
        if (visit.currentNodeRef() == root && index == 1 && !pausedPreChild)
        {
            pausedPreChild = true;
            return Result::Pause;
        }
        return Result::Continue;
    });
    visit.setPostNodeVisitor([&](AstNode&) {
        if (visit.currentNodeRef() == skipped && !visit.currentChildren().empty())
            return Result::Error;
        if (visit.currentNodeRef() == original)
        {
            if (!pausedPostNode)
            {
                pausedPostNode = true;
                return Result::Pause;
            }
            visit.restartCurrentNode(replacement);
        }
        return Result::Continue;
    });
    visit.setPostChildVisitor([&](AstNode&, AstNodeRef& childRef) {
        if (visit.currentNodeRef() == root && childRef == original && !pausedPostChild)
        {
            pausedPostChild = true;
            return Result::Pause;
        }
        return Result::Continue;
    });
    visit.start(ast, root);
    bool stopped = false;
    for (size_t step = 0; step < 1000 && !stopped; ++step)
    {
        const AstVisitResult result = visit.step(compilerCtx);
        if (result == AstVisitResult::Error)
            return Result::Error;
        stopped = result == AstVisitResult::Stop;
    }

    std::vector<AstNodeRef> expected = {root, skipped, original, oldLeaf, replacement, nested};
    expected.insert(expected.end(), leaves.begin(), leaves.end());
    expected.push_back(last);
    if (!stopped || entered != expected || !pausedPreChild || !pausedPreNode || !pausedPostNode || !pausedPostChild)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AstVisitResolvesChildrenWithoutFollowingActiveAncestors)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "AstVisitResolvedChildren", "");
    Ast&             ast = source.ast();
    std::array<AstNodeRef, 6> refs;
    for (AstNodeRef& ref : refs)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    const auto [root, identity, substituted, replacement, cyclic, unresolved] = refs;
    const std::array children = {identity, substituted, cyclic, unresolved};
    ast.node<AstNodeId::ArrayLiteral>(root)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(children));

    AstVisit visit;
    visit.setMode(AstVisitMode::ResolveBeforeCallbacks);
    visit.setNodeRefResolver([&](AstNodeRef ref) {
        if (ref == substituted)
            return replacement;
        if (ref == cyclic)
            return root;
        if (ref == unresolved)
            return AstNodeRef::invalid();
        return ref;
    });
    std::vector<AstNodeRef> entered;
    visit.setPreNodeVisitor([&](AstNode&) {
        entered.push_back(visit.currentNodeRef());
        return Result::Continue;
    });
    const std::array resolvedChildren = {identity, replacement, cyclic, unresolved};
    visit.setPreChildVisitor([&](AstNode&, AstNodeRef& childRef) {
        if (!std::ranges::equal(visit.currentChildren(), resolvedChildren) || childRef != resolvedChildren[visit.preChildIndex()])
            return Result::Error;
        return Result::Continue;
    });
    visit.start(ast, root);
    bool stopped = false;
    for (size_t step = 0; step < 100 && !stopped; ++step)
    {
        const AstVisitResult result = visit.step(compilerCtx);
        if (result == AstVisitResult::Error)
            return Result::Error;
        stopped = result == AstVisitResult::Stop;
    }
    const std::array expected = {root, identity, replacement, cyclic, unresolved};
    if (!stopped || !std::ranges::equal(entered, expected))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_SymbolLocationSortKeepsStableTokenOrderWithinOneFile)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "SymbolLocationSort", "");
    const std::array views = {
        std::array{source.ast().srcView().ref(), compiler.addSourceView(source.ref()).ref()},
        std::array{compiler.addSourceView().ref(), compiler.addSourceView().ref()},
    };

    for (const auto& pair : views)
    {
        std::array symbols = {
            LocationSortTestSymbol{pair[0], TokenRef{9}},
            LocationSortTestSymbol{pair[1], TokenRef{9}},
            LocationSortTestSymbol{pair[0], TokenRef{10}},
            LocationSortTestSymbol{pair[1], TokenRef{0}},
            LocationSortTestSymbol{pair[0], TokenRef::invalid()},
            LocationSortTestSymbol{pair[1], TokenRef{1000000000}},
        };
        std::vector<LocationSortTestSymbol*> values = {nullptr, &symbols[2], &symbols[0], &symbols[0], &symbols[1], &symbols[0], &symbols[3], &symbols[4], &symbols[2], &symbols[5], nullptr};
        auto reference = values;
        SymbolSort::sortAndUnique(reference, SymbolSort::LocationKeyFactory<LocationSortTestSymbol>{.compiler = &compiler});
        SymbolSort::sortAndUniqueByLocation(values, compiler);
        const std::array expected = {&symbols[3], &symbols[0], &symbols[1], &symbols[0], &symbols[2], &symbols[5], &symbols[4]};
        if (values != reference || !std::ranges::equal(values, expected))
            return Result::Error;

        const std::array smallInputs = {
            std::vector<LocationSortTestSymbol*>{},
            std::vector<LocationSortTestSymbol*>{nullptr, nullptr},
            std::vector<LocationSortTestSymbol*>{nullptr, &symbols[0], nullptr},
        };
        for (const auto& input : smallInputs)
        {
            values    = input;
            reference = input;
            SymbolSort::sortAndUnique(reference, SymbolSort::LocationKeyFactory<LocationSortTestSymbol>{.compiler = &compiler});
            SymbolSort::sortAndUniqueByLocation(values, compiler);
            if (values != reference)
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_SymbolLocationSortKeepsCompositeKeysAcrossFiles)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    const fs::path   path      = Unittest::makeTestSourcePath("Compiler", "SymbolLocationSortPrefixes");
    SourceFile&      first     = Unittest::addTestSource(compilerCtx, path, "");
    SourceFile&      longer    = Unittest::addTestSource(compilerCtx, fs::path(path.string() + "a"), "");
    SourceFile&      equalPath = Unittest::addTestSource(compilerCtx, path, "");
    std::array symbols = {
        LocationSortTestSymbol{first.ast().srcView().ref(), TokenRef{9}},
        LocationSortTestSymbol{equalPath.ast().srcView().ref(), TokenRef{9}},
        LocationSortTestSymbol{longer.ast().srcView().ref(), TokenRef::invalid()},
        LocationSortTestSymbol{compiler.addSourceView().ref(), TokenRef{0}},
    };
    std::vector<LocationSortTestSymbol*> values = {nullptr, &symbols[0], &symbols[0], &symbols[1], &symbols[0], &symbols[2], &symbols[3], nullptr};
    auto reference = values;
    SymbolSort::sortAndUnique(reference, SymbolSort::LocationKeyFactory<LocationSortTestSymbol>{.compiler = &compiler});
    SymbolSort::sortAndUniqueByLocation(values, compiler);
    if (values != reference)
        return Result::Error;
    // The longer path's 'a' precedes the shorter path's '|' delimiter.
    if (std::ranges::find(values, &symbols[2]) >= std::ranges::find(values, &symbols[0]))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AstVisitKeepsDepthFirstOrderWithPendingSiblings)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "AstVisitPendingSiblings", "");
    Ast&             ast    = source.ast();
    std::array<AstNodeRef, 5> refs;
    for (AstNodeRef& ref : refs)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    const auto [root, branch, skipped, skippedLeaf, last] = refs;

    std::vector<AstNodeRef> leaves;
    for (size_t index = 0; index < 48; ++index)
        leaves.push_back(ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first);
    ast.node<AstNodeId::ArrayLiteral>(branch)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(leaves));
    const std::array skippedChildren = {skippedLeaf};
    ast.node<AstNodeId::ArrayLiteral>(skipped)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(skippedChildren));
    // A repeated child is visited again; an invalid span entry is ignored when popped.
    const std::array rootChildren = {branch, AstNodeRef::invalid(), skipped, last, branch};
    ast.node<AstNodeId::ArrayLiteral>(root)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(rootChildren));

    std::vector<AstNodeRef> visited;
    Ast::visit(ast, root, [&](AstNodeRef ref, const AstNode&) {
        visited.push_back(ref);
        return ref == skipped ? Ast::VisitResult::Skip : Ast::VisitResult::Continue;
    });
    std::vector<AstNodeRef> expected = {root, branch};
    expected.insert(expected.end(), leaves.begin(), leaves.end());
    expected.insert(expected.end(), {skipped, last, branch});
    expected.insert(expected.end(), leaves.begin(), leaves.end());
    if (visited != expected)
        return Result::Error;

    visited.clear();
    Ast::visit(ast, root, [&](AstNodeRef ref, const AstNode&) {
        visited.push_back(ref);
        if (ref == last)
            return Ast::VisitResult::Stop;
        return ref == skipped ? Ast::VisitResult::Skip : Ast::VisitResult::Continue;
    });
    expected.resize(2 + leaves.size() + 2);
    if (visited != expected)
        return Result::Error;

    visited.clear();
    Ast::visit(ast, root, [&](AstNodeRef ref, const AstNode&) {
        visited.push_back(ref);
        return Ast::VisitResult::Skip;
    });
    if (visited != std::vector{root})
        return Result::Error;
    Ast::visit(ast, AstNodeRef::invalid(), [&](AstNodeRef ref, const AstNode&) {
        visited.push_back(ref);
        return Ast::VisitResult::Continue;
    });
    if (visited != std::vector{root})
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AutoInlineBlockedCallsUseDirectEdgesAndOriginalNameScopes)
{
    static constexpr std::string_view SOURCE = R"(#global private
func directExternal() { foreignMeta() }
func transitive() { directExternal() }
func absentTarget() { unresolvedCall() }
func overloaded()->s32 => 1
func overloaded(value: s32)->func||()->s32
{
    return func|value|()->s32 { return value }
}
func callsOverload() { overloaded() }
func localOnly() { foreignUnsupported() }
func useCandidates()
{
    transitive()
    absentTarget()
    callsOverload()
    localOnly()
}
)";
    std::string otherSource = R"(#global private
#[Swag.Macro]
func foreignMeta() {}
func foreignUnsupported()->func||()->s32
{
    return func||()->s32 { return 1 }
}
)";
    for (size_t index = 0; index < 80; ++index)
        otherSource += std::format("#[Swag.Mixin]\nfunc unusedMeta{}() {{}}\n", index);

    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "AutoInlineBlockedCalls", SOURCE);
    SourceFile&      other  = Unittest::addTestSource(compilerCtx, "Compiler", "AutoInlineBlockedCallTargets", otherSource);
    Lexer            lexer;
    Parser           parser;
    const std::array moduleAsts = {&source.ast(), &other.ast()};
    for (Ast* ast : moduleAsts)
    {
        lexer.tokenize(compilerCtx, ast->srcView(), LexerFlagsE::Default);
        if (ast->srcView().mustSkip())
            return Result::Error;
        parser.parse(compilerCtx, *ast);
    }
    Parser::finalizeAutoInlineCandidates(moduleAsts);

    for (const std::string_view name : {"directExternal", "callsOverload"})
    {
        const AstFunctionDecl* decl = findFunctionDecl(source.ast(), name);
        if (!decl || decl->hasFlag(AstFunctionFlagsE::AutoInlineBody))
            return Result::Error;
    }
    // Blocking is not transitive, absent names are harmless, and unsupported bodies
    // in another Ast do not become local targets. Meta-function names remain global.
    for (const std::string_view name : {"transitive", "absentTarget", "localOnly"})
    {
        const AstFunctionDecl* decl = findFunctionDecl(source.ast(), name);
        if (!decl || !decl->hasFlag(AstFunctionFlagsE::AutoInlineBody))
            return Result::Error;
    }

    SourceFile& clean = Unittest::addTestSource(compilerCtx, "Compiler", "AutoInlineWithoutBlockedTargets", "func leaf() {}\nfunc wrapper() { leaf() }\nfunc useWrapper() { wrapper() }\n");
    lexer.tokenize(compilerCtx, clean.ast().srcView(), LexerFlagsE::Default);
    if (clean.ast().srcView().mustSkip())
        return Result::Error;
    parser.parse(compilerCtx, clean.ast());
    const std::array cleanAsts = {&clean.ast()};
    Parser::finalizeAutoInlineCandidates(cleanAsts);
    const AstFunctionDecl* wrapper = findFunctionDecl(clean.ast(), "wrapper");
    if (!wrapper || !wrapper->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
