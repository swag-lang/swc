#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    Result constantFoldPlus(Sema& sema, ConstantRef& result, const SemaNodeView& ops)
    {
        const auto& ctx = sema.ctx();

        if (ops.type->isInt())
        {
            ApsInt value = ops.cst->getInt();
            value.setUnsigned(true);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), TypeInfo::Sign::Unsigned));
            return Result::Continue;
        }

        result = ops.cstRef;
        return Result::Continue;
    }

    Result constantFoldMinus(Sema& sema, ConstantRef& result, const SemaNodeView& ops)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (ops.node->is(AstNodeId::SuffixLiteral))
        {
            result = sema.constantRefOf(ops.nodeRef);
            return Result::Continue;
        }

        const auto& ctx = sema.ctx();
        if (ops.type->isInt())
        {
            ApsInt value = ops.cst->getInt();

            bool overflow = false;
            value.negate(overflow);
            if (overflow)
                return SemaError::raiseLiteralOverflow(sema, ops.nodeRef, *ops.cst, ops.typeRef);

            value.setUnsigned(false);
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), TypeInfo::Sign::Signed));
            return Result::Continue;
        }

        if (ops.type->isFloat())
        {
            ApFloat value = ops.cst->getFloat();
            value.negate();
            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, value, ops.type->floatBits()));
            return Result::Continue;
        }

        return Result::Stop;
    }

    Result constantFoldBang(Sema& sema, ConstantRef& result, const AstUnaryExpr&, const SemaNodeView& ops)
    {
        if (ops.cst->isBool())
        {
            result = sema.cstMgr().cstNegBool(ops.cstRef);
            return Result::Continue;
        }

        SWC_ASSERT(ops.cst->isInt());
        result = sema.cstMgr().cstBool(ops.cst->getInt().isZero());
        return Result::Continue;
    }

    Result constantFoldTilde(Sema& sema, ConstantRef& result, const AstUnaryExpr&, const SemaNodeView& ops)
    {
        const auto& ctx = sema.ctx();

        ApsInt value = ops.cst->getInt();
        value.invertAllBits();
        result = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), ops.type->intSign()));
        return Result::Continue;
    }

    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const AstUnaryExpr& node, const SemaNodeView& ops)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, result, ops);
            case TokenId::SymPlus:
                return constantFoldPlus(sema, result, ops);
            case TokenId::SymBang:
                return constantFoldBang(sema, result, node, ops);
            case TokenId::SymTilde:
                return constantFoldTilde(sema, result, node, ops);
            default:
                break;
        }

        return Result::Stop;
    }

    Result reportInvalidType(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_unary_operand_type, expr.srcViewRef(), expr.tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
        diag.report(sema.ctx());
        return Result::Stop;
    }

    Result checkMinus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isFloat() || ops.type->isIntSigned() || ops.type->isIntUnsized())
            return Result::Continue;

        if (ops.type->isIntUnsigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
            diag.report(sema.ctx());
            return Result::Stop;
        }

        return reportInvalidType(sema, expr, ops);
    }

    Result checkPlus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isFloat() || ops.type->isIntUnsigned() || ops.type->isIntUnsized())
            return Result::Continue;

        if (ops.type->isIntSigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
            diag.report(sema.ctx());
            return Result::Stop;
        }

        return reportInvalidType(sema, expr, ops);
    }

    Result checkBang(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isBool() || ops.type->isInt())
            return Result::Continue;
        return reportInvalidType(sema, expr, ops);
    }

    Result checkTilde(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isInt())
            return Result::Continue;
        return reportInvalidType(sema, expr, ops);
    }

    Result checkTakeAddress(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, const AstUnaryExpr& node, const SemaNodeView& ops)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return checkMinus(sema, node, ops);
            case TokenId::SymPlus:
                return checkPlus(sema, node, ops);
            case TokenId::SymBang:
                return checkBang(sema, node, ops);
            case TokenId::SymTilde:
                return checkTilde(sema, node, ops);
            case TokenId::SymAmpersand:
                return checkTakeAddress(sema, node, ops);

            case TokenId::KwdDRef:
            case TokenId::KwdMoveRef:
                // TODO
                return Result::Continue;

            default:
                return SemaError::raiseInternal(sema, node);
        }
    }
}

Result AstUnaryExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView ops(sema, nodeExprRef);

    // Value-check
    RESULT_VERIFY(SemaCheck::isValueExpr(sema, nodeExprRef));
    SemaInfo::addSemaFlags(*this, NodeSemaFlags::ValueExpr);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    RESULT_VERIFY(check(sema, tok.id, *this, ops));

    // Constant folding
    if (sema.hasConstant(nodeExprRef))
    {
        ConstantRef result;
        RESULT_VERIFY(constantFold(sema, result, tok.id, *this, ops));
        sema.setConstant(sema.curNodeRef(), result);
        return Result::Continue;
    }

    switch (tok.id)
    {
        case TokenId::KwdDRef:
        case TokenId::KwdMoveRef:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            break;

        case TokenId::SymAmpersand:
        {
            const TypeInfo& ty      = TypeInfo::makeValuePointer(ops.typeRef);
            const TypeRef   typeRef = sema.typeMgr().addType(ty);
            sema.setType(sema.curNodeRef(), typeRef);
            break;
        }

        default:
            sema.setType(sema.curNodeRef(), ops.typeRef);
            break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE()
