#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroOpBits indexOpBits(const TypeInfo& typeInfo)
    {
        if (!typeInfo.isIntLike())
            return MicroOpBits::B64;

        const uint32_t intBits = typeInfo.payloadIntLikeBits() ? typeInfo.payloadIntLikeBits() : 64;
        return microOpBitsFromBitWidth(intBits);
    }

    MicroReg materializeIndexReg(CodeGen& codeGen, AstNodeRef indexRef, MicroOpBits& outIndexBits)
    {
        const CodeGenNodePayload& indexPayload = codeGen.payload(indexRef);
        const SemaNodeView        indexView    = codeGen.viewType(indexRef);
        SWC_ASSERT(indexView.type());

        outIndexBits           = indexOpBits(*indexView.type());
        const bool indexSigned = indexView.type()->isIntSigned();

        if (outIndexBits == MicroOpBits::B64 && indexPayload.isValue())
            return indexPayload.reg;

        const MicroReg indexReg     = codeGen.nextVirtualIntRegister();
        MicroBuilder&  microBuilder = codeGen.builder();
        if (indexPayload.isAddress())
        {
            if (outIndexBits == MicroOpBits::B64)
                microBuilder.emitLoadRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64);
            else if (indexSigned)
                microBuilder.emitLoadSignedExtendRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64, outIndexBits);
            else
                microBuilder.emitLoadZeroExtendRegMem(indexReg, indexPayload.reg, 0, MicroOpBits::B64, outIndexBits);
        }
        else
        {
            if (indexSigned)
                microBuilder.emitLoadSignedExtendRegReg(indexReg, indexPayload.reg, MicroOpBits::B64, outIndexBits);
            else
                microBuilder.emitLoadZeroExtendRegReg(indexReg, indexPayload.reg, MicroOpBits::B64, outIndexBits);
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

        const MicroReg spillAddrReg = codeGen.runtimeStorageAddressReg(codeGen.curNodeRef());
        builder.emitLoadMemReg(spillAddrReg, 0, payload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfValue)));
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

        if (indexedType.isValuePointer() || indexedType.isBlockPointer() || indexedType.isCString())
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

        if (indexedType.isBlockPointer() || indexedType.isSlice() || indexedType.isTypedVariadic() || indexedType.isValuePointer() || indexedType.isReference() || indexedType.isCString())
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

        if (indexedType.isBlockPointer() || indexedType.isValuePointer() || indexedType.isReference() || indexedType.isSlice() || indexedType.isTypedVariadic() || indexedType.isCString())
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
        const MicroReg baseReg   = resolveIndexBaseAddress(codeGen, indexedType, indexedPayload);

        const uint64_t resultSize = resolveIndexStrideSize(codeGen, indexedType);
        SWC_ASSERT(resultSize > 0);

        CodeGenNodePayload resultPayload;
        resultPayload.typeRef = resultTypeRef;
        resultPayload.setIsAddress();
        resultPayload.reg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadAddressAmcRegMem(resultPayload.reg, MicroOpBits::B64, baseReg, indexReg, resultSize, 0, indexBits);
        return resultPayload;
    }
}

Result AstIndexExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const CodeGenNodePayload& indexedPayload = codeGen.payload(nodeExprRef);
    const SemaNodeView        indexedView    = codeGen.viewType(nodeExprRef);
    const SemaNodeView        resultView     = codeGen.curViewType();

    SWC_ASSERT(indexedView.type());
    SWC_ASSERT(resultView.type());

    const TypeRef            resultTypeRef        = resolveIndexedResultTypeRef(codeGen, *indexedView.type());
    const CodeGenNodePayload indexedResultPayload = emitIndexAddress(codeGen, nodeArgRef, *indexedView.type(), indexedPayload, resultTypeRef);
    CodeGenNodePayload&      resultPayload        = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
    resultPayload.reg                             = indexedResultPayload.reg;
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

    CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), currentTypeRef);
    resultPayload.reg                 = currentPayload.reg;
    return Result::Continue;
}

SWC_END_NAMESPACE();
