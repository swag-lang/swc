#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Support/Report/Diagnostic.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result constantFoldEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        if (nodeLeftView.type->isTypeValue() && nodeRightView.type->isTypeValue())
        {
            result = sema.cstMgr().cstBool(*nodeLeftView.type == *nodeRightView.type);
            return Result::Continue;
        }

        if (nodeLeftView.type->isAnyTypeInfo(sema.ctx()) && nodeRightView.type->isAnyTypeInfo(sema.ctx()))
        {
            const auto& leftCst  = sema.cstMgr().get(nodeLeftView.cstRef);
            const auto& rightCst = sema.cstMgr().get(nodeRightView.cstRef);
            result               = sema.cstMgr().cstBool(leftCst.getValuePointer() == rightCst.getValuePointer());
            return Result::Continue;
        }

        if (nodeLeftView.cst->isNull() || nodeRightView.cst->isNull())
        {
            result = sema.cstMgr().cstBool(nodeLeftView.cst->isNull() && nodeRightView.cst->isNull());
            return Result::Continue;
        }

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;
        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));

        // For float, we need to compare by values, because two different constants
        // can still have the same value. For example, 0.0 and -0.0 are two different
        // constants but have equal values.
        const auto& left = sema.cstMgr().get(leftCstRef);
        if (left.isFloat())
        {
            const auto& right = sema.cstMgr().get(rightCstRef);
            result            = sema.cstMgr().cstBool(left.eq(right));
            return Result::Continue;
        }

        result = sema.cstMgr().cstBool(leftCstRef == rightCstRef);
        return Result::Continue;
    }

    Result constantFoldLess(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.lt(rightCst));
        return Result::Continue;
    }

    Result constantFoldLessEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.le(rightCst));
        return Result::Continue;
    }

    Result constantFoldGreater(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.gt(rightCst));
        return Result::Continue;
    }

    Result constantFoldGreaterEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.ge(rightCst));
        return Result::Continue;
    }

    Result constantFoldCompareEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        RESULT_VERIFY(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        const auto& left  = sema.cstMgr().get(leftCstRef);
        const auto& right = sema.cstMgr().get(rightCstRef);

        int val;
        if (leftCstRef == rightCstRef)
            val = 0;
        else if (left.lt(right))
            val = -1;
        else if (right.lt(left))
            val = 1;
        else
            val = 0;

        result = sema.cstMgr().cstS32(val);
        return Result::Continue;
    }

    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymBangEqual:
                RESULT_VERIFY(constantFoldEqual(sema, result, nodeLeftView, nodeRightView));
                result = sema.cstMgr().cstNegBool(result);
                return Result::Continue;

            case TokenId::SymLess:
                return constantFoldLess(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymLessEqual:
                return constantFoldLessEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymGreater:
                return constantFoldGreater(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymGreaterEqual:
                return constantFoldGreaterEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymLessEqualGreater:
                return constantFoldCompareEqual(sema, result, nodeLeftView, nodeRightView);

            default:
                return Result::Error;
        }
    }

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.typeRef == nodeRightView.typeRef)
            return Result::Continue;
        if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isScalarNumeric())
            return Result::Continue;
        if (nodeLeftView.type->isType() && nodeRightView.type->isType())
            return Result::Continue;
        if (nodeLeftView.type->isNull() && nodeRightView.type->isPointerLike())
            return Result::Continue;
        if (nodeLeftView.type->isPointerLike() && nodeRightView.type->isNull())
            return Result::Continue;
        if (nodeLeftView.type->isAnyPointer() && nodeRightView.type->isAnyPointer())
            return Result::Continue;
        if (nodeLeftView.type->isAnyTypeInfo(sema.ctx()) && nodeRightView.type->isAnyTypeInfo(sema.ctx()))
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isScalarNumeric())
            return Result::Continue;
        if (nodeLeftView.type->isAnyPointer() && nodeRightView.type->isAnyPointer())
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    namespace
    {
        void enumForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type || !other.type)
                return;
            if (self.type->isEnum() && !other.type->isEnum())
                Cast::convertEnumToUnderlying(sema, self);
        }

        void nullForEquality(Sema& sema, const SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type || !other.type)
                return;
            if (self.type->isNull() && other.type->isPointerLike())
                Cast::createImplicitCast(sema, other.typeRef, self.nodeRef);
        }

        Result typeInfoForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type || !other.type)
                return Result::Continue;
            if (self.type->isTypeValue() && other.type->isAnyTypeInfo(sema.ctx()))
            {
                RESULT_VERIFY(Cast::cast(sema, self, sema.typeMgr().typeTypeInfo(), CastKind::Implicit));
                return Result::Continue;
            }

            return Result::Continue;
        }
    }

    Result promote(Sema& sema, TokenId op, const AstRelationalExpr&, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        if (op == TokenId::SymEqualEqual || op == TokenId::SymBangEqual)
        {
            enumForEquality(sema, nodeLeftView, nodeRightView);
            enumForEquality(sema, nodeRightView, nodeLeftView);
            nullForEquality(sema, nodeLeftView, nodeRightView);
            nullForEquality(sema, nodeRightView, nodeLeftView);
            RESULT_VERIFY(typeInfoForEquality(sema, nodeLeftView, nodeRightView));
            RESULT_VERIFY(typeInfoForEquality(sema, nodeRightView, nodeLeftView));
        }

        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
            case TokenId::SymBangEqual:
                return checkEqualEqual(sema, node, nodeLeftView, nodeRightView);

            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
            case TokenId::SymLessEqualGreater:
                return checkCompareEqual(sema, node, nodeLeftView, nodeRightView);

            default:
                SWC_UNREACHABLE();
        }
    }
}

Result AstRelationalExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef)
    {
        const SemaNodeView nodeLeftView(sema, nodeLeftRef);
        auto               frame = sema.frame();
        frame.pushBindingType(nodeLeftView.typeRef);
        sema.pushFramePopOnPostChild(frame, nodeRightRef);
    }

    return Result::Continue;
}

Result AstRelationalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeLeftView(sema, nodeLeftRef);
    SemaNodeView nodeRightView(sema, nodeRightRef);
    const auto&  tok = sema.token(srcViewRef(), tokRef());

    RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeLeftView));
    RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeRightView));
    SemaInfo::setIsValue(*this);

    // Force types
    RESULT_VERIFY(promote(sema, tok.id, *this, nodeLeftView, nodeRightView));

    // Type-check
    RESULT_VERIFY(check(sema, tok.id, *this, nodeLeftView, nodeRightView));

    // Set the result type
    if (tok.id == TokenId::SymLessEqualGreater)
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeInt(32, TypeInfo::Sign::Signed));
    else
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());

    // Constant folding
    if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
    {
        ConstantRef result;
        RESULT_VERIFY(constantFold(sema, result, tok.id, nodeLeftView, nodeRightView));
        sema.setConstant(sema.curNodeRef(), result);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
