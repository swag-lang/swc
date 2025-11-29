#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct UnaryOperands
    {
        const AstNode*       node    = nullptr;
        const ConstantValue* cst     = nullptr;
        ConstantRef          cstRef  = ConstantRef::invalid();
        TypeInfoRef          typeRef = TypeInfoRef::invalid();
        const TypeInfo*      type    = nullptr;

        UnaryOperands(Sema& sema, const AstUnaryExpr& expr) :
            node(&sema.node(expr.nodeExprRef)),
            typeRef(node->getNodeTypeRef(sema.ctx())),
            type(&sema.typeMgr().get(typeRef))
        {
        }
    };

    ConstantRef constantFoldMinus(Sema& sema, const AstUnaryExpr& node, const UnaryOperands& ops)
    {
        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (ops.node->is(AstNodeId::SuffixLiteral))
            return ops.node->getSemaConstantRef();

        const auto& ctx = sema.ctx();
        if (ops.type->isInt())
        {
            ApsInt cpyInt = ops.cst->getInt();

            bool overflow = false;
            cpyInt.negate(overflow);
            if (overflow)
            {
                sema.raiseLiteralOverflow(node.nodeExprRef, ops.node->getNodeTypeRef(sema.ctx()));
                return ConstantRef::invalid();
            }

            cpyInt.setUnsigned(false);
            return sema.constMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpyInt, ops.type->intBits()));
        }

        if (ops.type->isFloat())
        {
            ApFloat cpyFloat = ops.cst->getFloat();
            cpyFloat.negate();
            return sema.constMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, cpyFloat, ops.type->floatBits()));
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
        ops.cstRef = ops.node->getSemaConstantRef();
        ops.cst    = &ops.node->getSemaConstant(sema.ctx());

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
            auto diag = sema.reportError(DiagnosticId::sema_err_unary_operand_type, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
            diag.report(sema.ctx());
        }

        return Result::Error;
    }

    Result checkBang(Sema& sema, const AstUnaryExpr& expr, const UnaryOperands& ops)
    {
        if (ops.type->isBool() || ops.type->isInt())
            return Result::Success;

        auto diag = sema.reportError(DiagnosticId::sema_err_unary_operand_type, expr.srcViewRef(), expr.tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, ops.typeRef);
        diag.report(sema.ctx());
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

AstVisitStepResult AstUnaryExpr::semaPostNode(Sema& sema)
{
    UnaryOperands ops(sema, *this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (ops.node->isSemaConstant())
    {
        const auto cst = constantFold(sema, tok.id, *this, ops);
        if (cst.isValid())
        {
            setSemaConstant(cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
