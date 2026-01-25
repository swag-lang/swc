#include "pch.h"
#include "Parser/Parser.h"
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseIdentifierType()
{
    const TokenRef tokRef = ref();
    const auto     idRef  = parseQualifiedIdentifier();

    if (is(TokenId::SymLeftCurly) && !tok().hasFlag(TokenFlagsE::BlankBefore))
        return parseInitializerList(idRef);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::NamedType>(tokRef);
    nodePtr->nodeIdentRef   = idRef;
    return nodeRef;
}

AstNodeRef Parser::parseRetValType()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::RetValType>(consume());

    if (is(TokenId::SymLeftCurly) && !tok().hasFlag(TokenFlagsE::BlankBefore))
        return parseInitializerList(nodeRef);

    return nodeRef;
}

AstNodeRef Parser::parseSingleType()
{
    // Builtin
    if (Token::isType(tok().id))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::BuiltinType>(consume());
        return nodeRef;
    }

    switch (id())
    {
        case TokenId::Identifier:
            return parseIdentifierType();

        case TokenId::KwdStruct:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousStructDecl>(consume());
            nodePtr->nodeBodyRef    = parseAggregateBody();
            return nodeRef;
        }
        case TokenId::KwdUnion:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousUnionDecl>(consume());
            nodePtr->nodeBodyRef    = parseAggregateBody();
            return nodeRef;
        }
        case TokenId::SymLeftCurly:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AnonymousStructDecl>(ref());
            nodePtr->nodeBodyRef    = parseAggregateBody();
            return nodeRef;
        }

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseLambdaType();

        case TokenId::CompilerDeclType:
            return parseCompilerCall(1);

        default:
            break;
    }

    raiseError(DiagnosticId::parser_err_invalid_type, ref());
    return AstNodeRef::invalid();
}

namespace
{
    struct QualifierDesc
    {
        TokenId                           tokenId;
        EnumFlags<AstQualifiedTypeFlagsE> flag;
        uint8_t                           order;
    };

    constexpr QualifierDesc G_QUALIFIER_TABLE[] = {
        {.tokenId = TokenId::ModifierNullable, .flag = AstQualifiedTypeFlagsE::Nullable, .order = 0},
        {.tokenId = TokenId::KwdConst, .flag = AstQualifiedTypeFlagsE::Const, .order = 1},
    };

    const QualifierDesc* findQualifier(TokenId id)
    {
        for (const auto& q : G_QUALIFIER_TABLE)
        {
            if (q.tokenId == id)
                return &q;
        }

        return nullptr;
    }
}

AstNodeRef Parser::parseSubType()
{
    EnumFlags      qualifiers  = AstQualifiedTypeFlagsE::Zero;
    uint8_t        lastOrder   = 0;
    const TokenRef firstTokRef = ref();

    // Consume all leading qualifiers in order, diagnose duplicates / mis-ordering.
    for (;;)
    {
        const auto* qd = findQualifier(id());
        if (!qd)
            break;

        const TokenRef tokRef = ref();

        // Duplicate?
        if (qualifiers.has(qd->flag))
        {
            raiseError(DiagnosticId::parser_err_duplicate_type_qualifier, tokRef);
            consume();
            continue;
        }

        // Misplaced (violates canonical order)?
        if (std::cmp_less(qd->order, lastOrder))
        {
            raiseError(DiagnosticId::parser_err_misplace_type_qualifier, tokRef);
            consume();
            continue;
        }

        qualifiers.add(qd->flag);
        lastOrder = qd->order;
        consume();
    }

    // Parse the core subtype (pointers, refs, arrays, base type…)
    const AstNodeRef subNodeRef = parseSubTypeNoQualifiers();
    if (subNodeRef.isInvalid())
        return AstNodeRef::invalid();

    // No qualifiers? Just return the core type.
    if (qualifiers == AstQualifiedTypeFlagsE::Zero)
        return subNodeRef;

    // Wrap in a single QualifiedType node with all flags set.
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::QualifiedType>(firstTokRef);
    nodePtr->nodeTypeRef    = subNodeRef;
    nodePtr->flags()        = qualifiers;
    return nodeRef;
}

AstNodeRef Parser::parseSubTypeNoQualifiers()
{
    // Left reference
    if (consumeIf(TokenId::SymAmpersand).isValid())
    {
        const auto child = parseType();
        if (child.isInvalid())
            return AstNodeRef::invalid();
        auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::ReferenceType>(ref());
        nodePtr->nodePointeeTypeRef = child;
        return nodeRef;
    }

    // Right reference
    if (consumeIf(TokenId::SymAmpersandAmpersand).isValid())
    {
        const auto child = parseType();
        if (child.isInvalid())
            return AstNodeRef::invalid();
        auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::RRefType>(ref());
        nodePtr->nodePointeeTypeRef = child;
        return nodeRef;
    }

    // Value pointer
    if (consumeIf(TokenId::SymAsterisk).isValid())
    {
        const auto child = parseType();
        if (child.isInvalid())
            return AstNodeRef::invalid();
        auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::ValuePointerType>(ref());
        nodePtr->nodePointeeTypeRef = child;
        return nodeRef;
    }

    // Array or slice
    const TokenRef leftBracket = consumeIf(TokenId::SymLeftBracket);
    if (leftBracket.isValid())
    {
        const auto startTok = ref();

        // [*] Block pointer
        if (consumeIf(TokenId::SymAsterisk).isValid())
        {
            if (expectAndConsumeClosing(TokenId::SymRightBracket, leftBracket).isInvalid())
                return AstNodeRef::invalid();
            const auto child = parseType();
            if (child.isInvalid())
                return AstNodeRef::invalid();
            auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::BlockPointerType>(startTok);
            nodePtr->nodePointeeTypeRef = child;
            return nodeRef;
        }

        // [..] Slice
        if (consumeIf(TokenId::SymDotDot).isValid())
        {
            if (expectAndConsumeClosing(TokenId::SymRightBracket, leftBracket).isInvalid())
                return AstNodeRef::invalid();
            const auto child = parseType();
            if (child.isInvalid())
                return AstNodeRef::invalid();
            auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::SliceType>(startTok);
            nodePtr->nodePointeeTypeRef = child;
            return nodeRef;
        }

        // [?] Static array deduced size
        if (consumeIf(TokenId::SymQuestion).isValid())
        {
            if (expectAndConsumeClosing(TokenId::SymRightBracket, leftBracket).isInvalid())
                return AstNodeRef::invalid();
            const auto child = parseType();
            if (child.isInvalid())
                return AstNodeRef::invalid();
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ArrayType>(startTok);
            nodePtr->spanDimensionsRef.setInvalid();
            nodePtr->nodePointeeTypeRef = child;
            return nodeRef;
        }

        // []
        if (is(TokenId::SymRightBracket))
        {
            auto diag = reportError(DiagnosticId::parser_err_expected_array_dim, consume());
            diag.addElement(DiagnosticId::parser_help_empty_array_dim);
            diag.report(*ctx_);
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

        auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::ArrayType>(startTok);
        nodePtr->spanDimensionsRef  = ast_->pushSpan(dimensions.span());
        nodePtr->nodePointeeTypeRef = child;
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
    if (is(TokenId::CompilerCode))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CodeType>(consume());
        nodePtr->nodeTypeRef    = parseSubType();
        return nodeRef;
    }

    // '...'
    if (is(TokenId::SymDotDotDot))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VariadicType>(consume());
        return nodeRef;
    }

    const auto nodeSubType = parseSubType();

    // 'type...'
    if (is(TokenId::SymDotDotDot))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TypedVariadicType>(consume());
        nodePtr->nodeTypeRef    = nodeSubType;
        return nodeRef;
    }

    return nodeSubType;
}

AstNodeRef Parser::parseLambdaParam()
{
    return parseLambdaParam(true);
}

AstNodeRef Parser::parseLambdaType()
{
    EnumFlags  flags    = AstFunctionFlagsE::Zero;
    const auto tokStart = ref();

    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstFunctionFlagsE::Method);
    else
        consumeAssert(TokenId::KwdFunc);

    if (consumeIf(TokenId::SymPipePipe).isValid())
        flags.add(AstFunctionFlagsE::Closure);
    else if (flags.has(AstFunctionFlagsE::Method))
    {
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        flags.add(AstFunctionFlagsE::Closure);
    }

    const SpanRef params = parseCompoundContent(AstNodeId::LambdaType, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = AstNodeRef::invalid();
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdThrow).isValid())
        flags.add(AstFunctionFlagsE::Throwable);

    auto [nodeRef, nodePtr]    = ast_->makeNode<AstNodeId::LambdaType>(tokStart);
    nodePtr->flags()           = flags;
    nodePtr->spanParamsRef     = params;
    nodePtr->nodeReturnTypeRef = returnType;
    return nodeRef;
}

SWC_END_NAMESPACE();
