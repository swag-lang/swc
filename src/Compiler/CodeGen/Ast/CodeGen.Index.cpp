#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenTypeHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroReg copyAddressBaseReg(CodeGen& codeGen, const MicroReg baseReg)
    {
        MicroBuilder& builder = codeGen.builder();
        const auto    copyReg = codeGen.nextVirtualIntRegister();
        if (baseReg.isInt())
            builder.addVirtualRegForbiddenPhysReg(copyReg, baseReg);
        builder.emitLoadRegReg(copyReg, baseReg, MicroOpBits::B64);
        return copyReg;
    }

    MicroReg materializeIndexReg(CodeGen& codeGen, AstNodeRef indexRef, MicroOpBits& outIndexBits)
    {
        const CodeGenNodePayload& indexPayload = codeGen.payload(indexRef);
        const SemaNodeView        indexView    = codeGen.viewType(indexRef);
        SWC_ASSERT(indexView.type());

        outIndexBits           = CodeGenTypeHelpers::copyBits(*indexView.type());
        const bool indexSigned = indexView.type()->isIntSigned();

        if (outIndexBits == MicroOpBits::B64 && indexPayload.isValue())
            return indexPayload.reg;

        const MicroReg indexReg = codeGen.nextVirtualIntRegister();
        MicroBuilder&  builder  = codeGen.builder();
        if (indexPayload.isAddress())
        {
            if (outIndexBits == MicroOpBits::B64)
                builder.emitLoadRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64);
            else if (indexSigned)
                builder.emitLoadSignedExtendRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64, outIndexBits);
            else
                builder.emitLoadZeroExtendRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64, outIndexBits);
        }
        else
        {
            if (indexSigned)
                builder.emitLoadSignedExtendRegReg(indexReg, indexPayload.reg, MicroOpBits::B64, outIndexBits);
            else
                builder.emitLoadZeroExtendRegReg(indexReg, indexPayload.reg, MicroOpBits::B64, outIndexBits);
        }

        outIndexBits = MicroOpBits::B64;
        return indexReg;
    }

    MicroReg materializeAddressFromValue(CodeGen& codeGen, const CodeGenNodePayload& payload, const TypeInfo& typeInfo)
    {
        MicroBuilder&  builder     = codeGen.builder();
        const uint64_t sizeOfValue = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOfValue > 0);

        if (sizeOfValue != 1 && sizeOfValue != 2 && sizeOfValue != 4 && sizeOfValue != 8)
            return payload.reg;

        // Indexing a by-value array still needs a stable base address, so spill register-sized values to a
        // temporary storage slot first.
        const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        builder.emitLoadMemReg(spillAddrReg, 0, payload.reg, CodeGenTypeHelpers::bitsFromStorageSize(sizeOfValue));
        return spillAddrReg;
    }

    MicroReg resolveIndexBaseAddress(CodeGen& codeGen, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload)
    {
        MicroBuilder& builder = codeGen.builder();

        if (indexedType.isArray())
        {
            if (indexedPayload.isAddress())
                return indexedPayload.reg;
            return materializeAddressFromValue(codeGen, indexedPayload, indexedType);
        }

        if (indexedType.isAnyPointer() || indexedType.isCString())
        {
            if (indexedPayload.isValue())
                return indexedPayload.reg;

            const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(pointerReg, indexedPayload.reg, 0, MicroOpBits::B64);
            return pointerReg;
        }

        if (indexedType.isString() || indexedType.isSlice() || indexedType.isVariadic() || indexedType.isTypedVariadic())
        {
            const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(pointerReg, indexedPayload.reg, offsetof(Runtime::Slice<std::byte>, ptr), MicroOpBits::B64);
            return pointerReg;
        }

        SWC_UNREACHABLE();
    }

    uint64_t resolveIndexStrideSize(CodeGen& codeGen, const TypeInfo& indexedType)
    {
        TypeManager& typeMgr = codeGen.sema().typeMgr();
        if (indexedType.isArray())
        {
            const auto& dims       = indexedType.payloadArrayDims();
            const auto  elementRef = indexedType.payloadArrayElemTypeRef();
            if (dims.size() <= 1)
                return typeMgr.get(elementRef).sizeOf(codeGen.ctx());

            SmallVector<uint64_t> remainingDims;
            remainingDims.reserve(dims.size() - 1);
            for (size_t i = 1; i < dims.size(); ++i)
                remainingDims.push_back(dims[i]);

            const TypeRef strideTypeRef = typeMgr.addType(TypeInfo::makeArray(remainingDims.span(), elementRef, indexedType.flags()));
            return typeMgr.get(strideTypeRef).sizeOf(codeGen.ctx());
        }

        if (indexedType.isPointerOrReference() || indexedType.isSlice() || indexedType.isTypedVariadic() || indexedType.isCString())
            return typeMgr.get(indexedType.payloadTypeRef()).sizeOf(codeGen.ctx());
        if (indexedType.isString())
            return typeMgr.get(typeMgr.typeU8()).sizeOf(codeGen.ctx());
        if (indexedType.isVariadic())
            return typeMgr.get(typeMgr.typeAny()).sizeOf(codeGen.ctx());

        SWC_UNREACHABLE();
    }

    TypeRef resolveIndexedResultTypeRef(CodeGen& codeGen, const TypeInfo& indexedType)
    {
        TypeManager& typeMgr = codeGen.sema().typeMgr();
        if (indexedType.isArray())
        {
            const auto& dims = indexedType.payloadArrayDims();
            if (dims.size() <= 1)
                return indexedType.payloadArrayElemTypeRef();

            SmallVector<uint64_t> remainingDims;
            remainingDims.reserve(dims.size() - 1);
            for (size_t i = 1; i < dims.size(); ++i)
                remainingDims.push_back(dims[i]);

            return typeMgr.addType(TypeInfo::makeArray(remainingDims.span(), indexedType.payloadArrayElemTypeRef(), indexedType.flags()));
        }

        if (indexedType.isPointerOrReference() || indexedType.isSlice() || indexedType.isTypedVariadic() || indexedType.isCString())
            return indexedType.payloadTypeRef();
        if (indexedType.isString())
            return typeMgr.typeU8();
        if (indexedType.isVariadic())
            return typeMgr.typeAny();

        SWC_UNREACHABLE();
    }

    CodeGenNodePayload emitIndexAddress(CodeGen& codeGen, AstNodeRef indexRef, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload, TypeRef resultTypeRef)
    {
        auto           indexBits = MicroOpBits::B64;
        const MicroReg indexReg  = materializeIndexReg(codeGen, indexRef, indexBits);
        MicroReg       baseReg   = resolveIndexBaseAddress(codeGen, indexedType, indexedPayload);

        if (indexedType.isArray() && indexedPayload.isAddress())
        {
            const CodeGenNodePayload& indexPayload = codeGen.payload(indexRef);
            if (indexPayload.isAddress())
                baseReg = copyAddressBaseReg(codeGen, baseReg);
        }

        // Multidimensional indexing is just repeated address computation with the stride of the current
        // element type.
        const uint64_t resultSize = resolveIndexStrideSize(codeGen, indexedType);
        SWC_ASSERT(resultSize > 0);

        CodeGenNodePayload resultPayload;
        resultPayload.typeRef = resultTypeRef;
        resultPayload.setIsAddress();
        resultPayload.reg     = codeGen.nextVirtualIntRegister();
        MicroBuilder& builder = codeGen.builder();
        builder.emitLoadAddressAmcRegMem(resultPayload.reg, MicroOpBits::B64, baseReg, indexReg, resultSize, 0, indexBits);
        return resultPayload;
    }

    Result emitSliceValue(CodeGen& codeGen, const AstIndexExpr& node)
    {
        const auto&               range          = codeGen.node(node.nodeArgRef).cast<AstRangeExpr>();
        const CodeGenNodePayload& indexedPayload = codeGen.payload(node.nodeExprRef);
        const SemaNodeView        indexedView    = codeGen.viewType(node.nodeExprRef);
        const SemaNodeView        resultView     = codeGen.curViewType();
        SWC_ASSERT(indexedView.type());
        SWC_ASSERT(resultView.type());

        const TypeInfo& indexedType = *indexedView.type();
        const TypeInfo& resultType  = *resultView.type();
        MicroBuilder&   builder     = codeGen.builder();

        const MicroReg baseReg = resolveIndexBaseAddress(codeGen, indexedType, indexedPayload);

        const MicroReg lowReg = codeGen.nextVirtualIntRegister();
        if (range.nodeExprDownRef.isValid())
        {
            auto       lowBits   = MicroOpBits::B64;
            const auto rawLowReg = materializeIndexReg(codeGen, range.nodeExprDownRef, lowBits);
            builder.emitLoadRegReg(lowReg, rawLowReg, MicroOpBits::B64);
        }
        else
        {
            builder.emitLoadRegImm(lowReg, ApInt(0, 64), MicroOpBits::B64);
        }

        const MicroReg endExclusiveReg = codeGen.nextVirtualIntRegister();
        if (range.nodeExprUpRef.isValid())
        {
            auto       upBits   = MicroOpBits::B64;
            const auto rawUpReg = materializeIndexReg(codeGen, range.nodeExprUpRef, upBits);
            builder.emitLoadRegReg(endExclusiveReg, rawUpReg, MicroOpBits::B64);
            if (range.hasFlag(AstRangeExprFlagsE::Inclusive))
                builder.emitOpBinaryRegImm(endExclusiveReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        }
        else if (indexedType.isArray())
        {
            const uint64_t count = indexedType.payloadArrayDims().empty() ? 0 : indexedType.payloadArrayDims()[0];
            builder.emitLoadRegImm(endExclusiveReg, ApInt(count, 64), MicroOpBits::B64);
        }
        else if (indexedType.isString())
        {
            builder.emitLoadRegMem(endExclusiveReg, indexedPayload.reg, offsetof(Runtime::String, length), MicroOpBits::B64);
        }
        else if (indexedType.isSlice())
        {
            builder.emitLoadRegMem(endExclusiveReg, indexedPayload.reg, offsetof(Runtime::Slice<std::byte>, count), MicroOpBits::B64);
        }
        else
        {
            SWC_UNREACHABLE();
        }

        const uint64_t strideSize = resolveIndexStrideSize(codeGen, indexedType);
        const MicroReg dataReg    = codeGen.nextVirtualIntRegister();
        builder.emitLoadAddressAmcRegMem(dataReg, MicroOpBits::B64, baseReg, lowReg, strideSize, 0, MicroOpBits::B64);

        const MicroReg countReg = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(countReg, endExclusiveReg, MicroOpBits::B64);
        builder.emitOpBinaryRegReg(countReg, lowReg, MicroOp::Subtract, MicroOpBits::B64);

        const MicroReg runtimeValueReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        builder.emitLoadMemReg(runtimeValueReg, offsetof(Runtime::Slice<std::byte>, ptr), dataReg, MicroOpBits::B64);

        const uint32_t countOffset = resultType.isString() ? offsetof(Runtime::String, length) : offsetof(Runtime::Slice<std::byte>, count);
        builder.emitLoadMemReg(runtimeValueReg, countOffset, countReg, MicroOpBits::B64);

        CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), resultView.typeRef());
        payload.reg                 = codeGen.nextVirtualIntRegister();
        builder.emitLoadRegReg(payload.reg, runtimeValueReg, MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstIndexExpr::codeGenPostNode(CodeGen& codeGen) const
{
    if (codeGen.node(nodeArgRef).is(AstNodeId::RangeExpr))
        return emitSliceValue(codeGen, *this);

    const CodeGenNodePayload& indexedPayload = codeGen.payload(nodeExprRef);
    const SemaNodeView        indexedView    = codeGen.viewType(nodeExprRef);
    const SemaNodeView        resultView     = codeGen.curViewType();

    SWC_ASSERT(indexedView.type());
    SWC_ASSERT(resultView.type());

    const TypeRef            resultTypeRef        = resolveIndexedResultTypeRef(codeGen, *indexedView.type());
    const CodeGenNodePayload indexedResultPayload = emitIndexAddress(codeGen, nodeArgRef, *indexedView.type(), indexedPayload, resultTypeRef);
    codeGen.setPayloadAddressReg(codeGen.curNodeRef(), indexedResultPayload.reg, resultTypeRef);
    return Result::Continue;
}

Result AstIndexListExpr::codeGenPostNode(CodeGen& codeGen) const
{
    SmallVector<AstNodeRef> indexRefs;
    codeGen.ast().appendNodes(indexRefs, spanChildrenRef);
    SWC_ASSERT(!indexRefs.empty());

    TypeRef currentTypeRef = codeGen.viewType(nodeExprRef).typeRef();
    SWC_ASSERT(currentTypeRef.isValid());

    CodeGenNodePayload currentPayload = codeGen.payload(nodeExprRef);
    for (const AstNodeRef indexRef : indexRefs)
    {
        const TypeInfo& currentType = codeGen.typeMgr().get(currentTypeRef);
        const TypeRef   nextTypeRef = resolveIndexedResultTypeRef(codeGen, currentType);
        currentPayload              = emitIndexAddress(codeGen, indexRef, currentType, currentPayload, nextTypeRef);
        currentTypeRef              = nextTypeRef;
    }

    codeGen.setPayloadAddressReg(codeGen.curNodeRef(), currentPayload.reg, currentTypeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
