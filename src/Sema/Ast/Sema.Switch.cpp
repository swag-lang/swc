#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

Result AstSwitchStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    // Each case has its own breakable frame.
    if (sema.node(childRef).is(AstNodeId::SwitchCaseStmt))
    {
        SemaFrame frame = sema.frame();
        frame.setBreakable(sema.curNodeRef(), SemaFrame::BreakableKind::Switch);
        frame.setCurrentSwitch(sema.curNodeRef());
        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    }

    return Result::Continue;
}

Result AstSwitchStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        const SemaNodeView exprView(sema, nodeExprRef);

        const auto&     typeMgr   = sema.ctx().typeMgr();
        const TypeInfo& type      = typeMgr.get(exprView.typeRef);
        const TypeRef   ultimate  = type.ultimateTypeRef(sema.ctx(), exprView.typeRef);
        const TypeInfo& finalType = typeMgr.get(ultimate);
        if (!finalType.isIntLike() && !finalType.isFloat() && !finalType.isBool() && !finalType.isString())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_invalid_type, nodeExprRef);

        sema.setType(sema.curNodeRef(), exprView.typeRef);
    }

    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

namespace
{
    Result castToSwitchType(Sema& sema, AstNodeRef nodeRef, TypeRef switchTypeRef)
    {
        SemaNodeView view(sema, nodeRef);
        return Cast::cast(sema, view, switchTypeRef, CastKind::Implicit);
    }
}

Result AstSwitchCaseStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeWhereRef)
    {
        SemaNodeView nodeView(sema, nodeWhereRef);
        return Cast::cast(sema, nodeView, sema.ctx().typeMgr().typeBool(), CastKind::Condition);
    }

    const AstNodeRef switchRef = sema.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const TypeRef switchTypeRef = sema.typeRefOf(switchRef);
    if (switchTypeRef.isInvalid())
        return Result::Continue;

    // Only cast case expressions (not the statements in the case body).
    // `childRef` can be one of the expressions in `spanExprRef`.
    if (spanExprRef.isValid())
    {
        SmallVector<AstNodeRef> expressions;
        sema.ast().nodes(expressions, spanExprRef);
        const bool isExprChild = std::ranges::find(expressions, childRef) != expressions.end();

        if (isExprChild)
        {
            // Range expression
            if (sema.node(childRef).is(AstNodeId::RangeExpr))
            {
                const TypeRef   ultimateSwitchTypeRef = sema.typeMgr().get(switchTypeRef).ultimateTypeRef(sema.ctx(), switchTypeRef);
                const TypeInfo& switchType            = sema.typeMgr().get(ultimateSwitchTypeRef);
                if (!switchType.isScalarNumeric())
                    return SemaError::raise(sema, DiagnosticId::sema_err_switch_range_invalid_type, childRef);

                const auto* range = sema.node(childRef).cast<AstRangeExpr>();
                if (range->nodeExprDownRef.isValid())
                    RESULT_VERIFY(castToSwitchType(sema, range->nodeExprDownRef, switchTypeRef));
                if (range->nodeExprUpRef.isValid())
                    RESULT_VERIFY(castToSwitchType(sema, range->nodeExprUpRef, switchTypeRef));
                return Result::Continue;
            }

            return castToSwitchType(sema, childRef, switchTypeRef);
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
