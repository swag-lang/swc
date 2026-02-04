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
    Result checkRightConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymSlashEqual:
            case TokenId::SymPercentEqual:
                if (nodeRightView.type->isFloat() && nodeRightView.cst->getFloat().isZero())
                    return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef);
                if (nodeRightView.type->isInt() && nodeRightView.cst->getInt().isZero())
                    return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef);
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result castAndResultType(Sema& sema, TokenId op, const AstAssignStmt& node, const SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isScalarNumeric())
                {
                    RESULT_VERIFY(Cast::cast(sema, nodeRightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                    return Result::Continue;
                }
                break;

            default:
                break;
        }

        RESULT_VERIFY(Cast::cast(sema, nodeRightView, nodeLeftView.typeRef, CastKind::Assignment));
        return Result::Continue;
    }

    Result checkCompoundOp(Sema& sema, TokenId op, AstNodeRef nodeRef, const AstAssignStmt& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlusEqual:
                if (nodeLeftView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                if (nodeRightView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);

                if (nodeLeftView.type->isBlockPointer() && nodeLeftView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                if (nodeRightView.type->isBlockPointer() && nodeRightView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);

                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isScalarNumeric())
                    return Result::Continue;
                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isBlockPointer())
                    return Result::Continue;
                if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isBlockPointer())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);
                break;

            case TokenId::SymMinusEqual:
                if (nodeLeftView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                if (nodeRightView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);

                if (nodeLeftView.type->isBlockPointer() && nodeLeftView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                if (nodeRightView.type->isBlockPointer() && nodeRightView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);

                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isScalarNumeric())
                    return Result::Continue;
                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isBlockPointer())
                    return Result::Continue;
                break;

            default:
                break;
        }

        switch (op)
        {
            case TokenId::SymSlashEqual:
            case TokenId::SymPercentEqual:
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
            case TokenId::SymAsteriskEqual:
                if (!nodeLeftView.type->isScalarNumeric())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                if (!nodeRightView.type->isScalarNumeric())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);
                break;

            case TokenId::SymAmpersandEqual:
            case TokenId::SymPipeEqual:
            case TokenId::SymCircumflexEqual:
            case TokenId::SymGreaterGreaterEqual:
            case TokenId::SymLowerLowerEqual:
                if (!nodeLeftView.type->isInt())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                if (!nodeRightView.type->isInt())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, AstNodeRef nodeRef, const AstAssignStmt& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeRightView.cstRef.isValid())
            RESULT_VERIFY(checkRightConstant(sema, op, nodeRef, nodeRightView));

        switch (op)
        {
            case TokenId::SymEqual:
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
            case TokenId::SymAsteriskEqual:
            case TokenId::SymSlashEqual:
            case TokenId::SymAmpersandEqual:
            case TokenId::SymPipeEqual:
            case TokenId::SymCircumflexEqual:
            case TokenId::SymPercentEqual:
            case TokenId::SymLowerLowerEqual:
            case TokenId::SymGreaterGreaterEqual:
                return Result::Continue;

            default:
                return SemaError::raiseInternal(sema, nodeRef);
        }
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
    SemaNodeView       nodeRightView(sema, nodeRightRef);

    // TODO
    if (nodeLeftView.node->srcView(sema.ctx()).file()->isRuntime())
        return Result::Continue;

    const Token& tok = sema.token(codeRef());
    RESULT_VERIFY(SemaCheck::isAssignable(sema, sema.curNodeRef(), nodeLeftView));
    RESULT_VERIFY(check(sema, tok.id, sema.curNodeRef(), *this, nodeLeftView, nodeRightView));

    if (tok.id == TokenId::SymEqual)
    {
        RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeRightView));
    }
    else
    {
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));
        RESULT_VERIFY(checkCompoundOp(sema, tok.id, sema.curNodeRef(), *this, nodeLeftView, nodeRightView));
    }

    RESULT_VERIFY(castAndResultType(sema, tok.id, *this, nodeLeftView, nodeRightView));
    return Result::Continue;
}

SWC_END_NAMESPACE();
