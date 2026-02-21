#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Runtime.h"
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

    void emitConstantToPayload(CodeGen& codeGen, CodeGenNodePayload& payload, ConstantRef cstRef, const ConstantValue& cst, TypeRef targetTypeRef)
    {
        MicroBuilder& builder = codeGen.builder();

        switch (cst.kind())
        {
            case ConstantKind::Bool:
            {
                builder.emitLoadRegImm(payload.reg, cst.getBool() ? 1 : 0, MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Char:
            {
                builder.emitLoadRegImm(payload.reg, cst.getChar(), MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Rune:
            {
                builder.emitLoadRegImm(payload.reg, cst.getRune(), MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Int:
            {
                const auto& val = cst.getInt();
                SWC_ASSERT(val.fits64());
                builder.emitLoadRegImm(payload.reg, static_cast<uint64_t>(val.asI64()), MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Float:
            {
                const auto& value = cst.getFloat();
                if (value.bitWidth() == 32)
                {
                    const uint32_t bits = std::bit_cast<uint32_t>(value.asFloat());
                    builder.emitLoadRegImm(payload.reg, bits, MicroOpBits::B32);
                    payload.setIsValue();
                    return;
                }

                if (value.bitWidth() == 64)
                {
                    const uint64_t bits = std::bit_cast<uint64_t>(value.asDouble());
                    builder.emitLoadRegImm(payload.reg, bits, MicroOpBits::B64);
                    payload.setIsValue();
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
                builder.emitLoadRegPtrImm(payload.reg, storageAddress, cstRef);
                payload.setIsValue();
                return;
            }

            case ConstantKind::ValuePointer:
            {
                builder.emitLoadRegPtrImm(payload.reg, cst.getValuePointer(), cstRef);
                payload.setIsValue();
                return;
            }

            case ConstantKind::BlockPointer:
            {
                builder.emitLoadRegPtrImm(payload.reg, cst.getBlockPointer(), cstRef);
                payload.setIsValue();
                return;
            }

            case ConstantKind::Null:
            {
                builder.emitLoadRegImm(payload.reg, 0, MicroOpBits::B64);
                payload.setIsValue();
                return;
            }

            case ConstantKind::EnumValue:
                emitConstantToPayload(codeGen, payload, cst.getEnumValue(), codeGen.cstMgr().get(cst.getEnumValue()), targetTypeRef);
                return;

            case ConstantKind::Struct:
            {
                const ByteSpan structBytes = cst.getStruct();
                const uint64_t storageSize = cst.type(codeGen.ctx()).sizeOf(codeGen.ctx());
                SWC_ASSERT(structBytes.size() == storageSize);
                codeGen.builder().emitLoadRegPtrImm(payload.reg, reinterpret_cast<uint64_t>(structBytes.data()), cstRef);
                payload.setIsAddress();
                return;
            }

            case ConstantKind::Array:
            {
                const ByteSpan arrayBytes  = cst.getArray();
                if (targetTypeRef.isValid())
                {
                    const TypeInfo& targetType = codeGen.typeMgr().get(targetTypeRef);
                    if (targetType.isSlice())
                    {
                        const TypeInfo&      elementType = codeGen.typeMgr().get(targetType.payloadTypeRef());
                        const uint64_t       elementSize = elementType.sizeOf(codeGen.ctx());
                        const Runtime::Slice runtimeSlice{
                            .ptr   = const_cast<std::byte*>(arrayBytes.data()),
                            .count = elementSize ? arrayBytes.size() / elementSize : 0,
                        };
                        const ByteSpan runtimeSliceBytes = asByteSpan(reinterpret_cast<const std::byte*>(&runtimeSlice), sizeof(runtimeSlice));
                        const uint64_t storageAddress    = addPayloadToConstantManagerAndGetAddress(codeGen, runtimeSliceBytes);
                        codeGen.builder().emitLoadRegPtrImm(payload.reg, storageAddress, cstRef);
                        payload.setIsValue();
                        return;
                    }
                }

                const uint64_t storageSize = cst.type(codeGen.ctx()).sizeOf(codeGen.ctx());
                SWC_ASSERT(arrayBytes.size() == storageSize);
                codeGen.builder().emitLoadRegPtrImm(payload.reg, reinterpret_cast<uint64_t>(arrayBytes.data()), cstRef);
                payload.setIsAddress();
                return;
            }

            default:
                SWC_UNREACHABLE();
        }
    }
}

Result CodeGen::emitConstant(AstNodeRef nodeRef)
{
    if (payload(nodeRef))
        return Result::Continue;

    const SemaNodeView view = viewTypeConstant(nodeRef);
    if (view.cstRef().isInvalid())
        return Result::Continue;

    const ConstantValue& cst     = cstMgr().get(view.cstRef());
    CodeGenNodePayload&  payload = setPayload(nodeRef, view.typeRef());
    emitConstantToPayload(*this, payload, view.cstRef(), cst, view.typeRef());
    return Result::SkipChildren;
}

Result AstNullLiteral::codeGenPostNode(CodeGen& codeGen)
{
    const CodeGenNodePayload& payload = codeGen.setPayloadValue(codeGen.curNodeRef(), codeGen.curViewType().typeRef());
    codeGen.builder().emitLoadRegImm(payload.reg, 0, MicroOpBits::B64);
    return Result::Continue;
}

SWC_END_NAMESPACE();
