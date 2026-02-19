#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

Result AstRangeExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeDownView = sema.nodeView(nodeExprDownRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
    SemaNodeView nodeUpView   = sema.nodeView(nodeExprUpRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);

    if (nodeDownView.nodeRef.isValid())
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeDownView.nodeRef));
    if (nodeUpView.nodeRef.isValid())
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeUpView.nodeRef));

    TypeRef typeRef = TypeRef::invalid();
    if (nodeDownView.typeRef.isValid())
    {
        if (!nodeDownView.type->isScalarNumeric())
            return SemaError::raiseInvalidRangeType(sema, nodeExprDownRef, nodeDownView.typeRef);
        typeRef = nodeDownView.typeRef;
    }
    else if (nodeUpView.typeRef.isValid())
    {
        if (!nodeUpView.type->isScalarNumeric())
            return SemaError::raiseInvalidRangeType(sema, nodeExprUpRef, nodeUpView.typeRef);
        typeRef = nodeUpView.typeRef;
    }

    if (nodeDownView.typeRef.isValid() && nodeUpView.typeRef.isValid())
    {
        typeRef = sema.typeMgr().promote(nodeDownView.typeRef, nodeUpView.typeRef, false);
        RESULT_VERIFY(Cast::cast(sema, nodeDownView, typeRef, CastKind::Implicit));
        RESULT_VERIFY(Cast::cast(sema, nodeUpView, typeRef, CastKind::Implicit));
    }

    SWC_ASSERT(typeRef.isValid());
    sema.setType(sema.curNodeRef(), typeRef);
    sema.setIsValue(*this);

    if (nodeDownView.cstRef.isValid() && nodeUpView.cstRef.isValid())
    {
        ConstantRef          downCstRef = nodeDownView.cstRef;
        ConstantRef          upCstRef   = nodeUpView.cstRef;
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
