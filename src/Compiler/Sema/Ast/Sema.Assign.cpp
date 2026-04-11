#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef assignmentTargetTypeRef(const SemaNodeView& leftView, const bool rebindReference)
    {
        if (!rebindReference && leftView.type() && leftView.type()->isReference())
            return leftView.type()->payloadTypeRef();
        return leftView.typeRef();
    }

    SemaNodeView assignmentTargetView(Sema& sema, const SemaNodeView& leftView, const bool rebindReference)
    {
        SemaNodeView  targetView    = leftView;
        const TypeRef targetTypeRef = assignmentTargetTypeRef(leftView, rebindReference);
        if (targetTypeRef != leftView.typeRef())
        {
            targetView.typeRef() = targetTypeRef;
            targetView.type()    = &sema.typeMgr().get(targetTypeRef);
        }
        return targetView;
    }

    bool hasReferenceRebindModifier(const AstModifierFlags modifierFlags)
    {
        return modifierFlags.hasAny({AstModifierFlagsE::Ref, AstModifierFlagsE::ConstRef});
    }

    bool isReferenceRebindAssignment(const Sema& sema, TokenId op, const SemaNodeView& leftView)
    {
        if (op != TokenId::SymEqual)
            return false;
        if (!leftView.type() || !leftView.type()->isReference())
            return false;

        const auto& assignNode = sema.node(sema.curNodeRef()).cast<AstAssignStmt>();

        // `refVar = #ref rhs` rebinds the reference slot instead of assigning through it.
        return hasReferenceRebindModifier(assignNode.modifierFlags);
    }


    Result checkAssignModifiers(Sema& sema, const AstAssignStmt& node)
    {
        const TokenId tokId = sema.token(node.codeRef()).id;
        auto          allowed =
            AstModifierFlagsE::NoDrop |
            AstModifierFlagsE::Ref |
            AstModifierFlagsE::ConstRef |
            AstModifierFlagsE::Move |
            AstModifierFlagsE::MoveRaw;

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

        return SemaCheck::modifiers(sema, node, node.modifierFlags, allowed);
    }

    Result checkIntegerModifiers(Sema& sema, const AstAssignStmt& node, const SemaNodeView& nodeLeftView)
    {
        if (!node.modifierFlags.hasAny({AstModifierFlagsE::Wrap, AstModifierFlagsE::Promote}))
            return Result::Continue;

        const auto targetLeftView = assignmentTargetView(sema, nodeLeftView, false);
        if (targetLeftView.type()->isInt())
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

        const auto targetLeftView = assignmentTargetView(sema, nodeLeftView, false);
        if (!targetLeftView.type() || !nodeRightView.type())
            return false;
        if (!targetLeftView.type()->isIntLike() || !nodeRightView.type()->isIntLike())
            return false;
        return SemaHelpers::binaryOpNeedsOverflowSafety(Token::canonicalBinary(op), node.modifierFlags);
    }

    void markAssignmentTargetAddressableStorage(const SemaNodeView& leftView, const bool rebindReference)
    {
        if (!leftView.sym() || !leftView.sym()->isVariable() || !leftView.type())
            return;
        if (leftView.type()->isReference() && !rebindReference)
            return;

        auto& symVar = leftView.sym()->cast<SymbolVariable>();
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
            symVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
    }

    Result tryAssignmentCast(Sema& sema, AstNodeRef leftRef, const SemaNodeView& leftView, TypeRef srcTypeRef, bool rebindReference)
    {
        CastRequest castRequest(CastKind::Assignment);
        castRequest.errorNodeRef    = leftRef;
        const TypeRef targetTypeRef = assignmentTargetTypeRef(leftView, rebindReference);
        if (Cast::castAllowed(sema, castRequest, srcTypeRef, targetTypeRef) != Result::Continue)
            return Cast::emitCastFailure(sema, castRequest.failure);
        return Result::Continue;
    }

    void applyMoveAssignmentModifiers(Sema& sema, AstModifierFlags modifierFlags, SemaNodeView& rightView)
    {
        if (!modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::MoveRaw}))
            return;
        if (!rightView.type() || !rightView.type()->isMoveReference())
            return;

        const TypeRef valueTypeRef = rightView.type()->payloadTypeRef();
        rightView.typeRef()        = valueTypeRef;
        rightView.type()           = &sema.typeMgr().get(valueTypeRef);
    }

    void markMoveAssignmentSourceAddressableStorage(AstModifierFlags modifierFlags, const SemaNodeView& rightView)
    {
        if (!modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::MoveRaw}))
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
        switch (op)
        {
            case TokenId::SymSlashEqual:
            case TokenId::SymPercentEqual:
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

    Result castAndResultType(Sema& sema, TokenId op, const SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView, const bool rebindReference)
    {
        const TokenId binOp          = op == TokenId::SymEqual ? op : Token::assignToBinary(op);
        const auto    targetLeftView = assignmentTargetView(sema, nodeLeftView, rebindReference);
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
            SWC_RESULT(SemaCheck::isAssignable(sema, sema.curNodeRef(), leftView));
            markAssignmentTargetAddressableStorage(leftView, false);

            SWC_RESULT(tryAssignmentCast(sema, leftRef, leftView, fields[i]->typeRef(), false));
        }

        return Result::Continue;
    }

    Result assignMulti(Sema& sema, const Token& tok, const AstAssignList& assignList, AstModifierFlags modifierFlags, SemaNodeView nodeRightView)
    {
        SmallVector<AstNodeRef> leftRefs;
        sema.ast().appendNodes(leftRefs, assignList.spanChildrenRef);

        applyMoveAssignmentModifiers(sema, modifierFlags, nodeRightView);

        if (nodeRightView.cstRef().isValid())
            SWC_RESULT(checkRightConstant(sema, tok.id, sema.curNodeRef(), nodeRightView));

        if (tok.id == TokenId::SymEqual)
        {
            SWC_RESULT(SemaCheck::isValueOrType(sema, nodeRightView));
        }
        else
        {
            SWC_RESULT(SemaCheck::isValue(sema, nodeRightView.nodeRef()));
        }

        for (const auto leftRef : leftRefs)
        {
            if (sema.node(leftRef).is(AstNodeId::AssignIgnore))
                continue;

            const SemaNodeView leftView        = sema.viewNodeTypeSymbol(leftRef);
            const bool         rebindReference = isReferenceRebindAssignment(sema, tok.id, leftView);
            SWC_RESULT(SemaCheck::isAssignable(sema, sema.curNodeRef(), leftView));
            markAssignmentTargetAddressableStorage(leftView, rebindReference);

            if (tok.id != TokenId::SymEqual)
            {
                const TokenId binOp          = Token::assignToBinary(tok.id);
                const auto    targetLeftView = assignmentTargetView(sema, leftView, rebindReference);
                SWC_RESULT(SemaHelpers::checkBinaryOperandTypes(sema, sema.curNodeRef(), binOp, leftRef, nodeRightView.nodeRef(), targetLeftView, nodeRightView));
            }

            SWC_RESULT(tryAssignmentCast(sema, leftRef, leftView, nodeRightView.typeRef(), rebindReference));
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
            auto frame = sema.frame();
            frame.pushBindingType(leftView.typeRef());
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

    const bool rebindReference = isReferenceRebindAssignment(sema, tok.id, nodeLeftView);
    SWC_RESULT(SemaCheck::isAssignable(sema, sema.curNodeRef(), nodeLeftView));
    markAssignmentTargetAddressableStorage(nodeLeftView, rebindReference);
    SWC_RESULT(SemaSpecOp::tryResolveAssign(sema, *this, nodeLeftView, handled));
    if (handled)
        return Result::Continue;
    SWC_RESULT(check(sema, tok.id, sema.curNodeRef(), nodeRightView));

    applyMoveAssignmentModifiers(sema, modifierFlags, nodeRightView);
    markMoveAssignmentSourceAddressableStorage(modifierFlags, nodeRightView);

    if (tok.id == TokenId::SymEqual)
    {
        SWC_RESULT(SemaCheck::isValueOrType(sema, nodeRightView));
    }
    else
    {
        SWC_RESULT(SemaCheck::isValue(sema, nodeRightView.nodeRef()));
        const TokenId binOp          = Token::assignToBinary(tok.id);
        const auto    targetLeftView = assignmentTargetView(sema, nodeLeftView, rebindReference);
        SWC_RESULT(SemaHelpers::checkBinaryOperandTypes(sema, sema.curNodeRef(), binOp, nodeLeftRef, nodeRightRef, targetLeftView, nodeRightView));
    }

    SWC_RESULT(checkIntegerModifiers(sema, *this, nodeLeftView));
    SWC_RESULT(castAndResultType(sema, tok.id, nodeLeftView, nodeRightView, rebindReference));
    if (needsAssignOverflowRuntimeSafety(*this, tok.id, nodeLeftView, nodeRightView, sema))
        SWC_RESULT(SemaHelpers::setupRuntimeSafetyPanic(sema, sema.curNodeRef(), Runtime::SafetyWhat::Overflow, codeRef()));
    return Result::Continue;
}

SWC_END_NAMESPACE();
