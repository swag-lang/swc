#include "pch.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MachineCode.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Backend/JIT/JITExecMemoryManager.h"
#include "Backend/JIT/FFI.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST
#ifdef _M_X64

namespace
{
    Result runCase(TaskContext& ctx, void (*buildFn)(MicroInstrBuilder&, const CallConv&), uint64_t expectedResult)
    {
        const auto& callConv = CallConv::host();

        MicroInstrBuilder builder(ctx);
        buildFn(builder, callConv);

        MachineCode loweredCode;
        loweredCode.emit(ctx, builder);

        JITExecMemory executableMemory;
        FFI::emit(ctx, asByteSpan(loweredCode.bytes), loweredCode.codeRelocations, executableMemory);

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
    const auto& callConv = CallConv::host();

    MicroInstrBuilder calleeBuilder(ctx);
    calleeBuilder.encodeLoadRegImm(MicroReg::intReg(15), 0x1234, MicroOpBits::B64);
    calleeBuilder.encodeLoadRegImm(callConv.intReturn, 1, MicroOpBits::B64);
    calleeBuilder.encodeRet();

    MachineCode loweredCalleeCode;
    loweredCalleeCode.emit(ctx, calleeBuilder);

    JITExecMemory calleeExecMemory;
    FFI::emit(ctx, asByteSpan(loweredCalleeCode.bytes), loweredCalleeCode.codeRelocations, calleeExecMemory);
    using CalleeFnType  = uint64_t (*)();
    const auto calleeFn = calleeExecMemory.entryPoint<CalleeFnType>();
    SWC_ASSERT(calleeFn != nullptr);
    SWC_ASSERT(calleeFn() == 1);

    MicroInstrBuilder callerBuilder(ctx);
    callerBuilder.encodeLoadRegImm(MicroReg::intReg(15), 7, MicroOpBits::B64);
    callerBuilder.encodeLoadRegImm(MicroReg::intReg(10), reinterpret_cast<uint64_t>(calleeFn), MicroOpBits::B64);
    callerBuilder.encodeCallReg(MicroReg::intReg(10), CallConvKind::Host);
    callerBuilder.encodeOpBinaryRegImm(MicroReg::intReg(15), 1, MicroOp::Add, MicroOpBits::B64);
    callerBuilder.encodeLoadRegReg(callConv.intReturn, MicroReg::intReg(15), MicroOpBits::B64);
    callerBuilder.encodeRet();

    MachineCode loweredCallerCode;
    loweredCallerCode.emit(ctx, callerBuilder);

    JITExecMemory callerExecMemory;
    FFI::emit(ctx, asByteSpan(loweredCallerCode.bytes), loweredCallerCode.codeRelocations, callerExecMemory);
    using CallerFnType  = uint64_t (*)();
    const auto callerFn = callerExecMemory.entryPoint<CallerFnType>();
    SWC_ASSERT(callerFn != nullptr);
    SWC_ASSERT(callerFn() == 8);
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_ExecMemoryManagerReusesBlock)
{
    JITExecMemoryManager manager;
    JITExecMemory        memA;
    JITExecMemory        memB;

    constexpr std::array code = {std::byte{0xC3}};
    const ByteSpan       bytes(code.data(), code.size());

    SWC_ASSERT(manager.allocateAndCopy(bytes, memA));
    SWC_ASSERT(manager.allocateAndCopy(bytes, memB));

    using Fn       = void (*)();
    const auto fnA = memA.entryPoint<Fn>();
    const auto fnB = memB.entryPoint<Fn>();
    SWC_ASSERT(fnA != nullptr);
    SWC_ASSERT(fnB != nullptr);
    fnA();
    fnB();

    const auto ptrA = std::bit_cast<uintptr_t>(fnA);
    const auto ptrB = std::bit_cast<uintptr_t>(fnB);
    SWC_ASSERT(ptrB > ptrA);
    SWC_ASSERT(ptrB - ptrA < 64 * 1024ull);
}
SWC_TEST_END()

#endif
#endif

SWC_END_NAMESPACE();
