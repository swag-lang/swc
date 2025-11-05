#include "pch.h"
#include "Parser/Parser.h"
#include "Core/Timer.h"
#include "Lexer/SourceFile.h"
#include "Main/Context.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE()

void Parser::setReportArguments(Diagnostic& diag, TokenRef tokenRef) const
{
    const auto& token = file_->lexOut().token(tokenRef);

    diag.addArgument(Diagnostic::ARG_TOK, token.toString(*file_));
    diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id), false);
    diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Token::toAFamily(token.id), false);

    // Get the last non-trivia token
    if (tokenRef != 0)
    {
        const auto& tokenPrev = file_->lexOut().token(tokenRef - 1);
        diag.addArgument(Diagnostic::ARG_PREV_TOK, tokenPrev.toString(*file_));
        diag.addArgument(Diagnostic::ARG_PREV_TOK_FAM, Token::toFamily(tokenPrev.id), false);
        diag.addArgument(Diagnostic::ARG_PREV_A_TOK_FAM, Token::toAFamily(tokenPrev.id), false);
    }

    if (tokenRef < file_->lexOut().tokens().size() - 1)
    {
        const auto& tokenNext = file_->lexOut().token(tokenRef + 1);
        diag.addArgument(Diagnostic::ARG_NEXT_TOK, tokenNext.toString(*file_));
        diag.addArgument(Diagnostic::ARG_NEXT_TOK_FAM, Token::toFamily(tokenNext.id), false);
        diag.addArgument(Diagnostic::ARG_NEXT_A_TOK_FAM, Token::toAFamily(tokenNext.id), false);
    }
}

void Parser::setReportExpected(Diagnostic& diag, TokenId expectedTknId)
{
    diag.addArgument(Diagnostic::ARG_EXPECT, Token::toName(expectedTknId));
    diag.addArgument(Diagnostic::ARG_EXPECT_FAM, Token::toFamily(expectedTknId), false);
    diag.addArgument(Diagnostic::ARG_A_EXPECT_FAM, Token::toAFamily(expectedTknId), false);
}

Diagnostic Parser::reportError(DiagnosticId id, TokenRef tknRef)
{
    auto       diag  = Diagnostic::get(id, file_);
    const auto token = file_->lexOut().token(tknRef);
    setReportArguments(diag, tknRef);
    diag.last().addSpan(token.toLocation(*ctx_, *file_), "");

    if (tknRef == lastErrorToken_)
        diag.setSilent(true);
    lastErrorToken_ = tknRef;

    return diag;
}

void Parser::raiseError(DiagnosticId id, TokenRef tknRef)
{
    const auto diag = reportError(id, tknRef);
    diag.report(*ctx_);
}

bool Parser::skipTo(std::initializer_list<TokenId> targets, SkipUntilFlags flags)
{
    return skip(targets, flags);
}

bool Parser::skipAfter(std::initializer_list<TokenId> targets, SkipUntilFlags flags)
{
    return skip(targets, flags | SkipUntilFlags::Consume);
}

bool Parser::skip(std::initializer_list<TokenId> targets, SkipUntilFlags flags)
{
    int        parenDepth   = 0;
    int        bracketDepth = 0;
    int        curlyDepth   = 0;
    const auto refStart     = ref();

    while (!atEnd())
    {
        if (has_any(flags, SkipUntilFlags::EolBefore) && tok().startsLine() && refStart != ref())
            break;

        const bool atTopLevel = (parenDepth | bracketDepth | curlyDepth) == 0;

        if (atTopLevel)
        {
            // Stop at any target token (top level only).
            if (std::ranges::find(targets, id()) != targets.end())
            {
                if (has_any(flags, SkipUntilFlags::Consume))
                    consume();
                return true;
            }
        }

        // Update delimiter depths first (so we won't prematurely stop
        // on a target that appears inside a nested construct).
        switch (id())
        {
        case TokenId::SymLeftParen:
            ++parenDepth;
            break;
        case TokenId::SymRightParen:
            --parenDepth;
            break;
        case TokenId::SymLeftBracket:
        case TokenId::SymAttrStart:
            ++bracketDepth;
            break;
        case TokenId::SymRightBracket:
            --bracketDepth;
            break;
        case TokenId::SymLeftCurly:
            ++curlyDepth;
            break;
        case TokenId::SymRightCurly:
            --curlyDepth;
            break;
        default:
            break;
        }

        // Never let depths go negative (keeps recovery robust even on stray closers).
        parenDepth   = std::max(parenDepth, 0);
        bracketDepth = std::max(bracketDepth, 0);
        curlyDepth   = std::max(curlyDepth, 0);

        consume();
    }

    // Hit EOF without finding a sync point.
    return false;
}

TokenRef Parser::consume(TokenId id)
{
    SWC_ASSERT(is(id));
    return consume();
}

TokenRef Parser::consume()
{
    if (atEnd())
        return INVALID_REF;
    const auto result = ref();
    switch (id())
    {
    case TokenId::SymLeftParen:
        depthParen_++;
        break;
    case TokenId::SymRightParen:
        depthParen_--;
        break;
    case TokenId::SymLeftBracket:
    case TokenId::SymAttrStart:
        depthBracket_++;
        break;
    case TokenId::SymRightBracket:
        depthBracket_--;
        break;
    case TokenId::SymLeftCurly:
        depthCurly_++;
        break;
    case TokenId::SymRightCurly:
        depthCurly_--;
        break;
    default:
        break;
    }

    curToken_++;
    return result;
}

bool Parser::consumeIf(TokenId id, TokenRef* result)
{
    if (atEnd() || isNot(id))
    {
        if (result)
            *result = INVALID_REF;
        return false;
    }

    if (result)
        *result = ref();
    consume();
    return true;
}

TokenRef Parser::expectAndConsume(TokenId id, DiagnosticId diagId)
{
    if (is(id))
        return consume();

    auto diag = reportError(diagId, ref());
    setReportArguments(diag, ref());
    setReportExpected(diag, id);

    if (id == TokenId::Identifier && tok().isKeyword())
        diag.last().span(0).messageId = DiagnosticId::parser_note_reserved_identifier;

    diag.report(*ctx_);
    return INVALID_REF;
}

TokenRef Parser::expectAndConsumeClosingFor(TokenId openId, TokenRef openRef)
{
    const auto closingId = Token::toRelated(openId);
    if (is(closingId))
        return consume();

    auto diag = reportError(DiagnosticId::parser_err_expected_closing_before, ref());
    setReportArguments(diag, ref());
    setReportExpected(diag, closingId);

    diag.last().addSpan(file_->lexOut().token(openRef).toLocation(*ctx_, *file_), DiagnosticId::parser_note_opening, DiagnosticSeverity::Note);
    diag.report(*ctx_);

    skipTo({closingId, TokenId::SymSemiColon, TokenId::SymLeftCurly}, SkipUntilFlags::EolBefore);
    consumeIf(closingId);
    return INVALID_REF;
}

void Parser::expectEndStatement()
{
    if (tok().startsLine() || is(TokenId::EndOfFile))
        return;
    if (consumeIf(TokenId::SymSemiColon))
        return;

    const auto diag = reportError(DiagnosticId::parser_err_expected_eol, ref() - 1);
    auto       loc  = curToken_[-1].toLocation(*ctx_, *file_);
    loc.column += loc.len;
    loc.offset += loc.len;
    loc.len = 1;
    diag.last().addSpan(loc, "");
    diag.report(*ctx_);
}

Result Parser::parse(Context& ctx)
{
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeParser);
#endif

    file_ = ctx.sourceFile();
    ast_  = &file_->parserOut_.ast();
    ctx_  = &ctx;

    // Load
    SWC_CHECK(file_->loadContent(ctx));

    // Lexer
    Lexer lexer;
    SWC_CHECK(file_->unittest_.tokenize(ctx));
    SWC_CHECK(lexer.tokenize(ctx));

    SWC_ASSERT(!file_->lexOut_.tokens().empty());
    if (file_->hasFlag(FileFlags::LexOnly))
        return Result::Success;

    // Parser
    firstToken_ = &file_->lexOut_.tokens().front();
    lastToken_  = &file_->lexOut_.tokens().back();
    curToken_   = firstToken_;

    ast_->root_ = parseFile();

    return file_->hasErrors() ? Result::Error : Result::Success;
}

SWC_END_NAMESPACE()
