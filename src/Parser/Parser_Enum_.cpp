#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::Identifier};

    switch (id())
    {
    case TokenId::KwdUsing:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumUsingValue>();
        consume();
        nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenFam);
        if (isInvalid(nodePtr->tknName))
            skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
        return nodeRef;
    }

    case TokenId::Identifier:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumValue>();
        nodePtr->tknName        = consume();
        if (consumeIf(TokenId::SymEqual))
        {
            nodePtr->nodeValue = parseExpression();
            if (isInvalid(nodePtr->nodeValue))
                skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
        }
        return nodeRef;
    }

    case TokenId::CompilerAst:
        return parseCompilerFunc();

    case TokenId::SymAttrStart:
        return parseCompilerAttribute(AstNodeId::EnumBlock);

    default:
        raiseError(DiagnosticId::ParserUnexpectedToken, ref());
        return INVALID_REF;
    }
}

AstNodeRef Parser::parseEnum()
{
    static constexpr std::initializer_list END_OR_START_BLOCK = {TokenId::SymLeftCurly, TokenId::SymRightCurly};

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumDecl>();
    consume(TokenId::KwdEnum);

    // Name
    nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::ParserExpectedTokenBeforeFam, ref());
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
    nodePtr->nodeBody = parseBlock(TokenId::SymLeftCurly, AstNodeId::EnumBlock);
    if (isInvalid(nodePtr->nodeBody))
        skipTo(END_OR_START_BLOCK);

    return nodeRef;
}

AstNodeRef Parser::parseEnumImpl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumImpl>();
    consume(TokenId::KwdImpl);
    consume(TokenId::KwdEnum);
    nodePtr->nodeName = parseScopedIdentifier();
    if (isInvalid(nodePtr->nodeName))
        skipTo({TokenId::SymLeftCurly});

    nodePtr->nodeBody = parseBlock(TokenId::SymLeftCurly, AstNodeId::ImplBlock);
    return nodeRef;
}

SWC_END_NAMESPACE()
