#include "pch.h"
#include "Parser/Parser.h"
#include "Core/Timer.h"
#include "Lexer/SourceFile.h"
#include "Main/Context.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE()

void Parser::setReportArguments(Diagnostic& diag, const Token& token) const
{
    diag.addArgument(Diagnostic::ARG_TOK, token.toString(*file_));
    diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id), false);
    diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Token::toAFamily(token.id), false);

    // Get the last non-trivia token
    if (curToken_ != firstToken_)
        diag.addArgument(Diagnostic::ARG_AFTER, curToken_[-1].toString(*file_));
}

void Parser::setReportExpected(Diagnostic& diag, TokenId expectedTknId)
{
    diag.addArgument(Diagnostic::ARG_EXPECT, Token::toName(expectedTknId));
    diag.addArgument(Diagnostic::ARG_EXPECT_FAM, Token::toFamily(expectedTknId), false);
    diag.addArgument(Diagnostic::ARG_A_EXPECT_FAM, Token::toAFamily(expectedTknId), false);
}

Diagnostic Parser::reportError(DiagnosticId id, TokenRef tknRef) const
{
    auto       diag  = Diagnostic::get(*ctx_, id, file_);
    const auto token = file_->lexOut().token(tknRef);
    setReportArguments(diag, token);
    diag.last().setLocation(token.toLocation(*ctx_, *file_));
    return diag;
}

void Parser::raiseError(DiagnosticId id, TokenRef tknRef)
{
    if (tknRef == lastErrorToken_)
        return;
    lastErrorToken_ = tknRef;

    const auto diag = reportError(id, tknRef);
    diag.report(*ctx_);
}

Diagnostic Parser::reportExpected(const ParserExpect& expect) const
{
    SWC_ASSERT(expect.tokId != TokenId::Invalid);

    auto diag = reportError(expect.diag, ref());
    setReportArguments(diag, tok());
    setReportExpected(diag, expect.tokId);
    diag.addArgument(Diagnostic::ARG_BECAUSE, Diagnostic::diagIdMessage(expect.becauseCtx), false);

    // Additional notes
    if (expect.tokId == TokenId::Identifier && tok().isReservedWord())
        diag.addElement(DiagnosticId::ParserReservedAsIdentifier);

    if (expect.noteId != DiagnosticId::None)
    {
        const auto tknLoc = file_->lexOut().token(expect.noteToken);
        diag.addElement(expect.noteId).setLocation(tknLoc.toLocation(*ctx_, *file_));
    }

    return diag;
}

void Parser::raiseExpected(const ParserExpect& expect)
{
    if (ref() == lastErrorToken_)
        return;
    lastErrorToken_ = ref();

    const auto diag = reportExpected(expect);
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
    int        parenDepth  = 0;
    int        squareDepth = 0;
    int        braceDepth  = 0;
    const auto refStart    = ref();

    while (!atEnd())
    {
        if (has_any(flags, SkipUntilFlags::EolBefore) && tok().startsLine() && refStart != ref())
            break;

        const bool atTopLevel = (parenDepth | squareDepth | braceDepth) == 0;

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
            ++squareDepth;
            break;
        case TokenId::SymRightBracket:
            --squareDepth;
            break;
        case TokenId::SymLeftCurly:
            ++braceDepth;
            break;
        case TokenId::SymRightCurly:
            --braceDepth;
            break;
        default:
            break;
        }

        // Never let depths go negative (keeps recovery robust even on stray closers).
        parenDepth  = std::max(parenDepth, 0);
        squareDepth = std::max(squareDepth, 0);
        braceDepth  = std::max(braceDepth, 0);

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

TokenRef Parser::expect(const ParserExpect& expect)
{
    if (expect.valid(tok().id))
        return ref();
    raiseExpected(expect);
    return INVALID_REF;
}

TokenRef Parser::expectAndConsume(const ParserExpect& expect)
{
    if (expect.valid(tok().id))
        return consume();
    raiseExpected(expect);
    return INVALID_REF;
}

TokenRef Parser::expectAndConsumeClosingFor(TokenId openId, TokenRef openRef)
{
    const auto& open      = file_->lexOut().token(openRef);
    const auto  closingId = Token::toRelated(openId);
    auto        expect    = ParserExpect::one(closingId, DiagnosticId::ParserExpectedClosingBefore);
    if (open.id == openId)
        expect.note(DiagnosticId::ParserCorresponding, openRef);
    const auto result = expectAndConsume(expect);
    if (isInvalid(result))
    {
        skipTo({closingId, TokenId::SymSemiColon, TokenId::SymLeftCurly}, SkipUntilFlags::EolBefore);
        consumeIf(closingId);
    }

    return result;
}

void Parser::expectEndStatement()
{
    if (tok().startsLine() || is(TokenId::EndOfFile))
        return;
    if (consumeIf(TokenId::SymSemiColon))
        return;

    const auto diag = reportError(DiagnosticId::ParserExpectedEndOfLine, ref() - 1);
    auto       loc  = curToken_[-1].toLocation(*ctx_, *file_);
    loc.column += loc.len;
    loc.offset += loc.len;
    loc.len = 1;
    diag.last().setLocation(loc);
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
