#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseSingleType()
{
    // Builtin
    if (tok().isType())
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BuiltinType>();
        nodePtr->tknType        = consume();
        return nodeRef;
    }

    switch (id())
    {
    case TokenId::Identifier:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NamedType>();
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

    const auto diag = reportError(DiagnosticId::ParserInvalidType, ref());
    diag.report(*ctx_);
    return INVALID_REF;
}

AstNodeRef Parser::parseType()
{
    // Const
    if (is(TokenId::KwdConst))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::QualifiedType>();
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

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LRefType>();
        nodePtr->nodeType       = child;
        return nodeRef;
    }

    // Right reference
    if (consumeIf(TokenId::SymAmpersandAmpersand))
    {
        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RRefType>();
        nodePtr->nodeType       = child;
        return nodeRef;
    }

    // Pointer
    if (consumeIf(TokenId::SymAsterisk))
    {
        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::PointerType>();
        nodePtr->nodePointeeType = child;
        return nodeRef;
    }

    // Array or slice
    TokenRef leftBracket;
    if (consumeIf(TokenId::SymLeftBracket, &leftBracket))
    {
        // [*]
        if (consumeIf(TokenId::SymAsterisk))
        {
            if (isInvalid(expectAndConsumeClosingFor(TokenId::SymLeftBracket, leftBracket)))
                return INVALID_REF;

            const auto child = parseType();
            if (isInvalid(child))
                return INVALID_REF;

            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::BlockPointerType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // [..]
        if (consumeIf(TokenId::SymDotDot))
        {
            if (isInvalid(expectAndConsumeClosingFor(TokenId::SymLeftBracket, leftBracket)))
                return INVALID_REF;

            const auto child = parseType();
            if (isInvalid(child))
                return INVALID_REF;

            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::SliceType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // [?]
        if (consumeIf(TokenId::SymQuestion))
        {
            if (isInvalid(expectAndConsumeClosingFor(TokenId::SymLeftBracket, leftBracket)))
                return INVALID_REF;

            const auto child = parseType();
            if (isInvalid(child))
                return INVALID_REF;

            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::IncompleteArrayType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // []
        if (is(TokenId::SymRightBracket))
        {
            auto diag = reportError(DiagnosticId::ParserExpectedArrayDim, ref());
            diag.addElement(DiagnosticId::ParserHelpEmptyArrayDim);
            diag.report(*ctx_);
            consume();
            return INVALID_REF;
        }

        // Array with a dimension
        const auto dim = parseExpression();
        if (isInvalid(dim))
            return INVALID_REF;

        if (isInvalid(expectAndConsumeClosingFor(TokenId::SymLeftBracket, leftBracket)))
            return INVALID_REF;

        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::ArrayType>();
        nodePtr->nodeDim         = dim;
        nodePtr->nodePointeeType = child;
        return nodeRef;
    }

    return parseSingleType();
}

SWC_END_NAMESPACE()
