#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"

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

    bool promoteConstantsIfNeeded(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops, ConstantRef& leftRef, ConstantRef& rightRef)
    {
        if (ops.leftTypeRef == ops.rightTypeRef)
            return true;

        if (ops.leftType->canBePromoted() && ops.rightType->canBePromoted())
        {
            const TypeInfoRef promotedTypeRef = sema.typeMgr().promote(ops.leftTypeRef, ops.rightTypeRef);

            CastContext castCtx;
            castCtx.kind         = CastKind::Promotion;
            castCtx.errorNodeRef = node.nodeLeftRef;

            leftRef = sema.cast(castCtx, ops.nodeLeft->getSemaConstantRef(), promotedTypeRef);
            if (leftRef.isInvalid())
                return false;

            rightRef = sema.cast(castCtx, ops.nodeRight->getSemaConstantRef(), promotedTypeRef);
            if (rightRef.isInvalid())
                return false;

            return true;
        }

        SWC_UNREACHABLE();
    }

    ConstantRef constantFoldEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.leftCstRef == ops.rightCstRef)
            return sema.constMgr().cstTrue();

        auto leftCstRef  = ops.leftCstRef;
        auto rightCstRef = ops.rightCstRef;

        if (!promoteConstantsIfNeeded(sema, node, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        return sema.constMgr().cstBool(leftCstRef == rightCstRef);
    }

    ConstantRef constantFoldLess(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.leftCstRef == ops.rightCstRef)
            return sema.constMgr().cstFalse();

        auto leftCstRef  = ops.leftCstRef;
        auto rightCstRef = ops.rightCstRef;

        if (!promoteConstantsIfNeeded(sema, node, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        const auto& leftCst  = sema.constMgr().get(leftCstRef);
        const auto& rightCst = sema.constMgr().get(rightCstRef);

        return sema.constMgr().cstBool(leftCst.lt(rightCst));
    }

    ConstantRef constantFoldLessEqual(Sema& sema, const AstRelationalExpr& node, RelationalOperands& ops)
    {
        if (ops.leftCstRef == ops.rightCstRef)
            return sema.constMgr().cstTrue();
        return constantFoldLess(sema, node, ops);
    }

    ConstantRef constantFoldGreater(Sema& sema, const AstRelationalExpr& node, RelationalOperands& ops)
    {
        RelationalOperands swapped = ops;
        std::swap(swapped.nodeLeft, swapped.nodeRight);
        std::swap(swapped.leftCstRef, swapped.rightCstRef);
        std::swap(swapped.leftTypeRef, swapped.rightTypeRef);
        std::swap(swapped.leftType, swapped.rightType);
        return constantFoldLess(sema, node, swapped);
    }

    ConstantRef constantFoldGreaterEqual(Sema& sema, const AstRelationalExpr& node, RelationalOperands& ops)
    {
        if (ops.leftCstRef == ops.rightCstRef)
            return sema.constMgr().cstTrue();

        const ConstantRef lt = constantFoldLess(sema, node, ops);
        if (lt.isInvalid())
            return ConstantRef::invalid();

        return sema.constMgr().cstNegBool(lt);
    }

    ConstantRef constantFoldCompareEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        auto leftCstRef  = ops.leftCstRef;
        auto rightCstRef = ops.rightCstRef;

        if (!promoteConstantsIfNeeded(sema, node, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        const auto& left  = sema.constMgr().get(leftCstRef);
        const auto& right = sema.constMgr().get(rightCstRef);

        int result;
        if (leftCstRef == rightCstRef)
            result = 0;
        else if (left.lt(right))
            result = -1;
        else if (right.lt(left))
            result = 1;
        else
            result = 0;

        return sema.constMgr().cstS32(result);
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

            case TokenId::SymBangEqual:
                return sema.constMgr().cstNegBool(constantFoldEqual(sema, node, ops));

            case TokenId::SymLess:
                return constantFoldLess(sema, node, ops);

            case TokenId::SymLessEqual:
                return constantFoldLessEqual(sema, node, ops);

            case TokenId::SymGreater:
                return constantFoldGreater(sema, node, ops);

            case TokenId::SymGreaterEqual:
                return constantFoldGreaterEqual(sema, node, ops);

            case TokenId::SymLessEqualGreater:
                return constantFoldCompareEqual(sema, node, ops);

            default:
                return ConstantRef::invalid();
        }
    }

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.leftTypeRef == ops.rightTypeRef)
            return Result::Success;

        if (!ops.leftType->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeLeftRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.leftTypeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!ops.rightType->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeRightRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.rightTypeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Success;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (!ops.leftType->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeLeftRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.leftTypeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!ops.rightType->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeRightRef, node.srcViewRef(), node.tokRef());
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
            case TokenId::SymBangEqual:
                return checkEqualEqual(sema, node, ops);

            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
            case TokenId::SymLessEqualGreater:
                return checkCompareEqual(sema, node, ops);

            default:
                sema.raiseInternalError(node);
                return Result::Error;
        }
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
