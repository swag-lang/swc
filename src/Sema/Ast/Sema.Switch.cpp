#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/Ast/AstNodes.h"
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

Result AstSwitchStmt::semaPreNode(Sema& sema) const
{
    // A switch can be marked with the 'Complete' attribute, except if it does not have an expression.
    if (sema.frame().currentAttributes().hasRtFlag(RtAttributeFlagsE::Complete))
    {
        if (!nodeExprRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_complete_no_expr, sema.curNodeRef());

        const SemaNodeView exprView(sema, nodeExprRef);
        const TypeInfo&    type = sema.ctx().typeMgr().get(exprView.typeRef);
    }

    // A switch can be marked with the 'Incomplete' attribute, except if it does not have an expression.
    if (sema.frame().currentAttributes().hasRtFlag(RtAttributeFlagsE::Incomplete))
    {
        if (!nodeExprRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_incomplete_no_expr, sema.curNodeRef());
    }

    // Register switch
    SemaFrame frame = sema.frame();
    frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Switch);
    frame.setCurrentSwitch(sema.curNodeRef());
    sema.pushFramePopOnPostNode(frame);
    sema.setPayload(sema.curNodeRef(), sema.compiler().allocate<SwitchPayload>());
    return Result::Continue;
}

Result AstSwitchStmt::semaPostNode(Sema& sema)
{
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
        const TypeInfo&    type      = sema.ctx().typeMgr().get(exprView.typeRef);
        const TypeRef      ultimate  = type.unwrap(sema.ctx(), exprView.typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo&    finalType = sema.ctx().typeMgr().get(ultimate);
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
    Result castCaseToSwitch(Sema& sema, AstNodeRef nodeRef, TypeRef switchTypeRef)
    {
        SemaNodeView view(sema, nodeRef);
        return Cast::cast(sema, view, switchTypeRef, CastKind::Implicit);
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
            RESULT_VERIFY(castCaseToSwitch(sema, range->nodeExprDownRef, switchTypeRef));
        if (range->nodeExprUpRef.isValid())
            RESULT_VERIFY(castCaseToSwitch(sema, range->nodeExprUpRef, switchTypeRef));

        if (range->nodeExprDownRef.isValid())
            RESULT_VERIFY(checkCaseExprIsConst(sema, range->nodeExprDownRef));
        if (range->nodeExprUpRef.isValid())
            RESULT_VERIFY(checkCaseExprIsConst(sema, range->nodeExprUpRef));

        return Result::Continue;
    }

    Result checkDuplicateConstCaseValue(Sema& sema, AstNodeRef switchRef, AstNodeRef caseExprRef, AstNodeRef whereRef)
    {
        // A case expression with a 'where' clause is not tested for duplicates, except
        // if the where clause if a 'true' constant.
        if (whereRef.isValid())
        {
            if (!sema.hasConstant(whereRef) || sema.constantRefOf(whereRef) != sema.cstMgr().cstTrue())
                return Result::Continue;
        }

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

    // Be sure this is a case expression
    if (!spanExprRef.isValid())
        return Result::Continue;
    const bool isExprChild = childRef != nodeWhereRef && childRef != nodeBodyRef;
    if (!isExprChild)
        return Result::Continue;

    const AstNodeRef switchRef = sema.frame().currentSwitch();
    SWC_ASSERT(switchRef.isValid());

    const SwitchPayload* payload       = sema.payload<SwitchPayload>(switchRef);
    const TypeRef        switchTypeRef = payload->exprTypeRef;

    // This is a switch without an expression
    if (switchTypeRef.isInvalid())
    {
        SemaNodeView nodeView(sema, childRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.ctx().typeMgr().typeBool(), CastKind::Condition));
        return Result::Continue;
    }

    // Range expression
    if (sema.node(childRef).is(AstNodeId::RangeExpr))
        return handleRangeCaseExpr(sema, childRef, switchTypeRef);

    RESULT_VERIFY(castCaseToSwitch(sema, childRef, switchTypeRef));
    RESULT_VERIFY(checkCaseExprIsConst(sema, childRef));
    RESULT_VERIFY(checkDuplicateConstCaseValue(sema, switchRef, childRef, nodeWhereRef));

    return Result::Continue;
}

Result AstFallThroughStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().currentBreakableKind() != SemaFrame::BreakContextKind::Switch)
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());

    const AstNodeRef caseRef = sema.frame().currentSwitchCase();
    if (caseRef.isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());

    SmallVector<AstNodeRef> stmts;
    const auto*             caseStmt = sema.node(caseRef).cast<AstSwitchCaseStmt>();
    const auto*             caseBody = sema.node(caseStmt->nodeBodyRef).cast<AstSwitchCaseBody>();

    sema.ast().nodes(stmts, caseBody->spanChildrenRef);
    const auto itStmt = std::ranges::find(stmts, sema.curNodeRef());
    if (itStmt == stmts.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());
    if (itStmt + 1 != stmts.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_not_last_stmt, sema.curNodeRef());

    const AstNodeRef switchRef  = sema.frame().currentSwitch();
    const auto*      switchStmt = sema.node(switchRef).cast<AstSwitchStmt>();
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
