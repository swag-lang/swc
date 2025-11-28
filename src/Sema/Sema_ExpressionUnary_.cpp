#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldUnaryExpr(Sema& sema, TokenId op, AstNodeRef nodeRef)
    {
        const auto&          ctx      = sema.ctx();
        auto&                constMgr = sema.constMgr();
        const AstNode&       node     = sema.node(nodeRef);
        const ConstantValue& cst      = node.getSemaConstant(ctx);

        switch (op)
        {
            case TokenId::SymMinus:
            {
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

            default:
                break;
        }

        return ConstantRef::invalid();
    }
}

AstVisitStepResult AstUnaryExpr::semaPostNode(Sema& sema)
{
    const auto&     tok     = sema.token(srcViewRef(), tokRef());
    const AstNode&  node    = sema.node(nodeExprRef);
    TypeInfoRef     typeRef = node.getNodeTypeRef(sema.ctx());
    const TypeInfo& type    = sema.typeMgr().get(typeRef);

    switch (tok.id)
    {
        case TokenId::SymMinus:
            if (type.isFloat() || type.isIntSigned() || type.isInt0())
                break;
            if (type.isIntUnsigned())
            {
                auto diag = sema.reportError(DiagnosticId::sema_err_negate_unsigned, srcViewRef(), tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
                diag.report(sema.ctx());
            }
            else
            {
                auto diag = sema.reportError(DiagnosticId::sema_err_unary_operand_type, srcViewRef(), tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
                diag.report(sema.ctx());
            }
            return AstVisitStepResult::Stop;

        default:
            sema.raiseInternalError(*this);
            return AstVisitStepResult::Stop;
    }

    if (node.isSemaConstant())
    {
        const auto cst = constantFoldUnaryExpr(sema, tok.id, nodeExprRef);
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
