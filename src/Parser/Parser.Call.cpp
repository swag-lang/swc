#include "pch.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseAttributeValue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Attribute>(ref());
    nodePtr->nodeIdentRef   = parseQualifiedIdentifier();
    if (is(TokenId::SymLeftParen))
        nodePtr->nodeArgsRef = parseCompound<AstNodeId::NamedArgumentList>(TokenId::SymLeftParen);
    else
        nodePtr->nodeArgsRef.setInvalid();
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCall()
{
    uint32_t numParams = 0;
    switch (id())
    {
        case TokenId::IntrinsicBcBreakpoint:
        case TokenId::IntrinsicGetContext:
        case TokenId::IntrinsicDbgAlloc:
        case TokenId::IntrinsicSysAlloc:
            numParams = 0;
            break;
        case TokenId::IntrinsicAssert:
        case TokenId::IntrinsicSetContext:
        case TokenId::IntrinsicKindOf:
        case TokenId::IntrinsicCountOf:
        case TokenId::IntrinsicDataOf:
        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicMakeCallback:
        case TokenId::IntrinsicAbs:
        case TokenId::IntrinsicSqrt:
        case TokenId::IntrinsicSin:
        case TokenId::IntrinsicCos:
        case TokenId::IntrinsicTan:
        case TokenId::IntrinsicSinh:
        case TokenId::IntrinsicCosh:
        case TokenId::IntrinsicTanh:
        case TokenId::IntrinsicASin:
        case TokenId::IntrinsicACos:
        case TokenId::IntrinsicATan:
        case TokenId::IntrinsicLog:
        case TokenId::IntrinsicLog2:
        case TokenId::IntrinsicLog10:
        case TokenId::IntrinsicFloor:
        case TokenId::IntrinsicCeil:
        case TokenId::IntrinsicTrunc:
        case TokenId::IntrinsicRound:
        case TokenId::IntrinsicExp:
        case TokenId::IntrinsicExp2:
        case TokenId::IntrinsicByteSwap:
        case TokenId::IntrinsicBitCountNz:
        case TokenId::IntrinsicBitCountTz:
        case TokenId::IntrinsicBitCountLz:
            numParams = 1;
            break;
        case TokenId::IntrinsicMakeAny:
        case TokenId::IntrinsicMakeSlice:
        case TokenId::IntrinsicMakeString:
        case TokenId::IntrinsicCVaArg:
        case TokenId::IntrinsicRealloc:
        case TokenId::IntrinsicStringCmp:
        case TokenId::IntrinsicIs:
        case TokenId::IntrinsicTableOf:
        case TokenId::IntrinsicMin:
        case TokenId::IntrinsicMax:
        case TokenId::IntrinsicRol:
        case TokenId::IntrinsicRor:
        case TokenId::IntrinsicPow:
        case TokenId::IntrinsicATan2:
        case TokenId::IntrinsicAtomicXchg:
        case TokenId::IntrinsicAtomicXor:
        case TokenId::IntrinsicAtomicOr:
        case TokenId::IntrinsicAtomicAnd:
        case TokenId::IntrinsicAtomicAdd:
        case TokenId::IntrinsicCompilerError:
        case TokenId::IntrinsicCompilerWarning:
        case TokenId::IntrinsicPanic:
            numParams = 2;
            break;
        case TokenId::IntrinsicMakeInterface:
        case TokenId::IntrinsicAs:
        case TokenId::CompilerGetTag:
        case TokenId::IntrinsicAtomicCmpXchg:
        case TokenId::IntrinsicTypeCmp:
        case TokenId::IntrinsicMulAdd:
            numParams = 3;
            break;
        default:
            SWC_UNREACHABLE();
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCall>(consume());

    const auto              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    for (uint32_t i = 0; i < numParams; i++)
    {
        if (i != 0)
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
        }

        nodeArgs.push_back(parseExpression());
    }
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallVariadic()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicCallVariadic>(consume());

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    SmallVector<AstNodeRef> nodeArgs;
    while (isNot(TokenId::SymRightParen) && isNot(TokenId::EndOfFile))
    {
        if (!nodeArgs.empty())
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
            if (is(TokenId::SymRightParen))
                break;
        }

        nodeArgs.push_back(parseExpression());
    }

    nodePtr->spanChildrenRef = ast_->pushSpan(nodeArgs.span());
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicCallExpr()
{
    uint32_t numParams = 0;
    switch (id())
    {
        case TokenId::IntrinsicStrLen:
        case TokenId::IntrinsicAlloc:
        case TokenId::IntrinsicFree:
            numParams = 1;
            break;

        case TokenId::IntrinsicStrCmp:
            numParams = 2;
            break;

        case TokenId::IntrinsicMemCpy:
        case TokenId::IntrinsicMemMove:
        case TokenId::IntrinsicMemSet:
        case TokenId::IntrinsicMemCmp:
            numParams = 3;
            break;

        default:
            SWC_UNREACHABLE();
    }

    const auto tokRef       = consume();
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CallExpr>(tokRef);
    auto [idRef, idPtr]     = ast_->makeNode<AstNodeId::Identifier>(tokRef);
    nodePtr->nodeExprRef    = idRef;

    const auto              openRef = ref();
    SmallVector<AstNodeRef> nodeArgs;
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    for (uint32_t i = 0; i < numParams; i++)
    {
        if (i != 0)
        {
            if (expectAndConsume(TokenId::SymComma, DiagnosticId::parser_err_expected_token).isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymRightParen});
        }

        nodeArgs.push_back(parseExpression());
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
