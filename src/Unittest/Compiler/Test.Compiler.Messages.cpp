#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticBuilder.h"
#include "Support/Report/LogColor.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t compilerMessageMask(const Runtime::CompilerMsgKind kind)
    {
        return 1ull << static_cast<uint32_t>(kind);
    }

    bool isMessageWordCharacter(const char c)
    {
        return (c >= 'a' && c <= 'z') ||
               (c >= 'A' && c <= 'Z') ||
               (c >= '0' && c <= '9') ||
               c == '_';
    }

    bool containsMessageWord(const std::string_view message, const std::string_view word)
    {
        size_t pos = message.find(word);
        while (pos != std::string_view::npos)
        {
            const size_t end = pos + word.size();
            if ((pos == 0 || !isMessageWordCharacter(message[pos - 1])) &&
                (end == message.size() || !isMessageWordCharacter(message[end])))
                return true;
            pos = message.find(word, pos + 1);
        }

        return false;
    }

    Result reportDiagnosticStyleError(const DiagnosticId id, const std::string_view reason, const std::string_view message)
    {
        std::println(stderr, "[diagnostic-style] {}: {}; message is \"{}\"", Diagnostic::diagIdName(id), reason, message);
        return Result::Error;
    }
}

SWC_TEST_BEGIN(Compiler_MessagePassSkipsWithoutListeners)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_message_no_listener";

    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SWC_RESULT(compiler.setupSema(compilerCtx));

    if (compiler.hasCompilerMessageInterest(Runtime::CompilerMsgKind::PassAfterSemantic))
        return Result::Error;
    if (compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassAfterSemantic) != Result::Continue)
        return Result::Error;
    if (compiler.executePendingCompilerMessages(compilerCtx) != Result::Continue)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_MessagePassQueuesOnlyOncePerListener)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_message_listener";

    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SWC_RESULT(compiler.setupSema(compilerCtx));

    auto* listener = Symbol::make<SymbolFunction>(compilerCtx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), {});
    compiler.registerCompilerMessageFunction(listener, AstNodeRef::invalid(), compilerMessageMask(Runtime::CompilerMsgKind::PassAfterSemantic));

    if (!compiler.hasCompilerMessageInterest(Runtime::CompilerMsgKind::PassAfterSemantic))
        return Result::Error;
    if (compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassAfterSemantic) != Result::Pause)
        return Result::Error;
    if (compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassAfterSemantic) != Result::Continue)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_MessageAliasPayloadUsesUnderlyingType)
{
    auto* aliasSymbol = Symbol::make<SymbolAlias>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), {});
    aliasSymbol->setUnderlyingTypeRef(ctx.typeMgr().typeConstValuePtrVoid());

    const TypeRef aliasTypeRef = ctx.typeMgr().addType(TypeInfo::makeAlias(aliasSymbol));
    aliasSymbol->setTypeRef(aliasTypeRef);

    const TypeInfo& aliasType = ctx.typeMgr().get(aliasTypeRef);
    if (aliasType.payloadTypeRef() != ctx.typeMgr().typeConstValuePtrVoid())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticWarningSeverityColorIsMagenta)
{
    if (LogColorHelper::diagnosticSeverityColor(DiagnosticSeverity::Warning) != LogColor::BrightMagenta)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticCatalogFollowsSwagMessageStyle)
{
    constexpr std::string_view vagueWords[] = {
        "invalid",
        "unexpected",
        "failed",
        "failure",
        "wrong",
        "must",
        "mismatch",
    };

    for (size_t value = 1; value < static_cast<size_t>(DiagnosticId::Count); ++value)
    {
        const auto id = static_cast<DiagnosticId>(value);
        for (const std::string_view message : Diagnostic::diagIdMessages(id))
        {
            if (message.empty())
                return reportDiagnosticStyleError(id, "message is empty", message);
            if (message.size() > 260)
                return reportDiagnosticStyleError(id, "message exceeds 260 characters", message);
            if (message.find_first_of("\r\n\t") != std::string_view::npos)
                return reportDiagnosticStyleError(id, "message contains layout whitespace", message);
            if (message.ends_with('.') || message.ends_with('!') || message.ends_with(':') || message.ends_with(';'))
                return reportDiagnosticStyleError(id, "message has terminal punctuation", message);

            const size_t helpPos = message.find("[help]");
            if (helpPos != std::string_view::npos)
            {
                if (helpPos < 2 || message.substr(helpPos - 2, 9) != "; [help] ")
                    return reportDiagnosticStyleError(id, "help does not use the '; [help] ' delimiter", message);
                if (message.find("[help]", helpPos + 1) != std::string_view::npos)
                    return reportDiagnosticStyleError(id, "message contains more than one help section", message);
            }

            for (const std::string_view word : vagueWords)
            {
                if (containsMessageWord(message, word))
                    return reportDiagnosticStyleError(id, std::format("message uses vague word '{}'", word), message);
            }

            if (message.find("type mismatch") != std::string_view::npos || message.find("not viable") != std::string_view::npos)
                return reportDiagnosticStyleError(id, "message uses a vague summary instead of the broken contract", message);
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_InvalidCharacterHelpCoversAsciiAndUnicode)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    for (const char* value : {"0024", "0060", "20AC"})
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::lex_err_invalid_char);
        diag.addArgument(Diagnostic::ARG_VALUE, value);

        const Utf8 text     = DiagnosticBuilder(localCtx, diag).build();
        const Utf8 expected = Utf8("character U+") + value + " is not allowed in source code";
        if (text.find(expected) == Utf8::npos ||
            text.find("help: remove this character, or enclose it in a comment or literal") == Utf8::npos)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticSimdOperatorReportsOnlyCurrentContract)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    struct OperatorCase
    {
        const char* type;
        const char* op;
    };
    constexpr OperatorCase cases[] = {
        {"#simd [4] s32", "/"},
        {"#simd [4] f32", "%"},
        {"#simd [4] f32", "&"},
    };

    for (const auto& test : cases)
    {
        Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_simd_operator);
        diag.addArgument(Diagnostic::ARG_TYPE, test.type);
        diag.addArgument(Diagnostic::ARG_TOK, test.op);

        DiagnosticBuilder builder(localCtx, diag);
        const Utf8        text     = builder.build();
        const Utf8        expected = Utf8("'") + test.type + "' does not support operator '" + test.op + "' on its lanes";
        if (text.find(expected) == Utf8::npos || text.find("help:") != Utf8::npos || text.find("do not exist on the target") != Utf8::npos)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AssertDiagnosticPreservesLiteralSuffixQuotes)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    Diagnostic        diag = Diagnostic::get(DiagnosticId::sema_err_assert_failed);
    diag.addArgument(Diagnostic::ARG_BECAUSE, "text[0] == 'w''u8 + 'd''u8");

    DiagnosticBuilder builder(localCtx, diag);
    const Utf8        text = builder.build();

    if (text.find("assertion does not hold: text[0] == 'w''u8 + 'd''u8") == Utf8::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticEscapesQuotedArgumentTicks)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    Diagnostic        diag = Diagnostic::get(DiagnosticId::sema_err_type_not_indexable);
    diag.addArgument(Diagnostic::ARG_TYPE, "List'(s32)");

    DiagnosticBuilder builder(localCtx, diag);
    const Utf8        text = builder.build();

    if (text.find("type 'List'(s32)' does not support indexing") == Utf8::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticArgumentCountDoesNotRepeatUnit)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    for (const DiagnosticId id : {DiagnosticId::parser_err_too_many_arguments, DiagnosticId::parser_err_too_few_arguments,
                                  DiagnosticId::sema_err_too_many_arguments, DiagnosticId::sema_err_too_few_arguments,
                                  DiagnosticId::sema_note_overload_candidate_too_many_arguments, DiagnosticId::sema_note_overload_candidate_too_few_arguments})
    {
        for (const char* quantity : {"1 argument", "2 arguments", "at least 1 argument"})
        {
            for (const uint32_t namedDetail : {0u, 1u, 2u})
            {
                Diagnostic diag = Diagnostic::get(id);
                diag.addArgument(Diagnostic::ARG_WHAT, quantity);
                diag.addArgument(Diagnostic::ARG_VALUE, 3);
                if (namedDetail)
                    diag.addArgument(Diagnostic::ARG_SYM, "assert");
                if (namedDetail == 2)
                    diag.addArgument(Diagnostic::ARG_TOK, "value");

                DiagnosticBuilder builder(localCtx, diag);
                const Utf8        text     = builder.build();
                const Utf8        expected = Utf8(quantity) + ", found 3";
                if (text.find(expected) == Utf8::npos)
                    return Result::Error;
            }
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_ExpectedTokenBeforeEofNamesTheBoundary)
{
    CommandLine cmdLine;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;
    const TaskContext localCtx(ctx.global(), cmdLine);
    for (const DiagnosticId id : {DiagnosticId::parser_err_expected_token_before, DiagnosticId::parser_err_expected_token_fam_before})
    {
        Diagnostic diag = Diagnostic::get(id);
        diag.addArgument(Diagnostic::ARG_EXPECT_TOK, "(");
        diag.addArgument(Diagnostic::ARG_EXPECT_A_TOK_FAM, "an identifier");
        diag.addArgument(Diagnostic::ARG_TOK_FAM, "end of file");
        if (DiagnosticBuilder(localCtx, diag).build().find("before end of file") == Utf8::npos)
            return Result::Error;

        // A real following token keeps its spelling and the original message variant.
        diag.addArgument(Diagnostic::ARG_TOK, "{");
        diag.addArgument(Diagnostic::ARG_TOK_FAM, "symbol");
        if (DiagnosticBuilder(localCtx, diag).build().find("before '{'") == Utf8::npos)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticRemovesUnexpandedWordPlaceholders)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    Diagnostic        diag = Diagnostic::get(DiagnosticId::cmdline_err_invalid_enum);
    diag.addArgument(Diagnostic::ARG_ARG, "--backend");

    DiagnosticBuilder builder(localCtx, diag);
    const Utf8        text = builder.build();

    if (text.find("{value}") != Utf8::npos || text.find("{long}") != Utf8::npos || text.find("{values}") != Utf8::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_NativeExitCodeDiagnosticShowsDecimalAndHex)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    Diagnostic        diag = Diagnostic::get(DiagnosticId::cmd_err_native_artifact_failed);
    diag.addArgument(Diagnostic::ARG_VALUE, Os::formatProcessExitCode(0xC0000135u));

    DiagnosticBuilder builder(localCtx, diag);
    const Utf8        text = builder.build();

    if (text.find("generated executable exited with code 3221225781 (0xC0000135)") == Utf8::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticEscapesQuotedArgumentWithoutBreakingHelpSplit)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    Diagnostic        diag = Diagnostic::get(DiagnosticId::sema_err_type_not_indexable);
    diag.addArgument(Diagnostic::ARG_TYPE, "List'(s32); [help] fake");

    DiagnosticBuilder builder(localCtx, diag);
    const Utf8        text = builder.build();

    if (text.find("type 'List'(s32); [help] fake' does not support indexing") == Utf8::npos)
        return Result::Error;

    size_t helpCount = 0;
    size_t pos       = 0;
    while ((pos = text.find("help:", pos)) != Utf8::npos)
    {
        ++helpCount;
        pos += 5;
    }

    if (helpCount != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
