#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenExprView.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    template<typename T>
    inline void resetConditionalLabels(T& payload)
    {
        payload.falseLabel = MicroLabelRef::invalid();
        payload.doneLabel  = MicroLabelRef::invalid();
    }

    bool usesAddressBackedSelection(CodeGen& codeGen, const TypeInfo& typeInfo)
    {
        return !typeInfo.isSimd() && typeInfo.sizeOf(codeGen.ctx()) > 8;
    }

    void emitSelectedOperand(CodeGen& codeGen, const CodeGenNodePayload& resultPayload, const CodeGenNodePayload& operandPayload, MicroOpBits resultBits)
    {
        if (operandPayload.isAddress())
            codeGen.builder().emitLoadRegMem(resultPayload.reg, operandPayload.reg, 0, resultBits);
        else
            codeGen.builder().emitLoadRegReg(resultPayload.reg, operandPayload.reg, resultBits);
    }
}

Result AstConditionalExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef)
{
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);
    SWC_ASSERT(resolvedChildRef.isValid());

    SWC_ASSERT(codeGen.curViewType().type() != nullptr);

    // Select in the stored type. The resolved view can already expose an implicit
    // wrapper's type, but that cast converts the value after the branches join.
    const TypeRef resultTypeRef = codeGen.transparentPayloadTypeRef();
    const auto*   lowering      = codeGen.loweringPayload(codeGen.curNodeRef());
    const bool    ownsValue     = lowering && lowering->ownsValue;
    MicroBuilder& builder       = codeGen.builder();

    ConditionalExprCodeGenPayload* state = codeGen.safeNodePayload<ConditionalExprCodeGenPayload>(codeGen.curNodeRef());

    // Qualification casts can rewrite a direct child to a different resolved reference.
    // Child callbacks still arrive in source order, so track the lowering stage explicitly.
    // A deferred body reuses its payload after the previous emission cleared the labels.
    if (state == nullptr || state->doneLabel.isInvalid())
    {
        // Conditional expressions must short-circuit to preserve branch semantics.
        const CodeGenNodePayload& condPayload = codeGen.payload(resolvedChildRef);
        const TypeRef             condTypeRef = CodeGenExprView::payloadTypeRef(codeGen, condPayload, resolvedChildRef);
        const TypeInfo&           condType    = codeGen.typeMgr().get(condTypeRef);
        const MicroOpBits         condBits    = CodeGenTypeHelpers::compareBits(condType, codeGen.ctx());
        SWC_ASSERT(condBits != MicroOpBits::Zero);

        const MicroReg condReg = CodeGenCompareHelpers::materializeConditionOperand(codeGen, condPayload, condTypeRef, condType, condBits);
        SWC_RESULT(codeGen.flushTemporaryDrops(codeGen.curNodeRef()));

        ConditionalExprCodeGenPayload& newState = codeGen.ensureNodePayload<ConditionalExprCodeGenPayload>(codeGen.curNodeRef());
        newState.falseLabel                     = builder.createLabel();
        newState.doneLabel                      = builder.createLabel();
        newState.stage                          = ConditionalExprStage::TrueBranch;
        if (ownsValue)
        {
            auto& resultPayload   = codeGen.ensureNodePayload<CodeGenNodePayload>(codeGen.curNodeRef());
            resultPayload.reg     = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
            resultPayload.typeRef = resultTypeRef;
            resultPayload.setIsAddress();
            resultPayload.ownsValue = true;
        }

        CodeGenCompareHelpers::emitCompareRegZero(codeGen, condReg, condType, condBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen, condType, CodeGenCompareHelpers::falseyCondition(condType), newState.falseLabel);
        return Result::Continue;
    }

    if (ownsValue)
    {
        const CodeGenNodePayload& resultPayload = codeGen.payload(codeGen.curNodeRef());
        const CodeGenNodePayload& branch        = codeGen.payload(resolvedChildRef);
        CodeGenMemoryHelpers::storePayloadToAddress(codeGen, resultPayload.reg, branch, CodeGenFunctionHelpers::checkedTypeSizeInBytes(codeGen, codeGen.typeMgr().get(resultTypeRef)));
        SWC_RESULT(CodeGenMemoryHelpers::emitDynamicIdentity(codeGen, resultTypeRef, resultPayload.reg));

        const bool copiesBranch = !branch.ownsValue && SemaHelpers::expressionBorrowsStorage(codeGen.sema(), resolvedChildRef);
        const auto postKind     = copiesBranch ? CodeGen::LifecycleKind::PostCopy : CodeGen::LifecycleKind::PostMove;
        if (codeGen.hasLifecycle(resultTypeRef, postKind))
            SWC_RESULT(codeGen.emitLifecycle(resultTypeRef, postKind, resultPayload.reg));

        if (branch.ownsValue && branch.runtimeStorageSym)
            codeGen.cancelTemporaryDrop(*branch.runtimeStorageSym);

        SWC_RESULT(codeGen.flushTemporaryDrops(codeGen.curNodeRef()));

        if (state->stage == ConditionalExprStage::TrueBranch)
        {
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state->doneLabel);
            builder.placeLabel(state->falseLabel);
            state->stage = ConditionalExprStage::FalseBranch;
        }
        else
        {
            builder.placeLabel(state->doneLabel);
            resetConditionalLabels(*state);
        }

        return Result::Continue;
    }

    const TypeInfo& resultType    = codeGen.typeMgr().get(resultTypeRef);
    const bool      addressBacked = usesAddressBackedSelection(codeGen, resultType);
    if (state->stage == ConditionalExprStage::TrueBranch)
    {
        const CodeGenNodePayload& truePayload = codeGen.payload(resolvedChildRef);

        // The false branch reuses the destination payload created here.
        if (addressBacked)
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, truePayload.reg, MicroOpBits::B64);
        }
        else
        {
            const MicroOpBits   resultBits    = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);

            // Match the result register class: integer-register moves would
            // reinterpret a float selection's bits.
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultTypeRef, resultType);
            emitSelectedOperand(codeGen, resultPayload, truePayload, resultBits);
        }

        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state->doneLabel);
        builder.placeLabel(state->falseLabel);
        state->stage = ConditionalExprStage::FalseBranch;
        return Result::Continue;
    }

    if (state->stage == ConditionalExprStage::FalseBranch)
    {
        const CodeGenNodePayload& falsePayload  = codeGen.payload(resolvedChildRef);
        const CodeGenNodePayload& resultPayload = codeGen.payload(codeGen.curNodeRef());
        if (addressBacked)
        {
            builder.emitLoadRegReg(resultPayload.reg, falsePayload.reg, MicroOpBits::B64);
        }
        else
        {
            const MicroOpBits resultBits = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            emitSelectedOperand(codeGen, resultPayload, falsePayload, resultBits);
        }

        builder.placeLabel(state->doneLabel);
        resetConditionalLabels(*state);
    }

    return Result::Continue;
}

Result AstConditionalExpr::codeGenPostNode(CodeGen& codeGen)
{
    if (auto* state = codeGen.safeNodePayload<ConditionalExprCodeGenPayload>(codeGen.curNodeRef()))
        resetConditionalLabels(*state);

    const auto*   lowering = codeGen.loweringPayload(codeGen.curNodeRef());
    const TypeRef typeRef  = codeGen.transparentPayloadTypeRef();
    if (lowering && lowering->ownsValue && lowering->runtimeStorageSym->hasExtraFlag(SymbolVariableFlagsE::RuntimeStorage) &&
        codeGen.hasLifecycle(typeRef, CodeGen::LifecycleKind::Drop))
        codeGen.registerTemporaryDrop(codeGen.curNodeRef(), typeRef, *lowering->runtimeStorageSym);

    return Result::Continue;
}

namespace
{
    // Both truthiness tests and fused optional chains share this left-branch exit.
    void emitNullCoalescingSelectedLeft(CodeGen& codeGen, const NullCoalescingCodeGenPayload& state, const CodeGenNodePayload& leftPayload, const TypeInfo& resultType, bool addressBacked)
    {
        const TypeRef resultTypeRef = resultType.typeRef();
        MicroBuilder& builder       = codeGen.builder();
        if (addressBacked)
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, leftPayload.reg, MicroOpBits::B64);
        }
        else
        {
            const MicroOpBits   resultBits    = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);

            // Match the result register class: integer-register moves would
            // reinterpret a float selection's bits.
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultTypeRef, resultType);
            emitSelectedOperand(codeGen, resultPayload, leftPayload, resultBits);
        }

        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state.doneLabel);
        builder.placeLabel(state.falseLabel);
    }
}

Result AstNullCoalescingExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef)
{
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);
    SWC_ASSERT(resolvedChildRef.isValid());

    // Same stored-type rule as the conditional expression above.
    const TypeRef   resultTypeRef = codeGen.transparentPayloadTypeRef();
    const TypeInfo& resultType    = codeGen.typeMgr().get(resultTypeRef);
    const bool      addressBacked = usesAddressBackedSelection(codeGen, resultType);
    MicroBuilder&   builder       = codeGen.builder();

    NullCoalescingCodeGenPayload* state = codeGen.safeNodePayload<NullCoalescingCodeGenPayload>(codeGen.curNodeRef());

    // Rewrites can change operand references; callback order still identifies
    // lhs then rhs. Deferred bodies reuse the payload after labels are cleared.
    if (state == nullptr || state->doneLabel.isInvalid())
    {
        // Fused '?.' chain: the chain's null exit doubles as this coalescing's false
        // label, and the produced value flows through untested (its own value may
        // legitimately be zero or false).
        OptionalChainCodeGenPayload* chainState = nullptr;
        if (codeGen.node(resolvedChildRef).is(AstNodeId::OptionalChainExpr))
            chainState = codeGen.safeNodePayload<OptionalChainCodeGenPayload>(resolvedChildRef);

        if (chainState != nullptr && chainState->falseLabel.isValid())
        {
            NullCoalescingCodeGenPayload& newState = codeGen.ensureNodePayload<NullCoalescingCodeGenPayload>(codeGen.curNodeRef());
            newState.falseLabel                    = chainState->falseLabel;
            newState.doneLabel                     = chainState->doneLabel;
            chainState->falseLabel                 = MicroLabelRef::invalid();
            chainState->doneLabel                  = MicroLabelRef::invalid();

            emitNullCoalescingSelectedLeft(codeGen, newState, codeGen.payload(resolvedChildRef), resultType, addressBacked);
            return Result::Continue;
        }

        const CodeGenNodePayload& leftPayload = codeGen.payload(resolvedChildRef);
        const TypeRef             leftTypeRef = CodeGenExprView::payloadTypeRef(codeGen, leftPayload, resolvedChildRef);
        const TypeInfo&           leftType    = codeGen.typeMgr().get(leftTypeRef);
        const MicroOpBits         condBits    = CodeGenTypeHelpers::compareBits(leftType, codeGen.ctx());
        SWC_ASSERT(condBits != MicroOpBits::Zero);

        const MicroReg condReg = CodeGenCompareHelpers::materializeConditionOperand(codeGen, leftPayload, leftTypeRef, leftType, condBits);

        NullCoalescingCodeGenPayload& newState = codeGen.ensureNodePayload<NullCoalescingCodeGenPayload>(codeGen.curNodeRef());
        newState.falseLabel                    = builder.createLabel();
        newState.doneLabel                     = builder.createLabel();

        CodeGenCompareHelpers::emitCompareRegZero(codeGen, condReg, leftType, condBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen, leftType, CodeGenCompareHelpers::falseyCondition(leftType), newState.falseLabel);

        // When the lhs is present, null-coalescing resolves immediately and the rhs is skipped entirely.
        emitNullCoalescingSelectedLeft(codeGen, newState, leftPayload, resultType, addressBacked);
        return Result::Continue;
    }

    if (state != nullptr)
    {
        const CodeGenNodePayload& rightPayload  = codeGen.payload(resolvedChildRef);
        const CodeGenNodePayload& resultPayload = codeGen.payload(codeGen.curNodeRef());
        if (addressBacked)
        {
            builder.emitLoadRegReg(resultPayload.reg, rightPayload.reg, MicroOpBits::B64);
        }
        else
        {
            const MicroOpBits resultBits = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            emitSelectedOperand(codeGen, resultPayload, rightPayload, resultBits);
        }

        builder.placeLabel(state->doneLabel);
        resetConditionalLabels(*state);
    }

    return Result::Continue;
}

Result AstOptionalChainExpr::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef)
{
    SWC_UNUSED(childRef);

    // Create the null exit before the chain body is generated: every '?.' link inside
    // jumps here when its left side is null.
    OptionalChainCodeGenPayload& state = codeGen.ensureNodePayload<OptionalChainCodeGenPayload>(codeGen.curNodeRef());
    state.falseLabel                   = codeGen.builder().createLabel();
    state.doneLabel                    = codeGen.builder().createLabel();
    return Result::Continue;
}

Result AstOptionalChainExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef)
{
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);
    SWC_ASSERT(resolvedChildRef.isValid());

    MicroBuilder&                builder = codeGen.builder();
    OptionalChainCodeGenPayload* state   = codeGen.safeNodePayload<OptionalChainCodeGenPayload>(codeGen.curNodeRef());
    SWC_ASSERT(state != nullptr && state->falseLabel.isValid());

    const MicroLabelRef falseLabel = state->falseLabel;
    const MicroLabelRef doneLabel  = state->doneLabel;

    const TypeRef   chainTypeRef = codeGen.transparentPayloadTypeRef();
    const TypeInfo& chainType    = codeGen.typeMgr().get(chainTypeRef);

    // Statement chain: the null exit simply lands after the skipped call.
    if (chainType.isVoid())
    {
        builder.placeLabel(falseLabel);
        builder.placeLabel(doneLabel);
        state->falseLabel = MicroLabelRef::invalid();
        state->doneLabel  = MicroLabelRef::invalid();
        return Result::Continue;
    }

    // A fused orelse adopts these labels and the unchanged value because the
    // chain's result type cannot represent the null outcome.
    if (!chainType.isNullable())
    {
        codeGen.inheritPayload(codeGen.curNodeRef(), resolvedChildRef, chainTypeRef);
        return Result::Continue;
    }

    // Standalone nullable result: join the produced value with a materialized null.
    const CodeGenNodePayload& childPayload = codeGen.payload(resolvedChildRef);
    if (usesAddressBackedSelection(codeGen, chainType))
    {
        const uint64_t chainSize = chainType.sizeOf(codeGen.ctx());
        SWC_ASSERT(chainSize % 8 == 0);

        const CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), chainTypeRef);
        builder.emitLoadRegReg(resultPayload.reg, childPayload.reg, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        builder.placeLabel(falseLabel);
        const MicroReg storageReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        for (uint64_t offset = 0; offset < chainSize; offset += 8)
            builder.emitLoadMemImm(storageReg, offset, ApInt(0, 64), MicroOpBits::B64);

        builder.emitLoadRegReg(resultPayload.reg, storageReg, MicroOpBits::B64);
        builder.placeLabel(doneLabel);
    }
    else
    {
        const MicroOpBits   resultBits    = CodeGenTypeHelpers::compareBits(chainType, codeGen.ctx());
        CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), chainTypeRef);
        resultPayload.reg                 = codeGen.nextVirtualRegisterForType(chainTypeRef, chainType);
        emitSelectedOperand(codeGen, resultPayload, childPayload, resultBits);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);

        builder.placeLabel(falseLabel);
        builder.emitClearReg(resultPayload.reg, resultBits);
        builder.placeLabel(doneLabel);
    }

    // The chain owns its own join; nothing is left for a parent to adopt.
    state->falseLabel = MicroLabelRef::invalid();
    state->doneLabel  = MicroLabelRef::invalid();
    return Result::Continue;
}

SWC_END_NAMESPACE();
