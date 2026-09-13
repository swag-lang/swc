#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runDeadCodeEliminationPass(MicroBuilder& builder)
    {
        MicroDeadCodeEliminationPass pass;
        MicroPassManager             passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

SWC_TEST_BEGIN(DeadCodeElimination_RemovesEntireDeadChain)
{
    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(MicroReg::virtualIntReg(1), ApInt(17, 64), MicroOpBits::B64);
    for (uint32_t i = 2; i <= 128; ++i)
        builder.emitLoadRegReg(MicroReg::virtualIntReg(i), MicroReg::virtualIntReg(i - 1), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runDeadCodeEliminationPass(builder));
    if (builder.instructions().count() != 1 || Backend::Unittest::countOpcode(builder, MicroInstrOpcode::Ret) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DeadCodeElimination_JoinTracksSurvivingConsumers)
{
    for (const bool live : {false, true})
    {
        constexpr MicroReg  value = MicroReg::virtualIntReg(1);
        constexpr MicroReg  copy  = MicroReg::virtualIntReg(2);
        MicroBuilder        builder(ctx);
        const MicroLabelRef alternate = builder.createLabel();
        const MicroLabelRef join      = builder.createLabel();
        builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, alternate);
        builder.emitLoadRegImm(value, ApInt(17, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
        builder.placeLabel(alternate);
        builder.emitLoadRegImm(value, ApInt(23, 64), MicroOpBits::B64);
        builder.placeLabel(join);
        builder.emitLoadRegReg(copy, value, MicroOpBits::B64);
        if (live)
            builder.emitLoadMemReg(MicroReg::intReg(2), 0, copy, MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runDeadCodeEliminationPass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != (live ? 2 : 0) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != (live ? 1 : 0))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DeadCodeElimination_PhiCyclesNeedAnInstructionConsumer)
{
    for (const bool live : {false, true})
    {
        constexpr MicroReg  value = MicroReg::virtualIntReg(1);
        MicroBuilder        builder(ctx);
        const MicroLabelRef header = builder.createLabel();
        const MicroLabelRef join   = builder.createLabel();
        builder.emitLoadRegImm(value, ApInt(17, 64), MicroOpBits::B64);
        builder.placeLabel(header);
        builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, join);
        builder.emitLoadRegImm(value, ApInt(23, 64), MicroOpBits::B64);
        builder.placeLabel(join);
        builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B64, header);
        if (live)
            builder.emitLoadMemReg(MicroReg::intReg(2), 0, value, MicroOpBits::B64);
        builder.emitRet();

        MicroSsaState ssa;
        ssa.build(builder, builder.instructions(), builder.operands(), nullptr);
        if (ssa.phis().size() < 2)
            return Result::Error;

        SWC_RESULT(runDeadCodeEliminationPass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != (live ? 2 : 0))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DeadCodeElimination_DeadFlagConsumerExposesArithmetic)
{
    for (const bool live : {false, true})
    {
        constexpr MicroReg value = MicroReg::virtualIntReg(1);
        constexpr MicroReg flag  = MicroReg::virtualIntReg(2);
        MicroBuilder       builder(ctx);
        builder.emitLoadRegImm(value, ApInt(17, 64), MicroOpBits::B64);
        builder.emitOpBinaryRegImm(value, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitSetCondReg(flag, MicroCond::Zero);
        if (live)
            builder.emitLoadMemReg(MicroReg::intReg(2), 0, flag, MicroOpBits::B8);
        builder.emitCmpRegImm(MicroReg::intReg(3), ApInt(0, 64), MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runDeadCodeEliminationPass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegImm) != (live ? 1 : 0) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != (live ? 1 : 0))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DeadCodeElimination_PreservesStreamsWithoutVirtualDefinitions)
{
    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(17, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(MicroReg::intReg(1), MicroReg::virtualIntReg(1), MicroOpBits::B64);
    builder.emitLoadMemReg(MicroReg::intReg(2), 0, MicroReg::virtualFloatReg(1), MicroOpBits::B64);
    builder.emitRet();
    const auto revision = builder.instructions().revision();
    SWC_RESULT(runDeadCodeEliminationPass(builder));
    if (builder.instructions().revision() != revision || builder.instructions().count() != 4)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DeadCodeElimination_FanOutSkipsRemovedReadersAfterItsWitness)
{
    constexpr MicroReg source = MicroReg::virtualIntReg(1);
    for (const bool live : {false, true})
    {
        MicroBuilder builder(ctx);
        builder.emitLoadRegImm(source, ApInt(17, 64), MicroOpBits::B64);
        // The first consumer survives longer than the second consumer. The
        // cursor must skip that already erased reader when its witness dies.
        for (uint32_t i = 2; i <= 5; ++i)
            builder.emitLoadRegReg(MicroReg::virtualIntReg(i), MicroReg::virtualIntReg(i - 1), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(6), source, MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(7), MicroReg::virtualIntReg(6), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(8), MicroReg::virtualIntReg(7), MicroOpBits::B64);
        if (live)
            builder.emitLoadMemReg(MicroReg::intReg(2), 0, source, MicroOpBits::B64);
        // These inputs have no SSA value, but their consumers disappear after
        // the first wave, while direct-use cursors are already active.
        builder.emitLoadRegReg(MicroReg::virtualIntReg(20), MicroReg::intReg(3), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(21), MicroReg::virtualIntReg(20), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(30), MicroReg::virtualIntReg(99), MicroOpBits::B64);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(31), MicroReg::virtualIntReg(30), MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runDeadCodeEliminationPass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 0 || builder.instructions().count() != (live ? 3u : 1u))
            return Result::Error;
        if (live)
        {
            const auto& first = *builder.instructions().view().begin();
            if (first.op != MicroInstrOpcode::LoadRegImm || first.ops(builder.operands())[0].reg != source)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(DeadCodeElimination_DeferredFlagConsumerKeepsSweepsRunning)
{
    for (const bool live : {false, true})
    {
        constexpr MicroReg value = MicroReg::virtualIntReg(1);
        constexpr MicroReg flag  = MicroReg::virtualIntReg(2);
        constexpr MicroReg first = MicroReg::virtualIntReg(3);
        constexpr MicroReg last  = MicroReg::virtualIntReg(4);
        MicroBuilder       builder(ctx);
        builder.emitLoadRegImm(value, ApInt(17, 64), MicroOpBits::B64);
        // This read-modify-write has two operand uses of the same SSA value.
        builder.emitOpBinaryRegReg(value, value, MicroOp::Add, MicroOpBits::B64);
        builder.emitSetCondReg(flag, MicroCond::Zero);
        builder.emitLoadRegReg(first, flag, MicroOpBits::B8);
        builder.emitLoadRegReg(last, first, MicroOpBits::B8);
        if (live)
            builder.emitLoadMemReg(MicroReg::intReg(2), 0, last, MicroOpBits::B8);
        builder.emitCmpRegImm(MicroReg::intReg(3), ApInt(0, 64), MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runDeadCodeEliminationPass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::OpBinaryRegReg) != (live ? 1u : 0u) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != (live ? 1u : 0u) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::SetCondReg) != (live ? 1u : 0u) ||
            Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != (live ? 2u : 0u))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
