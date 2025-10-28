#include "pch.h"

#include "Parser/AstNodes.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseBlock(AstNodeId nodeId, TokenId endStmt)
{
    const auto& openToken = tok();

    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeBlock>(nodeId, ref());
    if (endStmt != TokenId::Invalid)
        consume();

    SmallVector<AstNodeRef> stmts;
    while (!atEnd() && isNot(endStmt))
    {
        const auto before = curToken_;

        AstNodeRef stmt;
        switch (nodeId)
        {
        case AstNodeId::File:
        case AstNodeId::TopLevelBlock:
            stmt = parseTopLevelDecl();
            break;
        default:
            std::unreachable();
        }

        if (stmt != INVALID_REF)
            stmts.push_back(stmt);

        // Be sure to advance one token
        if (curToken_ == before)
            stmts.push_back(ast_->makeNode(AstNodeId::Invalid, consume()));
    }

    // Consume end token if necessary
    if (endStmt != TokenId::Invalid)
    {
        if (is(endStmt))
            consumeTrivia();
        else
            reportError(DiagnosticId::ParserUnterminatedBlock, openToken);
    }

    nodePtr->children = ast_->store_.push_span(std::span(stmts.data(), stmts.size()));
    return nodeRef;
}

AstNodeRef Parser::parseFile()
{
    return parseBlock(AstNodeId::File, TokenId::Invalid);
}

AstNodeRef Parser::parseTopLevelDecl()
{
    switch (id())
    {
    case TokenId::SymLeftCurly:
        return parseBlock(AstNodeId::TopLevelBlock, TokenId::SymRightCurly);
    case TokenId::SymRightCurly:
        reportError(DiagnosticId::ParserUnexpectedToken, tok());
        return ast_->makeNode(AstNodeId::Invalid, consume());
    case TokenId::SymSemiColon:
        consumeTrivia();
        return INVALID_REF;
    case TokenId::KwdEnum:
        return parseEnum();
    default:
        break;
    }

    const auto curTokenRef = ref();
    skipUntil({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlags::StopAfterEol);
    return ast_->makeNode(AstNodeId::Invalid, curTokenRef);
}

SWC_END_NAMESPACE();
