#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.BranchSimplify.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result runBranchSimplifyPass(MicroBuilder& builder)
    {
        MicroBranchSimplifyPass pass;
        MicroPassManager        passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    uint32_t countConditionalJumps(const MicroBuilder& builder)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::JumpCond)
                continue;

            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (ops && ops[0].cpuCond != MicroCond::Unconditional)
                ++count;
        }

        return count;
    }

    uint32_t countLoadImmValue(const MicroBuilder& builder, const uint64_t value)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegImm)
                continue;

            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (ops && ops[2].valueU64 == value)
                ++count;
        }

        return count;
    }

    bool anyJumpTargetsLabel(const MicroBuilder& builder, const MicroLabelRef labelRef)
    {
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::JumpCond)
                continue;

            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (ops && ops[2].valueU64 == labelRef.get())
                return true;
        }

        return false;
    }
}

// je L0 ; L0: -> erase jump.
SWC_TEST_BEGIN(BranchSimplify_ErasesJumpToImmediateLabel)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef labelDone = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, labelDone);
    builder.placeLabel(labelDone);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// je Alias ; ... ; Alias: jmp Then  -> retarget to Then, then drop dead Alias block.
SWC_TEST_BEGIN(BranchSimplify_ThreadsJumpThroughEmptyBlock)
{
    constexpr MicroReg  v1 = MicroReg::virtualIntReg(1);
    MicroBuilder        builder(ctx);
    const MicroLabelRef labelAlias = builder.createLabel();
    const MicroLabelRef labelThen  = builder.createLabel();
    const MicroLabelRef labelJoin  = builder.createLabel();

    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, labelAlias);
    builder.emitLoadRegImm(v1, ApInt(1, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, labelJoin);
    builder.placeLabel(labelAlias);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, labelThen);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(v1, ApInt(2, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (anyJumpTargetsLabel(builder, labelAlias))
        return Result::Error;
    if (!anyJumpTargetsLabel(builder, labelThen))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// load 0 ; cmp 0 ; je Then -> keep only taken path.
SWC_TEST_BEGIN(BranchSimplify_FoldsKnownTrueBranch)
{
    constexpr MicroReg  vCond = MicroReg::virtualIntReg(1);
    constexpr MicroReg  vOut  = MicroReg::virtualIntReg(2);
    MicroBuilder        builder(ctx);
    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitLoadRegImm(vCond, ApInt(0, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(vCond, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, labelThen);
    builder.emitLoadRegImm(vOut, ApInt(1, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(vOut, ApInt(2, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 1) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 2) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// load 5 ; cmp 0 ; je Then -> erase branch and dead taken path.
SWC_TEST_BEGIN(BranchSimplify_FoldsKnownFalseBranch)
{
    constexpr MicroReg  vCond = MicroReg::virtualIntReg(1);
    constexpr MicroReg  vOut  = MicroReg::virtualIntReg(2);
    MicroBuilder        builder(ctx);
    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitLoadRegImm(vCond, ApInt(5, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(vCond, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, labelThen);
    builder.emitLoadRegImm(vOut, ApInt(1, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(vOut, ApInt(2, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 1) != 1)
        return Result::Error;
    if (countLoadImmValue(builder, 2) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// cmp -1, 0 ; jl Neg -> signed compare must fold to taken path.
SWC_TEST_BEGIN(BranchSimplify_FoldsKnownSignedLessBranch)
{
    constexpr MicroReg  vCond = MicroReg::virtualIntReg(1);
    constexpr MicroReg  vOut  = MicroReg::virtualIntReg(2);
    MicroBuilder        builder(ctx);
    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitLoadRegImm(vCond, ApInt(int64_t{-1}, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(vCond, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, labelThen);
    builder.emitLoadRegImm(vOut, ApInt(1, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(vOut, ApInt(2, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countLoadImmValue(builder, 1) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 2) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// cmp 1, 2 ; jb Then -> unsigned compare must fold to taken path.
SWC_TEST_BEGIN(BranchSimplify_FoldsKnownUnsignedBelowBranch)
{
    constexpr MicroReg  vCond = MicroReg::virtualIntReg(1);
    constexpr MicroReg  vOut  = MicroReg::virtualIntReg(2);
    MicroBuilder        builder(ctx);
    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();

    builder.emitLoadRegImm(vCond, ApInt(1, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(vCond, ApInt(2, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, labelThen);
    builder.emitLoadRegImm(vOut, ApInt(10, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(vOut, ApInt(20, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countLoadImmValue(builder, 10) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 20) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// ret ; dead ; dead -> erase dead tail.
SWC_TEST_BEGIN(BranchSimplify_ErasesDeadTailAfterRet)
{
    constexpr MicroReg v1 = MicroReg::virtualIntReg(1);
    MicroBuilder       builder(ctx);

    builder.emitLoadRegImm(v1, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();
    builder.emitLoadRegImm(v1, ApInt(2, 64), MicroOpBits::B64);
    builder.emitLoadRegImm(v1, ApInt(3, 64), MicroOpBits::B64);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countLoadImmValue(builder, 1) != 1)
        return Result::Error;
    if (countLoadImmValue(builder, 2) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 3) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// jcc over a single register copy becomes a conditional move on the
// inverted condition; the label survives.
SWC_TEST_BEGIN(BranchSimplify_ConvertsMinPatternToCmov)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const MicroLabelRef skip = builder.createLabel();

    builder.emitCmpRegReg(vB, vA, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, skip);
    builder.emitLoadRegReg(vA, vB, MicroOpBits::B64);
    builder.placeLabel(skip);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    uint32_t cmovCount = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op != MicroInstrOpcode::LoadCondRegReg)
            continue;
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (ops && ops[2].cpuCond == MicroCond::Below)
            ++cmovCount;
    }

    if (cmovCount != 1)
        return Result::Error;
    if (countConditionalJumps(builder) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// jcc over a single immediate load materializes the immediate above the
// branch and selects it conditionally.
SWC_TEST_BEGIN(BranchSimplify_ConvertsConditionalConstantToCmov)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vC = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const MicroLabelRef skip = builder.createLabel();

    builder.emitCmpRegImm(vC, ApInt(9, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, skip);
    builder.emitLoadRegImm(vA, ApInt(0, 64), MicroOpBits::B64);
    builder.placeLabel(skip);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    uint32_t cmovCount = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op != MicroInstrOpcode::LoadCondRegReg)
            continue;
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (ops && ops[2].cpuCond == MicroCond::Equal)
            ++cmovCount;
    }

    if (cmovCount != 1)
        return Result::Error;
    if (countConditionalJumps(builder) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A two-instruction body is not a conditional move candidate.
SWC_TEST_BEGIN(BranchSimplify_KeepsMultiInstructionBranchBody)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    const MicroReg vC = MicroReg::virtualIntReg(12);
    MicroBuilder   builder(ctx);

    const MicroLabelRef skip = builder.createLabel();

    builder.emitCmpRegReg(vB, vA, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, skip);
    builder.emitLoadRegReg(vA, vB, MicroOpBits::B64);
    builder.emitLoadRegReg(vC, vB, MicroOpBits::B64);
    builder.placeLabel(skip);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A short-circuit `and` exit is threaded straight to the join's target and
// the join label, once unreferenced, is erased.
SWC_TEST_BEGIN(BranchSimplify_ThreadsShortCircuitExit)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    const MicroReg vC = MicroReg::virtualIntReg(12);
    const MicroReg vT = MicroReg::virtualIntReg(13);
    const MicroReg vR = MicroReg::virtualIntReg(14);
    MicroBuilder   builder(ctx);

    const MicroLabelRef join = builder.createLabel();
    const MicroLabelRef exit = builder.createLabel();

    builder.emitCmpRegReg(vA, vB, MicroOpBits::B64);
    builder.emitSetCondReg(vT, MicroCond::Below);
    builder.emitLoadZeroExtendRegReg(vT, vT, MicroOpBits::B32, MicroOpBits::B8);
    builder.emitLoadRegReg(vR, vT, MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, join);
    builder.emitCmpRegImm(vC, ApInt(0x2C, 64), MicroOpBits::B32);
    builder.emitSetCondReg(vT, MicroCond::NotEqual);
    builder.emitLoadZeroExtendRegReg(vT, vT, MicroOpBits::B32, MicroOpBits::B8);
    builder.emitLoadRegReg(vR, vT, MicroOpBits::B8);
    builder.placeLabel(join);
    builder.emitCmpRegImm(vR, ApInt(0, 64), MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, exit);
    builder.emitOpBinaryRegImm(vA, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.placeLabel(exit);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    // Every remaining conditional jump lands on the exit label; the join is gone.
    const MicroOperandStorage& operands = builder.operands();
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op == MicroInstrOpcode::JumpCond)
        {
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops && ops[0].cpuCond != MicroCond::Unconditional && ops[2].valueU64 != exit.get())
                return Result::Error;
        }
        if (inst.op == MicroInstrOpcode::Label)
        {
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops && ops[0].valueU64 == join.get())
                return Result::Error;
        }
    }

    return Result::Continue;
}
SWC_TEST_END()

// A label some jump still targets is never collected.
SWC_TEST_BEGIN(BranchSimplify_KeepsReferencedLabel)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const MicroLabelRef target = builder.createLabel();

    builder.emitCmpRegReg(vA, vB, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, target);
    builder.emitOpBinaryRegImm(vA, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.placeLabel(target);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    uint32_t labelCount = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op == MicroInstrOpcode::Label)
            ++labelCount;
    }
    if (labelCount != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// cmov has no 8/16-bit forms: a narrow select keeps its branch.
SWC_TEST_BEGIN(BranchSimplify_KeepsByteSelectBranch)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const MicroLabelRef skip = builder.createLabel();

    builder.emitCmpRegReg(vB, vA, MicroOpBits::B8);
    builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, skip);
    builder.emitLoadRegReg(vA, vB, MicroOpBits::B8);
    builder.placeLabel(skip);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
