#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldMinus(Sema& sema, const AstUnaryExpr& node)
    {
        const auto&          ctx      = sema.ctx();
        const AstNode&       nodeExpr = sema.node(node.nodeExprRef);
        const ConstantValue& cst      = nodeExpr.getSemaConstant(ctx);

        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (nodeExpr.is(AstNodeId::SuffixLiteral))
            return nodeExpr.getSemaConstantRef();

        const TypeInfo& type = sema.typeMgr().get(cst.typeRef());
        if (type.isInt())
        {
            ApsInt cpyInt = cst.getInt();

            bool overflow = false;
            cpyInt.negate(overflow);
            if (overflow)
            {
                sema.raiseLiteralOverflow(node.nodeExprRef, nodeExpr.getNodeTypeRef(sema.ctx()));
                return ConstantRef::invalid();
            }

            cpyInt.setUnsigned(false);
            return sema.constMgr().addConstant(ctx, ConstantValue::makeInt(ctx, cpyInt, type.intBits()));
        }

        if (type.isFloat())
        {
            ApFloat cpyFloat = cst.getFloat();
            cpyFloat.negate();
            return sema.constMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, cpyFloat, type.floatBits()));
        }

        return ConstantRef::invalid();
    }

    Result checkMinus(Sema& sema, const AstUnaryExpr& expr)
    {
        const AstNode&    node    = sema.node(expr.nodeExprRef);
        const TypeInfoRef typeRef = node.getNodeTypeRef(sema.ctx());
        const TypeInfo&   type    = sema.typeMgr().get(typeRef);

        if (type.isFloat() || type.isIntSigned() || type.isInt0())
            return Result::Success;

        if (type.isIntUnsigned())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_negate_unsigned, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
            diag.report(sema.ctx());
        }
        else
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_unary_operand_type, expr.srcViewRef(), expr.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
            diag.report(sema.ctx());
        }

        return Result::Error;
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstUnaryExpr& node)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, node);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result check(Sema& sema, TokenId op, const AstUnaryExpr& expr)
    {
        switch (op)
        {
            case TokenId::SymMinus:
                return checkMinus(sema, expr);
            default:
                break;
        }

        sema.raiseInternalError(expr);
        return Result::Error;
    }
}

AstVisitStepResult AstUnaryExpr::semaPostNode(Sema& sema)
{
    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    const AstNode& node = sema.node(nodeExprRef);
    if (node.isSemaConstant())
    {
        const auto cst = constantFold(sema, tok.id, *this);
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
