#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroRelocation.h"
#include "Backend/Native/SymbolSort.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticBuilder.h"
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

    bool sameSourceRange(const SourceCodeRange& lhs, const SourceCodeRange& rhs)
    {
        return lhs.srcView == rhs.srcView && lhs.offset == rhs.offset && lhs.len == rhs.len &&
               lhs.line == rhs.line && lhs.column == rhs.column;
    }

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

SWC_TEST_BEGIN(Compiler_ParserWorkersKeepFileDiagnosticsIsolated)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    compilerCtx.setMuteOutput(true);
    compilerCtx.setReportToStats(false);

    std::vector<SourceFile*> files;
    for (uint32_t i = 0; i < 64; ++i)
    {
        const std::string_view source = i % 4 == 0 ? "func 0() {}" : "func parsed() {}";
        files.push_back(&Unittest::addTestSource(compilerCtx, "Compiler", std::format("ParserWorker_{}", i), source));
    }
    const TaskContext* currentBefore = TaskContext::current();
    parseSourceFiles(compilerCtx, files);
    if (TaskContext::current() != currentBefore || compilerCtx.hasError())
    {
        std::println(stderr, "parser batch changed its caller context: current={}, error={}", TaskContext::current() != currentBefore, compilerCtx.hasError());
        return Result::Error;
    }

    for (uint32_t i = 0; i < files.size(); ++i)
    {
        if (i % 4 == 0)
        {
            if (!files[i]->hasError())
            {
                std::println(stderr, "parser input {} has no error recorded", i);
                return Result::Error;
            }
        }
        else if (files[i]->hasError() || !findFunctionDecl(files[i]->ast(), "parsed"))
        {
            std::println(stderr, "parser input {} has no clean function declaration: error={}", i, files[i]->hasError());
            return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ImportedApisDoNotRetainDocumentationTrivia)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Doc;
    CompilerInstance                 compiler(ctx.global(), cmdLine);
    TaskContext                      compilerCtx(compiler);
    constexpr std::string_view       source   = "// Function documentation.\nfunc parsed()->s32 => 42\n";
    SourceFile&                      current  = Unittest::addTestSource(compilerCtx, "Compiler", "CurrentDocumentation", source);
    SourceFile&                      imported = Unittest::addTestSource(compilerCtx, "Compiler", "ImportedDocumentation", source, FileFlagsE::ImportedApi);
    const std::array<SourceFile*, 2> files    = {&current, &imported};
    parseSourceFiles(compilerCtx, files, {.emitTrivia = true});

    if (current.ast().srcView().trivia().empty() || !imported.ast().srcView().trivia().empty())
        return Result::Error;
    const AstFunctionDecl* declaration = findFunctionDecl(imported.ast(), "parsed");
    if (!declaration || imported.ast().srcView().tokenCodeRange(compilerCtx, declaration->tokNameRef).line != 2)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_EofDiagnosticsKeepFileAndTaskState)
{
    for (const bool oneLine : {false, true})
    {
        CommandLine cmdLine;
        cmdLine.diagOneLine = oneLine;
        CompilerInstance compiler(ctx.global(), cmdLine);
        TaskContext      compilerCtx(compiler);
        compilerCtx.setMuteOutput(true);
        compilerCtx.setReportToStats(false);

        for (uint32_t index = 0; index < 2; ++index)
        {
            SourceFile& file = Unittest::addTestSource(compilerCtx, "Compiler", std::format("EofOwner_{}", index), "func");
            TaskContext fileCtx(compilerCtx);
            SWC_RESULT(file.loadContent(fileCtx));
            SWC_RESULT(parseLoadedSourceFile(fileCtx, file, {}));
            if (!file.hasError() || !fileCtx.hasError() || !file.hasErrorLineInRange(1, 1))
                return Result::Error;
        }
        if (compilerCtx.hasError())
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AstSourceRangesKeepCachedStartCoordinates)
{
    struct TestCase
    {
        std::string_view source;
        std::string_view sameLineSpan;
    };
    constexpr TestCase cases[] = {
        {"\t/*\xC3\xA9*/ left + right\n", "left + right"},
        {"\tleft +\n right\n", "left +"},
        {"\tleft\n + right\n", "+ right"},
        {"\tleft + right", "left + right"},
    };

    for (const uint32_t tabSize : {4u, 8u})
    {
        CommandLine cmdLine;
        cmdLine.tabSize = tabSize;
        CompilerInstance compiler(ctx.global(), cmdLine);
        TaskContext      compilerCtx(compiler);
        uint32_t         sourceIndex = 0;

        for (const TestCase& test : cases)
        {
            for (const uint32_t lineOffset : {0u, 7u})
            {
                for (const bool haveLines : {true, false})
                {
                    SourceFile& file = Unittest::addTestSource(compilerCtx, "Compiler", std::format("AstRangeCoordinates_{}", sourceIndex++), test.source);
                    SWC_RESULT(file.loadContent(compilerCtx));
                    SourceView& view = file.ast().srcView();
                    Lexer       lexer;
                    lexer.tokenize(compilerCtx, view, LexerFlagsE::Default);
                    view.setLineOffset(lineOffset);
                    if (!haveLines)
                        view.lines().clear();

                    TokenRef leftToken;
                    TokenRef rightToken;
                    TokenRef operatorToken;
                    for (uint32_t index = 0; index < view.numTokens(); ++index)
                    {
                        const TokenRef token{index};
                        if (view.token(token).id == TokenId::EndOfFile)
                            continue;
                        const std::string_view text = view.tokenString(token);
                        if (text == "left")
                            leftToken = token;
                        else if (text == "right")
                            rightToken = token;
                        else if (text == "+")
                            operatorToken = token;
                    }
                    if (leftToken.isInvalid() || rightToken.isInvalid() || operatorToken.isInvalid())
                        return Result::Error;

                    Ast& ast                     = file.ast();
                    const auto [leftRef, left]   = ast.makeNode<AstNodeId::Identifier>(leftToken);
                    const auto [rightRef, right] = ast.makeNode<AstNodeId::Identifier>(rightToken);
                    const auto [rootRef, root]   = ast.makeNode<AstNodeId::BinaryExpr>(operatorToken);
                    SWC_UNUSED(left);
                    SWC_UNUSED(right);
                    SWC_UNUSED(rootRef);
                    root->nodeLeftRef  = leftRef;
                    root->nodeRightRef = rightRef;

                    const size_t    start = haveLines ? test.source.find(test.sameLineSpan) : test.source.find("left");
                    const size_t    len   = haveLines ? test.sameLineSpan.size() : test.source.find("right") + 5 - start;
                    SourceCodeRange expected;
                    expected.fromOffset(compilerCtx, view, static_cast<uint32_t>(start), static_cast<uint32_t>(len));
                    if (!sameSourceRange(root->codeRangeWithChildren(compilerCtx, ast, view), expected) ||
                        !sameSourceRange(root->codeRangeWithChildren(compilerCtx, ast), expected))
                        return Result::Error;
                }
            }
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AstSourceRangesPreserveBoundaryFallbacks)
{
    CommandLine cmdLine;
    cmdLine.tabSize = 4;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    uint32_t         sourceIndex = 0;

    for (const std::string_view source : {std::string_view{}, std::string_view{" \tleft"}})
    {
        SourceFile& file = Unittest::addTestSource(compilerCtx, "Compiler", std::format("AstRangeFallback_{}", sourceIndex++), source);
        SWC_RESULT(file.loadContent(compilerCtx));
        Ast&        ast  = file.ast();
        SourceView& view = ast.srcView();
        Lexer       lexer;
        lexer.tokenize(compilerCtx, view, LexerFlagsE::Default);
        view.setLineOffset(7);

        for (const TokenRef token : {TokenRef::invalid(), TokenRef{view.numTokens()}, TokenRef{view.numTokens() - 1}})
        {
            const auto [nodeRef, node] = ast.makeNode<AstNodeId::Identifier>(token);
            SWC_UNUSED(nodeRef);
            if (!sameSourceRange(node->codeRangeWithChildren(compilerCtx, ast, view), {}))
                return Result::Error;
        }

        const auto [nodeRef, node] = ast.makeNode<AstNodeId::Identifier>(TokenRef{0});
        SWC_UNUSED(nodeRef);
        if (!source.empty())
        {
            // An incomplete token retains the existing best-effort range at the view's start.
            view.tokens()[0].byteLength = static_cast<uint32_t>(source.size() + 1);
            SourceCodeRange expected;
            expected.fromOffset(compilerCtx, view, 0, 1);
            if (!sameSourceRange(node->codeRangeWithChildren(compilerCtx, ast, view), expected))
                return Result::Error;
        }

        view.tokens().clear();
        if (!sameSourceRange(node->codeRangeWithChildren(compilerCtx, ast, view), {}))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_RangeEndLinesMatchByteBoundaries)
{
    const std::array sources = {std::string_view{}, std::string_view{"\tfirst\r\n\xC3\xA9\tlast\n"}, std::string_view{"one line"}};
    for (const std::string_view source : sources)
    {
        SourceView view(SourceViewRef{0}, nullptr, source);
        view.lines().push_back(0);
        for (uint32_t offset = 0; offset < source.size(); ++offset)
        {
            if (source[offset] == '\n')
                view.lines().push_back(offset + 1);
        }

        for (const uint32_t lineOffset : {0u, 7u})
        {
            view.setLineOffset(lineOffset);
            for (uint32_t offset = 0; offset <= source.size(); ++offset)
            {
                for (uint32_t len = 0; len <= source.size() - offset; ++len)
                {
                    const SourceCodeRange range{.srcView = &view, .offset = offset, .len = len, .line = 19};
                    const uint32_t        expected = len ? 1 + lineOffset + static_cast<uint32_t>(std::count(source.begin(), source.begin() + offset + len - 1, '\n')) : 19;
                    if (range.endLine(ctx) != expected)
                        return Result::Error;
                }
            }
        }

        SourceCodeRange range{.srcView = &view, .offset = static_cast<uint32_t>(source.size()), .len = 1, .line = 19};
        if (range.endLine(ctx) != 0)
            return Result::Error;
        range.srcView = nullptr;
        if (range.endLine(ctx) != 19)
            return Result::Error;

        view.lines().clear();
        range.srcView = &view;
        range.offset  = 0;
        if (range.endLine(ctx) != 0)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ZeroLengthDiagnosticRangesKeepEofLocations)
{
    struct TestCase
    {
        std::string_view source;
        uint32_t         line;
        uint32_t         column;
    };
    constexpr TestCase cases[] = {
        {"", 1, 1},
        {"func", 1, 5},
        {"func\n", 2, 1},
        {"func\r\n", 2, 1},
        {"\tfoo", 1, 8},
        {"// \xC3\xA9", 1, 5},
    };
    for (const bool oneLine : {false, true})
    {
        CommandLine cmdLine;
        cmdLine.logColor        = false;
        cmdLine.diagOneLine     = oneLine;
        cmdLine.tabSize         = 4;
        cmdLine.filePathDisplay = FileSystem::FilePathDisplayMode::AsIs;
        CompilerInstance compiler(ctx.global(), cmdLine);
        TaskContext      compilerCtx(compiler);
        compilerCtx.setMuteOutput(true);
        compilerCtx.setReportToStats(false);

        for (uint32_t index = 0; index < std::size(cases); ++index)
        {
            const TestCase& test = cases[index];
            SourceFile&     file = Unittest::addTestSource(compilerCtx, "Compiler", std::format("EofLocation_{}", index), test.source);
            SWC_RESULT(file.loadContent(compilerCtx));
            SourceView& view = file.ast().srcView();
            Lexer       lexer;
            lexer.tokenize(compilerCtx, view, LexerFlagsE::Default);
            view.setLineOffset(7);
            SourceCodeRange range;
            range.fromOffset(compilerCtx, view, static_cast<uint32_t>(test.source.size()), 0);
            if (range.srcView != &view || range.offset != test.source.size() || range.len || range.line != test.line + 7 || range.column != test.column)
                return Result::Error;

            const SourceCodeRange tokenRange = view.tokenCodeRange(compilerCtx, TokenRef{view.numTokens() - 1});
            if (tokenRange.srcView != &view || tokenRange.offset != range.offset || tokenRange.len || tokenRange.line != range.line || tokenRange.column != range.column)
                return Result::Error;

            Utf8 previous;
            for (uint32_t overload = 0; overload < 3; ++overload)
            {
                Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_expr_not_const, file.ref());
                if (overload == 0)
                    diag.last().addSpan(&view, range.offset, 0);
                else if (overload == 1)
                    diag.last().addSpan(range);
                else
                    diag.last().addSpan(range, DiagnosticId::None);
                if (!diag.last().hasSpans())
                    return Result::Error;
                const Utf8 text     = DiagnosticBuilder(compilerCtx, diag).build();
                const Utf8 location = file.formatFileLocation(&compilerCtx, range.line, range.column, range.column);
                if (text.find(location) == Utf8::npos || (overload && text != previous))
                    return Result::Error;
                previous = text;
            }
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DuplicateDisplayStillVerifiesEachOwner)
{
    for (const bool oneLine : {false, true})
    {
        CommandLine cmdLine;
        cmdLine.sourceDrivenTest = true;
        cmdLine.diagOneLine      = oneLine;
        CompilerInstance compiler(ctx.global(), cmdLine);
        TaskContext      compilerCtx(compiler);
        compilerCtx.setMuteOutput(true);
        const uint64_t    errorsBefore = Stats::getNumErrors();
        RestoreErrorCount restoreErrors{errorsBefore};
        Utf8              firstText;
        for (uint32_t index = 0; index < 2; ++index)
        {
            SourceFile& file = Unittest::addTestSource(compilerCtx, "Compiler", std::format("DuplicateDisplay_{}", index), "// swc-expected-error@* {{sema_err_expr_not_const}}\n");
            TaskContext fileCtx(compilerCtx);
            SWC_RESULT(file.loadContent(fileCtx));
            file.unitTest().tokenize(fileCtx);
            if (!file.unitTest().hasUntouchedErrorDirectiveInLineRange(1, 1, "sema_err_"))
                return Result::Error;

            // Deliberately unlocated text keeps the display key identical across owners even
            // after EOF ranges become located. Publication must not depend on that key.
            const Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_expr_not_const, file.ref());
            const Utf8       text = DiagnosticBuilder(fileCtx, diag).build();
            if (index && text != firstText)
                return Result::Error;
            firstText = text;
            diag.report(fileCtx);
            if (!file.hasError() || !fileCtx.hasError() || file.unitTest().hasUntouchedErrorDirectiveInLineRange(1, 1, "sema_err_"))
                return Result::Error;
            if (compiler.tryRegisterReportedDiagnostic(text))
                return Result::Error;

            // A second task reporting the same site still fails, but adds neither display text
            // nor an unexpected-error statistic after the expectation has been consumed.
            TaskContext repeatedCtx(compilerCtx);
            diag.report(repeatedCtx);
            if (!repeatedCtx.hasError() || Stats::getNumErrors() != errorsBefore)
                return Result::Error;
        }
    }
}
SWC_TEST_END()

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

#[Swag.Foreign]
func bodylessCall(value: s32 = leaf(1))->s32

func wrapsBodyless(value: s32)->s32 => bodylessCall(value)

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

func memoryCall(a, b: [*] u8, size: u64)->s32 => Swag.memcmp(a, b, size)

func memoryCaller(a, b: [*] u8, size: u64)->s32
{
    return memoryCall(a, b, size) + memoryCall(b, a, size)
}

func hotMemoryCall(a, b: [*] u8, size: u64)->s32 => Swag.memcmp(a, b, size)

func hotMemoryCaller(a, b: [*] u8, size: u64)->s32
{
    var result = 0
    for i in 2
    {
        result += hotMemoryCall(a, b, size)
        result += hotMemoryCall(b, a, size)
    }
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
    let foreignValue = wrapsBodyless(7)
}
)";
    // If call-graph names from separate Asts are merged, the first source's
    // singleCall -> leaf and useCandidates -> singleCall edges combine with this edge into a
    // false cycle. Candidate discovery is local to each Ast, so their recursion graphs stay separate.
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
    const AstFunctionDecl* memoryCall      = findFunctionDecl(sourceFile.ast(), "memoryCall");
    const AstFunctionDecl* hotMemoryCall   = findFunctionDecl(sourceFile.ast(), "hotMemoryCall");
    const AstFunctionDecl* recursiveFirst  = findFunctionDecl(sourceFile.ast(), "recursiveFirst");
    const AstFunctionDecl* recursiveSecond = findFunctionDecl(sourceFile.ast(), "recursiveSecond");
    const AstFunctionDecl* errorManaged    = findFunctionDecl(sourceFile.ast(), "errorManaged");
    const AstFunctionDecl* wrapsMixin      = findFunctionDecl(sourceFile.ast(), "wrapsMixin");
    const AstFunctionDecl* wrapsClosure    = findFunctionDecl(sourceFile.ast(), "wrapsClosureProvider");
    if (!cheapCall || !addressTaken || !singleCall || !repeatedCall || !memoryCall || !hotMemoryCall || !recursiveFirst || !recursiveSecond || !errorManaged || !wrapsMixin || !wrapsClosure)
        return Result::Error;
    if (!cheapCall->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (addressTaken->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (singleCall->autoInlineCost <= K_AUTO_INLINE_MAX_BODY_TOKENS || !singleCall->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (repeatedCall->autoInlineCost <= K_AUTO_INLINE_MAX_BODY_TOKENS || repeatedCall->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (!memoryCall->hasFlag(AstFunctionFlagsE::AutoInlineHasCalls) || memoryCall->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (!hotMemoryCall->hasFlag(AstFunctionFlagsE::AutoInlineHasCalls) || !hotMemoryCall->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (recursiveFirst->hasFlag(AstFunctionFlagsE::AutoInlineBody) || recursiveSecond->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (errorManaged->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (wrapsMixin->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    if (wrapsClosure->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
    const AstFunctionDecl* wrapsBodyless = findFunctionDecl(sourceFile.ast(), "wrapsBodyless");
    if (!wrapsBodyless || wrapsBodyless->hasFlag(AstFunctionFlagsE::AutoInlineBody))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AutoInlineExpandsSameModuleCrossFileBody)
{
    static constexpr std::string_view PROVIDER     = R"(#global public
func mix(value: u64)->u64
{
    var result = value
    result = (result + 1) * 3
    result = (result + 2) * 5
    result = (result + 3) * 7
    result = (result + 4) * 11
    result = (result + 5) * 13
    result = (result + 6) * 17
    result = (result + 7) * 19
    result = (result + 8) * 23
    result = (result + 9) * 29
    return result
}
)";
    static constexpr std::string_view CALLER       = R"(#global public
func useMix(value: u64)->u64 => mix(value) + mix(value + 1)
)";
    const fs::path                    providerPath = Unittest::makeTestSourcePath("Compiler", "AutoInlineProvider");
    const fs::path                    callerPath   = Unittest::makeTestSourcePath("Compiler", "AutoInlineCaller");

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

    bool checkedProviderCost = false;
    for (SourceFile* file : compiler.files())
    {
        if (!FileSystem::pathEquals(file->path(), providerPath))
            continue;
        const AstFunctionDecl* mix = findFunctionDecl(file->ast(), "mix");
        if (!mix || mix->autoInlineCost <= 80 || mix->autoInlineCost > K_AUTO_INLINE_MAX_BODY_TOKENS || !mix->hasFlag(AstFunctionFlagsE::AutoInlineBody))
            return Result::Error;
        checkedProviderCost = true;
        break;
    }
    if (!checkedProviderCost)
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
        if (calls != 2 || expanded != 2)
            return Result::Error;
        return Result::Continue;
    }

    return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AutoInlineCompileTimeCallsKeepTheirExecutionContext)
{
    static constexpr std::string_view SOURCE     = R"(#global private
var initialized: u32
var expandedGlobal: u32
var calledGlobal: u32

func rotate(value, count: u64)->u64 => ((value >> count) | (value << (32 - count))) & 0xFFFFFFFF
func identity(value: u32)->u32 => value
func setExpanded(value: u32) { expandedGlobal = value }

#[Swag.NoInline]
func setCalled(value: u32) { calledGlobal = value }

func compute(value: u32)->u32
{
    var result = value + 1
    result *= 3
    return result
}

#[Swag.Compiler]
func initialize(value: u32) { initialized = value }

#run
{
    var value = 0x12345678'u64
    Swag.assert(rotate(value, 8) == 0x78123456)
    var input = 13'u32
    Swag.assert(compute(input) == 42)
    initialize(42)
    Swag.assert(initialized == 42)
    setExpanded(42)
    setCalled(42)
    Swag.assert(expandedGlobal == calledGlobal)
}

const copied = #run identity(42'u32)
#assert(copied == 42)
)";
    const fs::path                    sourcePath = Unittest::makeTestSourcePath("Compiler", "AutoInlineCompileTimeContext");

    CommandLine cmdLine;
    cmdLine.command  = CommandKind::Sema;
    cmdLine.name     = "compiler_auto_inline_compile_time";
    cmdLine.silent   = true;
    cmdLine.numCores = 6;
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t    errorsBefore = Stats::getNumErrors();
    RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance  compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, SOURCE);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    TaskContext compilerCtx(compiler);
    // Inlining a runtime helper into #run must keep the same segment as an ordinary call.
    std::optional<DataSegmentKind> expandedStorage;
    std::optional<DataSegmentKind> calledStorage;
    for (SourceFile* file : compiler.files())
    {
        if (!FileSystem::pathEquals(file->path(), sourcePath))
            continue;
        Sema sema(compilerCtx, file->nodePayloadContext(), false);
        Ast::visit(file->ast(), file->ast().root(), [&](AstNodeRef ref, const AstNode& node) {
            if (!node.is(AstNodeId::SingleVarDecl))
                return Ast::VisitResult::Continue;
            const Symbol* symbol = sema.viewSymbol(ref).sym();
            if (!symbol || !symbol->isVariable())
                return Ast::VisitResult::Continue;
            if (symbol->name(compilerCtx) == "expandedGlobal")
                expandedStorage = symbol->cast<SymbolVariable>().globalStorageKind();
            if (symbol->name(compilerCtx) == "calledGlobal")
                calledStorage = symbol->cast<SymbolVariable>().globalStorageKind();
            return Ast::VisitResult::Continue;
        });
    }
    if (!expandedStorage || !calledStorage || expandedStorage != calledStorage)
        return Result::Error;

    bool checkedRun = false;
    for (const SymbolFunction* function : compiler.jitPreparedFunctionsSnapshot())
    {
        const SourceFile* file = compiler.sourceViewFile(*function);
        if (!file || !FileSystem::pathEquals(file->path(), sourcePath) || !function->name(compilerCtx).starts_with("__run"))
            continue;
        checkedRun = true;
        for (const MicroRelocation& relocation : function->loweredCode().codeRelocations)
        {
            if (relocation.kind != MicroRelocation::Kind::LocalFunctionAddress || !relocation.targetSymbol)
                continue;
            const auto name = relocation.targetSymbol->name(compilerCtx);
            if (name == "rotate" || name == "compute" || name == "initialize" || name == "identity" || name == "setExpanded")
                return Result::Error;
        }
    }
    return checkedRun ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_CrossFileInlineTypePatternKeepsSourceToken)
{
    static constexpr std::string_view PROVIDER     = R"(#[Swag.Inline]
func matchesInteger(target: typeinfo)->bool => target is s32
)";
    static constexpr std::string_view CALLER       = R"(func checkPattern(target: typeinfo)->bool
{
    if matchesInteger(target) do
        return true
    return false
}
)";
    const fs::path                    providerPath = Unittest::makeTestSourcePath("Compiler", "InlineTypePatternProvider");
    const fs::path                    callerPath   = Unittest::makeTestSourcePath("Compiler", "InlineTypePatternCaller");

    CommandLine cmdLine;
    cmdLine.command         = CommandKind::Sema;
    cmdLine.name            = "compiler_cross_file_inline_type_pattern";
    cmdLine.moduleNamespace = "CompilerInlineTypePattern";
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
    mtd const opIndexPtr(_: s32)->*s32 => .value
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

SWC_TEST_BEGIN(Compiler_TrailingCodeBlockSearchCrossesSpanChunks)
{
    std::string      source            = R"(#global private

#[Swag.Macro]
func execute(stmt: #code)
{
    #inject(stmt)
}

func trailingUse()
{
)";
    constexpr size_t leadingStatements = PagedStore::K_DEFAULT_PAGE_SIZE / sizeof(AstNodeRef) + 1;
    for (size_t index = 0; index < leadingStatements; ++index)
        source += "    discard 0\n";
    source += R"(    execute()
    {
        #assert(42 == 42)
    }
}

#run
{
    trailingUse()
}
)";

    const fs::path sourcePath = Unittest::makeTestSourcePath("Compiler", "TrailingCodeBlockChunks");
    CommandLine    cmdLine;
    cmdLine.command         = CommandKind::Sema;
    cmdLine.name            = "compiler_trailing_code_block_chunks";
    cmdLine.moduleNamespace = "CompilerTrailingChunks";
    cmdLine.silent          = true;
    cmdLine.numCores        = 6;
    cmdLine.files.insert(sourcePath);
    CommandLineParser::refreshBuildCfg(cmdLine);

    const uint64_t    errorsBefore = Stats::getNumErrors();
    RestoreErrorCount restoreErrors{errorsBefore};
    CompilerInstance  compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, sourcePath, source);
    Command::sema(compiler);
    if (Stats::getNumErrors() != errorsBefore)
        return Result::Error;

    for (SourceFile* file : compiler.files())
    {
        if (!FileSystem::pathEquals(file->path(), sourcePath))
            continue;
        const AstFunctionDecl* declaration = findFunctionDecl(file->ast(), "trailingUse");
        if (!declaration || declaration->nodeBodyRef.isInvalid())
        {
            std::println(stderr, "trailing-block regression: missing function body");
            return Result::Error;
        }
        const auto* body = file->ast().node(declaration->nodeBodyRef).safeCast<AstEmbeddedBlock>();
        if (!body)
        {
            std::println(stderr, "trailing-block regression: unexpected body kind {}", Ast::nodeIdName(file->ast().node(declaration->nodeBodyRef).id()));
            return Result::Error;
        }
        const auto statements = file->ast().nodeSpan(body->spanChildrenRef);
        const auto first      = statements.chunksBegin();
        if (first.total <= first->count)
        {
            std::println(stderr, "trailing-block regression: {} statements fit in the first {}-element chunk", first.total, first->count);
            return Result::Error;
        }
        return Result::Continue;
    }
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

SWC_TEST_BEGIN(Compiler_AstNodeSpanPreservesOrderAcrossPagesAndGrowth)
{
    CommandLine             cmdLine;
    CompilerInstance        compiler(ctx.global(), cmdLine);
    TaskContext             compilerCtx(compiler);
    SourceFile&             source = Unittest::addTestSource(compilerCtx, "Compiler", "AstNodeSpanPages", "");
    Ast&                    ast    = source.ast();
    std::vector<AstNodeRef> refs;
    for (size_t i = 0; i < 2049; ++i)
        refs.push_back(ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first);

    const auto invalid = ast.nodeSpan(SpanRef::invalid());
    if (!invalid.empty() || invalid.chunksBegin() != invalid.chunksEnd())
        return Result::Error;
    const auto invalidRefs = ast.nodeRefs(SpanRef::invalid());
    if (!invalidRefs.empty() || invalidRefs.size())
        return Result::Error;
    for (const size_t count : {size_t{0}, size_t{1}, refs.size()})
    {
        const SpanRef ref     = ast.pushSpan(std::span<const AstNodeRef>(refs.data(), count));
        const auto    view    = ast.nodeSpan(ref);
        const auto    indexed = ast.nodeRefs(ref);
        // Appending more pages must not invalidate an earlier view.
        ast.pushSpan(std::span<const AstNodeRef>(refs));
        if (view.size() != count)
            return Result::Error;
        if (indexed.size() != count || indexed.empty() != (count == 0))
            return Result::Error;
        if (count == 1 && ast.oneNode(ref) != refs.front())
            return Result::Error;
        size_t next = 0;
        for (auto chunk = view.chunksBegin(); chunk != view.chunksEnd(); ++chunk)
        {
            if (!chunk->count || chunk->count > count - next)
                return Result::Error;
            for (const AstNodeRef& nodeRef : std::span(static_cast<const AstNodeRef*>(chunk->ptr), chunk->count))
            {
                if (std::addressof(indexed[next]) != std::addressof(nodeRef))
                    return Result::Error;
                if (nodeRef != refs[next++])
                    return Result::Error;
            }
        }
        if (next != count)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_StaticSwitchVisitsAllValuesBeforeBodiesAndCaseLabels)
{
    CommandLine               cmdLine;
    CompilerInstance          compiler(ctx.global(), cmdLine);
    TaskContext               compilerCtx(compiler);
    SourceFile&               source = Unittest::addTestSource(compilerCtx, "Compiler", "StaticSwitchChildOrder", "");
    Ast&                      ast    = source.ast();
    std::array<AstNodeRef, 7> values;
    for (auto& ref : values)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    std::array<AstNodeRef, 3> cases;
    for (auto& ref : cases)
        ref = ast.makeNode<AstNodeId::CompilerSwitchCase>(TokenRef::invalid()).first;
    ast.node<AstNodeId::CompilerSwitchCase>(cases[0])->spanExprRef = ast.pushSpan(std::span<const AstNodeRef>(&values[1], 2));
    // The middle case is a default, with no value expression.
    ast.node<AstNodeId::CompilerSwitchCase>(cases[2])->spanExprRef = ast.pushSpan(std::span<const AstNodeRef>(&values[3], 1));
    for (size_t i = 0; i < cases.size(); ++i)
        ast.node<AstNodeId::CompilerSwitchCase>(cases[i])->nodeBodyRef = values[4 + i];

    const auto [switchRef, node] = ast.makeNode<AstNodeId::CompilerSwitch>(TokenRef::invalid());
    node->nodeExprRef            = values[0];
    node->spanCasesRef           = ast.pushSpan(std::span<const AstNodeRef>(cases));
    SmallVector<AstNodeRef> children;
    ast.node(switchRef).collectChildrenFromAst(children, ast);
    const std::array expected = {values[0], values[1], values[2], values[3], values[4], values[5], values[6], cases[0], cases[1], cases[2]};
    if (!std::ranges::equal(children, expected))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AstVisitPreservesSiblingsAcrossPauseSkipAndRestart)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "AstVisitPauseSkipRestart", "");
    Ast&             ast    = source.ast();

    std::array<AstNodeRef, 8> refs;
    for (AstNodeRef& ref : refs)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    const auto [root, skipped, original, oldLeaf, replacement, nested, last, unvisited] = refs;
    const std::array rootChildren                                                       = {skipped, original, last};
    ast.node<AstNodeId::ArrayLiteral>(root)->spanChildrenRef                            = ast.pushSpan(std::span<const AstNodeRef>(rootChildren));
    const std::array skippedChildren                                                    = {unvisited};
    ast.node<AstNodeId::ArrayLiteral>(skipped)->spanChildrenRef                         = ast.pushSpan(std::span<const AstNodeRef>(skippedChildren));
    const std::array originalChildren                                                   = {oldLeaf};
    ast.node<AstNodeId::ArrayLiteral>(original)->spanChildrenRef                        = ast.pushSpan(std::span<const AstNodeRef>(originalChildren));
    const std::array replacementChildren                                                = {nested};
    ast.node<AstNodeId::ArrayLiteral>(replacement)->spanChildrenRef                     = ast.pushSpan(std::span<const AstNodeRef>(replacementChildren));

    std::array<AstNodeRef, 32> leaves;
    for (AstNodeRef& ref : leaves)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    ast.node<AstNodeId::ArrayLiteral>(nested)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(leaves));

    AstVisit                visit;
    std::vector<AstNodeRef> entered;
    bool                    pausedPreChild  = false;
    bool                    pausedPreNode   = false;
    bool                    pausedPostNode  = false;
    bool                    pausedPostChild = false;
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
        const auto     children = visit.currentChildren();
        const uint32_t index    = visit.preChildIndex();
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

SWC_TEST_BEGIN(Compiler_AstVisitRestartsFromChildCallbacks)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "AstVisitChildRestart", "");
    Ast&             ast    = source.ast();

    std::array<AstNodeRef, 6> refs;
    for (AstNodeRef& ref : refs)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    const auto [root, original, oldLeaf, replacement, newLeaf, sibling] = refs;
    const std::array rootChildren                                       = {original, sibling};
    const std::array oldChildren                                        = {oldLeaf};
    const std::array newChildren                                        = {newLeaf};
    ast.node<AstNodeId::ArrayLiteral>(root)->spanChildrenRef            = ast.pushSpan(std::span<const AstNodeRef>(rootChildren));
    ast.node<AstNodeId::ArrayLiteral>(original)->spanChildrenRef        = ast.pushSpan(std::span<const AstNodeRef>(oldChildren));
    ast.node<AstNodeId::ArrayLiteral>(replacement)->spanChildrenRef     = ast.pushSpan(std::span<const AstNodeRef>(newChildren));

    for (const bool restartBeforeChild : {true, false})
    {
        AstVisit                visit;
        std::vector<AstNodeRef> entered;
        visit.setPreNodeVisitor([&](AstNode&) {
            entered.push_back(visit.currentNodeRef());
            return Result::Continue;
        });
        const auto restart = [&](AstNode&, AstNodeRef&) {
            if (visit.currentNodeRef() == original)
                visit.restartCurrentNode(replacement);
            return Result::Continue;
        };
        if (restartBeforeChild)
            visit.setPreChildVisitor(restart);
        else
            visit.setPostChildVisitor(restart);
        visit.start(ast, root);
        bool stopped = false;
        for (size_t step = 0; step < 100 && !stopped; ++step)
        {
            const AstVisitResult result = visit.step(compilerCtx);
            if (result == AstVisitResult::Error)
                return Result::Error;
            stopped = result == AstVisitResult::Stop;
        }

        std::vector<AstNodeRef> expected = {root, original};
        if (!restartBeforeChild)
            expected.push_back(oldLeaf);
        expected.insert(expected.end(), {replacement, newLeaf, sibling});
        if (!stopped || entered != expected)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AstVisitResolvesChildrenWithoutFollowingActiveAncestors)
{
    CommandLine               cmdLine;
    CompilerInstance          compiler(ctx.global(), cmdLine);
    TaskContext               compilerCtx(compiler);
    SourceFile&               source = Unittest::addTestSource(compilerCtx, "Compiler", "AstVisitResolvedChildren", "");
    Ast&                      ast    = source.ast();
    std::array<AstNodeRef, 6> refs;
    for (AstNodeRef& ref : refs)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    const auto [root, identity, substituted, replacement, cyclic, unresolved] = refs;
    const std::array children                                                 = {identity, substituted, cyclic, unresolved};
    ast.node<AstNodeId::ArrayLiteral>(root)->spanChildrenRef                  = ast.pushSpan(std::span<const AstNodeRef>(children));

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

SWC_TEST_BEGIN(Compiler_AstVisitRefreshesDebugLocationWhenCodeRefChanges)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "AstVisitDebugLocation", "first second");
    SWC_RESULT(source.loadContent(compilerCtx));
    Ast&        ast  = source.ast();
    SourceView& view = ast.srcView();
    Lexer       lexer;
    lexer.tokenize(compilerCtx, view, LexerFlagsE::Default);

    const auto [root, rootNode]   = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef{0});
    const auto [child, childNode] = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid());
    const std::array children     = {child};
    rootNode->spanChildrenRef     = ast.pushSpan(std::span<const AstNodeRef>(children));

    AstVisit visit;
    bool     cleared   = false;
    bool     refreshed = false;
    visit.setPreNodeVisitor([&](AstNode& current) {
        if (&current == rootNode)
        {
            if (visit.dbgTokRef != TokenRef{0} || visit.dbgTokView != "first")
                return Result::Error;

            current.setCodeRef(SourceCodeRef(view.ref(), TokenRef{1}));
            return Result::Continue;
        }

        if (&current == childNode && visit.dbgTokRef.isInvalid() && visit.dbgTokView.empty() &&
            !visit.dbgSrcFile && !visit.dbgLoc.srcView)
        {
            cleared = true;
            return Result::Continue;
        }

        return Result::Error;
    });
    visit.setPostNodeVisitor([&](AstNode& current) {
        if (&current == childNode)
        {
            if (visit.dbgTokRef.isValid() || !visit.dbgTokView.empty() || visit.dbgSrcFile || visit.dbgLoc.srcView)
                return Result::Error;
            return Result::Continue;
        }
        if (&current != rootNode || visit.dbgTokRef != TokenRef{1} || visit.dbgTokView != "second")
            return Result::Error;

        refreshed = true;
        return Result::Continue;
    });
    visit.start(ast, root);
    for (size_t step = 0; step < 10; ++step)
    {
        const AstVisitResult result = visit.step(compilerCtx);
        if (result == AstVisitResult::Error)
            return Result::Error;
        if (result == AstVisitResult::Stop)
            return cleared && refreshed ? Result::Continue : Result::Error;
    }

    return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_SymbolLocationSortKeepsStableTokenOrderWithinOneFile)
{
    CommandLine      cmdLine;
    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SourceFile&      source = Unittest::addTestSource(compilerCtx, "Compiler", "SymbolLocationSort", "");
    const std::array views  = {
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
        std::vector<LocationSortTestSymbol*> values    = {nullptr, &symbols[2], &symbols[0], &symbols[0], &symbols[1], &symbols[0], &symbols[3], &symbols[4], &symbols[2], &symbols[5], nullptr};
        auto                                 reference = values;
        SymbolSort::sortAndUnique(reference, SymbolSort::LocationKeyFactory<LocationSortTestSymbol>{.compiler = &compiler});
        SymbolSort::sortAndUniqueByLocation(values, compiler);
        const std::array expected = {&symbols[3], &symbols[0], &symbols[1], &symbols[0], &symbols[2], &symbols[5], &symbols[4]};
        if (values != reference || !std::ranges::equal(values, expected))
            return Result::Error;

        std::vector<LocationSortTestSymbol*> uniqueValues    = {&symbols[2], &symbols[0], &symbols[1], &symbols[3], &symbols[4], &symbols[5]};
        auto                                 uniqueReference = uniqueValues;
        SymbolSort::sortAndUnique(uniqueReference, SymbolSort::LocationKeyFactory<LocationSortTestSymbol>{.compiler = &compiler});
        SymbolSort::LocationKeyCache keys(compiler);
        SymbolSort::sortByLocation(uniqueValues, compiler, keys);
        if (uniqueValues != uniqueReference)
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
    std::array       symbols   = {
        LocationSortTestSymbol{first.ast().srcView().ref(), TokenRef{9}},
        LocationSortTestSymbol{equalPath.ast().srcView().ref(), TokenRef{9}},
        LocationSortTestSymbol{longer.ast().srcView().ref(), TokenRef::invalid()},
        LocationSortTestSymbol{compiler.addSourceView().ref(), TokenRef{0}},
    };
    std::vector<LocationSortTestSymbol*> values    = {nullptr, &symbols[0], &symbols[0], &symbols[1], &symbols[0], &symbols[2], &symbols[3], nullptr};
    auto                                 reference = values;
    SymbolSort::sortAndUnique(reference, SymbolSort::LocationKeyFactory<LocationSortTestSymbol>{.compiler = &compiler});
    SymbolSort::sortAndUniqueByLocation(values, compiler);
    if (values != reference)
        return Result::Error;

    std::vector<LocationSortTestSymbol*> uniqueValues    = {&symbols[2], &symbols[3], &symbols[1], &symbols[0]};
    auto                                 uniqueReference = uniqueValues;
    SymbolSort::sortAndUnique(uniqueReference, SymbolSort::LocationKeyFactory<LocationSortTestSymbol>{.compiler = &compiler});
    SymbolSort::LocationKeyCache keys(compiler);
    SymbolSort::sortByLocation(uniqueValues, compiler, keys);
    if (uniqueValues != uniqueReference)
        return Result::Error;

    // The longer path's 'a' precedes the shorter path's '|' delimiter.
    if (std::ranges::find(values, &symbols[2]) >= std::ranges::find(values, &symbols[0]))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AstVisitKeepsDepthFirstOrderWithPendingSiblings)
{
    CommandLine               cmdLine;
    CompilerInstance          compiler(ctx.global(), cmdLine);
    TaskContext               compilerCtx(compiler);
    SourceFile&               source = Unittest::addTestSource(compilerCtx, "Compiler", "AstVisitPendingSiblings", "");
    Ast&                      ast    = source.ast();
    std::array<AstNodeRef, 5> refs;
    for (AstNodeRef& ref : refs)
        ref = ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first;
    const auto [root, branch, skipped, skippedLeaf, last] = refs;

    std::vector<AstNodeRef> leaves;
    for (size_t index = 0; index < 48; ++index)
        leaves.push_back(ast.makeNode<AstNodeId::ArrayLiteral>(TokenRef::invalid()).first);
    ast.node<AstNodeId::ArrayLiteral>(branch)->spanChildrenRef  = ast.pushSpan(std::span<const AstNodeRef>(leaves));
    const std::array skippedChildren                            = {skippedLeaf};
    ast.node<AstNodeId::ArrayLiteral>(skipped)->spanChildrenRef = ast.pushSpan(std::span<const AstNodeRef>(skippedChildren));
    // A repeated child is visited again; an invalid span entry is ignored when popped.
    const std::array rootChildren                            = {branch, AstNodeRef::invalid(), skipped, last, branch};
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
    static constexpr std::string_view SOURCE      = R"(#global private
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
    std::string                       otherSource = R"(#global private
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

SWC_TEST_BEGIN(Compiler_AutoInlineCyclesKeepIncomingWrappersSeparate)
{
    static constexpr std::string_view SOURCE = R"(#global private
func leaf() {}
func self()
{
    self()
    leaf()
}
func first()
{
    second()
    leaf()
}
func second() { third() }
func third()
{
    first()
    self()
}
func bridge()
{
    first()
    self()
}
func outer() { bridge() }
)";
    CommandLine                       cmdLine;
    CompilerInstance                  compiler(ctx.global(), cmdLine);
    TaskContext                       compilerCtx(compiler);
    SourceFile&                       source = Unittest::addTestSource(compilerCtx, "Compiler", "AutoInlineIncomingCycleWrapper", SOURCE);
    Lexer                             lexer;
    Parser                            parser;
    const uint64_t                    errorsBefore = Stats::get().numErrors.load(std::memory_order_relaxed);
    lexer.tokenize(compilerCtx, source.ast().srcView(), LexerFlagsE::Default);
    if (source.ast().srcView().mustSkip())
        return Result::Error;
    parser.parse(compilerCtx, source.ast());
    if (Stats::get().numErrors.load(std::memory_order_relaxed) != errorsBefore)
        return Result::Error;
    const std::array asts = {&source.ast()};
    Parser::finalizeAutoInlineCandidates(asts);

    // The three-node cycle also reaches an already completed self-recursive component.
    for (const std::string_view name : {"self", "first", "second", "third"})
    {
        const AstFunctionDecl* decl = findFunctionDecl(source.ast(), name);
        if (!decl || decl->hasFlag(AstFunctionFlagsE::AutoInlineBody))
            return Result::Error;
    }
    for (const std::string_view name : {"leaf", "bridge"})
    {
        const AstFunctionDecl* decl = findFunctionDecl(source.ast(), name);
        if (!decl || !decl->hasFlag(AstFunctionFlagsE::AutoInlineBody))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AutoInlineAssertionsNeedOneRepeatedCallSite)
{
    static constexpr std::string_view PROVIDER     = R"(#global private
func inLoop(value: *s32?)->s32 => value![]
func inRecursion(value: *s32?)->s32 => value![]
func inMutualRecursion(value: *s32?)->s32 => value![]
func inSetup(value: *s32?)->s32 => value![]
func addressTaken(value: *s32?)->s32 => value![]
func managed(value: *s32?)->s32 => try fallibleRead(value)
)";
    static constexpr std::string_view CALLER       = R"(#global private
func recursive(value: *s32?, depth: u32)->s32
{
    if depth == 0 do return 0
    return inRecursion(value) + recursive(value, depth - 1)
}
func first(value: *s32?, depth: u32)->s32
{
    if depth == 0 do return 0
    return inMutualRecursion(value) + second(value, depth - 1)
}
func second(value: *s32?, depth: u32)->s32
{
    return first(value, depth)
}
func use(value: *s32?, count: u32)
{
    let cold = inSetup(value)
    let callback = addressTaken
    for count
    {
        let hot = inLoop(value)
        let addressed = addressTaken(value)
        let handled = managed(value)
    }
}
)";
    const fs::path                    providerPath = Unittest::makeTestSourcePath("Compiler", "AutoInlineRepeatedProvider");
    const fs::path                    callerPath   = Unittest::makeTestSourcePath("Compiler", "AutoInlineRepeatedCaller");

    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_auto_inline_repeated";
    CompilerInstance compiler(ctx.global(), cmdLine);
    Unittest::registerTestSource(compiler, providerPath, PROVIDER);
    Unittest::registerTestSource(compiler, callerPath, CALLER);
    TaskContext compilerCtx(compiler);

    SourceFile& provider = compiler.addFile(providerPath, FileFlagsE::CustomSrc);
    SourceFile& caller   = compiler.addFile(callerPath, FileFlagsE::CustomSrc);
    SWC_RESULT(provider.loadContent(compilerCtx));
    SWC_RESULT(caller.loadContent(compilerCtx));
    Lexer  lexer;
    Parser parser;
    for (SourceFile* source : {&provider, &caller})
    {
        lexer.tokenize(compilerCtx, source->ast().srcView(), LexerFlagsE::Default);
        if (source->ast().srcView().mustSkip())
            return Result::Error;
        parser.parse(compilerCtx, source->ast());
    }
    const std::array moduleAsts = {&provider.ast(), &caller.ast()};
    Parser::finalizeAutoInlineCandidates(moduleAsts);

    for (const std::string_view name : {"inLoop", "inRecursion", "inMutualRecursion"})
    {
        const AstFunctionDecl* decl = findFunctionDecl(provider.ast(), name);
        if (!decl || !decl->autoInlineHasNotNull || !decl->autoInlineRepeatedCall || !decl->hasFlag(AstFunctionFlagsE::AutoInlineBody))
            return Result::Error;
    }
    for (const std::string_view name : {"inSetup", "addressTaken", "managed"})
    {
        const AstFunctionDecl* decl = findFunctionDecl(provider.ast(), name);
        if (!decl || decl->autoInlineRepeatedCall || decl->hasFlag(AstFunctionFlagsE::AutoInlineBody))
            return Result::Error;
    }
    for (const std::string_view name : {"recursive", "first", "second"})
    {
        const AstFunctionDecl* decl = findFunctionDecl(caller.ast(), name);
        if (!decl || decl->hasFlag(AstFunctionFlagsE::AutoInlineBody))
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_SharedApiTextSurvivesSnapshotAndEditorRevision)
{
    constexpr std::string_view         source = "func published()->s32 => 42\n";
    std::weak_ptr<const SourceContent> retained;
    {
        CommandLine cmdLine;
        cmdLine.command = CommandKind::Syntax;
        cmdLine.name    = "shared_api_text";
        CompilerInstance compiler(ctx.global(), cmdLine);
        TaskContext      compilerCtx(compiler);
        auto             snapshot = std::make_shared<const SourceContent>(source);
        retained                  = snapshot;

        SourceFile& first  = compiler.addFile(Unittest::makeTestSourcePath("Compiler", "SharedApiFirst"), FileFlagsE::ImportedApi);
        SourceFile& second = compiler.addFile(Unittest::makeTestSourcePath("Compiler", "SharedApiSecond"), FileFlagsE::ImportedApi);
        first.setContent(snapshot);
        second.setContent(snapshot);
        if (first.sourceView().data() != second.sourceView().data() || first.sourceView() != source)
            return Result::Error;
        for (size_t i = 0; i < SourceContent::TRAILING_0; ++i)
            if (first.content()[source.size() + i] != 0)
                return Result::Error;

        SWC_RESULT(first.loadContent(compilerCtx));
        SourceView& original = first.ast().srcView();
        Lexer       lexer;
        lexer.tokenize(compilerCtx, original, LexerFlagsE::Default);
        Parser parser;
        parser.parse(compilerCtx, first.ast());
        if (first.ast().root().isInvalid())
            return Result::Error;

        snapshot.reset();
        second.setContent("func other() {}\n");
        first.beginEditorRevision("func published()->s32 => 43\n");
        if (retained.expired() || original.stringView() != source || first.sourceView() == source)
            return Result::Error;
        SWC_RESULT(first.loadContent(compilerCtx));
        lexer.tokenize(compilerCtx, first.ast().srcView(), LexerFlagsE::Default);
        parser.parse(compilerCtx, first.ast());
        if (first.ast().root().isInvalid() || original.tokenString(TokenRef(1)) != "published")
            return Result::Error;
    }
    if (!retained.expired())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ArenaAllocationsReleaseOwnedResources)
{
    std::weak_ptr<uint64_t> retained;
    {
        CommandLine      cmdLine;
        CompilerInstance compiler(ctx.global(), cmdLine);
        TaskContext      compilerCtx(compiler);
        auto             resource = std::make_shared<uint64_t>(42);
        retained                  = resource;

        compiler.allocate<std::shared_ptr<uint64_t>>(resource);
        compilerCtx.allocate<std::shared_ptr<uint64_t>>(resource);
        auto* array = compiler.allocateArray<std::shared_ptr<uint64_t>>(2);
        array[0]    = resource;
        array[1]    = resource;
        if (resource.use_count() != 5)
            return Result::Error;
    }
    return retained.expired() ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ArenaFunctionReleasesGenericState)
{
    std::weak_ptr<uint64_t> retained;
    {
        CommandLine      cmdLine;
        CompilerInstance compiler(ctx.global(), cmdLine);
        TaskContext      compilerCtx(compiler);
        auto             resource = std::make_shared<uint64_t>(42);
        retained                  = resource;

        auto* function                                = compiler.allocate<SymbolFunction>(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlags{});
        function->ensureLazyBodyRunState(compilerCtx) = resource;
        if (resource.use_count() != 2)
            return Result::Error;
    }
    return retained.expired() ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
