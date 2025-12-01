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
    struct RelationalOperands
    {
        SemaNodeView nodeLeftView;
        SemaNodeView nodeRightView;
        RelationalOperands(Sema& sema, const AstRelationalExpr& node) :
            nodeLeftView(sema, node.nodeLeftRef),
            nodeRightView(sema, node.nodeRightRef)
        {
        }
    };

    bool
    promoteConstantsIfNeeded(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops, ConstantRef& leftRef, ConstantRef& rightRef)
    {
        if (ops.nodeLeftView.typeRef == ops.nodeRightView.typeRef)
            return true;

        if (ops.nodeLeftView.type->canBePromoted() && ops.nodeRightView.type->canBePromoted())
        {
            const TypeRef promotedTypeRef = sema.typeMgr().promote(ops.nodeLeftView.typeRef, ops.nodeRightView.typeRef);

            CastContext castCtx;
            castCtx.kind         = CastKind::Promotion;
            castCtx.errorNodeRef = node.nodeLeftRef;

            leftRef = sema.cast(castCtx, sema.constantRefOf(node.nodeLeftRef), promotedTypeRef);
            if (leftRef.isInvalid())
                return false;

            rightRef = sema.cast(castCtx, sema.constantRefOf(node.nodeRightRef), promotedTypeRef);
            if (rightRef.isInvalid())
                return false;

            return true;
        }

        SWC_UNREACHABLE();
    }

    ConstantRef constantFoldEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.nodeLeftView.cstRef == ops.nodeRightView.cstRef)
            return sema.cstMgr().cstTrue();

        auto leftCstRef  = ops.nodeLeftView.cstRef;
        auto rightCstRef = ops.nodeRightView.cstRef;

        if (!promoteConstantsIfNeeded(sema, node, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        return sema.cstMgr().cstBool(leftCstRef == rightCstRef);
    }

    ConstantRef constantFoldLess(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.nodeLeftView.cstRef == ops.nodeRightView.cstRef)
            return sema.cstMgr().cstFalse();

        auto leftCstRef  = ops.nodeLeftView.cstRef;
        auto rightCstRef = ops.nodeRightView.cstRef;

        if (!promoteConstantsIfNeeded(sema, node, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.lt(rightCst));
    }

    ConstantRef constantFoldLessEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.nodeLeftView.cstRef == ops.nodeRightView.cstRef)
            return sema.cstMgr().cstTrue();
        return constantFoldLess(sema, node, ops);
    }

    ConstantRef constantFoldGreater(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        RelationalOperands swapped = ops;
        std::swap(swapped.nodeLeftView, swapped.nodeRightView);
        return constantFoldLess(sema, node, swapped);
    }

    ConstantRef constantFoldGreaterEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (ops.nodeLeftView.cstRef == ops.nodeRightView.cstRef)
            return sema.cstMgr().cstTrue();

        const ConstantRef lt = constantFoldLess(sema, node, ops);
        if (lt.isInvalid())
            return ConstantRef::invalid();

        return sema.cstMgr().cstNegBool(lt);
    }

    ConstantRef constantFoldCompareEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        auto leftCstRef  = ops.nodeLeftView.cstRef;
        auto rightCstRef = ops.nodeRightView.cstRef;

        if (!promoteConstantsIfNeeded(sema, node, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        const auto& left  = sema.cstMgr().get(leftCstRef);
        const auto& right = sema.cstMgr().get(rightCstRef);

        int result;
        if (leftCstRef == rightCstRef)
            result = 0;
        else if (left.lt(right))
            result = -1;
        else if (right.lt(left))
            result = 1;
        else
            result = 0;

        return sema.cstMgr().cstS32(result);
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, node, ops);

            case TokenId::SymBangEqual:
                return sema.cstMgr().cstNegBool(constantFoldEqual(sema, node, ops));

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
        if (ops.nodeLeftView.typeRef == ops.nodeRightView.typeRef)
            return Result::Success;

        if (!ops.nodeLeftView.type->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeLeftRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeLeftView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!ops.nodeRightView.type->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeRightRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeRightView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Success;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const RelationalOperands& ops)
    {
        if (!ops.nodeLeftView.type->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeLeftRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeLeftView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!ops.nodeRightView.type->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeRightRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeRightView.typeRef);
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

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema) const
{
    const RelationalOperands ops(sema, *this);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (sema.hasConstant(nodeLeftRef) && sema.hasConstant(nodeRightRef))
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
