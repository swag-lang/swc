#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseImplEnum()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplEnum>();
    consume(TokenId::KwdImpl);
    consume(TokenId::KwdEnum);

    nodePtr->nodeName = parseQualifiedIdentifier();
    if (invalid(nodePtr->nodeName))
        skipTo({TokenId::SymLeftCurly});

    nodePtr->spanChildren = parseCompoundContent(AstNodeId::ImplEnum, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::Identifier};

    switch (id())
    {
    case TokenId::KwdUsing:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumUse>();
        consume();
        nodePtr->nodeName = parseQualifiedIdentifier();
        return nodeRef;
    }

    case TokenId::Identifier:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumValue>();
        nodePtr->tokName        = consume();
        if (consumeIf(TokenId::SymEqual) != INVALID_REF)
        {
            nodePtr->nodeValue = parseExpression();
            if (invalid(nodePtr->nodeValue))
                skipTo(ENUM_VALUE_SYNC, SkipUntilFlagsE::EolBefore);
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
    nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (invalid(nodePtr->tokName))
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon});

    // Type
    if (consumeIf(TokenId::SymColon) != INVALID_REF)
    {
        nodePtr->nodeType = parseType();
        if (invalid(nodePtr->nodeType))
            skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly});
    }

    // Content
    nodePtr->spanChildren = parseCompoundContent(AstNodeId::EnumDecl, TokenId::SymLeftCurly);

    return nodeRef;
}

SWC_END_NAMESPACE()
