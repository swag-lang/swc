#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ConditionalExprCodeGenPayload : CodeGenNodePayload
    {
        MicroLabelRef falseLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel  = MicroLabelRef::invalid();
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
    const AstNodeRef resolvedCondRef  = codeGen.resolvedNodeRef(nodeCondRef);
    const AstNodeRef resolvedTrueRef  = codeGen.resolvedNodeRef(nodeTrueRef);
    const AstNodeRef resolvedFalseRef = codeGen.resolvedNodeRef(nodeFalseRef);
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);

    const SemaNodeView resultView = codeGen.curViewType();
    SWC_ASSERT(resultView.type() != nullptr);

    const TypeRef resultTypeRef = resultView.typeRef();
    const bool    addressBacked = usesAddressBackedSelection(codeGen, resultTypeRef);
    MicroBuilder& builder       = codeGen.builder();

    if (resolvedCondRef.isValid() && resolvedChildRef == resolvedCondRef)
    {
        // Conditional expressions must short-circuit to preserve branch semantics.
        const SemaNodeView        condView    = codeGen.viewType(nodeCondRef);
        const CodeGenNodePayload& condPayload = codeGen.payload(nodeCondRef);
        const TypeRef             condTypeRef = condPayload.typeRef.isValid() ? condPayload.typeRef : condView.typeRef();
        const MicroOpBits         condBits    = CodeGenTypeHelpers::compareBits(codeGen.typeMgr().get(condTypeRef), codeGen.ctx());
        SWC_ASSERT(condBits != MicroOpBits::Zero);

        const MicroReg condReg = materializeTruthyOperand(codeGen, condPayload, condTypeRef);

        ConditionalExprCodeGenPayload& state = ensureConditionalExprCodeGenPayload(codeGen, codeGen.curNodeRef());
        state.falseLabel                     = builder.createLabel();
        state.doneLabel                      = builder.createLabel();

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.falseLabel);
        return Result::Continue;
    }

    if (resolvedTrueRef.isValid() && resolvedChildRef == resolvedTrueRef)
    {
        const ConditionalExprCodeGenPayload* state = conditionalExprCodeGenPayload(codeGen, codeGen.curNodeRef());
        SWC_ASSERT(state != nullptr);

        const CodeGenNodePayload& truePayload = codeGen.payload(nodeTrueRef);
        // The first selected branch allocates the destination payload; the other branch writes into that
        // same storage after the join label.
        if (addressBacked)
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, truePayload.reg, MicroOpBits::B64);
        }
        else
        {
            const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
            const MicroOpBits         resultBits    = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            emitSelectedOperand(codeGen, resultPayload, truePayload, resultBits);
        }

        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state->doneLabel);
        builder.placeLabel(state->falseLabel);
        return Result::Continue;
    }

    if (resolvedFalseRef.isValid() && resolvedChildRef == resolvedFalseRef)
    {
        const ConditionalExprCodeGenPayload* state = conditionalExprCodeGenPayload(codeGen, codeGen.curNodeRef());
        SWC_ASSERT(state != nullptr);

        const CodeGenNodePayload& falsePayload  = codeGen.payload(nodeFalseRef);
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
    const AstNodeRef resolvedLeftRef  = codeGen.resolvedNodeRef(nodeLeftRef);
    const AstNodeRef resolvedRightRef = codeGen.resolvedNodeRef(nodeRightRef);
    const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);

    const SemaNodeView resultView    = codeGen.curViewType();
    const TypeRef      resultTypeRef = resultView.typeRef();
    const bool         addressBacked = usesAddressBackedSelection(codeGen, resultTypeRef);
    MicroBuilder&      builder       = codeGen.builder();

    if (resolvedLeftRef.isValid() && resolvedChildRef == resolvedLeftRef)
    {
        const SemaNodeView        leftView    = codeGen.viewType(nodeLeftRef);
        const CodeGenNodePayload& leftPayload = codeGen.payload(nodeLeftRef);
        const TypeRef             leftTypeRef = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const MicroOpBits         condBits    = CodeGenTypeHelpers::compareBits(codeGen.typeMgr().get(leftTypeRef), codeGen.ctx());
        SWC_ASSERT(condBits != MicroOpBits::Zero);

        const MicroReg condReg = materializeTruthyOperand(codeGen, leftPayload, leftTypeRef);

        NullCoalescingCodeGenPayload& state = ensureNullCoalescingCodeGenPayload(codeGen, codeGen.curNodeRef());
        state.falseLabel                    = builder.createLabel();
        state.doneLabel                     = builder.createLabel();

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.falseLabel);

        // When the lhs is present, null-coalescing resolves immediately and the rhs is skipped entirely.
        if (addressBacked)
        {
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, leftPayload.reg, MicroOpBits::B64);
        }
        else
        {
            const TypeInfo&           resultType    = codeGen.typeMgr().get(resultTypeRef);
            const MicroOpBits         resultBits    = CodeGenTypeHelpers::compareBits(resultType, codeGen.ctx());
            const CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
            emitSelectedOperand(codeGen, resultPayload, leftPayload, resultBits);
        }

        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state.doneLabel);
        builder.placeLabel(state.falseLabel);
        return Result::Continue;
    }

    if (resolvedRightRef.isValid() && resolvedChildRef == resolvedRightRef)
    {
        const NullCoalescingCodeGenPayload* state = nullCoalescingCodeGenPayload(codeGen, codeGen.curNodeRef());
        SWC_ASSERT(state != nullptr);

        const CodeGenNodePayload& rightPayload  = codeGen.payload(nodeRightRef);
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
