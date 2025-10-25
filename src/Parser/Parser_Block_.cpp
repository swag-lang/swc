#include "pch.h"

#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelBlock(AstNodeId id)
{
    const auto myTokenRef = tokenRef();

    std::vector<AstNodeRef> stmts;

    while (curToken_ < lastToken_)
    {
        const auto result = parseTopLevelDecl();
        if (result != INVALID_REF)
            stmts.push_back(result);
    }

    return ast_->makeBlock(id, myTokenRef, stmts);
}

AstNodeRef Parser::parseTopLevelDecl()
{
    return ast_->makeNode(AstNodeId::Invalid, takeToken());
}

SWC_END_NAMESPACE();
