#include "pch.h"

#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelDecl()
{
    switch (curToken_->id)
    {
        case TokenId::OpLeftCurly:
            return parseTopLevelCurlyBlock();
        default:
            break;
    }

    return ast_->makeNode(AstNodeId::Invalid, takeToken());
}

AstNodeRef Parser::parseTopLevelCurlyBlock()
{
    const auto myTokenRef = tokenRef();
    const auto startCurly = ast_->makeNode(AstNodeId::Delimiter, takeToken());

    std::vector stmts = {startCurly};
    while (curToken_ < lastToken_ && curToken_->id != TokenId::OpRightCurly)
    {
        const auto result = parseTopLevelDecl();
        if (result != INVALID_REF)
            stmts.push_back(result);
    }

    if (curToken_->id == TokenId::OpRightCurly)
    {
        stmts.push_back(ast_->makeNode(AstNodeId::Delimiter, takeToken()));
    }
    else
    {
        stmts.push_back(ast_->makeNode(AstNodeId::Invalid, takeToken()));
    }

    return ast_->makeBlock(AstNodeId::CurlyBlock, myTokenRef, stmts);
}

AstNodeRef Parser::parseFile()
{
    const auto myTokenRef = tokenRef();

    std::vector<AstNodeRef> stmts;
    while (curToken_ < lastToken_)
    {
        const auto result = parseTopLevelDecl();
        if (result != INVALID_REF)
            stmts.push_back(result);
    }

    return ast_->makeBlock(AstNodeId::File, myTokenRef, stmts);
}

SWC_END_NAMESPACE();
