#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list<TokenId> EnumValueSync = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::EndOfLine, TokenId::Identifier};

    EnsureConsume ec(*this);

    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeEnumValue>(ref());

    // Name
    nodePtr->name = expectAndConsumeOne(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
    if (isInvalid(nodePtr->name))
        skipTo(EnumValueSync);
    skipTrivia();

    // Value
    if (consumeIf(TokenId::SymEqual))
    {
        nodePtr->value = parseExpression();
        if (isInvalid(nodePtr->value))
            skipTo(EnumValueSync);
    }

    // End of value
    if (isNot(TokenId::SymRightCurly) && !consumeIfAny(TokenId::SymComma, TokenId::EndOfLine))
    {
        (void) expect(Expect::One(TokenId::SymComma, DiagnosticId::ParserExpectedTokenAfter).because(DiagnosticId::BecauseEnumValues));
        skipTo(EnumValueSync);
    }

    return nodeRef;
}

AstNodeRef Parser::parseEnum()
{
    static constexpr std::initializer_list<TokenId> StartEndBlock = {TokenId::SymLeftCurly, TokenId::SymRightCurly};

    auto [nodeRef, nodePtr] = ast_->makeNodePtr<AstNodeEnumDecl>(consume());

    // Name
    nodePtr->name = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFamAfter);
    if (isInvalid(nodePtr->name))
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon});

    // Type
    if (consumeIf(TokenId::SymColon))
    {
        nodePtr->type = parseType();
        if (isInvalid(nodePtr->type))
            skipTo(StartEndBlock);
    }

    // Content
    const auto leftCurly = expect(Expect::One(TokenId::SymLeftCurly, DiagnosticId::ParserExpectedTokenAfter).because(DiagnosticId::BecauseStartEnumBody));
    if (isInvalid(leftCurly))
    {
        skipTo(StartEndBlock);
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
