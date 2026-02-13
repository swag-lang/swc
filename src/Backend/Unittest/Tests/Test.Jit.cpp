#include "pch.h"
#include "Backend/Jit/Jit.h"
#include "Backend/Jit/JitExecMemory.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroReg.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#ifdef _M_X64

namespace
{
    Result runConstantReturn42(TaskContext& ctx)
    {
        const auto& callConv = CallConv::get(CallConvKind::C);

        MicroInstrBuilder builder(ctx);
        builder.encodeLoadRegImm(callConv.intReturn, 42, MicroOpBits::B32, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);

        Backend::JitExecMemory executableMemory;
        RESULT_VERIFY(Backend::Jit::compile(ctx, builder, executableMemory));

        using TestFn  = uint64_t (*)();
        const auto fn = executableMemory.entryPoint<TestFn>();
        if (!fn)
            return Result::Error;
        if (fn() != 42)
            return Result::Error;

        return Result::Continue;
    }
}

SWC_TEST_BEGIN(Jit)
{
    RESULT_VERIFY(runConstantReturn42(ctx));
}
SWC_TEST_END()

#endif
#endif

SWC_END_NAMESPACE();
