#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"
#include "Support/Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

#if SWC_HAS_UNITTEST

namespace
{
    void setPeepholeOptimizeLevel(MicroBuilder& builder)
    {
        Runtime::BuildCfgBackend backendCfg{};
        backendCfg.optimize = true;
        builder.setBackendBuildCfg(backendCfg);
    }

    void runPeepholePass(MicroBuilder& builder)
    {
        MicroPeepholePass peepholePass;
        MicroPassManager  passes;
        passes.add(peepholePass);

        MicroPassContext passCtx;
        builder.runPasses(passes, nullptr, passCtx);
    }

    uint32_t instructionCount(const MicroBuilder& builder)
    {
        uint32_t count = 0;
        for (const auto& inst : builder.instructions().view())
        {
            SWC_UNUSED(inst);
            count++;
        }

        return count;
    }

    bool hasInstruction(const MicroBuilder& builder, MicroInstrOpcode opcode)
    {
        for (const auto& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                return true;
        }

        return false;
    }
}

SWC_TEST_BEGIN(Peephole_EliminatesNoOps)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);
    constexpr MicroReg r10 = MicroReg::intReg(10);
    constexpr MicroReg r11 = MicroReg::intReg(11);
    constexpr MicroReg r12 = MicroReg::intReg(12);

    builder.emitNop();
    builder.emitLoadRegReg(r8, r8, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(r9, r9, 0, MicroOpBits::B64);
    builder.emitLoadCondRegReg(r10, r10, MicroCond::Greater, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(r11, r11, MicroOp::Exchange, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r12, ApInt(0, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r12, ApInt(0, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r12, ApInt(0, 64), MicroOp::Or, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r12, ApInt(0, 64), MicroOp::Xor, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r12, ApInt(0xFFFFFFFFFFFFFFFF, 64), MicroOp::And, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r12, ApInt(0, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r12, ApInt(0, 64), MicroOp::ShiftRight, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r12, ApInt(0, 64), MicroOp::ShiftArithmeticRight, MicroOpBits::B64);
    builder.emitRet();

    runPeepholePass(builder);

    if (instructionCount(builder) != 1)
        return Result::Error;

    if (!hasInstruction(builder, MicroInstrOpcode::Ret))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_PreservesNonNoOps)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);
    constexpr MicroReg r10 = MicroReg::intReg(10);
    constexpr MicroReg r11 = MicroReg::intReg(11);
    constexpr MicroReg r12 = MicroReg::intReg(12);
    constexpr MicroReg r13 = MicroReg::intReg(13);
    constexpr MicroReg r14 = MicroReg::intReg(14);

    builder.emitNop();
    builder.emitLoadRegReg(r8, r9, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(r9, r9, 1, MicroOpBits::B64);
    builder.emitLoadCondRegReg(r10, r11, MicroCond::Greater, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(r12, r8, MicroOp::Exchange, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r14, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r14, ApInt(1, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r14, ApInt(0x7F, 64), MicroOp::And, MicroOpBits::B64);
    builder.emitRet();

    runPeepholePass(builder);

    if (instructionCount(builder) != 8)
        return Result::Error;

    if (hasInstruction(builder, MicroInstrOpcode::Nop))
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();





