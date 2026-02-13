#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#ifdef _M_X64

namespace
{
    uint64_t ffiNativeReturn123()
    {
        return 123;
    }
}

SWC_TEST_BEGIN(FFI_CallNativeNoArgU64)
{
    Backend::JITExecMemory executableMemory;
    RESULT_VERIFY(Backend::FFI::compileCallU64(ctx, reinterpret_cast<void*>(&ffiNativeReturn123), executableMemory));

    using TestFn  = uint64_t (*)();
    const auto fn = executableMemory.entryPoint<TestFn>();
    if (!fn)
        return Result::Error;
    if (fn() != 123)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_RejectNullFunction)
{
    Backend::JITExecMemory executableMemory;
    if (Backend::FFI::compileCallU64(ctx, nullptr, executableMemory) != Result::Error)
        return Result::Error;
}
SWC_TEST_END()

#endif
#endif

SWC_END_NAMESPACE();
