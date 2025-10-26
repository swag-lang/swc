#include "pch.h"

#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelDecl()
{
    switch (curToken_->id)
    {
        case TokenId::SymLeftCurly:
            return parseTopLevelCurlyBlock();
        case TokenId::SymRightCurly:
            reportError(DiagnosticId::ParserUnexpectedToken, curToken_);
            return ast_->makeNode(AstNodeId::Invalid, eat());
        default:
            break;
    }

    return ast_->makeNode(AstNodeId::Invalid, eat());
}

AstNodeRef Parser::parseTopLevelCurlyBlock()
{
    const auto myTokenRef = tokenRef();
    const auto myToken    = curToken_;
    const auto startCurly = ast_->makeNode(AstNodeId::Delimiter, eat());

    SmallVector<AstNodeRef> stmts;
    stmts.push_back(startCurly);

    while (!atEnd() && id() != TokenId::SymRightCurly)
    {
        const auto result = parseTopLevelDecl();
        if (result != INVALID_REF)
            stmts.push_back(result);
    }

    if (id() == TokenId::SymRightCurly)
    {
        stmts.push_back(ast_->makeNode(AstNodeId::Delimiter, eat()));
    }
    else
    {
        stmts.push_back(ast_->makeNode(AstNodeId::MissingToken, tokenRef()));
        reportError(DiagnosticId::ParserUnterminatedCurlyBlock, myToken);
    }

    return ast_->makeBlock(AstNodeId::CurlyBlock, myTokenRef, stmts);
}

AstNodeRef Parser::parseFile()
{
    const auto myTokenRef = tokenRef();

    SmallVector<AstNodeRef> stmts;
    while (!atEnd())
    {
        const auto result = parseTopLevelDecl();
        if (result != INVALID_REF)
            stmts.push_back(result);
    }

    return ast_->makeBlock(AstNodeId::File, myTokenRef, stmts);
}

SWC_END_NAMESPACE();
