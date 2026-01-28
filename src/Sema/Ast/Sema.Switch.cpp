#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct SwitchCaseConstSet
    {
        // Track constant identities (not their string representation).
        // `ConstantRef` is a `StrongRef` (no `std::hash`), so store the underlying id.
        std::unordered_map<ConstantRef, SourceCodeLocation> seen;
    };
}

Result AstSwitchStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    // Each case has its own breakable frame.
    if (sema.node(childRef).is(AstNodeId::SwitchCaseStmt))
    {
        // A switch without an expression behaves like a condition-switch.
        // Give it a `bool` type so case expressions can be validated/cast accordingly.
        const auto& switchNode = sema.node(sema.curNodeRef());
        const auto* switchStmt = switchNode.cast<AstSwitchStmt>();
        if (switchStmt && !switchStmt->nodeExprRef.isValid())
            sema.setType(sema.curNodeRef(), sema.ctx().typeMgr().typeBool());

        SemaFrame frame = sema.frame();
        frame.setBreakable(sema.curNodeRef(), SemaFrame::BreakableKind::Switch);
        frame.setCurrentSwitch(sema.curNodeRef());
        frame.setCurrentSwitchCase(childRef);

        // If the switch expression is an enum (or an alias to an enum), provide the enum type
        // as a binding type so `case .EnumValue` can resolve via auto-scope.
        const TypeRef switchTypeRef = sema.typeRefOf(sema.curNodeRef());
        const TypeRef enumTypeRef   = sema.typeMgr().get(switchTypeRef).unwrap(sema.ctx(), switchTypeRef, TypeExpandE::Alias);
        if (sema.typeMgr().get(enumTypeRef).isEnum())
            frame.pushBindingType(enumTypeRef);

        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    }

    return Result::Continue;
}

Result AstFallThroughStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().breakableKind() != SemaFrame::BreakableKind::Switch)
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());

    const AstNodeRef switchRef = sema.frame().currentSwitch();
    const AstNodeRef caseRef   = sema.frame().currentSwitchCase();
    if (switchRef.isInvalid() || caseRef.isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());

    const auto* caseStmt = sema.node(caseRef).cast<AstSwitchCaseStmt>();
    if (!caseStmt->spanChildrenRef.isValid())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());

    SmallVector<AstNodeRef> stmts;
    sema.ast().nodes(stmts, caseStmt->spanChildrenRef);
    const auto itStmt = std::ranges::find(stmts, sema.curNodeRef());
    if (itStmt == stmts.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());
    if (itStmt + 1 != stmts.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_not_last_stmt, sema.curNodeRef());

    const auto* switchStmt = sema.node(switchRef).cast<AstSwitchStmt>();
    if (!switchStmt->spanChildrenRef.isValid())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());

    SmallVector<AstNodeRef> cases;
    sema.ast().nodes(cases, switchStmt->spanChildrenRef);
    const auto itCase = std::ranges::find(cases, caseRef);
    if (itCase == cases.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());
    if (itCase + 1 == cases.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_in_last_case, sema.curNodeRef());

    return Result::Continue;
}

Result AstSwitchStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        const SemaNodeView exprView(sema, nodeExprRef);

        const auto&     typeMgr   = sema.ctx().typeMgr();
        const TypeInfo& type      = typeMgr.get(exprView.typeRef);
        const TypeRef   ultimate  = type.unwrap(sema.ctx(), exprView.typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& finalType = typeMgr.get(ultimate);
        if (!finalType.isIntLike() && !finalType.isFloat() && !finalType.isBool() && !finalType.isString())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_invalid_type, nodeExprRef);

        sema.setType(sema.curNodeRef(), exprView.typeRef);

        // For value-switches, track duplicate constant case values across all cases.
        // Initialize this once per switch (after the switch expression is type-checked).
        if (sema.frame().currentSwitch() != sema.curNodeRef() || !sema.frame().switchPayload())
        {
            sema.frame().setCurrentSwitch(sema.curNodeRef());
            sema.frame().setSwitchPayload(sema.compiler().allocate<SwitchCaseConstSet>());
        }
    }

    // A switch can be marked with the 'Complete' attribute, except if it does not have an expression.
    if (sema.frame().attributes().hasSwagFlag(SwagAttributeFlagsE::Complete))
    {
        if (!nodeExprRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_complete_no_expr, sema.curNodeRef());
    }

    // A switch can be marked with the 'Incomplete' attribute, except if it does not have an expression.
    if (sema.frame().attributes().hasSwagFlag(SwagAttributeFlagsE::Incomplete))
    {
        if (!nodeExprRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_incomplete_no_expr, sema.curNodeRef());
    }

    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstSwitchCaseStmt::semaPreNodeChild(Sema& sema, AstNodeRef& childRef) const
{
    const AstNodeRef switchRef = sema.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const TypeRef switchTypeRef = sema.typeRefOf(switchRef);
    if (switchTypeRef.isInvalid())
        return Result::Continue;

    // Only touch case expressions (not the statements in the case body).
    if (!spanExprRef.isValid())
        return Result::Continue;

    SmallVector<AstNodeRef> expressions;
    sema.ast().nodes(expressions, spanExprRef);
    const bool isExprChild = std::ranges::find(expressions, childRef) != expressions.end();
    if (!isExprChild)
        return Result::Continue;

    // If the switch is on an enum, allow shorthand by rewriting it to an
    // auto-member-access expression (equivalent to `.Value`), which will resolve in the
    // enum scope provided by the binding type pushed from the parent switch.
    const TypeRef enumTypeRef = sema.typeMgr().get(switchTypeRef).unwrap(sema.ctx(), switchTypeRef, TypeExpandE::Alias);
    if (sema.typeMgr().get(enumTypeRef).isEnum() && sema.node(childRef).is(AstNodeId::Identifier))
    {
        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::AutoMemberAccessExpr>(sema.node(childRef).tokRef());
        nodePtr->nodeIdentRef   = childRef;
        childRef                = nodeRef;
    }

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

    const auto& switchNode    = sema.node(switchRef);
    const auto* switchStmt    = switchNode.cast<AstSwitchStmt>();
    const bool  hasSwitchExpr = switchStmt && switchStmt->nodeExprRef.isValid();

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
            // Condition-switch: each `case <expr>` must be bool-compatible.
            if (!hasSwitchExpr)
            {
                SemaNodeView  nodeView(sema, childRef);
                const TypeRef boolTypeRef = sema.ctx().typeMgr().typeBool();

                CastContext castCtx(CastKind::Condition);
                castCtx.errorNodeRef = childRef;
                if (Cast::castAllowed(sema, castCtx, nodeView.typeRef, boolTypeRef) != Result::Continue)
                    return SemaError::raise(sema, DiagnosticId::sema_err_switch_case_not_bool, childRef);

                RESULT_VERIFY(Cast::cast(sema, nodeView, boolTypeRef, CastKind::Condition));
                return Result::Continue;
            }

            // Range expression
            if (sema.node(childRef).is(AstNodeId::RangeExpr))
            {
                const TypeRef   ultimateSwitchTypeRef = sema.typeMgr().get(switchTypeRef).unwrap(sema.ctx(), switchTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
                const TypeInfo& switchType            = sema.typeMgr().get(ultimateSwitchTypeRef);
                if (!switchType.isScalarNumeric())
                    return SemaError::raise(sema, DiagnosticId::sema_err_switch_range_invalid_type, childRef);

                const auto* range = sema.node(childRef).cast<AstRangeExpr>();
                if (range->nodeExprDownRef.isValid())
                    RESULT_VERIFY(castToSwitchType(sema, range->nodeExprDownRef, switchTypeRef));
                if (range->nodeExprUpRef.isValid())
                    RESULT_VERIFY(castToSwitchType(sema, range->nodeExprUpRef, switchTypeRef));

                if (range->nodeExprDownRef.isValid())
                {
                    const SemaNodeView downView(sema, range->nodeExprDownRef);
                    if (downView.cstRef.isInvalid())
                        return SemaError::raise(sema, DiagnosticId::sema_err_switch_case_not_const, range->nodeExprDownRef);
                }

                if (range->nodeExprUpRef.isValid())
                {
                    const SemaNodeView upView(sema, range->nodeExprUpRef);
                    if (upView.cstRef.isInvalid())
                        return SemaError::raise(sema, DiagnosticId::sema_err_switch_case_not_const, range->nodeExprUpRef);
                }

                return Result::Continue;
            }

            RESULT_VERIFY(castToSwitchType(sema, childRef, switchTypeRef));
            const SemaNodeView exprView(sema, childRef);
            if (exprView.cstRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_switch_case_not_const, childRef);

            // Duplicate constant value check (value-switch only).
            if (sema.frame().switchPayload())
            {
                auto*                    seenSet = static_cast<SwitchCaseConstSet*>(sema.frame().switchPayload());
                const SourceCodeLocation curLoc  = sema.node(childRef).locationWithChildren(sema.ctx(), sema.ast());
                const auto               it      = seenSet->seen.find(exprView.cstRef);
                if (it == seenSet->seen.end())
                {
                    seenSet->seen.emplace(exprView.cstRef, curLoc);
                }
                else
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_case_duplicate, childRef);
                    diag.addArgument(Diagnostic::ARG_VALUE, sema.cstMgr().get(exprView.cstRef).toString(sema.ctx()));
                    diag.addNote(DiagnosticId::sema_note_previous_case_value);
                    diag.last().addSpan(it->second);
                    diag.report(sema.ctx());
                    return Result::Error;
                }
            }
            return Result::Continue;
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
