#include "pch.h"
#include "Parser/Parser.h"
#include "Core/Timer.h"
#include "Lexer/SourceFile.h"
#include "Main/Context.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE();

void Parser::skipTopOrEol(std::initializer_list<TokenId> tokens)
{
    while (!atEnd())
    {
        if (curToken_->flags.has(TokenFlagsEnum::EolAfter))
            return;
        const auto cur = curToken_->id;
        if (std::ranges::find(tokens, cur) != tokens.end())
            return;
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

    SWC_CHECK(file_->loadContent(ctx));
    SWC_CHECK(file_->tokenize(ctx));
    SWC_ASSERT(!file_->lexOut_.tokens_.empty());

    firstToken_ = &file_->lexOut_.tokens_.front();
    lastToken_  = &file_->lexOut_.tokens_.back();
    curToken_   = firstToken_;

    ast_->root_ = parseFile();

#if SWC_HAS_STATS
    Stats::get().numAstNodes.fetch_add(ast_->nodes_.size());
#endif

    return file_->hasError() ? Result::Error : Result::Success;
}

SWC_END_NAMESPACE();
