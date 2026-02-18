#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t addPayloadToConstantManagerAndGetAddress(CodeGen& codeGen, ByteSpan payload)
    {
        const std::string_view payloadView(reinterpret_cast<const char*>(payload.data()), payload.size());
        const std::string_view storedPayload = codeGen.cstMgr().addPayloadBuffer(payloadView);
        return reinterpret_cast<uint64_t>(storedPayload.data());
    }

    void emitLoweredConstantToPayload(CodeGen& codeGen, CodeGenNodePayload& payload, ConstantRef cstRef, const ConstantValue& cst, TypeRef targetTypeRef)
    {
        const TypeRef   finalTypeRef = targetTypeRef.isValid() ? targetTypeRef : cst.typeRef();
        const TypeInfo& typeInfo     = codeGen.typeMgr().get(finalTypeRef);
        const uint64_t  storageSize  = typeInfo.sizeOf(codeGen.ctx());
        if (!storageSize)
        {
            codeGen.builder().encodeLoadRegImm(payload.reg, 0, MicroOpBits::B64);
            payload.storageKind = CodeGenNodePayload::StorageKind::Value;
            return;
        }

        if (typeInfo.isStruct() && cst.isStruct())
        {
            const ByteSpan structBytes = cst.getStruct();
            SWC_ASSERT(structBytes.size() == storageSize);
            codeGen.builder().encodeLoadRegPtrImm(payload.reg, reinterpret_cast<uint64_t>(structBytes.data()), cstRef);
            payload.storageKind = CodeGenNodePayload::StorageKind::Address;
            return;
        }

        if (typeInfo.isArray() && cst.isArray())
        {
            const ByteSpan arrayBytes = cst.getArray();
            SWC_ASSERT(arrayBytes.size() == storageSize);
            codeGen.builder().encodeLoadRegPtrImm(payload.reg, reinterpret_cast<uint64_t>(arrayBytes.data()), cstRef);
            payload.storageKind = CodeGenNodePayload::StorageKind::Address;
            return;
        }

        SmallVector<std::byte> tmpStorage(storageSize);
        ByteSpanRW             tmpSpan{tmpStorage.data(), tmpStorage.size()};
        std::memset(tmpSpan.data(), 0, tmpSpan.size());
        ConstantLower::lowerToBytes(codeGen.sema(), tmpSpan, cstRef, finalTypeRef);

        if (storageSize <= sizeof(uint64_t) && !typeInfo.isString() && !typeInfo.isSlice() && !typeInfo.isStruct() && !typeInfo.isArray())
        {
            uint64_t value = 0;
            std::memcpy(&value, tmpSpan.data(), storageSize);
            codeGen.builder().encodeLoadRegImm(payload.reg, value, MicroOpBits::B64);
            payload.storageKind = CodeGenNodePayload::StorageKind::Value;
            return;
        }

        const uint64_t storageAddress = addPayloadToConstantManagerAndGetAddress(codeGen, tmpSpan);
        codeGen.builder().encodeLoadRegPtrImm(payload.reg, storageAddress, cstRef);
        payload.storageKind = CodeGenNodePayload::StorageKind::Address;
    }

    void emitConstantToPayload(CodeGen& codeGen, CodeGenNodePayload& payload, ConstantRef cstRef, const ConstantValue& cst, TypeRef targetTypeRef)
    {
        MicroBuilder& builder = codeGen.builder();

        switch (cst.kind())
        {
            case ConstantKind::Bool:
            {
                builder.encodeLoadRegImm(payload.reg, cst.getBool() ? 1 : 0, MicroOpBits::B64);
                payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                return;
            }

            case ConstantKind::Char:
            {
                builder.encodeLoadRegImm(payload.reg, cst.getChar(), MicroOpBits::B64);
                payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                return;
            }

            case ConstantKind::Rune:
            {
                builder.encodeLoadRegImm(payload.reg, cst.getRune(), MicroOpBits::B64);
                payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                return;
            }

            case ConstantKind::Int:
            {
                const auto& val = cst.getInt();
                SWC_ASSERT(val.fits64());
                builder.encodeLoadRegImm(payload.reg, static_cast<uint64_t>(val.asI64()), MicroOpBits::B64);
                payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                return;
            }

            case ConstantKind::Float:
            {
                const auto& value = cst.getFloat();
                if (value.bitWidth() == 32)
                {
                    const uint32_t bits = std::bit_cast<uint32_t>(value.asFloat());
                    builder.encodeLoadRegImm(payload.reg, bits, MicroOpBits::B32);
                    payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                    return;
                }

                if (value.bitWidth() == 64)
                {
                    const uint64_t bits = std::bit_cast<uint64_t>(value.asDouble());
                    builder.encodeLoadRegImm(payload.reg, bits, MicroOpBits::B64);
                    payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                    return;
                }

                SWC_UNREACHABLE();
            }

            case ConstantKind::String:
            {
                const std::string_view value              = cst.getString();
                const Runtime::String  runtimeString      = {.ptr = value.data(), .length = value.size()};
                const ByteSpan         runtimeStringBytes = asByteSpan(reinterpret_cast<const std::byte*>(&runtimeString), sizeof(runtimeString));
                const uint64_t         storageAddress     = addPayloadToConstantManagerAndGetAddress(codeGen, runtimeStringBytes);
                builder.encodeLoadRegPtrImm(payload.reg, storageAddress, cstRef);
                payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                return;
            }

            case ConstantKind::ValuePointer:
            {
                builder.encodeLoadRegPtrImm(payload.reg, cst.getValuePointer(), cstRef);
                payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                return;
            }

            case ConstantKind::BlockPointer:
            {
                builder.encodeLoadRegPtrImm(payload.reg, cst.getBlockPointer(), cstRef);
                payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                return;
            }

            case ConstantKind::Null:
            {
                builder.encodeLoadRegImm(payload.reg, 0, MicroOpBits::B64);
                payload.storageKind = CodeGenNodePayload::StorageKind::Value;
                return;
            }

            case ConstantKind::EnumValue:
                emitConstantToPayload(codeGen, payload, cst.getEnumValue(), codeGen.cstMgr().get(cst.getEnumValue()), targetTypeRef);
                return;

            case ConstantKind::Struct:
            case ConstantKind::Array:
            case ConstantKind::AggregateStruct:
            case ConstantKind::AggregateArray:
                emitLoweredConstantToPayload(codeGen, payload, cstRef, cst, targetTypeRef);
                return;

            default:
                emitLoweredConstantToPayload(codeGen, payload, cstRef, cst, targetTypeRef);
                return;
        }
    }
}

Result CodeGen::emitConstant(AstNodeRef nodeRef)
{
    if (payload(nodeRef))
        return Result::Continue;

    const SemaNodeView nodeView = this->nodeView(nodeRef);
    if (nodeView.cstRef.isInvalid())
        return Result::Continue;

    const ConstantValue& cst     = cstMgr().get(nodeView.cstRef);
    CodeGenNodePayload&  payload = setPayload(nodeRef, nodeView.typeRef);
    emitConstantToPayload(*this, payload, nodeView.cstRef, cst, nodeView.typeRef);
    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
