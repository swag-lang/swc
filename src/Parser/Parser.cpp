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
        const auto& tok        = *curToken_;
        const bool  atTopLevel = (parenDepth | squareDepth | braceDepth) == 0;

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

        consumeOne();
    }

    // Hit EOF without finding a sync point.
    return false;
}

TokenRef Parser::expect(TokenId expected, DiagnosticId diagId) const
{
    if (is(expected))
        return ref();
    (void) reportExpected(expected, diagId);
    return INVALID_REF;
}

TokenRef Parser::expectAndConsume(TokenId expected, DiagnosticId diagId)
{
    if (is(expected))
        return consume();
    (void) reportExpected(expected, diagId);
    return INVALID_REF;
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

#if SWC_HAS_STATS
    Stats::get().numAstNodes.fetch_add(ast_->store_.size());
#endif

    return file_->hasErrors() ? Result::Error : Result::Success;
}

SWC_END_NAMESPACE()
