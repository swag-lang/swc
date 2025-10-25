#include "pch.h"

#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

ParserResult Parser::parseTopLevelBlock(AstNodeId id)
{
    const auto myRef = tokenRef();

    ParserResult            result;
    std::vector<AstNodeRef> stmts;

    while (curToken_ < lastToken_)
    {
        result = parseTopLevelInstruction();
        if (result.node != INVALID_REF)
            stmts.push_back(result.node);
    }

    result.node = ast_->makeBlock(id, myRef, stmts);
    result.ok   = true;
    return result;
}

ParserResult Parser::parseTopLevelInstruction()
{
    const auto myRef = tokenRef();
    nextToken();

    ParserResult result;
    result.node = ast_->makeNode(AstNodeId::Invalid, myRef);
    result.ok   = true;
    return result;
}

SWC_END_NAMESPACE();
