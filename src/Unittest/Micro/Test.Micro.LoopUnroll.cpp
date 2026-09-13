#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.LoopUnroll.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runLoopUnrollPass(MicroBuilder& builder)
    {
        MicroLoopUnrollPass pass;
        MicroPassManager    passManager;
        passManager.addStartPass(pass);
        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    void emitCountedLoop(MicroBuilder& builder, MicroLabelRef header)
    {
        constexpr MicroReg counter = MicroReg::virtualIntReg(1);
        constexpr MicroReg value   = MicroReg::virtualIntReg(2);
        builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
        builder.placeLabel(header);
        builder.emitLoadRegReg(value, counter, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(counter, ApInt(3, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, header);
    }
}

SWC_TEST_BEGIN(LoopUnroll_MultipleLoops_RebuildsIncomingJumpRanges)
{
    MicroBuilder builder(ctx);
    emitCountedLoop(builder, builder.createLabel());
    emitCountedLoop(builder, builder.createLabel());
    builder.emitRet();

    SWC_RESULT(runLoopUnrollPass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 6)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(LoopUnroll_MultipleIncomingJumps_PreservesLoop)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef header = builder.createLabel();
    builder.emitCmpRegImm(MicroReg::virtualIntReg(3), ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, header);
    emitCountedLoop(builder, header);
    builder.emitRet();

    SWC_RESULT(runLoopUnrollPass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 2)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(LoopUnroll_ExternalJumpToBody_PreservesLoop)
{
    constexpr MicroReg  counter = MicroReg::virtualIntReg(1);
    constexpr MicroReg  value   = MicroReg::virtualIntReg(2);
    MicroBuilder        builder(ctx);
    const MicroLabelRef header = builder.createLabel();
    const MicroLabelRef inner  = builder.createLabel();
    builder.emitCmpRegImm(value, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, inner);
    builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(header);
    builder.emitLoadRegReg(value, counter, MicroOpBits::B64);
    builder.placeLabel(inner);
    builder.emitLoadRegReg(value, counter, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(counter, ApInt(3, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, header);
    builder.emitRet();

    SWC_RESULT(runLoopUnrollPass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 2)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
