#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseExpression()
{
    if (isAny(TokenId::NumberInteger,
              TokenId::NumberFloat,
              TokenId::NumberBinary,
              TokenId::NumberHexadecimal,
              TokenId::StringLine,
              TokenId::StringRaw,
              TokenId::Character,
              TokenId::KwdTrue,
              TokenId::KwdFalse,
              TokenId::KwdNull,
              TokenId::Identifier))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Invalid>();
        consume();
        return nodeRef;
    }

    if (is(TokenId::SymLeftBracket))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Invalid>();
        consume();
        skipAfter({TokenId::SymRightBracket});
        return nodeRef;
    }

    (void) reportError(DiagnosticId::ParserUnexpectedToken, tok());
    return INVALID_REF;
}

AstNodeRef Parser::parseIdentifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Identifier>();
    nodePtr->tknName        = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
    return nodeRef;
}

SWC_END_NAMESPACE()
