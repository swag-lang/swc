#include "pch.h"

#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelBlock(AstNodeId id)
{
    const auto start = static_cast<TokenRef>(curToken_ - firstToken_);

    std::vector<AstNodeRef> stmts;
    while (curToken_ < lastToken_)
    {
        const auto stmt = parseTopLevelInstruction();
        if (stmt != INVALID_REF)
            stmts.push_back(stmt);
    }

    return ast_->makeBlock(id, start, stmts);
}

AstNodeRef Parser::parseTopLevelInstruction()
{
    const auto start = static_cast<TokenRef>(curToken_ - firstToken_);
    nextToken();
    return ast_->makeNode(AstNodeId::Invalid, start);
}

SWC_END_NAMESPACE();
