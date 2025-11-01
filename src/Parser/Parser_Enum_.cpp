#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::Identifier};

    TokenRef result = INVALID_REF;
    switch (id())
    {
    case TokenId::KwdUsing:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeEnumUsingValue>();
        consume();
        nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
        if (isInvalid(nodePtr->tknName))
            skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
        result = nodeRef;
        break;
    }

    case TokenId::Identifier:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeEnumValue>();

        // Name
        nodePtr->tknName = consume();

        // Value
        if (consumeIf(TokenId::SymEqual))
        {
            nodePtr->nodeValue = parseExpression();
            if (isInvalid(nodePtr->nodeValue))
                skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
        }

        break;
    }

    default:
        auto diag = reportError(DiagnosticId::ParserExpectedTokenFam, tok());
        diag.addArgument(Diagnostic::ARG_EXPECT, TokenId::Identifier);
        break;
    }

    // End of value
    if (is(TokenId::SymRightCurly))
        return result;
    if (consumeIf(TokenId::SymComma))
        return result;
    if (tok().startsLine())
        return result;

    auto diag = reportError(DiagnosticId::ParserExpectedTokenAfter, tok());
    diag.addArgument(Diagnostic::ARG_EXPECT, TokenId::SymComma);
    diag.addArgument(Diagnostic::ARG_BECAUSE, DiagnosticId::BecauseEnumValues, false);

    skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
    return result;
}

AstNodeRef Parser::parseEnum()
{
    static constexpr std::initializer_list END_OR_START_BLOCK = {TokenId::SymLeftCurly, TokenId::SymRightCurly};

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
            skipTo(END_OR_START_BLOCK);
    }

    // Content
    const auto leftCurly = expect(ParserExpect::one(TokenId::SymLeftCurly, DiagnosticId::ParserExpectedTokenAfter).because(DiagnosticId::BecauseStartEnumBody));
    if (isInvalid(leftCurly))
    {
        skipTo(END_OR_START_BLOCK);
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

AstNodeRef Parser::parseEnumImpl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeEnumImpl>();
    skip(); // impl
    skip(); // enum
    nodePtr->nodeName = parseIdentifier();
    if (isInvalid(nodePtr->nodeName))
        skipTo({TokenId::SymLeftCurly});

    nodePtr->nodeBody = parseBlock(AstNodeId::TopLevelBlock, TokenId::SymRightCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
