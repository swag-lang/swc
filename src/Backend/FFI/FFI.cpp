#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JIT.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    Result FFI::compileCallU64(TaskContext& ctx, void* targetFn, JITExecMemory& outExecutableMemory)
    {
        if (!targetFn)
            return Result::Error;

        MicroInstrBuilder builder(ctx);
        builder.encodeLoadRegImm(MicroReg::intReg(0), reinterpret_cast<uint64_t>(targetFn), MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeCallReg(MicroReg::intReg(0), CallConvKind::Host, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);

        return JIT::compile(ctx, builder, outExecutableMemory);
    }
}

SWC_END_NAMESPACE();
