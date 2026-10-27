#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseImpl()
{
    const TokenRef tokImpl = ref();
    consume();

    const AstNodeRef nodeIdent = parseQualifiedIdentifier();
    if (nodeIdent.isInvalid())
        skipTo({TokenId::SymLeftCurly, TokenId::KwdFor});

    AstNodeRef nodeFor = AstNodeRef::invalid();
    if (consumeIf(TokenId::KwdFor).isValid())
    {
        nodeFor = parseQualifiedIdentifier();
        if (nodeIdent.isInvalid())
            skipTo({TokenId::SymLeftCurly});
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Impl>(tokImpl);

    nodePtr->nodeIdentRef    = nodeIdent;
    nodePtr->nodeForRef      = nodeFor;
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);

    return nodeRef;
}

AstNodeRef Parser::parseAggregateAccessModifier()
{
    const TokenId  modifierId  = id();
    const TokenRef tokModifier = consume();

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AccessModifier>(tokModifier);

    nodePtr->addFlag(AstAccessModifierFlagsE::Member);

    // readonly restricts writes without changing the access level. Accept it
    // alone or after one level, and require it to be last.
    TokenRef tokReadOnly = TokenRef::invalid();
    if (modifierId == TokenId::KwdReadOnly)
    {
        nodePtr->addFlag(AstAccessModifierFlagsE::ReadOnly);
        tokReadOnly = tokModifier;
    }
    else if (is(TokenId::KwdReadOnly))
    {
        nodePtr->addFlag(AstAccessModifierFlagsE::ReadOnly);
        tokReadOnly = consume();
    }

    if (modifierId != TokenId::KwdReadOnly && aggregateAccessModifierRef_.isValid())
    {
        const Diagnostic diag = reportError(DiagnosticId::parser_err_nested_member_access, tokModifier);
        diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, aggregateAccessModifierRef_), DiagnosticId::parser_note_other_def, DiagnosticSeverity::Note);
        diag.report(*ctx_);
    }
    else if (tokReadOnly.isValid() && aggregateReadOnlyRef_.isValid())
    {
        const Diagnostic diag = reportError(DiagnosticId::parser_err_duplicated_modifier, tokReadOnly);
        diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, aggregateReadOnlyRef_), DiagnosticId::parser_note_other_def, DiagnosticSeverity::Note);
        diag.report(*ctx_);
    }

    switch (id())
    {
        case TokenId::KwdPublic:
        case TokenId::KwdInternal:
        case TokenId::KwdPrivate:
        case TokenId::KwdReadOnly:
        {
            // Diagnose reversed readonly/access order separately from conflicting levels.
            if (modifierId == TokenId::KwdReadOnly && !is(TokenId::KwdReadOnly))
                raiseError(DiagnosticId::parser_err_readonly_before_access, ref());
            else
            {
                const bool         repeatsReadOnly = is(TokenId::KwdReadOnly) && tokReadOnly.isValid();
                const DiagnosticId diagId          = id() == modifierId || repeatsReadOnly ? DiagnosticId::parser_err_duplicated_modifier : DiagnosticId::parser_err_duplicate_modifier;

                const Diagnostic diag = reportError(diagId, ref());
                diag.last().addSpan(ast_->srcView().tokenCodeRange(*ctx_, tokModifier), DiagnosticId::parser_note_other_def, DiagnosticSeverity::Note);
                diag.report(*ctx_);
            }

            skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
            return AstNodeRef::invalid();
        }

        default:
            break;
    }

    const TokenRef savedAccessModifierRef = aggregateAccessModifierRef_;
    const TokenRef savedReadOnlyRef       = aggregateReadOnlyRef_;

    aggregateAccessModifierRef_ = tokModifier;
    if (tokReadOnly.isValid())
        aggregateReadOnlyRef_ = tokReadOnly;

    nodePtr->nodeWhatRef = parseAggregateValue();

    aggregateAccessModifierRef_ = savedAccessModifierRef;
    aggregateReadOnlyRef_       = savedReadOnlyRef;

    return nodeRef;
}

AstNodeRef Parser::parseAggregateValue()
{
    switch (id())
    {
        case TokenId::CompilerAssert:
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
        case TokenId::CompilerPrint:
            return parseCompilerDiagnostic();

        case TokenId::CompilerStatic:
            return parseCompilerStatic<AstNodeId::AggregateBody>();

        case TokenId::SymAttrStart:
            return parseAttributeList<AstNodeId::AggregateBody>();

        case TokenId::KwdStruct:
            return parseStructDecl();

        case TokenId::KwdUnion:
            return parseUnionDecl();

        case TokenId::KwdEnum:
            return parseEnumDecl();

        case TokenId::KwdCase:
            return parseTaggedUnionCase();

        case TokenId::SymLeftCurly:
            return parseCompound<AstNodeId::AggregateBody>(TokenId::SymLeftCurly);

        case TokenId::CompilerAst:
        case TokenId::CompilerRun:
            return parseCompilerFunc();

        case TokenId::KwdVar:
            raiseError(DiagnosticId::parser_err_var_struct, ref());
            return parseVarDecl();

        case TokenId::KwdConst:
            return parseVarDecl();

        case TokenId::KwdLate:
        case TokenId::KwdTls:
        case TokenId::KwdGlobal:
        {
            // A field's storage modifier belongs to its declaration span, including
            // for formatting. Only blocks and access modifiers need scoped aggregate state.
            if (!nextIsAny(TokenId::KwdPublic, TokenId::KwdInternal, TokenId::KwdPrivate, TokenId::KwdReadOnly, TokenId::SymLeftCurly))
                return parseVarDecl();

            const EnumFlags<AstVarStorageFlagsE> storageFlags = parseStorageModifiers();

            const EnumFlags<AstVarStorageFlagsE> savedStorageFlags = aggregateStorageFlags_;

            aggregateStorageFlags_.add(storageFlags);

            AstNodeRef nodeRef;
            if (isAny(TokenId::KwdPublic, TokenId::KwdInternal, TokenId::KwdPrivate, TokenId::KwdReadOnly))
                nodeRef = parseAggregateAccessModifier();
            else if (is(TokenId::SymLeftCurly))
                nodeRef = parseCompound<AstNodeId::AggregateBody>(TokenId::SymLeftCurly);
            else
                nodeRef = parseVarDecl();

            aggregateStorageFlags_ = savedStorageFlags;

            return nodeRef;
        }

        case TokenId::KwdPublic:
        case TokenId::KwdInternal:
        case TokenId::KwdPrivate:
        case TokenId::KwdReadOnly:
            return parseAggregateAccessModifier();

        case TokenId::Identifier:
            if (nextIs(TokenId::SymLeftParen) || nextIs(TokenId::SymDot))
                return parseTopLevelStmt();

            return parseVarDecl();

        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::KwdUsing:
        {
            consume();

            const PushContextFlags _{this, ParserContextFlagsE::InUsingMemberDecl};
            return parseVarDecl();
        }

        default:
            return parseVarDecl();
    }
}

AstNodeRef Parser::parseUnionDecl()
{
    return parseAggregateDecl<AstNodeId::UnionDecl>();
}

// The parenthesized enum after 'union' (or after a union's name) names its tag. Sema decides
// whether it is one; the parser only records the type.
AstNodeRef Parser::parseTaggedUnionTag()
{
    if (isNot(TokenId::SymLeftParen))
        return AstNodeRef::invalid();

    const TokenRef   openRef = consume();
    const AstNodeRef typeRef = parseType();
    if (expectAndConsumeClosing(TokenId::SymRightParen, openRef).isInvalid())
        return AstNodeRef::invalid();

    return typeRef;
}

// 'case .A, .B: member: T'. The values are ordinary expressions: sema resolves them against the
// union's tag and rejects a label outside a tagged union.
AstNodeRef Parser::parseTaggedUnionCase()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TaggedUnionCase>(consume());

    SmallVector<AstNodeRef> values;
    values.push_back(parseExpression());
    while (consumeIf(TokenId::SymComma).isValid())
        values.push_back(parseExpression());

    nodePtr->spanValuesRef = ast_->pushSpan(values.span());
    expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeMemberRef = parseVarDecl();

    return nodeRef;
}

AstNodeRef Parser::parseStructDecl()
{
    return parseAggregateDecl<AstNodeId::StructDecl>();
}

template<AstNodeId ID>
AstNodeRef Parser::parseAggregateDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<ID>(consume());

    if (is(TokenId::SymLeftParen))
    {
        nodePtr->spanGenericParamsRef = parseCompoundContent(AstNodeId::GenericParamList, TokenId::SymLeftParen);
        if (nodePtr->spanGenericParamsRef.isInvalid())
            skipTo({TokenId::SymLeftCurly});
    }
    else
        nodePtr->spanGenericParamsRef.setInvalid();

    nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (nodePtr->tokNameRef.isInvalid())
        skipTo({TokenId::SymLeftCurly});

    if constexpr (ID == AstNodeId::UnionDecl)
        nodePtr->nodeTagTypeRef = parseTaggedUnionTag();

    if constexpr (ID == AstNodeId::InterfaceDecl)
    {
        if (consumeIf(TokenId::KwdIs).isValid())
            nodePtr->nodeBaseRef = parseType();
    }

    SmallVector<AstNodeRef> whereRefs;
    parseConstraintList(whereRefs);

    nodePtr->spanWhereRef = whereRefs.empty() ? SpanRef::invalid() : ast_->pushSpan(whereRefs.span());

    if constexpr (ID == AstNodeId::InterfaceDecl)
        nodePtr->nodeBodyRef = parseCompound<AstNodeId::InterfaceBody>(TokenId::SymLeftCurly);
    else
        nodePtr->nodeBodyRef = parseAggregateBody();

    return nodeRef;
}

AstNodeRef Parser::parseAggregateBody()
{
    const TokenRef savedAccessModifierRef = aggregateAccessModifierRef_;
    const TokenRef savedReadOnlyRef       = aggregateReadOnlyRef_;

    const EnumFlags<AstVarStorageFlagsE> savedTopLevelStorageFlags = topLevelStorageFlags_;
    const EnumFlags<AstVarStorageFlagsE> savedStorageFlags         = aggregateStorageFlags_;

    aggregateAccessModifierRef_.setInvalid();
    aggregateReadOnlyRef_.setInvalid();
    topLevelStorageFlags_.clear();
    aggregateStorageFlags_.clear();

    const AstNodeRef result = parseCompound<AstNodeId::AggregateBody>(TokenId::SymLeftCurly);

    aggregateAccessModifierRef_ = savedAccessModifierRef;
    aggregateReadOnlyRef_       = savedReadOnlyRef;
    topLevelStorageFlags_       = savedTopLevelStorageFlags;
    aggregateStorageFlags_      = savedStorageFlags;

    return result;
}

AstNodeRef Parser::parseInterfaceValue()
{
    switch (id())
    {
        case TokenId::CompilerAssert:
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
        case TokenId::CompilerPrint:
            return parseCompilerDiagnostic();

        case TokenId::CompilerStatic:
            return parseCompilerStatic<AstNodeId::InterfaceBody>();

        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFunctionDecl(true);

        case TokenId::KwdConst:
            return parseVarDecl();

        case TokenId::SymAttrStart:
            return parseAttributeList<AstNodeId::InterfaceBody>();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseInterfaceDecl()
{
    return parseAggregateDecl<AstNodeId::InterfaceDecl>();
}

SWC_END_NAMESPACE();
