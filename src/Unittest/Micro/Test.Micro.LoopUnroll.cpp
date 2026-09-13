#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
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

SWC_TEST_BEGIN(LoopUnroll_FreshRegisterFilesRespectRenamingEligibility)
{
    // Integer-only temporaries, then a renamable and a preserved float temporary.
    for (uint32_t floatMode = 0; floatMode < 3; ++floatMode)
    {
        const MicroReg     sp        = CallConv::get(CallConvKind::Swag).stackPointer;
        constexpr MicroReg counter   = MicroReg::virtualIntReg(1);
        constexpr MicroReg integer   = MicroReg::virtualIntReg(2);
        constexpr MicroReg packed    = MicroReg::virtualFloatReg(2);
        constexpr MicroReg highFloat = MicroReg::virtualFloatReg(900);
        MicroBuilder       builder(ctx);
        const auto         header = builder.createLabel();
        builder.emitLoadRegImm(MicroReg::virtualIntReg(1000), ApInt(7, 64), MicroOpBits::B64);
        builder.emitClearReg(highFloat, MicroOpBits::B128);
        if (floatMode == 2)
            builder.preserveVirtualCopy(packed);
        builder.emitLoadRegImm(counter, ApInt(0, 64), MicroOpBits::B64);
        builder.placeLabel(header);
        builder.emitLoadRegReg(integer, counter, MicroOpBits::B64);
        builder.emitLoadMemReg(sp, 0x40, integer, MicroOpBits::B64);
        if (floatMode != 0)
        {
            builder.emitLoadRegReg(packed, highFloat, MicroOpBits::B128);
            builder.emitStoreVecMemReg(sp, 0x60, packed, MicroOpBits::B128);
        }
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(counter, ApInt(3, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B64, header);
        builder.emitRet();

        SWC_RESULT(runLoopUnrollPass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
            return Result::Error;
        uint32_t integerCopies = 0;
        uint32_t floatCopies   = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg)
                continue;
            const auto* ops = inst.ops(builder.operands());
            if (ops[0].reg.isVirtualFloat())
            {
                const uint32_t expected = floatCopies == 0 || floatMode == 2 ? 2 : 900 + floatCopies;
                if (ops[0].reg.index() != expected || ops[1].reg != highFloat)
                    return Result::Error;
                ++floatCopies;
            }
            else
            {
                const uint32_t expectedDst = integerCopies == 0 ? 2 : 1002 + integerCopies;
                const uint32_t expectedSrc = integerCopies == 0 ? 1 : 1000 + integerCopies;
                if (ops[0].reg.index() != expectedDst || ops[1].reg.index() != expectedSrc)
                    return Result::Error;
                ++integerCopies;
            }
        }
        if (integerCopies != 3 || floatCopies != (floatMode == 0 ? 0u : 3u))
            return Result::Error;
    }
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
