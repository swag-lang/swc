#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaInfo.h"
#include "Sema/SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFold(Sema& sema, TokenId op, const AstLogicalExpr& node, const SemaNodeViewList& ops)
    {
        const ConstantRef leftCstRef  = ops.nodeView[0].cstRef;
        const ConstantRef rightCstRef = ops.nodeView[1].cstRef;

        switch (op)
        {
            case TokenId::KwdAnd:
                if (leftCstRef == sema.cstMgr().cstFalse())
                    return sema.cstMgr().cstFalse();
                if (rightCstRef == sema.cstMgr().cstFalse())
                    return sema.cstMgr().cstFalse();
                return sema.cstMgr().cstTrue();

            case TokenId::KwdOr:
                if (leftCstRef == sema.cstMgr().cstTrue())
                    return sema.cstMgr().cstTrue();
                if (rightCstRef == sema.cstMgr().cstTrue())
                    return sema.cstMgr().cstTrue();
                return sema.cstMgr().cstFalse();

            default:
                SWC_UNREACHABLE();
        }
    }

    Result check(const Sema& sema, TokenId op, const AstLogicalExpr& node, const SemaNodeViewList& ops)
    {
        if (!ops.nodeView[0].type->isBool())
        {
            sema.raiseBinaryOperandType(node, node.nodeLeftRef, ops.nodeView[0].typeRef);
            return Result::Error;
        }

        if (!ops.nodeView[1].type->isBool())
        {
            sema.raiseBinaryOperandType(node, node.nodeRightRef, ops.nodeView[1].typeRef);
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

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
