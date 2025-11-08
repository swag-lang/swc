#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseImpl()
{
    if (nextIs(TokenId::KwdEnum))
        return parseImplEnum();

    consume();

    // Name
    const AstNodeRef nodeIdent = parseQualifiedIdentifier();
    if (invalid(nodeIdent))
        skipTo({TokenId::SymLeftCurly, TokenId::KwdFor});

    // For
    AstNodeRef nodeFor = INVALID_REF;
    if (consumeIf(TokenId::KwdFor))
    {
        nodeFor = parseQualifiedIdentifier();
        if (invalid(nodeIdent))
            skipTo({TokenId::SymLeftCurly});
    }

    if (invalid(nodeFor))
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
        return parseCompilerAttribute(AstNodeId::AggregateBody);

    case TokenId::KwdStruct:
        return parseStructDecl();
    case TokenId::KwdUnion:
        return parseUnionDecl();
    case TokenId::KwdEnum:
        return parseEnumDecl();

    case TokenId::SymLeftCurly:
        return parseCompound(AstNodeId::AggregateBody, TokenId::SymLeftCurly);

    case TokenId::CompilerAst:
    case TokenId::CompilerRun:
        return parseCompilerFunc();

    case TokenId::KwdVar:
        raiseError(DiagnosticId::parser_err_var_struct, ref());
        consume();
        return parseVarDecl();

    case TokenId::KwdPrivate:
        return parseAggregateAccessModifier();

    case TokenId::KwdConst:
    case TokenId::KwdAlias:
        // @skip
        skipTo({TokenId::SymRightCurly, TokenId::SymComma}, SkipUntilFlags::EolBefore);
        return INVALID_REF;

    case TokenId::Identifier:
        if (nextIs(TokenId::SymLeftParen) || nextIs(TokenId::SymDot))
            return parseTopLevelStmt();
        return parseVarDecl();

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
        if (invalid(nodePtr->spanGenericParams))
            skipTo({TokenId::SymLeftCurly});
    }

    // Name
    nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (invalid(nodePtr->tokName))
        skipTo({TokenId::SymLeftCurly});

    // Where
    SmallVector<AstNodeRef> whereRefs;
    while (is(TokenId::KwdWhere))
    {
        const auto loopStartToken = curToken_;
        auto       whereRef       = parseConstraint();
        if (valid(whereRef))
            whereRefs.push_back(whereRef);

        if (loopStartToken == curToken_)
            consume();
    }

    nodePtr->spanWhere = whereRefs.empty() ? INVALID_REF : ast_->store_.push_span(whereRefs.span());

    // Content
    nodePtr->nodeBody = parseAggregateBody();

    return nodeRef;
}

AstNodeRef Parser::parseAggregateBody()
{
    return parseCompound(AstNodeId::AggregateBody, TokenId::SymLeftCurly);
}

SWC_END_NAMESPACE()
