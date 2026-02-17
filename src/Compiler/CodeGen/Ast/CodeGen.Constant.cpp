#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void emitLoweredConstantToPayload(CodeGen& codeGen, CodeGenNodePayload& payload, ConstantRef cstRef, const ConstantValue& cst, TypeRef targetTypeRef)
    {
        auto&           ctx         = codeGen.ctx();
        const TypeRef   finalTypeRef = targetTypeRef.isValid() ? targetTypeRef : cst.typeRef();
        const TypeInfo& typeInfo     = ctx.typeMgr().get(finalTypeRef);
        const uint64_t  storageSize = typeInfo.sizeOf(ctx);
        if (!storageSize)
        {
            codeGen.builder().encodeLoadRegImm(payload.reg, 0, MicroOpBits::B64);
            payload.storageKind = CodeGenNodePayload::StorageKind::Value;
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

        auto* const storage = ctx.compiler().allocateArray<std::byte>(storageSize);
        std::memcpy(storage, tmpSpan.data(), tmpSpan.size());
        codeGen.builder().encodeLoadRegPtrImm(payload.reg, reinterpret_cast<uint64_t>(storage), cstRef);
        payload.storageKind = CodeGenNodePayload::StorageKind::Address;
    }

    void emitConstantToPayload(CodeGen& codeGen, CodeGenNodePayload& payload, ConstantRef cstRef, const ConstantValue& cst, TypeRef targetTypeRef)
    {
        auto& builder = codeGen.builder();

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

                SWC_ASSERT(false);
                return;
            }

            case ConstantKind::String:
            {
                const std::string_view value = cst.getString();
                char*                  data  = nullptr;
                if (!value.empty())
                {
                    data = codeGen.ctx().compiler().allocateArray<char>(value.size());
                    std::memcpy(data, value.data(), value.size());
                }

                auto* runtimeString   = codeGen.ctx().compiler().allocate<Runtime::String>();
                runtimeString->ptr    = data;
                runtimeString->length = value.size();

                builder.encodeLoadRegPtrImm(payload.reg, reinterpret_cast<uint64_t>(runtimeString), cstRef);
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
                emitConstantToPayload(codeGen, payload, cst.getEnumValue(), codeGen.ctx().cstMgr().get(cst.getEnumValue()), targetTypeRef);
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
    ConstantRef        cstRef   = nodeView.cstRef;
    TypeRef            typeRef  = nodeView.typeRef;

    if (cstRef.isInvalid())
    {
        cstRef = sema().constantRefOf(nodeRef);
        if (cstRef.isInvalid())
            return Result::Continue;
    }

    if (typeRef.isInvalid())
        typeRef = sema().typeRefOf(nodeRef);

    const auto& cst = sema().cstMgr().get(cstRef);

    auto& payload = setPayload(nodeRef, typeRef);
    emitConstantToPayload(*this, payload, cstRef, cst, typeRef);
    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
