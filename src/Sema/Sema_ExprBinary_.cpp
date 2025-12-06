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
    ConstantRef constantFoldOp(Sema& sema, TokenId op, const AstBinaryExpr& node, const SemaNodeViewList& ops)
    {
        const auto& ctx         = sema.ctx();
        ConstantRef leftCstRef  = ops.nodeView[0].cstRef;
        ConstantRef rightCstRef = ops.nodeView[1].cstRef;

        if (!sema.promoteConstantsIfNeeded(ops, leftCstRef, rightCstRef))
            return ConstantRef::invalid();

        const ConstantValue& leftCst  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& rightCst = sema.cstMgr().get(rightCstRef);

        const TypeInfo& type = leftCst.type(sema.ctx());
        if (type.isFloat())
        {
            auto val1 = leftCst.getFloat();
            switch (op)
            {
                case TokenId::SymPlus:
                    val1.add(rightCst.getFloat());
                    break;
                case TokenId::SymMinus:
                    val1.sub(rightCst.getFloat());
                    break;
                case TokenId::SymAsterisk:
                    val1.mul(rightCst.getFloat());
                    break;
                case TokenId::SymSlash:
                    if (rightCst.getFloat().isZero())
                    {
                        auto diag = sema.reportError(DiagnosticId::sema_err_division_zero, ops.nodeView[1].nodeRef, node.srcViewRef(), node.tokRef());
                        diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                        diag.report(sema.ctx());
                        return ConstantRef::invalid();
                    }

                    val1.div(rightCst.getFloat());
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            return sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, val1, type.floatBits()));
        }

        if (type.isInt())
        {
            ApsInt        val1     = leftCst.getInt();
            const ApsInt& val2     = rightCst.getInt();
            bool          overflow = false;

            switch (op)
            {
                case TokenId::SymPlus:
                    val1.add(val2, overflow);
                    break;

                case TokenId::SymMinus:
                    val1.sub(val2, overflow);
                    break;

                case TokenId::SymAsterisk:
                    val1.mul(val2, overflow);
                    break;

                case TokenId::SymSlash:
                    if (val2.isZero())
                    {
                        auto diag = sema.reportError(DiagnosticId::sema_err_division_zero, ops.nodeView[1].nodeRef, node.srcViewRef(), node.tokRef());
                        diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                        diag.report(sema.ctx());
                        return ConstantRef::invalid();
                    }

                    val1.div(val2, overflow);
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            if (overflow)
            {
                auto diag = sema.reportError(DiagnosticId::sema_err_integer_overflow, node.srcViewRef(), node.tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                diag.report(sema.ctx());
                return ConstantRef::invalid();
            }

            return sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, val1, type.intBits()));
        }

        return ConstantRef::invalid();
    }

    ConstantRef constantFoldPlusPlus(Sema& sema, const AstBinaryExpr&, const SemaNodeViewList& ops)
    {
        const auto& ctx    = sema.ctx();
        Utf8        result = ops.nodeView[0].cst->toString();
        result += ops.nodeView[1].cst->toString();
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstBinaryExpr& node, const SemaNodeViewList& ops)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, node, ops);
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
            case TokenId::SymSlash:
                return constantFoldOp(sema, op, node, ops);
            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkPlusPlus(const Sema& sema, const AstBinaryExpr& node, const SemaNodeViewList&)
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

    Result checkOp(Sema& sema, const AstBinaryExpr& node, const SemaNodeViewList& ops)
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

    Result check(Sema& sema, TokenId op, const AstBinaryExpr& expr, const SemaNodeViewList& ops)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return checkPlusPlus(sema, expr, ops);
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
            case TokenId::SymSlash:
                return checkOp(sema, expr, ops);
            default:
                break;
        }

        sema.raiseInternalError(expr);
        return Result::Error;
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(Sema& sema) const
{
    const SemaNodeViewList ops(sema, nodeLeftRef, nodeRightRef);

    // Type-check
    const Token& tok = sema.token(srcViewRef(), tokRef());
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
