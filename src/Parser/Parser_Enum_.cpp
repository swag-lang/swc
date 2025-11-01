#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::Identifier};

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeEnumValue>();

    // Name
    nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
    if (isInvalid(nodePtr->tknName))
    {
        skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
        return nodeRef;
    }

    // Value
    if (consumeIf(TokenId::SymEqual))
    {
        nodePtr->nodeValue = parseExpression();
        if (isInvalid(nodePtr->nodeValue))
        {
            skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
            return nodeRef;
        }
    }

    // End of value
    if (is(TokenId::SymRightCurly))
        return nodeRef;
    if (consumeIf(TokenId::SymComma))
        return nodeRef;
    if (tok().startsLine())
        return nodeRef;

    auto diag = reportError(DiagnosticId::ParserExpectedTokenAfter, tok());
    diag.addArgument(Diagnostic::ARG_EXPECT, TokenId::SymComma);
    diag.addArgument(Diagnostic::ARG_BECAUSE, Diagnostic::diagIdMessage(DiagnosticId::BecauseEnumValues), false);

    skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
    return nodeRef;
}

AstNodeRef Parser::parseEnum()
{
    static constexpr std::initializer_list START_END_BLOCK = {TokenId::SymLeftCurly, TokenId::SymRightCurly};

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeEnumDecl>();
    consume();

    // Name
    nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFamAfter);
    if (isInvalid(nodePtr->tknName))
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon});

    // Type
    if (consumeIf(TokenId::SymColon))
    {
        nodePtr->nodeType = parseType();
        if (isInvalid(nodePtr->nodeType))
            skipTo(START_END_BLOCK);
    }

    // Content
    const auto leftCurly = expect(ParserExpect::one(TokenId::SymLeftCurly, DiagnosticId::ParserExpectedTokenAfter).because(DiagnosticId::BecauseStartEnumBody));
    if (isInvalid(leftCurly))
    {
        skipTo(START_END_BLOCK);
        if (isNot(TokenId::SymLeftCurly))
        {
            nodePtr->nodeBody = INVALID_REF;
            if (is(TokenId::SymRightCurly))
                consume();
            return nodeRef;
        }
    }

    nodePtr->nodeBody = parseBlock(AstNodeId::EnumBlock, TokenId::SymRightCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
