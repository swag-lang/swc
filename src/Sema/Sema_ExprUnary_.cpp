#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldMinus(Sema& sema, const AstNode& node, AstNodeRef nodeRef)
    {
        const auto&          ctx      = sema.ctx();
        auto&                constMgr = sema.constMgr();
        const ConstantValue& cst      = node.getSemaConstant(ctx);

        // In the case of a literal with a suffix, it has already been done
        // @MinusLiteralSuffix
        if (node.is(AstNodeId::SuffixLiteral))
            return node.getSemaConstantRef();

        ApsInt cpy = cst.getInt();

        bool overflow = false;
        cpy.negate(overflow);
        if (overflow)
        {
            sema.raiseLiteralOverflow(nodeRef, node.getNodeTypeRef(sema.ctx()));
            return ConstantRef::invalid();
        }

        cpy.setUnsigned(false);
        return constMgr.addConstant(ctx, ConstantValue::makeInt(ctx, cpy, cpy.bitWidth()));
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

    ConstantRef constantFold(Sema& sema, TokenId op, AstNodeRef nodeRef)
    {
        const AstNode& node = sema.node(nodeRef);

        switch (op)
        {
            case TokenId::SymMinus:
                return constantFoldMinus(sema, node, nodeRef);
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
    const auto&       tok     = sema.token(srcViewRef(), tokRef());
    const AstNode&    node    = sema.node(nodeExprRef);
    const TypeInfoRef typeRef = node.getNodeTypeRef(sema.ctx());
    const TypeInfo&   type    = sema.typeMgr().get(typeRef);

    // Type-check
    if (check(sema, tok.id, *this) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (node.isSemaConstant())
    {
        const auto cst = constantFold(sema, tok.id, nodeExprRef);
        if (cst.isValid())
        {
            setSemaConstant(cst);
            return AstVisitStepResult::Continue;
        }
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
