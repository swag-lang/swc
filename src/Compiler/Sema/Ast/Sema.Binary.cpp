#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result constantFoldOp(Sema& sema, ConstantRef& result, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto&       ctx         = sema.ctx();
        ConstantRef leftCstRef  = nodeLeftView.cstRef;
        ConstantRef rightCstRef = nodeRightView.cstRef;

        const bool promote = node.modifierFlags.has(AstModifierFlagsE::Promote);
        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef, promote));

        const ConstantValue& leftCst  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& rightCst = sema.cstMgr().get(rightCstRef);
        const TypeInfo&      type     = leftCst.type(sema.ctx());

        // Wrap and promote modifiers can only be applied to integers
        if (node.modifierFlags.hasAny({AstModifierFlagsE::Wrap, AstModifierFlagsE::Promote}))
        {
            if (!type.isInt())
            {
                const SourceView& srcView = sema.compiler().srcView(node.srcViewRef());
                const TokenRef    mdfRef  = srcView.findRightFrom(node.tokRef(), {TokenId::ModifierWrap, TokenId::ModifierPromote});
                auto              diag    = SemaError::report(sema, DiagnosticId::sema_err_modifier_only_integer, SourceCodeRef{node.srcViewRef(), mdfRef});
                diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        if (type.isFloat())
        {
            auto val1 = leftCst.getFloat();
            switch (op)
            {
                case TokenId::SymPlus:
                    val1.add(rightCst.getFloat());
                    break;
                case TokenId::SymMinus:
                    val1.sub(rightCst.getFloat());
                    break;
                case TokenId::SymAsterisk:
                    val1.mul(rightCst.getFloat());
                    break;
                case TokenId::SymSlash:
                    val1.div(rightCst.getFloat());
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, val1, type.payloadFloatBits()));
            return Result::Continue;
        }

        if (type.isInt())
        {
            ApsInt val1 = leftCst.getInt();
            ApsInt val2 = rightCst.getInt();

            const bool wrap     = node.modifierFlags.has(AstModifierFlagsE::Wrap);
            bool       overflow = false;

            if (type.isIntUnsized())
            {
                val1.setSigned(true);
                val2.setSigned(true);
            }

            switch (op)
            {
                case TokenId::SymPlus:
                    val1.add(val2, overflow);
                    break;
                case TokenId::SymMinus:
                    val1.sub(val2, overflow);
                    break;
                case TokenId::SymAsterisk:
                    val1.mul(val2, overflow);
                    break;

                case TokenId::SymSlash:
                    val1.div(val2, overflow);
                    break;

                case TokenId::SymPercent:
                    val1.mod(val2, overflow);
                    break;

                case TokenId::SymAmpersand:
                    val1.bitwiseAnd(val2);
                    break;
                case TokenId::SymPipe:
                    val1.bitwiseOr(val2);
                    break;
                case TokenId::SymCircumflex:
                    val1.bitwiseXor(val2);
                    break;

                case TokenId::SymGreaterGreater:
                    if (val2.isNegative())
                    {
                        auto diag = SemaError::report(sema, DiagnosticId::sema_err_negative_shift, node.nodeRightRef);
                        diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                        diag.report(sema.ctx());
                        return Result::Error;
                    }

                    if (!val2.fits64())
                        overflow = true;
                    else
                        val1.shiftRight(val2.asI64());
                    break;

                case TokenId::SymLowerLower:
                    if (val2.isNegative())
                    {
                        auto diag = SemaError::report(sema, DiagnosticId::sema_err_negative_shift, node.nodeRightRef);
                        diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                        diag.report(sema.ctx());
                        return Result::Error;
                    }

                    if (!val2.fits64())
                        overflow = true;
                    else
                        val1.shiftLeft(val2.asI64(), overflow);
                    overflow = false;
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            if (!wrap && type.payloadIntBits() != 0 && overflow)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_integer_overflow, node.codeRef());
                diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                diag.addArgument(Diagnostic::ARG_LEFT, leftCstRef);
                diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                diag.report(sema.ctx());
                return Result::Error;
            }

            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, val1, type.payloadIntBits(), type.payloadIntSign()));
            return Result::Continue;
        }

        return Result::Error;
    }

    Result constantFoldPlusPlus(Sema& sema, ConstantRef& result, const AstBinaryExpr&, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto& ctx = sema.ctx();
        Utf8  str = nodeLeftView.cst->toString(ctx);
        str += nodeRightView.cst->toString(ctx);
        result = sema.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, str));
        return Result::Continue;
    }

    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, result, node, nodeLeftView, nodeRightView);

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
                return constantFoldOp(sema, result, op, node, nodeLeftView, nodeRightView);

            default:
                break;
        }

        return Result::Error;
    }

    Result checkPlusPlus(Sema& sema, const AstBinaryExpr& node, const SemaNodeView&, const SemaNodeView&)
    {
        RESULT_VERIFY(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Zero));
        RESULT_VERIFY(SemaCheck::isConstant(sema, node.nodeLeftRef));
        RESULT_VERIFY(SemaCheck::isConstant(sema, node.nodeRightRef));
        return Result::Continue;
    }

    Result checkOp(Sema& sema, AstNodeRef nodeRef, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlus:
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
                if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isBlockPointer())
                    return Result::Continue;
                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isBlockPointer())
                    return Result::Continue;
                break;

            case TokenId::SymMinus:
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
            case TokenId::SymSlash:
            case TokenId::SymPercent:
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
                if (!nodeLeftView.type->isScalarNumeric())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                if (!nodeRightView.type->isScalarNumeric())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                if (!nodeLeftView.type->isInt())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef);
                if (!nodeRightView.type->isInt())
                    return SemaError::raiseBinaryOperandType(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef);
                break;

            default:
                break;
        }

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

    Result promote(Sema& sema, AstNodeRef nodeRef, TokenId op, const AstBinaryExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
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

    Result checkConstant(Sema& sema, AstNodeRef nodeRef, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymSlash:
            case TokenId::SymPercent:
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

    Result check(Sema& sema, AstNodeRef nodeRef, TokenId op, const AstBinaryExpr& expr, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return checkPlusPlus(sema, expr, nodeLeftView, nodeRightView);

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
                return checkOp(sema, nodeRef, op, expr, nodeLeftView, nodeRightView);

            default:
                return SemaError::raiseInternal(sema, nodeRef);
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
    const AstNodeRef nodeRef = sema.curNodeRef();
    SemaNodeView nodeLeftView(sema, nodeLeftRef);
    SemaNodeView nodeRightView(sema, nodeRightRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeLeftView.nodeRef));
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));
    sema.setIsValue(*this);

    // Force types
    const Token& tok = sema.token(codeRef());
    RESULT_VERIFY(promote(sema, nodeRef, tok.id, *this, nodeLeftView, nodeRightView));

    // Type-check
    RESULT_VERIFY(check(sema, nodeRef, tok.id, *this, nodeLeftView, nodeRightView));

    // Set the result type
    TypeRef resultTypeRef = nodeLeftView.typeRef;
    if (tok.id == TokenId::SymPlus)
    {
        if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isBlockPointer())
            resultTypeRef = nodeRightView.typeRef;
    }
    else if (tok.id == TokenId::SymMinus)
    {
        if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isBlockPointer())
            resultTypeRef = sema.typeMgr().typeInt(64, TypeInfo::Sign::Signed);
    }

    sema.setType(sema.curNodeRef(), resultTypeRef);

    // Right is constant
    if (nodeRightView.cstRef.isValid())
    {
        RESULT_VERIFY(checkConstant(sema, nodeRef, tok.id, *this, nodeRightView));
    }

    // Constant folding
    if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
    {
        ConstantRef result;
        RESULT_VERIFY(constantFold(sema, result, tok.id, *this, nodeLeftView, nodeRightView));
        sema.setConstant(sema.curNodeRef(), result);
    }

    return Result::Continue;
}

Result AstBinaryConditionalExpr::semaPostNode(Sema& sema)
{
    // TODO
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstS32(1));
    sema.setIsValue(*this);
    return Result::Continue;
}

SWC_END_NAMESPACE();
