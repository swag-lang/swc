#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaCast.h"
#include "Sema/SemaInfo.h"
#include "Sema/SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].cstRef == ops.nodeView[1].cstRef)
            return sema.cstMgr().cstTrue();
        if (ops.nodeView[0].type->isTypeInfo() && ops.nodeView[1].type->isTypeInfo())
            return sema.cstMgr().cstBool(*ops.nodeView[0].type == *ops.nodeView[1].type);

        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;
        if (!SemaCast::promoteConstants(sema, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        // For float, we need to compare by values, because two different constants
        // can still have the same value. For example, 0.0 and -0.0 are two different
        // constants but have equal values.
        const auto& left = sema.cstMgr().get(leftCstRef);
        if (left.isFloat())
        {
            const auto& right = sema.cstMgr().get(rightCstRef);
            return sema.cstMgr().cstBool(left.eq(right));
        }

        return sema.cstMgr().cstBool(leftCstRef == rightCstRef);
    }

    ConstantRef constantFoldLess(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].cstRef == ops.nodeView[1].cstRef)
            return sema.cstMgr().cstFalse();

        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;

        if (!SemaCast::promoteConstants(sema, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();
        if (leftCstRef == rightCstRef)
            return sema.cstMgr().cstFalse();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.lt(rightCst));
    }

    ConstantRef constantFoldLessEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].cstRef == ops.nodeView[1].cstRef)
            return sema.cstMgr().cstTrue();

        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;

        if (!SemaCast::promoteConstants(sema, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();
        if (leftCstRef == rightCstRef)
            return sema.cstMgr().cstTrue();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.le(rightCst));
    }

    ConstantRef constantFoldGreater(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;

        if (!SemaCast::promoteConstants(sema, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();
        if (leftCstRef == rightCstRef)
            return sema.cstMgr().cstFalse();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.gt(rightCst));
    }

    ConstantRef constantFoldGreaterEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].cstRef == ops.nodeView[1].cstRef)
            return sema.cstMgr().cstTrue();

        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;

        if (!SemaCast::promoteConstants(sema, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();
        if (leftCstRef == rightCstRef)
            return sema.cstMgr().cstTrue();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.ge(rightCst));
    }

    ConstantRef constantFoldCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        auto leftCstRef  = ops.nodeView[0].cstRef;
        auto rightCstRef = ops.nodeView[1].cstRef;

        if (!SemaCast::promoteConstants(sema, ops, leftCstRef, rightCstRef))
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
        if (ops.nodeView[0].type->isScalarNumeric() && ops.nodeView[1].type->isScalarNumeric())
            return Result::Success;
        if (ops.nodeView[0].type->isTypeInfo() && ops.nodeView[1].type->isTypeInfo())
            return Result::Success;

        auto diag = sema.reportError(DiagnosticId::sema_err_compare_operand_type, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_LEFT, ops.nodeView[0].typeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, ops.nodeView[1].typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.nodeView[0].type->isScalarNumeric() && ops.nodeView[1].type->isScalarNumeric())
            return Result::Success;

        auto diag = sema.reportError(DiagnosticId::sema_err_compare_operand_type, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_LEFT, ops.nodeView[0].typeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, ops.nodeView[1].typeRef);
        diag.report(sema.ctx());
        return Result::Error;
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
