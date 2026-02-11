#include "pch.h"
#include "Compiler/Sema/Constant/ConstantFold.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result constantFoldPlus(Sema& sema, ConstantRef& result, const SemaNodeView& nodeView)
    {
        auto& ctx = sema.ctx();

        if (nodeView.type->isInt())
        {
            ApsInt value = nodeView.cst->getInt();
            value.setUnsigned(true);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, nodeView.type->payloadIntBits(), TypeInfo::Sign::Unsigned));
            return Result::Continue;
        }

        result = nodeView.cstRef;
        return Result::Continue;
    }

    Result constantFoldMinus(Sema& sema, ConstantRef& result, const AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (nodeView.node->is(AstNodeId::SuffixLiteral))
        {
            result = nodeView.cstRef;
            return Result::Continue;
        }

        auto& ctx = sema.ctx();
        if (nodeView.type->isInt())
        {
            ApsInt value = nodeView.cst->getInt();

            bool overflow = false;
            value.negate(overflow);
            if (overflow)
                return SemaError::raiseLiteralOverflow(sema, nodeView.nodeRef, *nodeView.cst, nodeView.typeRef);

            value.setUnsigned(false);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, nodeView.type->payloadIntBits(), TypeInfo::Sign::Signed));
            return Result::Continue;
        }

        if (nodeView.type->isFloat())
        {
            ApFloat value = nodeView.cst->getFloat();
            value.negate();
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, value, nodeView.type->payloadFloatBits()));
            return Result::Continue;
        }

        return Result::Error;
    }

    Result constantFoldBang(Sema& sema, ConstantRef& result, const SemaNodeView& nodeView)
    {
        const auto& cstMgr = sema.cstMgr();

        if (nodeView.cst->isBool())
        {
            result = cstMgr.cstNegBool(nodeView.cstRef);
            return Result::Continue;
        }

        if (nodeView.cst->isInt())
        {
            result = cstMgr.cstBool(nodeView.cst->getInt().isZero());
            return Result::Continue;
        }

        if (nodeView.cst->isChar())
        {
            result = cstMgr.cstBool(nodeView.cst->getChar());
            return Result::Continue;
        }

        if (nodeView.cst->isRune())
        {
            result = cstMgr.cstBool(nodeView.cst->getRune());
            return Result::Continue;
        }

        if (nodeView.cst->isString())
        {
            result = cstMgr.cstFalse();
            return Result::Continue;
        }

        SWC_INTERNAL_ERROR(sema.ctx());
    }

    Result constantFoldTilde(Sema& sema, ConstantRef& result, const AstUnaryExpr&, const SemaNodeView& nodeView)
    {
        auto&  ctx   = sema.ctx();
        ApsInt value = nodeView.cst->getInt();
        value.invertAllBits();
        result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, nodeView.type->payloadIntBits(), nodeView.type->payloadIntSign()));
        return Result::Continue;
    }

    Result constantFoldPlusPlus(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto& ctx = sema.ctx();
        Utf8  str = nodeLeftView.cst->toString(ctx);
        str += nodeRightView.cst->toString(ctx);
        result = sema.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, str));
        return Result::Continue;
    }

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
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_integer_overflow, node);
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

    Result constantFoldEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        if (nodeLeftView.type->isTypeValue() && nodeRightView.type->isTypeValue())
        {
            result = sema.cstMgr().cstBool(*nodeLeftView.type == *nodeRightView.type);
            return Result::Continue;
        }

        if (nodeLeftView.type->isAnyTypeInfo(sema.ctx()) && nodeRightView.type->isAnyTypeInfo(sema.ctx()))
        {
            const auto& leftCst  = sema.cstMgr().get(nodeLeftView.cstRef);
            const auto& rightCst = sema.cstMgr().get(nodeRightView.cstRef);
            result               = sema.cstMgr().cstBool(leftCst.getValuePointer() == rightCst.getValuePointer());
            return Result::Continue;
        }

        if (nodeLeftView.cst->isNull() || nodeRightView.cst->isNull())
        {
            result = sema.cstMgr().cstBool(nodeLeftView.cst->isNull() && nodeRightView.cst->isNull());
            return Result::Continue;
        }

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;
        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));

        // For float, we need to compare by values, because two different constants
        // can still have the same value. For example, 0.0 and -0.0 are two different
        // constants but have equal values.
        const auto& left = sema.cstMgr().get(leftCstRef);
        if (left.isFloat())
        {
            const auto& right = sema.cstMgr().get(rightCstRef);
            result            = sema.cstMgr().cstBool(left.eq(right));
            return Result::Continue;
        }

        result = sema.cstMgr().cstBool(leftCstRef == rightCstRef);
        return Result::Continue;
    }

    Result constantFoldLess(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.lt(rightCst));
        return Result::Continue;
    }

    Result constantFoldLessEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.le(rightCst));
        return Result::Continue;
    }

    Result constantFoldGreater(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.gt(rightCst));
        return Result::Continue;
    }

    Result constantFoldGreaterEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.ge(rightCst));
        return Result::Continue;
    }

    Result constantFoldCompareEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        const auto& left  = sema.cstMgr().get(leftCstRef);
        const auto& right = sema.cstMgr().get(rightCstRef);

        int val;
        if (leftCstRef == rightCstRef)
            val = 0;
        else if (left.lt(right))
            val = -1;
        else if (right.lt(left))
            val = 1;
        else
            val = 0;

        result = sema.cstMgr().cstS32(val);
        return Result::Continue;
    }

    Result constantFoldLogical(Sema& sema, ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const ConstantRef leftCstRef  = nodeLeftView.cstRef;
        const ConstantRef rightCstRef = nodeRightView.cstRef;
        const ConstantRef cstFalseRef = sema.cstMgr().cstFalse();
        const ConstantRef cstTrueRef  = sema.cstMgr().cstTrue();

        switch (op)
        {
            case TokenId::KwdAnd:
                if (leftCstRef == cstFalseRef)
                    result = cstFalseRef;
                else if (rightCstRef == cstFalseRef)
                    result = cstFalseRef;
                else
                    result = cstTrueRef;
                return Result::Continue;

            case TokenId::KwdOr:
                if (leftCstRef == cstTrueRef)
                    result = cstTrueRef;
                else if (rightCstRef == cstTrueRef)
                    result = cstTrueRef;
                else
                    result = cstFalseRef;
                return Result::Continue;

            default:
                SWC_UNREACHABLE();
        }
    }
}

namespace ConstantFold
{
    Result unary(Sema& sema, ConstantRef& result, TokenId op, const AstUnaryExpr& node, const SemaNodeView& nodeView)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, result, node, nodeView);
            case TokenId::SymPlus:
                return constantFoldPlus(sema, result, nodeView);
            case TokenId::SymBang:
                return constantFoldBang(sema, result, nodeView);
            case TokenId::SymTilde:
                return constantFoldTilde(sema, result, node, nodeView);
            default:
                break;
        }

        return Result::Error;
    }

    Result binary(Sema& sema, ConstantRef& result, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, result, nodeLeftView, nodeRightView);

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

    Result relational(Sema& sema, ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymBangEqual:
                RESULT_VERIFY(constantFoldEqual(sema, result, nodeLeftView, nodeRightView));
                result = sema.cstMgr().cstNegBool(result);
                return Result::Continue;

            case TokenId::SymLess:
                return constantFoldLess(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymLessEqual:
                return constantFoldLessEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymGreater:
                return constantFoldGreater(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymGreaterEqual:
                return constantFoldGreaterEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymLessEqualGreater:
                return constantFoldCompareEqual(sema, result, nodeLeftView, nodeRightView);

            default:
                return Result::Error;
        }
    }

    Result logical(Sema& sema, ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        return constantFoldLogical(sema, result, op, nodeLeftView, nodeRightView);
    }

    Result checkRightConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView)
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
}

SWC_END_NAMESPACE();
