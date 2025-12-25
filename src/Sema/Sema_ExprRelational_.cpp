#include "pch.h"
#include "Helpers/SemaError.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Type/SemaCast.h"
#include "Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    ConstantRef constantFoldEqual(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
            return sema.cstMgr().cstTrue();
        if (nodeLeftView.type->isTypeValue() && nodeRightView.type->isTypeValue())
            return sema.cstMgr().cstBool(*nodeLeftView.type == *nodeRightView.type);

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;
        if (!SemaCast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef))
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

    ConstantRef constantFoldLess(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
            return sema.cstMgr().cstFalse();

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        if (!SemaCast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef))
            return ConstantRef::invalid();
        if (leftCstRef == rightCstRef)
            return sema.cstMgr().cstFalse();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.lt(rightCst));
    }

    ConstantRef constantFoldLessEqual(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
            return sema.cstMgr().cstTrue();

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        if (!SemaCast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef))
            return ConstantRef::invalid();
        if (leftCstRef == rightCstRef)
            return sema.cstMgr().cstTrue();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.le(rightCst));
    }

    ConstantRef constantFoldGreater(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        if (!SemaCast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef))
            return ConstantRef::invalid();
        if (leftCstRef == rightCstRef)
            return sema.cstMgr().cstFalse();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.gt(rightCst));
    }

    ConstantRef constantFoldGreaterEqual(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef == nodeRightView.cstRef)
            return sema.cstMgr().cstTrue();

        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        if (!SemaCast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef))
            return ConstantRef::invalid();
        if (leftCstRef == rightCstRef)
            return sema.cstMgr().cstTrue();

        const auto& leftCst  = sema.cstMgr().get(leftCstRef);
        const auto& rightCst = sema.cstMgr().get(rightCstRef);

        return sema.cstMgr().cstBool(leftCst.ge(rightCst));
    }

    ConstantRef constantFoldCompareEqual(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        auto leftCstRef  = nodeLeftView.cstRef;
        auto rightCstRef = nodeRightView.cstRef;

        if (!SemaCast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef))
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

    ConstantRef constantFold(Sema& sema, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, nodeLeftView, nodeRightView);

            case TokenId::SymBangEqual:
                return sema.cstMgr().cstNegBool(constantFoldEqual(sema, nodeLeftView, nodeRightView));

            case TokenId::SymLess:
                return constantFoldLess(sema, nodeLeftView, nodeRightView);

            case TokenId::SymLessEqual:
                return constantFoldLessEqual(sema, nodeLeftView, nodeRightView);

            case TokenId::SymGreater:
                return constantFoldGreater(sema, nodeLeftView, nodeRightView);

            case TokenId::SymGreaterEqual:
                return constantFoldGreaterEqual(sema, nodeLeftView, nodeRightView);

            case TokenId::SymLessEqualGreater:
                return constantFoldCompareEqual(sema, nodeLeftView, nodeRightView);

            default:
                return ConstantRef::invalid();
        }
    }

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.typeRef == nodeRightView.typeRef)
            return Result::Success;
        if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isScalarNumeric())
            return Result::Success;
        if (nodeLeftView.type->isType() && nodeRightView.type->isType())
            return Result::Success;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.type->isScalarNumeric() && nodeRightView.type->isScalarNumeric())
            return Result::Success;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    void promoteTypeToTypeInfoForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (!other.type->isTypeValue())
            return;
        if (self.type->isTypeValue())
            return;
        if (!self.type->isType())
            return;

        TaskContext&      ctx    = sema.ctx();
        const ConstantRef cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeTypeValue(ctx, self.typeRef));
        self.setCstRef(sema, cstRef);
    }

    void promoteEnumForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (!self.type->isEnum())
            return;
        if (other.type->isEnum())
            return;

        if (self.cstRef.isValid())
        {
            self.setCstRef(sema, self.cst->getEnumValue());
            return;
        }

        const SymbolEnum& symEnum = self.type->enumSym();
        SemaCast::createImplicitCast(sema, symEnum.underlyingTypeRef(), self.nodeRef);
    }

    void promoteEqualEqual(Sema& sema, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        promoteTypeToTypeInfoForEquality(sema, nodeLeftView, nodeRightView);
        promoteEnumForEquality(sema, nodeLeftView, nodeRightView);
        promoteTypeToTypeInfoForEquality(sema, nodeRightView, nodeLeftView);
        promoteEnumForEquality(sema, nodeRightView, nodeLeftView);
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
            case TokenId::SymBangEqual:
                promoteEqualEqual(sema, nodeLeftView, nodeRightView);
                return checkEqualEqual(sema, node, nodeLeftView, nodeRightView);

            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
            case TokenId::SymLessEqualGreater:
                return checkCompareEqual(sema, node, nodeLeftView, nodeRightView);

            default:
                SemaError::raiseInternal(sema, node);
                return Result::Error;
        }
    }
}

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema) const
{
    SemaNodeView nodeLeftView(sema, nodeLeftRef);
    SemaNodeView nodeRightView(sema, nodeRightRef);

    // Type-check
    const auto& tok = sema.token(srcViewRef(), tokRef());
    if (check(sema, tok.id, *this, nodeLeftView, nodeRightView) == Result::Error)
        return AstVisitStepResult::Stop;

    // Constant folding
    if (nodeLeftView.cstRef.isValid() && nodeRightView.cstRef.isValid())
    {
        const auto cst = constantFold(sema, tok.id, nodeLeftView, nodeRightView);
        if (cst.isValid())
        {
            sema.setConstant(sema.curNodeRef(), cst);
            return AstVisitStepResult::Continue;
        }

        return AstVisitStepResult::Stop;
    }

    SemaError::raiseInternal(sema, *this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
