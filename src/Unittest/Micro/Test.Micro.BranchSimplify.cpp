#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
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

    uint32_t countTableAddresses(const MicroBuilder& builder)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::LoadRegPtrReloc)
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

// Clearing an XMM register preserves the dynamic comparison's integer flags.
SWC_TEST_BEGIN(BranchSimplify_KeepsDynamicBranchAcrossFloatClear)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64, MicroOpBits::B128})
    {
        const MicroReg vA    = MicroReg::virtualIntReg(1);
        const MicroReg vB    = MicroReg::virtualIntReg(2);
        const MicroReg vZero = MicroReg::virtualFloatReg(1);
        MicroBuilder   builder(ctx);

        const MicroLabelRef skip = builder.createLabel();
        builder.emitCmpRegReg(vA, vB, MicroOpBits::B64);
        builder.emitClearReg(vZero, bits);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, skip);
        // A guarded store cannot be converted to a conditional move or speculated.
        builder.emitLoadMemImm(vA, 0, ApInt(17, 64), MicroOpBits::B64);
        builder.placeLabel(skip);
        builder.emitRet();

        SWC_RESULT(runBranchSimplifyPass(builder));

        if (countConditionalJumps(builder) != 1)
            return Result::Error;
        if (!anyJumpTargetsLabel(builder, skip))
            return Result::Error;
    }

    return Result::Continue;
}
SWC_TEST_END()

// An integer clear does replace the comparison's flags with the known zero result.
SWC_TEST_BEGIN(BranchSimplify_FoldsKnownBranchAfterIntegerClear)
{
    const MicroReg vA    = MicroReg::virtualIntReg(1);
    const MicroReg vB    = MicroReg::virtualIntReg(2);
    const MicroReg vZero = MicroReg::virtualIntReg(3);
    const MicroReg vOut  = MicroReg::virtualIntReg(4);
    MicroBuilder   builder(ctx);

    const MicroLabelRef labelThen = builder.createLabel();
    const MicroLabelRef labelJoin = builder.createLabel();
    builder.emitCmpRegReg(vA, vB, MicroOpBits::B64);
    builder.emitClearReg(vZero, MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, labelThen);
    builder.emitLoadRegImm(vOut, ApInt(17, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, labelJoin);
    builder.placeLabel(labelThen);
    builder.emitLoadRegImm(vOut, ApInt(23, 64), MicroOpBits::B64);
    builder.placeLabel(labelJoin);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 17) != 0)
        return Result::Error;
    if (countLoadImmValue(builder, 23) != 1)
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

namespace
{
    // cmp a, b; setb t; r = t; jae .join; <rhs>; .join: cmp r, 0; jne .exit;
    // <fall-through, reading the flags first when `readsFlags`>; .exit: ret
    // The join falls through on the early exit, where r is zero.
    void emitFallThroughJoin(MicroBuilder& builder, MicroLabelRef join, MicroLabelRef exit, bool readsFlags)
    {
        const MicroReg vA = MicroReg::virtualIntReg(10);
        const MicroReg vB = MicroReg::virtualIntReg(11);
        const MicroReg vC = MicroReg::virtualIntReg(12);
        const MicroReg vT = MicroReg::virtualIntReg(13);
        const MicroReg vR = MicroReg::virtualIntReg(14);
        const MicroReg vF = MicroReg::virtualIntReg(15);

        builder.emitCmpRegReg(vA, vB, MicroOpBits::B64);
        builder.emitSetCondReg(vT, MicroCond::Below);
        builder.emitLoadRegReg(vR, vT, MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, join);
        builder.emitCmpRegImm(vC, ApInt(0x2C, 64), MicroOpBits::B32);
        builder.emitSetCondReg(vT, MicroCond::NotEqual);
        builder.emitLoadRegReg(vR, vT, MicroOpBits::B8);
        builder.placeLabel(join);
        builder.emitCmpRegImm(vR, ApInt(0, 64), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, exit);
        if (readsFlags)
            builder.emitSetCondReg(vF, MicroCond::Equal);
        builder.emitOpBinaryRegImm(vA, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.placeLabel(exit);
        builder.emitLoadMemReg(vB, 0, vR, MicroOpBits::B8);
        builder.emitRet();
    }

    uint64_t earlyExitTarget(const MicroBuilder& builder)
    {
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::JumpCond && ops[0].cpuCond == MicroCond::AboveOrEqual)
                return ops[2].valueU64;
        }
        return UINT64_MAX;
    }
}

// The early exit of an `and` whose join falls through for it goes past the
// join's test.
SWC_TEST_BEGIN(BranchSimplify_ThreadsShortCircuitExitPastJoin)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef join = builder.createLabel();
    const MicroLabelRef exit = builder.createLabel();
    emitFallThroughJoin(builder, join, exit, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    const uint64_t target = earlyExitTarget(builder);
    if (target == UINT64_MAX || target == join.get() || target == exit.get())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A fall-through that reads the join's flags keeps the exit on the join.
SWC_TEST_BEGIN(BranchSimplify_KeepsShortCircuitExitWhenFallThroughReadsFlags)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef join = builder.createLabel();
    const MicroLabelRef exit = builder.createLabel();
    emitFallThroughJoin(builder, join, exit, true);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (earlyExitTarget(builder) != join.get())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // cmp a, b; setge t; r = t; jl .join; <rhs>; .join: o = r; cmp r, 0; je .exit
    void emitNestedShortCircuit(MicroBuilder& builder, MicroLabelRef join, MicroLabelRef exit, bool rhsReadsOuter)
    {
        const MicroReg vA = MicroReg::virtualIntReg(10);
        const MicroReg vB = MicroReg::virtualIntReg(11);
        const MicroReg vC = MicroReg::virtualIntReg(12);
        const MicroReg vT = MicroReg::virtualIntReg(13);
        const MicroReg vR = MicroReg::virtualIntReg(14);
        const MicroReg vO = MicroReg::virtualIntReg(15);
        const MicroReg vU = MicroReg::virtualIntReg(16);

        builder.emitCmpRegReg(vA, vB, MicroOpBits::B32);
        builder.emitSetCondReg(vT, MicroCond::GreaterOrEqual);
        builder.emitLoadRegReg(vR, vT, MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, join);
        if (rhsReadsOuter)
            builder.emitLoadRegReg(vU, vO, MicroOpBits::B8);
        builder.emitCmpRegImm(vC, ApInt(0, 64), MicroOpBits::B32);
        builder.emitSetCondReg(vT, MicroCond::NotEqual);
        builder.emitLoadRegReg(vR, vT, MicroOpBits::B8);
        builder.placeLabel(join);
        builder.emitLoadRegReg(vO, vR, MicroOpBits::B8);
        builder.emitCmpRegImm(vR, ApInt(0, 64), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, exit);
        builder.emitOpBinaryRegImm(vA, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
        builder.placeLabel(exit);
        builder.emitLoadZeroExtendRegReg(CallConv::get(CallConvKind::Swag).intReturn, vO, MicroOpBits::B64, MicroOpBits::B8);
        builder.emitRet();
    }
}

// The join first copies the boolean for an enclosing `and`: both results
// share one register, and the early exit goes straight to the join's target.
SWC_TEST_BEGIN(BranchSimplify_ThreadsShortCircuitExitThroughJoinCopy)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef join = builder.createLabel();
    const MicroLabelRef exit = builder.createLabel();
    emitNestedShortCircuit(builder, join, exit, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (anyJumpTargetsLabel(builder, join))
        return Result::Error;
    uint32_t outerCopies = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::LoadRegReg && ops && ops[0].reg == MicroReg::virtualIntReg(15))
            ++outerCopies;
    }
    if (outerCopies != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The rhs reads the register the join copy writes: the two results cannot
// share one register, so the exit keeps going through the join.
SWC_TEST_BEGIN(BranchSimplify_KeepsShortCircuitExitWhenRhsReadsJoinCopy)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef join = builder.createLabel();
    const MicroLabelRef exit = builder.createLabel();
    emitNestedShortCircuit(builder, join, exit, true);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (!anyJumpTargetsLabel(builder, join))
        return Result::Error;
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

// Two adjacent comparison guards reject to the same select arm. The shared
// arm is intentional here: both guards become conditional moves and no branch
// or arm label remains.
SWC_TEST_BEGIN(BranchSimplify_ConvertsGuardedSelectToCmovChain)
{
    const MicroReg vX       = MicroReg::virtualIntReg(8);
    const MicroReg vLow     = MicroReg::virtualIntReg(9);
    const MicroReg vHigh    = MicroReg::virtualIntReg(10);
    const MicroReg vInside  = MicroReg::virtualIntReg(11);
    const MicroReg vOutside = MicroReg::virtualIntReg(12);
    const MicroReg vResult  = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    const MicroLabelRef outsideLabel = builder.createLabel();
    const MicroLabelRef joinLabel    = builder.createLabel();
    builder.emitCmpRegReg(vX, vLow, MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, outsideLabel);
    builder.emitCmpRegReg(vX, vHigh, MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Above, MicroOpBits::B32, outsideLabel);
    builder.emitLoadRegReg(vResult, vInside, MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, joinLabel);
    builder.placeLabel(outsideLabel);
    builder.emitLoadRegReg(vResult, vOutside, MicroOpBits::B32);
    builder.placeLabel(joinLabel);
    builder.emitLoadRegReg(MicroReg::virtualIntReg(14), vResult, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0)
        return Result::Error;
    if (countConditionalMoves(builder, MicroCond::Above) != 1 ||
        countConditionalMoves(builder, MicroCond::Below) != 1)
        return Result::Error;
    if (anyJumpTargetsLabel(builder, outsideLabel))
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

// NOT preserves the entry flags. A later conditional move still needs them,
// so an arithmetic sibling arm cannot be speculated before it.
SWC_TEST_BEGIN(BranchSimplify_KeepsDiamondWithFlagReadAfterBitwiseNot)
{
    const MicroReg vX = MicroReg::virtualIntReg(8);
    const MicroReg vY = MicroReg::virtualIntReg(9);
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const DiamondShape shape = openDiamond(builder, vX, vY, MicroCond::Equal);
    builder.emitLoadRegReg(shape.result, vA, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(shape.result, ApInt(1, 32), MicroOp::Add, MicroOpBits::B32);
    switchDiamondArm(builder, shape);
    builder.emitLoadRegReg(shape.result, vB, MicroOpBits::B32);
    builder.emitOpUnaryReg(shape.result, MicroOp::BitwiseNot, MicroOpBits::B32);
    builder.emitLoadCondRegReg(shape.result, vA, MicroCond::Equal, MicroOpBits::B32);
    closeDiamond(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1)
        return Result::Error;
    if (countConditionalMoves(builder, MicroCond::Equal) != 1)
        return Result::Error;
    if (!anyJumpTargetsLabel(builder, shape.armLabel))
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

// The same entry-flag dependency must survive the early-return conversion.
SWC_TEST_BEGIN(BranchSimplify_KeepsEarlyReturnWithFlagReadAfterBitwiseNot)
{
    const MicroReg returnReg = CallConv::get(CallConvKind::Swag).intReturn;
    const MicroReg vX        = MicroReg::virtualIntReg(8);
    const MicroReg vY        = MicroReg::virtualIntReg(9);
    const MicroReg vA        = MicroReg::virtualIntReg(10);
    const MicroReg vB        = MicroReg::virtualIntReg(11);
    const MicroReg early     = MicroReg::virtualIntReg(12);
    const MicroReg tail      = MicroReg::virtualIntReg(13);
    MicroBuilder   builder(ctx);

    const MicroLabelRef restLabel = builder.createLabel();
    builder.emitCmpRegReg(vX, vY, MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, restLabel);
    builder.emitLoadRegReg(early, vA, MicroOpBits::B32);
    builder.emitOpBinaryRegImm(early, ApInt(1, 32), MicroOp::Add, MicroOpBits::B32);
    builder.emitLoadRegReg(returnReg, early, MicroOpBits::B32);
    builder.emitRet();
    builder.placeLabel(restLabel);
    builder.emitLoadRegReg(tail, vB, MicroOpBits::B32);
    builder.emitOpUnaryReg(tail, MicroOp::BitwiseNot, MicroOpBits::B32);
    builder.emitLoadCondRegReg(tail, vA, MicroCond::Equal, MicroOpBits::B32);
    builder.emitLoadRegReg(returnReg, tail, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1)
        return Result::Error;
    if (countConditionalMoves(builder, MicroCond::Equal) != 1)
        return Result::Error;
    if (!anyJumpTargetsLabel(builder, restLabel))
        return Result::Error;

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

namespace
{
    // `if v < lo do return lo` followed by `return v`, the way the lowering
    // writes it: a compare, a jump over the early return, each return
    // materializing its value in the ABI's return register.
    void emitEarlyReturn(MicroBuilder& builder, const MicroReg v, const MicroReg lo, const MicroReg returnReg)
    {
        const MicroLabelRef restLabel = builder.createLabel();
        builder.emitCmpRegReg(v, lo, MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B32, restLabel);
        builder.emitLoadRegReg(returnReg, lo, MicroOpBits::B32);
        builder.emitRet();
        builder.placeLabel(restLabel);
    }
}

// The early return and the final return fold into one return fed by a move
// taken when the jump would not have been.
SWC_TEST_BEGIN(BranchSimplify_ConvertsEarlyReturnToCmov)
{
    const MicroReg returnReg = CallConv::get(CallConvKind::Swag).intReturn;
    const MicroReg v         = MicroReg::virtualIntReg(10);
    const MicroReg lo        = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    emitEarlyReturn(builder, v, lo, returnReg);
    builder.emitLoadRegReg(returnReg, v, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalMoves(builder, MicroCond::Less) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::Ret) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::Label) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A chain of two early returns folds from the bottom, one per sweep.
SWC_TEST_BEGIN(BranchSimplify_ConvertsEarlyReturnChainToCmovs)
{
    const MicroReg returnReg = CallConv::get(CallConvKind::Swag).intReturn;
    const MicroReg v         = MicroReg::virtualIntReg(10);
    const MicroReg lo        = MicroReg::virtualIntReg(11);
    const MicroReg hi        = MicroReg::virtualIntReg(12);
    MicroBuilder   builder(ctx);

    emitEarlyReturn(builder, v, lo, returnReg);
    emitEarlyReturn(builder, hi, v, returnReg);
    builder.emitLoadRegReg(returnReg, v, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));
    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalMoves(builder, MicroCond::Less) != 2)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::Ret) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The early return's value comes from memory the condition guards: the branch
// stays, or the load would run on the path that never reached it.
SWC_TEST_BEGIN(BranchSimplify_KeepsEarlyReturnWithGuardedLoad)
{
    const MicroReg      returnReg = CallConv::get(CallConvKind::Swag).intReturn;
    const MicroReg      v         = MicroReg::virtualIntReg(10);
    const MicroReg      lo        = MicroReg::virtualIntReg(11);
    const MicroReg      table     = MicroReg::virtualIntReg(12);
    MicroBuilder        builder(ctx);
    const MicroLabelRef restLabel = builder.createLabel();

    builder.emitCmpRegReg(v, lo, MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B32, restLabel);
    builder.emitLoadRegMem(returnReg, table, 8, MicroOpBits::B32);
    builder.emitRet();
    builder.placeLabel(restLabel);
    builder.emitLoadRegReg(returnReg, v, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::JumpCond) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::Ret) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The early path negates its value, which writes the flags: the compare is
// re-issued before the move.
SWC_TEST_BEGIN(BranchSimplify_SinksCompareBelowFlagWritingEarlyReturn)
{
    const MicroReg      returnReg = CallConv::get(CallConvKind::Swag).intReturn;
    const MicroReg      v         = MicroReg::virtualIntReg(10);
    const MicroReg      negated   = MicroReg::virtualIntReg(11);
    MicroBuilder        builder(ctx);
    const MicroLabelRef restLabel = builder.createLabel();

    builder.emitCmpRegImm(v, ApInt(uint64_t{0}, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B32, restLabel);
    builder.emitLoadRegReg(negated, v, MicroOpBits::B32);
    builder.emitOpUnaryReg(negated, MicroOp::Negate, MicroOpBits::B32);
    builder.emitLoadRegReg(returnReg, negated, MicroOpBits::B32);
    builder.emitRet();
    builder.placeLabel(restLabel);
    builder.emitLoadRegReg(returnReg, v, MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalMoves(builder, MicroCond::Less) != 1)
        return Result::Error;
    if (countInstructionsWithOpcode(builder, MicroInstrOpcode::JumpCond) != 0)
        return Result::Error;

    // The compare now sits right before the move, after the negation.
    bool seenNegate         = false;
    bool compareAfterNegate = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op == MicroInstrOpcode::OpUnaryReg)
            seenNegate = true;
        if (inst.op == MicroInstrOpcode::CmpRegImm && seenNegate)
            compareAfterNegate = true;
    }
    if (!compareAfterNegate)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(BranchSimplify_EarlyReturnChecksBothCompareInputs)
{
    constexpr MicroReg lhs     = MicroReg::virtualIntReg(10);
    constexpr MicroReg rhs     = MicroReg::virtualIntReg(11);
    constexpr MicroReg negated = MicroReg::virtualIntReg(12);
    constexpr MicroReg scratch = MicroReg::virtualIntReg(13);
    const MicroReg     result  = CallConv::get(CallConvKind::Swag).intReturn;
    for (const MicroReg tailDef : {scratch, lhs, rhs})
    {
        MicroBuilder builder(ctx);
        const auto   rest = builder.createLabel();
        builder.emitCmpRegReg(lhs, rhs, MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::GreaterOrEqual, MicroOpBits::B32, rest);
        builder.emitLoadRegReg(negated, lhs, MicroOpBits::B32);
        builder.emitOpUnaryReg(negated, MicroOp::Negate, MicroOpBits::B32);
        builder.emitLoadRegReg(result, negated, MicroOpBits::B32);
        builder.emitRet();
        builder.placeLabel(rest);
        builder.emitLoadRegImm(tailDef, ApInt(0, 64), MicroOpBits::B32);
        builder.emitLoadRegReg(result, lhs, MicroOpBits::B32);
        builder.emitRet();

        SWC_RESULT(runBranchSimplifyPass(builder));
        // The negation requires reissuing the compare. Either operand being
        // overwritten by the tail prevents that, even if it is the second one.
        const bool canConvert = tailDef == scratch;
        if (countConditionalMoves(builder, MicroCond::Less) != (canConvert ? 1 : 0))
            return Result::Error;
        if (countInstructionsWithOpcode(builder, MicroInstrOpcode::JumpCond) != (canConvert ? 0 : 1))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(BranchSimplify_InvertsJumpPairAfterImmediateJumpErasure)
{
    constexpr MicroReg  input = MicroReg::virtualIntReg(1);
    constexpr MicroReg  base  = MicroReg::virtualIntReg(2);
    MicroBuilder        builder(ctx);
    const MicroLabelRef next = builder.createLabel();
    const MicroLabelRef far  = builder.createLabel();
    builder.emitCmpRegImm(input, ApInt(0, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, next);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, far);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, next);
    builder.placeLabel(next);
    builder.emitLoadMemImm(base, 0, ApInt(1, 64), MicroOpBits::B64);
    builder.emitRet();
    builder.placeLabel(far);
    builder.emitLoadMemImm(base, 0, ApInt(2, 64), MicroOpBits::B64);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));
    if (countConditionalJumps(builder) != 1 || anyJumpTargetsLabel(builder, next))
        return Result::Error;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op != MicroInstrOpcode::JumpCond)
            continue;
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (ops[0].cpuCond != MicroCond::NotEqual || ops[2].valueU64 != far.get())
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(BranchSimplify_TriangleScratchPreservesAcceptedPlanOrder)
{
    for (const bool includeImmediate : {false, true})
    {
        constexpr MicroReg input = MicroReg::virtualIntReg(1);
        MicroBuilder       builder(ctx);
        const auto         rejected = builder.createLabel();
        builder.emitCmpRegImm(input, ApInt(0, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, rejected);
        // An 8-bit immediate body is not a cmov candidate.
        builder.emitLoadRegImm(MicroReg::virtualIntReg(900), ApInt(17, 8), MicroOpBits::B8);
        builder.placeLabel(rejected);

        const auto copied = builder.createLabel();
        builder.emitCmpRegImm(input, ApInt(1, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, copied);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(11), MicroReg::virtualIntReg(12), MicroOpBits::B64);
        builder.placeLabel(copied);
        if (includeImmediate)
        {
            const auto loaded = builder.createLabel();
            builder.emitCmpRegImm(input, ApInt(2, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B64, loaded);
            builder.emitLoadRegImm(MicroReg::virtualIntReg(13), ApInt(23, 64), MicroOpBits::B64);
            builder.placeLabel(loaded);
        }
        builder.emitLoadRegImm(MicroReg::virtualIntReg(1000), ApInt(99, 64), MicroOpBits::B64);
        builder.emitRet();

        SWC_RESULT(runBranchSimplifyPass(builder));
        if (countConditionalMoves(builder, MicroCond::NotEqual) != (includeImmediate ? 2 : 1))
            return Result::Error;
        bool foundScratch = false;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::LoadCondRegReg)
            {
                if (ops[0].reg == MicroReg::virtualIntReg(11) && ops[1].reg != MicroReg::virtualIntReg(12))
                    return Result::Error;
                if (ops[0].reg == MicroReg::virtualIntReg(13) && ops[1].reg != MicroReg::virtualIntReg(1001))
                    return Result::Error;
            }
            if (inst.op == MicroInstrOpcode::LoadRegImm && ops[0].reg.isVirtualInt() && ops[0].reg.index() > 1000)
            {
                if (foundScratch || ops[0].reg != MicroReg::virtualIntReg(1001) || ops[2].valueU64 != 23)
                    return Result::Error;
                foundScratch = true;
            }
        }
        if (foundScratch != includeImmediate)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(BranchSimplify_BooleanFusionChecksTakenFlags)
{
    for (const bool readsFlags : {false, true})
    {
        MicroBuilder       builder(ctx);
        constexpr MicroReg input   = MicroReg::virtualIntReg(1);
        constexpr MicroReg boolean = MicroReg::virtualIntReg(2);
        constexpr MicroReg output  = MicroReg::virtualIntReg(3);
        const auto         target  = builder.createLabel();
        const auto         next    = builder.createLabel();
        builder.emitCmpRegImm(input, ApInt(7, 64), MicroOpBits::B64);
        builder.emitSetCondReg(boolean, MicroCond::Below);
        builder.emitCmpRegImm(boolean, ApInt(0, 8), MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B64, target);
        builder.emitRet();
        builder.placeLabel(target);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, next);
        builder.placeLabel(next);
        if (!readsFlags)
            builder.emitCmpRegImm(input, ApInt(9, 64), MicroOpBits::B64);
        builder.emitSetCondReg(output, MicroCond::Above);
        builder.emitRet();

        SWC_RESULT(runBranchSimplifyPass(builder));
        bool hasBooleanCompare = false;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::CmpRegImm && inst.ops(builder.operands())[0].reg == boolean)
                hasBooleanCompare = true;
        }
        if (hasBooleanCompare != readsFlags)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(BranchSimplify_BooleanMoveFusionPreservesLaterFlags)
{
    for (const bool readsFlags : {false, true})
    {
        MicroBuilder       builder(ctx);
        constexpr MicroReg input   = MicroReg::virtualIntReg(1);
        constexpr MicroReg boolean = MicroReg::virtualIntReg(2);
        constexpr MicroReg output  = MicroReg::virtualIntReg(3);
        builder.emitCmpRegImm(input, ApInt(7, 64), MicroOpBits::B64);
        builder.emitSetCondReg(boolean, MicroCond::Below);
        builder.emitCmpRegImm(boolean, ApInt(0, 8), MicroOpBits::B8);
        builder.emitLoadCondRegReg(output, input, MicroCond::NotEqual, MicroOpBits::B64);
        if (!readsFlags)
            builder.emitCmpRegImm(input, ApInt(9, 64), MicroOpBits::B64);
        builder.emitSetCondReg(MicroReg::virtualIntReg(4), MicroCond::Above);
        builder.emitRet();

        SWC_RESULT(runBranchSimplifyPass(builder));
        bool hasBooleanCompare = false;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const auto* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::CmpRegImm && ops[0].reg == boolean)
                hasBooleanCompare = true;
            if (inst.op == MicroInstrOpcode::LoadCondRegReg &&
                ops[2].cpuCond != (readsFlags ? MicroCond::NotEqual : MicroCond::Below))
                return Result::Error;
        }
        if (hasBooleanCompare != readsFlags)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(BranchSimplify_RepeatedBooleanMovesStillFuse)
{
    MicroBuilder       builder(ctx);
    constexpr MicroReg input   = MicroReg::virtualIntReg(1);
    constexpr MicroReg boolean = MicroReg::virtualIntReg(2);
    builder.emitCmpRegImm(input, ApInt(7, 64), MicroOpBits::B64);
    builder.emitSetCondReg(boolean, MicroCond::Below);
    for (uint32_t i = 0; i < 3; ++i)
    {
        builder.emitCmpRegImm(boolean, ApInt(0, 8), MicroOpBits::B8);
        builder.emitLoadCondRegReg(MicroReg::virtualIntReg(3 + i), input, MicroCond::NotEqual, MicroOpBits::B64);
    }
    builder.emitRet();
    SWC_RESULT(runBranchSimplifyPass(builder));
    uint32_t moves = 0;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const auto* ops = inst.ops(builder.operands());
        if (inst.op == MicroInstrOpcode::CmpRegImm && ops[0].reg == boolean)
            return Result::Error;
        if (inst.op == MicroInstrOpcode::LoadCondRegReg)
        {
            ++moves;
            if (ops[2].cpuCond != MicroCond::Below)
                return Result::Error;
        }
    }
    return moves == 3 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

namespace
{
    // `c = 0; if a > b do <arm on c>` - the arm updates c and falls into the join.
    struct TriangleShape
    {
        MicroReg      result = MicroReg::virtualIntReg(12);
        MicroLabelRef join   = MicroLabelRef::invalid();
    };

    TriangleShape openTriangle(MicroBuilder& builder, const MicroReg lhs, const MicroReg rhs)
    {
        TriangleShape shape;
        shape.join = builder.createLabel();
        builder.emitLoadRegImm(shape.result, ApInt(5, 64), MicroOpBits::B64);
        builder.emitCmpRegReg(lhs, rhs, MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::LessOrEqual, MicroOpBits::B32, shape.join);
        return shape;
    }

    void closeTriangle(MicroBuilder& builder, const TriangleShape& shape)
    {
        builder.placeLabel(shape.join);
        builder.emitLoadRegReg(MicroReg::virtualIntReg(13), shape.result, MicroOpBits::B64);
        builder.emitRet();
    }
}

// `if a > b do c += 1` written as an address step and a copy: the arm runs on
// a renamed register and one move picks it when the skipped branch would not
// have been taken.
SWC_TEST_BEGIN(BranchSimplify_ConvertsConditionalUpdateToCmov)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    const MicroReg vT = MicroReg::virtualIntReg(14);
    MicroBuilder   builder(ctx);

    const TriangleShape shape = openTriangle(builder, vA, vB);
    builder.emitLoadAddressRegMem(vT, shape.result, 1, MicroOpBits::B64);
    builder.emitLoadRegReg(shape.result, vT, MicroOpBits::B64);
    closeTriangle(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countConditionalMoves(builder, MicroCond::Greater) != 1)
        return Result::Error;

    // Nothing in the arm writes the result any more; only the move does.
    for (const MicroInstr& inst : builder.instructions().view())
    {
        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if ((inst.op == MicroInstrOpcode::LoadRegReg || inst.op == MicroInstrOpcode::LoadAddrRegMem) && ops && ops[0].reg == shape.result)
            return Result::Error;
    }

    return Result::Continue;
}
SWC_TEST_END()

// An arm that writes the flags gets the compare re-issued in front of the move.
SWC_TEST_BEGIN(BranchSimplify_ConditionalUpdateReissuesCompare)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const TriangleShape shape = openTriangle(builder, vA, vB);
    builder.emitOpBinaryRegImm(shape.result, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    closeTriangle(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countConditionalMoves(builder, MicroCond::Greater) != 1)
        return Result::Error;

    // add, then compare, then move.
    bool sawAdd     = false;
    bool sawCompare = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op == MicroInstrOpcode::OpBinaryRegImm)
            sawAdd = true;
        else if (inst.op == MicroInstrOpcode::CmpRegReg)
            sawCompare = sawAdd;
        else if (inst.op == MicroInstrOpcode::LoadCondRegReg && !sawCompare)
            return Result::Error;
    }

    return Result::Continue;
}
SWC_TEST_END()

// A load may fault on the path that skipped it: the branch stays.
SWC_TEST_BEGIN(BranchSimplify_KeepsConditionalUpdateWithGuardedLoad)
{
    const MicroReg vA = MicroReg::virtualIntReg(10);
    const MicroReg vB = MicroReg::virtualIntReg(11);
    MicroBuilder   builder(ctx);

    const TriangleShape shape = openTriangle(builder, vA, vB);
    builder.emitLoadRegMem(shape.result, vA, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(shape.result, ApInt(3, 64), MicroOp::Add, MicroOpBits::B64);
    closeTriangle(builder, shape);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 1 || countInstructionsWithOpcode(builder, MicroInstrOpcode::LoadCondRegReg) != 0)
        return Result::Error;

    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // cmp v, C; sete t; r = t; je .end ... for each constant, the last one falling into .end
    void emitEqualityChain(MicroBuilder& builder, std::span<const uint64_t> constants)
    {
        const MicroReg base   = MicroReg::virtualIntReg(9);
        const MicroReg value  = MicroReg::virtualIntReg(10);
        const MicroReg result = MicroReg::virtualIntReg(11);
        const auto     end    = builder.createLabel();
        builder.emitLoadRegMem(value, base, 0, MicroOpBits::B32);
        for (size_t i = 0; i < constants.size(); ++i)
        {
            const MicroReg flag = MicroReg::virtualIntReg(static_cast<uint32_t>(20 + i));
            builder.emitCmpRegImm(value, ApInt(constants[i], 64), MicroOpBits::B32);
            builder.emitSetCondReg(flag, MicroCond::Equal);
            builder.emitLoadRegReg(result, flag, MicroOpBits::B8);
            if (i + 1 < constants.size())
                builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, end);
        }
        builder.placeLabel(end);
        builder.emitLoadZeroExtendRegReg(CallConv::get(CallConvKind::Swag).intReturn, result, MicroOpBits::B64, MicroOpBits::B8);
        builder.emitRet();
    }
}

SWC_TEST_BEGIN(BranchSimplify_EqualityChainBecomesBitTest)
{
    MicroBuilder             builder(ctx);
    const std::array<uint64_t, 4> constants = {32, 9, 10, 13};
    emitEqualityChain(builder, constants);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countLoadImmValue(builder, (1ULL << 32) | (1ULL << 9) | (1ULL << 10) | (1ULL << 13)) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    uint32_t countBinaryRegRegOps(const MicroBuilder& builder, MicroOp op)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::OpBinaryRegReg && inst.ops(builder.operands())[3].microOp == op)
                ++count;
        }
        return count;
    }

    // `c - '0' <= 9 or c - 'a' <= 5 or c - 'A' <= 5` once its ranges fold.
    // `storeInSecond` makes the second link write memory.
    void emitRangeChain(MicroBuilder& builder, bool storeInSecond)
    {
        constexpr uint64_t lows[]  = {0x30, 0x61, 0x41};
        constexpr uint64_t spans[] = {9, 5, 5};
        const MicroReg     base    = MicroReg::virtualIntReg(9);
        const MicroReg     value   = MicroReg::virtualIntReg(10);
        const MicroReg     result  = MicroReg::virtualIntReg(11);
        const auto         end     = builder.createLabel();
        builder.emitLoadRegMem(value, base, 0, MicroOpBits::B32);
        for (uint32_t i = 0; i < 3; ++i)
        {
            const MicroReg index = MicroReg::virtualIntReg(20 + i);
            const MicroReg flag  = MicroReg::virtualIntReg(30 + i);
            builder.emitLoadAddressRegMem(index, value, (0 - lows[i]), MicroOpBits::B32);
            if (storeInSecond && i == 1)
                builder.emitLoadMemReg(base, 8, index, MicroOpBits::B32);
            builder.emitCmpRegImm(index, ApInt(spans[i], 64), MicroOpBits::B32);
            builder.emitSetCondReg(flag, MicroCond::BelowOrEqual);
            builder.emitLoadRegReg(result, flag, MicroOpBits::B8);
            if (i < 2)
                builder.emitJumpToLabel(MicroCond::BelowOrEqual, MicroOpBits::B32, end);
        }
        builder.placeLabel(end);
        builder.emitLoadZeroExtendRegReg(CallConv::get(CallConvKind::Swag).intReturn, result, MicroOpBits::B64, MicroOpBits::B8);
        builder.emitRet();
    }
}

// Constants farther apart than a word are no bit test, but the short chain of
// compares still folds into one byte OR.
SWC_TEST_BEGIN(BranchSimplify_WideEqualityChainBecomesOr)
{
    MicroBuilder             builder(ctx);
    const std::array<uint64_t, 3> constants = {1, 40, 200};
    emitEqualityChain(builder, constants);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countBinaryRegRegOps(builder, MicroOp::Or) != 2 || countBinaryRegRegOps(builder, MicroOp::ShiftRight) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Range tests OR-ed by early exits run unconditionally.
SWC_TEST_BEGIN(BranchSimplify_RangeChainBecomesBranchless)
{
    MicroBuilder builder(ctx);
    emitRangeChain(builder, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countBinaryRegRegOps(builder, MicroOp::Or) != 2)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A link that writes memory must not run on the path that already left.
SWC_TEST_BEGIN(BranchSimplify_RangeChainWithStoreKept)
{
    MicroBuilder builder(ctx);
    emitRangeChain(builder, true);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // x > y ? 1 : -zext(x < y), the diamond `x > y ? 1 : (x < y ? -1 : 0)`
    // leaves. `plainElse` replaces the negated byte with a loaded value.
    void emitSignDiamond(MicroBuilder& builder, MicroCond branchCond, MicroCond lessCond, bool plainElse, bool mirrored = false)
    {
        const MicroReg base   = MicroReg::virtualIntReg(9);
        const MicroReg value  = MicroReg::virtualIntReg(10);
        const MicroReg other  = MicroReg::virtualIntReg(11);
        const MicroReg result = MicroReg::virtualIntReg(12);
        const MicroReg flag   = MicroReg::virtualIntReg(13);
        const MicroReg wide   = MicroReg::virtualIntReg(14);
        const auto     other_ = builder.createLabel();
        const auto     end    = builder.createLabel();
        builder.emitLoadRegMem(value, base, 0, MicroOpBits::B64);
        builder.emitLoadRegMem(other, base, 8, MicroOpBits::B64);
        builder.emitCmpRegReg(value, other, MicroOpBits::B64);
        builder.emitJumpToLabel(branchCond, MicroOpBits::B32, other_);
        builder.emitLoadRegImm(result, ApInt(mirrored ? 0xFFFFFFFFFFFFFFFF : 1, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, end);
        builder.placeLabel(other_);
        builder.emitCmpRegReg(value, other, MicroOpBits::B64);
        builder.emitSetCondReg(flag, lessCond);
        builder.emitLoadZeroExtendRegReg(wide, flag, MicroOpBits::B64, MicroOpBits::B8);
        if (plainElse)
            builder.emitLoadRegMem(wide, base, 16, MicroOpBits::B64);
        if (!mirrored)
            builder.emitOpUnaryReg(wide, MicroOp::Negate, MicroOpBits::B64);
        builder.emitLoadRegReg(result, wide, MicroOpBits::B64);
        builder.placeLabel(end);
        builder.emitLoadMemReg(base, 24, result, MicroOpBits::B64);
        builder.emitRet();
    }

    bool hasSignedByteExtend(const MicroBuilder& builder)
    {
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::LoadSignedExtRegReg && inst.ops(builder.operands())[3].opBits == MicroOpBits::B8)
                return true;
        }
        return false;
    }
}

// The signed three-way sign becomes setg - setl.
SWC_TEST_BEGIN(BranchSimplify_SignDiamondBecomesByteDifference)
{
    MicroBuilder builder(ctx);
    emitSignDiamond(builder, MicroCond::LessOrEqual, MicroCond::Less, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || !hasSignedByteExtend(builder))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The unsigned one becomes seta - setb.
SWC_TEST_BEGIN(BranchSimplify_UnsignedSignDiamondBecomesByteDifference)
{
    MicroBuilder builder(ctx);
    emitSignDiamond(builder, MicroCond::BelowOrEqual, MicroCond::Below, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || !hasSignedByteExtend(builder))
        return Result::Error;
    bool above = false;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op == MicroInstrOpcode::SetCondReg && inst.ops(builder.operands())[1].cpuCond == MicroCond::Above)
            above = true;
    }
    return above ? Result::Continue : Result::Error;
}
SWC_TEST_END()

// A mixed signed branch and unsigned byte is no sign.
SWC_TEST_BEGIN(BranchSimplify_MixedSignDiamondKept)
{
    MicroBuilder builder(ctx);
    emitSignDiamond(builder, MicroCond::LessOrEqual, MicroCond::Below, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (hasSignedByteExtend(builder))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// An arm that negates something else is no sign either.
SWC_TEST_BEGIN(BranchSimplify_SignDiamondWithOtherValueKept)
{
    MicroBuilder builder(ctx);
    emitSignDiamond(builder, MicroCond::LessOrEqual, MicroCond::Less, true);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (hasSignedByteExtend(builder))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // switch on a loaded key: `values[i]` for `keys[i]`, the default otherwise.
    // `returns` makes every arm return; otherwise they join after loading.
    void emitConstantSwitch(MicroBuilder& builder, std::span<const uint64_t> keys, std::span<const uint64_t> values, uint64_t fallback, bool returns, bool readArm, MicroOpBits keyBits = MicroOpBits::B32)
    {
        const MicroReg base   = MicroReg::virtualIntReg(9);
        const MicroReg key    = MicroReg::virtualIntReg(10);
        const MicroReg result = returns ? CallConv::get(CallConvKind::Swag).intReturn : MicroReg::virtualIntReg(11);
        SmallVector<MicroLabelRef> arms;
        for (size_t i = 0; i < keys.size(); ++i)
            arms.push_back(builder.createLabel());
        const auto fallbackLabel = builder.createLabel();
        const auto end           = builder.createLabel();

        builder.emitLoadRegMem(key, base, 0, keyBits);
        if (!returns)
            builder.emitLoadRegImm(result, ApInt(fallback, 64), MicroOpBits::B32);
        for (size_t i = 0; i < keys.size(); ++i)
        {
            builder.emitCmpRegImm(key, ApInt(keys[i], 64), keyBits);
            builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, arms[i]);
        }
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, returns ? fallbackLabel : end);
        for (size_t i = 0; i < keys.size(); ++i)
        {
            builder.placeLabel(arms[i]);
            if (readArm && i == 1)
                builder.emitLoadRegMem(result, base, 4, MicroOpBits::B32);
            else
                builder.emitLoadRegImm(result, ApInt(values[i], 64), MicroOpBits::B32);
            if (returns)
                builder.emitRet();
            else if (i + 1 < keys.size())
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, end);
        }
        if (returns)
        {
            builder.placeLabel(fallbackLabel);
            builder.emitLoadRegImm(result, ApInt(fallback, 64), MicroOpBits::B32);
            builder.emitRet();
        }
        builder.placeLabel(end);
        if (!returns)
            builder.emitLoadMemReg(base, 8, result, MicroOpBits::B32);
        builder.emitRet();
    }

    uint32_t countSelects(const MicroBuilder& builder)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::LoadCondRegReg)
                ++count;
        }
        return count;
    }
}

// Returning a small constant per case reads a constant table at the index.
SWC_TEST_BEGIN(BranchSimplify_ReturningSwitchBecomesLookupTable)
{
    MicroBuilder                  builder(ctx);
    const std::array<uint64_t, 3> keys   = {0, 1, 2};
    const std::array<uint64_t, 3> values = {1, 4, 9};
    emitConstantSwitch(builder, keys, values, 16, true, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countSelects(builder) != 1 || countTableAddresses(builder) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Cases that join after their loads take the default from before the chain;
// the negative entries are sign-extended from their packed width.
SWC_TEST_BEGIN(BranchSimplify_JoiningSwitchBecomesPackedTable)
{
    MicroBuilder                  builder(ctx);
    const std::array<uint64_t, 4> keys   = {0x30, 0x31, 0x35, 0x37};
    const std::array<uint64_t, 4> values = {0, 1, 5, 70};
    emitConstantSwitch(builder, keys, values, 0xFFFFFFFF, false, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countSelects(builder) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// An arm that loads from memory is no table entry.
SWC_TEST_BEGIN(BranchSimplify_SwitchWithLoadedArmKept)
{
    MicroBuilder                  builder(ctx);
    const std::array<uint64_t, 3> keys   = {0, 1, 2};
    const std::array<uint64_t, 3> values = {1, 4, 9};
    emitConstantSwitch(builder, keys, values, 16, true, true);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countSelects(builder) != 0 || countConditionalJumps(builder) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Keys spread over the whole word are no table, even when their span wraps.
SWC_TEST_BEGIN(BranchSimplify_WholeWordSwitchKept)
{
    MicroBuilder                  builder(ctx);
    const std::array<uint64_t, 3> keys   = {0, 1, 0xFFFFFFFFFFFFFFFF};
    const std::array<uint64_t, 3> values = {1, 2, 3};
    emitConstantSwitch(builder, keys, values, 0, true, false, MicroOpBits::B64);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countSelects(builder) != 0 || countConditionalJumps(builder) == 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// Entries too wide for one register still make a table, in memory.
SWC_TEST_BEGIN(BranchSimplify_WideSwitchBecomesLookupTable)
{
    MicroBuilder                  builder(ctx);
    const std::array<uint64_t, 4> keys   = {0, 1, 2, 3};
    const std::array<uint64_t, 4> values = {0x10000, 0x20000, 0x30000, 0x40000};
    emitConstantSwitch(builder, keys, values, 0x50000, true, false);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countSelects(builder) != 1 || countTableAddresses(builder) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// `case 3, 4, 5` lowered as a range joins the table.
SWC_TEST_BEGIN(BranchSimplify_SwitchWithCaseRangeBecomesPackedTable)
{
    const MicroReg base   = MicroReg::virtualIntReg(9);
    const MicroReg key    = MicroReg::virtualIntReg(10);
    const MicroReg result = CallConv::get(CallConvKind::Swag).intReturn;
    MicroBuilder   builder(ctx);
    const auto     first    = builder.createLabel();
    const auto     second   = builder.createLabel();
    const auto     skip     = builder.createLabel();
    const auto     fallback = builder.createLabel();

    builder.emitLoadRegMem(key, base, 0, MicroOpBits::B32);
    builder.emitCmpRegImm(key, ApInt(1, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, first);
    builder.emitCmpRegImm(key, ApInt(2, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, second);
    builder.emitCmpRegImm(key, ApInt(3, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, skip);
    builder.emitCmpRegImm(key, ApInt(5, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::BelowOrEqual, MicroOpBits::B32, first);
    builder.placeLabel(skip);
    builder.emitCmpRegImm(key, ApInt(8, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, second);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, fallback);
    builder.placeLabel(first);
    builder.emitLoadRegImm(result, ApInt(31, 64), MicroOpBits::B32);
    builder.emitRet();
    builder.placeLabel(second);
    builder.emitLoadRegImm(result, ApInt(28, 64), MicroOpBits::B32);
    builder.emitRet();
    builder.placeLabel(fallback);
    builder.emitLoadRegImm(result, ApInt(30, 64), MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countSelects(builder) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The last case may leave for the default on inequality and fall into its arm.
SWC_TEST_BEGIN(BranchSimplify_SwitchFallingIntoLastCaseBecomesPackedTable)
{
    const MicroReg base   = MicroReg::virtualIntReg(9);
    const MicroReg key    = MicroReg::virtualIntReg(10);
    const MicroReg result = CallConv::get(CallConvKind::Swag).intReturn;
    MicroBuilder   builder(ctx);
    const auto     first    = builder.createLabel();
    const auto     second   = builder.createLabel();
    const auto     fallback = builder.createLabel();

    builder.emitLoadRegMem(key, base, 0, MicroOpBits::B32);
    builder.emitCmpRegImm(key, ApInt(1, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, first);
    builder.emitCmpRegImm(key, ApInt(2, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, second);
    builder.emitCmpRegImm(key, ApInt(4, 64), MicroOpBits::B32);
    builder.emitJumpToLabel(MicroCond::NotEqual, MicroOpBits::B32, fallback);
    builder.placeLabel(first);
    builder.emitLoadRegImm(result, ApInt(31, 64), MicroOpBits::B32);
    builder.emitRet();
    builder.placeLabel(second);
    builder.emitLoadRegImm(result, ApInt(28, 64), MicroOpBits::B32);
    builder.emitRet();
    builder.placeLabel(fallback);
    builder.emitLoadRegImm(result, ApInt(30, 64), MicroOpBits::B32);
    builder.emitRet();

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || countSelects(builder) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// x < y ? -1 : (x > y ? 1 : 0) branches the other way and becomes the same
// byte difference.
SWC_TEST_BEGIN(BranchSimplify_MirroredSignDiamondBecomesByteDifference)
{
    MicroBuilder builder(ctx);
    emitSignDiamond(builder, MicroCond::GreaterOrEqual, MicroCond::Greater, false, true);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (countConditionalJumps(builder) != 0 || !hasSignedByteExtend(builder))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// The mirrored arm must test `x > y`: `x < y` there is another function.
SWC_TEST_BEGIN(BranchSimplify_MirroredSignDiamondWithLessKept)
{
    MicroBuilder builder(ctx);
    emitSignDiamond(builder, MicroCond::GreaterOrEqual, MicroCond::Less, false, true);

    SWC_RESULT(runBranchSimplifyPass(builder));

    if (hasSignedByteExtend(builder))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // comiss x, y ; j(cond) .E ; d = p ; jmp .J ; .E: d = q ; .J: ret
    void emitFloatSelect(MicroBuilder& builder, MicroCond cond, bool fallTakesLeft)
    {
        const MicroReg x = MicroReg::virtualFloatReg(10);
        const MicroReg y = MicroReg::virtualFloatReg(11);
        const MicroReg d = MicroReg::virtualFloatReg(12);

        const MicroLabelRef elseLabel = builder.createLabel();
        const MicroLabelRef joinLabel = builder.createLabel();
        builder.emitCmpRegReg(x, y, MicroOpBits::B32);
        builder.emitJumpToLabel(cond, MicroOpBits::B32, elseLabel);
        builder.emitLoadRegReg(d, fallTakesLeft ? x : y, MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, joinLabel);
        builder.placeLabel(elseLabel);
        builder.emitLoadRegReg(d, fallTakesLeft ? y : x, MicroOpBits::B32);
        builder.placeLabel(joinLabel);
        builder.emitLoadRegReg(CallConv::get(CallConvKind::Swag).floatReturn, d, MicroOpBits::B32);
        builder.emitRet();
    }

    MicroOp floatSelectOp(const MicroBuilder& builder)
    {
        for (const MicroInstr& inst : builder.instructions().view())
        {
            const MicroInstrOperand* ops = inst.ops(builder.operands());
            if (inst.op == MicroInstrOpcode::OpBinaryRegReg && (ops[3].microOp == MicroOp::FloatMax || ops[3].microOp == MicroOp::FloatMin))
                return ops[3].microOp;
        }
        return MicroOp::Move;
    }
}

// x > y ? x : y is maxss, x > y ? y : x minss.
SWC_TEST_BEGIN(BranchSimplify_FloatSelectOfComparedValues_BecomesMinMax)
{
    {
        MicroBuilder builder(ctx);
        emitFloatSelect(builder, MicroCond::BelowOrEqual, true);
        SWC_RESULT(runBranchSimplifyPass(builder));
        if (floatSelectOp(builder) != MicroOp::FloatMax || countConditionalJumps(builder) != 0)
            return Result::Error;
    }
    {
        MicroBuilder builder(ctx);
        emitFloatSelect(builder, MicroCond::BelowOrEqual, false);
        SWC_RESULT(runBranchSimplifyPass(builder));
        if (floatSelectOp(builder) != MicroOp::FloatMin || countConditionalJumps(builder) != 0)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// x >= y ? x : y keeps x on equal values, which maxss would not.
SWC_TEST_BEGIN(BranchSimplify_FloatSelectOnNonStrictTest_Kept)
{
    MicroBuilder builder(ctx);
    emitFloatSelect(builder, MicroCond::Below, true);
    SWC_RESULT(runBranchSimplifyPass(builder));
    if (floatSelectOp(builder) != MicroOp::Move)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // `links` short-circuit `and` links, each `cmp ; setge T ; D = T ; jl .J`,
    // a last `cmp ; setl T ; D = T`, and `.J: rax = D ; ret`.
    void emitAndChainReturn(MicroBuilder& builder, uint32_t links)
    {
        constexpr MicroReg result = MicroReg::virtualIntReg(1);
        const MicroLabelRef join  = builder.createLabel();
        for (uint32_t link = 0; link < links; ++link)
        {
            const MicroReg left  = MicroReg::virtualIntReg(10 + link * 3);
            const MicroReg right = MicroReg::virtualIntReg(11 + link * 3);
            const MicroReg flag  = MicroReg::virtualIntReg(12 + link * 3);
            builder.emitLoadRegMem(left, MicroReg::intReg(1), link * 8, MicroOpBits::B32);
            builder.emitLoadRegMem(right, MicroReg::intReg(1), link * 8 + 4, MicroOpBits::B32);
            builder.emitCmpRegReg(left, right, MicroOpBits::B32);
            builder.emitSetCondReg(flag, MicroCond::GreaterOrEqual);
            builder.emitLoadRegReg(result, flag, MicroOpBits::B8);
            builder.emitJumpToLabel(MicroCond::Less, MicroOpBits::B32, join);
        }
        constexpr MicroReg lastFlag = MicroReg::virtualIntReg(99);
        builder.emitCmpRegReg(MicroReg::intReg(2), MicroReg::intReg(8), MicroOpBits::B32);
        builder.emitSetCondReg(lastFlag, MicroCond::Less);
        builder.emitLoadRegReg(result, lastFlag, MicroOpBits::B8);
        builder.placeLabel(join);
        builder.emitLoadRegReg(MicroReg::intReg(0), result, MicroOpBits::B8);
        builder.emitRet();
    }

    Result runLateBranchSimplifyPass(MicroBuilder& builder)
    {
        MicroBranchSimplifyPass pass(true);
        MicroPassManager        passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }
}

// Two exits pin the result to zero: they go to one block that sets it.
SWC_TEST_BEGIN(BranchSimplify_ShortCircuitExitsTakeTheirConstant)
{
    MicroBuilder builder(ctx);
    emitAndChainReturn(builder, 2);
    SWC_RESULT(runLateBranchSimplifyPass(builder));
    if (countLoadImmValue(builder, 0) != 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// One exit does not pay for the block.
SWC_TEST_BEGIN(BranchSimplify_SingleShortCircuitExitKept)
{
    MicroBuilder builder(ctx);
    emitAndChainReturn(builder, 1);
    SWC_RESULT(runLateBranchSimplifyPass(builder));
    if (countLoadImmValue(builder, 0) != 0)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

namespace
{
    // cmp ; jae .E ; D = [base] (or D += [base]) ; jmp .J ; .E: D = 0 (or clear D) ; .J: store D ; ret
    void emitLoadOrZeroDiamond(MicroBuilder& builder, bool thenReadsResult, bool clearElse = false)
    {
        constexpr MicroReg result = MicroReg::virtualIntReg(1);
        constexpr MicroReg base   = MicroReg::virtualIntReg(2);
        const MicroLabelRef other = builder.createLabel();
        const MicroLabelRef join  = builder.createLabel();
        builder.emitLoadRegMem(base, MicroReg::intReg(1), 0, MicroOpBits::B64);
        builder.emitLoadRegMem(result, MicroReg::intReg(1), 8, MicroOpBits::B64);
        builder.emitCmpRegReg(MicroReg::intReg(2), MicroReg::intReg(8), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::AboveOrEqual, MicroOpBits::B32, other);
        if (thenReadsResult)
            builder.emitOpBinaryRegMem(result, base, 0, MicroOp::Add, MicroOpBits::B32);
        else
            builder.emitLoadRegMem(result, base, 0, MicroOpBits::B32);
        builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, join);
        builder.placeLabel(other);
        if (clearElse)
            builder.emitClearReg(result, MicroOpBits::B64);
        else
            builder.emitLoadRegImm(result, ApInt(0, 64), MicroOpBits::B32);
        builder.placeLabel(join);
        builder.emitLoadMemReg(MicroReg::intReg(1), 16, result, MicroOpBits::B32);
        builder.emitRet();
    }

    uint32_t countUnconditionalJumps(const MicroBuilder& builder)
    {
        uint32_t count = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::JumpCond && inst.ops(builder.operands())[0].cpuCond == MicroCond::Unconditional)
                ++count;
        }
        return count;
    }
}

// The zero arm runs before the branch, and the jump over it goes.
SWC_TEST_BEGIN(BranchSimplify_CheapElseArmSpeculated)
{
    MicroBuilder builder(ctx);
    emitLoadOrZeroDiamond(builder, false);
    SWC_RESULT(runLateBranchSimplifyPass(builder));
    return countUnconditionalJumps(builder) == 0 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

// A cleared else arm moves as a zero load: an xor between the compare and its
// jump would decide the jump.
SWC_TEST_BEGIN(BranchSimplify_SpeculatedClearKeepsFlags)
{
    MicroBuilder builder(ctx);
    emitLoadOrZeroDiamond(builder, false, true);
    SWC_RESULT(runLateBranchSimplifyPass(builder));
    if (countUnconditionalJumps(builder) != 0)
        return Result::Error;
    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op == MicroInstrOpcode::ClearReg)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

// A then arm that reads the result needs it untouched: the diamond stays.
SWC_TEST_BEGIN(BranchSimplify_ElseArmKeptWhenThenReadsResult)
{
    MicroBuilder builder(ctx);
    emitLoadOrZeroDiamond(builder, true);
    SWC_RESULT(runLateBranchSimplifyPass(builder));
    return countUnconditionalJumps(builder) == 1 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

namespace
{
    // cmp C, D ; seta ; R = T ; jbe .J ; cmp D, N ; seta ; R = T' ; .J: rax = R ; ret
    void emitFloatRangeAnd(MicroBuilder& builder, uint64_t negatedBits)
    {
        constexpr MicroReg value    = MicroReg::virtualFloatReg(1);
        constexpr MicroReg limit    = MicroReg::virtualFloatReg(2);
        constexpr MicroReg negLimit = MicroReg::virtualFloatReg(3);
        constexpr MicroReg result   = MicroReg::virtualIntReg(1);
        constexpr MicroReg first    = MicroReg::virtualIntReg(2);
        constexpr MicroReg second   = MicroReg::virtualIntReg(3);
        const MicroLabelRef join    = builder.createLabel();
        builder.emitLoadRegMem(value, MicroReg::intReg(1), 0, MicroOpBits::B32);
        builder.emitLoadRegImm(limit, ApInt(0x3A83126F, 64), MicroOpBits::B32);
        builder.emitCmpRegReg(limit, value, MicroOpBits::B32);
        builder.emitSetCondReg(first, MicroCond::Above);
        builder.emitLoadRegReg(result, first, MicroOpBits::B8);
        builder.emitJumpToLabel(MicroCond::BelowOrEqual, MicroOpBits::B32, join);
        builder.emitLoadRegImm(negLimit, ApInt(negatedBits, 64), MicroOpBits::B32);
        builder.emitCmpRegReg(value, negLimit, MicroOpBits::B32);
        builder.emitSetCondReg(second, MicroCond::Above);
        builder.emitLoadRegReg(result, second, MicroOpBits::B8);
        builder.placeLabel(join);
        builder.emitLoadRegReg(MicroReg::intReg(0), result, MicroOpBits::B8);
        builder.emitRet();
    }

    bool hasFloatAnd(const MicroBuilder& builder)
    {
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == MicroInstrOpcode::OpBinaryRegMem && inst.ops(builder.operands())[3].microOp == MicroOp::FloatAnd)
                return true;
        }
        return false;
    }
}

// `d < c and d > -c` tests |d| once.
SWC_TEST_BEGIN(BranchSimplify_FloatRangeBecomesAbsoluteTest)
{
    MicroBuilder builder(ctx);
    emitFloatRangeAnd(builder, 0xBA83126F);
    SWC_RESULT(runLateBranchSimplifyPass(builder));
    return hasFloatAnd(builder) && countConditionalJumps(builder) == 0 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

// Bounds that are not each other's negation keep both tests.
SWC_TEST_BEGIN(BranchSimplify_UnbalancedFloatRangeKept)
{
    MicroBuilder builder(ctx);
    emitFloatRangeAnd(builder, 0xBA000000);
    SWC_RESULT(runLateBranchSimplifyPass(builder));
    return !hasFloatAnd(builder) && countConditionalJumps(builder) == 1 ? Result::Continue : Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
