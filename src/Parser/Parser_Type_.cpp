#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseSingleType()
{
    // Builtin
    if (tok().isType())
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeBuiltinType>();
        nodePtr->tknType        = consume();
        return nodeRef;
    }

    switch (id())
    {
    case TokenId::Identifier:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeNamedType>();
        nodePtr->tknName        = consume();
        return nodeRef;
    }

    case TokenId::KwdStruct:
        break;

    case TokenId::KwdUnion:
        break;

    case TokenId::SymLeftCurly:
        break;

    case TokenId::KwdFunc:
    case TokenId::KwdMtd:
        break;

    case TokenId::CompilerDeclType:
        break;

    default:
        break;
    }

    auto diag = reportError(DiagnosticId::ParserInvalidType, tok());
    return INVALID_REF;
}

AstNodeRef Parser::parseType()
{
    // Const
    if (is(TokenId::KwdConst))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeQualifiedType>();
        nodePtr->tknQual        = consume();
        nodePtr->nodeType       = parseType();
        return nodeRef;
    }

    // Left reference
    if (consumeIf(TokenId::SymAmpersand))
    {
        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeRefType>(AstNodeId::LRefType);
        nodePtr->nodeType       = child;
        return nodeRef;
    }

    // Right reference
    if (consumeIf(TokenId::SymAmpersandAmpersand))
    {
        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeRefType>(AstNodeId::RRefType);
        nodePtr->nodeType       = child;
        return nodeRef;
    }

    // Pointer
    if (consumeIf(TokenId::SymAsterisk))
    {
        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodePointerType>();
        nodePtr->nodePointeeType = child;
        return nodeRef;
    }

    // Array or slice
    if (consumeIf(TokenId::SymLeftBracket))
    {
        // [*]
        if (consumeIf(TokenId::SymAsterisk))
        {
            (void) expectAndConsume(TokenId::SymRightBracket, DiagnosticId::ParserExpectedTokenAfter);

            const auto child = parseType();
            if (isInvalid(child))
                return INVALID_REF;

            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeBlockPointerType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // [..]
        if (consumeIf(TokenId::SymDotDot))
        {
            (void) expectAndConsume(TokenId::SymRightBracket, DiagnosticId::ParserExpectedTokenAfter);

            const auto child = parseType();
            if (isInvalid(child))
                return INVALID_REF;

            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeSliceType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // [?]
        if (consumeIf(TokenId::SymQuestion))
        {
            (void) expectAndConsume(TokenId::SymRightBracket, DiagnosticId::ParserExpectedTokenAfter);

            const auto child = parseType();
            if (isInvalid(child))
                return INVALID_REF;

            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeIncompleteArrayType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // Array with a dimension
        const auto dim = parseExpression();
        if (isInvalid(dim))
            return INVALID_REF;

        (void) expectAndConsume(TokenId::SymRightBracket, DiagnosticId::ParserExpectedTokenAfter);

        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeArrayType>();
        nodePtr->nodeDim         = dim;
        nodePtr->nodePointeeType = child;
        return nodeRef;
    }

    return parseSingleType();
}

SWC_END_NAMESPACE()
