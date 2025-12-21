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
    ConstantRef constantFoldEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        const SemaNodeView& view0 = ops.view[0];
        const SemaNodeView& view1 = ops.view[1];

        if (view0.cstRef == view1.cstRef)
            return sema.cstMgr().cstTrue();
        if (view0.type->isTypeInfo() && view1.type->isTypeInfo())
            return sema.cstMgr().cstBool(*view0.type == *view1.type);

        auto leftCstRef  = view0.cstRef;
        auto rightCstRef = view1.cstRef;
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
        if (ops.view[0].cstRef == ops.view[1].cstRef)
            return sema.cstMgr().cstFalse();

        auto leftCstRef  = ops.view[0].cstRef;
        auto rightCstRef = ops.view[1].cstRef;

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
        if (ops.view[0].cstRef == ops.view[1].cstRef)
            return sema.cstMgr().cstTrue();

        auto leftCstRef  = ops.view[0].cstRef;
        auto rightCstRef = ops.view[1].cstRef;

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
        auto leftCstRef  = ops.view[0].cstRef;
        auto rightCstRef = ops.view[1].cstRef;

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
        if (ops.view[0].cstRef == ops.view[1].cstRef)
            return sema.cstMgr().cstTrue();

        auto leftCstRef  = ops.view[0].cstRef;
        auto rightCstRef = ops.view[1].cstRef;

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
        auto leftCstRef  = ops.view[0].cstRef;
        auto rightCstRef = ops.view[1].cstRef;

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
        const SemaNodeView& view0 = ops.view[0];
        const SemaNodeView& view1 = ops.view[1];

        if (view0.typeRef == view1.typeRef)
            return Result::Success;
        if (view0.type->isScalarNumeric() && view1.type->isScalarNumeric())
            return Result::Success;
        if (view0.type->isType() && view1.type->isType())
            return Result::Success;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_LEFT, view0.typeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, view1.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeViewList& ops)
    {
        if (ops.view[0].type->isScalarNumeric() && ops.view[1].type->isScalarNumeric())
            return Result::Success;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.srcViewRef(), node.tokRef());
        diag.addArgument(Diagnostic::ARG_LEFT, ops.view[0].typeRef);
        diag.addArgument(Diagnostic::ARG_RIGHT, ops.view[1].typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    void promoteTypeToTypeInfoForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        if (!other.type->isTypeInfo())
            return;
        if (self.type->isTypeInfo())
            return;
        if (!self.type->isType())
            return;
        TaskContext&      ctx    = sema.ctx();
        const ConstantRef cstRef = sema.cstMgr().addConstant(ctx, ConstantValue::makeTypeInfo(ctx, self.typeRef));
        self.setCstRef(sema, cstRef);
    }

    void promoteEnumForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
    {
        // Only kick in when comparing enum to a scalar numeric (or whatever rule you want)
        if (!self.type->isEnum())
            return;
        if (other.type->isEnum())
            return;
        if (!other.type->isScalarNumeric())
            return;

        if (self.cstRef.isValid())
        {
            self.setCstRef(sema, self.cst->getEnumValue());
            return;
        }

        const SymbolEnum* symEnum = self.type->enumSym();
        SemaCast::createImplicitCast(sema, symEnum->underlyingTypeRef(), self.nodeRef);
    }

    void promoteEqualEqual(Sema& sema, SemaNodeViewList& ops)
    {
        for (int i = 0; i < 2; ++i)
        {
            auto& self  = ops.view[i];
            auto& other = ops.view[1 - i];
            promoteTypeToTypeInfoForEquality(sema, self, other);
            promoteEnumForEquality(sema, self, other);
        }
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& node, SemaNodeViewList& ops)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
            case TokenId::SymBangEqual:
                promoteEqualEqual(sema, ops);
                return checkEqualEqual(sema, node, ops);

            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
            case TokenId::SymLessEqualGreater:
                return checkCompareEqual(sema, node, ops);

            default:
                SemaError::raiseInternal(sema, node);
                return Result::Error;
        }
    }
}

AstVisitStepResult AstRelationalExpr::semaPostNode(Sema& sema) const
{
    SemaNodeViewList ops(sema, nodeLeftRef, nodeRightRef);
    const auto&      tok = sema.token(srcViewRef(), tokRef());

    // Type-check
    if (check(sema, tok.id, *this, ops) == Result::Error)
        return AstVisitStepResult::Stop;

    const SemaNodeView& view0 = ops.view[0];
    const SemaNodeView& view1 = ops.view[1];

    // Constant folding
    if (view0.cstRef.isValid() && view1.cstRef.isValid())
    {
        const auto cst = constantFold(sema, tok.id, *this, ops);
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
