#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void emitConstantToPayload(CodeGen& codeGen, const CodeGenNodePayload& payload, const ConstantValue& cst)
    {
        auto& builder = codeGen.builder();

        switch (cst.kind())
        {
            case ConstantKind::Bool:
            {
                builder.encodeLoadRegImm(payload.reg, cst.getBool() ? 1 : 0, MicroOpBits::B64, EncodeFlagsE::Zero);
                return;
            }

            case ConstantKind::Char:
            {
                builder.encodeLoadRegImm(payload.reg, cst.getChar(), MicroOpBits::B64, EncodeFlagsE::Zero);
                return;
            }

            case ConstantKind::Rune:
            {
                builder.encodeLoadRegImm(payload.reg, cst.getRune(), MicroOpBits::B64, EncodeFlagsE::Zero);
                return;
            }

            case ConstantKind::Int:
            {
                const auto& val = cst.getInt();
                SWC_ASSERT(val.fits64());
                builder.encodeLoadRegImm(payload.reg, static_cast<uint64_t>(val.asI64()), MicroOpBits::B64, EncodeFlagsE::Zero);
                return;
            }

            case ConstantKind::Float:
            {
                const auto& value = cst.getFloat();
                if (value.bitWidth() == 32)
                {
                    const uint32_t bits = std::bit_cast<uint32_t>(value.asFloat());
                    builder.encodeLoadRegImm(payload.reg, bits, MicroOpBits::B32, EncodeFlagsE::Zero);
                    return;
                }

                if (value.bitWidth() == 64)
                {
                    const uint64_t bits = std::bit_cast<uint64_t>(value.asDouble());
                    builder.encodeLoadRegImm(payload.reg, bits, MicroOpBits::B64, EncodeFlagsE::Zero);
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

                builder.encodeLoadRegImm(payload.reg, reinterpret_cast<uint64_t>(runtimeString), MicroOpBits::B64, EncodeFlagsE::Zero);
                return;
            }

            case ConstantKind::ValuePointer:
            {
                builder.encodeLoadRegImm(payload.reg, cst.getValuePointer(), MicroOpBits::B64, EncodeFlagsE::Zero);
                return;
            }

            case ConstantKind::BlockPointer:
            {
                builder.encodeLoadRegImm(payload.reg, cst.getBlockPointer(), MicroOpBits::B64, EncodeFlagsE::Zero);
                return;
            }

            case ConstantKind::Null:
            {
                builder.encodeLoadRegImm(payload.reg, 0, MicroOpBits::B64, EncodeFlagsE::Zero);
                return;
            }

            case ConstantKind::EnumValue:
                emitConstantToPayload(codeGen, payload, codeGen.ctx().cstMgr().get(cst.getEnumValue()));
                return;

            default:
                SWC_UNREACHABLE();
        }
    }
}

Result CodeGen::emitConstant(AstNodeRef nodeRef)
{
    if (payload(nodeRef))
        return Result::Continue;

    const SemaNodeView nodeView = this->nodeView(nodeRef);
    if (!nodeView.cst)
        return Result::Continue;

    const auto& payload = setPayload(nodeRef, nodeView.typeRef);
    emitConstantToPayload(*this, payload, *nodeView.cst);
    return Result::Continue;
}

SWC_END_NAMESPACE();
