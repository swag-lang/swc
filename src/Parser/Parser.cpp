#include "pch.h"
#include "Parser/Parser.h"
#include "Core/Timer.h"
#include "Lexer/SourceFile.h"
#include "Main/Context.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE();

void Parser::skipToOrEol(std::initializer_list<TokenId> tokens)
{
    int parenDepth  = 0;
    int squareDepth = 0;
    int curlyDepth  = 0;

    while (!atEnd())
    {
        if (curToken_->flags.has(TokenFlagsEnum::EolBefore))
            return;
        if (parenDepth == 0 && squareDepth == 0 && curlyDepth == 0 &&
            std::ranges::find(tokens, id()) != tokens.end())
            return;

        // adjust nesting
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
                ++curlyDepth;
                break;
            case TokenId::SymRightCurly:
                --curlyDepth;
                break;
            default:
                break;
        }

        consume();
    }
}

Result Parser::parse(Context& ctx)
{
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeParser);
#endif

    file_ = ctx.sourceFile();
    ast_  = &file_->parserOut_.ast_;
    ctx_  = &ctx;

    // Load
    SWC_CHECK(file_->loadContent(ctx));

    // Lexer
    Lexer lexer;
    SWC_CHECK(file_->unittest_.tokenize(ctx));
    SWC_CHECK(lexer.tokenize(ctx));

    SWC_ASSERT(!file_->lexOut_.tokens_.empty());
    if (file_->hasFlag(FileFlagsEnum::LexOnly))
        return Result::Success;

    // Parser
    firstToken_ = &file_->lexOut_.tokens_.front();
    lastToken_  = &file_->lexOut_.tokens_.back();
    curToken_   = firstToken_;

    ast_->root_ = parseFile();

#if SWC_HAS_STATS
    Stats::get().numAstNodes.fetch_add(ast_->nodes_.size());
#endif

    return file_->hasErrors() ? Result::Error : Result::Success;
}

SWC_END_NAMESPACE();
