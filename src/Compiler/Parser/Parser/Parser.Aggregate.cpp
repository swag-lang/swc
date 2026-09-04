#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseImpl()
{
    const TokenRef tokImpl = ref();
    consume();

    // Name
    const AstNodeRef nodeIdent = parseQualifiedIdentifier();
    if (nodeIdent.isInvalid())
        skipTo({TokenId::SymLeftCurly, TokenId::KwdFor});

    // For
    AstNodeRef nodeFor = AstNodeRef::invalid();
    if (consumeIf(TokenId::KwdFor).isValid())
    {
        nodeFor = parseQualifiedIdentifier();
        if (nodeIdent.isInvalid())
            skipTo({TokenId::SymLeftCurly});
    }

    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::Impl>(tokImpl);
    nodePtr->nodeIdentRef    = nodeIdent;
    nodePtr->nodeForRef      = nodeFor;
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseAggregateAccessModifier()
{
    const TokenId  modifierId  = id();
    const TokenRef tokModifier = consume();
    auto [nodeRef, nodePtr]    = ast_->makeNode<AstNodeId::AccessModifier>(tokModifier);
    nodePtr->addFlag(AstAccessModifierFlagsE::Member);

    // 'readonly' is not a level: it rides on the one written before it, and on the default when
    // written alone. It is therefore the one modifier that may follow another, and it comes last
    // so the pair reads the way the access table does.
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
            // A level after 'readonly' is the pair written the wrong way round, not two levels,
            // so name the order instead of reporting a conflict the author did not make.
            if (modifierId == TokenId::KwdReadOnly && !is(TokenId::KwdReadOnly))
                raiseError(DiagnosticId::parser_err_readonly_before_access, ref());
            else
            {
                const bool         repeatsReadOnly = is(TokenId::KwdReadOnly) && tokReadOnly.isValid();
                const DiagnosticId diagId          = id() == modifierId || repeatsReadOnly ? DiagnosticId::parser_err_duplicated_modifier : DiagnosticId::parser_err_duplicate_modifier;
                const Diagnostic   diag            = reportError(diagId, ref());
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
    aggregateAccessModifierRef_           = tokModifier;
    if (tokReadOnly.isValid())
        aggregateReadOnlyRef_ = tokReadOnly;
    nodePtr->nodeWhatRef        = parseAggregateValue();
    aggregateAccessModifierRef_ = savedAccessModifierRef;
    aggregateReadOnlyRef_       = savedReadOnlyRef;
    return nodeRef;
}

AstNodeRef Parser::parseAggregateValue()
{
    switch (id())
    {
        case TokenId::CompilerAssert:
            return parseCompilerDiagnostic();
        case TokenId::CompilerError:
            return parseCompilerDiagnostic();
        case TokenId::CompilerWarning:
            return parseCompilerDiagnostic();
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
            // A storage modifier directly before a field belongs to that field's
            // declaration span. Besides preserving the AST source range, this lets the
            // formatter keep `late field: T` as one declaration. Only a block or access
            // modifier needs the scoped aggregate state below.
            if (!nextIsAny(TokenId::KwdPublic, TokenId::KwdInternal, TokenId::KwdPrivate, TokenId::KwdReadOnly, TokenId::SymLeftCurly))
                return parseVarDecl();

            EnumFlags<AstVarStorageFlagsE> storageFlags = AstVarStorageFlagsE::Zero;
            while (true)
            {
                AstVarStorageFlagsE storageFlag = AstVarStorageFlagsE::Zero;
                switch (id())
                {
                    case TokenId::KwdLate: storageFlag = AstVarStorageFlagsE::Late; break;
                    case TokenId::KwdTls: storageFlag = AstVarStorageFlagsE::Tls; break;
                    case TokenId::KwdGlobal: storageFlag = AstVarStorageFlagsE::Global; break;
                    default: break;
                }

                if (storageFlag == AstVarStorageFlagsE::Zero)
                    break;
                if (storageFlags.has(storageFlag))
                    reportError(DiagnosticId::parser_err_duplicate_storage_modifier, ref()).report(*ctx_);
                storageFlags.add(storageFlag);
                consume();
            }

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

AstNodeRef Parser::parseStructDecl()
{
    return parseAggregateDecl<AstNodeId::StructDecl>();
}

template<AstNodeId ID>
AstNodeRef Parser::parseAggregateDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<ID>(consume());

    // Generic types
    if (is(TokenId::SymLeftParen))
    {
        nodePtr->spanGenericParamsRef = parseCompoundContent(AstNodeId::GenericParamList, TokenId::SymLeftParen);
        if (nodePtr->spanGenericParamsRef.isInvalid())
            skipTo({TokenId::SymLeftCurly});
    }
    else
        nodePtr->spanGenericParamsRef.setInvalid();

    // Name
    nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (nodePtr->tokNameRef.isInvalid())
        skipTo({TokenId::SymLeftCurly});

    // Where
    SmallVector<AstNodeRef> whereRefs;
    while (is(TokenId::KwdWhere))
    {
        const Token*     loopStartToken = curToken_;
        const AstNodeRef whereRef       = parseConstraint();
        if (whereRef.isValid())
            whereRefs.push_back(whereRef);

        if (loopStartToken == curToken_)
            consume();
    }

    nodePtr->spanWhereRef = whereRefs.empty() ? SpanRef::invalid() : ast_->pushSpan(whereRefs.span());

    // Content
    if constexpr (ID == AstNodeId::InterfaceDecl)
        nodePtr->nodeBodyRef = parseCompound<AstNodeId::InterfaceBody>(TokenId::SymLeftCurly);
    else
        nodePtr->nodeBodyRef = parseAggregateBody();

    return nodeRef;
}

AstNodeRef Parser::parseAggregateBody()
{
    const TokenRef                       savedAccessModifierRef    = aggregateAccessModifierRef_;
    const TokenRef                       savedReadOnlyRef          = aggregateReadOnlyRef_;
    const EnumFlags<AstVarStorageFlagsE> savedTopLevelStorageFlags = topLevelStorageFlags_;
    const EnumFlags<AstVarStorageFlagsE> savedStorageFlags         = aggregateStorageFlags_;
    aggregateAccessModifierRef_.setInvalid();
    aggregateReadOnlyRef_.setInvalid();
    topLevelStorageFlags_.clear();
    aggregateStorageFlags_.clear();
    const AstNodeRef result     = parseCompound<AstNodeId::AggregateBody>(TokenId::SymLeftCurly);
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
            return parseCompilerDiagnostic();
        case TokenId::CompilerError:
            return parseCompilerDiagnostic();
        case TokenId::CompilerWarning:
            return parseCompilerDiagnostic();
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
