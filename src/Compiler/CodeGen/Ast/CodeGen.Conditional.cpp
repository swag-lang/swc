#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct NullCoalescingCodeGenPayload : CodeGenNodePayload
    {
        MicroLabelRef falseLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel  = MicroLabelRef::invalid();
    };

    MicroOpBits compareOpBits(const TypeInfo& typeInfo)
    {
        if (typeInfo.isFloat())
        {
            const uint32_t floatBits = typeInfo.payloadFloatBits() ? typeInfo.payloadFloatBits() : 64;
            return microOpBitsFromBitWidth(floatBits);
        }

        if (typeInfo.isIntLike())
        {
            const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
            return microOpBitsFromBitWidth(intBits);
        }

        if (typeInfo.isBool())
            return MicroOpBits::B8;

        return MicroOpBits::B64;
    }

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

        const MicroOpBits opBits = compareOpBits(typeInfo);
        SWC_ASSERT(opBits != MicroOpBits::Zero);
        MicroReg outReg;
        materializeScalarOperand(outReg, codeGen, operandPayload, operandTypeRef, opBits);
        return outReg;
    }

    AstNodeRef resolvedNodeRef(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.viewZero(nodeRef).nodeRef();
    }

    NullCoalescingCodeGenPayload* nullCoalescingCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;
        return codeGen.sema().codeGenPayload<NullCoalescingCodeGenPayload>(nodeRef);
    }

    NullCoalescingCodeGenPayload& ensureNullCoalescingCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        SWC_ASSERT(nodeRef.isValid());

        auto* payload = codeGen.sema().codeGenPayload<NullCoalescingCodeGenPayload>(nodeRef);
        if (!payload)
        {
            payload = codeGen.compiler().allocate<NullCoalescingCodeGenPayload>();
            codeGen.sema().setCodeGenPayload(nodeRef, payload);
        }

        return *payload;
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

Result AstConditionalExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const SemaNodeView condView   = codeGen.viewType(nodeCondRef);
    const SemaNodeView trueView   = codeGen.viewType(nodeTrueRef);
    const SemaNodeView falseView  = codeGen.viewType(nodeFalseRef);
    const SemaNodeView resultView = codeGen.curViewType();
    SWC_ASSERT(condView.type() && trueView.type() && falseView.type() && resultView.type());

    const CodeGenNodePayload& condPayload  = codeGen.payload(nodeCondRef);
    const CodeGenNodePayload& truePayload  = codeGen.payload(nodeTrueRef);
    const CodeGenNodePayload& falsePayload = codeGen.payload(nodeFalseRef);

    const TypeRef condTypeRef   = condPayload.typeRef.isValid() ? condPayload.typeRef : condView.typeRef();
    const TypeRef resultTypeRef = resultView.typeRef();
    const TypeRef trueTypeRef   = truePayload.typeRef.isValid() ? truePayload.typeRef : trueView.typeRef();
    const TypeRef falseTypeRef  = falsePayload.typeRef.isValid() ? falsePayload.typeRef : falseView.typeRef();

    const MicroOpBits condBits   = compareOpBits(codeGen.typeMgr().get(condTypeRef));
    const MicroOpBits resultBits = compareOpBits(codeGen.typeMgr().get(resultTypeRef));
    SWC_ASSERT(condBits != MicroOpBits::Zero && resultBits != MicroOpBits::Zero);

    MicroReg condReg, trueReg, falseReg;
    materializeScalarOperand(condReg, codeGen, condPayload, condTypeRef, condBits);
    materializeScalarOperand(trueReg, codeGen, truePayload, trueTypeRef, resultBits);
    materializeScalarOperand(falseReg, codeGen, falsePayload, falseTypeRef, resultBits);

    CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
    resultPayload.reg                 = codeGen.nextVirtualRegisterForType(resultTypeRef);

    MicroBuilder&       builder    = codeGen.builder();
    const MicroLabelRef falseLabel = builder.createLabel();
    const MicroLabelRef doneLabel  = builder.createLabel();

    builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, falseLabel);
    builder.emitLoadRegReg(resultPayload.reg, trueReg, resultBits);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(falseLabel);
    builder.emitLoadRegReg(resultPayload.reg, falseReg, resultBits);
    builder.placeLabel(doneLabel);

    return Result::Continue;
}

Result AstNullCoalescingExpr::codeGenPostNode(CodeGen& codeGen) const
{
    return Result::Continue;
}

Result AstNullCoalescingExpr::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedLeftRef  = resolvedNodeRef(codeGen, nodeLeftRef);
    const AstNodeRef resolvedRightRef = resolvedNodeRef(codeGen, nodeRightRef);
    const AstNodeRef resolvedChildRef = resolvedNodeRef(codeGen, childRef);

    const SemaNodeView resultView    = codeGen.curViewType();
    const TypeRef      resultTypeRef = resultView.typeRef();
    const bool         addressBacked = usesAddressBackedSelection(codeGen, resultTypeRef);
    MicroBuilder&      builder       = codeGen.builder();

    if (resolvedLeftRef.isValid() && resolvedChildRef == resolvedLeftRef)
    {
        const SemaNodeView        leftView    = codeGen.viewType(nodeLeftRef);
        const CodeGenNodePayload& leftPayload = codeGen.payload(nodeLeftRef);
        const TypeRef             leftTypeRef = leftPayload.typeRef.isValid() ? leftPayload.typeRef : leftView.typeRef();
        const MicroOpBits         condBits    = compareOpBits(codeGen.typeMgr().get(leftTypeRef));
        SWC_ASSERT(condBits != MicroOpBits::Zero);

        const MicroReg condReg = materializeTruthyOperand(codeGen, leftPayload, leftTypeRef);

        NullCoalescingCodeGenPayload& state = ensureNullCoalescingCodeGenPayload(codeGen, codeGen.curNodeRef());
        state.falseLabel                    = builder.createLabel();
        state.doneLabel                     = builder.createLabel();

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.falseLabel);

        if (addressBacked)
        {
            CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
            builder.emitLoadRegReg(resultPayload.reg, leftPayload.reg, MicroOpBits::B64);
        }
        else
        {
            const TypeInfo&     resultType    = codeGen.typeMgr().get(resultTypeRef);
            const MicroOpBits   resultBits    = compareOpBits(resultType);
            CodeGenNodePayload& resultPayload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultTypeRef);
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
            const MicroOpBits resultBits = compareOpBits(resultType);
            emitSelectedOperand(codeGen, resultPayload, rightPayload, resultBits);
        }

        builder.placeLabel(state->doneLabel);
        eraseNullCoalescingCodeGenPayload(codeGen, codeGen.curNodeRef());
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
