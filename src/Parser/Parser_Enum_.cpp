#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseEnumImplDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumImplDecl>();
    consume(TokenId::KwdImpl);
    consume(TokenId::KwdEnum);

    nodePtr->nodeName = parseScopedIdentifier();
    if (invalid(nodePtr->nodeName))
        skipTo({TokenId::SymLeftCurly});

    nodePtr->spanChildren = parseBlockContent(AstNodeId::EnumImplDecl, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::Identifier};

    switch (id())
    {
    case TokenId::KwdUsing:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumUsingValue>();
        consume();
        nodePtr->nodeName = parseScopedIdentifier();
        return nodeRef;
    }

    case TokenId::Identifier:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumValue>();
        nodePtr->tknName        = consume();
        if (consumeIf(TokenId::SymEqual))
        {
            nodePtr->nodeValue = parseExpression();
            if (invalid(nodePtr->nodeValue))
                skipTo(ENUM_VALUE_SYNC, SkipUntilFlags::EolBefore);
        }
        return nodeRef;
    }

    case TokenId::CompilerAst:
        return parseCompilerFunc();

    case TokenId::SymAttrStart:
        return parseCompilerAttribute(AstNodeId::EnumDecl);

    default:
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        return INVALID_REF;
    }
}

AstNodeRef Parser::parseEnumDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumDecl>();
    consume(TokenId::KwdEnum);

    // Name
    nodePtr->tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (invalid(nodePtr->tknName))
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon});

    // Type
    if (consumeIf(TokenId::SymColon))
    {
        nodePtr->nodeType = parseType();
        if (invalid(nodePtr->nodeType))
            skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly});
    }

    // Content
    nodePtr->spanChildren = parseBlockContent(AstNodeId::EnumDecl, TokenId::SymLeftCurly);

    return nodeRef;
}

SWC_END_NAMESPACE()
