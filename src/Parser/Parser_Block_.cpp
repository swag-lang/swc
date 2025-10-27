#include "pch.h"

#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelCurlyBlock()
{
    const auto openToken    = curToken_;
    const auto openTokenRef = eat();

    SmallVector<AstNodeRef> stmts;
    while (!atEnd() && id() != TokenId::SymRightCurly)
    {
        const auto before = curToken_;
        stmts.push_back(parseTopLevelDecl());
        if (curToken_ == before)
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, eat()));
    }

    TokenRef closeTokenRef = INVALID_REF;
    if (id() == TokenId::SymRightCurly)
        closeTokenRef = eat();
    else
        reportError(DiagnosticId::ParserUnterminatedCurlyBlock, openToken);

    return ast_->makeBlock(AstNodeId::CurlyBlock, openTokenRef, closeTokenRef, stmts);
}

AstNodeRef Parser::parseFile()
{
    const auto myTokenRef = tokenRef();

    SmallVector<AstNodeRef> stmts;
    while (!atEnd())
    {
        const auto before = curToken_;
        stmts.push_back(parseTopLevelDecl());
        if (curToken_ == before)
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, eat()));
    }

    return ast_->makeBlock(AstNodeId::File, myTokenRef, stmts);
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
            return ast_->makeNode(AstNodeId::SemiCol, eat());
        case TokenId::KwdEnum:
            return parseEnum();
        default:
            break;
    }

    const auto curTokenRef = tokenRef();
    skipUntil({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::StopAfterEol);
    return ast_->makeNode(AstNodeId::Invalid, curTokenRef);
}

SWC_END_NAMESPACE();
