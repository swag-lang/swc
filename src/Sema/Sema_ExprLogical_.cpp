#include "pch.h"
#include "Helpers/SemaError.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFold(Sema& sema, TokenId op, const AstLogicalExpr& node, const SemaNodeViewList& ops)
    {
        const ConstantRef leftCstRef  = ops.nodeView[0].cstRef;
        const ConstantRef rightCstRef = ops.nodeView[1].cstRef;
        const ConstantRef cstFalseRef = sema.cstMgr().cstFalse();
        const ConstantRef cstTrueRef  = sema.cstMgr().cstTrue();

        switch (op)
        {
            case TokenId::KwdAnd:
                if (leftCstRef == cstFalseRef)
                    return cstFalseRef;
                if (rightCstRef == cstFalseRef)
                    return cstFalseRef;
                return cstTrueRef;

            case TokenId::KwdOr:
                if (leftCstRef == cstTrueRef)
                    return cstTrueRef;
                if (rightCstRef == cstTrueRef)
                    return cstTrueRef;
                return cstFalseRef;

            default:
                SWC_UNREACHABLE();
        }
    }

    Result check(Sema& sema, TokenId op, const AstLogicalExpr& node, const SemaNodeViewList& ops)
    {
        if (!ops.nodeView[0].type->isBool())
        {
            SemaError::raiseBinaryOperandType(sema, node, node.nodeLeftRef, ops.nodeView[0].typeRef);
            return Result::Error;
        }

        if (!ops.nodeView[1].type->isBool())
        {
            SemaError::raiseBinaryOperandType(sema, node, node.nodeRightRef, ops.nodeView[1].typeRef);
            return Result::Error;
        }

        return Result::Success;
    }
}

AstVisitStepResult AstLogicalExpr::semaPostNode(Sema& sema) const
{
    const SemaNodeViewList ops(sema, nodeLeftRef, nodeRightRef);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (sema.hasConstant(nodeLeftRef) && sema.hasConstant(nodeRightRef))
    {
        const auto cst = constantFold(sema, tok.id, *this, ops);
        if (cst.isValid())
        {
            sema.setConstant(sema.curNodeRef(), cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    SemaError::raiseInternalError(sema, *this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
