#include "pch.h"
#include "Parser/Parser.h"
#include "Core/Timer.h"
#include "Lexer/SourceFile.h"
#include "Main/Context.h"
#include "Report/Stats.h"

SWC_BEGIN_NAMESPACE();

void Parser::nextToken()
{
    SWC_ASSERT(curToken_->id != TokenId::EndOfFile);
    curToken_++;
    while (curToken_->id == TokenId::Blank || curToken_->id == TokenId::Eol)
        curToken_++;
}

Result Parser::parse(Context& ctx)
{
#if SWC_HAS_STATS
    Timer time(&Stats::get().timeParser);
#endif

    file_ = ctx.sourceFile();
    ast_  = &file_->parserOut_.ast_;

    SWC_CHECK(file_->loadContent(ctx));
    SWC_CHECK(file_->tokenize(ctx));

    // Root node
    ast_->root_ = ast_->makeNode(AstNodeId::File, file_->ref());
    if (file_->lexOut_.tokens_.empty())
        return Result::Success;

    // Top level
    curToken_  = &file_->lexOut_.tokens_.front();
    lastToken_ = &file_->lexOut_.tokens_.back();
    while (curToken_ < lastToken_)
    {
        nextToken();
    }

    return Result::Success;
}

SWC_END_NAMESPACE();
