#include "pch.h"
#include "Support/Report/Assert.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITMemory.h"
#include "Backend/Micro/MachineCode.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
#ifdef _M_X64

namespace
{
    struct Copy128Payload
    {
        uint64_t lo;
        uint64_t hi;
    };

    Result runCase(TaskContext& ctx, void (*buildFn)(MicroBuilder&, const CallConv&), uint64_t expectedResult)
    {
        const CallConv& callConv = CallConv::swag();

        MicroBuilder builder(ctx);
        buildFn(builder, callConv);

        MachineCode loweredCode;
        SWC_RESULT(loweredCode.emit(ctx, builder));

        JITMemory executableMemory;
        SWC_RESULT(JIT::emit(ctx, executableMemory, loweredCode.bytes, loweredCode.codeRelocations, loweredCode.unwindInfo));

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

    void buildReturnVirtualAcrossConcreteClobber(MicroBuilder& builder, const CallConv& callConv)
    {
        constexpr MicroReg v0  = MicroReg::virtualIntReg(0);
        constexpr MicroReg r10 = MicroReg::intReg(10);
        constexpr MicroReg r11 = MicroReg::intReg(11);

        SmallVector<MicroReg> forbiddenRegs;
        for (const auto reg : callConv.intRegs)
        {
            if (reg == r10 || reg == r11)
                continue;

            forbiddenRegs.push_back(reg);
        }

        builder.addVirtualRegForbiddenPhysRegs(v0, forbiddenRegs.span());
        builder.emitLoadRegImm(v0, ApInt(3, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(r11, ApInt(0x11, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(r11, ApInt(0x22, 64), MicroOpBits::B64);
        builder.emitLoadRegReg(callConv.intReturn, v0, MicroOpBits::B64);
        builder.emitRet();
    }

    void buildReturnZeroAfter128BitStackCopy(MicroBuilder& builder, const CallConv& callConv)
    {
        static constexpr Copy128Payload PAYLOAD = {
            .lo = 0x1122334455667788ull,
            .hi = 0x99AABBCCDDEEFF00ull,
        };
        Runtime::BuildCfgBackend buildCfg{};
        buildCfg.optimize = true;
        builder.setBackendBuildCfg(buildCfg);

        constexpr MicroReg r8   = MicroReg::intReg(8);
        constexpr MicroReg r9   = MicroReg::intReg(9);
        constexpr MicroReg r10  = MicroReg::intReg(10);
        constexpr MicroReg r11  = MicroReg::intReg(11);
        constexpr MicroReg rbx  = MicroReg::intReg(1);
        constexpr MicroReg xmm3 = MicroReg::floatReg(3);

        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(32, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitLoadRegReg(rbx, callConv.stackPointer, MicroOpBits::B64);
        builder.emitLoadRegPtrImm(r8, reinterpret_cast<uint64_t>(&PAYLOAD));
        builder.emitLoadRegMem(xmm3, r8, 0, MicroOpBits::B128);
        builder.emitLoadMemReg(rbx, 16, xmm3, MicroOpBits::B128);

        builder.emitLoadRegMem(callConv.intReturn, rbx, 16, MicroOpBits::B64);
        builder.emitLoadRegMem(r11, rbx, 24, MicroOpBits::B64);

        builder.emitLoadRegImm(r9, ApInt(PAYLOAD.lo, 64), MicroOpBits::B64);
        builder.emitOpBinaryRegReg(callConv.intReturn, r9, MicroOp::Xor, MicroOpBits::B64);
        builder.emitLoadRegImm(r10, ApInt(PAYLOAD.hi, 64), MicroOpBits::B64);
        builder.emitOpBinaryRegReg(r11, r10, MicroOp::Xor, MicroOpBits::B64);
        builder.emitOpBinaryRegReg(callConv.intReturn, r11, MicroOp::Or, MicroOpBits::B64);

        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(32, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitRet();
    }

    void buildReturnOneAfterPointerSpillRoundTrip(MicroBuilder& builder, const CallConv& callConv)
    {
        Runtime::BuildCfgBackend buildCfg{};
        buildCfg.optimize = true;
        builder.setBackendBuildCfg(buildCfg);

        constexpr MicroReg rcx = MicroReg::intReg(2);
        constexpr MicroReg r8  = MicroReg::intReg(8);
        constexpr MicroReg r9  = MicroReg::intReg(9);
        constexpr MicroReg r10 = MicroReg::intReg(10);

        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(0x80, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitLoadAddressRegMem(rcx, callConv.stackPointer, 8, MicroOpBits::B64);
        builder.emitLoadMemReg(callConv.stackPointer, 0x70, rcx, MicroOpBits::B64);
        builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B32);
        builder.emitLoadRegMem(r9, callConv.stackPointer, 0x70, MicroOpBits::B64);
        builder.emitLoadMemReg(r9, 0, r8, MicroOpBits::B32);
        builder.emitLoadRegMem(r10, callConv.stackPointer, 0x70, MicroOpBits::B64);
        builder.emitLoadRegMem(callConv.intReturn, r10, 0, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(0x80, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitRet();
    }

    struct ConstantDivisionCase
    {
        uint64_t    dividend;
        uint64_t    divisor;
        MicroOp     op;
        MicroOpBits opBits;
    };

    // Exercises the strength-reduction expansion of division by a constant: unsigned
    // magic with and without the add-fixup, signed magic, signed powers of two, and
    // the matching modulo reconstructions, over both operand widths and including
    // the boundary dividends. The baseline (unoptimized) run of the same program
    // cross-checks the C++ reference against the hardware divide.
    constexpr ConstantDivisionCase CONSTANT_DIVISION_CASES[] = {
        {0, 10, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {1, 10, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {9, 10, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {123456789, 10, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {0xFFFFFFFFFFFFFFFFull, 10, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {0, 7, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {6, 7, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {49, 7, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {(1ull << 63) + 12345, 7, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {0xFFFFFFFFFFFFFFFFull, 7, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {999999999999999989ull, 641, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {0xFFFFFFFFFFFFFFFFull, 0xFFFFFFFFFFFFFFFBull, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {12345, 800, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {639999, 800, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {640000, 800, MicroOp::DivideUnsigned, MicroOpBits::B64},
        {0xFFFFFFFFFFFFFFFFull, 10, MicroOp::ModuloUnsigned, MicroOpBits::B64},
        {123, 10, MicroOp::ModuloUnsigned, MicroOpBits::B64},
        {(1ull << 63) + 9, 7, MicroOp::ModuloUnsigned, MicroOpBits::B64},
        {639999, 800, MicroOp::ModuloUnsigned, MicroOpBits::B64},
        {1000002, 1000003, MicroOp::ModuloUnsigned, MicroOpBits::B64},
        {1000003, 1000003, MicroOp::ModuloUnsigned, MicroOpBits::B64},
        {2000007, 1000003, MicroOp::ModuloUnsigned, MicroOpBits::B64},
        {0xFFFFFFFF, 7, MicroOp::DivideUnsigned, MicroOpBits::B32},
        {0xFFFFFFFF, 10, MicroOp::DivideUnsigned, MicroOpBits::B32},
        {99, 10, MicroOp::DivideUnsigned, MicroOpBits::B32},
        {1ull << 31, 800, MicroOp::DivideUnsigned, MicroOpBits::B32},
        {0xFFFFFFFF, 10, MicroOp::ModuloUnsigned, MicroOpBits::B32},
        {801, 800, MicroOp::ModuloUnsigned, MicroOpBits::B32},
        {static_cast<uint64_t>(INT64_MIN), 2, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(INT64_MIN), 4096, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-37), 8, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-8), 8, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-7), 8, MicroOp::DivideSigned, MicroOpBits::B64},
        {7, 8, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(INT64_MAX), 2, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(INT64_MIN), 7, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(INT64_MAX), 7, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-1000003), 10, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-37), 3, MicroOp::DivideSigned, MicroOpBits::B64},
        {999999, 1000003, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-999999999999ll), 800, MicroOp::DivideSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(INT64_MIN), 7, MicroOp::ModuloSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-37), 10, MicroOp::ModuloSigned, MicroOpBits::B64},
        {37, 10, MicroOp::ModuloSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-4096), 4096, MicroOp::ModuloSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(INT64_MIN), 4096, MicroOp::ModuloSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(-1), 3, MicroOp::ModuloSigned, MicroOpBits::B64},
        {static_cast<uint64_t>(INT32_MIN), 7, MicroOp::DivideSigned, MicroOpBits::B32},
        {static_cast<uint64_t>(-5), 7, MicroOp::DivideSigned, MicroOpBits::B32},
        {6, 7, MicroOp::DivideSigned, MicroOpBits::B32},
        {static_cast<uint64_t>(INT32_MIN), 8, MicroOp::DivideSigned, MicroOpBits::B32},
        {static_cast<uint64_t>(-5), 8, MicroOp::ModuloSigned, MicroOpBits::B32},
        {0x7FFFFFFF, 7, MicroOp::ModuloSigned, MicroOpBits::B32},
    };

    uint64_t g_constantDivisionDividends[std::size(CONSTANT_DIVISION_CASES)];

    uint64_t foldConstantDivision(const ConstantDivisionCase& divisionCase)
    {
        const uint64_t n = divisionCase.dividend;
        const uint64_t d = divisionCase.divisor;

        if (divisionCase.opBits == MicroOpBits::B64)
        {
            switch (divisionCase.op)
            {
                case MicroOp::DivideUnsigned:
                    return n / d;
                case MicroOp::ModuloUnsigned:
                    return n % d;
                case MicroOp::DivideSigned:
                    return static_cast<uint64_t>(static_cast<int64_t>(n) / static_cast<int64_t>(d));
                case MicroOp::ModuloSigned:
                    return static_cast<uint64_t>(static_cast<int64_t>(n) % static_cast<int64_t>(d));
                default:
                    SWC_UNREACHABLE();
            }
        }

        const auto n32 = static_cast<uint32_t>(n);
        const auto d32 = static_cast<uint32_t>(d);
        switch (divisionCase.op)
        {
            case MicroOp::DivideUnsigned:
                return n32 / d32;
            case MicroOp::ModuloUnsigned:
                return n32 % d32;
            case MicroOp::DivideSigned:
                return static_cast<uint32_t>(static_cast<int32_t>(n32) / static_cast<int32_t>(d32));
            case MicroOp::ModuloSigned:
                return static_cast<uint32_t>(static_cast<int32_t>(n32) % static_cast<int32_t>(d32));
            default:
                SWC_UNREACHABLE();
        }
    }

    uint64_t constantDivisionChecksum()
    {
        uint64_t checksum = 0;
        for (const auto& divisionCase : CONSTANT_DIVISION_CASES)
            checksum = checksum * 31 + foldConstantDivision(divisionCase);
        return checksum;
    }

    void buildConstantDivisionChecksum(MicroBuilder& builder, const CallConv& callConv, bool optimize)
    {
        Runtime::BuildCfgBackend buildCfg{};
        buildCfg.optimize = optimize;
        builder.setBackendBuildCfg(buildCfg);

        constexpr MicroReg checksumReg = MicroReg::virtualIntReg(1);
        constexpr MicroReg valueReg    = MicroReg::virtualIntReg(2);
        constexpr MicroReg tableReg    = MicroReg::virtualIntReg(3);

        // The dividends are read from memory so constant folding cannot collapse the
        // divisions before the strength-reduction expansion runs.
        for (size_t i = 0; i < std::size(CONSTANT_DIVISION_CASES); ++i)
            g_constantDivisionDividends[i] = CONSTANT_DIVISION_CASES[i].dividend;

        builder.emitLoadRegImm(checksumReg, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.emitLoadRegPtrImm(tableReg, reinterpret_cast<uint64_t>(g_constantDivisionDividends));

        for (size_t i = 0; i < std::size(CONSTANT_DIVISION_CASES); ++i)
        {
            const ConstantDivisionCase& divisionCase = CONSTANT_DIVISION_CASES[i];
            const uint32_t              bits         = getNumBits(divisionCase.opBits);

            builder.emitLoadRegMem(valueReg, tableReg, i * 8, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(valueReg, ApInt(divisionCase.divisor, bits), divisionCase.op, divisionCase.opBits);
            if (divisionCase.opBits == MicroOpBits::B32)
                builder.emitLoadZeroExtendRegReg(valueReg, valueReg, MicroOpBits::B64, MicroOpBits::B32);

            builder.emitOpBinaryRegImm(checksumReg, ApInt(31, 64), MicroOp::MultiplySigned, MicroOpBits::B64);
            builder.emitOpBinaryRegReg(checksumReg, valueReg, MicroOp::Add, MicroOpBits::B64);
        }

        builder.emitLoadRegReg(callConv.intReturn, checksumReg, MicroOpBits::B64);
        builder.emitRet();
    }

    void buildConstantDivisionChecksumOptimized(MicroBuilder& builder, const CallConv& callConv)
    {
        buildConstantDivisionChecksum(builder, callConv, true);
    }

    void buildConstantDivisionChecksumBaseline(MicroBuilder& builder, const CallConv& callConv)
    {
        buildConstantDivisionChecksum(builder, callConv, false);
    }

    void buildReturnOneAfterB32LoadAndZeroExtend(MicroBuilder& builder, const CallConv& callConv)
    {
        Runtime::BuildCfgBackend buildCfg{};
        buildCfg.optimize = true;
        builder.setBackendBuildCfg(buildCfg);

        constexpr MicroReg rdx = MicroReg::intReg(3);

        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(16, 64), MicroOp::Subtract, MicroOpBits::B64);
        builder.emitLoadMemImm(callConv.stackPointer, 0, ApInt(1, 64), MicroOpBits::B32);
        builder.emitLoadMemImm(callConv.stackPointer, 4, ApInt(0x12345678, 64), MicroOpBits::B32);
        builder.emitLoadRegMem(rdx, callConv.stackPointer, 0, MicroOpBits::B32);
        builder.emitLoadZeroExtendRegReg(callConv.intReturn, rdx, MicroOpBits::B64, MicroOpBits::B32);
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(16, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitRet();
    }
}

SWC_TEST_BEGIN(JIT_Return42)
{
    SWC_RESULT(runCase(ctx, &buildReturn42, 42));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_RegAllocAvoidsFutureConcreteClobber)
{
    SWC_RESULT(runCase(ctx, &buildReturnVirtualAcrossConcreteClobber, 3));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_128BitStackCopy)
{
    SWC_RESULT(runCase(ctx, &buildReturnZeroAfter128BitStackCopy, 0));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_PointerSpillRoundTrip)
{
    SWC_RESULT(runCase(ctx, &buildReturnOneAfterPointerSpillRoundTrip, 1));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_B32LoadAndZeroExtendKeepsUpperBitsClear)
{
    SWC_RESULT(runCase(ctx, &buildReturnOneAfterB32LoadAndZeroExtend, 1));
}
SWC_TEST_END()

// Hardware divides only: validates the C++ reference checksum itself.
SWC_TEST_BEGIN(JIT_ConstantDivisionBaseline)
{
    SWC_RESULT(runCase(ctx, &buildConstantDivisionChecksumBaseline, constantDivisionChecksum()));
}
SWC_TEST_END()

// Optimized pipeline: the same divisions go through the multiply-high expansion.
SWC_TEST_BEGIN(JIT_ConstantDivisionStrengthReduced)
{
    SWC_RESULT(runCase(ctx, &buildConstantDivisionChecksumOptimized, constantDivisionChecksum()));
}
SWC_TEST_END()

SWC_TEST_BEGIN(JIT_PersistentRegPreservedAcrossCall)
{
    const CallConv& callConv = CallConv::swag();

    MicroBuilder calleeBuilder(ctx);
    calleeBuilder.emitLoadRegImm(MicroReg::intReg(15), ApInt(0x1234, 64), MicroOpBits::B64);
    calleeBuilder.emitLoadRegImm(callConv.intReturn, ApInt(1, 64), MicroOpBits::B64);
    calleeBuilder.emitRet();

    MachineCode loweredCalleeCode;
    SWC_RESULT(loweredCalleeCode.emit(ctx, calleeBuilder));

    JITMemory calleeExecMemory;
    SWC_RESULT(JIT::emit(ctx, calleeExecMemory, loweredCalleeCode.bytes, loweredCalleeCode.codeRelocations, loweredCalleeCode.unwindInfo));
    using CalleeFnType  = uint64_t (*)();
    const auto calleeFn = reinterpret_cast<CalleeFnType>(calleeExecMemory.entryPoint());
    SWC_ASSERT(calleeFn != nullptr);
    SWC_ASSERT(calleeFn() == 1);

    MicroBuilder callerBuilder(ctx);
    callerBuilder.emitLoadRegImm(MicroReg::intReg(15), ApInt(7, 64), MicroOpBits::B64);
    callerBuilder.emitLoadRegPtrImm(MicroReg::intReg(10), reinterpret_cast<uint64_t>(calleeFn));
    callerBuilder.emitCallReg(MicroReg::intReg(10), CallConvKind::Swag);
    callerBuilder.emitOpBinaryRegImm(MicroReg::intReg(15), ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    callerBuilder.emitLoadRegReg(callConv.intReturn, MicroReg::intReg(15), MicroOpBits::B64);
    callerBuilder.emitRet();

    MachineCode loweredCallerCode;
    SWC_RESULT(loweredCallerCode.emit(ctx, callerBuilder));

    JITMemory callerExecMemory;
    SWC_RESULT(JIT::emit(ctx, callerExecMemory, loweredCallerCode.bytes, loweredCallerCode.codeRelocations, loweredCallerCode.unwindInfo));
    using CallerFnType  = uint64_t (*)();
    const auto callerFn = reinterpret_cast<CallerFnType>(callerExecMemory.entryPoint());
    SWC_ASSERT(callerFn != nullptr);
    SWC_ASSERT(callerFn() == 8);
}
SWC_TEST_END()

#endif
SWC_END_NAMESPACE();

#endif
