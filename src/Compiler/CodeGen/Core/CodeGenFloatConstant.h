#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Support/Math/ApFloat.h"
#include <bit>

SWC_BEGIN_NAMESPACE();

namespace CodeGenFloatConstant
{
    inline bool emit(CodeGen& codeGen, MicroBuilder& builder, CodeGenNodePayload& payload, const ApFloat& value)
    {
        payload.reg = codeGen.nextVirtualFloatRegister();
        if (value.bitWidth() == 32)
        {
            const double   widenedValue = value.asFloat();
            const uint64_t widenedBits  = std::bit_cast<uint64_t>(widenedValue);
            const MicroReg widenedReg   = codeGen.nextVirtualFloatRegister();
            builder.emitLoadRegImm(widenedReg, ApInt(widenedBits, 64), MicroOpBits::B64);
            builder.emitClearReg(payload.reg, MicroOpBits::B32);
            builder.emitOpBinaryRegReg(payload.reg, widenedReg, MicroOp::ConvertFloatToFloat, MicroOpBits::B64);
            payload.setIsValue();
            return true;
        }

        if (value.bitWidth() == 64)
        {
            const auto bits = std::bit_cast<uint64_t>(value.asDouble());
            builder.emitLoadRegImm(payload.reg, ApInt(bits, 64), MicroOpBits::B64);
            payload.setIsValue();
            return true;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
