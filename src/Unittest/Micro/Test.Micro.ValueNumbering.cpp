#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.ValueNumbering.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

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

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrRegMem) != 1)
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

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAddrRegMem) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// Two loads of one indexed address with nothing written in between: the
// second becomes a copy of the first.
SWC_TEST_BEGIN(ValueNumbering_DedupRepeatedLoad)
{
    const MicroReg vBase = MicroReg::virtualIntReg(10);
    const MicroReg vIdx  = MicroReg::virtualIntReg(11);
    const MicroReg v1    = MicroReg::virtualIntReg(12);
    const MicroReg v2    = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vIdx, ApInt(3, 64), MicroOpBits::B64);
    builder.emitLoadAmcRegMem(v1, MicroOpBits::B32, vBase, vIdx, 4, 0, MicroOpBits::B64);
    builder.emitLoadAmcRegMem(v2, MicroOpBits::B32, vBase, vIdx, 4, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::Add, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAmcRegMem) != 1)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegReg) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The same for a plain base+offset load, which mem2reg left in memory.
SWC_TEST_BEGIN(ValueNumbering_DedupRepeatedFieldLoad)
{
    const MicroReg vBase = MicroReg::virtualIntReg(10);
    const MicroReg v1    = MicroReg::virtualIntReg(12);
    const MicroReg v2    = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(v1, vBase, 8, MicroOpBits::B64);
    builder.emitLoadRegMem(v2, vBase, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A store in between may have changed the cell, whatever it wrote through:
// both loads stay.
SWC_TEST_BEGIN(ValueNumbering_KeepsLoadAcrossStore)
{
    const MicroReg vBase  = MicroReg::virtualIntReg(10);
    const MicroReg vIdx   = MicroReg::virtualIntReg(11);
    const MicroReg v1     = MicroReg::virtualIntReg(12);
    const MicroReg v2     = MicroReg::virtualIntReg(13);
    const MicroReg vOther = MicroReg::virtualIntReg(14);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vIdx, ApInt(3, 64), MicroOpBits::B64);
    builder.emitLoadAmcRegMem(v1, MicroOpBits::B32, vBase, vIdx, 4, 0, MicroOpBits::B64);
    builder.emitLoadMemReg(vOther, 0, v1, MicroOpBits::B32);
    builder.emitLoadAmcRegMem(v2, MicroOpBits::B32, vBase, vIdx, 4, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::Add, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAmcRegMem) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A label in between means another path may reach the second load: it stays,
// even though the first load dominates it here.
SWC_TEST_BEGIN(ValueNumbering_KeepsLoadAcrossLabel)
{
    const MicroReg vBase = MicroReg::virtualIntReg(10);
    const MicroReg vIdx  = MicroReg::virtualIntReg(11);
    const MicroReg v1    = MicroReg::virtualIntReg(12);
    const MicroReg v2    = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vIdx, ApInt(3, 64), MicroOpBits::B64);
    const MicroLabelRef label = builder.createLabel();
    builder.emitLoadAmcRegMem(v1, MicroOpBits::B32, vBase, vIdx, 4, 0, MicroOpBits::B64);
    builder.emitCmpRegImm(v1, ApInt(0, 32), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, label);
    builder.emitOpBinaryRegImm(v1, ApInt(1, 32), MicroOp::Add, MicroOpBits::B32);
    builder.placeLabel(label);
    builder.emitLoadAmcRegMem(v2, MicroOpBits::B32, vBase, vIdx, 4, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::Add, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAmcRegMem) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A conditional jump does not end the straight line for the fall-through
// path: the load after it still repeats the one before.
SWC_TEST_BEGIN(ValueNumbering_DedupLoadAcrossFallthroughBranch)
{
    const MicroReg vBase = MicroReg::virtualIntReg(10);
    const MicroReg vIdx  = MicroReg::virtualIntReg(11);
    const MicroReg v1    = MicroReg::virtualIntReg(12);
    const MicroReg v2    = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(vIdx, ApInt(3, 64), MicroOpBits::B64);
    const MicroLabelRef exit = builder.createLabel();
    builder.emitLoadAmcRegMem(v1, MicroOpBits::B32, vBase, vIdx, 4, 0, MicroOpBits::B64);
    builder.emitCmpRegImm(v1, ApInt(0, 32), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, exit);
    builder.emitLoadAmcRegMem(v2, MicroOpBits::B32, vBase, vIdx, 4, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::Add, MicroOpBits::B32);
    builder.placeLabel(exit);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadAmcRegMem) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The byte a scanner compares is the byte it consumes: a zero-extending load
// and a plain byte load of the same cell share one read, and the plain one
// becomes a byte copy of the extended register.
SWC_TEST_BEGIN(ValueNumbering_DedupPlainLoadAfterExtendingLoad)
{
    const MicroReg vBase = MicroReg::virtualIntReg(10);
    const MicroReg v1    = MicroReg::virtualIntReg(12);
    const MicroReg v2    = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadZeroExtendRegMem(v1, vBase, 8, MicroOpBits::B32, MicroOpBits::B8);
    builder.emitLoadRegMem(v2, vBase, 8, MicroOpBits::B8);
    builder.emitOpBinaryRegImm(v2, ApInt(48, 8), MicroOp::Subtract, MicroOpBits::B8);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::Add, MicroOpBits::B8);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 0)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadZeroExtRegMem) != 1)
        return Result::Error;

    uint32_t byteCopies = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadRegReg && ops && ops[0].reg == v2 && ops[1].reg == v1 && ops[2].opBits == MicroOpBits::B8)
            ++byteCopies;
    }
    if (byteCopies != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The other way round: the plain byte load came first, so the extending load
// becomes the same extension of the register that holds the byte.
SWC_TEST_BEGIN(ValueNumbering_ExtendsEarlierPlainLoad)
{
    const MicroReg vBase = MicroReg::virtualIntReg(10);
    const MicroReg v1    = MicroReg::virtualIntReg(12);
    const MicroReg v2    = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    builder.emitLoadRegImm(vBase, ApInt(0x1000, 64), MicroOpBits::B64);
    builder.emitLoadRegMem(v1, vBase, 8, MicroOpBits::B8);
    builder.emitLoadSignedExtendRegMem(v2, vBase, 8, MicroOpBits::B64, MicroOpBits::B8);
    builder.emitOpBinaryRegReg(v2, v1, MicroOp::Add, MicroOpBits::B8);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadSignedExtRegMem) != 0)
        return Result::Error;

    uint32_t extensions = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadSignedExtRegReg && ops && ops[0].reg == v2 && ops[1].reg == v1 && ops[2].opBits == MicroOpBits::B64 && ops[3].opBits == MicroOpBits::B8)
            ++extensions;
    }
    if (extensions != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A local's slot belongs to mem2reg: reloads through the frame are not
// numbered, so promotion does not find a copy chain in its way.
SWC_TEST_BEGIN(ValueNumbering_KeepsFrameLoadsForMemToReg)
{
    const MicroReg sp  = CallConv::get(CallConvKind::Swag).stackPointer;
    const MicroReg vFb = MicroReg::virtualIntReg(10);
    const MicroReg v1  = MicroReg::virtualIntReg(12);
    const MicroReg v2  = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    builder.emitLoadAddressRegMem(vFb, sp, 0x20, MicroOpBits::B64);
    builder.emitLoadRegMem(v1, vFb, 8, MicroOpBits::B64);
    builder.emitLoadRegMem(v2, vFb, 8, MicroOpBits::B64);
    builder.emitOpBinaryRegReg(v1, v2, MicroOp::Add, MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runValueNumberingPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegMem) != 2)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ValueNumbering_SharesScalarFloatLiteralBits)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        const uint64_t sign = bits == MicroOpBits::B32 ? 0x80000000ULL : 0x8000000000000000ULL;
        const uint64_t nan  = bits == MicroOpBits::B32 ? 0x7FC00123ULL : 0x7FF8000000000123ULL;
        for (const uint64_t raw : {uint64_t{1}, sign, nan})
        {
            constexpr MicroReg first  = MicroReg::virtualFloatReg(1);
            constexpr MicroReg second = MicroReg::virtualFloatReg(2);
            MicroBuilder       builder(ctx);
            builder.emitLoadRegImm(first, ApInt(raw, 64), bits);
            builder.emitLoadMemReg(MicroReg::intReg(2), 0, first, bits);
            builder.emitLoadRegImm(second, ApInt(raw, 64), bits);
            builder.emitLoadMemReg(MicroReg::intReg(2), 8, second, bits);
            builder.emitRet();
            SWC_RESULT(runValueNumberingPass(builder));
            if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 1)
                return Result::Error;
            bool found = false;
            for (const MicroInstr& inst : builder.instructions().view())
            {
                if (inst.op != MicroInstrOpcode::LoadRegReg)
                    continue;
                const MicroInstrOperand* ops = inst.ops(builder.operands());
                if (ops[0].reg == second && ops[1].reg == first && ops[2].opBits == bits)
                    found = true;
            }
            if (!found)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ValueNumbering_KeepsCheapOrDistinctLiterals)
{
    struct Case
    {
        bool        floating;
        MicroOpBits firstBits;
        MicroOpBits secondBits;
        uint64_t    firstRaw;
        uint64_t    secondRaw;
    };
    constexpr Case CASES[] = {
        {false, MicroOpBits::B64, MicroOpBits::B64, 1, 1},
        {true, MicroOpBits::B64, MicroOpBits::B64, 0, 0},
        {true, MicroOpBits::B64, MicroOpBits::B64, 0, 0x8000000000000000ULL},
        {true, MicroOpBits::B32, MicroOpBits::B64, 1, 1},
        {true, MicroOpBits::B64, MicroOpBits::B64, 0x7FF8000000000001ULL, 0x7FF8000000000002ULL},
    };
    for (const Case& test : CASES)
    {
        const MicroReg first  = test.floating ? MicroReg::virtualFloatReg(1) : MicroReg::virtualIntReg(1);
        const MicroReg second = test.floating ? MicroReg::virtualFloatReg(2) : MicroReg::virtualIntReg(2);
        MicroBuilder   builder(ctx);
        builder.emitLoadRegImm(first, ApInt(test.firstRaw, 64), test.firstBits);
        builder.emitLoadRegImm(second, ApInt(test.secondRaw, 64), test.secondBits);
        builder.emitRet();
        SWC_RESULT(runValueNumberingPass(builder));
        if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadRegImm) != 2)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
