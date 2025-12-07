#include "pch.h"
#include "Main/CompilerInstance.h"
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

        const bool promote = node.modifierFlags.has(AstModifierFlagsE::Promote);
        if (!sema.promoteConstants(ops, leftCstRef, rightCstRef, promote))
            return ConstantRef::invalid();

        const ConstantValue& leftCst  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& rightCst = sema.cstMgr().get(rightCstRef);
        const TypeInfo&      type     = leftCst.type(sema.ctx());

        // Wrap and promote modifiers can only be applied to integers
        if (node.modifierFlags.hasAny({AstModifierFlagsE::Wrap, AstModifierFlagsE::Promote}))
        {
            if (!type.isInt())
            {
                const SourceView& srcView = sema.compiler().srcView(node.srcViewRef());
                const TokenRef    mdfRef  = srcView.findRightFrom(node.tokRef(), {TokenId::ModifierWrap, TokenId::ModifierPromote});
                auto              diag    = sema.reportError(DiagnosticId::sema_err_modifier_only_integer, node.srcViewRef(), mdfRef);
                diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                diag.report(sema.ctx());
                return ConstantRef::invalid();
            }
        }

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
                        sema.raiseDivZero(node, ops.nodeView[1].nodeRef, leftCst.typeRef());
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
            ApsInt val1 = leftCst.getInt();
            ApsInt val2 = rightCst.getInt();

            const bool wrap     = node.modifierFlags.has(AstModifierFlagsE::Wrap);
            bool       overflow = false;

            if (type.isIntUnsized())
            {
                val1.setSigned(true);
                val2.setSigned(true);
            }

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
                        sema.raiseDivZero(node, ops.nodeView[1].nodeRef, leftCst.typeRef());
                        return ConstantRef::invalid();
                    }

                    val1.div(val2, overflow);
                    break;

                case TokenId::SymPercent:
                    if (val2.isZero())
                    {
                        sema.raiseDivZero(node, ops.nodeView[1].nodeRef, leftCst.typeRef());
                        return ConstantRef::invalid();
                    }

                    val1.mod(val2, overflow);
                    break;

                case TokenId::SymAmpersand:
                    val1.bitwiseAnd(val2);
                    break;
                case TokenId::SymPipe:
                    val1.bitwiseOr(val2);
                    break;
                case TokenId::SymCircumflex:
                    val1.bitwiseXor(val2);
                    break;

                case TokenId::SymGreaterGreater:
                    if (val2.isNegative())
                    {
                        auto diag = sema.reportError(DiagnosticId::sema_err_negative_shift, node.nodeRightRef);
                        diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                        diag.report(sema.ctx());
                        return ConstantRef::invalid();
                    }

                    if (!val2.fits64())
                        overflow = true;
                    else
                        val1.shiftRight(val2.asU64());
                    break;

                case TokenId::SymLowerLower:
                    if (val2.isNegative())
                    {
                        auto diag = sema.reportError(DiagnosticId::sema_err_negative_shift, node.nodeRightRef);
                        diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                        diag.report(sema.ctx());
                        return ConstantRef::invalid();
                    }

                    if (!val2.fits64())
                        overflow = true;
                    else
                        val1.shiftLeft(val2.asU64(), overflow);
                    overflow = false;
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            if (!wrap && type.intBits() != 0 && overflow)
            {
                auto diag = sema.reportError(DiagnosticId::sema_err_integer_overflow, node.srcViewRef(), node.tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                diag.addArgument(Diagnostic::ARG_LEFT, leftCstRef);
                diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
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
        Utf8        result = ops.nodeView[0].cst->toString(ctx);
        result += ops.nodeView[1].cst->toString(ctx);
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
            case TokenId::SymPercent:
            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                return constantFoldOp(sema, op, node, ops);

            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkPlusPlus(Sema& sema, const AstBinaryExpr& node, const SemaNodeViewList&)
    {
        if (sema.checkModifiers(node, node.modifierFlags, AstModifierFlagsE::Zero) == Result::Error)
            return Result::Error;

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

    Result checkOp(Sema& sema, TokenId op, const AstBinaryExpr& node, const SemaNodeViewList& ops)
    {
        switch (op)
        {
            case TokenId::SymSlash:
            case TokenId::SymPercent:
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
                if (!ops.nodeView[0].type->canBePromoted())
                {
                    sema.raiseBinaryOperandType(node, node.nodeLeftRef, ops.nodeView[0].typeRef);
                    return Result::Error;
                }

                if (!ops.nodeView[1].type->canBePromoted())
                {
                    sema.raiseBinaryOperandType(node, node.nodeRightRef, ops.nodeView[1].typeRef);
                    return Result::Error;
                }
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                if (!ops.nodeView[0].type->isInt())
                {
                    sema.raiseBinaryOperandType(node, node.nodeLeftRef, ops.nodeView[0].typeRef);
                    return Result::Error;
                }

                if (!ops.nodeView[1].type->isInt())
                {
                    sema.raiseBinaryOperandType(node, node.nodeRightRef, ops.nodeView[1].typeRef);
                    return Result::Error;
                }
                break;

            default:
                break;
        }

        switch (op)
        {
            case TokenId::SymSlash:
            case TokenId::SymPercent:
                if (sema.checkModifiers(node, node.modifierFlags, AstModifierFlagsE::Promote) == Result::Error)
                    return Result::Error;
                break;

            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
                if (sema.checkModifiers(node, node.modifierFlags, AstModifierFlagsE::Wrap | AstModifierFlagsE::Promote) == Result::Error)
                    return Result::Error;
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                if (sema.checkModifiers(node, node.modifierFlags, AstModifierFlagsE::Zero) == Result::Error)
                    return Result::Error;
                break;

            default:
                break;
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
            case TokenId::SymPercent:
            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                return checkOp(sema, op, expr, ops);

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
