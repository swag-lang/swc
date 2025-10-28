#include "pch.h"

#include "Parser/AstNodes.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelCurlyBlock()
{
    const auto openToken = curToken_;
    auto [ref, node]     = ast_->makeNodePtr<AstNodeDelimitedBlock>(AstNodeId::CurlyBlock, consume());

    SmallVector<AstNodeRef> stmts;
    while (!atEnd() && isNot(TokenId::SymRightCurly))
    {
        const auto before = curToken_;
        stmts.push_back(parseTopLevelDecl());
        if (curToken_ == before)
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, consume()));
    }

    if (id() == TokenId::SymRightCurly)
        node->closeToken = consume();
    else
        reportError(DiagnosticId::ParserUnterminatedCurlyBlock, openToken);

    node->children = ast_->store_.push_span(std::span(stmts.data(), stmts.size()));
    return ref;
}

AstNodeRef Parser::parseFile()
{
    auto [ref, node] = ast_->makeNodePtr<AstNodeBlock>(AstNodeId::File, tokenRef());

    SmallVector<AstNodeRef> stmts;
    while (!atEnd())
    {
        const auto before = curToken_;
        stmts.push_back(parseTopLevelDecl());
        if (curToken_ == before)
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, consume()));
    }

    node->children = ast_->store_.push_span(std::span(stmts.data(), stmts.size()));
    return ref;
}

AstNodeRef Parser::parseTopLevelDecl()
{
    switch (curToken_->id)
    {
        case TokenId::SymLeftCurly:
            return parseTopLevelCurlyBlock();
        case TokenId::SymRightCurly:
            reportError(DiagnosticId::ParserUnexpectedToken, curToken_);
            return ast_->makeNode(AstNodeId::Invalid, consume());
        case TokenId::SymSemiColon:
            return ast_->makeNode(AstNodeId::SemiCol, consume());
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
