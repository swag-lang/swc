#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantFold.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.codeRef());
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

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.codeRef());
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
    const auto&  tok = sema.token({srcViewRef(), tokRef()});

    RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeLeftView));
    RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeRightView));
    sema.setIsValue(*this);

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
        RESULT_VERIFY(ConstantFold::relational(sema, result, tok.id, nodeLeftView, nodeRightView));
        sema.setConstant(sema.curNodeRef(), result);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
