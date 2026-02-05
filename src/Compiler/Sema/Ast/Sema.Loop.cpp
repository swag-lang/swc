#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"

SWC_BEGIN_NAMESPACE();

Result AstForStmt::semaPreNode(Sema& sema) const
{
    return SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Reverse);
}

Result AstForStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeWhereRef || (childRef == nodeBodyRef && nodeWhereRef.isInvalid()))
    {
        // TODO
        if (sema.file()->isRuntime())
            return Result::SkipChildren;

        SemaFrame frame = sema.frame();
        frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Loop);
        sema.pushFramePopOnPostNode(frame);
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);

        // Create a variable
        if (tokNameRef.isValid())
        {
            auto& symVar = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
            symVar.registerAttributes(sema);
            symVar.setDeclared(sema.ctx());
            RESULT_VERIFY(Match::ghosting(sema, symVar));

            const SemaNodeView nodeView(sema, nodeExprRef);
            symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
            symVar.setTypeRef(nodeView.typeRef);
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
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
        if (nodeView.node->isNot(AstNodeId::RangeExpr) && !nodeView.type->isInt())
        {
            const AstNode& exprNode   = sema.node(nodeExprRef);
            auto [countRef, countPtr] = sema.ast().makeNode<AstNodeId::CountOfExpr>(exprNode.tokRef());
            countPtr->nodeExprRef     = nodeExprRef;
            RESULT_VERIFY(SemaHelpers::intrinsicCountOf(sema, countRef, nodeExprRef));
            sema.setSubstitute(nodeExprRef, countRef);
        }
        else if (!nodeView.type->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_countof_type, nodeView.nodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    if (childRef == nodeWhereRef)
    {
        SemaNodeView nodeView(sema, nodeWhereRef);
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
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
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));
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

SWC_END_NAMESPACE();
