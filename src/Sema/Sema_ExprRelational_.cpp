#include "pch.h"

#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/ConstantManager.h"
#include "Sema/Sema.h"
#include "TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldEqual(Sema& sema, const AstRelationalExpr& node)
    {
        const auto&    ctx       = sema.ctx();
        const AstNode& leftNode  = sema.node(node.nodeLeftRef);
        const AstNode& rightNode = sema.node(node.nodeRightRef);

        if (leftNode.getSemaConstantRef() == rightNode.getSemaConstantRef())
            return sema.constMgr().addConstant(ctx, ConstantValue::makeBool(ctx, true));

        const ConstantValue& leftCst      = leftNode.getSemaConstant(ctx);
        const ConstantValue& rightCst     = rightNode.getSemaConstant(ctx);
        const TypeInfoRef    leftTypeRef  = leftCst.typeRef();
        const TypeInfoRef    rightTypeRef = rightCst.typeRef();
        const TypeInfo&      leftType     = sema.typeMgr().get(leftTypeRef);
        const TypeInfo&      rightType    = sema.typeMgr().get(rightTypeRef);

        if (leftType.isIntFloat() && rightType.isIntFloat() && leftTypeRef != rightTypeRef)
        {
            const TypeInfoRef promotedTypeRef = sema.typeMgr().promote(leftTypeRef, rightTypeRef);
            const TypeInfo&   promotedType    = sema.typeMgr().get(promotedTypeRef);

            CastContext castCtx;
            castCtx.kind                   = CastKind::Promotion;
            castCtx.errorNodeRef           = node.nodeLeftRef;
            const auto leftPromotedCstRef  = sema.cast(castCtx, leftNode.getSemaConstantRef(), promotedTypeRef);
            const auto rightPromotedCstRef = sema.cast(castCtx, rightNode.getSemaConstantRef(), promotedTypeRef);

            const bool result = (leftPromotedCstRef == rightPromotedCstRef);
            return sema.constMgr().addConstant(ctx, ConstantValue::makeBool(ctx, result));
        }

        const bool result = (leftCst == rightCst);
        return sema.constMgr().addConstant(ctx, ConstantValue::makeBool(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstRelationalExpr& node)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, node);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& node)
    {
        const auto&          ctx          = sema.ctx();
        const AstNode&       leftNode     = sema.node(node.nodeLeftRef);
        const AstNode&       rightNode    = sema.node(node.nodeRightRef);
        const ConstantValue& leftCst      = leftNode.getSemaConstant(ctx);
        const ConstantValue& rightCst     = rightNode.getSemaConstant(ctx);
        const TypeInfoRef    leftTypeRef  = leftCst.typeRef();
        const TypeInfoRef    rightTypeRef = rightCst.typeRef();

        if (leftTypeRef == rightTypeRef)
            return Result::Success;

        const TypeInfo& leftType  = sema.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType = sema.typeMgr().get(rightTypeRef);

        if (!leftType.isIntFloat())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_unary_operand_type, node.nodeLeftRef);
            diag.addArgument(Diagnostic::ARG_TYPE, leftTypeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!rightType.isIntFloat())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_unary_operand_type, node.nodeRightRef);
            diag.addArgument(Diagnostic::ARG_TYPE, rightTypeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Success;
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& node)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return checkEqualEqual(sema, node);
            default:
                break;
        }

        sema.raiseInternalError(node);
        return Result::Error;
    }
}

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema)
{
    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    const AstNode& nodeLeft  = sema.node(nodeLeftRef);
    const AstNode& nodeRight = sema.node(nodeRightRef);
    if (nodeLeft.isSemaConstant() && nodeRight.isSemaConstant())
    {
        const auto cst = constantFold(sema, tok.id, *this);
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
