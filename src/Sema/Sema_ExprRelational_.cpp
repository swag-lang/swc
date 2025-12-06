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
    ConstantRef constantFoldEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].cstRef == ops.nodeView[1].cstRef)
            return sema.cstMgr().cstTrue();

        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;

        if (!sema.promoteConstants( ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        return sema.cstMgr().cstBool(leftCstRef == rightCstRef);
    }

    ConstantRef constantFoldLess(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].cstRef == ops.nodeView[1].cstRef)
            return sema.cstMgr().cstFalse();

        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;

        if (!sema.promoteConstants(ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.lt(rightCst));
    }

    ConstantRef constantFoldLessEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].cstRef == ops.nodeView[1].cstRef)
            return sema.cstMgr().cstTrue();
        return constantFoldLess(sema, node, ops);
    }

    ConstantRef constantFoldGreater(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        SemaNodeViewList swapped = ops;
        std::swap(swapped.nodeView[0], swapped.nodeView[1]);
        return constantFoldLess(sema, node, swapped);
    }

    ConstantRef constantFoldGreaterEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].cstRef == ops.nodeView[1].cstRef)
            return sema.cstMgr().cstTrue();

        const ConstantRef lt = constantFoldLess(sema, node, ops);
        if (lt.isInvalid())
            return ConstantRef::invalid();

        return sema.cstMgr().cstNegBool(lt);
    }

    ConstantRef constantFoldCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;

        if (!sema.promoteConstants(ops, leftCstRef, rightCstRef))
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

    ConstantRef constantFold(Sema& sema, TokenId op, const AstRelationalExpr& node, const SemaNodeViewList& ops)
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

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].typeRef == ops.nodeView[1].typeRef)
            return Result::Success;

        if (!ops.nodeView[0].type->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeLeftRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeView[0].typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!ops.nodeView[1].type->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeRightRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeView[1].typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Success;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (!ops.nodeView[0].type->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeLeftRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeView[0].typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!ops.nodeView[1].type->canBePromoted())
        {
            auto diag = sema.reportError(DiagnosticId::sema_err_binary_operand_type, node.nodeRightRef, node.srcViewRef(), node.tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, ops.nodeView[1].typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Success;
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& node, const SemaNodeViewList& ops)
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
    const SemaNodeViewList ops(sema, nodeLeftRef, nodeRightRef);

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
