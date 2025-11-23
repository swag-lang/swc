#include "pch.h"
#include "ConstantManager.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldBinaryExpr(SemaJob& job, TokenId op, AstNodeRef left, AstNodeRef right)
    {
        const auto& ctx      = job.ctx();
        auto&       constMgr = job.constMgr();
        const auto  leftPtr  = job.node(left);
        const auto  rightPtr = job.node(right);
        const auto& leftCst  = leftPtr->getConstant(ctx);
        const auto& rightCst = rightPtr->getConstant(ctx);

        switch (op)
        {
            case TokenId::SymPlusPlus:
            {
                Utf8 result = leftCst.toString();
                result += rightCst.toString();
                return constMgr.addConstant(ApValue::makeString(ctx, result));
            }

            default:
                break;
        }

        return ConstantRef::invalid();
    }

    ConstantRef constantFoldRelationalExpr(SemaJob& job, TokenId op, AstNodeRef left, AstNodeRef right)
    {
        const auto& ctx      = job.ctx();
        auto&       constMgr = job.constMgr();
        const auto  leftPtr  = job.node(left);
        const auto  rightPtr = job.node(right);
        const auto& leftCst  = leftPtr->getConstant(ctx);
        const auto& rightCst = rightPtr->getConstant(ctx);

        switch (op)
        {
            case TokenId::SymEqualEqual:
            {
                const bool result = leftCst == rightCst;
                return constMgr.addConstant(ApValue::makeBool(ctx, result));
            }

            default:
                break;
        }

        return ConstantRef::invalid();
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(SemaJob& job)
{
    const auto& tok          = job.token(srcViewRef(), tokRef());
    const auto  nodeLeftPtr  = job.node(nodeLeft);
    const auto  nodeRightPtr = job.node(nodeRight);

    if (nodeLeftPtr->isConstant() && nodeRightPtr->isConstant())
    {
        const auto cst = constantFoldBinaryExpr(job, tok.id, nodeLeft, nodeRight);
        if (cst.isValid())
            setConstant(cst);
        else
            job.raiseUnsupported(this);
        return AstVisitStepResult::Continue;
    }

    job.raiseUnsupported(this);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstRelationalExpr::semaPostNode(SemaJob& job)
{
    const auto& tok          = job.token(srcViewRef(), tokRef());
    const auto  nodeLeftPtr  = job.node(nodeLeft);
    const auto  nodeRightPtr = job.node(nodeRight);

    if (nodeLeftPtr->isConstant() && nodeRightPtr->isConstant())
    {
        const auto cst = constantFoldRelationalExpr(job, tok.id, nodeLeft, nodeRight);
        if (cst.isValid())
            setConstant(cst);
        else
            job.raiseUnsupported(this);
        return AstVisitStepResult::Continue;
    }

    job.raiseUnsupported(this);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
