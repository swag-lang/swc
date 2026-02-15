#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool tryEmitConstantToPayload(CodeGen& codeGen, AstNodeRef nodeRef, TypeRef typeRef, const ConstantValue& cst)
    {
        auto& builder = codeGen.builder();

        switch (cst.kind())
        {
            case ConstantKind::Bool:
            {
                auto& payload = codeGen.setPayload(nodeRef, typeRef);
                builder.encodeLoadRegImm(payload.reg, cst.getBool() ? 1 : 0, MicroOpBits::B64, EncodeFlagsE::Zero);
                return true;
            }

            case ConstantKind::Char:
            {
                auto& payload = codeGen.setPayload(nodeRef, typeRef);
                builder.encodeLoadRegImm(payload.reg, static_cast<uint64_t>(cst.getChar()), MicroOpBits::B64, EncodeFlagsE::Zero);
                return true;
            }

            case ConstantKind::Rune:
            {
                auto& payload = codeGen.setPayload(nodeRef, typeRef);
                builder.encodeLoadRegImm(payload.reg, static_cast<uint64_t>(cst.getRune()), MicroOpBits::B64, EncodeFlagsE::Zero);
                return true;
            }

            case ConstantKind::Int:
            {
                const auto& val = cst.getInt();
                if (!val.fits64())
                    return false;
                auto& payload = codeGen.setPayload(nodeRef, typeRef);
                builder.encodeLoadRegImm(payload.reg, static_cast<uint64_t>(val.asI64()), MicroOpBits::B64, EncodeFlagsE::Zero);
                return true;
            }

            case ConstantKind::Float:
            {
                const auto& value = cst.getFloat();
                auto&       payload = codeGen.setPayload(nodeRef, typeRef);
                if (value.bitWidth() == 32)
                {
                    const uint32_t bits = std::bit_cast<uint32_t>(value.asFloat());
                    builder.encodeLoadRegImm(payload.reg, bits, MicroOpBits::B32, EncodeFlagsE::Zero);
                    return true;
                }

                if (value.bitWidth() == 64)
                {
                    const uint64_t bits = std::bit_cast<uint64_t>(value.asDouble());
                    builder.encodeLoadRegImm(payload.reg, bits, MicroOpBits::B64, EncodeFlagsE::Zero);
                    return true;
                }

                return false;
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

                auto* runtimeString = codeGen.ctx().compiler().allocate<Runtime::String>();
                runtimeString->ptr    = data;
                runtimeString->length = value.size();

                auto& payload = codeGen.setPayload(nodeRef, typeRef);
                builder.encodeLoadRegImm(payload.reg, reinterpret_cast<uint64_t>(runtimeString), MicroOpBits::B64, EncodeFlagsE::Zero);
                return true;
            }

            case ConstantKind::ValuePointer:
            {
                auto& payload = codeGen.setPayload(nodeRef, typeRef);
                builder.encodeLoadRegImm(payload.reg, cst.getValuePointer(), MicroOpBits::B64, EncodeFlagsE::Zero);
                return true;
            }

            case ConstantKind::BlockPointer:
            {
                auto& payload = codeGen.setPayload(nodeRef, typeRef);
                builder.encodeLoadRegImm(payload.reg, cst.getBlockPointer(), MicroOpBits::B64, EncodeFlagsE::Zero);
                return true;
            }

            case ConstantKind::Null:
            {
                auto& payload = codeGen.setPayload(nodeRef, typeRef);
                builder.encodeLoadRegImm(payload.reg, 0, MicroOpBits::B64, EncodeFlagsE::Zero);
                return true;
            }

            case ConstantKind::EnumValue:
                return tryEmitConstantToPayload(codeGen, nodeRef, typeRef, codeGen.ctx().cstMgr().get(cst.getEnumValue()));

            default:
                return false;
        }
    }
}

Result CodeGen::lowerConstant(AstNodeRef nodeRef)
{
    if (payload(nodeRef))
        return Result::Continue;

    const SemaNodeView nodeView = this->nodeView(nodeRef);
    if (!nodeView.cst)
        return Result::Continue;

    tryEmitConstantToPayload(*this, nodeRef, nodeView.typeRef, *nodeView.cst);
    return Result::Continue;
}

SWC_END_NAMESPACE();
