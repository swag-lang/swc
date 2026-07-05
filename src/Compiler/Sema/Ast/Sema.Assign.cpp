#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef assignmentTargetTypeRef(const SemaNodeView& leftView)
    {
        if (leftView.type() && leftView.type()->isReference())
            return leftView.type()->payloadTypeRef();
        return leftView.typeRef();
    }

    SemaNodeView assignmentTargetView(Sema& sema, const SemaNodeView& leftView)
    {
        SemaNodeView  targetView    = leftView;
        const TypeRef targetTypeRef = assignmentTargetTypeRef(leftView);
        if (targetTypeRef != leftView.typeRef())
        {
            targetView.typeRef() = targetTypeRef;
            targetView.type()    = &sema.typeMgr().get(targetTypeRef);
        }
        return targetView;
    }

    Result checkAssignModifiers(Sema& sema, const AstAssignStmt& node)
    {
        const TokenId tokId = sema.token(node.codeRef()).id;
        auto          allowed =
            AstModifierFlagsE::NoDrop |
            AstModifierFlagsE::Move |
            AstModifierFlagsE::Relocate;

        switch (tokId)
        {
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
            case TokenId::SymAsteriskEqual:
                allowed.add(AstModifierFlagsE::Wrap | AstModifierFlagsE::Promote);
                break;

            case TokenId::SymSlashEqual:
            case TokenId::SymPercentEqual:
                allowed.add(AstModifierFlagsE::Promote);
                break;

            case TokenId::SymLowerLowerEqual:
            case TokenId::SymGreaterGreaterEqual:
                allowed.add(AstModifierFlagsE::Wrap);
                break;

            default:
                break;
        }

        SWC_RESULT(SemaCheck::modifiers(sema, node, node.modifierFlags, allowed));

        // '#relocate' already implies an uninitialized target and an abandoned source.
        if (node.modifierFlags.has(AstModifierFlagsE::Relocate) &&
            (node.modifierFlags.has(AstModifierFlagsE::Move) || node.modifierFlags.has(AstModifierFlagsE::NoDrop)))
            return SemaError::raise(sema, DiagnosticId::sema_err_relocate_modifier_conflict, sema.curNodeRef());

        return Result::Continue;
    }

    const TypeInfo& aliasType(Sema& sema, const SemaNodeView& view)
    {
        const TypeRef typeRef = sema.typeMgr().get(view.typeRef()).unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Alias);
        SWC_ASSERT(typeRef.isValid());
        return sema.typeMgr().get(typeRef);
    }

    bool shouldReadReferenceValue(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeRef normalizedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (!normalizedTypeRef.isValid())
            return false;

        const TypeInfo& normalizedType = sema.typeMgr().get(normalizedTypeRef);
        return normalizedType.isReference();
    }

    Result readReferenceValue(Sema& sema, SemaNodeView& view)
    {
        if (!shouldReadReferenceValue(sema, view.typeRef()))
            return Result::Continue;

        const TypeRef normalizedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), view.typeRef());
        const TypeRef valueTypeRef      = sema.typeMgr().get(normalizedTypeRef).payloadTypeRef();
        SWC_RESULT(Cast::cast(sema, view, valueTypeRef, CastKind::Implicit));
        return Result::Continue;
    }

    Result checkIntegerModifiers(Sema& sema, const AstAssignStmt& node, const SemaNodeView& nodeLeftView)
    {
        if (!node.modifierFlags.hasAny({AstModifierFlagsE::Wrap, AstModifierFlagsE::Promote}))
            return Result::Continue;

        const auto targetLeftView = assignmentTargetView(sema, nodeLeftView);
        if (aliasType(sema, targetLeftView).isIntLike())
            return Result::Continue;

        const SourceView& srcView = sema.compiler().srcView(node.srcViewRef());
        const TokenRef    mdfRef  = srcView.findRightFrom(node.tokRef(), {TokenId::ModifierWrap, TokenId::ModifierPromote});
        auto              diag    = SemaError::report(sema, DiagnosticId::sema_err_modifier_only_integer, SourceCodeRef{node.srcViewRef(), mdfRef});
        diag.addArgument(Diagnostic::ARG_TYPE, targetLeftView.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    bool needsAssignOverflowRuntimeSafety(const AstAssignStmt& node, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView, Sema& sema)
    {
        if (op == TokenId::SymEqual)
            return false;

        const auto targetLeftView = assignmentTargetView(sema, nodeLeftView);
        if (!targetLeftView.type() || !nodeRightView.type())
            return false;
        if (!aliasType(sema, targetLeftView).isIntLike() || !aliasType(sema, nodeRightView).isIntLike())
            return false;
        return SemaHelpers::binaryOpNeedsOverflowSafety(Token::canonicalBinary(op), node.modifierFlags);
    }

    void markAssignmentTargetAddressableStorage(const SemaNodeView& leftView)
    {
        if (!leftView.sym() || !leftView.sym()->isVariable() || !leftView.type())
            return;
        if (leftView.type()->isReference())
            return;

        auto& symVar = leftView.sym()->cast<SymbolVariable>();
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            symVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
    }

    Result emitAssignmentCastFailure(Sema& sema, CastRequest& castRequest, AstNodeRef leftRef, DiagnosticId noteId)
    {
        if (noteId != DiagnosticId::None && castRequest.failure.noteId == DiagnosticId::None)
        {
            castRequest.failure.noteId      = noteId;
            castRequest.failure.noteNodeRef = leftRef;
        }

        return Cast::emitCastFailure(sema, castRequest.failure);
    }

    Result tryAssignmentCast(Sema& sema, AstNodeRef leftRef, const SemaNodeView& leftView, TypeRef srcTypeRef, AstNodeRef errorNodeRef = AstNodeRef::invalid(), DiagnosticId noteId = DiagnosticId::None)
    {
        CastRequest castRequest(CastKind::Assignment);
        castRequest.errorNodeRef    = errorNodeRef.isValid() ? errorNodeRef : leftRef;
        const TypeRef targetTypeRef = assignmentTargetTypeRef(leftView);
        if (Cast::castAllowed(sema, castRequest, srcTypeRef, targetTypeRef) != Result::Continue)
            return emitAssignmentCastFailure(sema, castRequest, leftRef, noteId);
        return Result::Continue;
    }

    const TypeInfo& aliasEnumType(Sema& sema, const SemaNodeView& view)
    {
        const TypeRef typeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), view.typeRef());
        SWC_ASSERT(typeRef.isValid());
        return sema.typeMgr().get(typeRef);
    }

    TypeRef compoundPointerArithmeticResultTypeRef(Sema& sema, TokenId binOp, const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        if (!leftView.type() || !rightView.type())
            return TypeRef::invalid();

        const TypeInfo& leftType  = aliasEnumType(sema, leftView);
        const TypeInfo& rightType = aliasEnumType(sema, rightView);
        switch (binOp)
        {
            case TokenId::SymPlus:
                if (leftType.isBlockPointer() && aliasType(sema, rightView).isIntLike())
                    return leftView.typeRef();
                if (aliasType(sema, leftView).isIntLike() && rightType.isBlockPointer())
                    return rightView.typeRef();
                break;

            case TokenId::SymMinus:
                if (leftType.isBlockPointer() && aliasType(sema, rightView).isIntLike())
                    return leftView.typeRef();
                if (leftType.isBlockPointer() && rightType.isBlockPointer())
                    return sema.typeMgr().typeS64();
                break;

            default:
                break;
        }

        return TypeRef::invalid();
    }

    Result tryCompoundAssignmentCast(Sema& sema, TokenId op, AstNodeRef leftRef, const SemaNodeView& leftView, const SemaNodeView& rightView, AstNodeRef errorNodeRef = AstNodeRef::invalid(), DiagnosticId noteId = DiagnosticId::None)
    {
        const auto    targetLeftView = assignmentTargetView(sema, leftView);
        const TokenId binOp          = Token::assignToBinary(op);

        const TypeRef pointerResultTypeRef = compoundPointerArithmeticResultTypeRef(sema, binOp, targetLeftView, rightView);
        if (pointerResultTypeRef.isValid())
        {
            SWC_RESULT(tryAssignmentCast(sema, leftRef, leftView, pointerResultTypeRef, errorNodeRef, noteId));
            if (aliasEnumType(sema, targetLeftView).isBlockPointer() && aliasType(sema, rightView).isIntLike() && rightView.type()->isScalarNumeric())
            {
                CastRequest castRequest(CastKind::Assignment);
                castRequest.errorNodeRef = errorNodeRef.isValid() ? errorNodeRef : leftRef;
                if (Cast::castAllowed(sema, castRequest, rightView.typeRef(), sema.typeMgr().typeS64()) != Result::Continue)
                    return emitAssignmentCastFailure(sema, castRequest, leftRef, noteId);
            }
            return Result::Continue;
        }

        return tryAssignmentCast(sema, leftRef, leftView, rightView.typeRef(), errorNodeRef, noteId);
    }

    void applyMoveAssignmentModifiers(Sema& sema, AstModifierFlags modifierFlags, SemaNodeView& rightView)
    {
        if (!modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::Relocate}))
            return;
        if (!rightView.type() || !rightView.type()->isMoveReference())
            return;

        const TypeRef valueTypeRef = rightView.type()->payloadTypeRef();
        rightView.typeRef()        = valueTypeRef;
        rightView.type()           = &sema.typeMgr().get(valueTypeRef);
    }

    void markMoveAssignmentSourceAddressableStorage(AstModifierFlags modifierFlags, const SemaNodeView& rightView)
    {
        if (!modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::Relocate}))
            return;
        if (!rightView.sym() || !rightView.sym()->isVariable() || !rightView.type())
            return;
        if (rightView.type()->isReference() || rightView.type()->isAnyPointer() || rightView.type()->isMoveReference())
            return;

        auto& symVar = rightView.sym()->cast<SymbolVariable>();
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            symVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
    }

    Result checkRightConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView)
    {
        const TypeInfo& type = aliasType(sema, nodeRightView);
        switch (op)
        {
            case TokenId::SymSlashEqual:
            case TokenId::SymPercentEqual:
                if (type.isFloat() && nodeRightView.cst()->getFloat().isZero())
                    return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef());
                if (type.isIntLike() && nodeRightView.cst()->getIntLike().isZero())
                    return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef());
                break;

            default:
                break;
        }

        return Result::Continue;
    }

    Result castAndResultType(Sema& sema, TokenId op, const SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        const TokenId binOp                = op == TokenId::SymEqual ? op : Token::assignToBinary(op);
        const auto    targetLeftView       = assignmentTargetView(sema, nodeLeftView);
        const TypeRef pointerResultTypeRef = compoundPointerArithmeticResultTypeRef(sema, binOp, targetLeftView, nodeRightView);
        if (pointerResultTypeRef.isValid())
            SWC_RESULT(tryAssignmentCast(sema, nodeLeftView.nodeRef(), nodeLeftView, pointerResultTypeRef, sema.curNodeRef(), DiagnosticId::sema_note_assignment_target_here));

        SWC_RESULT(SemaHelpers::castBinaryRightToLeft(sema, binOp, sema.curNodeRef(), targetLeftView, nodeRightView, CastKind::Assignment));
        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView)
    {
        if (nodeRightView.cstRef().isValid())
            SWC_RESULT(checkRightConstant(sema, op, nodeRef, nodeRightView));

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

        SWC_RESULT(SemaCheck::isValue(sema, nodeRightView.nodeRef()));

        if (!nodeRightView.type()->isStruct())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_struct, nodeRightView.nodeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, nodeRightView.typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        SWC_RESULT(sema.waitSemaCompleted(nodeRightView.type(), nodeRightView.nodeRef()));

        const SymbolStruct& symStruct = nodeRightView.type()->payloadSymStruct();
        const auto&         fields    = symStruct.fields();

        SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, sema.curNodeRef(), sema.node(sema.curNodeRef()), nodeRightView.typeRef(), "__assign_decomp_runtime_storage"));

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

            const SemaNodeView leftView = sema.viewNodeTypeSymbol(leftRef);
            SWC_RESULT(SemaCheck::isAssignable(sema, sema.curNodeRef(), leftRef, leftView, true));
            markAssignmentTargetAddressableStorage(leftView);

            SWC_RESULT(tryAssignmentCast(sema, leftRef, leftView, fields[i]->typeRef()));
        }

        return Result::Continue;
    }

    Result assignMulti(Sema& sema, const Token& tok, const AstAssignList& assignList, AstModifierFlags modifierFlags, SemaNodeView nodeRightView)
    {
        SmallVector<AstNodeRef> leftRefs;
        sema.ast().appendNodes(leftRefs, assignList.spanChildrenRef);

        applyMoveAssignmentModifiers(sema, modifierFlags, nodeRightView);

        if (tok.id == TokenId::SymEqual)
        {
            SWC_RESULT(SemaCheck::isValueOrType(sema, nodeRightView));
        }
        else
        {
            SWC_RESULT(SemaCheck::isValue(sema, nodeRightView.nodeRef()));
            SWC_RESULT(readReferenceValue(sema, nodeRightView));
        }

        if (nodeRightView.cstRef().isValid())
            SWC_RESULT(checkRightConstant(sema, tok.id, sema.curNodeRef(), nodeRightView));

        for (const auto leftRef : leftRefs)
        {
            if (sema.node(leftRef).is(AstNodeId::AssignIgnore))
                continue;

            const SemaNodeView leftView = sema.viewNodeTypeSymbol(leftRef);
            SWC_RESULT(SemaCheck::isAssignable(sema, sema.curNodeRef(), leftRef, leftView, true));
            markAssignmentTargetAddressableStorage(leftView);

            if (tok.id != TokenId::SymEqual)
            {
                const TokenId binOp          = Token::assignToBinary(tok.id);
                const auto    targetLeftView = assignmentTargetView(sema, leftView);
                SWC_RESULT(SemaHelpers::checkBinaryOperandTypes(sema, sema.curNodeRef(), binOp, leftRef, nodeRightView.nodeRef(), targetLeftView, nodeRightView));
            }

            if (tok.id == TokenId::SymEqual)
            {
                SWC_RESULT(SemaCheck::noCopyOfNonCopyable(sema, nodeRightView.nodeRef(), nodeRightView.typeRef(), leftView.typeRef(), modifierFlags, false));
                SWC_RESULT(tryAssignmentCast(sema, leftRef, leftView, nodeRightView.typeRef(), nodeRightView.nodeRef(), DiagnosticId::sema_note_assignment_target_here));
            }
            else
                SWC_RESULT(tryCompoundAssignmentCast(sema, tok.id, leftRef, leftView, nodeRightView, nodeRightView.nodeRef(), DiagnosticId::sema_note_assignment_target_here));
        }

        return Result::Continue;
    }

}

Result AstAssignStmt::semaPreNode(Sema& sema) const
{
    SWC_RESULT(checkAssignModifiers(sema, *this));
    return Result::Continue;
}

Result AstAssignStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef && nodeRightRef.isValid())
    {
        // Provide a type hint to the RHS: `a = expr` should type `expr` as `typeof(a)` when possible.
        const SemaNodeView leftView = sema.viewType(nodeLeftRef);
        if (leftView.typeRef().isValid())
        {
            TypeRef specOpBindingTypeRef = TypeRef::invalid();
            SWC_RESULT(SemaSpecOp::resolveAssignLambdaBindingType(sema, *this, leftView, specOpBindingTypeRef));

            auto frame = sema.frame();
            frame.pushBindingType(leftView.typeRef());
            frame.pushBindingType(specOpBindingTypeRef);
            SemaHelpers::preferContextualAutoMemberBindingType(sema, nodeRightRef);
            sema.pushFramePopOnPostChild(frame, nodeRightRef);
        }
    }

    return Result::Continue;
}

Result AstAssignStmt::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeLeftView  = sema.viewNodeTypeSymbol(nodeLeftRef);
    SemaNodeView       nodeRightView = sema.viewNodeTypeConstantSymbol(nodeRightRef);

    const Token& tok = sema.token(codeRef());
    if (nodeLeftView.node()->is(AstNodeId::AssignList))
    {
        const auto& assignList = nodeLeftView.node()->cast<AstAssignList>();
        if (assignList.hasFlag(AstAssignListFlagsE::Destructuring))
            return assignDecomposition(sema, tok, assignList, modifierFlags, nodeRightView);
        return assignMulti(sema, tok, assignList, modifierFlags, nodeRightView);
    }

    bool handled = false;
    SWC_RESULT(SemaSpecOp::tryResolveIndexAssign(sema, *this, handled));
    if (handled)
        return Result::Continue;

    SWC_RESULT(SemaCheck::isAssignable(sema, sema.curNodeRef(), nodeLeftRef, nodeLeftView, true));
    markAssignmentTargetAddressableStorage(nodeLeftView);
    SWC_RESULT(SemaSpecOp::tryResolveAssign(sema, *this, nodeLeftView, handled));
    if (handled)
        return Result::Continue;

    applyMoveAssignmentModifiers(sema, modifierFlags, nodeRightView);
    markMoveAssignmentSourceAddressableStorage(modifierFlags, nodeRightView);

    if (tok.id == TokenId::SymEqual)
    {
        SWC_RESULT(SemaCheck::isValueOrType(sema, nodeRightView));
        SWC_RESULT(SemaCheck::noCopyOfNonCopyable(sema, nodeRightView.nodeRef(), nodeRightView.typeRef(), nodeLeftView.typeRef(), modifierFlags, false));
        SWC_RESULT(check(sema, tok.id, sema.curNodeRef(), nodeRightView));
    }
    else
    {
        SWC_RESULT(SemaCheck::isValue(sema, nodeRightView.nodeRef()));
        SWC_RESULT(readReferenceValue(sema, nodeRightView));
        SWC_RESULT(check(sema, tok.id, sema.curNodeRef(), nodeRightView));
        const TokenId binOp          = Token::assignToBinary(tok.id);
        const auto    targetLeftView = assignmentTargetView(sema, nodeLeftView);
        SWC_RESULT(SemaHelpers::checkBinaryOperandTypes(sema, sema.curNodeRef(), binOp, nodeLeftRef, nodeRightRef, targetLeftView, nodeRightView));
    }

    SWC_RESULT(checkIntegerModifiers(sema, *this, nodeLeftView));
    SWC_RESULT(castAndResultType(sema, tok.id, nodeLeftView, nodeRightView));
    if (needsAssignOverflowRuntimeSafety(*this, tok.id, nodeLeftView, nodeRightView, sema))
        SWC_RESULT(SemaHelpers::setupRuntimeSafetyPanic(sema, sema.curNodeRef(), Runtime::SafetyWhat::Overflow, codeRef()));
    return Result::Continue;
}

SWC_END_NAMESPACE();
