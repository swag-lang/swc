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
