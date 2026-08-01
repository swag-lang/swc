#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.ValueNumbering.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runValueNumberingPass(MicroBuilder& builder)
    {
        MicroValueNumberingPass pass;
        MicroPassManager        passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t countBinaryRegRegOp(const MicroBuilder& builder, MicroOp op)
    {
        const MicroOperandStorage& operands = builder.operands();
        uint32_t                   count    = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegReg)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops && ops[3].microOp == op)
                ++count;
        }

        return count;
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

// Two identical adds on the same values: the second becomes a plain copy.
SWC_TEST_BEGIN(ValueNumbering_DedupIdenticalCompute)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    const MicroReg v1 = MicroReg::virtualIntReg(12);
    const MicroReg v2 = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vA, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vB, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v1, vA, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, vB, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegReg(v2, vA, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v2, vB, MicroOp::Add, MicroOpBits::B64);
    // Redefine the flags so dropping the duplicate's definition is provably
    // safe before the terminator boundary.
    builder.emitOpBinaryRegImm(v2, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (countBinaryRegRegOp(builder, MicroOp::Add) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Different right-hand values: both adds must stay.
SWC_TEST_BEGIN(ValueNumbering_KeepsDifferentInputs)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    const MicroReg vC = MicroReg::virtualIntReg(12);
    const MicroReg v1 = MicroReg::virtualIntReg(13);
    const MicroReg v2 = MicroReg::virtualIntReg(14);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vA, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vB, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vC, ApInt(9, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v1, vA, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, vB, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegReg(v2, vA, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v2, vC, MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (countBinaryRegRegOp(builder, MicroOp::Add) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The duplicate compute feeds a conditional jump: dropping its flag
// definition would change the branch, so it must stay.
SWC_TEST_BEGIN(ValueNumbering_KeepsComputeWithLiveFlags)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    const MicroReg v1 = MicroReg::virtualIntReg(12);
    const MicroReg v2 = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    const MicroLabelRef done = builder.createLabel();

    builder.emitLoadRegImm(vA, ApInt(5, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vB, ApInt(7, 64), MicroOpBits::B64);
    builder.emitLoadRegReg(v1, vA, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, vB, MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadRegReg(v2, vA, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v2, vB, MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B32, done);
    builder.placeLabel(done);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (countBinaryRegRegOp(builder, MicroOp::Add) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Two identical address computations collapse into one lea plus a copy.
SWC_TEST_BEGIN(ValueNumbering_DedupLoadAddress)
{
    const MicroReg vBase = MicroReg::virtualIntReg(10);
    const MicroReg v1    = MicroReg::virtualIntReg(11);
    const MicroReg v2    = MicroReg::virtualIntReg(12);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadAddressRegMem(v1, vBase, 0x40, MicroOpBits::B64);
    builder.emitLoadAddressRegMem(v2, vBase, 0x40, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadAddrRegMem) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The first result's register is overwritten before the duplicate, so the
// duplicate cannot be rewritten into a copy of it.
SWC_TEST_BEGIN(ValueNumbering_KeepsComputeWhenSourceClobbered)
{
    const MicroReg vBase = MicroReg::virtualIntReg(10);
    const MicroReg v1    = MicroReg::virtualIntReg(11);
    const MicroReg v2    = MicroReg::virtualIntReg(12);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadAddressRegMem(v1, vBase, 0x40, MicroOpBits::B64);
    builder.emitLoadRegImm(v1, ApInt(0, 64), MicroOpBits::B64); // clobber the first result
    builder.emitLoadAddressRegMem(v2, vBase, 0x40, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (countOpcode(builder, MicroInstrOpcode::LoadAddrRegMem) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
