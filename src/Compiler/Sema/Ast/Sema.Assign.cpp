#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef assignmentTargetTypeRef(const SemaNodeView& leftView)
    {
        if (leftView.type && leftView.type->isReference())
            return leftView.type->payloadTypeRef();
        return leftView.typeRef;
    }

    SemaNodeView assignmentTargetView(Sema& sema, const SemaNodeView& leftView)
    {
        SemaNodeView  targetView    = leftView;
        const TypeRef targetTypeRef = assignmentTargetTypeRef(leftView);
        if (targetTypeRef != leftView.typeRef)
        {
            targetView.typeRef = targetTypeRef;
            targetView.type    = &sema.typeMgr().get(targetTypeRef);
        }
        return targetView;
    }

    void applyMoveAssignmentModifiers(Sema& sema, AstModifierFlags modifierFlags, SemaNodeView& rightView)
    {
        if (!modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::MoveRaw}))
            return;
        if (!rightView.type || !rightView.type->isMoveReference())
            return;

        const TypeRef valueTypeRef = rightView.type->payloadTypeRef();
        rightView.typeRef          = valueTypeRef;
        rightView.type             = &sema.typeMgr().get(valueTypeRef);
    }

    Result checkRightConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymSlashEqual:
            case TokenId::SymPercentEqual:
                if (nodeRightView.type->isFloat() && nodeRightView.cst->getFloat().isZero())
                    return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef);
                if (nodeRightView.type->isInt() && nodeRightView.cst->getInt().isZero())
                    return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef);
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result castAndResultType(Sema& sema, TokenId op, const SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        const TokenId binOp          = Token::assignToBinary(op);
        const auto    targetLeftView = assignmentTargetView(sema, nodeLeftView);
        RESULT_VERIFY(SemaHelpers::castBinaryRightToLeft(sema, binOp, sema.curNodeRef(), targetLeftView, nodeRightView, CastKind::Assignment));
        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView)
    {
        if (nodeRightView.cstRef.isValid())
            RESULT_VERIFY(checkRightConstant(sema, op, nodeRef, nodeRightView));

        switch (op)
        {
            case TokenId::SymEqual:
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
                return Result::Continue;

            default:
                SWC_INTERNAL_ERROR();
        }
    }

    Result assignDecomposition(Sema& sema, const Token& tok, const AstAssignList& assignList, AstModifierFlags modifierFlags, SemaNodeView nodeRightView)
    {
        if (tok.id != TokenId::SymEqual)
        {
            SWC_INTERNAL_ERROR();
        }

        applyMoveAssignmentModifiers(sema, modifierFlags, nodeRightView);

        SmallVector<AstNodeRef> leftRefs;
        sema.ast().appendNodes(leftRefs, assignList.spanChildrenRef);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));

        if (!nodeRightView.type->isStruct())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_struct, nodeRightView.nodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, nodeRightView.typeRef);
            diag.report(sema.ctx());
            return Result::Error;
        }

        RESULT_VERIFY(sema.waitSemaCompleted(nodeRightView.type, nodeRightView.nodeRef));

        const SymbolStruct& symStruct = nodeRightView.type->payloadSymStruct();
        const auto&         fields    = symStruct.fields();

        if (leftRefs.size() > fields.size())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_too_many_names, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (leftRefs.size() < fields.size())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_enough_names, sema.curNodeRef());
            diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        for (size_t i = 0; i < leftRefs.size(); i++)
        {
            const auto leftRef = leftRefs[i];
            if (leftRef.isInvalid())
                continue;
            if (sema.node(leftRef).is(AstNodeId::AssignIgnore))
                continue;

            const SemaNodeView leftView(sema, leftRef);
            RESULT_VERIFY(SemaCheck::isAssignable(sema, sema.curNodeRef(), leftView));

            CastRequest castRequest(CastKind::Assignment);
            castRequest.errorNodeRef    = leftRef;
            const TypeRef targetTypeRef = assignmentTargetTypeRef(leftView);
            if (Cast::castAllowed(sema, castRequest, fields[i]->typeRef(), targetTypeRef) != Result::Continue)
                return Cast::emitCastFailure(sema, castRequest.failure);
        }

        return Result::Continue;
    }

    Result assignMulti(Sema& sema, const Token& tok, const AstAssignList& assignList, AstModifierFlags modifierFlags, SemaNodeView nodeRightView)
    {
        SmallVector<AstNodeRef> leftRefs;
        sema.ast().appendNodes(leftRefs, assignList.spanChildrenRef);

        applyMoveAssignmentModifiers(sema, modifierFlags, nodeRightView);

        if (nodeRightView.cstRef.isValid())
            RESULT_VERIFY(checkRightConstant(sema, tok.id, sema.curNodeRef(), nodeRightView));

        if (tok.id == TokenId::SymEqual)
        {
            RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeRightView));
        }
        else
        {
            RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));
        }

        for (const auto leftRef : leftRefs)
        {
            if (sema.node(leftRef).is(AstNodeId::AssignIgnore))
                continue;

            const SemaNodeView leftView(sema, leftRef);
            RESULT_VERIFY(SemaCheck::isAssignable(sema, sema.curNodeRef(), leftView));

            if (tok.id != TokenId::SymEqual)
            {
                const TokenId binOp          = Token::assignToBinary(tok.id);
                const auto    targetLeftView = assignmentTargetView(sema, leftView);
                RESULT_VERIFY(SemaHelpers::checkBinaryOperandTypes(sema, sema.curNodeRef(), binOp, leftRef, nodeRightView.nodeRef, targetLeftView, nodeRightView));
            }

            CastRequest castRequest(CastKind::Assignment);
            castRequest.errorNodeRef    = leftRef;
            const TypeRef targetTypeRef = assignmentTargetTypeRef(leftView);
            if (Cast::castAllowed(sema, castRequest, nodeRightView.typeRef, targetTypeRef) != Result::Continue)
                return Cast::emitCastFailure(sema, castRequest.failure);
        }

        return Result::Continue;
    }

}

Result AstAssignStmt::semaPreNode(Sema& sema) const
{
    constexpr AstModifierFlags allowed = AstModifierFlagsE::NoDrop |
                                         AstModifierFlagsE::Ref |
                                         AstModifierFlagsE::ConstRef |
                                         AstModifierFlagsE::Move |
                                         AstModifierFlagsE::MoveRaw;
    RESULT_VERIFY(SemaCheck::modifiers(sema, *this, modifierFlags, allowed));
    return Result::Continue;
}

Result AstAssignStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef && nodeRightRef.isValid())
    {
        // Provide a type hint to the RHS: `a = expr` should type `expr` as `typeof(a)` when possible.
        const SemaNodeView leftView(sema, nodeLeftRef);
        if (leftView.typeRef.isValid())
        {
            auto frame = sema.frame();
            frame.pushBindingType(leftView.typeRef);
            sema.pushFramePopOnPostChild(frame, nodeRightRef);
        }
    }

    return Result::Continue;
}

Result AstAssignStmt::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeLeftView(sema, nodeLeftRef);
    SemaNodeView       nodeRightView(sema, nodeRightRef);

    const Token& tok = sema.token(codeRef());
    if (nodeLeftView.node->is(AstNodeId::AssignList))
    {
        const auto* assignList = nodeLeftView.node->cast<AstAssignList>();
        if (assignList->hasFlag(AstAssignListFlagsE::Destructuring))
            return assignDecomposition(sema, tok, *assignList, modifierFlags, nodeRightView);
        return assignMulti(sema, tok, *assignList, modifierFlags, nodeRightView);
    }

    RESULT_VERIFY(SemaCheck::isAssignable(sema, sema.curNodeRef(), nodeLeftView));
    RESULT_VERIFY(check(sema, tok.id, sema.curNodeRef(), nodeRightView));

    applyMoveAssignmentModifiers(sema, modifierFlags, nodeRightView);

    if (tok.id == TokenId::SymEqual)
    {
        RESULT_VERIFY(SemaCheck::isValueOrType(sema, nodeRightView));
    }
    else
    {
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeRightView.nodeRef));
        const TokenId binOp          = Token::assignToBinary(tok.id);
        const auto    targetLeftView = assignmentTargetView(sema, nodeLeftView);
        RESULT_VERIFY(SemaHelpers::checkBinaryOperandTypes(sema, sema.curNodeRef(), binOp, nodeLeftRef, nodeRightRef, targetLeftView, nodeRightView));
    }

    RESULT_VERIFY(castAndResultType(sema, tok.id, nodeLeftView, nodeRightView));
    return Result::Continue;
}

SWC_END_NAMESPACE();
