#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"

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

Result AstAssignStmt::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeLeftView(sema, nodeLeftRef);

    // TODO
    if (nodeLeftView.node->srcView(sema.ctx()).file()->isRuntime())
        return Result::Continue;

    // Check LHS assignability
    RESULT_VERIFY(SemaCheck::isAssignable(sema, *this, nodeLeftView));

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

    return Result::Continue;
}

SWC_END_NAMESPACE();
