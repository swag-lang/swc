#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TokenId canonicalBinaryToken(TokenId op)
    {
        switch (op)
        {
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
            case TokenId::SymAsteriskEqual:
            case TokenId::SymSlashEqual:
            case TokenId::SymAmpersandEqual:
            case TokenId::SymPipeEqual:
            case TokenId::SymCircumflexEqual:
            case TokenId::SymPercentEqual:
            case TokenId::SymLowerLowerEqual:
            case TokenId::SymGreaterGreaterEqual:
                return Token::assignToBinary(op);

            default:
                break;
        }

        return op;
    }

    bool mapTokenToFoldBinaryOp(Math::FoldBinaryOp& outOp, TokenId op)
    {
        switch (op)
        {
            case TokenId::SymPlus:
                outOp = Math::FoldBinaryOp::Add;
                return true;
            case TokenId::SymMinus:
                outOp = Math::FoldBinaryOp::Subtract;
                return true;
            case TokenId::SymAsterisk:
                outOp = Math::FoldBinaryOp::Multiply;
                return true;
            case TokenId::SymSlash:
                outOp = Math::FoldBinaryOp::Divide;
                return true;
            case TokenId::SymPercent:
                outOp = Math::FoldBinaryOp::Modulo;
                return true;
            case TokenId::SymAmpersand:
                outOp = Math::FoldBinaryOp::BitwiseAnd;
                return true;
            case TokenId::SymPipe:
                outOp = Math::FoldBinaryOp::BitwiseOr;
                return true;
            case TokenId::SymCircumflex:
                outOp = Math::FoldBinaryOp::BitwiseXor;
                return true;
            case TokenId::SymGreaterGreater:
                outOp = Math::FoldBinaryOp::ShiftRight;
                return true;
            case TokenId::SymLowerLower:
                outOp = Math::FoldBinaryOp::ShiftLeft;
                return true;
            default:
                return false;
        }
    }

    bool keepEnumFlagsResult(const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView, TokenId op)
    {
        if (op != TokenId::SymPipe && op != TokenId::SymAmpersand && op != TokenId::SymCircumflex)
            return false;
        if (!nodeLeftView.type()->isEnumFlags() || !nodeRightView.type()->isEnumFlags())
            return false;
        return nodeLeftView.typeRef() == nodeRightView.typeRef();
    }

    Result constantFoldOp(Sema& sema, ConstantRef& result, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const TaskContext& ctx         = sema.ctx();
        ConstantRef        leftCstRef  = nodeLeftView.cstRef();
        ConstantRef        rightCstRef = nodeRightView.cstRef();
        const bool         keepEnumRes = keepEnumFlagsResult(nodeLeftView, nodeRightView, op);

        if (keepEnumRes)
        {
            const ConstantValue& leftVal  = sema.cstMgr().get(leftCstRef);
            const ConstantValue& rightVal = sema.cstMgr().get(rightCstRef);
            SWC_ASSERT(leftVal.isEnumValue() && rightVal.isEnumValue());
            leftCstRef  = leftVal.getEnumValue();
            rightCstRef = rightVal.getEnumValue();
        }

        const bool promote = node.modifierFlags.has(AstModifierFlagsE::Promote);
        if (!keepEnumRes)
            SWC_RESULT(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef, promote));

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
                auto              diag    = SemaError::report(sema, DiagnosticId::sema_err_modifier_only_integer, SourceCodeRef{node.srcViewRef(), mdfRef});
                diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        if (type.isFloat())
        {
            Math::FoldBinaryOp foldOp;
            const bool         mapped = mapTokenToFoldBinaryOp(foldOp, op);
            SWC_ASSERT(mapped);
            if (!mapped)
                return Result::Error;

            ApFloat                foldedValue;
            const Math::FoldStatus foldStatus = Math::foldBinaryFloat(foldedValue, leftCst.getFloat(), rightCst.getFloat(), foldOp);
            if (foldStatus != Math::FoldStatus::Ok)
            {
                if (Math::isSafetyError(foldStatus))
                    return SemaError::raiseFoldSafety(sema, foldStatus, sema.curNodeRef(), node.nodeRightRef, SemaError::ReportLocation::Token);
                return Result::Error;
            }

            result = sema.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, foldedValue, type.payloadFloatBits()));
            return Result::Continue;
        }

        if (type.isInt())
        {
            ApsInt     val1 = leftCst.getInt();
            ApsInt     val2 = rightCst.getInt();
            const bool wrap = node.modifierFlags.has(AstModifierFlagsE::Wrap);

            if (type.isIntUnsized())
            {
                val1.setSigned(true);
                val2.setSigned(true);
            }

            Math::FoldBinaryOp foldOp;
            const bool         mapped = mapTokenToFoldBinaryOp(foldOp, op);
            SWC_ASSERT(mapped);
            if (!mapped)
                return Result::Error;

            Math::FoldBinaryIntOptions foldOptions;
            if (op == TokenId::SymLowerLower)
                foldOptions.ignoreShiftOverflow = true;

            ApsInt           foldedValue;
            Math::FoldStatus foldStatus = Math::foldBinaryInt(foldedValue, val1, val2, foldOp, foldOptions);
            if (foldStatus == Math::FoldStatus::Overflow && (wrap || type.payloadIntBits() == 0))
                foldStatus = Math::FoldStatus::Ok;

            if (foldStatus != Math::FoldStatus::Ok)
            {
                if (foldStatus == Math::FoldStatus::Overflow)
                {
                    auto diag = SemaError::reportFoldSafety(sema, foldStatus, sema.curNodeRef(), SemaError::ReportLocation::Children);
                    diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                    diag.addArgument(Diagnostic::ARG_LEFT, leftCstRef);
                    diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                    diag.report(sema.ctx());
                    return Result::Error;
                }

                if (Math::isSafetyError(foldStatus))
                {
                    auto diag = SemaError::reportFoldSafety(sema, foldStatus, sema.curNodeRef(), SemaError::ReportLocation::Token);
                    if (foldStatus == Math::FoldStatus::NegativeShift)
                        diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                    if (foldStatus == Math::FoldStatus::DivisionByZero || foldStatus == Math::FoldStatus::NegativeShift)
                        SemaError::addSpan(sema, diag.last(), node.nodeRightRef, "", DiagnosticSeverity::Note);
                    diag.report(sema.ctx());
                    return Result::Error;
                }

                return Result::Error;
            }

            const ConstantRef intResult = sema.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, foldedValue, type.payloadIntBits(), type.payloadIntSign()));
            if (keepEnumRes)
            {
                const ConstantValue enumResult = ConstantValue::makeEnumValue(ctx, intResult, nodeLeftView.typeRef());
                result                         = sema.cstMgr().addConstant(ctx, enumResult);
            }
            else
            {
                result = intResult;
            }
            return Result::Continue;
        }

        return Result::Error;
    }

    Result constantFoldPlusPlus(Sema& sema, ConstantRef& result, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        SWC_UNUSED(node);
        const TaskContext& ctx = sema.ctx();
        Utf8               str = nodeLeftView.cst()->toString(ctx);
        str += nodeRightView.cst()->toString(ctx);
        result = sema.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, str));
        return Result::Continue;
    }

    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymPlusPlus:
                return constantFoldPlusPlus(sema, result, node, nodeLeftView, nodeRightView);

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
                return constantFoldOp(sema, result, op, node, nodeLeftView, nodeRightView);

            default:
                break;
        }

        return Result::Error;
    }

    Result checkPlusPlus(Sema& sema, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        SWC_UNUSED(nodeLeftView);
        SWC_UNUSED(nodeRightView);
        SWC_RESULT(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Zero));
        SWC_RESULT(SemaCheck::isConstant(sema, node.nodeLeftRef));
        SWC_RESULT(SemaCheck::isConstant(sema, node.nodeRightRef));
        return Result::Continue;
    }

    Result checkOp(Sema& sema, AstNodeRef nodeRef, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        SWC_RESULT(SemaHelpers::checkBinaryOperandTypes(sema, nodeRef, op, node.nodeLeftRef, node.nodeRightRef, nodeLeftView, nodeRightView));

        switch (op)
        {
            case TokenId::SymSlash:
            case TokenId::SymPercent:
                SWC_RESULT(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Promote));
                break;

            case TokenId::SymPlus:
            case TokenId::SymMinus:
            case TokenId::SymAsterisk:
                SWC_RESULT(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Wrap | AstModifierFlagsE::Promote));
                break;

            case TokenId::SymAmpersand:
            case TokenId::SymPipe:
            case TokenId::SymCircumflex:
            case TokenId::SymGreaterGreater:
            case TokenId::SymLowerLower:
                SWC_RESULT(SemaCheck::modifiers(sema, node, node.modifierFlags, AstModifierFlagsE::Zero));
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result promote(Sema& sema, TokenId op, AstNodeRef nodeRef, const AstBinaryExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        if (op == TokenId::SymPipe || op == TokenId::SymAmpersand || op == TokenId::SymCircumflex)
        {
            const bool leftEnumFlags  = nodeLeftView.type()->isEnumFlags();
            const bool rightEnumFlags = nodeRightView.type()->isEnumFlags();

            if (nodeLeftView.type()->isEnum())
            {
                if (!leftEnumFlags)
                    return SemaError::raiseInvalidOpEnum(sema, nodeRef, node.nodeLeftRef, nodeLeftView.typeRef());
            }

            if (nodeRightView.type()->isEnum())
            {
                if (!rightEnumFlags)
                    return SemaError::raiseInvalidOpEnum(sema, nodeRef, node.nodeRightRef, nodeRightView.typeRef());
            }

            if (leftEnumFlags && rightEnumFlags && nodeLeftView.typeRef() == nodeRightView.typeRef())
                return Result::Continue;

            if (nodeLeftView.type()->isEnum())
                Cast::convertEnumToUnderlying(sema, nodeLeftView);
            if (nodeRightView.type()->isEnum())
                Cast::convertEnumToUnderlying(sema, nodeRightView);
        }

        return Result::Continue;
    }

    Result castAndResultType(Sema& sema, TokenId op, const AstBinaryExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        // Constant folding
        if (nodeLeftView.cstRef().isValid() && nodeRightView.cstRef().isValid())
        {
            ConstantRef result;
            SWC_RESULT(constantFold(sema, result, op, node, nodeLeftView, nodeRightView));
            sema.setConstant(sema.curNodeRef(), result);
            return Result::Continue;
        }

        TypeRef resultTypeRef = nodeLeftView.typeRef();
        switch (op)
        {
            case TokenId::SymPlus:
                if (nodeLeftView.type()->isScalarNumeric() && nodeRightView.type()->isBlockPointer())
                {
                    SWC_RESULT(Cast::cast(sema, nodeLeftView, sema.typeMgr().typeS64(), CastKind::Implicit));
                    nodeRightView.compute(sema, node.nodeRightRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
                    resultTypeRef = nodeRightView.typeRef();
                }
                else if (nodeLeftView.type()->isBlockPointer() && nodeRightView.type()->isScalarNumeric())
                {
                    SWC_RESULT(Cast::cast(sema, nodeRightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                    nodeLeftView.compute(sema, node.nodeLeftRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
                    resultTypeRef = nodeLeftView.typeRef();
                }
                break;

            case TokenId::SymMinus:
                if (nodeLeftView.type()->isBlockPointer() && nodeRightView.type()->isScalarNumeric())
                {
                    SWC_RESULT(Cast::cast(sema, nodeRightView, sema.typeMgr().typeS64(), CastKind::Implicit));
                    nodeLeftView.compute(sema, node.nodeLeftRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
                    resultTypeRef = nodeLeftView.typeRef();
                }
                else if (nodeLeftView.type()->isBlockPointer() && nodeRightView.type()->isBlockPointer())
                {
                    resultTypeRef = sema.typeMgr().typeS64();
                }
                break;

            default:
                break;
        }

        switch (op)
        {
            case TokenId::SymPlusPlus:
                break;

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
                SWC_RESULT(SemaHelpers::castBinaryRightToLeft(sema, op, sema.curNodeRef(), nodeLeftView, nodeRightView, CastKind::Implicit));
                break;

            default:
                break;
        }

        sema.setType(sema.curNodeRef(), resultTypeRef);
        return Result::Continue;
    }

    Result checkRightConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymSlash:
            case TokenId::SymPercent:
                if (nodeRightView.type()->isFloat() && nodeRightView.cst()->getFloat().isZero())
                    return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef());
                if (nodeRightView.type()->isInt() && nodeRightView.cst()->getInt().isZero())
                    return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef());
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, AstNodeRef nodeRef, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeRightView.cstRef().isValid())
            SWC_RESULT(checkRightConstant(sema, op, sema.curNodeRef(), nodeRightView));

        switch (op)
        {
            case TokenId::SymPlusPlus:
                return checkPlusPlus(sema, node, nodeLeftView, nodeRightView);

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
                return checkOp(sema, nodeRef, op, node, nodeLeftView, nodeRightView);

            default:
                SWC_INTERNAL_ERROR();
        }
    }
}

Result AstBinaryExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef)
    {
        const SemaNodeView nodeLeftView = sema.viewType(nodeLeftRef);
        auto               frame        = sema.frame();
        frame.pushBindingType(nodeLeftView.typeRef());
        sema.pushFramePopOnPostChild(frame, nodeRightRef);
    }

    return Result::Continue;
}

Result AstBinaryExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeLeftView  = sema.viewNodeTypeConstant(nodeLeftRef);
    SemaNodeView nodeRightView = sema.viewNodeTypeConstant(nodeRightRef);

    // Value-check
    SWC_RESULT(SemaCheck::isValue(sema, nodeLeftView.nodeRef()));
    SWC_RESULT(SemaCheck::isValue(sema, nodeRightView.nodeRef()));
    sema.setIsValue(*this);

    const TokenId op = canonicalBinaryToken(sema.token(codeRef()).id);

    SWC_RESULT(promote(sema, op, sema.curNodeRef(), *this, nodeLeftView, nodeRightView));
    SWC_RESULT(check(sema, op, sema.curNodeRef(), *this, nodeLeftView, nodeRightView));
    SWC_RESULT(castAndResultType(sema, op, *this, nodeLeftView, nodeRightView));

    return Result::Continue;
}

SWC_END_NAMESPACE();
