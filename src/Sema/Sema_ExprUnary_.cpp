#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaInfo.h"
#include "Sema/SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct UnaryOperands
    {
        SemaNodeView nodeView;
        UnaryOperands(Sema& sema, const AstUnaryExpr& node) :
            nodeView(sema, node.nodeExprRef)
        {
        }
    };

    ConstantRef constantFoldMinus(Sema& sema, const AstUnaryExpr& node, const UnaryOperands& ops)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (ops.nodeView.node->is(AstNodeId::SuffixLiteral))
            return sema.constantRefOf(node.nodeExprRef);

        const auto& ctx = sema.ctx();
        if (ops.nodeView.type->isInt())
        {
            ApsInt value = ops.nodeView.cst->getInt();

            bool overflow = false;
            value.negate(overflow);
            if (overflow)
            {
                sema.raiseLiteralOverflow(node.nodeExprRef, sema.typeRefOf(node.nodeExprRef));
                return ConstantRef::invalid();
            }

            value.setUnsigned(false);
            return sema.constMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.nodeView.type->intBits()));
        }

        if (ops.nodeView.type->isFloat())
        {
            ApFloat value = ops.nodeView.cst->getFloat();
            value.negate();
            return sema.constMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, value, ops.nodeView.type->floatBits()));
        }

        return ConstantRef::invalid();
    }

    ConstantRef constantFoldBang(Sema& sema, const AstUnaryExpr&, const UnaryOperands& ops)
    {
        if (ops.nodeView.cst->isBool())
            return sema.constMgr().cstNegBool(ops.nodeView.cstRef);
        SWC_ASSERT(ops.nodeView.cst->isInt());
        return sema.constMgr().cstBool(!ops.nodeView.cst->getInt().isZero());
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstUnaryExpr& node, const UnaryOperands& ops)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, node, ops);
            case TokenId::SymBang:
                return constantFoldBang(sema, node, ops);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    void reportInvalidType(Sema& sema, const AstUnaryExpr& expr, const UnaryOperands& ops)
    {
        auto diag = sema.reportError(DiagnosticId::sema_err_unary_operand_type, expr.srcViewRef(), expr.tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeView.typeRef);
        diag.report(sema.ctx());
    }

    Result checkMinus(Sema& sema, const AstUnaryExpr& expr, const UnaryOperands& ops)
    {
        if (ops.nodeView.type->isFloat() || ops.nodeView.type->isIntSigned() || ops.nodeView.type->isInt0())
            return Result::Success;

        if (ops.nodeView.type->isIntUnsigned())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeView.typeRef);
            diag.report(sema.ctx());
        }
        else
        {
            reportInvalidType(sema, expr, ops);
        }

        return Result::Error;
    }

    Result checkBang(Sema& sema, const AstUnaryExpr& expr, const UnaryOperands& ops)
    {
        if (ops.nodeView.type->isBool() || ops.nodeView.type->isInt())
            return Result::Success;

        reportInvalidType(sema, expr, ops);
        return Result::Error;
    }

    Result check(Sema& sema, TokenId op, const AstUnaryExpr& node, const UnaryOperands& ops)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return checkMinus(sema, node, ops);
            case TokenId::SymBang:
                return checkBang(sema, node, ops);
            default:
                break;
        }

        sema.raiseInternalError(node);
        return Result::Error;
    }
}

AstVisitStepResult AstUnaryExpr::semaPostNode(Sema& sema) const
{
    const UnaryOperands ops(sema, *this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (sema.hasConstant(nodeExprRef))
    {
        const auto cst = constantFold(sema, tok.id, *this, ops);
        if (cst.isValid())
        {
            sema.setConstant(sema.curNodeRef(), cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
