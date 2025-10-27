#include "pch.h"

#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelCurlyBlock()
{
    const auto myTokenRef = tokenRef();
    const auto myToken    = curToken_;
    const auto startCurly = ast_->makeNode(AstNodeId::Delimiter, eat());

    SmallVector<AstNodeRef> stmts;
    stmts.push_back(startCurly);

    while (!atEnd() && id() != TokenId::SymRightCurly)
    {
        const auto before = curToken_;
        const auto result = parseTopLevelDecl();
        if (result != INVALID_REF)
            stmts.push_back(result);
        if (curToken_ == before)
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, eat()));
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

    return ast_->makeCompound(AstNodeId::CurlyBlock, myTokenRef, stmts);
}

AstNodeRef Parser::parseFile()
{
    const auto myTokenRef = tokenRef();

    SmallVector<AstNodeRef> stmts;
    while (!atEnd())
    {
        const auto before = curToken_;
        const auto result = parseTopLevelDecl();
        if (result != INVALID_REF)
            stmts.push_back(result);
        if (curToken_ == before)
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, eat()));
    }

    return ast_->makeCompound(AstNodeId::File, myTokenRef, stmts);
}

AstNodeRef Parser::parseTopLevelDecl()
{
    switch (curToken_->id)
    {
        case TokenId::SymLeftCurly:
            return parseTopLevelCurlyBlock();
        case TokenId::SymRightCurly:
            reportError(DiagnosticId::ParserUnexpectedToken, curToken_);
            return ast_->makeNode(AstNodeId::Invalid, eat());
        case TokenId::SymSemiColon:
            return ast_->makeNode(AstNodeId::Delimiter, eat());
        case TokenId::KwdEnum:
            return parseEnum();
        default:
            break;
    }

    const auto curTokenRef = tokenRef();
    skipUntil({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsEnum::StopAfterEol);
    return ast_->makeNode(AstNodeId::Invalid, curTokenRef);
}

SWC_END_NAMESPACE();
