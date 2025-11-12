#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseImpl()
{
    if (nextIs(TokenId::KwdEnum))
        return parseImplEnum();

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
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Impl>();
        nodePtr->nodeIdent      = nodeIdent;
        nodePtr->spanChildren   = parseCompoundContent(AstNodeId::Impl, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplFor>();
    nodePtr->nodeIdent      = nodeIdent;
    nodePtr->nodeFor        = nodeFor;
    nodePtr->spanChildren   = parseCompoundContent(AstNodeId::ImplFor, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseAggregateAccessModifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AccessModifier>();
    nodePtr->tokAccess      = consume();
    nodePtr->nodeWhat       = parseAggregateValue();
    return nodeRef;
}

AstNodeRef Parser::parseAggregateValue()
{
    switch (id())
    {
        case TokenId::SymAttrStart:
            return parseAttributeList(AstNodeId::AggregateBody);

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
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingVarDecl>();
            consume();
            nodePtr->nodeVar = parseVarDecl();
            return nodeRef;
        }

        default:
            return parseVarDecl();
    }
}

AstNodeRef Parser::parseUnionDecl()
{
    return parseAggregateDecl(AstNodeId::UnionDecl);
}

AstNodeRef Parser::parseStructDecl()
{
    return parseAggregateDecl(AstNodeId::StructDecl);
}

AstNodeRef Parser::parseAggregateDecl(AstNodeId nodeId)
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstAggregateDecl>(nodeId);
    consume();

    // Generic types
    if (is(TokenId::SymLeftParen))
    {
        nodePtr->spanGenericParams = parseCompoundContent(AstNodeId::GenericParamList, TokenId::SymLeftParen);
        if (nodePtr->spanGenericParams.isInvalid())
            skipTo({TokenId::SymLeftCurly});
    }

    // Name
    nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (nodePtr->tokName.isInvalid())
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

    nodePtr->spanWhere = whereRefs.empty() ? SpanRef::invalid() : ast_->store_.push_span(whereRefs.span());

    // Content
    nodePtr->nodeBody = parseAggregateBody();

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
        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFuncDecl();

        case TokenId::KwdConst:
            return parseVarDecl();

        case TokenId::SymAttrStart:
            return parseAttributeList(AstNodeId::InterfaceBody);

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseInterfaceDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::InterfaceDecl>();
    consume();
    nodePtr->tokName  = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    nodePtr->nodeBody = parseCompound<AstNodeId::InterfaceBody>(TokenId::SymLeftCurly);
    return nodeRef;
}

SWC_END_NAMESPACE()
