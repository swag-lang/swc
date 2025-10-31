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
    if (is(TokenId::SymAmpersand))
    {
        consume();
        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeRefType>(AstNodeId::LRefType);
        consume();
        nodePtr->nodeType = child;
        return nodeRef;
    }

    // Right reference
    if (is(TokenId::SymAmpersandAmpersand))
    {
        consume();
        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeRefType>(AstNodeId::RRefType);
        consume();
        nodePtr->nodeType = child;
        return nodeRef;
    }

    // Pointer
    if (is(TokenId::SymAsterisk))
    {
        consume();
        const auto child = parseType();
        if (isInvalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodePointerType>();
        nodePtr->pointeeType    = child;
        return nodeRef;
    }

    // Array or slice
    if (is(TokenId::SymLeftBracket))
    {
        consume();

        // [*]
        if (is(TokenId::SymAsterisk))
        {
            consume();
            auto child = expectAndConsume(TokenId::SymRightBracket, DiagnosticId::ParserExpectedTokenAfter);
            if (isInvalid(child))
                return INVALID_REF;

            child = parseType();
            if (isInvalid(child))
                return INVALID_REF;

            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeBlockPointerType>();
            nodePtr->pointeeType    = child;
            return nodeRef;
        }
    }

    return parseSingleType();
}

SWC_END_NAMESPACE()
