#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnumValue()
{
    EnsureConsume ec(*this);

    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeEnumValue>(AstNodeId::EnumValue, ref());

    // Name
    nodePtr->name = expectAndConsume(TokenId::Identifier);
    if (isInvalid(nodePtr->name))
        skipTo({TokenId::SymRightCurly, TokenId::SymComma, TokenId::EndOfLine, TokenId::SymSemiColon});

    // Value
    if (is(TokenId::SymEqual))
    {
        consumeAsTrivia();
        nodePtr->value = parseExpression();
        if (isInvalid(nodePtr->value))
            skipTo({TokenId::SymRightCurly, TokenId::SymComma, TokenId::EndOfLine, TokenId::SymSemiColon});
    }

    if (is(TokenId::SymComma) || is(TokenId::EndOfLine) || is(TokenId::SymSemiColon))
        consumeAsTrivia();
    else if (isNot(TokenId::SymRightCurly))
    {
        (void) expect(TokenId::SymComma);
        skipTo({TokenId::SymRightCurly, TokenId::SymComma, TokenId::EndOfLine, TokenId::SymSemiColon});
    }

    return nodeRef;
}

AstNodeRef Parser::parseEnum()
{
    EnsureConsume ec(*this);

    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeEnumDecl>(AstNodeId::EnumDecl, consume());

    // Name
    nodePtr->name = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFamAfter);
    if (isInvalid(nodePtr->name))
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon, TokenId::SymSemiColon});

    // Type
    if (is(TokenId::SymColon))
    {
        consumeAsTrivia();
        nodePtr->type = parseType();
        if (isInvalid(nodePtr->type))
            skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly});
    }

    // Content
    const auto leftCurly = expect(TokenId::SymLeftCurly, DiagnosticId::ParserExpectedTokenAfter);
    if (isInvalid(leftCurly))
    {
        skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly});
        if (isNot(TokenId::SymLeftCurly))
        {
            nodePtr->body = INVALID_REF;
            if (is(TokenId::SymRightCurly))
                consume();
            return nodeRef;
        }
    }

    nodePtr->body = parseBlock(AstNodeId::EnumBlock, TokenId::SymRightCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
