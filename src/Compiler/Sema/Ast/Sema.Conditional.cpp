#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
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

    // Two branches of one concrete type have settled the result on their own. An unsized
    // constant, a 'null', or an untyped aggregate literal still needs the context.
    bool isSettledBranchType(const SemaNodeView& view)
    {
        const TypeInfo* type = view.type();
        return type && !type->isScalarUnsized() && !type->isNull() && !type->isAggregate();
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
        const TypeInfo* unaliasedTrueType    = rawTrueType.unwrapAliasType(sema.ctx());
        const TypeInfo& trueType             = unaliasedTrueType ? *unaliasedTrueType : rawTrueType;
        const TypeRef   concreteTrueTypeRef  = trueType.typeRef();
        const TypeInfo& rawFalseType         = sema.typeMgr().get(falseTypeRef);
        const TypeInfo* unaliasedFalseType   = rawFalseType.unwrapAliasType(sema.ctx());
        const TypeInfo& falseType            = unaliasedFalseType ? *unaliasedFalseType : rawFalseType;
        const TypeRef   concreteFalseTypeRef = falseType.typeRef();

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

        // Two branches that agree on a concrete type keep it: adopting the binding instead
        // would silently convert a typed value, and put its overflow check on the wrong
        // operation.
        if (nodeTrueView.typeRef() == nodeFalseView.typeRef() && isSettledBranchType(nodeTrueView))
        {
            outTypeRef = nodeTrueView.typeRef();
            return Result::Continue;
        }

        const std::span<const TypeRef> bindingTypes = sema.frame().bindingTypes();
        for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
        {
            const TypeRef bindingTypeRef = bindingTypes[bindingIndex - 1];
            const Result  trueCastResult = tryImplicitBranchCast(sema, nodeTrueView, bindingTypeRef);
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
        const TypeInfo* unaliasedLeftType   = rawLeftType.unwrapAliasType(sema.ctx());
        const TypeInfo& leftType            = unaliasedLeftType ? *unaliasedLeftType : rawLeftType;
        const TypeRef   concreteLeftTypeRef = leftType.typeRef();
        if (!leftType.isSupportsNullableQualifier() || leftType.isNonNullable())
            return leftTypeRef;

        // The left branch is selected only when it is present, so the fallback
        // determines the result contract. An explicit non-null lhs remains non-null.
        const TypeInfo& rawRightType         = sema.typeMgr().get(rightTypeRef);
        const TypeInfo* unaliasedRightType   = rawRightType.unwrapAliasType(sema.ctx());
        const TypeInfo& rightType            = unaliasedRightType ? *unaliasedRightType : rawRightType;
        const TypeRef   concreteRightTypeRef = rightType.typeRef();
        if (rightType.isNull() || rightType.isNullable())
            return leftTypeRef;

        TypeInfo resultType = leftType;
        resultType.removeFlag(TypeInfoFlagsE::Nullable);
        const TypeRef resultTypeRef = sema.typeMgr().addType(resultType);
        if (resultTypeRef == concreteLeftTypeRef)
            return leftTypeRef;

        // Narrowing the left changes its concrete type. When the fallback already has
        // that exact result type, keep its alias rather than implicitly stripping it.
        return resultTypeRef == concreteRightTypeRef ? rightTypeRef : resultTypeRef;
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

        return !SemaHelpers::aliasEnumType(sema, nodeLeftView).isNullable();
    }

    // 'orelse' substitutes a MISSING value, never a zero one, so its left operand has to be
    // of a type that can carry null at all. Substituting a zero is a different question, and
    // the ternary already answers it.
    //
    // The test is on the type's CAPABILITY, not on what flow analysis currently knows: a
    // narrowed operand, or a generic instantiated with a non-null argument, keeps compiling.
    // A dead fallback is a code-quality matter, not a broken contract.
    Result checkNullCoalescingOperand(Sema& sema, const SemaNodeView& nodeLeftView)
    {
        const TypeRef leftTypeRef = nodeLeftView.typeRef();
        if (!leftTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& rawLeftType  = *nodeLeftView.type();
        const TypeInfo* aliasType    = rawLeftType.unwrapAliasType(sema.ctx());
        const TypeInfo& concreteType = aliasType ? *aliasType : rawLeftType;
        if (concreteType.isSupportsNullableQualifier())
            return Result::Continue;

        return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_orelse_not_nullable_type, nodeLeftView.nodeRef(), leftTypeRef);
    }
}

Result AstConditionalExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // `cond ? a : b`: each branch only evaluates on the matching truth of the condition,
    // so it inherits the condition's narrowing facts.
    if (childRef == nodeTrueRef || childRef == nodeFalseRef)
    {
        SemaHelpers::NarrowGuards guards;
        SemaHelpers::collectNarrowGuards(sema, nodeCondRef, guards);
        const auto& facts = childRef == nodeTrueRef ? guards.whenTrue : guards.whenFalse;

        // `cond ? Kind.A : .B` where the expression itself has no expected type: the false branch
        // names its members against the enum the true branch settled on, before the enum of an
        // enclosing switch.
        TypeRef enumTypeRef = TypeRef::invalid();
        if (childRef == nodeFalseRef && !sema.frame().hasExpressionBindingTypes())
        {
            const SemaNodeView trueView = sema.viewNodeType(nodeTrueRef);
            if (trueView.type() && trueView.type()->isEnum())
                enumTypeRef = trueView.typeRef();
        }

        if (!facts.empty() || enumTypeRef.isValid())
        {
            SemaFrame frame = sema.frame();
            SemaHelpers::addNarrowFacts(frame, {facts.data(), facts.size()});
            frame.pushBindingType(enumTypeRef);
            sema.pushFramePopOnPostChild(std::move(frame), childRef);
        }
    }

    return Result::Continue;
}

Result AstConditionalExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // A branch only evaluates on its side of the condition, so the facts pushed for it in
    // 'semaPreNodeChild' still hold here -- and this is the last point where they do, because
    // the frame is popped immediately after. Pin the proven type on the branch node: the join
    // and the conversions in 'semaPostNode' run without those facts, so 'c ? p : q!' would
    // join a still-nullable 'p' with a non-null 'q!' and hand back a nullable result the
    // caller has to assert a second time.
    if (childRef != nodeTrueRef && childRef != nodeFalseRef)
        return Result::Continue;
    if (!sema.frame().hasNarrowFacts())
        return Result::Continue;

    const SemaNodeView branchView      = sema.viewNodeType(childRef);
    const TypeRef      narrowedTypeRef = branchView.typeRef();
    if (!narrowedTypeRef.isValid() || narrowedTypeRef == sema.viewStored(childRef, SemaNodeViewPartE::Type).typeRef())
        return Result::Continue;

    sema.setType(branchView.nodeRef(), narrowedTypeRef);
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

    SWC_RESULT(SemaHelpers::materializeMovedValue(sema, nodeTrueView));
    SWC_RESULT(SemaHelpers::materializeMovedValue(sema, nodeFalseView));
    bool ownsValue = SemaHelpers::ownsExpressionValue(sema, nodeTrueView.nodeRef()) ||
                     SemaHelpers::ownsExpressionValue(sema, nodeFalseView.nodeRef());

    // Condition must be bool
    SWC_RESULT(SemaCheck::castToBool(sema, nodeCondView));

    // Make both branches compatible
    TypeRef typeRef = TypeRef::invalid();
    SWC_RESULT(resolveConditionalResultType(sema, typeRef, nodeTrueView, nodeFalseView));

    if (!typeRef.isValid())
        return SemaError::raiseConditionalBranchTypes(sema, sema.curNodeRef(), nodeFalseRef, nodeTrueView.typeRef(), nodeFalseView.typeRef());

    // A runtime select has no single constant to concretize when an inferred
    // local captures it. Settle both integer literal widths here, after contextual
    // bindings have had their chance, so later uses cannot default to s32.
    if (!nodeCondView.cstRef().isValid() && sema.typeMgr().get(typeRef).isIntUnsized() &&
        isUnsizedScalarConstant(nodeTrueView) && isUnsizedScalarConstant(nodeFalseView))
    {
        ConstantRef trueConstant;
        ConstantRef falseConstant;
        SWC_RESULT(Cast::concretizeConstant(sema, trueConstant, nodeTrueView.nodeRef(), nodeTrueView.cstRef(), TypeInfo::Sign::Unknown));
        SWC_RESULT(Cast::concretizeConstant(sema, falseConstant, nodeFalseView.nodeRef(), nodeFalseView.cstRef(), TypeInfo::Sign::Unknown));
        typeRef = sema.typeMgr().promote(sema.cstMgr().get(trueConstant).typeRef(), sema.cstMgr().get(falseConstant).typeRef(), true);
    }

    sema.setType(sema.curNodeRef(), typeRef);

    // Constant folding
    if (nodeCondView.cstRef().isValid() && !ownsValue)
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

        // A branch converted through 'opSet' owns the value it built, like a moved one. The
        // conditional then adopts each branch in its own storage, and drops what a branch
        // left behind before the join, where only that branch's temporaries exist.
        ownsValue = ownsValue || SemaHelpers::ownsExpressionValue(sema, mutableTrueView.nodeRef()) || SemaHelpers::ownsExpressionValue(sema, mutableFalseView.nodeRef());
        if (ownsValue)
        {
            SWC_RESULT(SemaCheck::noCopyOfNonCopyable(sema, nodeTrueView.nodeRef(), nodeTrueView.typeRef(), typeRef, AstModifierFlagsE::Zero, false));
            SWC_RESULT(SemaCheck::noCopyOfNonCopyable(sema, nodeFalseView.nodeRef(), nodeFalseView.typeRef(), typeRef, AstModifierFlagsE::Zero, false));
            SemaHelpers::ensureCodeGenLoweringPayload(sema, sema.curNodeRef()).ownsValue = true;
            SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, *this, typeRef, "__conditional_value"));
        }
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

    SWC_RESULT(checkNullCoalescingOperand(sema, nodeLeftView));

    const TypeRef   resultTypeRef   = resolveNullCoalescingResultType(sema, nodeLeftView.typeRef(), nodeRightView.typeRef());
    TypeRef         fallbackTypeRef = resultTypeRef;
    const TypeInfo& leftType        = SemaHelpers::aliasEnumType(sema, nodeLeftView);
    const TypeInfo& rightType       = SemaHelpers::aliasEnumType(sema, nodeRightView);
    if (leftType.isNonNullable() && (rightType.isNull() || rightType.isNullable()))
    {
        // A non-null left makes the fallback unreachable, including after inline
        // argument substitution. Check its value family without requiring presence.
        TypeInfo fallbackType = leftType;
        fallbackType.addFlag(TypeInfoFlagsE::Nullable);
        fallbackTypeRef = sema.typeMgr().addType(fallbackType);
    }
    SWC_RESULT(Cast::cast(sema, nodeRightView, fallbackTypeRef, CastKind::Implicit));
    sema.setType(sema.curNodeRef(), resultTypeRef);

    // Constant folding
    if (nodeLeftView.cstRef().isValid())
    {
        // 'orelse' asks presence, not truthiness, and its operand is always a nullable-capable
        // family: a constant left selects the fallback exactly when it is null. Reading that
        // from the constant keeps the condition rules off a spelling that is not a condition,
        // where they would reject the dead fallback a non-null left deliberately keeps.
        const bool        leftIsFalse = nodeLeftView.cst()->isNullValue(sema.ctx());
        const auto        selectedRef = leftIsFalse ? nodeRightView.nodeRef() : nodeLeftView.nodeRef();
        const ConstantRef selectedCst = leftIsFalse ? nodeRightView.cstRef() : nodeLeftView.cstRef();
        if (selectedCst.isValid())
        {
            // Nullability qualifiers do not change representation. Retag the selected
            // constant so '#typeof' observes the same contract as the expression.
            const ConstantValue& source       = sema.cstMgr().get(selectedCst);
            ConstantRef          resultCstRef = selectedCst;
            if (source.typeRef() != resultTypeRef)
            {
                ConstantValue resultCst = source;
                resultCst.setTypeRef(resultTypeRef);
                resultCstRef = sema.cstMgr().addConstant(sema.ctx(), resultCst);
            }
            sema.setConstant(sema.curNodeRef(), resultCstRef);
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

    const TypeInfo& exprType = SemaHelpers::aliasEnumType(sema, exprView);

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
