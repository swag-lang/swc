#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaInfo.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct UnaryOperands
    {
        const AstNode*       nodeExpr = nullptr;
        const ConstantValue* cst      = nullptr;
        ConstantRef          cstRef   = ConstantRef::invalid();
        TypeRef              typeRef  = TypeRef::invalid();
        const TypeInfo*      type     = nullptr;

        UnaryOperands(Sema& sema, const AstUnaryExpr& node) :
            nodeExpr(&sema.node(node.nodeExprRef)),
            typeRef(sema.semaInfo().getTypeRef(sema.ctx(), node.nodeExprRef)),
            type(&sema.typeMgr().get(typeRef))
        {
        }
    };

    ConstantRef constantFoldMinus(Sema& sema, const AstUnaryExpr& node, const UnaryOperands& ops)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (ops.nodeExpr->is(AstNodeId::SuffixLiteral))
            return sema.semaInfo().getConstantRef(node.nodeExprRef);

        const auto& ctx = sema.ctx();
        if (ops.type->isInt())
        {
            ApsInt value = ops.cst->getInt();

            bool overflow = false;
            value.negate(overflow);
            if (overflow)
            {
                sema.raiseLiteralOverflow(node.nodeExprRef, sema.semaInfo().getTypeRef(sema.ctx(), node.nodeExprRef));
                return ConstantRef::invalid();
            }

            value.setUnsigned(false);
            return sema.constMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, ops.type->intBits()));
        }

        if (ops.type->isFloat())
        {
            ApFloat value = ops.cst->getFloat();
            value.negate();
            return sema.constMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, value, ops.type->floatBits()));
        }

        return ConstantRef::invalid();
    }

    ConstantRef constantFoldBang(Sema& sema, const AstUnaryExpr& node, const UnaryOperands& ops)
    {
        if (ops.cst->isBool())
            return sema.constMgr().cstNegBool(ops.cstRef);
        SWC_ASSERT(ops.cst->isInt());
        return sema.constMgr().cstBool(!ops.cst->getInt().isZero());
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstUnaryExpr& node, UnaryOperands& ops)
    {
        ops.cstRef = sema.semaInfo().getConstantRef(node.nodeExprRef);
        ops.cst    = &sema.semaInfo().getConstant(sema.ctx(), node.nodeExprRef);

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
        diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
        diag.report(sema.ctx());
    }

    Result checkMinus(Sema& sema, const AstUnaryExpr& expr, const UnaryOperands& ops)
    {
        if (ops.type->isFloat() || ops.type->isIntSigned() || ops.type->isInt0())
            return Result::Success;

        if (ops.type->isIntUnsigned())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
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
        if (ops.type->isBool() || ops.type->isInt())
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
    UnaryOperands ops(sema, *this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (sema.semaInfo().hasConstant(nodeExprRef))
    {
        const auto cst = constantFold(sema, tok.id, *this, ops);
        if (cst.isValid())
        {
            sema.semaInfo().setConstant(sema.currentNodeRef(), cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
