#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

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
    // Left must be assignable.
    const SemaNodeView leftView(sema, nodeLeftRef);

    // TODO
    if (leftView.node->srcView(sema.ctx()).file()->isRuntime())
        return Result::Continue;

    if (!SemaInfo::isLValue(*leftView.node))
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_not_lvalue, srcViewRef(), tokRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    // Right must be a value (or a type that can be converted to a value).
    SemaNodeView rightView(sema, nodeRightRef);
    RESULT_VERIFY(SemaCheck::isValueOrType(sema, rightView));

    // Cast RHS to LHS type.
    if (leftView.typeRef.isValid())
        RESULT_VERIFY(Cast::cast(sema, rightView, leftView.typeRef, CastKind::Initialization));

    // Assignment statement has no value. Ensure the current node isn't flagged as a value.
    SemaInfo::removeSemaFlags(*this, NodeSemaFlags::Value);
    return Result::Continue;
}

SWC_END_NAMESPACE();
