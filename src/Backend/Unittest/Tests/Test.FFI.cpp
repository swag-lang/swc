#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    Result runCase(TaskContext& ctx, void* targetFn, uint64_t expectedResult)
    {
        Backend::JITExecMemory executableMemory;
        RESULT_VERIFY(Backend::FFI::compileCallU64(ctx, targetFn, executableMemory));

        using TestFn  = uint64_t (*)();
        const auto fn = executableMemory.entryPoint<TestFn>();
        if (!fn)
            return Result::Error;
        if (fn() != expectedResult)
            return Result::Error;

        return Result::Continue;
    }
}

namespace
{
    uint64_t ffiNativeReturn123()
    {
        return 123;
    }
}

SWC_TEST_BEGIN(FFI_CallNativeNoArgU64)
{
    RESULT_VERIFY(runCase(ctx, reinterpret_cast<void*>(&ffiNativeReturn123), 123));
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
