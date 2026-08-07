#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PostRALoopHoist.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPostRaLoopHoistPass(MicroBuilder& builder)
    {
        MicroPostRaLoopHoistPass pass;
        MicroPassManager         passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t countOpcode(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                ++count;
        }

        return count;
    }

    // First linear position of an opcode, or UINT32_MAX.
    uint32_t firstPosition(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t position = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                return position;
            ++position;
        }

        return std::numeric_limits<uint32_t>::max();
    }
}

// The shape the register allocator leaves behind: a base pointer reloaded from
// its stack home on every iteration of a loop that never writes the slot. The
// load must end up before the loop label and stay there alone.
SWC_TEST_BEGIN(PostRALoopHoist_InvariantReload_MovesToPreheader)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    const MicroReg  sp   = conv.stackPointer;
    const MicroReg  base = conv.intTransientRegs[3];
    const MicroReg  cnt  = conv.intTransientRegs[4];
    MicroBuilder    builder(ctx);

    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(cnt, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitLoadRegMem(base, sp, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(cnt, base, MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;

    const uint32_t posLoad  = firstPosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = firstPosition(builder, MicroInstrOpcode::Label);
    if (posLoad > posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A write to the same slot inside the body makes the reload variant: it reads
// something different on the next iteration and must not move.
SWC_TEST_BEGIN(PostRALoopHoist_SlotWrittenInBody_Blocks)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    const MicroReg  sp   = conv.stackPointer;
    const MicroReg  base = conv.intTransientRegs[3];
    const MicroReg  cnt  = conv.intTransientRegs[4];
    MicroBuilder    builder(ctx);

    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(cnt, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitLoadRegMem(base, sp, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(cnt, base, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(sp, 0x40, cnt, MicroOpBits::B64);
    builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    const uint32_t posLoad  = firstPosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = firstPosition(builder, MicroInstrOpcode::Label);
    if (posLoad < posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A store through a register the pass cannot resolve to a frame slot could
// alias anything, so nothing moves.
SWC_TEST_BEGIN(PostRALoopHoist_OpaqueStoreInBody_Blocks)
{
    const CallConv& conv  = CallConv::get(CallConvKind::Swag);
    const MicroReg  sp    = conv.stackPointer;
    const MicroReg  base  = conv.intTransientRegs[3];
    const MicroReg  cnt   = conv.intTransientRegs[4];
    const MicroReg  other = conv.intTransientRegs[5];
    MicroBuilder    builder(ctx);

    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(cnt, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(other, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitLoadRegMem(base, sp, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(cnt, base, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(other, 0, cnt, MicroOpBits::B64);
    builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    const uint32_t posLoad  = firstPosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = firstPosition(builder, MicroInstrOpcode::Label);
    if (posLoad < posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A second reload of the same slot into a different register reads a value the
// hoisted register already holds: it becomes a register copy, not a memory
// access.
SWC_TEST_BEGIN(PostRALoopHoist_SecondReload_BecomesCopy)
{
    const CallConv& conv  = CallConv::get(CallConvKind::Swag);
    const MicroReg  sp    = conv.stackPointer;
    const MicroReg  base  = conv.intTransientRegs[3];
    const MicroReg  cnt   = conv.intTransientRegs[4];
    const MicroReg  other = conv.intTransientRegs[5];
    MicroBuilder    builder(ctx);

    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(cnt, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitLoadRegMem(base, sp, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(cnt, base, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegMem(other, sp, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(cnt, other, MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;

    const uint32_t posLoad  = firstPosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = firstPosition(builder, MicroInstrOpcode::Label);
    if (posLoad > posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The destination carries a value into the loop, so overwriting it in the
// preheader would destroy it.
SWC_TEST_BEGIN(PostRALoopHoist_DestinationLiveAtPreheader_Blocks)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    const MicroReg  sp   = conv.stackPointer;
    const MicroReg  base = conv.intTransientRegs[3];
    const MicroReg  cnt  = conv.intTransientRegs[4];
    MicroBuilder    builder(ctx);

    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(cnt, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(base, ApInt(7, 64), MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitOpBinaryRegReg(cnt, base, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegMem(base, sp, 0x40, MicroOpBits::B64);
    builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    const uint32_t posLoad  = firstPosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = firstPosition(builder, MicroInstrOpcode::Label);
    if (posLoad < posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
