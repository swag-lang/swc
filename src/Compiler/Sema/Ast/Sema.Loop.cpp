#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result checkForCountExpr(Sema& sema, AstNodeRef nodeRef)
    {
        const SemaNodeView nodeView(sema, nodeRef);

        if (nodeView.type && nodeView.type->isInt())
            return Result::Continue;

        bool countOfOk = false;
        if (nodeView.type)
        {
            if (nodeView.cst && (nodeView.cst->isString() || nodeView.cst->isSlice()))
                countOfOk = true;
            else if (nodeView.type->isEnum())
            {
                RESULT_VERIFY(sema.waitCompleted(nodeView.type, nodeView.nodeRef));
                countOfOk = true;
            }
            else if (nodeView.type->isAnyString() || nodeView.type->isArray() || nodeView.type->isSlice())
            {
                countOfOk = true;
            }
        }

        if (countOfOk)
            return Result::Continue;

        if (!nodeView.type)
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_countof, nodeView.nodeRef);

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, nodeView.nodeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    TypeRef getForIndexType(Sema& sema, AstNodeRef nodeRef)
    {
        const SemaNodeView nodeView(sema, nodeRef);

        if (nodeView.type && nodeView.type->isInt())
            return nodeView.typeRef;

        return sema.typeMgr().typeU64();
    }
}

Result AstForStmt::semaPreNode(Sema& sema) const
{
    return SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Reverse);
}

Result AstForStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeBodyRef)
    {
        // TODO
        if (sema.file()->isRuntime())
            return Result::SkipChildren;

        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);

        if (tokNameRef.isValid())
        {
            const TypeRef indexTypeRef = getForIndexType(sema, nodeExprRef);

            auto& symVar = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
            symVar.registerAttributes(sema);
            symVar.setDeclared(sema.ctx());
            RESULT_VERIFY(Match::ghosting(sema, symVar));

            symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
            symVar.setTypeRef(indexTypeRef);
            symVar.setTyped(sema.ctx());
            symVar.setCompleted(sema.ctx());
        }
    }

    return Result::Continue;
}

Result AstForStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
    {
        const SemaNodeView nodeView(sema, nodeExprRef);
        if (const auto* range = nodeView.node->safeCast<AstRangeExpr>())
        {
            if (range->nodeExprDownRef.isValid())
                RESULT_VERIFY(checkForCountExpr(sema, range->nodeExprDownRef));
            if (range->nodeExprUpRef.isValid())
                RESULT_VERIFY(checkForCountExpr(sema, range->nodeExprUpRef));
        }
        else
        {
            RESULT_VERIFY(checkForCountExpr(sema, nodeExprRef));
        }
    }

    if (childRef == nodeWhereRef)
    {
        SemaNodeView nodeView(sema, nodeWhereRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
    }

    return Result::Continue;
}

Result AstWhileStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeBodyRef)
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    }

    return Result::Continue;
}

Result AstInfiniteLoopStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeBodyRef)
    {
        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostChild(frame, childRef);
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    }

    return Result::Continue;
}

Result AstWhileStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Ensure while condition is `bool` (or castable to it).
    if (childRef == nodeExprRef)
    {
        SemaNodeView nodeView(sema, nodeExprRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.typeMgr().typeBool(), CastKind::Condition));
    }

    return Result::Continue;
}

Result AstBreakStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().currentBreakableKind() == SemaFrame::BreakContextKind::None)
        return SemaError::raise(sema, DiagnosticId::sema_err_break_outside_breakable, sema.curNodeRef());
    return Result::Continue;
}

Result AstContinueStmt::semaPreNode(Sema& sema)
{
    if (sema.frame().currentBreakableKind() == SemaFrame::BreakContextKind::None)
        return SemaError::raise(sema, DiagnosticId::sema_err_continue_outside_breakable, sema.curNodeRef());
    if (sema.frame().currentBreakableKind() != SemaFrame::BreakContextKind::Loop)
        return SemaError::raise(sema, DiagnosticId::sema_err_continue_not_in_loop, sema.curNodeRef());
    return Result::Continue;
}

Result AstRangeExpr::semaPostNode(Sema& sema) const
{
    SemaNodeView nodeDownView(sema, nodeExprDownRef);
    SemaNodeView nodeUpView(sema, nodeExprUpRef);

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
