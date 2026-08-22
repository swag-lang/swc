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

namespace
{
    uint32_t countInstructionsWithOpcode(const MicroBuilder& builder, const MicroInstrOpcode opcode)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == opcode)
                ++count;
        }

        return count;
    }

    uint32_t countConditionalMoves(const MicroBuilder& builder, const MicroCond cond)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op != MicroInstrOpcode::LoadCondRegReg)
                continue;
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (ops && ops[2].cpuCond == cond)
                ++count;
        }

        return count;
    }

    // The ternary diamond the code generator emits for `c ? a : b`, with the
    // caller choosing what each arm does and a reader after the join.
    struct DiamondShape
    {
        MicroReg      result   = MicroReg::virtualIntReg(12);
        MicroLabelRef armLabel = MicroLabelRef::invalid();
        MicroLabelRef join     = MicroLabelRef::invalid();
    };

    DiamondShape openDiamond(MicroBuilder& builder, const MicroReg lhs, const MicroReg rhs, const MicroCond cond)
    {
        DiamondShape shape;
        shape.armLabel = builder.createLabel();
        shape.join     = builder.createLabel();
        builder.emitCmpRegReg(lhs, rhs, MicroOpBits::B32);
        builder.emitJumpToLabel(cond, MicroOpBits::B32, shape.armLabel);
        return shape;
    }

    void switchDiamondArm(MicroBuilder& builder, const DiamondShape& shape)
    {
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, shape.join);
        builder.placeLabel(shape.armLabel);
    }

    void closeDiamond(MicroBuilder& builder, const DiamondShape& shape)
    {
        builder.placeLabel(shape.join);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(13), shape.result, MicroOpBits::B32);
        builder.emitRet();
    }
}

// A ternary whose arms are one copy each: the jump arm's result is renamed,
// selected by the branch condition, and no branch is left.
SWC_TEST_BEGIN(BranchSimplify_ConvertsDiamondSelectToCmov)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vA, vB, MicroCond::GreaterOrEqual);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B32);
    switchDiamondArm(builder, shape);
    builder.emitLoadRegReg(shape.result, vB, MicroOpBits::B32);
    closeDiamond(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalMoves(builder, MicroCond::GreaterOrEqual) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::Label) != 1)
        return Result::Error;

    // The jump arm's copy writes a fresh register, and the move reads it.
    MicroReg renamed = MicroReg::invalid();
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadRegReg && ops && ops[1].reg == vB)
            renamed = ops[0].reg;
        if (inst.op == MicroInstrOpcode::LoadCondRegReg && ops && (ops[0].reg != shape.result || ops[1].reg != renamed))
            return Result::Error;
    }
    if (!renamed.isValid() || renamed == shape.result)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// `c ? 7 : 9`: both arms load an immediate, both loads stay and feed the move.
SWC_TEST_BEGIN(BranchSimplify_ConvertsDiamondConstantsToCmov)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vA, vB, MicroCond::NotEqual);
    builder.emitLoadRegImm(shape.result, ApInt(7, 32), MicroOpBits::B32);
    switchDiamondArm(builder, shape);
    builder.emitLoadRegImm(shape.result, ApInt(9, 32), MicroOpBits::B32);
    closeDiamond(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalMoves(builder, MicroCond::NotEqual) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 7) != 1 || countLoadImmValue(builder, 9) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A nested select: the jump arm carries its own compare and move, so the
// outer compare is re-issued right before the outer move.
SWC_TEST_BEGIN(BranchSimplify_SinksCompareBelowFlagWritingArm)
{
    const MicroReg vX = MicroReg::virtualIntReg(8);
    const MicroReg vY = MicroReg::virtualIntReg(9);
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vX, vY, MicroCond::Less);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B32);
    switchDiamondArm(builder, shape);
    builder.emitCmpRegReg(vA, vB, MicroOpBits::B32);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B32);
    builder.emitLoadCondRegReg(shape.result, vB, MicroCond::Greater, MicroOpBits::B32);
    closeDiamond(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalMoves(builder, MicroCond::Less) != 1 || countConditionalMoves(builder, MicroCond::Greater) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::CmpRegReg) != 2)
        return Result::Error;

    // The outer compare now sits right before the outer move.
    bool previousWasOuterCompare = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadCondRegReg && ops && ops[2].cpuCond == MicroCond::Less && !previousWasOuterCompare)
            return Result::Error;
        previousWasOuterCompare = inst.op == MicroInstrOpcode::CmpRegReg && ops && ops[0].reg == vX && ops[1].reg == vY;
    }

    return Result::Continue;
}
SWC_TEST_END()

// An arm that reads memory may fault on the path that used to skip it: the
// branch stays.
SWC_TEST_BEGIN(BranchSimplify_KeepsDiamondWithGuardedLoad)
{
    const MicroReg vP = MicroReg::virtualIntReg(10);
    const MicroReg vZ = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vP, vZ, MicroCond::Equal);
    builder.emitLoadRegMem(shape.result, vP, 0, MicroOpBits::B32);
    switchDiamondArm(builder, shape);
    builder.emitLoadRegImm(shape.result, ApInt(0, 32), MicroOpBits::B32);
    closeDiamond(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The jump arm's label is also reached from elsewhere: folding the arm into
// the straight line would strand that other path.
SWC_TEST_BEGIN(BranchSimplify_KeepsDiamondWithSharedArmLabel)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vA, vB, MicroCond::GreaterOrEqual);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B32);
    switchDiamondArm(builder, shape);
    builder.emitLoadRegReg(shape.result, vB, MicroOpBits::B32);
    builder.placeLabel(shape.join);
    builder.emitCmpRegReg(vA, vB, MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, shape.armLabel);
    builder.emitLoadRegReg(MicroReg::virtualIntReg(13), shape.result, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 2)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The jump arm reads the result before writing it: renaming would make it
// read the other arm's value.
SWC_TEST_BEGIN(BranchSimplify_KeepsDiamondWhenArmReadsResultFirst)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vA, vB, MicroCond::GreaterOrEqual);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B32);
    switchDiamondArm(builder, shape);
    builder.emitLoadRegReg(shape.result, shape.result, MicroOpBits::B32);
    closeDiamond(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// A flag-writing arm that also overwrites a compare input: the compare cannot
// be re-issued after it, so the branch stays.
SWC_TEST_BEGIN(BranchSimplify_KeepsDiamondWhenArmClobbersCompareInput)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vA, vB, MicroCond::GreaterOrEqual);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B32);
    switchDiamondArm(builder, shape);
    builder.emitOpBinaryRegImm(vA, ApInt(1, 32), MicroOp::Add, MicroOpBits::B32);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B32);
    closeDiamond(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// cmov has no 8/16-bit forms: a narrow diamond keeps its branch.
SWC_TEST_BEGIN(BranchSimplify_KeepsByteDiamond)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vA, vB, MicroCond::GreaterOrEqual);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B8);
    switchDiamondArm(builder, shape);
    builder.emitLoadRegReg(shape.result, vB, MicroOpBits::B8);
    closeDiamond(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
