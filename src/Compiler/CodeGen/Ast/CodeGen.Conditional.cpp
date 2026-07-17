#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class ConditionalExprStage : uint8_t
    {
        TrueBranch,
        FalseBranch,
    };

    struct ConditionalExprCodeGenPayload : CodeGenNodePayload
    {
        MicroLabelRef       falseLabel = MicroLabelRef::invalid();
        MicroLabelRef       doneLabel  = MicroLabelRef::invalid();
        ConditionalExprStage stage     = ConditionalExprStage::TrueBranch;
    };

    struct NullCoalescingCodeGenPayload : CodeGenNodePayload
    {
        MicroLabelRef falseLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel  = MicroLabelRef::invalid();
    };

    void materializeScalarOperand(MicroReg& outReg, CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef, MicroOpBits opBits)
    {
        outReg = codeGen.nextVirtualRegisterForType(operandTypeRef);

        MicroBuilder& builder = codeGen.builder();
        if (operandPayload.isAddress())
            builder.emitLoadRegMem(outReg, operandPayload.reg, 0, opBits);
        else
            builder.emitLoadRegReg(outReg, operandPayload.reg, opBits);
    }

    MicroReg materializeTruthyOperand(CodeGen& codeGen, const CodeGenNodePayload& operandPayload, TypeRef operandTypeRef)
    {
        if (operandTypeRef.isValid() && operandPayload.typeRef.isValid() && codeGen.typeMgr().get(operandTypeRef).isBool())
            operandTypeRef = operandPayload.typeRef;

        const TypeInfo& typeInfo = codeGen.typeMgr().get(operandTypeRef);
        const uint64_t  sizeOf   = typeInfo.sizeOf(codeGen.ctx());
        if (sizeOf > 8)
        {
            const MicroReg resultReg = codeGen.nextVirtualIntRegister();
            codeGen.builder().emitLoadRegMem(resultReg, operandPayload.reg, 0, MicroOpBits::B64);
            return resultReg;
        }

        const MicroOpBits opBits = CodeGenTypeHelpers::compareBits(typeInfo, codeGen.ctx());
        SWC_ASSERT(opBits != MicroOpBits::Zero);
        MicroReg outReg;
        materializeScalarOperand(outReg, codeGen, operandPayload, operandTypeRef, opBits);
        return outReg;
    }

    ConditionalExprCodeGenPayload* conditionalExprCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<ConditionalExprCodeGenPayload>(nodeRef);
    }

    ConditionalExprCodeGenPayload& ensureConditionalExprCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.ensureNodePayload<ConditionalExprCodeGenPayload>(nodeRef);
    }

    void eraseConditionalExprCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        ConditionalExprCodeGenPayload* payload = conditionalExprCodeGenPayload(codeGen, nodeRef);
        if (payload)
        {
            payload->falseLabel = MicroLabelRef::invalid();
            payload->doneLabel  = MicroLabelRef::invalid();
        }
    }

    NullCoalescingCodeGenPayload* nullCoalescingCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<NullCoalescingCodeGenPayload>(nodeRef);
    }

    NullCoalescingCodeGenPayload& ensureNullCoalescingCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.ensureNodePayload<NullCoalescingCodeGenPayload>(nodeRef);
    }

    void eraseNullCoalescingCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        NullCoalescingCodeGenPayload* payload = nullCoalescingCodeGenPayload(codeGen, nodeRef);
        if (payload)
        {
            payload->falseLabel = MicroLabelRef::invalid();
            payload->doneLabel  = MicroLabelRef::invalid();
        }
    }

    bool usesAddressBackedSelection(CodeGen& codeGen, TypeRef typeRef)
    {
        return codeGen.typeMgr().get(typeRef).sizeOf(codeGen.ctx()) > 8;
    }

    void emitSelectedOperand(CodeGen& codeGen, const CodeGenNodePayload& resultPayload, const CodeGenNodePayload& operandPayload, MicroOpBits resultBits)
    {
        if (operandPayload.isAddress())
            codeGen.builder().emitLoadRegMem(resultPayload.reg, operandPayload.reg, 0, resultBits);
        else
            codeGen.builder().emitLoadRegReg(resultPayload.reg, operandPayload.reg, resultBits);
    }
}

Result AstConditionalExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);
    SWC_ASSERT(resolvedChildRef.isValid());

    const SemaNodeView resultView = codeGen.curViewType();
    SWC_ASSERT(resultView.type() != nullptr);

    // When the conditional was wrapped by an implicit cast, the wrapper's type shows
    // through the resolved view. The selection must produce its own stored type; the
    // wrapping cast then converts the joined value.
    const TypeRef resultTypeRef = codeGen.transparentPayloadTypeRef();
    const bool    addressBacked = usesAddressBackedSelection(codeGen, resultTypeRef);
    MicroBuilder& builder       = codeGen.builder();
    ConditionalExprCodeGenPayload* state = conditionalExprCodeGenPayload(codeGen, codeGen.curNodeRef());

    // Qualification casts can rewrite a direct child to a different resolved reference.
    // Child callbacks still arrive in source order, so track the lowering stage explicitly.
    if (state == nullptr)
    {
        // Conditional expressions must short-circuit to preserve branch semantics.
        const SemaNodeView        condView    = codeGen.viewType(resolvedChildRef);
        const CodeGenNodePayload& condPayload = codeGen.payload(resolvedChildRef);
        const TypeRef             condTypeRef = condPayload.typeRef.isValid() ? condPayload.typeRef : condView.typeRef();
        const TypeInfo&           condType    = codeGen.typeMgr().get(condTypeRef);
        const MicroOpBits         condBits    = CodeGenTypeHelpers::compareBits(condType, codeGen.ctx());
        SWC_ASSERT(condBits != MicroOpBits::Zero);

        const MicroReg condReg = materializeTruthyOperand(codeGen, condPayload, condTypeRef);

        ConditionalExprCodeGenPayload& newState = ensureConditionalExprCodeGenPayload(codeGen, codeGen.curNodeRef());
        newState.falseLabel                     = builder.createLabel();
        newState.doneLabel                      = builder.createLabel();

        CodeGenCompareHelpers::emitCompareRegZero(codeGen, condReg, condType, condBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen, condType, CodeGenCompareHelpers::falseyCondition(condType), newState.falseLabel);
        return Result::Continue;
    }

    if (state->stage == ConditionalExprStage::TrueBranch)
    {
        const CodeGenNodePayload& truePayload = codeGen.payload(resolvedChildRef);
        // The first selected branch allocates the destination payload; the other branch writes into that
        // same storage after the join label.
        if (addressBacked)
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, truePayload.reg, MicroOpBits::B64);
        }
        else
        {
            const TypeInfo&     resultType    = codeGen.typeMgr().get(resultTypeRef);
            const MicroOpBits   resultBits    = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            // The join register must match the result type's register class: a float
            // selection materialized in an integer register would turn the branch
            // moves into bit reinterprets and break every float consumer downstream.
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultTypeRef);
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
            const TypeInfo&   resultType = codeGen.typeMgr().get(resultTypeRef);
            const MicroOpBits resultBits = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            emitSelectedOperand(codeGen, resultPayload, falsePayload, resultBits);
        }

        builder.placeLabel(state->doneLabel);
        eraseConditionalExprCodeGenPayload(codeGen, codeGen.curNodeRef());
    }

    return Result::Continue;
}

Result AstConditionalExpr::codeGenPostNode(CodeGen& codeGen)
{
    eraseConditionalExprCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstNullCoalescingExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);
    SWC_ASSERT(resolvedChildRef.isValid());

    // Same stored-type rule as the conditional expression above.
    const TypeRef resultTypeRef = codeGen.transparentPayloadTypeRef();
    const bool    addressBacked = usesAddressBackedSelection(codeGen, resultTypeRef);
    MicroBuilder& builder       = codeGen.builder();
    NullCoalescingCodeGenPayload* state = nullCoalescingCodeGenPayload(codeGen, codeGen.curNodeRef());

    // Qualification casts can also rewrite either coalescing operand. The first direct
    // callback is the lhs; the presence of lowering state identifies the rhs callback.
    if (state == nullptr)
    {
        const SemaNodeView        leftView    = codeGen.viewType(resolvedChildRef);
        const CodeGenNodePayload& leftPayload = codeGen.payload(resolvedChildRef);
        const TypeRef             leftTypeRef = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const TypeInfo&           leftType    = codeGen.typeMgr().get(leftTypeRef);
        const MicroOpBits         condBits    = CodeGenTypeHelpers::compareBits(leftType, codeGen.ctx());
        SWC_ASSERT(condBits != MicroOpBits::Zero);

        const MicroReg condReg = materializeTruthyOperand(codeGen, leftPayload, leftTypeRef);

        NullCoalescingCodeGenPayload& state = ensureNullCoalescingCodeGenPayload(codeGen, codeGen.curNodeRef());
        state.falseLabel                    = builder.createLabel();
        state.doneLabel                     = builder.createLabel();

        CodeGenCompareHelpers::emitCompareRegZero(codeGen, condReg, leftType, condBits);
        CodeGenCompareHelpers::emitConditionJump(codeGen, leftType, CodeGenCompareHelpers::falseyCondition(leftType), state.falseLabel);

        // When the lhs is present, null-coalescing resolves immediately and the rhs is skipped entirely.
        if (addressBacked)
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, leftPayload.reg, MicroOpBits::B64);
        }
        else
        {
            const TypeInfo&     resultType    = codeGen.typeMgr().get(resultTypeRef);
            const MicroOpBits   resultBits    = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            // Same register-class constraint as the conditional expression above.
            resultPayload.reg = codeGen.nextVirtualRegisterForType(resultTypeRef);
            emitSelectedOperand(codeGen, resultPayload, leftPayload, resultBits);
        }

        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state.doneLabel);
        builder.placeLabel(state.falseLabel);
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
            const TypeInfo&   resultType = codeGen.typeMgr().get(resultTypeRef);
            const MicroOpBits resultBits = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            emitSelectedOperand(codeGen, resultPayload, rightPayload, resultBits);
        }

        builder.placeLabel(state->doneLabel);
        eraseNullCoalescingCodeGenPayload(codeGen, codeGen.curNodeRef());
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
