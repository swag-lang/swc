#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPostRaPeepholePass(MicroBuilder& builder)
    {
        MicroPostRaPeepholePass pass;
        MicroPassManager        passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t countOpcode(const MicroBuilder& builder, MicroInstrOpcode opcode)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                ++count;
        }

        return count;
    }
}

SWC_TEST_BEGIN(PostRAPeephole_Nop_Erased)
{
    MicroBuilder builder(ctx);
    builder.emitNop();
    builder.emitRet();

    SWC_RESULT(runPostRaPeepholePass(builder));

    if (countOpcode(builder, MicroInstrOpcode::Nop) != 0)
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

    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
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

    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
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

    if (countOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::Nop) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0)
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

    if (countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 0)
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

    if (countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
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

    if (countOpcode(builder, MicroInstrOpcode::CmpRegReg) != 1)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::JumpCond) != 1)
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

    if (countOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 1)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
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
    if (countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::JumpCond) != 1)
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

    if (countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
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

    if (countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
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

    if (countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::ClearReg) != 1)
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

    if (countOpcode(builder, MicroInstrOpcode::ClearReg) != 0)
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

    if (countOpcode(builder, MicroInstrOpcode::ClearReg) != 0)
        return Result::Error;
    if (countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
