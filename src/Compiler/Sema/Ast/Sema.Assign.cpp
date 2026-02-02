#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Constant.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result checkConstant(Sema& sema, TokenId op, const AstNode& node, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymSlashEqual:
            case TokenId::SymPercentEqual:
                if (nodeRightView.type->isFloat() && nodeRightView.cst->getFloat().isZero())
                    return SemaError::raiseDivZero(sema, node, nodeRightView.nodeRef);
                if (nodeRightView.type->isInt() && nodeRightView.cst->getInt().isZero())
                    return SemaError::raiseDivZero(sema, node, nodeRightView.nodeRef);
                break;

            default:
                break;
        }

        return Result::Continue;
    }
}

Result AstAssignStmt::semaPreNode(Sema& sema) const
{
    RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, AstModifierFlagsE::Zero));
    return Result::Continue;
}

Result AstAssignStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef && nodeRightRef.isValid())
    {
        // Provide a type hint to the RHS: `a = expr` should type `expr` as `typeof(a)` when possible.
        const SemaNodeView leftView(sema, nodeLeftRef);
        if (leftView.typeRef.isValid())
        {
            auto frame = sema.frame();
            frame.pushBindingType(leftView.typeRef);
            sema.pushFramePopOnPostChild(frame, nodeRightRef);
        }
    }

    return Result::Continue;
}

Result AstAssignStmt::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeLeftView(sema, nodeLeftRef);

    // TODO
    if (nodeLeftView.node->srcView(sema.ctx()).file()->isRuntime())
        return Result::Continue;

    // Disallow assignment to immutable lvalues:
    if (nodeLeftView.sym)
    {
        const auto* symVar = nodeLeftView.sym->safeCast<SymbolVariable>();
        if (symVar && symVar->hasExtraFlag(SymbolVariableFlagsE::Let))
        {
            const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_let, srcViewRef(), tokRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        const auto* symConst = nodeLeftView.sym->safeCast<SymbolConstant>();
        if (symConst)
        {
            const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_const, srcViewRef(), tokRef());
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    if (nodeLeftView.type && nodeLeftView.type->isConst())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_immutable, srcViewRef(), tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeLeftView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    // Left must be a l-value
    if (!SemaInfo::isLValue(*nodeLeftView.node))
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_not_lvalue, srcViewRef(), tokRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    // Right must be a value (or a type that can be converted to a value).
    SemaNodeView nodeRightView(sema, nodeRightRef);
    RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeRightView));

    // Cast RHS to LHS type.
    if (nodeLeftView.typeRef.isValid())
        RESULT_VERIFY(Cast::cast(sema, nodeRightView, nodeLeftView.typeRef, CastKind::Initialization));

    // Right is constant
    const Token& tok = sema.token(srcViewRef(), tokRef());
    if (nodeRightView.cstRef.isValid())
    {
        RESULT_VERIFY(checkConstant(sema, tok.id, *this, nodeRightView));
    }

    // Assignment statement has no value. Ensure the current node isn't flagged as a value.
    SemaInfo::removeSemaFlags(*this, NodeSemaFlags::Value);
    return Result::Continue;
}

SWC_END_NAMESPACE();
