#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct RelationalOperands
    {
        const AstNode*       nodeLeft     = nullptr;
        const AstNode*       nodeRight    = nullptr;
        const ConstantValue* leftCst      = nullptr;
        const ConstantValue* rightCst     = nullptr;
        ConstantRef          leftCstRef   = ConstantRef::invalid();
        ConstantRef          rightCstRef  = ConstantRef::invalid();
        TypeInfoRef          leftTypeRef  = TypeInfoRef::invalid();
        TypeInfoRef          rightTypeRef = TypeInfoRef::invalid();
        const TypeInfo*      leftType     = nullptr;
        const TypeInfo*      rightType    = nullptr;

        RelationalOperands(Sema& sema, const AstRelationalExpr& expr) :
            nodeLeft(&sema.node(expr.nodeLeftRef)),
            nodeRight(&sema.node(expr.nodeRightRef)),
            leftTypeRef(nodeLeft->getNodeTypeRef(sema.ctx())),
            rightTypeRef(nodeRight->getNodeTypeRef(sema.ctx())),
            leftType(&sema.typeMgr().get(leftTypeRef)),
            rightType(&sema.typeMgr().get(rightTypeRef))
        {
        }
    };

    ConstantRef constantFoldEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.leftCstRef == ops.rightCstRef)
            return sema.constMgr().cstTrue();

        auto leftCstRef  = ops.leftCstRef;
        auto rightCstRef = ops.rightCstRef;

        if (ops.leftTypeRef != ops.rightTypeRef)
        {
            if (ops.leftType->canBePromoted() && ops.rightType->canBePromoted())
            {
                const TypeInfoRef promotedTypeRef = sema.typeMgr().promote(ops.leftTypeRef, ops.rightTypeRef);

                CastContext castCtx;
                castCtx.kind         = CastKind::Promotion;
                castCtx.errorNodeRef = node.nodeLeftRef;
                leftCstRef           = sema.cast(castCtx, ops.nodeLeft->getSemaConstantRef(), promotedTypeRef);
                if (leftCstRef.isInvalid())
                    return ConstantRef::invalid();
                rightCstRef = sema.cast(castCtx, ops.nodeRight->getSemaConstantRef(), promotedTypeRef);
                if (rightCstRef.isInvalid())
                    return ConstantRef::invalid();
            }
            else
            {
                SWC_UNREACHABLE();
            }
        }

        return sema.constMgr().cstBool(leftCstRef == rightCstRef);
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstRelationalExpr& node, RelationalOperands& ops)
    {
        ops.leftCstRef  = ops.nodeLeft->getSemaConstantRef();
        ops.rightCstRef = ops.nodeRight->getSemaConstantRef();
        ops.leftCst     = &ops.nodeLeft->getSemaConstant(sema.ctx());
        ops.rightCst    = &ops.nodeRight->getSemaConstant(sema.ctx());

        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, node, ops);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.leftTypeRef == ops.rightTypeRef)
            return Result::Success;

        if (!ops.leftType->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeLeftRef);
            diag.addArgument(Diagnostic::ARG_TYPE, ops.leftTypeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!ops.rightType->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeRightRef);
            diag.addArgument(Diagnostic::ARG_TYPE, ops.rightTypeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Success;
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return checkEqualEqual(sema, node, ops);
            default:
                break;
        }

        sema.raiseInternalError(node);
        return Result::Error;
    }
}

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema)
{
    RelationalOperands ops(sema, *this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (ops.nodeLeft->isSemaConstant() && ops.nodeRight->isSemaConstant())
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
