#include "pch.h"
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
              TokenId::Identifier))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNode>();
        consume();
        return nodeRef;
    }

    if (is(TokenId::SymLeftBracket))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNode>();
        skipTo({TokenId::SymRightBracket}, SkipUntilFlags::Consume);
        return nodeRef;
    }

    (void) reportError(DiagnosticId::ParserUnexpectedToken, tok());
    return INVALID_REF;
}

SWC_END_NAMESPACE()
