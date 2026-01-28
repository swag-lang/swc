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
    struct SwitchPayload
    {
        TypeRef exprTypeRef = TypeRef::invalid();

        std::unordered_map<ConstantRef, SourceCodeLocation> seen;
    };
}

Result AstSwitchStmt::semaPreNode(Sema& sema)
{
    SemaFrame frame = sema.frame();
    frame.setBreakable(sema.curNodeRef(), SemaFrame::BreakableKind::Switch);
    frame.setCurrentSwitch(sema.curNodeRef());
    sema.pushFramePopOnPostNode(frame);
    sema.setPayload(sema.curNodeRef(), sema.compiler().allocate<SwitchPayload>());
    return Result::Continue;
}

Result AstSwitchStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    if (sema.node(childRef).is(AstNodeId::SwitchCaseStmt))
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentSwitchCase(childRef);
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
        const auto&        typeMgr   = sema.ctx().typeMgr();
        const TypeInfo&    type      = typeMgr.get(exprView.typeRef);
        const TypeRef      ultimate  = type.unwrap(sema.ctx(), exprView.typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo&    finalType = typeMgr.get(ultimate);
        if (!finalType.isIntLike() && !finalType.isFloat() && !finalType.isBool() && !finalType.isString())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_invalid_type, nodeExprRef);

        sema.payload<SwitchPayload>(sema.curNodeRef())->exprTypeRef = exprView.typeRef;

        if (type.isEnum())
        {
            SemaFrame frame = sema.frame();
            frame.pushBindingType(exprView.typeRef);
            sema.pushFramePopOnPostNode(frame);
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

    const auto*   payload       = sema.payload<SwitchPayload>(switchRef);
    const TypeRef switchTypeRef = payload->exprTypeRef;
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
    bool isChildOfSpanExprRef(Sema& sema, const SpanRef& spanExprRef, const AstNodeRef& childRef)
    {
        if (!spanExprRef.isValid())
            return false;

        SmallVector<AstNodeRef> expressions;
        sema.ast().nodes(expressions, spanExprRef);
        return std::ranges::find(expressions, childRef) != expressions.end();
    }

    Result castToSwitchType(Sema& sema, AstNodeRef nodeRef, TypeRef switchTypeRef)
    {
        SemaNodeView view(sema, nodeRef);
        return Cast::cast(sema, view, switchTypeRef, CastKind::Implicit);
    }

    Result castCaseExprToBoolForConditionSwitch(Sema& sema, const AstNodeRef& exprRef)
    {
        SemaNodeView  nodeView(sema, exprRef);
        const TypeRef boolTypeRef = sema.ctx().typeMgr().typeBool();

        CastContext castCtx(CastKind::Condition);
        castCtx.errorNodeRef = exprRef;
        if (Cast::castAllowed(sema, castCtx, nodeView.typeRef, boolTypeRef) != Result::Continue)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_case_not_bool, exprRef);
            diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Cast::cast(sema, nodeView, boolTypeRef, CastKind::Condition);
    }

    Result checkCaseExprIsConst(Sema& sema, const AstNodeRef& exprRef)
    {
        const SemaNodeView exprView(sema, exprRef);
        if (exprView.cstRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_case_not_const, exprRef);
        return Result::Continue;
    }

    Result handleRangeCaseExpr(Sema& sema, const AstNodeRef& rangeRef, TypeRef switchTypeRef)
    {
        const TypeRef   ultimateSwitchTypeRef = sema.typeMgr().get(switchTypeRef).unwrap(sema.ctx(), switchTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& switchType            = sema.typeMgr().get(ultimateSwitchTypeRef);

        if (!switchType.isScalarNumeric())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_range_invalid_type, rangeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, ultimateSwitchTypeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        const auto* range = sema.node(rangeRef).cast<AstRangeExpr>();
        if (range->nodeExprDownRef.isValid())
            RESULT_VERIFY(castToSwitchType(sema, range->nodeExprDownRef, switchTypeRef));
        if (range->nodeExprUpRef.isValid())
            RESULT_VERIFY(castToSwitchType(sema, range->nodeExprUpRef, switchTypeRef));

        if (range->nodeExprDownRef.isValid())
            RESULT_VERIFY(checkCaseExprIsConst(sema, range->nodeExprDownRef));
        if (range->nodeExprUpRef.isValid())
            RESULT_VERIFY(checkCaseExprIsConst(sema, range->nodeExprUpRef));

        return Result::Continue;
    }

    Result checkDuplicateConstCaseValue(Sema& sema, const AstNodeRef& switchRef, const AstNodeRef& caseExprRef)
    {
        auto* seenSet = sema.payload<SwitchPayload>(switchRef);
        SWC_ASSERT(seenSet);

        const SemaNodeView       exprView(sema, caseExprRef);
        const SourceCodeLocation curLoc = sema.node(caseExprRef).locationWithChildren(sema.ctx(), sema.ast());

        const auto it = seenSet->seen.find(exprView.cstRef);
        if (it == seenSet->seen.end())
        {
            seenSet->seen.emplace(exprView.cstRef, curLoc);
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_case_duplicate, caseExprRef);
        diag.addArgument(Diagnostic::ARG_VALUE, sema.cstMgr().get(exprView.cstRef).toString(sema.ctx()));
        diag.addNote(DiagnosticId::sema_note_previous_case_value);
        diag.last().addSpan(it->second);
        diag.report(sema.ctx());
        return Result::Error;
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

    const AstNode&       switchNode    = sema.node(switchRef);
    const AstSwitchStmt* switchStmt    = switchNode.cast<AstSwitchStmt>();
    const bool           hasSwitchExpr = switchStmt->nodeExprRef.isValid();

    const SwitchPayload* payload       = sema.payload<SwitchPayload>(switchRef);
    const TypeRef        switchTypeRef = payload->exprTypeRef;

    // Only cast case expressions (not the statements in the case body).
    // `childRef` can be one of the expressions in `spanExprRef`.
    if (!isChildOfSpanExprRef(sema, spanExprRef, childRef))
        return Result::Continue;

    // Condition-switch: each `case <expr>` must be bool-compatible.
    if (!hasSwitchExpr)
    {
        RESULT_VERIFY(castCaseExprToBoolForConditionSwitch(sema, childRef));
        return Result::Continue;
    }

    // Range expression
    if (sema.node(childRef).is(AstNodeId::RangeExpr))
        return handleRangeCaseExpr(sema, childRef, switchTypeRef);

    RESULT_VERIFY(castToSwitchType(sema, childRef, switchTypeRef));
    RESULT_VERIFY(checkCaseExprIsConst(sema, childRef));
    RESULT_VERIFY(checkDuplicateConstCaseValue(sema, switchRef, childRef));

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

SWC_END_NAMESPACE();
