#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
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

    Result runPeepholePass(MicroBuilder& builder)
    {
        CallConv::setup();

        MicroPeepholePass peepholePass;
        MicroPassManager  passes;
        passes.add(peepholePass);

        MicroPassContext passCtx;
        passCtx.callConvKind = CallConvKind::Host;
        return builder.runPasses(passes, nullptr, passCtx);
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

    uint32_t countInstruction(const MicroBuilder& builder, MicroInstrOpcode opcode)
    {
        uint32_t count = 0;
        for (const auto& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                count++;
        }

        return count;
    }

    uint32_t countStackAccess(const MicroBuilder& builder, MicroInstrOpcode opcode, MicroReg stackBaseReg, uint64_t offset)
    {
        uint32_t                   count    = 0;
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != opcode)
                continue;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;

            uint8_t baseIndex   = 0;
            uint8_t offsetIndex = 0;
            if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, inst))
                continue;

            if (ops[baseIndex].reg == stackBaseReg && ops[offsetIndex].valueU64 == offset)
                ++count;
        }

        return count;
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

    SWC_RESULT_VERIFY(runPeepholePass(builder));

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

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (instructionCount(builder) != 8)
        return Result::Error;

    if (hasInstruction(builder, MicroInstrOpcode::Nop))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_RemovesRedundantStackSaveRestoreAroundImmediateShift)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg rcx = MicroReg::intReg(1);
    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg r8  = MicroReg::intReg(8);

    builder.emitLoadMemReg(rsp, 32, rcx, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r8, ApInt(1, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitLoadRegMem(rcx, rsp, 32, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (instructionCount(builder) != 2)
        return Result::Error;
    if (hasInstruction(builder, MicroInstrOpcode::LoadMemReg))
        return Result::Error;
    if (hasInstruction(builder, MicroInstrOpcode::LoadRegMem))
        return Result::Error;
    if (!hasInstruction(builder, MicroInstrOpcode::OpBinaryRegImm))
        return Result::Error;
    if (!hasInstruction(builder, MicroInstrOpcode::Ret))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_KeepsStackSaveRestoreWhenShiftWritesSavedReg)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg rcx = MicroReg::intReg(1);
    constexpr MicroReg rsp = MicroReg::intReg(4);

    builder.emitLoadMemReg(rsp, 32, rcx, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rcx, ApInt(1, 64), MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitLoadRegMem(rcx, rsp, 32, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (instructionCount(builder) != 4)
        return Result::Error;
    if (!hasInstruction(builder, MicroInstrOpcode::LoadMemReg))
        return Result::Error;
    if (!hasInstruction(builder, MicroInstrOpcode::LoadRegMem))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_RemovesRedundantStackLoadStorePair)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rcx = MicroReg::intReg(1);

    builder.emitLoadRegMem(rax, rsp, 0x38, MicroOpBits::B64);
    builder.emitLoadRegMem(rcx, rsp, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rcx, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0x40, rcx, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0x38, rax, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (countStackAccess(builder, MicroInstrOpcode::LoadRegMem, rsp, 0x38) != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_KeepsStackLoadStorePairWhenSlotWasWritten)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rcx = MicroReg::intReg(1);

    builder.emitLoadRegMem(rax, rsp, 0x38, MicroOpBits::B64);
    builder.emitLoadMemImm(rsp, 0x38, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(rcx, rsp, 0x38, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0x38, rax, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (countStackAccess(builder, MicroInstrOpcode::LoadRegMem, rsp, 0x38) != 2)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_FoldsLoadOpStoreIntoMemImm)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);

    builder.emitLoadRegMem(r8, rsp, 0x20, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r8, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0x20, r8, MicroOpBits::B64);
    builder.emitLoadRegMem(r9, rsp, 0x20, MicroOpBits::B64);
    builder.emitCmpRegImm(r9, ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (!hasInstruction(builder, MicroInstrOpcode::OpBinaryMemImm))
        return Result::Error;
    if (hasInstruction(builder, MicroInstrOpcode::OpBinaryRegImm))
        return Result::Error;
    if (countStackAccess(builder, MicroInstrOpcode::LoadMemReg, rsp, 0x20) != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_KeepsLoadOpStoreWhenResultRegIsUsed)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);

    builder.emitLoadRegMem(r8, rsp, 0x20, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r8, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0x20, r8, MicroOpBits::B64);
    builder.emitCmpRegImm(r8, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(r9, rsp, 0x20, MicroOpBits::B64);
    builder.emitCmpRegImm(r9, ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (hasInstruction(builder, MicroInstrOpcode::OpBinaryMemImm))
        return Result::Error;
    if (!hasInstruction(builder, MicroInstrOpcode::OpBinaryRegImm))
        return Result::Error;
    if (countStackAccess(builder, MicroInstrOpcode::LoadMemReg, rsp, 0x20) != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_FoldsInterleavedLoadOpStoreIntoMemImm)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rcx = MicroReg::intReg(1);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);
    constexpr MicroReg r10 = MicroReg::intReg(10);

    builder.emitLoadRegMem(rcx, rsp, 0x40, MicroOpBits::B64);
    builder.emitLoadRegMem(r8, rsp, 0x48, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(r8, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(rcx, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0x40, rcx, MicroOpBits::B64);
    builder.emitLoadMemReg(rsp, 0x48, r8, MicroOpBits::B64);
    builder.emitLoadRegMem(r9, rsp, 0x40, MicroOpBits::B64);
    builder.emitCmpRegImm(r9, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(r10, rsp, 0x48, MicroOpBits::B64);
    builder.emitCmpRegImm(r10, ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (countInstruction(builder, MicroInstrOpcode::OpBinaryMemImm) != 2)
        return Result::Error;
    if (countStackAccess(builder, MicroInstrOpcode::LoadMemReg, rsp, 0x40) != 0)
        return Result::Error;
    if (countStackAccess(builder, MicroInstrOpcode::LoadMemReg, rsp, 0x48) != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_FoldsInterleavedLoadCmpIntoCmpMemImmAcrossJump)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg  rsp       = MicroReg::intReg(4);
    constexpr MicroReg  rcx       = MicroReg::intReg(1);
    constexpr MicroReg  rax       = MicroReg::intReg(0);
    constexpr MicroReg  r8        = MicroReg::intReg(8);
    const MicroLabelRef doneLabel = builder.createLabel();

    builder.emitLoadRegMem(rcx, rsp, 0x38, MicroOpBits::B64);
    builder.emitLoadRegMem(rax, rsp, 0x40, MicroOpBits::B64);
    builder.emitLoadRegMem(r8, rsp, 0x48, MicroOpBits::B64);
    builder.emitCmpRegImm(rax, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
    builder.emitLoadRegReg(rax, r8, MicroOpBits::B64);
    builder.placeLabel(doneLabel);
    builder.emitLoadRegImm(rax, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    if (!hasInstruction(builder, MicroInstrOpcode::CmpMemImm))
        return Result::Error;
    if (countStackAccess(builder, MicroInstrOpcode::LoadRegMem, rsp, 0x40) != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_FoldsCopySwapAddIntoAccumulator)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg rsp = MicroReg::intReg(4);
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rcx = MicroReg::intReg(1);
    constexpr MicroReg r8  = MicroReg::intReg(8);

    builder.emitLoadRegReg(rax, r8, MicroOpBits::B32);
    builder.emitLoadRegReg(r8, rcx, MicroOpBits::B32);
    builder.emitOpBinaryRegReg(r8, rax, MicroOp::Add, MicroOpBits::B32);
    builder.emitOpBinaryMemReg(rsp, 0x30, r8, MicroOp::Add, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    bool                       hasRewrittenAdd = false;
    const MicroOperandStorage& operands        = builder.operands();
    for (const auto& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(operands);
        if (!ops)
            continue;

        if (inst.op == MicroInstrOpcode::OpBinaryRegReg &&
            ops[0].reg == rcx &&
            ops[1].reg == r8 &&
            ops[2].opBits == MicroOpBits::B32 &&
            ops[3].microOp == MicroOp::Add)
        {
            hasRewrittenAdd = true;
        }
    }

    if (!hasRewrittenAdd)
        return Result::Error;
    if (countInstruction(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Peephole_KeepsFramePointerCopyWhenSourceIsStackPointer)
{
    MicroBuilder builder(ctx);
    setPeepholeOptimizeLevel(builder);

    constexpr MicroReg  rbp       = MicroReg::intReg(5);
    constexpr MicroReg  rsp       = MicroReg::intReg(4);
    constexpr MicroReg  rdx       = MicroReg::intReg(2);
    constexpr MicroReg  rcx       = MicroReg::intReg(1);
    constexpr MicroReg  rax       = MicroReg::intReg(0);
    constexpr MicroReg  r13       = MicroReg::intReg(13);
    constexpr MicroReg  r14       = MicroReg::intReg(14);
    constexpr MicroReg  r15       = MicroReg::intReg(15);
    const MicroLabelRef loopLabel = builder.createLabel();

    builder.emitPush(rbp);
    builder.emitLoadRegReg(rbp, rsp, MicroOpBits::B64);
    builder.emitPush(r15);
    builder.emitPush(r14);
    builder.emitPush(r13);
    builder.emitLoadRegMem(rdx, rbp, 0x30, MicroOpBits::B64);
    builder.emitLoadRegMem(rcx, rbp, 0x38, MicroOpBits::B64);
    builder.emitLoadRegMem(rax, rbp, 0x40, MicroOpBits::B64);
    builder.placeLabel(loopLabel);
    builder.emitRet();

    SWC_RESULT_VERIFY(runPeepholePass(builder));

    bool                       hasFrameCopy          = false;
    bool                       hasLoadFromFrameBase0 = false;
    bool                       hasLoadFromFrameBase1 = false;
    bool                       hasLoadFromFrameBase2 = false;
    bool                       hasLoadFromStackBase  = false;
    const MicroOperandStorage& operands              = builder.operands();
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(operands);
        if (!ops)
            continue;

        if (inst.op == MicroInstrOpcode::LoadRegReg &&
            ops[0].reg == rbp &&
            ops[1].reg == rsp &&
            ops[2].opBits == MicroOpBits::B64)
        {
            hasFrameCopy = true;
        }

        if (inst.op == MicroInstrOpcode::LoadRegMem &&
            ops[0].reg == rdx &&
            ops[3].valueU64 == 0x30 &&
            ops[2].opBits == MicroOpBits::B64)
        {
            if (ops[1].reg == rbp)
                hasLoadFromFrameBase0 = true;
            if (ops[1].reg == rsp)
                hasLoadFromStackBase = true;
        }

        if (inst.op == MicroInstrOpcode::LoadRegMem &&
            ops[0].reg == rcx &&
            ops[3].valueU64 == 0x38 &&
            ops[2].opBits == MicroOpBits::B64)
        {
            if (ops[1].reg == rbp)
                hasLoadFromFrameBase1 = true;
            if (ops[1].reg == rsp)
                hasLoadFromStackBase = true;
        }

        if (inst.op == MicroInstrOpcode::LoadRegMem &&
            ops[0].reg == rax &&
            ops[3].valueU64 == 0x40 &&
            ops[2].opBits == MicroOpBits::B64)
        {
            if (ops[1].reg == rbp)
                hasLoadFromFrameBase2 = true;
            if (ops[1].reg == rsp)
                hasLoadFromStackBase = true;
        }
    }

    if (!hasFrameCopy)
        return Result::Error;
    if (!hasLoadFromFrameBase0)
        return Result::Error;
    if (!hasLoadFromFrameBase1)
        return Result::Error;
    if (!hasLoadFromFrameBase2)
        return Result::Error;
    if (hasLoadFromStackBase)
        return Result::Error;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();
