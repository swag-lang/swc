#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantFold.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result checkPlusPlus(Sema& sema, const AstBinaryExpr& node, const SemaNodeView&, const SemaNodeView&)
    {
        RESULT_VERIFY(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Zero));
        RESULT_VERIFY(SemaCheck::isConstant(sema, node.nodeLeftRef));
        RESULT_VERIFY(SemaCheck::isConstant(sema, node.nodeRightRef));
        return Result::Continue;
    }

    Result checkOp(Sema& sema, AstNodeRef nodeRef, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        RESULT_VERIFY(SemaHelpers::checkBinaryOperandTypes(sema, nodeRef, op, node.nodeLeftRef, node.nodeRightRef, nodeLeftView, nodeRightView));

        switch (op)
        {
            case TokenId::SymSlash:
            case TokenId::SymPercent:
                RESULT_VERIFY(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Promote));
                break;

            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
                RESULT_VERIFY(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Wrap | AstModifierFlagsE::Promote));
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                RESULT_VERIFY(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Zero));
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result promote(Sema& sema, TokenId op, AstNodeRef nodeRef, const AstBinaryExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        if (op == TokenId::SymPipe || op == TokenId::SymAmpersand || op == TokenId::SymCircumflex)
        {
            if (nodeLeftView.type->isEnum())
            {
                if (!nodeLeftView.type->isEnumFlags())
                    return SemaError::raiseInvalidOpEnum(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                Cast::convertEnumToUnderlying(sema, nodeLeftView);
            }

            if (nodeRightView.type->isEnum())
            {
                if (!nodeRightView.type->isEnumFlags())
                    return SemaError::raiseInvalidOpEnum(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);
                Cast::convertEnumToUnderlying(sema, nodeRightView);
            }
        }

        return Result::Continue;
    }

    Result castAndResultType(Sema& sema, TokenId op, const AstBinaryExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        // Constant folding
        if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
        {
            ConstantRef result;
            RESULT_VERIFY(ConstantFold::binary(sema, result, op, node, nodeLeftView, nodeRightView));
            sema.setConstant(sema.curNodeRef(), result);
            return Result::Continue;
        }

        TypeRef resultTypeRef = nodeLeftView.typeRef;
        switch (op)
        {
            case TokenId::SymPlus:
                if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isBlockPointer())
                {
                    RESULT_VERIFY(Cast::cast(sema, nodeLeftView, sema.typeMgr().typeS64(), CastKind::Implicit));
                    nodeRightView.compute(sema, node.nodeRightRef);
                    resultTypeRef = nodeRightView.typeRef;
                }
                else if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isScalarNumeric())
                {
                    RESULT_VERIFY(Cast::cast(sema, nodeRightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                    nodeLeftView.compute(sema, node.nodeLeftRef);
                    resultTypeRef = nodeLeftView.typeRef;
                }
                break;

            case TokenId::SymMinus:
                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isScalarNumeric())
                {
                    RESULT_VERIFY(Cast::cast(sema, nodeRightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                    nodeLeftView.compute(sema, node.nodeLeftRef);
                    resultTypeRef = nodeLeftView.typeRef;
                }
                else if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isBlockPointer())
                {
                    resultTypeRef = sema.typeMgr().typeS64();
                }
                break;

            default:
                break;
        }

        switch (op)
        {
            case TokenId::SymPlusPlus:
                break;

            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
            case TokenId::SymSlash:
            case TokenId::SymPercent:
            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                RESULT_VERIFY(SemaHelpers::castBinaryRightToLeft(sema, op, sema.curNodeRef(), nodeLeftView, nodeRightView, CastKind::Implicit));
                break;

            default:
                break;
        }

        sema.setType(sema.curNodeRef(), resultTypeRef);
        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, AstNodeRef nodeRef, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeRightView.cstRef.isValid())
            RESULT_VERIFY(ConstantFold::checkRightConstant(sema, op, sema.curNodeRef(), nodeRightView));

        switch (op)
        {
            case TokenId::SymPlusPlus:
                return checkPlusPlus(sema, node, nodeLeftView, nodeRightView);

            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
            case TokenId::SymSlash:
            case TokenId::SymPercent:
            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                return checkOp(sema, nodeRef, op, node, nodeLeftView, nodeRightView);

            default:
                SWC_INTERNAL_ERROR(sema.ctx());
        }
    }
}

Result AstBinaryExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef)
    {
        const SemaNodeView nodeLeftView(sema, nodeLeftRef);
        auto               frame = sema.frame();
        frame.pushBindingType(nodeLeftView.typeRef);
        sema.pushFramePopOnPostChild(frame, nodeRightRef);
    }

    return Result::Continue;
}

Result AstBinaryExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeLeftView(sema, nodeLeftRef);
    SemaNodeView nodeRightView(sema, nodeRightRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeLeftView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));
    sema.setIsValue(*this);

    const Token& tok = sema.token(codeRef());

    RESULT_VERIFY(promote(sema, tok.id, sema.curNodeRef(), *this, nodeLeftView, nodeRightView));
    RESULT_VERIFY(check(sema, tok.id, sema.curNodeRef(), *this, nodeLeftView, nodeRightView));
    RESULT_VERIFY(castAndResultType(sema, tok.id, *this, nodeLeftView, nodeRightView));

    return Result::Continue;
}

SWC_END_NAMESPACE();
