#include "pch.h"
#include "Core/SmallVector.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseIdentifierType()
{
    const auto identifier = parseQualifiedIdentifier();

    if (is(TokenId::SymLeftCurly) && tok().hasNotFlag(TokenFlagsE::BlankBefore))
        return parseInitializerList(identifier);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NamedType>(ref());
    nodePtr->nodeIdent      = identifier;
    return nodeRef;
}

AstNodeRef Parser::parseRetValType()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RetValType>(ref());
    consume();

    if (is(TokenId::SymLeftCurly) && tok().hasNotFlag(TokenFlagsE::BlankBefore))
        return parseInitializerList(nodeRef);

    return nodeRef;
}

AstNodeRef Parser::parseSingleType()
{
    // Builtin
    if (Token::isType(tok().id))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BuiltinType>(ref());
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
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousStructDecl>(ref());
            nodePtr->nodeBody       = parseAggregateBody();
            return nodeRef;
        }
        case TokenId::KwdUnion:
        {
            consume();
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousUnionDecl>(ref());
            nodePtr->nodeBody       = parseAggregateBody();
            return nodeRef;
        }
        case TokenId::SymLeftCurly:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousStructDecl>(ref());
            nodePtr->nodeBody       = parseAggregateBody();
            return nodeRef;
        }

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseLambdaType();

        case TokenId::CompilerDeclType:
            return parseCompilerCallUnary();

        default:
            break;
    }

    const auto diag = reportError(DiagnosticId::parser_err_invalid_type, ref());
    diag.report(*ctx_);
    return AstNodeRef::invalid();
}

AstNodeRef Parser::parseSubType()
{
    // Modifiers
    if (isAny(TokenId::KwdConst, TokenId::ModifierNullable))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::QualifiedType>(ref());
        consume();
        nodePtr->nodeType       = parseType();
        return nodeRef;
    }

    // Left reference
    if (consumeIf(TokenId::SymAmpersand).isValid())
    {
        const auto child = parseType();
        if (child.isInvalid())
            return AstNodeRef::invalid();
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LRefType>(ref());
        nodePtr->nodeType       = child;
        return nodeRef;
    }

    // Right reference
    if (consumeIf(TokenId::SymAmpersandAmpersand).isValid())
    {
        const auto child = parseType();
        if (child.isInvalid())
            return AstNodeRef::invalid();
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RRefType>(ref());
        nodePtr->nodeType       = child;
        return nodeRef;
    }

    // Pointer
    if (consumeIf(TokenId::SymAsterisk).isValid())
    {
        const auto child = parseType();
        if (child.isInvalid())
            return AstNodeRef::invalid();
        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::PointerType>(ref());
        nodePtr->nodePointeeType = child;
        return nodeRef;
    }

    // Array or slice
    const TokenRef leftBracket = consumeIf(TokenId::SymLeftBracket);
    if (leftBracket.isValid())
    {
        // [*]
        if (consumeIf(TokenId::SymAsterisk).isValid())
        {
            if (expectAndConsumeClosing(TokenId::SymRightBracket, leftBracket).isInvalid())
                return AstNodeRef::invalid();
            const auto child = parseType();
            if (child.isInvalid())
                return AstNodeRef::invalid();
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::BlockPointerType>(ref());
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // [..]
        if (consumeIf(TokenId::SymDotDot).isValid())
        {
            if (expectAndConsumeClosing(TokenId::SymRightBracket, leftBracket).isInvalid())
                return AstNodeRef::invalid();
            const auto child = parseType();
            if (child.isInvalid())
                return AstNodeRef::invalid();
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::SliceType>(ref());
            nodePtr->nodePointeeType = child;
            return nodeRef;
        }

        // [?]
        if (consumeIf(TokenId::SymQuestion).isValid())
        {
            if (expectAndConsumeClosing(TokenId::SymRightBracket, leftBracket).isInvalid())
                return AstNodeRef::invalid();
            const auto child = parseType();
            if (child.isInvalid())
                return AstNodeRef::invalid();
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ArrayType>(ref());
            nodePtr->spanDimensions.setInvalid();
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
            return AstNodeRef::invalid();
        }

        // Array with a dimension
        SmallVector<AstNodeRef> dimensions;
        const auto              firstDim = parseExpression();
        if (firstDim.isInvalid())
            return AstNodeRef::invalid();
        dimensions.push_back(firstDim);

        // Parse additional dimensions separated by commas
        while (consumeIf(TokenId::SymComma).isValid())
        {
            const auto dim = parseExpression();
            if (dim.isInvalid())
                return AstNodeRef::invalid();
            dimensions.push_back(dim);
        }

        if (expectAndConsumeClosing(TokenId::SymRightBracket, leftBracket).isInvalid())
            return AstNodeRef::invalid();

        // Recursively parse the rest of the type (handles chaining like [X][Y])
        const auto child = parseType();
        if (child.isInvalid())
            return AstNodeRef::invalid();

        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::ArrayType>(ref());
        nodePtr->spanDimensions  = ast_->store().push_span(dimensions.span());
        nodePtr->nodePointeeType = child;
        return nodeRef;
    }

    return parseSingleType();
}

AstNodeRef Parser::parseType()
{
    // 'retval'
    if (is(TokenId::KwdRetVal))
        return parseRetValType();

    // '#code'
    if (consumeIf(TokenId::CompilerCode).isValid())
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CodeType>(ref());
        nodePtr->nodeType       = parseSubType();
        return nodeRef;
    }

    // '...'
    if (consumeIf(TokenId::SymDotDotDot).isValid())
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VariadicType>(ref());
        return nodeRef;
    }

    const auto nodeSubType = parseSubType();

    // 'type...'
    if (consumeIf(TokenId::SymDotDotDot).isValid())
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TypedVariadicType>(ref());
        nodePtr->nodeType       = nodeSubType;
        return nodeRef;
    }

    return nodeSubType;
}

SWC_END_NAMESPACE()
