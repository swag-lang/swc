#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.Legalize.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPostRaPeepholePass(MicroBuilder& builder, Encoder* encoder = nullptr)
    {
        MicroPostRaPeepholePass pass;
        MicroPassManager        passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, encoder, passContext);
    }

    Result runLegalizePass(MicroBuilder& builder, Encoder& encoder)
    {
        MicroLegalizePass pass;
        MicroPassManager  passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, &encoder, passContext);
    }

    bool hasLoadRegReg(const MicroBuilder& builder, MicroReg dst, MicroReg src)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg)
                continue;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;

            if (ops[0].reg == dst && ops[1].reg == src)
                return true;
        }

        return false;
    }

    bool hasBinaryRegRegDst(const MicroBuilder& builder, MicroReg dst, MicroOp op, MicroOpBits bits)
    {
        const MicroOperandStorage& operands = builder.operands();
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegReg)
                continue;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;

            if (ops[0].reg == dst && ops[2].opBits == bits && ops[3].microOp == op)
                return true;
        }

        return false;
    }
}

SWC_TEST_BEGIN(PostRAPeephole_Nop_Erased)
{
    MicroBuilder builder(ctx);
    builder.emitNop();
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::Nop) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DoesNotForwardFromStoreClaimedByImmediateFold)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rbx  = MicroReg::intReg(3);
    constexpr MicroReg r9   = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(rbx, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadMemReg(base, 24, rbx, MicroOpBits::B64);
    builder.emitLoadRegMem(r9, base, 24, MicroOpBits::B64);
    builder.emitLoadRegImm(rbx, ApInt(9, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemImm) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    if (hasLoadRegReg(builder, r9, rbx))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_CopyForward_DoesNotCrossClaimedStoreReload)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg rcx   = MicroReg::intReg(2);
    constexpr MicroReg r14   = MicroReg::intReg(14);
    constexpr MicroReg r15   = MicroReg::intReg(15);

    MicroBuilder builder(ctx);
    builder.emitLoadMemReg(stack, 24, r14, MicroOpBits::B64);
    builder.emitLoadRegReg(rax, r15, MicroOpBits::B64);
    builder.emitLoadRegMem(rcx, stack, 24, MicroOpBits::B64);
    builder.emitLoadRegReg(r14, rax, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (!hasLoadRegReg(builder, rcx, r14))
        return Result::Error;
    if (!hasLoadRegReg(builder, r14, rax))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ErasesStoreOverwrittenBeforeMemoryAccess)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg r8   = MicroReg::intReg(8);
    constexpr MicroReg r9   = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitLoadMemReg(base, 16, r8, MicroOpBits::B16);
    builder.emitOpBinaryRegImm(r8, ApInt(1, 16), MicroOp::Add, MicroOpBits::B16);
    builder.emitLoadMemReg(base, 16, r9, MicroOpBits::B16);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DoesNotEraseOverwrittenNonFrameStore)
{
    constexpr MicroReg base = MicroReg::intReg(12);
    constexpr MicroReg r8   = MicroReg::intReg(8);
    constexpr MicroReg r9   = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitLoadMemReg(base, 16, r8, MicroOpBits::B16);
    builder.emitOpBinaryRegImm(r8, ApInt(1, 16), MicroOp::Add, MicroOpBits::B16);
    builder.emitLoadMemReg(base, 16, r9, MicroOpBits::B16);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadMemReg) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ErasesOwnStoreReloadOnConditionalFallthrough)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg r8   = MicroReg::intReg(8);

    MicroBuilder        builder(ctx);
    const MicroLabelRef doneLabel = builder.createLabel();
    builder.emitLoadMemReg(base, 24, r8, MicroOpBits::B16);
    builder.emitCmpRegImm(r8, ApInt(0, 16), MicroOpBits::B16);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, doneLabel);
    builder.emitLoadRegMem(r8, base, 24, MicroOpBits::B16);
    builder.placeLabel(doneLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ForwardsStoredValueToReload)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg r8   = MicroReg::intReg(8);
    constexpr MicroReg r9   = MicroReg::intReg(9);

    MicroBuilder builder(ctx);
    builder.emitLoadMemReg(base, 24, r8, MicroOpBits::B16);
    builder.emitCmpRegImm(r8, ApInt(0, 16), MicroOpBits::B16);
    builder.emitLoadRegMem(r9, base, 24, MicroOpBits::B16);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (!hasLoadRegReg(builder, r9, r8))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_CopyForward_StopsAtEncoderImplicitDef)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg rdx = MicroReg::intReg(3);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);
    constexpr MicroReg r12 = MicroReg::intReg(12);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r9, r12, 0, MicroOpBits::B64);
    builder.emitLoadRegImm(rax, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(r8, ApInt(11, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::MultiplyUnsigned, MicroOpBits::B64);
    builder.emitLoadRegReg(rdx, r9, MicroOpBits::B64);
    builder.emitLoadRegMem(r9, r12, 8, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (!hasLoadRegReg(builder, rdx, r9))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_DoesNotPreserveDeadShiftRegisterAcrossJump)
{
    constexpr MicroReg rcx = MicroReg::intReg(2);
    constexpr MicroReg r8  = MicroReg::intReg(8);
    constexpr MicroReg r9  = MicroReg::intReg(9);

    MicroBuilder        builder(ctx);
    const MicroLabelRef doneLabel = builder.createLabel();
    builder.emitLoadRegImm(rcx, ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(r8, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(r9, ApInt(3, 64), MicroOpBits::B64);
    builder.emitOpBinaryRegReg(r8, r9, MicroOp::ShiftLeft, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, doneLabel);
    builder.placeLabel(doneLabel);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;
    if (!hasLoadRegReg(builder, rcx, r9))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Legalize_RewritesB8SignedMultiplyRegMemToRax)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg r10 = MicroReg::intReg(10);
    constexpr MicroReg r14 = MicroReg::intReg(14);

    MicroBuilder builder(ctx);
    builder.emitOpBinaryRegMem(r14, r10, 0, MicroOp::MultiplySigned, MicroOpBits::B8);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 0)
        return Result::Error;
    if (!hasBinaryRegRegDst(builder, rax, MicroOp::MultiplySigned, MicroOpBits::B8))
        return Result::Error;
    if (!hasLoadRegReg(builder, r14, rax))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A memory-destination operation on virtual registers reaches the encoder as
// it is: legalization used to read a virtual register as "not an integer" and
// rewrite every such form back into a load, a register operation and a store.
SWC_TEST_BEGIN(Legalize_KeepsMemoryDestinationAdd)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg value = MicroReg::virtualIntReg(2);

    MicroBuilder builder(ctx);
    builder.emitOpBinaryMemReg(base, 8, value, MicroOp::Add, MicroOpBits::B32);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The atomic exchange in particular: its register rewrite is a plain
// read-modify-write, so it must stay `xchg [mem], reg`.
SWC_TEST_BEGIN(Legalize_KeepsMemoryExchange)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg value = MicroReg::virtualIntReg(2);

    MicroBuilder builder(ctx);
    builder.emitOpBinaryMemReg(base, 0, value, MicroOp::Exchange, MicroOpBits::B32);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runLegalizePass(builder, encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryMemReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DoesNotForwardB8SignedMultiplyImmediate)
{
    constexpr MicroReg rax = MicroReg::intReg(0);
    constexpr MicroReg r8  = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(r8, ApInt(2, 64), MicroOpBits::B8);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::MultiplySigned, MicroOpBits::B8);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// An integer reload consumed once by an addition folds into the addition's
// memory operand, the way float reloads already do.
SWC_TEST_BEGIN(PostRAPeephole_FoldsIntegerReloadIntoBinary)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg r8    = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r8, stack, 16, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The reloaded register is read again after the consumer: the load stays.
SWC_TEST_BEGIN(PostRAPeephole_KeepsIntegerReloadReadAfterConsumer)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg r8    = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r8, stack, 16, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(stack, 24, r8, MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A reload compared on the left folds into `cmp [mem], reg`.
SWC_TEST_BEGIN(PostRAPeephole_FoldsIntegerReloadIntoCompare)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg rcx   = MicroReg::intReg(2);
    constexpr MicroReg r8    = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r8, stack, 16, MicroOpBits::B32);
    builder.emitCmpRegReg(r8, rax, MicroOpBits::B32);
    builder.emitSetCondReg(rcx, MicroCond::Below);
    builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpMemReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The byte multiply reads memory through rax alone; the fold would only hand
// the encoder a legalization nothing runs any more.
SWC_TEST_BEGIN(PostRAPeephole_KeepsByteMultiplyReload)
{
    const MicroReg     stack = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg rax   = MicroReg::intReg(0);
    constexpr MicroReg r8    = MicroReg::intReg(8);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(r8, stack, 16, MicroOpBits::B8);
    builder.emitOpBinaryRegReg(rax, r8, MicroOp::MultiplySigned, MicroOpBits::B8);
    builder.emitLoadRegImm(r8, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();

    X64Encoder encoder(ctx);
    SWC_RESULT(runPostRaPeepholePass(builder, &encoder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_SelfCopy_B64_Erased)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    builder.emitLoadRegReg(conv.intReturn, conv.intReturn, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_SelfCopy_IntB32_Preserved)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    builder.emitLoadRegReg(conv.intReturn, conv.intReturn, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_FallthroughJumpSkipsTrivialGap)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef nextLabel = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, nextLabel);
    builder.emitNop();
    builder.emitLoadRegReg(conv.intReturn, conv.intReturn, MicroOpBits::B64);
    builder.placeLabel(nextLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::Nop) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DeadCompareBeforeRet_Erased)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    builder.emitCmpRegReg(conv.intRegs[0], conv.intRegs[1], MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_DeadCompareAfterRedundantJump_Erased)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef nextLabel = builder.createLabel();

    builder.emitCmpRegReg(conv.intRegs[0], conv.intRegs[1], MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, nextLabel);
    builder.placeLabel(nextLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_LiveCompareForBranch_Preserved)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef takenLabel = builder.createLabel();

    builder.emitCmpRegReg(conv.intRegs[0], conv.intRegs[1], MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, takenLabel);
    builder.emitRet();
    builder.placeLabel(takenLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_LoadCondRegRegKeepsCopyBecauseDestinationIsUseDef)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    builder.emitLoadRegImm(conv.intRegs[0], ApInt(1, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(conv.intRegs[2], ApInt(2, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[1], ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadCondRegReg(conv.intRegs[0], conv.intRegs[1], MicroCond::AboveOrEqual, MicroOpBits::B64);
    builder.emitLoadRegReg(conv.intRegs[2], conv.intRegs[0], MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[2], ApInt(0, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_FlagReuse_SubThenCompareZero_CompareErased)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef takenLabel = builder.createLabel();

    builder.emitOpBinaryRegImm(conv.intRegs[0], ApInt(5, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, takenLabel);
    builder.emitRet();
    builder.placeLabel(takenLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    // The sub already set ZF; the redundant compare against zero is gone, but
    // the branch that consumes the flags stays.
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_FlagReuse_UnsafeCondition_ComparePreserved)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef takenLabel = builder.createLabel();

    builder.emitOpBinaryRegImm(conv.intRegs[0], ApInt(5, 64), MicroOp::Subtract, MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    // 'Below' depends on CF, which `cmp r,0` clears but `sub` may set: not reusable.
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, takenLabel);
    builder.emitRet();
    builder.placeLabel(takenLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_FlagReuse_NonFlagProducer_ComparePreserved)
{
    const CallConv&     conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder        builder(ctx);
    const MicroLabelRef takenLabel = builder.createLabel();

    // A plain copy does not set CPU flags, so the compare is load-bearing.
    builder.emitLoadRegReg(conv.intRegs[0], conv.intRegs[1], MicroOpBits::B64);
    builder.emitCmpRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, takenLabel);
    builder.emitRet();
    builder.placeLabel(takenLabel);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ZeroToClear_LiveFlagsDead_Converted)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    // The zero is materialized then used as a memory base (not a foldable
    // immediate slot), so it stays genuinely live and flags are unused: it
    // becomes an xor-zeroing.
    builder.emitLoadRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(conv.intRegs[1], conv.intRegs[0], 0, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ZeroToClear_DeadReg_NotConverted)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    // The zero is never read before being overwritten: it must NOT become a
    // ClearReg (whose flag write would defeat dead-code elimination); leave it
    // as a plain mov-immediate for DCE to remove.
    builder.emitLoadRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(conv.intRegs[0], ApInt(5, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_ZeroToClear_FlagsLive_NotConverted)
{
    const CallConv& conv = CallConv::get(CallConvKind::Swag);
    MicroBuilder    builder(ctx);

    // reg0 is live (used as a memory base below), but a setcc reads the flags
    // that xor-zeroing would clobber, so the mov-immediate must be preserved.
    builder.emitLoadRegImm(conv.intRegs[0], ApInt(0, 64), MicroOpBits::B64);
    builder.emitSetCondReg(conv.intRegs[2], MicroCond::NotEqual);
    builder.emitLoadRegMem(conv.intRegs[1], conv.intRegs[0], 0, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::ClearReg) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRAPeephole_SelfOperand_FoldsWhenDestinationHoldsTheSlot)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg xmm3 = MicroReg::floatReg(3);

    MicroBuilder builder(ctx);
    builder.emitLoadRegMem(xmm3, base, 0x54, MicroOpBits::B32);
    builder.emitOpBinaryRegMem(xmm3, base, 0x54, MicroOp::FloatMultiply, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The rule walks back a bounded number of instructions looking for the load
// of the slot into the destination. When the destination's last write sits
// beyond that window, nothing is known about what it holds: the memory
// operand has to stay.
SWC_TEST_BEGIN(PostRAPeephole_SelfOperand_KeepsMemoryOperandWhenWindowExhausted)
{
    const MicroReg     base = CallConv::get(CallConvKind::Swag).stackPointer;
    constexpr MicroReg xmm3 = MicroReg::floatReg(3);
    constexpr MicroReg xmm4 = MicroReg::floatReg(4);
    constexpr MicroReg xmm5 = MicroReg::floatReg(5);
    constexpr MicroReg xmm6 = MicroReg::floatReg(6);

    MicroBuilder builder(ctx);
    builder.emitLoadRegReg(xmm3, xmm4, MicroOpBits::B32);
    for (uint32_t i = 0; i < 16; ++i)
        builder.emitOpBinaryRegReg(xmm5, xmm6, MicroOp::FloatAdd, MicroOpBits::B32);
    builder.emitOpBinaryRegMem(xmm3, base, 0x54, MicroOp::FloatMultiply, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegMem) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
