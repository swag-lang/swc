#include "pch.h"
#include "Support/Report/Assert.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const TypeInfo& aliasType(Sema& sema, const SemaNodeView& view)
    {
        const TypeRef typeRef = sema.typeMgr().get(view.typeRef()).unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Alias);
        SWC_ASSERT(typeRef.isValid());
        return sema.typeMgr().get(typeRef);
    }

    Result validateRangeBoundType(Sema& sema, AstNodeRef nodeRef, const SemaNodeView& view)
    {
        const TypeInfo& type = aliasType(sema, view);
        if (type.isScalarNumeric())
            return Result::Continue;
        if (type.isEnum())
            return sema.waitSemaCompleted(&type, nodeRef);
        return SemaError::raiseInvalidRangeType(sema, nodeRef, view.typeRef());
    }

    ConstantRef rangeComparableConstantRef(Sema& sema, ConstantRef cstRef)
    {
        const ConstantValue& value = sema.cstMgr().get(cstRef);
        if (value.isEnumValue())
            return value.getEnumValue();
        return cstRef;
    }

    bool isEnumRangeBound(Sema& sema, const SemaNodeView& view)
    {
        return view.typeRef().isValid() && aliasType(sema, view).isEnum();
    }

    Result validateEnumRangeBounds(Sema& sema, const SemaNodeView& nodeDownView, const SemaNodeView& nodeUpView, AstNodeRef nodeExprDownRef, AstNodeRef nodeExprUpRef)
    {
        const bool downIsEnum = isEnumRangeBound(sema, nodeDownView);
        const bool upIsEnum   = isEnumRangeBound(sema, nodeUpView);
        if (!downIsEnum && !upIsEnum)
            return Result::Continue;

        if (nodeDownView.typeRef().isValid() && !downIsEnum)
            return SemaError::raiseInvalidRangeType(sema, nodeExprDownRef, nodeDownView.typeRef());
        if (nodeUpView.typeRef().isValid() && !upIsEnum)
            return SemaError::raiseInvalidRangeType(sema, nodeExprUpRef, nodeUpView.typeRef());

        if (downIsEnum && upIsEnum && &aliasType(sema, nodeDownView).payloadSymEnum() != &aliasType(sema, nodeUpView).payloadSymEnum())
            return SemaError::raiseCannotCast(sema, nodeExprUpRef, nodeUpView.typeRef(), nodeDownView.typeRef());

        return Result::Continue;
    }
}

Result AstRangeExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeDownView = sema.viewNodeTypeConstant(nodeExprDownRef);
    SemaNodeView nodeUpView   = sema.viewNodeTypeConstant(nodeExprUpRef);

    if (nodeDownView.nodeRef().isValid())
        SWC_RESULT(SemaCheck::isValue(sema, nodeDownView.nodeRef()));
    if (nodeUpView.nodeRef().isValid())
        SWC_RESULT(SemaCheck::isValue(sema, nodeUpView.nodeRef()));

    if (nodeDownView.typeRef().isValid())
        SWC_RESULT(validateRangeBoundType(sema, nodeExprDownRef, nodeDownView));
    if (nodeUpView.typeRef().isValid())
        SWC_RESULT(validateRangeBoundType(sema, nodeExprUpRef, nodeUpView));

    SWC_RESULT(validateEnumRangeBounds(sema, nodeDownView, nodeUpView, nodeExprDownRef, nodeExprUpRef));

    TypeRef typeRef = TypeRef::invalid();
    if (!nodeDownView.typeRef().isValid() && !nodeUpView.typeRef().isValid())
        typeRef = sema.typeMgr().typeU64();
    else if (nodeDownView.typeRef().isValid())
        typeRef = nodeDownView.typeRef();
    else if (nodeUpView.typeRef().isValid())
        typeRef = nodeUpView.typeRef();

    if (nodeDownView.typeRef().isValid() && nodeUpView.typeRef().isValid() && !isEnumRangeBound(sema, nodeDownView))
    {
        SWC_RESULT(Cast::castPromote(sema, nodeDownView, nodeUpView, CastKind::Implicit));
        typeRef = nodeDownView.typeRef();
    }

    SWC_ASSERT(typeRef.isValid());
    sema.setType(sema.curNodeRef(), typeRef);
    sema.setIsValue(*this);

    if (nodeDownView.cstRef().isValid() && nodeUpView.cstRef().isValid())
    {
        ConstantRef          downCstRef = rangeComparableConstantRef(sema, nodeDownView.cstRef());
        ConstantRef          upCstRef   = rangeComparableConstantRef(sema, nodeUpView.cstRef());
        const ConstantValue& downCst    = sema.cstMgr().get(downCstRef);
        const ConstantValue& upCst      = sema.cstMgr().get(upCstRef);
        const bool           ok         = hasFlag(AstRangeExprFlagsE::Inclusive) ? downCst.le(upCst) : downCst.lt(upCst);
        if (!ok)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_range_invalid_bounds, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_LEFT, downCstRef);
            diag.addArgument(Diagnostic::ARG_RIGHT, upCstRef);
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
