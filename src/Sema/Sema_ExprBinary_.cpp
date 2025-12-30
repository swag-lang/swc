#include "pch.h"
#include "Helpers/SemaCheck.h"
#include "Helpers/SemaError.h"
#include "Main/CompilerInstance.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldOp(Sema& sema, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const auto& ctx         = sema.ctx();
        ConstantRef leftCstRef  = nodeLeftView.cstRef;
        ConstantRef rightCstRef = nodeRightView.cstRef;

        const bool promote = node.modifierFlags.has(AstModifierFlagsE::Promote);
        if (!SemaCast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef, promote))
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
                auto              diag    = SemaError::report(sema, DiagnosticId::sema_err_modifier_only_integer, node.srcViewRef(), mdfRef);
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
                        SemaError::raiseDivZero(sema, node, nodeRightView.nodeRef, leftCst.typeRef());
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
                        SemaError::raiseDivZero(sema, node, nodeRightView.nodeRef, leftCst.typeRef());
                        return ConstantRef::invalid();
                    }

                    val1.div(val2, overflow);
                    break;

                case TokenId::SymPercent:
                    if (val2.isZero())
                    {
                        SemaError::raiseDivZero(sema, node, nodeRightView.nodeRef, leftCst.typeRef());
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
                        auto diag = SemaError::report(sema, DiagnosticId::sema_err_negative_shift, node.nodeRightRef);
                        diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                        diag.report(sema.ctx());
                        return ConstantRef::invalid();
                    }

                    if (!val2.fits64())
                        overflow = true;
                    else
                        val1.shiftRight(val2.asI64());
                    break;

                case TokenId::SymLowerLower:
                    if (val2.isNegative())
                    {
                        auto diag = SemaError::report(sema, DiagnosticId::sema_err_negative_shift, node.nodeRightRef);
                        diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                        diag.report(sema.ctx());
                        return ConstantRef::invalid();
                    }

                    if (!val2.fits64())
                        overflow = true;
                    else
                        val1.shiftLeft(val2.asI64(), overflow);
                    overflow = false;
                    break;

                default:
                    SWC_UNREACHABLE();
            }

            if (!wrap && type.intBits() != 0 && overflow)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_integer_overflow, node.srcViewRef(), node.tokRef());
                diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                diag.addArgument(Diagnostic::ARG_LEFT, leftCstRef);
                diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                diag.report(sema.ctx());
                return ConstantRef::invalid();
            }

            return sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, val1, type.intBits(), type.intSign()));
        }

        return ConstantRef::invalid();
    }

    ConstantRef constantFoldPlusPlus(Sema& sema, const AstBinaryExpr&, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const auto& ctx    = sema.ctx();
        Utf8        result = nodeLeftView.cst->toString(ctx);
        result += nodeRightView.cst->toString(ctx);
        return sema.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, result));
    }

    ConstantRef constantFold(Sema& sema, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, node, nodeLeftView, nodeRightView);

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
                return constantFoldOp(sema, op, node, nodeLeftView, nodeRightView);

            default:
                break;
        }

        return ConstantRef::invalid();
    }

    Result checkPlusPlus(Sema& sema, const AstBinaryExpr& node, const SemaNodeView&, const SemaNodeView&)
    {
        if (SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Zero) == Result::Error)
            return Result::Error;
        if (SemaCheck::isConstant(sema, node.nodeLeftRef) != Result::Success)
            return Result::Error;
        if (SemaCheck::isConstant(sema, node.nodeRightRef) != Result::Success)
            return Result::Error;

        return Result::Success;
    }

    Result checkOp(Sema& sema, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymSlash:
            case TokenId::SymPercent:
            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
                if (!nodeLeftView.type->isScalarNumeric())
                {
                    SemaError::raiseBinaryOperandType(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                    return Result::Error;
                }

                if (!nodeRightView.type->isScalarNumeric())
                {
                    SemaError::raiseBinaryOperandType(sema, node, node.nodeRightRef, nodeRightView.typeRef);
                    return Result::Error;
                }
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                if (!nodeLeftView.type->isInt())
                {
                    SemaError::raiseBinaryOperandType(sema, node, node.nodeLeftRef, nodeLeftView.typeRef);
                    return Result::Error;
                }

                if (!nodeRightView.type->isInt())
                {
                    SemaError::raiseBinaryOperandType(sema, node, node.nodeRightRef, nodeRightView.typeRef);
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
                if (SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Promote) == Result::Error)
                    return Result::Error;
                break;

            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
                if (SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Wrap | AstModifierFlagsE::Promote) == Result::Error)
                    return Result::Error;
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                if (SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Zero) == Result::Error)
                    return Result::Error;
                break;

            default:
                break;
        }

        return Result::Success;
    }

    Result promote(Sema& sema, TokenId op, const AstBinaryExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        if (op == TokenId::SymPipe || op == TokenId::SymAmpersand || op == TokenId::SymCircumflex)
        {
            if (nodeLeftView.type->isEnum())
            {
                if (!nodeLeftView.type->enumSym().isEnumFlags())
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_op_enum, node.srcViewRef(), node.tokRef());
                    diag.addArgument(Diagnostic::ARG_TYPE, nodeLeftView.typeRef);
                    const SourceCodeLocation loc = sema.node(node.nodeLeftRef).locationWithChildren(sema.ctx(), sema.ast());
                    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);
                    diag.report(sema.ctx());
                    return Result::Error;
                }

                SemaCast::convertEnumToUnderlying(sema, nodeLeftView);
            }

            if (nodeRightView.type->isEnum())
            {
                if (!nodeRightView.type->enumSym().isEnumFlags())
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_op_enum, node.srcViewRef(), node.tokRef());
                    diag.addArgument(Diagnostic::ARG_TYPE, nodeRightView.typeRef);
                    const SourceCodeLocation loc = sema.node(node.nodeRightRef).locationWithChildren(sema.ctx(), sema.ast());
                    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);
                    diag.report(sema.ctx());
                    return Result::Error;
                }

                SemaCast::convertEnumToUnderlying(sema, nodeRightView);
            }
        }

        return Result::Success;
    }

    Result check(Sema& sema, TokenId op, const AstBinaryExpr& expr, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return checkPlusPlus(sema, expr, nodeLeftView, nodeRightView);

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
                return checkOp(sema, op, expr, nodeLeftView, nodeRightView);

            default:
                break;
        }

        SemaError::raiseInternal(sema, expr);
        return Result::Error;
    }
}

AstVisitStepResult AstBinaryExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeLeftView(sema, nodeLeftRef);
    SemaNodeView nodeRightView(sema, nodeRightRef);

    // Value-check
    if (SemaCheck::isValueExpr(sema, nodeLeftRef) != Result::Success)
        return AstVisitStepResult::Stop;
    if (SemaCheck::isValueExpr(sema, nodeRightRef) != Result::Success)
        return AstVisitStepResult::Stop;
    SemaInfo::addSemaFlags(*this, NodeSemaFlags::ValueExpr);

    // Force types
    const Token& tok = sema.token(srcViewRef(), tokRef());
    if (promote(sema, tok.id, *this, nodeLeftView, nodeRightView) == Result::Error)
        return AstVisitStepResult::Stop;

    // Type-check
    if (check(sema, tok.id, *this, nodeLeftView, nodeRightView) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
    {
        const ConstantRef cst = constantFold(sema, tok.id, *this, nodeLeftView, nodeRightView);
        if (cst.isValid())
        {
            sema.semaInfo().setConstant(sema.curNodeRef(), cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    SemaError::raiseInternal(sema, *this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
