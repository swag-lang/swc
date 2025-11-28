#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldBinaryExpr(Sema& sema, TokenId op, AstNodeRef leftNodeRef, AstNodeRef rightNodeRef)
    {
        const auto&    ctx       = sema.ctx();
        auto&          constMgr  = sema.constMgr();
        const AstNode& leftNode  = sema.node(leftNodeRef);
        const AstNode& rightNode = sema.node(rightNodeRef);
        const auto&    leftCst   = leftNode.getSemaConstant(ctx);
        const auto&    rightCst  = rightNode.getSemaConstant(ctx);

        switch (op)
        {
            case TokenId::SymPlusPlus:
            {
                Utf8 result = leftCst.toString();
                result += rightCst.toString();
                return constMgr.addConstant(ctx, ConstantValue::makeString(ctx, result));
            }

            default:
                break;
        }

        return ConstantRef::invalid();
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(Sema& sema)
{
    const auto&    tok       = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeLeft  = sema.node(nodeLeftRef);
    const AstNode& nodeRight = sema.node(nodeRightRef);

    if (nodeLeft.isSemaConstant() && nodeRight.isSemaConstant())
    {
        const auto cst = constantFoldBinaryExpr(sema, tok.id, nodeLeftRef, nodeRightRef);
        if (cst.isValid())
        {
            setSemaConstant(cst);
            return AstVisitStepResult::Continue;
        }
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

namespace
{
    ConstantRef constantFoldRelationalExpr(Sema& sema, TokenId op, AstNodeRef leftNodeRef, AstNodeRef rightNodeRef)
    {
        const auto&    ctx       = sema.ctx();
        auto&          constMgr  = sema.constMgr();
        const AstNode& leftNode  = sema.node(leftNodeRef);
        const AstNode& rightNode = sema.node(rightNodeRef);
        const auto&    leftCst   = leftNode.getSemaConstant(ctx);
        const auto&    rightCst  = rightNode.getSemaConstant(ctx);

        switch (op)
        {
            case TokenId::SymEqualEqual:
            {
                const bool result = leftCst == rightCst;
                return constMgr.addConstant(ctx, ConstantValue::makeBool(ctx, result));
            }

            default:
                break;
        }

        return ConstantRef::invalid();
    }
}

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema)
{
    const auto&    tok       = sema.token(srcViewRef(), tokRef());
    const AstNode& nodeLeft  = sema.node(nodeLeftRef);
    const AstNode& nodeRight = sema.node(nodeRightRef);

    if (nodeLeft.isSemaConstant() && nodeRight.isSemaConstant())
    {
        const auto cst = constantFoldRelationalExpr(sema, tok.id, nodeLeftRef, nodeRightRef);
        if (cst.isValid())
        {
            setSemaConstant(cst);
            return AstVisitStepResult::Continue;
        }
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
