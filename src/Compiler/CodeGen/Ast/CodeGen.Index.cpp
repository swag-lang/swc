#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
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
        const CodeGenNodePayload* indexPayload = SWC_CHECK_NOT_NULL(codeGen.payload(indexRef));
        const SemaNodeView        indexView    = codeGen.sema().viewType(indexRef);
        SWC_ASSERT(indexView.type());

        outIndexBits           = indexOpBits(*indexView.type());
        const bool indexSigned = indexView.type()->isIntSigned();

        if (outIndexBits == MicroOpBits::B64 && indexPayload->storageKind == CodeGenNodePayload::StorageKind::Value)
            return indexPayload->reg;

        const MicroReg indexReg = codeGen.nextVirtualIntRegister();
        if (indexPayload->storageKind == CodeGenNodePayload::StorageKind::Address)
        {
            if (outIndexBits == MicroOpBits::B64)
            {
                codeGen.builder().emitLoadRegMem(indexReg, indexPayload->reg, 0, MicroOpBits::B64);
            }
            else if (indexSigned)
            {
                codeGen.builder().emitLoadSignedExtendRegMem(indexReg, indexPayload->reg, 0, MicroOpBits::B64, outIndexBits);
            }
            else
            {
                codeGen.builder().emitClearReg(indexReg, MicroOpBits::B64);
                codeGen.builder().emitLoadRegMem(indexReg, indexPayload->reg, 0, outIndexBits);
            }
        }
        else
        {
            if (indexSigned)
            {
                codeGen.builder().emitLoadSignedExtendRegReg(indexReg, indexPayload->reg, MicroOpBits::B64, outIndexBits);
            }
            else
            {
                codeGen.builder().emitClearReg(indexReg, MicroOpBits::B64);
                codeGen.builder().emitLoadRegReg(indexReg, indexPayload->reg, outIndexBits);
            }
        }

        outIndexBits = MicroOpBits::B64;
        return indexReg;
    }

    MicroReg materializeAddressFromValue(CodeGen& codeGen, const CodeGenNodePayload& payload, const TypeInfo& typeInfo)
    {
        const uint64_t sizeOfValue = typeInfo.sizeOf(codeGen.ctx());
        SWC_ASSERT(sizeOfValue > 0 && sizeOfValue <= 8);

        std::byte* spillData = codeGen.compiler().allocateArray<std::byte>(static_cast<size_t>(sizeOfValue));
        std::memset(spillData, 0, static_cast<size_t>(sizeOfValue));

        const MicroReg spillAddrReg = codeGen.nextVirtualIntRegister();
        codeGen.builder().emitLoadRegPtrImm(spillAddrReg, reinterpret_cast<uint64_t>(spillData));
        codeGen.builder().emitLoadMemReg(spillAddrReg, 0, payload.reg, microOpBitsFromChunkSize(static_cast<uint32_t>(sizeOfValue)));
        return spillAddrReg;
    }

    MicroReg resolveIndexBaseAddress(CodeGen& codeGen, const TypeInfo& indexedType, const CodeGenNodePayload& indexedPayload)
    {
        MicroBuilder& builder = codeGen.builder();

        if (indexedType.isArray())
        {
            if (indexedPayload.storageKind == CodeGenNodePayload::StorageKind::Address)
                return indexedPayload.reg;
            return materializeAddressFromValue(codeGen, indexedPayload, indexedType);
        }

        if (indexedType.isValuePointer() || indexedType.isBlockPointer() || indexedType.isCString())
        {
            if (indexedPayload.storageKind == CodeGenNodePayload::StorageKind::Value)
                return indexedPayload.reg;

            const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(pointerReg, indexedPayload.reg, 0, MicroOpBits::B64);
            return pointerReg;
        }

        if (indexedType.isString())
        {
            MicroReg stringReg = indexedPayload.reg;
            if (indexedPayload.storageKind == CodeGenNodePayload::StorageKind::Address)
            {
                stringReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(stringReg, indexedPayload.reg, 0, MicroOpBits::B64);
            }

            const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(pointerReg, stringReg, offsetof(Runtime::String, ptr), MicroOpBits::B64);
            return pointerReg;
        }

        if (indexedType.isSlice())
        {
            MicroReg sliceReg = indexedPayload.reg;
            if (indexedPayload.storageKind == CodeGenNodePayload::StorageKind::Address)
            {
                sliceReg = codeGen.nextVirtualIntRegister();
                builder.emitLoadRegMem(sliceReg, indexedPayload.reg, 0, MicroOpBits::B64);
            }

            const MicroReg pointerReg = codeGen.nextVirtualIntRegister();
            builder.emitLoadRegMem(pointerReg, sliceReg, offsetof(Runtime::Slice<std::byte>, ptr), MicroOpBits::B64);
            return pointerReg;
        }

        SWC_UNREACHABLE();
    }
}

Result AstIndexExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const CodeGenNodePayload* indexedPayload = SWC_CHECK_NOT_NULL(codeGen.payload(nodeExprRef));
    const TypeRef             resultTypeRef  = codeGen.sema().viewType(codeGen.curNodeRef()).typeRef();
    const SemaNodeView        indexedView    = codeGen.sema().viewType(nodeExprRef);
    const SemaNodeView        resultView     = codeGen.sema().viewType(codeGen.curNodeRef());
    SWC_ASSERT(indexedView.type());
    SWC_ASSERT(resultView.type());

    auto           indexBits = MicroOpBits::B64;
    const MicroReg indexReg  = materializeIndexReg(codeGen, nodeArgRef, indexBits);
    const MicroReg baseReg   = resolveIndexBaseAddress(codeGen, *indexedView.type(), *indexedPayload);

    const uint64_t resultSize = resultView.type()->sizeOf(codeGen.ctx());
    SWC_ASSERT(resultSize > 0);

    const CodeGenNodePayload& resultPayload = codeGen.setPayloadAddress(codeGen.curNodeRef(), resultTypeRef);
    codeGen.builder().emitLoadAddressAmcRegMem(resultPayload.reg, MicroOpBits::B64, baseReg, indexReg, resultSize, 0, indexBits);
    return Result::Continue;
}

SWC_END_NAMESPACE();
