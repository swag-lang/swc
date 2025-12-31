#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFold(Sema& sema, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const ConstantRef leftCstRef  = nodeLeftView.cstRef;
        const ConstantRef rightCstRef = nodeRightView.cstRef;
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

    Result check(Sema& sema, const AstLogicalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (!nodeLeftView.type->isBool())
        {
            SemaError::raiseBinaryOperandType(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
            return Result::Error;
        }

        if (!nodeRightView.type->isBool())
        {
            SemaError::raiseBinaryOperandType(sema, node, node.nodeRightRef, nodeRightView.typeRef);
            return Result::Error;
        }

        return Result::Success;
    }
}

AstVisitStepResult AstLogicalExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView nodeRightView(sema, nodeRightRef);

    // Value-check
    if (SemaCheck::isValueExpr(sema, nodeLeftRef) != Result::Success)
        return AstVisitStepResult::Stop;
    if (SemaCheck::isValueExpr(sema, nodeRightRef) != Result::Success)
        return AstVisitStepResult::Stop;
    SemaInfo::addSemaFlags(*this, NodeSemaFlags::ValueExpr);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, *this, nodeLeftView, nodeRightView) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
    {
        const ConstantRef cst = constantFold(sema, tok.id, nodeLeftView, nodeRightView);
        if (cst.isValid())
        {
            sema.setConstant(sema.curNodeRef(), cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    SemaError::raiseInternal(sema, *this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
