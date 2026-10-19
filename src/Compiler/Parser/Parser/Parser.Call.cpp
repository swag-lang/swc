#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseAttributeValue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>(ref());
    const PushContextFlags ctx(this, ParserContextFlagsE::InAttribute);
    const AstNodeRef       nodeIdentRef = parseQualifiedIdentifier();
    if (is(TokenId::SymLeftParen))
    {
        nodePtr->nodeCallRef = parseFunctionArguments(nodeIdentRef);
        return nodeRef;
    }

    markCallCalleeNode(nodeIdentRef);

    auto [callRef, callPtr] = ast_->makeNode<AstNodeId::CallExpr>(ref());
    callPtr->nodeExprRef    = nodeIdentRef;
    if (hasContextFlag(ParserContextFlagsE::InAttribute))
        callPtr->addFlag(AstCallExprFlagsE::AttributeContext);
    callPtr->spanChildrenRef = SpanRef::invalid();
    nodePtr->nodeCallRef     = callRef;
    return nodeRef;
}

// Consume the opening '(' and its arguments, leaving ')' for the caller to close.
TokenRef Parser::parseParenArgumentExpressions(SmallVector<AstNodeRef>& outArgs)
{
    const TokenRef openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!outArgs.empty() && !prepareNextArgument())
            break;

        {
            const PushContextFlags ctxFlags(this, ParserContextFlagsE::InCallArgument);
            outArgs.push_back(parseExpression());
        }
    }

    return openRef;
}

AstNodeRef Parser::parseIntrinsicCall(uint32_t numParams)
{
    const TokenRef tokRef = consume();

    SmallVector<AstNodeRef> nodeArgs;
    const TokenRef          openRef = parseParenArgumentExpressions(nodeArgs);

    reportArgumentCountForList(tokRef, nodeArgs, numParams, numParams, false);

    expectAndConsumeClosing(TokenId::SymRightParen, openRef, {TokenId::SymRightCurly, TokenId::SymRightBracket});

    const TokenId tokId = tokRef.isValid() ? ast_->srcView().token(tokRef).id : TokenId::Invalid;
    if (tokId == TokenId::IntrinsicCountOf)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CountOfExpr>(tokRef);
        nodePtr->nodeExprRef    = nodeArgs.empty() ? AstNodeRef::invalid() : nodeArgs[0];
        return nodeRef;
    }

    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::IntrinsicCall>(tokRef);
    nodePtr->intrinsicId     = tokId;
    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallConstantExpr()
{
    const TokenRef tokRef   = consume();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallExpr>(tokRef);
    nodePtr->intrinsicId    = ast_->srcView().token(tokRef).id;

    auto [idRef, idPtr]  = ast_->makeNode<AstNodeId::Identifier>(tokRef);
    nodePtr->nodeExprRef = idRef;
    idPtr->addFlag(AstIdentifierFlagsE::CallCallee);
    nodePtr->spanChildrenRef.setInvalid();
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallExpr(uint32_t numParams)
{
    const TokenRef tokRef   = consume();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallExpr>(tokRef);
    nodePtr->intrinsicId    = ast_->srcView().token(tokRef).id;

    auto [idRef, idPtr]  = ast_->makeNode<AstNodeId::Identifier>(tokRef);
    nodePtr->nodeExprRef = idRef;
    idPtr->addFlag(AstIdentifierFlagsE::CallCallee);

    SmallVector<AstNodeRef> nodeArgs;
    const TokenRef          openRef = parseParenArgumentExpressions(nodeArgs);

    if (numParams != UINT32_MAX)
        reportArgumentCountForList(tokRef, nodeArgs, numParams, numParams, false);
    else
    {
        if (nodeArgs.empty())
        {
            const Diagnostic diag = reportArgumentCountError(DiagnosticId::parser_err_too_few_arguments, tokRef, ref(), 1, static_cast<uint32_t>(nodeArgs.size()), true);
            diag.report(*ctx_);
        }
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef, {TokenId::SymRightCurly, TokenId::SymRightBracket});
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
    const AstNodeRef nodeRef = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    AstAttributeList* nodePtr = ast_->node<AstNodeId::AttributeList>(nodeRef);
    if (is(TokenId::SymLeftCurly) && !(ID == AstNodeId::EmbeddedBlock && isDestructuringAssignmentAhead()))
        nodePtr->nodeBodyRef = parseCompound<ID>(TokenId::SymLeftCurly);
    else
        nodePtr->nodeBodyRef = parseCompoundValue(ID);
    return nodeRef;
}

SWC_END_NAMESPACE();
