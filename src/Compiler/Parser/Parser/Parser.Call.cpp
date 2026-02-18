#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseAttributeValue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>(ref());
    PushContextFlags ctx(this, ParserContextFlagsE::InAttribute);
    const AstNodeRef nodeIdentRef = parseQualifiedIdentifier();
    if (is(TokenId::SymLeftParen))
    {
        nodePtr->nodeCallRef = parseFunctionArguments(nodeIdentRef);
        return nodeRef;
    }

    AstNode& calleeNode = ast_->node(nodeIdentRef);
    switch (calleeNode.id())
    {
        case AstNodeId::Identifier:
            calleeNode.cast<AstIdentifier>()->addFlag(AstIdentifierFlagsE::CallCallee);
            break;
        case AstNodeId::MemberAccessExpr:
            calleeNode.cast<AstMemberAccessExpr>()->addFlag(AstMemberAccessExprFlagsE::CallCallee);
            break;
        case AstNodeId::AutoMemberAccessExpr:
            calleeNode.cast<AstAutoMemberAccessExpr>()->addFlag(AstAutoMemberAccessExprFlagsE::CallCallee);
            break;
        default:
            break;
    }

    auto [callRef, callPtr] = ast_->makeNode<AstNodeId::CallExpr>(ref());
    callPtr->nodeExprRef    = nodeIdentRef;
    if (hasContextFlag(ParserContextFlagsE::InAttribute))
        callPtr->addFlag(AstCallExprFlagsE::AttributeContext);
    callPtr->spanChildrenRef = SpanRef::invalid();
    nodePtr->nodeCallRef     = callRef;
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCall(uint32_t numParams)
{
    const TokenRef tokRef = consume();

    const TokenRef              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        {
            PushContextFlags ctxFlags(this, ParserContextFlagsE::InCallArgument);
            nodeArgs.push_back(parseExpression());
        }
    }

    if (nodeArgs.size() < numParams)
    {
        auto diag = reportError(DiagnosticId::parser_err_too_few_arguments, ref());
        diag.addArgument(Diagnostic::ARG_COUNT, numParams);
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }
    else if (nodeArgs.size() > numParams)
    {
        auto diag = reportError(DiagnosticId::parser_err_too_many_arguments, nodeArgs[numParams]);
        diag.addArgument(Diagnostic::ARG_COUNT, numParams);
        diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
        diag.report(*ctx_);
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    const TokenId tokId = tokRef.isValid() ? ast_->srcView().token(tokRef).id : TokenId::Invalid;
    if (tokId == TokenId::IntrinsicCountOf)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CountOfExpr>(tokRef);
        nodePtr->nodeExprRef    = nodeArgs.empty() ? AstNodeRef::invalid() : nodeArgs[0];
        return nodeRef;
    }

    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::IntrinsicCall>(tokRef);
    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallConstantExpr()
{
    const TokenRef tokRef       = consume();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallExpr>(tokRef);
    auto [idRef, idPtr]     = ast_->makeNode<AstNodeId::Identifier>(tokRef);
    nodePtr->nodeExprRef    = idRef;
    idPtr->addFlag(AstIdentifierFlagsE::CallCallee);
    nodePtr->spanChildrenRef.setInvalid();
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallExpr(uint32_t numParams)
{
    const TokenRef tokRef       = consume();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallExpr>(tokRef);
    auto [idRef, idPtr]     = ast_->makeNode<AstNodeId::Identifier>(tokRef);
    nodePtr->nodeExprRef    = idRef;
    idPtr->addFlag(AstIdentifierFlagsE::CallCallee);

    const TokenRef              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        {
            PushContextFlags ctxFlags(this, ParserContextFlagsE::InCallArgument);
            nodeArgs.push_back(parseExpression());
        }
    }

    if (numParams != UINT32_MAX)
    {
        if (nodeArgs.size() < numParams)
        {
            auto diag = reportError(DiagnosticId::parser_err_too_few_arguments, ref());
            diag.addArgument(Diagnostic::ARG_COUNT, numParams);
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
            diag.report(*ctx_);
        }
        else if (nodeArgs.size() > numParams)
        {
            auto diag = reportError(DiagnosticId::parser_err_too_many_arguments, nodeArgs[numParams]);
            diag.addArgument(Diagnostic::ARG_COUNT, numParams);
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
            diag.report(*ctx_);
        }
    }
    else
    {
        if (nodeArgs.empty())
        {
            auto diag = reportError(DiagnosticId::parser_err_too_few_arguments, ref());
            diag.addArgument(Diagnostic::ARG_COUNT, numParams);
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(nodeArgs.size()));
            diag.report(*ctx_);
        }
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    return nodeRef;
}

template AstNodeRef Parser::parseAttributeList<AstNodeId::AggregateBody>();
template AstNodeRef Parser::parseAttributeList<AstNodeId::InterfaceBody>();
template AstNodeRef Parser::parseAttributeList<AstNodeId::EnumBody>();
template AstNodeRef Parser::parseAttributeList<AstNodeId::TopLevelBlock>();
template AstNodeRef Parser::parseAttributeList<AstNodeId::EmbeddedBlock>();

template<AstNodeId ID>
AstNodeRef Parser::parseAttributeList()
{
    const auto nodeRef = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    const auto nodePtr = ast_->node<AstNodeId::AttributeList>(nodeRef);
    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBodyRef = parseCompound<ID>(TokenId::SymLeftCurly);
    else
        nodePtr->nodeBodyRef = parseCompoundValue(ID);
    return nodeRef;
}

SWC_END_NAMESPACE();
