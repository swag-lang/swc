#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

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
        if (!nodeLeftView.type->isConvertibleToBool())
            return SemaError::raiseBinaryOperandType(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
        if (!nodeRightView.type->isConvertibleToBool())
            return SemaError::raiseBinaryOperandType(sema, node, node.nodeRightRef, nodeRightView.typeRef);
        return Result::Continue;
    }
}

Result AstLogicalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeLeftView(sema, nodeLeftRef);
    SemaNodeView nodeRightView(sema, nodeRightRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeLeftView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));
    SemaInfo::setIsValue(*this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    RESULT_VERIFY(check(sema, *this, nodeLeftView, nodeRightView));

    // Set the result type
    RESULT_VERIFY(Cast::cast(sema, nodeLeftView, sema.typeMgr().typeBool(), CastKind::Condition));
    RESULT_VERIFY(Cast::cast(sema, nodeRightView, sema.typeMgr().typeBool(), CastKind::Condition));
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
