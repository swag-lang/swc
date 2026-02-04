#include "pch.h"
#include "Compiler/Sema/Helpers/SemaBinaryOp.h"
#include "Compiler/Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

namespace SemaBinaryOp
{
    Result checkOperandTypes(Sema& sema, AstNodeRef nodeRef, TokenId op, AstNodeRef leftRef, AstNodeRef rightRef, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        switch (op)
        {
            case TokenId::SymPlus:
                if (leftView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, leftRef, leftView.typeRef);
                if (rightView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, rightRef, rightView.typeRef);

                if (leftView.type->isBlockPointer() && leftView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef);
                if (rightView.type->isBlockPointer() && rightView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef);

                if (leftView.type->isBlockPointer() && rightView.type->isScalarNumeric())
                    return Result::Continue;
                if (leftView.type->isBlockPointer() && rightView.type->isBlockPointer())
                    return Result::Continue;
                if (leftView.type->isScalarNumeric() && rightView.type->isBlockPointer())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, rightView.typeRef);
                break;

            case TokenId::SymMinus:
                if (leftView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, leftRef, leftView.typeRef);
                if (rightView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, nodeRef, rightRef, rightView.typeRef);

                if (leftView.type->isBlockPointer() && leftView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, leftRef, leftView.typeRef);
                if (rightView.type->isBlockPointer() && rightView.type->payloadTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, nodeRef, rightRef, rightView.typeRef);

                if (leftView.type->isBlockPointer() && rightView.type->isScalarNumeric())
                    return Result::Continue;
                if (leftView.type->isBlockPointer() && rightView.type->isBlockPointer())
                    return Result::Continue;
                break;

            default:
                break;
        }

        switch (op)
        {
            case TokenId::SymSlash:
            case TokenId::SymPercent:
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
                if (!leftView.type->isScalarNumeric())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef);
                if (!rightView.type->isScalarNumeric())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, rightView.typeRef);
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                if (!leftView.type->isInt())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, leftRef, leftView.typeRef);
                if (!rightView.type->isInt())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, rightRef, rightView.typeRef);
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result castRightToLeft(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& leftView, SemaNodeView& rightView, CastKind castKind)
    {
        (void) nodeRef;
        switch (op)
        {
            case TokenId::SymPlus:
            case TokenId::SymMinus:
                if (leftView.type->isBlockPointer() && rightView.type->isScalarNumeric())
                {
                    RESULT_VERIFY(Cast::cast(sema, rightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                    return Result::Continue;
                }
                if (leftView.type->isBlockPointer() && rightView.type->isBlockPointer())
                {
                    return Result::Continue;
                }
                break;

            default:
                break;
        }

        RESULT_VERIFY(Cast::cast(sema, rightView, leftView.typeRef, castKind));
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
