#include "pch.h"
#include "Parser/Parser.h"
#include "Core/Timer.h"
#include "Lexer/SourceFile.h"
#include "Main/Context.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE()

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
    int parenDepth  = 0;
    int squareDepth = 0;
    int braceDepth  = 0;

    while (!atEnd())
    {
        if (has_any(flags, SkipUntilFlags::EolBefore) && tok().startsLine())
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
    skip();
    return true;
}

TokenRef Parser::skip(TokenId id)
{
    SWC_ASSERT(is(id));
    return skip();
}

TokenRef Parser::skip()
{
    return consume();
}

TokenRef Parser::expect(const ParserExpect& expect) const
{
    if (expect.valid(tok().id))
        return ref();
    (void) reportExpected(expect);
    return INVALID_REF;
}

TokenRef Parser::expectAndConsume(const ParserExpect& expect)
{
    if (expect.valid(tok().id))
        return consume();
    (void) reportExpected(expect);
    return INVALID_REF;
}

TokenRef Parser::expectAndSkip(const ParserExpect& expect)
{
    if (expect.valid(tok().id))
        return skip();
    (void) reportExpected(expect);
    return INVALID_REF;
}

TokenRef Parser::expectAndConsumeClosing(TokenId openId, TokenRef openRef)
{
    const auto& open      = file_->lexOut().token(openRef);
    const auto  closingId = Token::toRelated(openId);
    auto        expect    = ParserExpect::one(closingId, DiagnosticId::ParserExpectedClosingBefore);
    if (open.id == openId)
        expect.note(DiagnosticId::ParserCorresponding, openRef);
    return expectAndConsume(expect);
}

TokenRef Parser::expectAndSkipClosing(TokenId openId, TokenRef openRef)
{
    const auto& open      = file_->lexOut().token(openRef);
    const auto  closingId = Token::toRelated(openId);
    auto        expect    = ParserExpect::one(closingId, DiagnosticId::ParserExpectedClosingBefore);
    if (open.id == openId)
        expect.note(DiagnosticId::ParserCorresponding, openRef);
    return expectAndSkip(expect);
}

void Parser::expectEndStatement()
{
    if (tok().startsLine() || is(TokenId::EndOfFile))
        return;

    if (is(TokenId::SymSemiColon))
    {
        skip();
        return;
    }

    const auto diag = reportError(DiagnosticId::ParserExpectedEndOfLine, curToken_[-1]);
    auto       loc  = curToken_[-1].toLocation(*ctx_, *file_);
    loc.column += loc.len;
    loc.offset += loc.len;
    loc.len = 1;
    diag.last().setLocation(loc);
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
