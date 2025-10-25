#include "pch.h"

#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelBlock(AstNodeId id)
{
    const auto myRef = tokenRef();

    std::vector<AstNodeRef> stmts;

    while (curToken_ < lastToken_)
    {
        const auto result = parseTopLevelDecl();
        if (result != INVALID_REF)
            stmts.push_back(result);
    }

    return ast_->makeBlock(id, myRef, stmts);
}

AstNodeRef Parser::parseTopLevelDecl()
{
    const auto myRef = tokenRef();
    nextToken();
    return ast_->makeNode(AstNodeId::Invalid, myRef);
}

SWC_END_NAMESPACE();
