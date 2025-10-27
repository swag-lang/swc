#include "pch.h"

#include "Parser/Parser.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelCurlyBlock()
{
    const auto openToken = curToken_;
    auto [ref, node] = ast_->makeNodePtr<AstNodeDelimitedBlock>(AstNodeId::CurlyBlock, eat());

    SmallVector<AstNodeRef> stmts;
    while (!atEnd() && id() != TokenId::SymRightCurly)
    {
        const auto before = curToken_;
        stmts.push_back(parseTopLevelDecl());
        if (curToken_ == before)
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, eat()));
    }

    if (id() == TokenId::SymRightCurly)
        node->closeToken = eat();
    else
        reportError(DiagnosticId::ParserUnterminatedCurlyBlock, openToken);

    node->children = ast_->store_.push_span(std::span<AstNodeRef>(stmts.data(), stmts.size()));
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
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, eat()));
    }

    node->children = ast_->store_.push_span(std::span<AstNodeRef>(stmts.data(), stmts.size()));
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
