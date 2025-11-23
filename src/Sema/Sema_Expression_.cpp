#include "pch.h"
#include "ConstantManager.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/SemaJob.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldBinaryExpr(SemaJob& job, TokenId op, AstNodeRef left, AstNodeRef right)
    {
        const auto& ctx      = job.ctx();
        const auto& typeMgr  = job.typeMgr();
        auto&       constMgr = job.constMgr();
        const auto  leftPtr  = job.node(left);
        const auto  rightPtr = job.node(right);
        const auto& leftCst  = leftPtr->getConstant(ctx);
        const auto& rightCst = rightPtr->getConstant(ctx);

        switch (op)
        {
            case TokenId::SymPlusPlus:
                if (!leftCst.isString())
                    job.raiseInvalidType(left, typeMgr.getString(), leftCst.typeRef());
                if (!rightCst.isString())
                    job.raiseInvalidType(right, typeMgr.getString(), rightCst.typeRef());
                if (leftCst.isString() && rightCst.isString())
                {
                    Utf8 result = leftCst.getString();
                    result += rightCst.getString();
                    return constMgr.addConstant(ConstantValue::makeString(ctx, result));
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
        return AstVisitStepResult::Continue;
    }

    job.raiseUnsupported(this);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
