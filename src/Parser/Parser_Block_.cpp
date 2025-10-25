#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelBlock(AstNodeId id)
{
    const auto start = static_cast<TokenRef>(curToken_ - firstToken_);

    std::vector<AstNodeRef> stmts;
    while (curToken_ < lastToken_)
    {
        stmts.push_back(parseTopLevelInstruction());
    }

    return ast_->makeBlock(AstNodeId::File, start, stmts);
}

AstNodeRef Parser::parseTopLevelInstruction()
{
    const auto start = static_cast<TokenRef>(curToken_ - firstToken_);
    nextToken();
    return ast_->makeNode(AstNodeId::Invalid, file_->ref(), start);
}

SWC_END_NAMESPACE();
