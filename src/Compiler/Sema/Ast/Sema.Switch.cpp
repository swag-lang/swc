#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Payload.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"

SWC_BEGIN_NAMESPACE();

Result AstSwitchStmt::semaPreNode(Sema& sema) const
{
    // A switch can be marked with the 'Complete' attribute, except if it does not have an expression.
    if (sema.frame().currentAttributes().hasRtFlag(RtAttributeFlagsE::Complete))
    {
        if (!nodeExprRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_complete_no_expr, sema.curNodeRef());
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

    SwitchPayload* payload = sema.compiler().allocate<SwitchPayload>();
    payload->isComplete    = sema.frame().currentAttributes().hasRtFlag(RtAttributeFlagsE::Complete);
    sema.setPayload(sema.curNodeRef(), payload);
    return Result::Continue;
}

Result AstSwitchStmt::semaPostNode(Sema& sema)
{
    const SwitchPayload* payload = sema.payload<SwitchPayload>(sema.curNodeRef());
    if (!payload || !payload->isComplete || payload->exprTypeRef.isInvalid())
        return Result::Continue;

    const TypeRef   enumTypeRef = sema.typeMgr().get(payload->exprTypeRef).unwrap(sema.ctx(), payload->exprTypeRef, TypeExpandE::Alias);
    const TypeInfo& enumType    = sema.typeMgr().get(enumTypeRef);
    if (!enumType.isEnum())
        return Result::Continue;

    std::vector<const Symbol*> symbols;
    enumType.payloadSymEnum().getAllSymbols(symbols);

    for (const Symbol* sym : symbols)
    {
        if (!sym || !sym->isEnumValue())
            continue;
        const SymbolEnumValue* value = sym->safeCast<SymbolEnumValue>();
        if (!value)
            continue;
        const ConstantRef cstRef = value->cstRef();
        if (cstRef.isInvalid())
            continue;

        if (!payload->seen.contains(cstRef))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_complete_enum_not_exhaustive, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, enumTypeRef);

            diag.addNote(DiagnosticId::sema_note_switch_missing_enum_value);
            diag.last().addArgument(Diagnostic::ARG_VALUE, value->getFullScopedName(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

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
        SemaNodeView exprView = sema.nodeViewTypeConstant(nodeExprRef);
        RESULT_VERIFY(SemaCheck::isValueOrTypeInfo(sema, exprView));

        const TypeInfo& type      = sema.typeMgr().get(exprView.typeRef());
        const TypeRef   ultimate  = type.unwrap(sema.ctx(), exprView.typeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& finalType = sema.typeMgr().get(ultimate);
        if (!finalType.isIntLike() && !finalType.isFloat() && !finalType.isBool() && !finalType.isString() && !finalType.isTypeInfo())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_invalid_type, nodeExprRef);

        sema.payload<SwitchPayload>(sema.curNodeRef())->exprTypeRef = exprView.typeRef();

        if (type.isEnum())
        {
            SemaFrame frame = sema.frame();
            frame.pushBindingType(exprView.typeRef());
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

    const SwitchPayload* payload       = sema.payload<SwitchPayload>(switchRef);
    const TypeRef        switchTypeRef = payload->exprTypeRef;
    if (switchTypeRef.isInvalid())
        return Result::Continue;

    // This is a 'default' case (no expressions). Validate default-specific rules once.
    if (!spanExprRef.isValid() && childRef == nodeBodyRef)
    {
        SwitchPayload* switchPayload = sema.payload<SwitchPayload>(switchRef);
        SWC_ASSERT(switchPayload);

        const AstNodeRef caseRef = sema.frame().currentSwitchCase();

        // A 'default' with a 'where' clause is only considered an unconditional default if the
        // where clause is a constant 'true'. Otherwise, it behaves like a conditional default
        // and does not participate in duplicate-default checks.
        bool isUnconditionalDefault = nodeWhereRef.isInvalid();
        if (!isUnconditionalDefault)
        {
            const SemaNodeView whereView = sema.nodeViewConstant(nodeWhereRef);
            isUnconditionalDefault       = whereView.cstRef() == sema.cstMgr().cstTrue();
        }
        if (!isUnconditionalDefault)
            return Result::Continue;

        if (switchPayload->isComplete)
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_complete_has_default, caseRef);

        if (!switchPayload->firstDefaultRef.isValid())
        {
            switchPayload->firstDefaultRef = caseRef;
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_multiple_default, caseRef);
        diag.addNote(DiagnosticId::sema_note_previous_default_case);
        diag.last().addSpan(sema.node(switchPayload->firstDefaultRef).codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    // Only touch case expressions (not the statements in the case body).
    if (!spanExprRef.isValid())
        return Result::Continue;

    SmallVector<AstNodeRef> expressions;
    sema.ast().appendNodes(expressions, spanExprRef);
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
        SemaNodeView view = sema.nodeViewNodeTypeConstant(nodeRef);
        return Cast::cast(sema, view, switchTypeRef, CastKind::Implicit);
    }

    Result checkCaseExprIsConst(Sema& sema, const AstNodeRef& exprRef)
    {
        const SemaNodeView exprView = sema.nodeViewConstant(exprRef);
        if (exprView.cstRef().isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_switch_case_not_const, exprRef);
        return Result::Continue;
    }

    Result handleRangeCaseExpr(Sema& sema, const AstNodeRef& rangeRef, TypeRef switchTypeRef)
    {
        const AstRangeExpr* range = sema.node(rangeRef).cast<AstRangeExpr>();
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
            const SemaNodeView whereView = sema.nodeViewConstant(whereRef);
            if (whereView.cstRef().isInvalid() || whereView.cstRef() != sema.cstMgr().cstTrue())
                return Result::Continue;
        }

        SwitchPayload* seenSet = sema.payload<SwitchPayload>(switchRef);
        SWC_ASSERT(seenSet);

        const SemaNodeView exprView = sema.nodeViewConstant(caseExprRef);

        const auto it = seenSet->seen.find(exprView.cstRef());
        if (it == seenSet->seen.end())
        {
            seenSet->seen.emplace(exprView.cstRef(), caseExprRef);
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_switch_case_duplicate, caseExprRef);
        diag.addArgument(Diagnostic::ARG_VALUE, sema.cstMgr().get(exprView.cstRef()).toString(sema.ctx()));
        diag.addNote(DiagnosticId::sema_note_previous_case_value);
        diag.last().addSpan(sema.node(it->second).codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }
}

Result AstSwitchCaseStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeWhereRef)
    {
        SemaNodeView nodeView = sema.nodeViewNodeTypeConstant(nodeWhereRef);
        return Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition);
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
        SemaNodeView nodeView = sema.nodeViewNodeTypeConstant(childRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
        return Result::Continue;
    }

    // Range expression
    if (sema.node(childRef).is(AstNodeId::RangeExpr))
        return handleRangeCaseExpr(sema, childRef, switchTypeRef);

    // Be sure it's a value
    SemaNodeView exprView = sema.nodeViewTypeConstant(childRef);
    RESULT_VERIFY(SemaCheck::isValueOrTypeInfo(sema, exprView));

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

    SmallVector<AstNodeRef>  stmts;
    const AstSwitchCaseStmt* caseStmt = sema.node(caseRef).cast<AstSwitchCaseStmt>();
    const AstSwitchCaseBody* caseBody = sema.node(caseStmt->nodeBodyRef).cast<AstSwitchCaseBody>();

    sema.ast().appendNodes(stmts, caseBody->spanChildrenRef);
    const auto itStmt = std::ranges::find(stmts, sema.curNodeRef());
    if (itStmt == stmts.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());
    if (itStmt + 1 != stmts.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_not_last_stmt, sema.curNodeRef());

    const AstNodeRef     switchRef  = sema.frame().currentSwitch();
    const AstSwitchStmt* switchStmt = sema.node(switchRef).cast<AstSwitchStmt>();
    if (!switchStmt->spanChildrenRef.isValid())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());

    SmallVector<AstNodeRef> cases;
    sema.ast().appendNodes(cases, switchStmt->spanChildrenRef);
    const auto itCase = std::ranges::find(cases, caseRef);
    if (itCase == cases.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_outside_switch_case, sema.curNodeRef());
    if (itCase + 1 == cases.end())
        return SemaError::raise(sema, DiagnosticId::sema_err_fallthrough_in_last_case, sema.curNodeRef());

    return Result::Continue;
}

SWC_END_NAMESPACE();


