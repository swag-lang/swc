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
    SWC_ASSERT(!file_->lexOut_.tokens_.empty());

    firstToken_ = &file_->lexOut_.tokens_.front();
    lastToken_  = &file_->lexOut_.tokens_.back();
    curToken_   = firstToken_;

    ast_->root_ = parseTopLevelBlock(AstNodeId::File);

    return file_->hasError() ? Result::Error : Result::Success;
}

SWC_END_NAMESPACE();
