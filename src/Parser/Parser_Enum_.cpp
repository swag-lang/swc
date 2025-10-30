#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnum()
{
    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeEnumDecl>(AstNodeId::EnumDecl, consume());

    nodePtr->name = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFamAfter);
    if (nodePtr->name == INVALID_REF)
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon, TokenId::SymSemiColon});

    if (is(TokenId::SymColon))
    {
        consumeTrivia();

        const auto before = curToken_;
        nodePtr->type = parseType();
        if (nodePtr->type == INVALID_REF)
            skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly, TokenId::SymSemiColon});
        if (before == curToken_)
            consume();
    }

    const auto leftCurly = expect(TokenId::SymLeftCurly, DiagnosticId::ParserExpectedTokenAfter);
    if (leftCurly == INVALID_REF)
    {
        skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly, TokenId::SymSemiColon});
        if (isNot(TokenId::SymLeftCurly))
        {
            nodePtr->body = INVALID_REF;
            if (is(TokenId::SymRightCurly) || is(TokenId::SymSemiColon))
                consume();
            return nodeRef;
        }
    }

    nodePtr->body = parseBlock(AstNodeId::EnumBody, TokenId::SymRightCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
