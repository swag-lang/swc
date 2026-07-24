#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result tryImplicitBranchCast(Sema& sema, const SemaNodeView& branchView, TypeRef bindingTypeRef)
    {
        CastRequest castRequest(CastKind::Implicit);
        castRequest.errorNodeRef = branchView.nodeRef();
        return Cast::castAllowed(sema, castRequest, branchView.typeRef(), bindingTypeRef);
    }

    bool isUnsizedScalarConstant(const SemaNodeView& view)
    {
        return view.cstRef().isValid() && view.type() && view.type()->isScalarUnsized();
    }

    Result resolveUnsizedConstantAgainstTypedBranch(Sema& sema, TypeRef& outTypeRef, const SemaNodeView& nodeTrueView, const SemaNodeView& nodeFalseView)
    {
        const bool trueUnsizedConstant  = isUnsizedScalarConstant(nodeTrueView);
        const bool falseUnsizedConstant = isUnsizedScalarConstant(nodeFalseView);
        if (trueUnsizedConstant == falseUnsizedConstant)
            return Result::Continue;

        const SemaNodeView& unsizedView = trueUnsizedConstant ? nodeTrueView : nodeFalseView;
        const SemaNodeView& typedView   = trueUnsizedConstant ? nodeFalseView : nodeTrueView;
        if (!typedView.type() || typedView.type()->isScalarUnsized())
            return Result::Continue;

        const Result castResult = tryImplicitBranchCast(sema, unsizedView, typedView.typeRef());
        if (castResult == Result::Pause)
            return Result::Pause;
        if (castResult == Result::Continue)
            outTypeRef = typedView.typeRef();

        return Result::Continue;
    }

    Result resolveTypeLikeConditionalResultType(Sema& sema, TypeRef& outTypeRef, const SemaNodeView& nodeTrueView, const SemaNodeView& nodeFalseView)
    {
        outTypeRef = TypeRef::invalid();

        const TaskContext& ctx                    = sema.ctx();
        const TypeRef      normalizedTrueTypeRef  = SemaHelpers::normalizeTypeLikeValueTypeRef(sema, nodeTrueView.typeRef(), nodeTrueView.cstRef(), nodeTrueView.nodeRef());
        const TypeRef      normalizedFalseTypeRef = SemaHelpers::normalizeTypeLikeValueTypeRef(sema, nodeFalseView.typeRef(), nodeFalseView.cstRef(), nodeFalseView.nodeRef());
        if (normalizedTrueTypeRef == nodeTrueView.typeRef() && normalizedFalseTypeRef == nodeFalseView.typeRef())
            return Result::Continue;

        if (!normalizedTrueTypeRef.isValid() || !normalizedFalseTypeRef.isValid())
            return Result::Continue;

        if (normalizedTrueTypeRef == normalizedFalseTypeRef)
        {
            outTypeRef = normalizedTrueTypeRef;
            return Result::Continue;
        }

        const TypeInfo& normalizedTrueType  = sema.typeMgr().get(normalizedTrueTypeRef);
        const TypeInfo& normalizedFalseType = sema.typeMgr().get(normalizedFalseTypeRef);
        if (normalizedTrueType.isAnyTypeInfo(ctx) && normalizedFalseType.isAnyTypeInfo(ctx))
            outTypeRef = sema.typeMgr().typeTypeInfo();

        return Result::Continue;
    }

    TypeRef preserveUnambiguousConditionalAlias(const TypeRef resultTypeRef, const TypeRef trueTypeRef, const TypeRef concreteTrueTypeRef, const TypeRef falseTypeRef, const TypeRef concreteFalseTypeRef)
    {
        const bool preserveTrueAlias  = trueTypeRef != concreteTrueTypeRef && concreteTrueTypeRef == resultTypeRef;
        const bool preserveFalseAlias = falseTypeRef != concreteFalseTypeRef && concreteFalseTypeRef == resultTypeRef;
        if (preserveTrueAlias == preserveFalseAlias)
            return resultTypeRef;
        return preserveTrueAlias ? trueTypeRef : falseTypeRef;
    }

    TypeRef resolveConditionalNullabilityJoin(Sema& sema, const TypeRef trueTypeRef, const TypeRef falseTypeRef)
    {
        const TypeInfo& rawTrueType          = sema.typeMgr().get(trueTypeRef);
        const TypeRef   concreteTrueTypeRef  = rawTrueType.unwrap(sema.ctx(), trueTypeRef, TypeExpandE::Alias);
        const TypeInfo& trueType             = sema.typeMgr().get(concreteTrueTypeRef);
        const TypeInfo& rawFalseType         = sema.typeMgr().get(falseTypeRef);
        const TypeRef   concreteFalseTypeRef = rawFalseType.unwrap(sema.ctx(), falseTypeRef, TypeExpandE::Alias);
        const TypeInfo& falseType            = sema.typeMgr().get(concreteFalseTypeRef);

        if (trueType.isNull() || falseType.isNull())
        {
            const TypeInfo& valueType = trueType.isNull() ? falseType : trueType;
            if (!valueType.isSupportsNullableQualifier())
                return TypeRef::invalid();

            TypeInfo resultType = valueType;
            resultType.addFlag(TypeInfoFlagsE::Nullable);
            const TypeRef resultTypeRef = sema.typeMgr().addType(resultType);
            return preserveUnambiguousConditionalAlias(resultTypeRef, trueTypeRef, concreteTrueTypeRef, falseTypeRef, concreteFalseTypeRef);
        }

        if (!trueType.isSupportsNullableQualifier() || !falseType.isSupportsNullableQualifier())
            return TypeRef::invalid();

        TypeInfo trueBaseType = trueType;
        trueBaseType.removeFlag(TypeInfoFlagsE::Nullable);
        TypeInfo falseBaseType = falseType;
        falseBaseType.removeFlag(TypeInfoFlagsE::Nullable);
        if (trueBaseType != falseBaseType)
            return TypeRef::invalid();

        TypeInfo resultType = trueBaseType;
        if (trueType.isNullable() || falseType.isNullable())
            resultType.addFlag(TypeInfoFlagsE::Nullable);

        const TypeRef resultTypeRef = sema.typeMgr().addType(resultType);
        return preserveUnambiguousConditionalAlias(resultTypeRef, trueTypeRef, concreteTrueTypeRef, falseTypeRef, concreteFalseTypeRef);
    }

    Result resolveConditionalResultType(Sema& sema, TypeRef& outTypeRef, const SemaNodeView& nodeTrueView, const SemaNodeView& nodeFalseView)
    {
        outTypeRef = TypeRef::invalid();

        SWC_RESULT(resolveTypeLikeConditionalResultType(sema, outTypeRef, nodeTrueView, nodeFalseView));
        if (outTypeRef.isValid())
            return Result::Continue;

        SWC_RESULT(resolveUnsizedConstantAgainstTypedBranch(sema, outTypeRef, nodeTrueView, nodeFalseView));
        if (outTypeRef.isValid())
            return Result::Continue;

        const std::span<const SemaFrame> frames = sema.frames();
        for (size_t frameIndex = frames.size(); frameIndex > 0; --frameIndex)
        {
            const std::span<const TypeRef> bindingTypes = frames[frameIndex - 1].bindingTypes();
            for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
            {
                const TypeRef bindingTypeRef = bindingTypes[bindingIndex - 1];
                if (!bindingTypeRef.isValid())
                    continue;

                const Result trueCastResult = tryImplicitBranchCast(sema, nodeTrueView, bindingTypeRef);
                if (trueCastResult == Result::Pause)
                    return Result::Pause;
                if (trueCastResult != Result::Continue)
                    continue;

                const Result falseCastResult = tryImplicitBranchCast(sema, nodeFalseView, bindingTypeRef);
                if (falseCastResult == Result::Pause)
                    return Result::Pause;
                if (falseCastResult != Result::Continue)
                    continue;

                outTypeRef = bindingTypeRef;
                return Result::Continue;
            }
        }

        if (nodeTrueView.typeRef() == nodeFalseView.typeRef())
        {
            outTypeRef = nodeTrueView.typeRef();
            return Result::Continue;
        }

        outTypeRef = resolveConditionalNullabilityJoin(sema, nodeTrueView.typeRef(), nodeFalseView.typeRef());
        if (outTypeRef.isValid())
            return Result::Continue;

        outTypeRef = Cast::castAllowedBothWays(sema, nodeTrueView.typeRef(), nodeFalseView.typeRef());
        return Result::Continue;
    }

    TypeRef resolveNullCoalescingResultType(Sema& sema, const TypeRef leftTypeRef, const TypeRef rightTypeRef)
    {
        const TypeInfo& rawLeftType         = sema.typeMgr().get(leftTypeRef);
        const TypeRef   concreteLeftTypeRef = rawLeftType.unwrap(sema.ctx(), leftTypeRef, TypeExpandE::Alias);
        const TypeInfo& leftType            = sema.typeMgr().get(concreteLeftTypeRef);
        if (!leftType.isSupportsNullableQualifier() || leftType.isNonNullable())
            return leftTypeRef;

        TypeInfo resultType = leftType;
        resultType.removeFlag(TypeInfoFlagsE::Nullable);

        // The left branch is selected only when it is present, so the fallback
        // determines the result contract. An explicit non-null lhs remains non-null.
        const TypeInfo& rawRightType         = sema.typeMgr().get(rightTypeRef);
        const TypeRef   concreteRightTypeRef = rawRightType.unwrap(sema.ctx(), rightTypeRef, TypeExpandE::Alias);
        const TypeInfo& rightType            = sema.typeMgr().get(concreteRightTypeRef);
        if (rightType.isNull() || rightType.isNullable())
            resultType.addFlag(TypeInfoFlagsE::Nullable);

        const TypeRef resultTypeRef = sema.typeMgr().addType(resultType);
        return resultTypeRef == concreteLeftTypeRef ? leftTypeRef : resultTypeRef;
    }

    // A '?.' chain whose result type cannot carry the null outcome fuses with an
    // enclosing 'orelse': the chain's null exit lands directly on the fallback, so
    // no truthiness test of the produced value is involved.
    bool isFusedOptionalChainLeft(Sema& sema, const SemaNodeView& nodeLeftView)
    {
        if (!nodeLeftView.node() || !nodeLeftView.node()->is(AstNodeId::OptionalChainExpr))
            return false;
        if (!nodeLeftView.typeRef().isValid())
            return false;

        const TypeRef unwrappedRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), nodeLeftView.typeRef());
        return unwrappedRef.isValid() && !sema.typeMgr().get(unwrappedRef).isNullable();
    }
}

Result AstConditionalExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // `cond ? a : b`: each branch only evaluates on the matching truth of the condition,
    // so it inherits the condition's narrowing facts.
    if (childRef == nodeTrueRef || childRef == nodeFalseRef)
    {
        SemaHelpers::NullNarrowGuards guards;
        SemaHelpers::collectNullNarrowGuards(sema, nodeCondRef, guards);
        const auto& facts = childRef == nodeTrueRef ? guards.whenTrue : guards.whenFalse;
        if (!facts.empty())
        {
            SemaFrame frame = sema.frame();
            SemaHelpers::addNullNarrowFacts(frame, {facts.data(), facts.size()});
            sema.pushFramePopOnPostChild(frame, childRef);
        }
    }

    return Result::Continue;
}

Result AstConditionalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeCondView  = sema.viewNodeTypeConstant(nodeCondRef);
    SemaNodeView nodeTrueView  = sema.viewNodeTypeConstant(nodeTrueRef);
    SemaNodeView nodeFalseView = sema.viewNodeTypeConstant(nodeFalseRef);

    // Value-check
    SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, nodeTrueView));
    SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, nodeFalseView));
    sema.setIsValue(*this);

    // Condition must be bool
    SWC_RESULT(SemaCheck::castToBool(sema, nodeCondView));

    // Make both branches compatible
    TypeRef typeRef = TypeRef::invalid();
    SWC_RESULT(resolveConditionalResultType(sema, typeRef, nodeTrueView, nodeFalseView));

    if (!typeRef.isValid())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_binary_operand_type, codeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeTrueView.typeRef());
        diag.addNote(DiagnosticId::sema_note_other_definition);
        diag.last().addSpan(nodeFalseView.node()->codeRangeWithChildren(sema.ctx(), sema.ast()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    sema.setType(sema.curNodeRef(), typeRef);

    // Constant folding
    if (nodeCondView.cstRef().isValid())
    {
        const AstNodeRef selectedBranchRef  = nodeCondView.cst()->getBool() ? nodeTrueRef : nodeFalseRef;
        SemaNodeView     selectedBranchView = sema.viewNodeTypeConstant(selectedBranchRef);
        SWC_RESULT(Cast::cast(sema, selectedBranchView, typeRef, CastKind::Implicit));
        sema.setSubstitute(sema.curNodeRef(), selectedBranchView.nodeRef());
        if (selectedBranchView.cstRef().isValid())
            sema.setConstant(sema.curNodeRef(), selectedBranchView.cstRef());
    }
    else
    {
        SemaNodeView mutableTrueView  = sema.viewNodeTypeConstant(nodeTrueRef);
        SemaNodeView mutableFalseView = sema.viewNodeTypeConstant(nodeFalseRef);
        SWC_RESULT(Cast::cast(sema, mutableTrueView, typeRef, CastKind::Implicit));
        SWC_RESULT(Cast::cast(sema, mutableFalseView, typeRef, CastKind::Implicit));
    }

    return Result::Continue;
}

Result AstNullCoalescingExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeLeftView  = sema.viewNodeTypeConstant(nodeLeftRef);
    SemaNodeView       nodeRightView = sema.viewNodeTypeConstant(nodeRightRef);

    // Value-check
    SWC_RESULT(SemaCheck::isValue(sema, nodeLeftView.nodeRef()));
    SWC_RESULT(SemaCheck::isValue(sema, nodeRightView.nodeRef()));
    sema.setIsValue(*this);

    // Fused '?.' chain: the fallback replaces the chain's null outcome, and the
    // produced value flows through untested (its own value may legitimately be
    // zero or false).
    if (isFusedOptionalChainLeft(sema, nodeLeftView))
    {
        const TypeRef resultTypeRef = nodeLeftView.typeRef();
        SWC_RESULT(Cast::cast(sema, nodeRightView, resultTypeRef, CastKind::Implicit));
        sema.setType(sema.curNodeRef(), resultTypeRef);
        return Result::Continue;
    }

    if (!nodeLeftView.type()->isConvertibleToBoolAliasAware(sema.ctx()))
        return SemaError::raiseBinaryOperandType(sema, sema.curNodeRef(), nodeLeftRef, nodeLeftView.typeRef(), nodeRightView.typeRef());

    const TypeRef resultTypeRef = resolveNullCoalescingResultType(sema, nodeLeftView.typeRef(), nodeRightView.typeRef());
    SWC_RESULT(Cast::cast(sema, nodeRightView, resultTypeRef, CastKind::Implicit));
    sema.setType(sema.curNodeRef(), resultTypeRef);

    // Constant folding
    if (nodeLeftView.cstRef().isValid())
    {
        ConstantRef nodeBoolCstRef = ConstantRef::invalid();
        SWC_RESULT(Cast::castConstant(sema, nodeBoolCstRef, nodeLeftView.cstRef(), sema.typeMgr().typeBool(), nodeLeftView.nodeRef(), CastKind::Condition));

        const bool        leftIsFalse = nodeBoolCstRef == sema.cstMgr().cstFalse();
        const auto        selectedRef = leftIsFalse ? nodeRightView.nodeRef() : nodeLeftView.nodeRef();
        const ConstantRef selectedCst = leftIsFalse ? nodeRightView.cstRef() : nodeLeftView.cstRef();
        if (selectedCst.isValid())
        {
            // Nullability qualifiers do not change representation. Retag the selected
            // constant so '#typeof' observes the same contract as the expression.
            ConstantValue resultCst = sema.cstMgr().get(selectedCst);
            resultCst.setTypeRef(resultTypeRef);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), resultCst));
        }
        else
            sema.setSubstitute(sema.curNodeRef(), selectedRef);
    }

    return Result::Continue;
}

Result AstOptionalChainExpr::semaPostNode(Sema& sema)
{
    const SemaNodeView exprView = sema.viewNodeType(nodeExprRef);
    if (!exprView.typeRef().isValid())
        return Result::Error;

    const TypeRef unwrappedRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), exprView.typeRef());
    SWC_ASSERT(unwrappedRef.isValid());
    const TypeInfo& exprType = sema.typeMgr().get(unwrappedRef);

    // A skipped void chain is a statement: its null exit simply lands after the call.
    if (exprType.isVoid())
    {
        sema.setType(sema.curNodeRef(), exprView.typeRef());
        return Result::Continue;
    }

    SWC_RESULT(SemaCheck::isValue(sema, exprView.nodeRef()));
    sema.setIsValue(*this);

    // A nullable-capable result carries the null outcome in its own type.
    if (exprType.isSupportsNullableQualifier())
    {
        TypeRef resultTypeRef = exprView.typeRef();
        if (!exprType.isNullable())
        {
            TypeInfo resultType = exprType;
            resultType.addFlag(TypeInfoFlagsE::Nullable);
            resultTypeRef = sema.typeMgr().addType(resultType);
        }
        sema.setType(sema.curNodeRef(), resultTypeRef);

        // Wide results (string, slice, interface, ...) join through an address:
        // the null outcome needs zeroed storage to point at.
        if (exprType.sizeOf(sema.ctx()) > 8)
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, sema.curNodeRef(), *this, resultTypeRef, "__optional_chain_storage"));
        return Result::Continue;
    }

    // Any other result type must hand the null outcome to an immediate 'orelse'
    // fallback (see isFusedOptionalChainLeft).
    const AstNodeRef parentRef = sema.visit().parentNodeRef();
    if (parentRef.isValid() && sema.node(parentRef).is(AstNodeId::NullCoalescingExpr) &&
        sema.node(parentRef).cast<AstNullCoalescingExpr>().nodeLeftRef == sema.curNodeRef())
    {
        sema.setType(sema.curNodeRef(), exprView.typeRef());
        return Result::Continue;
    }

    return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_optional_access_result_type, sema.curNodeRef(), exprView.typeRef());
}

SWC_END_NAMESPACE();
