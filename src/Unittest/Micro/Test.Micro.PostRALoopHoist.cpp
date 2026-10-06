#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PostRALoopHoist.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPostRaLoopHoistPass(MicroBuilder& builder, uint64_t spillLo = 0, uint64_t spillHi = 0)
    {
        MicroPostRaLoopHoistPass pass;
        MicroPassManager         passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        passContext.spillAreaLo  = spillLo;
        passContext.spillAreaHi  = spillHi;
        return builder.runPasses(passManager, nullptr, passContext);
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

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;

    const uint32_t posLoad  = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label);
    if (posLoad > posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A prior read makes the folded operand safe to materialize before a loop.
// Calls that can write, body stores, a changing base, a live scratch register,
// and an absent ABI save each prevent the rewrite.
SWC_TEST_BEGIN(PostRALoopHoist_FoldedBitwiseOperandNeedsStableSavedRegister)
{
    constexpr MicroReg base    = MicroReg::intReg(1);
    constexpr MicroReg value   = MicroReg::intReg(12);
    constexpr MicroReg other   = MicroReg::intReg(13);
    constexpr MicroReg counter = MicroReg::intReg(14);
    constexpr MicroReg scratch = MicroReg::intReg(15);
    for (uint32_t mode = 0; mode < 9; ++mode)
    {
        SymbolFunction callee(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        if (mode != 2)
        {
            AttributeList attributes;
            attributes.addRtFlag(RtAttributeFlagsE::ReadOnly);
            callee.setAttributes(ctx, attributes);
        }
        MicroBuilder builder(ctx);
        const auto   top  = builder.createLabel();
        const auto   done = builder.createLabel();
        if (mode != 6)
            builder.emitPush(scratch);
        builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
        const MicroOp     bitwise = mode == 1 ? MicroOp::Or : MicroOp::And;
        const MicroOpBits bits    = mode == 8 ? MicroOpBits::B32 : MicroOpBits::B64;
        MicroInstrRef     entryReadRef;
        if (mode != 4)
        {
            builder.emitOpBinaryRegMem(value, base, 0x20, bitwise, bits);
            entryReadRef = builder.instructions().lastInstructionRef();
        }
        if (mode == 7)
            builder.emitOpBinaryRegReg(value, scratch, MicroOp::Xor, MicroOpBits::B64);
        builder.placeLabel(top);
        builder.emitCmpRegImm(counter, ApInt(3, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        if (mode == 0 || mode == 2)
            builder.emitCallLocal(&callee, CallConvKind::Swag);
        builder.emitOpBinaryRegMem(value, base, 0x20, bitwise, bits);
        const MicroInstrRef foldedRef = builder.instructions().lastInstructionRef();
        MicroInstrRef       secondFoldedRef;
        if (mode == 1)
        {
            builder.emitOpBinaryRegMem(value, base, 0x20, MicroOp::Xor, MicroOpBits::B64);
            secondFoldedRef = builder.instructions().lastInstructionRef();
        }
        if (mode == 3)
            builder.emitLoadMemReg(base, 0x20, other, MicroOpBits::B64);
        if (mode == 5)
            builder.emitLoadRegReg(base, other, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        builder.placeLabel(done);
        if (mode != 6)
            builder.emitPop(scratch);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopHoistPass(builder));
        const MicroInstr* folded   = builder.instructions().ptr(foldedRef);
        const bool        expected = mode == 0 || mode == 1 || mode == 8;
        if (!folded || (folded->op == MicroInstrOpcode::OpBinaryRegReg) != expected ||
            (folded->op == MicroInstrOpcode::OpBinaryRegMem) == expected)
            return Result::Error;
        if (expected && folded->ops(builder.operands())[1].reg != scratch)
            return Result::Error;
        if (expected && (!builder.instructions().ptr(entryReadRef) ||
                         builder.instructions().ptr(entryReadRef)->op != MicroInstrOpcode::OpBinaryRegReg))
            return Result::Error;
        if (mode == 1 && (!builder.instructions().ptr(secondFoldedRef) ||
                          builder.instructions().ptr(secondFoldedRef)->op != MicroInstrOpcode::OpBinaryRegReg))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// The register already holds the initial frame value and remains current on
// every exit. Only the final value needs to reach its frame home.
SWC_TEST_BEGIN(PostRALoopHoist_LoopStore_WritesBackAtExit)
{
    const CallConv& conv  = CallConv::get(CallConvKind::Swag);
    const MicroReg  sp    = conv.stackPointer;
    const MicroReg  value = conv.intTransientRegs[3];
    const MicroReg  init  = conv.intTransientRegs[4];
    MicroBuilder    builder(ctx);

    const MicroLabelRef top  = builder.createLabel();
    const MicroLabelRef done = builder.createLabel();
    builder.emitLoadRegImm(init, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(value, init, MicroOpBits::B64);
    builder.emitLoadMemReg(sp, 0x40, init, MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitCmpRegImm(value, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
    builder.emitOpBinaryRegImm(value, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(sp, 0x40, value, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
    builder.placeLabel(done);
    builder.emitLoadRegMem(init, sp, 0x40, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    uint32_t position   = 0;
    uint32_t labelCount = 0;
    uint32_t storeCount = 0;
    uint32_t exitStore  = std::numeric_limits<uint32_t>::max();
    uint32_t exitLoad   = std::numeric_limits<uint32_t>::max();
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op == MicroInstrOpcode::Label)
            ++labelCount;
        if (inst.op == MicroInstrOpcode::LoadMemReg)
        {
            ++storeCount;
            if (labelCount == 2)
                exitStore = position;
        }
        if (inst.op == MicroInstrOpcode::LoadRegMem && labelCount == 2)
            exitLoad = position;
        ++position;
    }

    if (storeCount != 2 || exitStore == std::numeric_limits<uint32_t>::max() || exitStore + 1 != exitLoad)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A zero-trip loop must keep the preheader's value. A later register rewrite
// must not replace the value that the loop stored on its last iteration.
SWC_TEST_BEGIN(PostRALoopHoist_LoopStore_UnsafeSourcesStayInLoop)
{
    for (const bool mismatchedInitial : {false, true})
    {
        const CallConv& conv  = CallConv::get(CallConvKind::Swag);
        const MicroReg  sp    = conv.stackPointer;
        const MicroReg  value = conv.intTransientRegs[3];
        const MicroReg  init  = conv.intTransientRegs[4];
        MicroBuilder    builder(ctx);

        const MicroLabelRef top  = builder.createLabel();
        const MicroLabelRef done = builder.createLabel();
        builder.emitLoadRegImm(init, ApInt(0, 64), MicroOpBits::B64);
        if (mismatchedInitial)
            builder.emitLoadRegImm(value, ApInt(10, 64), MicroOpBits::B64);
        else
            builder.emitLoadRegReg(value, init, MicroOpBits::B64);
        builder.emitLoadMemReg(sp, 0x40, init, MicroOpBits::B64);
        builder.placeLabel(top);
        builder.emitCmpRegImm(value, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        builder.emitOpBinaryRegImm(value, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(sp, 0x40, value, MicroOpBits::B64);
        if (!mismatchedInitial)
            builder.emitLoadRegImm(value, ApInt(20, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        builder.placeLabel(done);
        builder.emitLoadRegMem(init, sp, 0x40, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopHoistPass(builder));

        uint32_t labelCount   = 0;
        uint32_t storesInLoop = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::Label)
                ++labelCount;
            if (inst.op == MicroInstrOpcode::LoadMemReg && labelCount == 1)
                ++storesInLoop;
        }
        if (storesInLoop != 1)
            return Result::Error;
    }

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

    const uint32_t posLoad  = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label);
    if (posLoad < posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A store through a register the pass cannot resolve to a frame slot could alias
// anything, so nothing moves - provided a pointer into the frame exists at all.
// The function has to hand one out for that to be true: with a frame no address
// is ever taken of, the pass proves no program pointer can reach a slot and
// hoists regardless, which is the case the test after this one covers.
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
    builder.emitLoadAddressRegMem(other, sp, 0x80, MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitLoadRegMem(base, sp, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(cnt, base, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(other, 0, cnt, MicroOpBits::B64);
    builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    const uint32_t posLoad  = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label);
    if (posLoad < posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The same body over a frame whose address is never taken. No program pointer
// can reach a slot of it, so the opaque store cannot alias the reload however
// unresolvable its base is, and the load leaves the loop.
SWC_TEST_BEGIN(PostRALoopHoist_OpaqueStoreOverPrivateFrame_Hoists)
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

    const uint32_t posLoad  = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label);
    if (posLoad > posLabel)
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

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;

    const uint32_t posLoad  = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label);
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
    // No otherwise unused SIMD register can hold this invariant either.
    for (const MicroReg reg : conv.floatTransientRegs)
        builder.emitClearReg(reg, MicroOpBits::B128);
    builder.placeLabel(top);
    builder.emitOpBinaryRegReg(cnt, base, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegMem(base, sp, 0x40, MicroOpBits::B64);
    builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    const uint32_t posLoad  = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label);
    if (posLoad < posLabel)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The accumulator shape: the body loads a slot, computes, and stores it back on
// every iteration because the allocator gave the value a memory home. The load
// and the store must leave the loop, replaced by one seeding load before it and
// one write-back after it.
SWC_TEST_BEGIN(PostRALoopHoist_CarriedSlot_LeavesTheLoop)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    const MicroReg  sp   = conv.stackPointer;
    const MicroReg  acc  = conv.intTransientRegs[3];
    const MicroReg  cnt  = conv.intTransientRegs[4];
    MicroBuilder    builder(ctx);

    const MicroLabelRef top  = builder.createLabel();
    const MicroLabelRef done = builder.createLabel();
    builder.emitLoadRegImm(cnt, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(top);
    builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
    builder.emitLoadRegMem(acc, sp, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(acc, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(sp, 0x40, acc, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(cnt, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
    builder.placeLabel(done);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));

    // One load and one store remain, and both are outside the loop: the load
    // before the loop label, the write-back after the exit label.
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 1)
        return Result::Error;

    const uint32_t posLoad  = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem);
    const uint32_t posLabel = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label);
    const uint32_t posStore = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadMemReg);
    const uint32_t posRet   = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Ret);
    if (posLoad > posLabel)
        return Result::Error;
    if (posStore + 1 != posRet)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The same shape, except the register also carries something across the
// iteration outside the load/store window. Promoting it would lose that value.
SWC_TEST_BEGIN(PostRALoopHoist_CarriedRegisterReusedElsewhere_Blocks)
{
    for (const bool beforeLoad : {false, true})
    {
        const CallConv& conv = CallConv::get(CallConvKind::Swag);
        const MicroReg  sp   = conv.stackPointer;
        const MicroReg  acc  = conv.intTransientRegs[3];
        const MicroReg  cnt  = conv.intTransientRegs[4];
        MicroBuilder    builder(ctx);

        const MicroLabelRef top  = builder.createLabel();
        const MicroLabelRef done = builder.createLabel();
        builder.emitLoadRegImm(cnt, ApInt(0, 64), MicroOpBits::B64);
        builder.placeLabel(top);
        builder.emitCmpRegImm(cnt, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        // The scratch lifetime sits immediately outside either boundary.
        if (beforeLoad)
        {
            builder.emitLoadRegImm(acc, ApInt(1, 64), MicroOpBits::B64);
            builder.emitOpBinaryRegReg(cnt, acc, MicroOp::Add, MicroOpBits::B64);
        }
        builder.emitLoadRegMem(acc, sp, 0x40, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(acc, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(sp, 0x40, acc, MicroOpBits::B64);
        if (!beforeLoad)
        {
            builder.emitLoadRegImm(acc, ApInt(1, 64), MicroOpBits::B64);
            builder.emitOpBinaryRegReg(cnt, acc, MicroOp::Add, MicroOpBits::B64);
        }
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        builder.placeLabel(done);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopHoistPass(builder));

        // The load and the store stay where they were, inside the loop.
        const uint32_t posLoad  = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem);
        const uint32_t posLabel = Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label);
        if (posLoad < posLabel)
            return Result::Error;
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 1)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopHoist_SecondDefinitionOfDestinationBlocks)
{
    const CallConv&     conv    = CallConv::get(CallConvKind::Swag);
    const MicroReg      base    = conv.intTransientRegs[3];
    const MicroReg      counter = conv.intTransientRegs[4];
    MicroBuilder        builder(ctx);
    const MicroLabelRef top = builder.createLabel();
    builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
    // No otherwise unused SIMD register can hold this invariant either.
    for (const MicroReg reg : conv.floatTransientRegs)
        builder.emitClearReg(reg, MicroOpBits::B128);
    builder.placeLabel(top);
    builder.emitLoadRegMem(base, conv.stackPointer, 0x40, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(counter, base, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegImm(base, ApInt(1, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopHoistPass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    if (Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem) < Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopHoist_TransientFloatArgumentCopyStaysInLoop)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    // A call clobbers its transient float argument register, so every iteration needs the copy.
    for (const bool changesSource : {false, true})
    {
        MicroBuilder   builder(ctx);
        const MicroReg source  = conv.floatPersistentRegs[6];
        const MicroReg arg     = conv.floatArgRegs[0];
        const MicroReg counter = conv.intPersistentRegs[2];
        const auto     top     = builder.createLabel();
        builder.emitLoadRegMem(source, conv.stackPointer, 0x40, MicroOpBits::B64);
        builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
        builder.placeLabel(top);
        builder.emitLoadRegReg(arg, source, MicroOpBits::B64);
        const auto copy = builder.instructions().lastInstructionRef();
        builder.emitCallReg(conv.intReturn, CallConvKind::Swag, 0, 1);
        if (changesSource)
            builder.emitLoadRegMem(source, conv.stackPointer, 0x48, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
        builder.emitLoadRegMem(arg, conv.stackPointer, 0x50, MicroOpBits::B128);
        builder.emitRet();

        SWC_RESULT(runPostRaLoopHoistPass(builder));
        if (builder.instructions().ptr(copy) == nullptr)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// A reused GP destination does not prevent caching in an otherwise unused SIMD
// register. Calls, writes, narrow values, and register liveness still bar the move.
SWC_TEST_BEGIN(PostRALoopHoist_IntegerReloadUsesUnusedFloatRegister)
{
    const CallConv& conv    = CallConv::get(CallConvKind::Swag);
    const MicroReg  base    = conv.intTransientRegs[3];
    const MicroReg  counter = conv.intTransientRegs[4];
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        for (uint32_t mode = 0; mode < 7; ++mode)
        {
            MicroBuilder      builder(ctx);
            const auto        top      = builder.createLabel();
            const MicroOpBits loadBits = mode == 6 ? MicroOpBits::B16 : bits;
            builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
            builder.emitLoadRegImm(base, ApInt(7, 64), MicroOpBits::B64);
            if (mode == 2)
            {
                for (const MicroReg reg : conv.floatTransientRegs)
                    builder.emitClearReg(reg, MicroOpBits::B128);
            }
            builder.placeLabel(top);
            if (mode == 1)
                builder.emitOpBinaryRegReg(counter, base, MicroOp::Add, MicroOpBits::B64);
            builder.emitLoadRegMem(base, conv.stackPointer, 0x40, loadBits);
            builder.emitOpBinaryRegReg(counter, base, MicroOp::Add, MicroOpBits::B64);
            builder.emitLoadRegImm(base, ApInt(1, 64), MicroOpBits::B64);
            if (mode == 3)
                builder.emitLoadMemReg(conv.stackPointer, 0x40, counter, loadBits);
            builder.emitLoadRegMem(base, conv.stackPointer, 0x40, loadBits);
            builder.emitOpBinaryRegReg(counter, base, MicroOp::Add, MicroOpBits::B64);
            builder.emitLoadRegImm(base, ApInt(2, 64), MicroOpBits::B64);
            builder.emitCmpRegImm(counter, ApInt(100, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
            if (mode == 4)
                builder.emitCallReg(conv.intReturn, CallConvKind::Swag, 0);
            if (mode == 5)
                builder.emitClearReg(conv.floatTransientRegs[0], MicroOpBits::B128);
            builder.emitRet();
            SWC_RESULT(runPostRaLoopHoistPass(builder));
            const bool cached    = mode == 0 || mode == 1 || mode == 5;
            uint32_t   loads     = 0;
            uint32_t   transfers = 0;
            bool       inLoop    = false;
            MicroReg   cache;
            for (const auto& inst : builder.instructions().view())
            {
                const auto* ops = inst.ops(builder.operands());
                if (inst.op == MicroInstrOpcode::Label)
                    inLoop = true;
                if (inst.op == MicroInstrOpcode::LoadRegMem)
                {
                    ++loads;
                    if (cached)
                    {
                        if (inLoop || !ops[0].reg.isFloat() || ops[2].opBits != bits)
                            return Result::Error;
                        cache = ops[0].reg;
                        if (mode == 5 && cache == conv.floatTransientRegs[0])
                            return Result::Error;
                    }
                    else if (!inLoop || ops[0].reg != base)
                        return Result::Error;
                }
                if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg == base && ops[1].reg.isFloat())
                {
                    if (!cached || !inLoop || ops[1].reg != cache || ops[2].opBits != bits)
                        return Result::Error;
                    ++transfers;
                }
            }
            if (loads != (cached ? 1u : 2u) || transfers != (cached ? 2u : 0u))
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopHoist_CarriedSpillCacheAcrossArmsAndExits)
{
    for (uint32_t variant = 0; variant < 4; ++variant)
    {
        const CallConv& conv  = CallConv::get(CallConvKind::Swag);
        const MicroReg  sp    = conv.stackPointer;
        const MicroReg  value = conv.intTransientRegs[3];
        const MicroReg  count = conv.intTransientRegs[4];
        MicroBuilder    builder(ctx);
        const auto      top        = builder.createLabel();
        const auto      arm        = builder.createLabel();
        const auto      latch      = builder.createLabel();
        const auto      firstExit  = builder.createLabel();
        const auto      secondExit = builder.createLabel();
        if (variant == 2)
            builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, secondExit);
        builder.emitLoadRegImm(count, ApInt(0, 64), MicroOpBits::B64);
        if (variant == 3)
            builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, top);
        builder.placeLabel(top);
        builder.emitCmpRegImm(count, ApInt(20, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, firstExit);
        builder.emitLoadRegMem(value, sp, 0x80, MicroOpBits::B64);
        builder.emitCmpRegImm(value, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, arm);
        builder.emitOpBinaryRegImm(value, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(sp, 0x80, value, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, latch);
        builder.placeLabel(arm);
        builder.emitLoadRegMem(value, sp, 0x80, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(value, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadMemReg(sp, 0x80, value, MicroOpBits::B64);
        builder.placeLabel(latch);
        if (variant == 1)
            builder.emitLoadMemReg(sp, 0x84, count, MicroOpBits::B32);
        builder.emitLoadRegImm(value, ApInt(7, 64), MicroOpBits::B64);
        builder.emitOpBinaryRegReg(count, value, MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, secondExit);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        builder.placeLabel(firstExit);
        builder.emitRet();
        builder.placeLabel(secondExit);
        builder.emitRet();
        SWC_RESULT(runPostRaLoopHoistPass(builder, 0x80, 0x88));
        const uint32_t loads  = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem);
        const uint32_t copies = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg);
        if (variant == 0 || variant == 3)
        {
            SWC_ASSERT(loads == 1 && copies == 4);
            SWC_ASSERT(Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) == 2);
            SWC_ASSERT(Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::LoadRegMem) <
                       Backend::Unittest::firstOpcodePosition(builder, MicroInstrOpcode::Label));
        }
        else
            SWC_ASSERT(loads == 2 && copies == 0);
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopHoist_PrivateSpillCacheAcrossConditionalCall)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    for (uint32_t variant = 0; variant < 3; ++variant)
    {
        MicroBuilder   builder(ctx);
        const MicroReg value     = conv.intTransientRegs[3];
        const MicroReg counter   = conv.intPersistentRegs[2];
        const auto     top       = builder.createLabel();
        const auto     afterCall = builder.createLabel();
        builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
        builder.placeLabel(top);
        builder.emitLoadRegMem(value, conv.stackPointer, 0x80, MicroOpBits::B64);
        builder.emitOpBinaryRegReg(counter, value, MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
        if (variant != 1)
            builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B64, afterCall);
        builder.emitCallReg(conv.intReturn, CallConvKind::Swag, 0, 1);
        builder.placeLabel(afterCall);
        builder.emitLoadRegMem(value, conv.stackPointer, 0x80, MicroOpBits::B64);
        builder.emitOpBinaryRegReg(counter, value, MicroOp::Add, MicroOpBits::B64);
        if (variant == 2)
            builder.emitLoadMemReg(conv.stackPointer, 0x80, counter, MicroOpBits::B64);
        builder.emitLoadRegMem(value, conv.stackPointer, 0x80, MicroOpBits::B64);
        builder.emitOpBinaryRegReg(counter, value, MicroOp::Add, MicroOpBits::B64);
        builder.emitLoadRegImm(value, ApInt(0, 64), MicroOpBits::B64);
        builder.emitCmpRegImm(counter, ApInt(100, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, top);
        builder.emitRet();
        SWC_RESULT(runPostRaLoopHoistPass(builder, 0x80, 0x88));
        const uint32_t copies = Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg);
        SWC_ASSERT(copies == (variant == 0 ? 3u : variant == 2 ? 4u
                                                               : 0u));
        if (variant != 1)
        {
            for (const MicroInstr& inst : builder.instructions().view())
                if (inst.op == MicroInstrOpcode::LoadRegMem)
                    SWC_ASSERT(inst.ops(builder.operands())[0].reg == conv.floatTransientRegs[1]);
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
