#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseImpl()
{
    if (nextIs(TokenId::KwdEnum))
        return parseImplEnum();

    const auto tokImpl = ref();
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

    if (nodeFor.isInvalid())
    {
        auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::Impl>(tokImpl);
        nodePtr->nodeIdentRef    = nodeIdent;
        nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::ImplFor>(tokImpl);
    nodePtr->nodeIdentRef    = nodeIdent;
    nodePtr->nodeForRef      = nodeFor;
    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseAggregateAccessModifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AccessModifier>(consume());
    nodePtr->nodeWhatRef    = parseAggregateValue();
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
        case TokenId::CompilerIf:
            return parseCompilerIf<AstNodeId::AggregateBody>();

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

        case TokenId::KwdPrivate:
            return parseAggregateAccessModifier();

        case TokenId::Identifier:
            if (nextIs(TokenId::SymLeftParen) || nextIs(TokenId::SymDot))
                return parseTopLevelStmt();
            return parseVarDecl();

        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::KwdUsing:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingMemberDecl>(consume());
            nodePtr->nodeVarRef     = parseVarDecl();
            return nodeRef;
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
        const auto loopStartToken = curToken_;
        auto       whereRef       = parseConstraint();
        if (whereRef.isValid())
            whereRefs.push_back(whereRef);

        if (loopStartToken == curToken_)
            consume();
    }

    nodePtr->spanWhereRef = whereRefs.empty() ? SpanRef::invalid() : ast_->pushSpan(whereRefs.span());

    // Content
    nodePtr->nodeBodyRef = parseAggregateBody();

    return nodeRef;
}

AstNodeRef Parser::parseAggregateBody()
{
    return parseCompound<AstNodeId::AggregateBody>(TokenId::SymLeftCurly);
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
        case TokenId::CompilerIf:
            return parseCompilerIf<AstNodeId::InterfaceBody>();

        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFunctionDecl();

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
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::InterfaceDecl>(consume());
    nodePtr->tokNameRef     = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    nodePtr->nodeBodyRef    = parseCompound<AstNodeId::InterfaceBody>(TokenId::SymLeftCurly);
    return nodeRef;
}

SWC_END_NAMESPACE();
