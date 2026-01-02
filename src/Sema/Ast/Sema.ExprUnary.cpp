#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldPlus(Sema& sema, const SemaNodeView& ops)
    {
        const auto& ctx = sema.ctx();

        if (ops.type->isInt())
        {
            ApsInt value = ops.cst->getInt();
            value.setUnsigned(true);
            return sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), TypeInfo::Sign::Unsigned));
        }

        return ops.cstRef;
    }

    ConstantRef constantFoldMinus(Sema& sema, const SemaNodeView& ops)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (ops.node->is(AstNodeId::SuffixLiteral))
            return sema.constantRefOf(ops.nodeRef);

        const auto& ctx = sema.ctx();
        if (ops.type->isInt())
        {
            ApsInt value = ops.cst->getInt();

            bool overflow = false;
            value.negate(overflow);
            if (overflow)
            {
                SemaError::raiseLiteralOverflow(sema, ops.nodeRef, *ops.cst, ops.typeRef);
                return ConstantRef::invalid();
            }

            value.setUnsigned(false);
            return sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), TypeInfo::Sign::Signed));
        }

        if (ops.type->isFloat())
        {
            ApFloat value = ops.cst->getFloat();
            value.negate();
            return sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, value, ops.type->floatBits()));
        }

        return ConstantRef::invalid();
    }

    ConstantRef constantFoldBang(Sema& sema, const AstUnaryExpr&, const SemaNodeView& ops)
    {
        if (ops.cst->isBool())
            return sema.cstMgr().cstNegBool(ops.cstRef);
        SWC_ASSERT(ops.cst->isInt());
        return sema.cstMgr().cstBool(ops.cst->getInt().isZero());
    }

    ConstantRef constantFoldTilde(Sema& sema, const AstUnaryExpr&, const SemaNodeView& ops)
    {
        if (!ops.type->isInt())
            return ConstantRef::invalid();

        const auto& ctx   = sema.ctx();
        ApsInt      value = ops.cst->getInt();

        value.invertAllBits();

        return sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits(), ops.type->intSign()));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstUnaryExpr& node, const SemaNodeView& ops)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, ops);
            case TokenId::SymPlus:
                return constantFoldPlus(sema, ops);
            case TokenId::SymBang:
                return constantFoldBang(sema, node, ops);
            case TokenId::SymTilde:
                return constantFoldTilde(sema, node, ops);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    void reportInvalidType(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_unary_operand_type, expr.srcViewRef(), expr.tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
        diag.report(sema.ctx());
    }

    Result checkMinus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isFloat() || ops.type->isIntSigned() || ops.type->isIntUnsized())
            return Result::Success;

        if (ops.type->isIntUnsigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
            diag.report(sema.ctx());
        }
        else
        {
            reportInvalidType(sema, expr, ops);
        }

        return Result::Error;
    }

    Result checkPlus(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isFloat() || ops.type->isIntUnsigned() || ops.type->isIntUnsized())
            return Result::Success;

        if (ops.type->isIntSigned())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
            diag.report(sema.ctx());
        }
        else
        {
            reportInvalidType(sema, expr, ops);
        }

        return Result::Error;
    }

    Result checkBang(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isBool() || ops.type->isInt())
            return Result::Success;

        reportInvalidType(sema, expr, ops);
        return Result::Error;
    }

    Result checkTilde(Sema& sema, const AstUnaryExpr& expr, const SemaNodeView& ops)
    {
        if (ops.type->isInt())
            return Result::Success;

        reportInvalidType(sema, expr, ops);
        return Result::Error;
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
            default:
                break;
        }

        SemaError::raiseInternal(sema, node);
        return Result::Error;
    }
}

AstStepResult AstUnaryExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView ops(sema, nodeExprRef);

    // Value-check
    if (SemaCheck::isValueExpr(sema, nodeExprRef) != Result::Success)
        return AstStepResult::Stop;
    SemaInfo::addSemaFlags(*this, NodeSemaFlags::ValueExpr);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstStepResult::Stop;

    // Constant folding
    if (sema.hasConstant(nodeExprRef))
    {
        const ConstantRef cst = constantFold(sema, tok.id, *this, ops);
        if (cst.isValid())
        {
            sema.setConstant(sema.curNodeRef(), cst);
            return AstStepResult::Continue;
        }

        return AstStepResult::Stop;
    }

    SemaError::raiseInternal(sema, *this);
    return AstStepResult::Stop;
}

SWC_END_NAMESPACE()
