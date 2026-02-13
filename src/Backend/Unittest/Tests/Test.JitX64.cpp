#include "pch.h"
#include "Backend/Jit/JitExecutableMemory.h"
#include "Backend/Jit/JitX64.h"
#include "Backend/MachineCode/Micro/MicroReg.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    Result runConstantReturn42(TaskContext& ctx)
    {
#if defined(_M_X64)
        Backend::JitExecutableMemory executableMemory;
        RESULT_VERIFY(Backend::JitX64::compile(ctx, [](MicroInstrBuilder& b) {
                                                    b.encodeLoadRegImm(MicroReg::intReg(0), 42, MicroOpBits::B32, EncodeFlagsE::Zero);
                                                    b.encodeRet(EncodeFlagsE::Zero);
                                                },
                                                executableMemory));

        using TestFn  = uint64_t (*)();
        const auto fn = executableMemory.entryPoint<TestFn>();
        if (!fn)
            return Result::Error;
        if (fn() != 42)
            return Result::Error;
#else
        (void) ctx;
#endif

        return Result::Continue;
    }
}

SWC_TEST_BEGIN(JitX64)
{
    RESULT_VERIFY(runConstantReturn42(ctx));
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
