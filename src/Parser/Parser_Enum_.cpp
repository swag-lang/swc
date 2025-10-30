#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::EndOfLine, TokenId::Identifier};

    EnsureConsume ec(*this);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeEnumValue>(ref());

    // Name
    nodePtr->name = expectAndConsumeSingle(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
    if (isInvalid(nodePtr->name))
        skipTo(ENUM_VALUE_SYNC);
    skipTrivia();

    // Value
    if (consumeIf(TokenId::SymEqual))
    {
        nodePtr->value = parseExpression();
        if (isInvalid(nodePtr->value))
            skipTo(ENUM_VALUE_SYNC);
    }

    // End of value
    if (isNot(TokenId::SymRightCurly) && !consumeIfAny(TokenId::SymComma, TokenId::EndOfLine))
    {
        (void) expect(Expect::one(TokenId::SymComma, DiagnosticId::ParserExpectedTokenAfter).because(DiagnosticId::BecauseEnumValues));
        skipTo(ENUM_VALUE_SYNC);
    }

    return nodeRef;
}

AstNodeRef Parser::parseEnum()
{
    static constexpr std::initializer_list START_END_BLOCK = {TokenId::SymLeftCurly, TokenId::SymRightCurly};

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeEnumDecl>(consume());

    // Name
    nodePtr->name = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFamAfter);
    if (isInvalid(nodePtr->name))
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon});

    // Type
    if (consumeIf(TokenId::SymColon))
    {
        nodePtr->type = parseType();
        if (isInvalid(nodePtr->type))
            skipTo(START_END_BLOCK);
    }

    // Content
    const auto leftCurly = expect(Expect::one(TokenId::SymLeftCurly, DiagnosticId::ParserExpectedTokenAfter).because(DiagnosticId::BecauseStartEnumBody));
    if (isInvalid(leftCurly))
    {
        skipTo(START_END_BLOCK);
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
