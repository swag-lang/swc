#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const ConstantRef leftCstRef  = nodeLeftView.cstRef;
        const ConstantRef rightCstRef = nodeRightView.cstRef;
        const ConstantRef cstFalseRef = sema.cstMgr().cstFalse();
        const ConstantRef cstTrueRef  = sema.cstMgr().cstTrue();

        switch (op)
        {
            case TokenId::KwdAnd:
                if (leftCstRef == cstFalseRef)
                    result = cstFalseRef;
                else if (rightCstRef == cstFalseRef)
                    result = cstFalseRef;
                else
                    result = cstTrueRef;
                return Result::Continue;

            case TokenId::KwdOr:
                if (leftCstRef == cstTrueRef)
                    result = cstTrueRef;
                else if (rightCstRef == cstTrueRef)
                    result = cstTrueRef;
                else
                    result = cstFalseRef;
                return Result::Continue;

            default:
                SWC_UNREACHABLE();
        }
    }

    Result check(Sema& sema, const AstLogicalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (!nodeLeftView.type->isBool())
            return SemaError::raiseBinaryOperandType(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
        if (!nodeRightView.type->isBool())
            return SemaError::raiseBinaryOperandType(sema, node, node.nodeRightRef, nodeRightView.typeRef);
        return Result::Continue;
    }
}

Result AstLogicalExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView nodeRightView(sema, nodeRightRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeLeftRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightRef));
    SemaInfo::setIsValue(*this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    RESULT_VERIFY(check(sema, *this, nodeLeftView, nodeRightView));

    // Set the result type
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());

    // Constant folding
    if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
    {
        ConstantRef result;
        RESULT_VERIFY(constantFold(sema, result, tok.id, nodeLeftView, nodeRightView));
        sema.setConstant(sema.curNodeRef(), result);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
