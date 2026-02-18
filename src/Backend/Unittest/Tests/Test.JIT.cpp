#include "pch.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MachineCode.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITMemory.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#ifdef _M_X64

namespace
{
    Result runCase(TaskContext& ctx, void (*buildFn)(MicroBuilder&, const CallConv&), uint64_t expectedResult)
    {
        const CallConv& callConv = CallConv::host();

        MicroBuilder builder(ctx);
        buildFn(builder, callConv);

        MachineCode loweredCode;
        loweredCode.emit(ctx, builder);

        JITMemory executableMemory;
        JIT::emit(ctx, executableMemory, asByteSpan(loweredCode.bytes), loweredCode.codeRelocations);

        using TestFn  = uint64_t (*)();
        const auto fn = reinterpret_cast<TestFn>(executableMemory.entryPoint());
        if (!fn)
            return Result::Error;
        if (fn() != expectedResult)
            return Result::Error;

        return Result::Continue;
    }

    void buildReturn42(MicroBuilder& builder, const CallConv& callConv)
    {
        builder.encodeLoadRegImm(callConv.intReturn, 42, MicroOpBits::B64);
        builder.encodeRet();
    }
}

SWC_TEST_BEGIN(JIT_Return42)
{
    RESULT_VERIFY(runCase(ctx, &buildReturn42, 42));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_PersistentRegPreservedAcrossCall)
{
    const CallConv& callConv = CallConv::host();

    MicroBuilder calleeBuilder(ctx);
    calleeBuilder.encodeLoadRegImm(MicroReg::intReg(15), 0x1234, MicroOpBits::B64);
    calleeBuilder.encodeLoadRegImm(callConv.intReturn, 1, MicroOpBits::B64);
    calleeBuilder.encodeRet();

    MachineCode loweredCalleeCode;
    loweredCalleeCode.emit(ctx, calleeBuilder);

    JITMemory calleeExecMemory;
    JIT::emit(ctx, calleeExecMemory, asByteSpan(loweredCalleeCode.bytes), loweredCalleeCode.codeRelocations);
    using CalleeFnType  = uint64_t (*)();
    const auto calleeFn = reinterpret_cast<CalleeFnType>(calleeExecMemory.entryPoint());
    SWC_ASSERT(calleeFn != nullptr);
    SWC_ASSERT(calleeFn() == 1);

    MicroBuilder callerBuilder(ctx);
    callerBuilder.encodeLoadRegImm(MicroReg::intReg(15), 7, MicroOpBits::B64);
    callerBuilder.encodeLoadRegPtrImm(MicroReg::intReg(10), reinterpret_cast<uint64_t>(calleeFn));
    callerBuilder.encodeCallReg(MicroReg::intReg(10), CallConvKind::Host);
    callerBuilder.encodeOpBinaryRegImm(MicroReg::intReg(15), 1, MicroOp::Add, MicroOpBits::B64);
    callerBuilder.encodeLoadRegReg(callConv.intReturn, MicroReg::intReg(15), MicroOpBits::B64);
    callerBuilder.encodeRet();

    MachineCode loweredCallerCode;
    loweredCallerCode.emit(ctx, callerBuilder);

    JITMemory callerExecMemory;
    JIT::emit(ctx, callerExecMemory, asByteSpan(loweredCallerCode.bytes), loweredCallerCode.codeRelocations);
    using CallerFnType  = uint64_t (*)();
    const auto callerFn = reinterpret_cast<CallerFnType>(callerExecMemory.entryPoint());
    SWC_ASSERT(callerFn != nullptr);
    SWC_ASSERT(callerFn() == 8);
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_ExecMemoryManagerReusesBlock)
{
    JITMemoryManager manager;
    JITMemory        memA;
    JITMemory        memB;

    constexpr std::array code = {std::byte{0xC3}};
    const ByteSpan       bytes(code.data(), code.size());

    SWC_ASSERT(manager.allocateAndCopy(memA, bytes));
    SWC_ASSERT(manager.allocateAndCopy(memB, bytes));

    using Fn       = void (*)();
    const auto fnA = reinterpret_cast<Fn>(memA.entryPoint());
    const auto fnB = reinterpret_cast<Fn>(memB.entryPoint());
    SWC_ASSERT(fnA != nullptr);
    SWC_ASSERT(fnB != nullptr);
    fnA();
    fnB();

    const uintptr_t ptrA = std::bit_cast<uintptr_t>(fnA);
    const uintptr_t ptrB = std::bit_cast<uintptr_t>(fnB);
    SWC_ASSERT(ptrB > ptrA);
    SWC_ASSERT(ptrB - ptrA < 64 * 1024ull);
}
SWC_TEST_END()

#endif
#endif

SWC_END_NAMESPACE();
