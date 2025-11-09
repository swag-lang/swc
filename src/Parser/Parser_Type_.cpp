#include "pch.h"
#include "Core/SmallVector.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseIdentifierType()
{
    const auto identifier = parseQualifiedIdentifier();

    if (is(TokenId::SymLeftCurly) && tok().hasNotFlag(TokenFlagsE::BlankBefore))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::StructInit>();
        nodePtr->nodeExpr       = identifier;
        nodePtr->nodeArgs       = parseCompound(AstNodeId::NamedArgList, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NamedType>();
    nodePtr->nodeIdent      = identifier;
    return nodeRef;
}

AstNodeRef Parser::parseSingleType()
{
    // Builtin
    if (tok().isType())
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BuiltinType>();
        nodePtr->tokType        = consume();
        return nodeRef;
    }

    switch (id())
    {
    case TokenId::Identifier:
        return parseIdentifierType();

    case TokenId::KwdStruct:
    {
        consume();
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousStructDecl>();
        nodePtr->nodeBody       = parseAggregateBody();
        return nodeRef;
    }
    case TokenId::KwdUnion:
    {
        consume();
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousUnionDecl>();
        nodePtr->nodeBody       = parseAggregateBody();
        return nodeRef;
    }
    case TokenId::SymLeftCurly:
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousStructDecl>();
        nodePtr->nodeBody       = parseAggregateBody();
        return nodeRef;
    }

    case TokenId::KwdFunc:
    case TokenId::KwdMtd:
        return parseLambdaType();

    case TokenId::CompilerDeclType:
        return parseInternalCallUnary(AstNodeId::CompilerCallUnary);

    default:
        break;
    }

    const auto diag = reportError(DiagnosticId::parser_err_invalid_type, ref());
    diag.report(*ctx_);
    return INVALID_REF;
}

AstNodeRef Parser::parseType()
{
    // Const
    if (isAny(TokenId::KwdConst, TokenId::ModifierNullable))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::QualifiedType>();
        nodePtr->tokQual        = consume();
        nodePtr->nodeType       = parseType();
        return nodeRef;
    }

    // Left reference
    if (consumeIf(TokenId::SymAmpersand))
    {
        const auto child = parseType();
        if (invalid(child))
            return INVALID_REF;
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LRefType>();
        nodePtr->nodeType       = child;
        return nodeRef;
    }

    // Right reference
    if (consumeIf(TokenId::SymAmpersandAmpersand))
    {
        const auto child = parseType();
        if (invalid(child))
            return INVALID_REF;
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RRefType>();
        nodePtr->nodeType       = child;
        return nodeRef;
    }

    // Pointer
    if (consumeIf(TokenId::SymAsterisk))
    {
        const auto child = parseType();
        if (invalid(child))
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
            if (invalid(expectAndConsumeClosingFor(TokenId::SymLeftBracket, leftBracket)))
                return INVALID_REF;
            const auto child = parseType();
            if (invalid(child))
                return INVALID_REF;
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::BlockPointerType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // [..]
        if (consumeIf(TokenId::SymDotDot))
        {
            if (invalid(expectAndConsumeClosingFor(TokenId::SymLeftBracket, leftBracket)))
                return INVALID_REF;
            const auto child = parseType();
            if (invalid(child))
                return INVALID_REF;
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::SliceType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // [?]
        if (consumeIf(TokenId::SymQuestion))
        {
            if (invalid(expectAndConsumeClosingFor(TokenId::SymLeftBracket, leftBracket)))
                return INVALID_REF;
            const auto child = parseType();
            if (invalid(child))
                return INVALID_REF;
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::IncompleteArrayType>();
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // []
        if (is(TokenId::SymRightBracket))
        {
            auto diag = reportError(DiagnosticId::parser_err_expected_array_dim, ref());
            diag.addElement(DiagnosticId::parser_help_empty_array_dim);
            diag.report(*ctx_);
            consume();
            return INVALID_REF;
        }

        // Array with a dimension
        SmallVector<AstNodeRef> dimensions;
        const auto              firstDim = parseExpression();
        if (invalid(firstDim))
            return INVALID_REF;
        dimensions.push_back(firstDim);

        // Parse additional dimensions separated by commas
        while (consumeIf(TokenId::SymComma))
        {
            const auto dim = parseExpression();
            if (invalid(dim))
                return INVALID_REF;
            dimensions.push_back(dim);
        }

        if (invalid(expectAndConsumeClosingFor(TokenId::SymLeftBracket, leftBracket)))
            return INVALID_REF;

        // Recursively parse the rest of the type (handles chaining like [X][Y])
        const auto child = parseType();
        if (invalid(child))
            return INVALID_REF;

        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::ArrayType>();
        nodePtr->spanDimensions  = ast_->store_.push_span(dimensions.span());
        nodePtr->nodePointeeType = child;
        return nodeRef;
    }

    return parseSingleType();
}

SWC_END_NAMESPACE()
