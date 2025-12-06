#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/SemaInfo.h"
#include "Sema/SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct BinaryOperands
    {
        SemaNodeView nodeLeftView;
        SemaNodeView nodeRightView;
        BinaryOperands(Sema& sema, const AstBinaryExpr& node) :
            nodeLeftView(sema, node.nodeLeftRef),
            nodeRightView(sema, node.nodeRightRef)
        {
        }
    };

    bool promoteConstantsIfNeeded(Sema& sema, const AstBinaryExpr& node, const BinaryOperands& ops, ConstantRef& leftRef, ConstantRef& rightRef)
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

    ConstantRef constantFoldPlus(Sema& sema, const AstBinaryExpr& node, const BinaryOperands& ops)
    {
        const auto& ctx = sema.ctx();

        auto leftCstRef  = ops.nodeLeftView.cstRef;
        auto rightCstRef = ops.nodeRightView.cstRef;

        if (!promoteConstantsIfNeeded(sema, node, ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        const TypeInfo& type = ops.nodeLeftView.cst->type(sema.ctx());
        if (type.isFloat())
        {
            auto val1 = leftCst.getFloat();
            val1.add(rightCst.getFloat());
            return sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, val1, type.floatBits()));
        }

        return ConstantRef::invalid();
    }

    ConstantRef constantFoldPlusPlus(Sema& sema, const AstBinaryExpr&, const BinaryOperands& ops)
    {
        const auto& ctx    = sema.ctx();
        Utf8        result = ops.nodeLeftView.cst->toString();
        result += ops.nodeRightView.cst->toString();
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstBinaryExpr& node, const BinaryOperands& ops)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, node, ops);
            case TokenId::SymPlus:
                return constantFoldPlus(sema, node, ops);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkPlusPlus(const Sema& sema, const AstBinaryExpr& node, const BinaryOperands&)
    {
        if (!sema.hasConstant(node.nodeLeftRef))
        {
            sema.raiseExprNotConst(node.nodeLeftRef);
            return Result::Error;
        }

        if (!sema.hasConstant(node.nodeRightRef))
        {
            sema.raiseExprNotConst(node.nodeRightRef);
            return Result::Error;
        }

        return Result::Success;
    }

    Result checkPlus(Sema& sema, const AstBinaryExpr& node, const BinaryOperands& ops)
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

    Result check(Sema& sema, TokenId op, const AstBinaryExpr& expr, const BinaryOperands& ops)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return checkPlusPlus(sema, expr, ops);
            case TokenId::SymPlus:
                return checkPlus(sema, expr, ops);
            default:
                break;
        }

        sema.raiseInternalError(expr);
        return Result::Error;
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(Sema& sema) const
{
    const BinaryOperands ops(sema, *this);

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
            sema.semaInfo().setConstant(sema.curNodeRef(), cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
