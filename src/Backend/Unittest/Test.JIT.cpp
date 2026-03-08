#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITMemory.h"
#include "Backend/Micro/MachineCode.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
#ifdef _M_X64

namespace
{
    Result runCase(TaskContext& ctx, void (*buildFn)(MicroBuilder&, const CallConv&), uint64_t expectedResult)
    {
        const CallConv& callConv = CallConv::host();

        MicroBuilder builder(ctx);
        buildFn(builder, callConv);

        MachineCode loweredCode;
        SWC_RESULT_VERIFY(loweredCode.emit(ctx, builder));

        JITMemory executableMemory;
        JIT::emit(ctx, executableMemory, asByteSpan(loweredCode.bytes), loweredCode.codeRelocations, loweredCode.unwindInfo);

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
        builder.emitLoadRegImm(callConv.intReturn, ApInt(42, 64), MicroOpBits::B64);
        builder.emitRet();
    }
}

SWC_TEST_BEGIN(JIT_Return42)
{
    SWC_RESULT_VERIFY(runCase(ctx, &buildReturn42, 42));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_PersistentRegPreservedAcrossCall)
{
    const CallConv& callConv = CallConv::host();

    MicroBuilder calleeBuilder(ctx);
    calleeBuilder.emitLoadRegImm(MicroReg::intReg(15), ApInt(0x1234, 64), MicroOpBits::B64);
    calleeBuilder.emitLoadRegImm(callConv.intReturn, ApInt(1, 64), MicroOpBits::B64);
    calleeBuilder.emitRet();

    MachineCode loweredCalleeCode;
    SWC_RESULT_VERIFY(loweredCalleeCode.emit(ctx, calleeBuilder));

    JITMemory calleeExecMemory;
    JIT::emit(ctx, calleeExecMemory, asByteSpan(loweredCalleeCode.bytes), loweredCalleeCode.codeRelocations, loweredCalleeCode.unwindInfo);
    using CalleeFnType  = uint64_t (*)();
    const auto calleeFn = reinterpret_cast<CalleeFnType>(calleeExecMemory.entryPoint());
    SWC_ASSERT(calleeFn != nullptr);
    SWC_ASSERT(calleeFn() == 1);

    MicroBuilder callerBuilder(ctx);
    callerBuilder.emitLoadRegImm(MicroReg::intReg(15), ApInt(7, 64), MicroOpBits::B64);
    callerBuilder.emitLoadRegPtrImm(MicroReg::intReg(10), reinterpret_cast<uint64_t>(calleeFn));
    callerBuilder.emitCallReg(MicroReg::intReg(10), CallConvKind::Host);
    callerBuilder.emitOpBinaryRegImm(MicroReg::intReg(15), ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    callerBuilder.emitLoadRegReg(callConv.intReturn, MicroReg::intReg(15), MicroOpBits::B64);
    callerBuilder.emitRet();

    MachineCode loweredCallerCode;
    SWC_RESULT_VERIFY(loweredCallerCode.emit(ctx, callerBuilder));

    JITMemory callerExecMemory;
    JIT::emit(ctx, callerExecMemory, asByteSpan(loweredCallerCode.bytes), loweredCallerCode.codeRelocations, loweredCallerCode.unwindInfo);
    using CallerFnType  = uint64_t (*)();
    const auto callerFn = reinterpret_cast<CallerFnType>(callerExecMemory.entryPoint());
    SWC_ASSERT(callerFn != nullptr);
    SWC_ASSERT(callerFn() == 8);
}
SWC_TEST_END()

#endif
SWC_END_NAMESPACE();

#endif
