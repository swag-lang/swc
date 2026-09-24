#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.PostRALoopRotate.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runPostRaLoopRotatePass(MicroBuilder& builder)
    {
        MicroPostRaLoopRotatePass pass;
        MicroPassManager          passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

SWC_TEST_BEGIN(PostRALoopRotate_IndependentHeadersRotate)
{
    MicroBuilder               builder(ctx);
    SmallVector<MicroInstrRef> backEdges;
    SmallVector<MicroLabelRef> headers;
    for (uint32_t i = 0; i < 2; ++i)
    {
        const MicroLabelRef top     = builder.createLabel();
        const MicroLabelRef done    = builder.createLabel();
        const MicroReg      counter = MicroReg::intReg(i);
        headers.push_back(top);
        builder.placeLabel(top);
        builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
        builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
        backEdges.push_back(builder.instructions().lastInstructionRef());
        builder.placeLabel(done);
    }
    builder.emitRet();

    SWC_RESULT(runPostRaLoopRotatePass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 4)
        return Result::Error;
    for (uint32_t i = 0; i < backEdges.size(); ++i)
    {
        const auto* inst = builder.instructions().ptr(backEdges[i]);
        if (!inst || inst->op != MicroInstrOpcode::JumpCond)
            return Result::Error;
        const auto* ops = inst->ops(builder.operands());
        if (ops[0].cpuCond != MicroCond::Less || ops[2].valueU64 == headers[i].get())
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_FlagOnlyTestsRotateWithUniqueBackEdge)
{
    constexpr MicroReg counter = MicroReg::intReg(0);
    constexpr MicroReg other   = MicroReg::intReg(1);
    for (const MicroInstrOpcode testOp : {MicroInstrOpcode::TestRegReg, MicroInstrOpcode::TestRegImm,
                                           MicroInstrOpcode::TestMemReg, MicroInstrOpcode::TestMemImm})
    {
        for (const bool secondEntry : {false, true})
        {
            MicroBuilder builder(ctx);
            const auto   top  = builder.createLabel();
            const auto   done = builder.createLabel();
            if (secondEntry)
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
            builder.placeLabel(top);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, done);
            const MicroInstrRef jumpRef = builder.instructions().lastInstructionRef();
            MicroInstrOperand   testOps[4] = {};
            testOps[0].reg = counter;
            switch (testOp)
            {
                case MicroInstrOpcode::TestRegReg:
                    testOps[1].reg    = counter;
                    testOps[2].opBits = MicroOpBits::B64;
                    builder.instructions().insertDerivedBefore(builder.operands(), jumpRef, testOp, std::span(testOps, 3));
                    break;
                case MicroInstrOpcode::TestRegImm:
                    testOps[1].opBits = MicroOpBits::B64;
                    testOps[2].setImmediateValue(ApInt(1, 64));
                    builder.instructions().insertDerivedBefore(builder.operands(), jumpRef, testOp, std::span(testOps, 3));
                    break;
                case MicroInstrOpcode::TestMemReg:
                    testOps[1].reg      = other;
                    testOps[2].opBits   = MicroOpBits::B64;
                    testOps[3].valueU64 = 0;
                    builder.instructions().insertDerivedBefore(builder.operands(), jumpRef, testOp, std::span(testOps, 4));
                    break;
                case MicroInstrOpcode::TestMemImm:
                    testOps[1].opBits   = MicroOpBits::B64;
                    testOps[2].valueU64 = 0;
                    testOps[3].setImmediateValue(ApInt(1, 64));
                    builder.instructions().insertDerivedBefore(builder.operands(), jumpRef, testOp, std::span(testOps, 4));
                    break;
                default:
                    return Result::Error;
            }
            builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Subtract, MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
            const MicroInstrRef backRef = builder.instructions().lastInstructionRef();
            builder.placeLabel(done);
            builder.emitRet();

            SWC_RESULT(runPostRaLoopRotatePass(builder));
            if (Backend::Unittest::countOpcode(builder, testOp) != (secondEntry ? 1u : 2u))
                return Result::Error;
            const MicroInstr* back = builder.instructions().ptr(backRef);
            if (!back || back->op != MicroInstrOpcode::JumpCond ||
                back->ops(builder.operands())[0].cpuCond != (secondEntry ? MicroCond::Unconditional : MicroCond::NotEqual))
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_SecondIncomingJumpBlocks)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef top     = builder.createLabel();
    const MicroLabelRef done    = builder.createLabel();
    constexpr MicroReg  counter = MicroReg::intReg(0);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
    builder.placeLabel(top);
    builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
    builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, top);
    const auto backEdge = builder.instructions().lastInstructionRef();
    builder.placeLabel(done);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopRotatePass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    const auto* ops = builder.instructions().ptr(backEdge)->ops(builder.operands());
    if (ops[0].cpuCond != MicroCond::Unconditional || ops[2].valueU64 != top.get())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(PostRALoopRotate_ConditionalBackEdgeBlocks)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef top     = builder.createLabel();
    const MicroLabelRef done    = builder.createLabel();
    constexpr MicroReg  counter = MicroReg::intReg(0);
    builder.placeLabel(top);
    builder.emitCmpRegImm(counter, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B64, done);
    builder.emitOpBinaryRegImm(counter, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B64, top);
    const auto backEdge = builder.instructions().lastInstructionRef();
    builder.placeLabel(done);
    builder.emitRet();

    SWC_RESULT(runPostRaLoopRotatePass(builder));
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::CmpRegImm) != 1)
        return Result::Error;
    const auto* ops = builder.instructions().ptr(backEdge)->ops(builder.operands());
    if (ops[0].cpuCond != MicroCond::NotZero || ops[2].valueU64 != top.get())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
