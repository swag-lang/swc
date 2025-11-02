#include "pch.h"
#include "Parser/AstNode.h"
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
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumUsingValue>();
        consume();
        nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
        if (isInvalid(nodePtr->tknName))
            skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
        result = nodeRef;
        break;
    }

    case TokenId::Identifier:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumValue>();

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
        (void) reportError(DiagnosticId::ParserUnexpectedToken, tok());
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
    setReportExpected(diag, TokenId::SymComma);
    diag.addArgument(Diagnostic::ARG_BECAUSE, DiagnosticId::BecauseEnumValues, false);

    skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
    return result;
}

AstNodeRef Parser::parseEnum()
{
    static constexpr std::initializer_list END_OR_START_BLOCK = {TokenId::SymLeftCurly, TokenId::SymRightCurly};

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumDecl>();
    consume(TokenId::KwdEnum);

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
    nodePtr->nodeBody = parseBlock(AstNodeId::EnumBlock, TokenId::SymLeftCurly);
    if (isInvalid(nodePtr->nodeBody))
        skipTo(END_OR_START_BLOCK);

    return nodeRef;
}

AstNodeRef Parser::parseEnumImpl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumImpl>();
    consume(TokenId::KwdImpl);
    consume(TokenId::KwdEnum);
    nodePtr->nodeName = parseIdentifier();
    if (isInvalid(nodePtr->nodeName))
        skipTo({TokenId::SymLeftCurly});

    nodePtr->nodeBody = parseBlock(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
