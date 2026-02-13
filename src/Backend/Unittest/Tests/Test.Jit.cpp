#include "pch.h"
#include "Backend/Jit/Jit.h"
#include "Backend/Jit/JitExecMemory.h"
#include "Backend/MachineCode/Micro/MicroReg.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#if defined(_M_X64)

namespace
{
    Result runConstantReturn42(TaskContext& ctx)
    {
        Backend::JitExecMemory executableMemory;
        RESULT_VERIFY(Backend::Jit::compile(ctx, [](MicroInstrBuilder& b) {
                                                b.encodeLoadRegImm(MicroReg::intReg(0), 42, MicroOpBits::B32, EncodeFlagsE::Zero);
                                                b.encodeRet(EncodeFlagsE::Zero); }, executableMemory));

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
