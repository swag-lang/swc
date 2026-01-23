#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Main/CompilerInstance.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaInfo.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result constantFoldOp(Sema& sema, ConstantRef& result, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const auto& ctx         = sema.ctx();
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
                auto              diag    = SemaError::report(sema, DiagnosticId::sema_err_modifier_only_integer, node.srcViewRef(), mdfRef);
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
                    if (rightCst.getFloat().isZero())
                        return SemaError::raiseDivZero(sema, node, nodeRightView.nodeRef, leftCst.typeRef());
                    val1.div(rightCst.getFloat());
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, val1, type.floatBits()));
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
                    if (val2.isZero())
                    {
                        SemaError::raiseDivZero(sema, node, nodeRightView.nodeRef, leftCst.typeRef());
                        return Result::Error;
                    }

                    val1.div(val2, overflow);
                    break;

                case TokenId::SymPercent:
                    if (val2.isZero())
                    {
                        SemaError::raiseDivZero(sema, node, nodeRightView.nodeRef, leftCst.typeRef());
                        return Result::Error;
                    }

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

            if (!wrap && type.intBits() != 0 && overflow)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_integer_overflow, node.srcViewRef(), node.tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                diag.addArgument(Diagnostic::ARG_LEFT, leftCstRef);
                diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                diag.report(sema.ctx());
                return Result::Error;
            }

            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, val1, type.intBits(), type.intSign()));
            return Result::Continue;
        }

        return Result::Error;
    }

    Result constantFoldPlusPlus(Sema& sema, ConstantRef& result, const AstBinaryExpr&, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const auto& ctx = sema.ctx();

        Utf8 str = nodeLeftView.cst->toString(ctx);
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

    Result checkOp(Sema& sema, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlus:
                if (nodeLeftView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                if (nodeRightView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, node, node.nodeRightRef, nodeRightView.typeRef);

                if (nodeLeftView.type->isBlockPointer() && nodeLeftView.type->underlyingTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                if (nodeRightView.type->isBlockPointer() && nodeRightView.type->underlyingTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, node, node.nodeRightRef, nodeRightView.typeRef);

                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isScalarNumeric())
                    return Result::Continue;
                if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isBlockPointer())
                    return Result::Continue;
                if (nodeLeftView.type->isBlockPointer() && nodeRightView.type->isBlockPointer())
                    return Result::Continue;
                break;

            case TokenId::SymMinus:
                if (nodeLeftView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                if (nodeRightView.type->isValuePointer())
                    return SemaError::raisePointerArithmeticValuePointer(sema, node, node.nodeRightRef, nodeRightView.typeRef);

                if (nodeLeftView.type->isBlockPointer() && nodeLeftView.type->underlyingTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                if (nodeRightView.type->isBlockPointer() && nodeRightView.type->underlyingTypeRef() == sema.typeMgr().typeVoid())
                    return SemaError::raisePointerArithmeticVoidPointer(sema, node, node.nodeRightRef, nodeRightView.typeRef);

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
                    return SemaError::raiseBinaryOperandType(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                if (!nodeRightView.type->isScalarNumeric())
                    return SemaError::raiseBinaryOperandType(sema, node, node.nodeRightRef, nodeRightView.typeRef);
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                if (!nodeLeftView.type->isInt())
                    return SemaError::raiseBinaryOperandType(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                if (!nodeRightView.type->isInt())
                    return SemaError::raiseBinaryOperandType(sema, node, node.nodeRightRef, nodeRightView.typeRef);
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

    Result promote(Sema& sema, TokenId op, const AstBinaryExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        if (op == TokenId::SymPipe || op == TokenId::SymAmpersand || op == TokenId::SymCircumflex)
        {
            if (nodeLeftView.type->isEnum())
            {
                if (!nodeLeftView.type->isEnumFlags())
                    return SemaError::raiseInvalidOpEnum(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                Cast::convertEnumToUnderlying(sema, nodeLeftView);
            }

            if (nodeRightView.type->isEnum())
            {
                if (!nodeRightView.type->isEnumFlags())
                    return SemaError::raiseInvalidOpEnum(sema, node, node.nodeRightRef, nodeRightView.typeRef);
                Cast::convertEnumToUnderlying(sema, nodeRightView);
            }
        }

        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, const AstBinaryExpr& expr, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
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
                return checkOp(sema, op, expr, nodeLeftView, nodeRightView);

            default:
                return SemaError::raiseInternal(sema, expr);
        }
    }
}

Result AstBinaryExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef)
    {
        const SemaNodeView nodeLeftView(sema, nodeLeftRef);
        if (nodeLeftView.typeRef.isValid())
            sema.frame().setTypeHint(nodeLeftView.typeRef);
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
    SemaInfo::setIsValue(*this);

    // Force types
    const Token& tok = sema.token(srcViewRef(), tokRef());
    RESULT_VERIFY(promote(sema, tok.id, *this, nodeLeftView, nodeRightView));

    // Type-check
    RESULT_VERIFY(check(sema, tok.id, *this, nodeLeftView, nodeRightView));

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

    // Constant folding
    if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
    {
        ConstantRef result;
        RESULT_VERIFY(constantFold(sema, result, tok.id, *this, nodeLeftView, nodeRightView));
        sema.semaInfo().setConstant(sema.curNodeRef(), result);
    }

    return Result::Continue;
}

Result AstBinaryConditionalExpr::semaPostNode(Sema& sema)
{
    // TODO
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstS32(1));
    SemaInfo::addSemaFlags(sema.node(sema.curNodeRef()), NodeSemaFlags::Value);
    return Result::Continue;
}

SWC_END_NAMESPACE();
