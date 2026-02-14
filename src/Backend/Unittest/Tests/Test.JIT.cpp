#include "pch.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Backend/MachineCode/CallConv.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#ifdef _M_X64

namespace
{
    Result runCase(TaskContext& ctx, void (*buildFn)(MicroInstrBuilder&, const CallConv&), uint64_t expectedResult)
    {
        const auto& callConv = CallConv::get(CallConvKind::Host);

        MicroInstrBuilder builder(ctx);
        buildFn(builder, callConv);

        JITExecMemory executableMemory;
        RESULT_VERIFY(JIT::compile(ctx, builder, executableMemory));

        using TestFn  = uint64_t (*)();
        const auto fn = executableMemory.entryPoint<TestFn>();
        if (!fn)
            return Result::Error;
        if (fn() != expectedResult)
            return Result::Error;

        return Result::Continue;
    }

    void buildReturn42(MicroInstrBuilder& builder, const CallConv& callConv)
    {
        builder.encodeLoadRegImm(callConv.intReturn, 42, MicroOpBits::B64, EncodeFlagsE::Zero);
        builder.encodeRet(EncodeFlagsE::Zero);
    }
}

SWC_TEST_BEGIN(JIT_Return42)
{
    RESULT_VERIFY(runCase(ctx, &buildReturn42, 42));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_ExecMemoryManagerReusesBlock)
{
    JITExecMemoryManager manager;
    JITExecMemory        memA;
    JITExecMemory        memB;

    const std::array code = {std::byte{0xC3}};
    const ByteSpan   bytes(code.data(), code.size());

    SWC_ASSERT(manager.allocateAndCopy(bytes, memA));
    SWC_ASSERT(manager.allocateAndCopy(bytes, memB));

    using Fn = void (*)();
    const auto fnA = memA.entryPoint<Fn>();
    const auto fnB = memB.entryPoint<Fn>();
    SWC_ASSERT(fnA != nullptr);
    SWC_ASSERT(fnB != nullptr);
    fnA();
    fnB();

    const auto ptrA = std::bit_cast<uintptr_t>(fnA);
    const auto ptrB = std::bit_cast<uintptr_t>(fnB);
    SWC_ASSERT(ptrB > ptrA);
    SWC_ASSERT(ptrB - ptrA < 64 * 1024);
}
SWC_TEST_END()

#endif
#endif

SWC_END_NAMESPACE();

