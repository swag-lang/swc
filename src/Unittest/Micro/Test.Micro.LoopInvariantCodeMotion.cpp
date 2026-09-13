#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/Passes/Pass.LoopInvariantCodeMotion.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHelpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    std::vector<uint8_t> reachableWithoutInstruction(const MicroControlFlowGraph& cfg, const uint32_t excluded, const uint32_t entry = 0)
    {
        std::vector<uint8_t>  reachable(cfg.instructionCount(), 0);
        std::vector<uint32_t> pending;
        if (excluded != entry && entry < reachable.size())
        {
            reachable[entry] = 1;
            pending.push_back(entry);
        }
        while (!pending.empty())
        {
            const uint32_t current = pending.back();
            pending.pop_back();
            for (const uint32_t successor : cfg.successors(current))
            {
                if (successor != excluded && !reachable[successor])
                {
                    reachable[successor] = 1;
                    pending.push_back(successor);
                }
            }
        }
        return reachable;
    }

    Result runLicmPass(MicroBuilder& builder)
    {
        MicroLoopInvariantCodeMotionPass pass;
        MicroPassManager                 passManager;
        passManager.addStartPass(pass);

        MicroPassContext passContext;
        passContext.callConvKind = CallConvKind::Swag;
        return builder.runPasses(passManager, nullptr, passContext);
    }

    // Position of the first instruction with this opcode, or UINT32_MAX.
    uint32_t firstPositionOf(const MicroBuilder& builder, MicroInstrOpcode op)
    {
        uint32_t position = 0;
        for (const MicroInstr& inst : builder.instructions().view())
        {
            if (inst.op == op)
                return position;
            ++position;
        }

        return std::numeric_limits<uint32_t>::max();
    }

    // A counted loop reading one word through a pointer parameter. The load
    // is emitted with `emitLoad`, so the same shape can carry a plain or a
    // volatile load.
    template<typename EmitLoad>
    void buildPollingLoop(MicroBuilder& builder, EmitLoad emitLoad)
    {
        constexpr MicroReg rcx   = MicroReg::intReg(2);
        constexpr MicroReg rax   = MicroReg::intReg(0);
        constexpr MicroReg base  = MicroReg::virtualIntReg(1);
        constexpr MicroReg count = MicroReg::virtualIntReg(2);
        constexpr MicroReg value = MicroReg::virtualIntReg(3);
        constexpr MicroReg acc   = MicroReg::virtualIntReg(4);

        const MicroLabelRef loopLabel = builder.createLabel();
        builder.emitLoadRegReg(base, rcx, MicroOpBits::B64);
        builder.emitLoadRegImm(count, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.emitLoadRegImm(acc, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.placeLabel(loopLabel);
        emitLoad(builder, value, base);
        builder.emitOpBinaryRegReg(acc, value, MicroOp::Add, MicroOpBits::B64);
        builder.emitOpBinaryRegImm(count, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(count, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loopLabel);
        builder.emitLoadRegReg(rax, acc, MicroOpBits::B64);
        builder.emitRet();
    }
}

SWC_TEST_BEGIN(MicroDominators_MatchReachabilityWithANodeRemoved)
{
    constexpr MicroReg  value = MicroReg::virtualIntReg(1);
    MicroBuilder        builder(ctx);
    const MicroLabelRef left  = builder.createLabel();
    const MicroLabelRef right = builder.createLabel();
    const MicroLabelRef join  = builder.createLabel();
    builder.emitLoadRegImm(value, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitCmpRegImm(value, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, right);
    builder.placeLabel(left);
    builder.emitOpBinaryRegImm(value, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, join);
    builder.placeLabel(right);
    builder.emitOpBinaryRegImm(value, ApInt(uint64_t{2}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(value, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, left);
    builder.placeLabel(join);
    builder.emitCmpRegImm(value, ApInt(uint64_t{8}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, right);
    builder.emitRet();
    builder.emitLoadRegImm(value, ApInt(uint64_t{42}, 64), MicroOpBits::B64);
    builder.emitRet();

    const MicroControlFlowGraph& cfg       = builder.controlFlowGraph();
    const auto                   dom       = MicroPassHelpers::computeInstructionDominators(cfg, 0);
    const auto                   reachable = reachableWithoutInstruction(cfg, UINT32_MAX);
    for (uint32_t candidate = 0; candidate <= cfg.instructionCount(); ++candidate)
    {
        const auto without = reachableWithoutInstruction(cfg, candidate);
        for (uint32_t node = 0; node < cfg.instructionCount(); ++node)
        {
            const bool expected = reachable[node] && !without[node];
            if (dom.dominates(candidate, node) != expected)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

// Control: a load nothing in the loop can alias moves to the preheader.
SWC_TEST_BEGIN(LICM_HoistsInvariantLoad)
{
    MicroBuilder builder(ctx);
    buildPollingLoop(builder, [](MicroBuilder& b, MicroReg value, MicroReg base) {
        b.emitLoadRegMem(value, base, 8, MicroOpBits::B64);
    });

    SWC_RESULT(runLicmPass(builder));

    if (firstPositionOf(builder, MicroInstrOpcode::LoadRegMem) > firstPositionOf(builder, MicroInstrOpcode::Label))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A scalar broadcast into a vector register, from a value the loop never
// writes, moves to the preheader even with one reader: rebuilding it costs a
// lane move and a shuffle per iteration.
SWC_TEST_BEGIN(LICM_HoistsSingleUseLaneBroadcast)
{
    constexpr MicroReg rcx   = MicroReg::intReg(2);
    constexpr MicroReg rdx   = MicroReg::intReg(3);
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg count = MicroReg::virtualIntReg(2);
    constexpr MicroReg word  = MicroReg::virtualIntReg(3);
    constexpr MicroReg lane  = MicroReg::virtualFloatReg(1);
    constexpr MicroReg lanes = MicroReg::virtualFloatReg(2);
    constexpr MicroReg row   = MicroReg::virtualFloatReg(3);
    constexpr MicroReg sum   = MicroReg::virtualFloatReg(4);
    MicroBuilder       builder(ctx);

    const MicroLabelRef loopLabel = builder.createLabel();
    builder.emitLoadRegReg(base, rcx, MicroOpBits::B64);
    builder.emitLoadRegReg(word, rdx, MicroOpBits::B32);
    builder.emitLoadRegImm(count, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
    builder.placeLabel(loopLabel);
    builder.emitLoadVecRegMem(row, base, 0, MicroOpBits::B128);
    builder.emitLoadRegReg(lane, word, MicroOpBits::B32);
    builder.emitVecShuffleRegRegImm(lanes, lane, 0, MicroOpBits::B128);
    builder.emitOpBinaryRegRegReg(sum, row, lanes, MicroOp::VecAdd32, MicroOpBits::B128);
    builder.emitStoreVecMemReg(base, 0, sum, MicroOpBits::B128);
    builder.emitOpBinaryRegImm(base, ApInt(uint64_t{16}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(count, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitCmpRegImm(count, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loopLabel);
    builder.emitRet();

    SWC_RESULT(runLicmPass(builder));

    const uint32_t labelPosition = firstPositionOf(builder, MicroInstrOpcode::Label);
    if (firstPositionOf(builder, MicroInstrOpcode::VecShuffleRegRegImm) > labelPosition)
        return Result::Error;
    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::VecShuffleRegRegImm) != 1)
        return Result::Error;
    if (firstPositionOf(builder, MicroInstrOpcode::LoadVecRegMem) < labelPosition)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

// A volatile load reads memory on every iteration: the same loop keeps it.
SWC_TEST_BEGIN(LICM_KeepsVolatileLoadInLoop)
{
    MicroBuilder builder(ctx);
    buildPollingLoop(builder, [](MicroBuilder& b, MicroReg value, MicroReg base) {
        b.emitLoadVolatileRegMem(value, base, 8, MicroOpBits::B64);
    });

    SWC_RESULT(runLicmPass(builder));

    if (Backend::Unittest::countOpcode(builder, MicroInstrOpcode::LoadVolatileRegMem) != 1)
        return Result::Error;
    if (firstPositionOf(builder, MicroInstrOpcode::LoadVolatileRegMem) < firstPositionOf(builder, MicroInstrOpcode::Label))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(LICM_HoistsFloatConversionAcrossCallWithLiveIntegerFlags)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        constexpr MicroReg  base  = MicroReg::virtualIntReg(1);
        constexpr MicroReg  count = MicroReg::virtualIntReg(2);
        constexpr MicroReg  word  = MicroReg::virtualIntReg(3);
        constexpr MicroReg  flag  = MicroReg::virtualIntReg(4);
        constexpr MicroReg  value = MicroReg::virtualFloatReg(1);
        MicroBuilder        builder(ctx);
        const MicroLabelRef loop = builder.createLabel();
        builder.emitLoadRegReg(base, MicroReg::intReg(2), MicroOpBits::B64);
        builder.emitLoadRegReg(word, MicroReg::intReg(3), bits);
        builder.emitLoadRegImm(count, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.emitCmpRegImm(word, ApInt(uint64_t{0}, 64), bits);
        builder.placeLabel(loop);
        builder.emitClearReg(value, bits);
        builder.emitOpBinaryRegReg(value, word, MicroOp::ConvertIntToFloat, bits);
        builder.emitSetCondReg(flag, MicroCond::Equal);
        builder.emitLoadMemReg(base, 0, value, bits);
        builder.emitLoadMemReg(base, 8, value, bits);
        builder.emitLoadMemReg(base, 16, flag, MicroOpBits::B8);
        builder.emitCallReg(MicroReg::intReg(0), CallConvKind::Swag);
        builder.emitOpBinaryRegImm(count, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(count, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loop);
        builder.emitRet();
        SWC_RESULT(runLicmPass(builder));
        const uint32_t label = firstPositionOf(builder, MicroInstrOpcode::Label);
        if (firstPositionOf(builder, MicroInstrOpcode::ClearReg) >= label ||
            firstPositionOf(builder, MicroInstrOpcode::OpBinaryRegReg) >= label ||
            firstPositionOf(builder, MicroInstrOpcode::SetCondReg) <= label)
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(LICM_KeepsIntegerClearWhenFlagsAreLiveAtEitherSite)
{
    for (const bool liveAtEntry : {false, true})
    {
        constexpr MicroReg  base  = MicroReg::virtualIntReg(1);
        constexpr MicroReg  count = MicroReg::virtualIntReg(2);
        constexpr MicroReg  value = MicroReg::virtualIntReg(3);
        constexpr MicroReg  flag  = MicroReg::virtualIntReg(4);
        MicroBuilder        builder(ctx);
        const MicroLabelRef loop = builder.createLabel();
        builder.emitLoadRegReg(base, MicroReg::intReg(2), MicroOpBits::B64);
        builder.emitLoadRegImm(count, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.emitCmpRegImm(base, ApInt(uint64_t{0}, 64), MicroOpBits::B64);
        builder.placeLabel(loop);
        if (liveAtEntry)
            builder.emitSetCondReg(flag, MicroCond::Equal);
        builder.emitClearReg(value, MicroOpBits::B64);
        if (!liveAtEntry)
            builder.emitSetCondReg(flag, MicroCond::Equal);
        builder.emitLoadMemReg(base, 0, value, MicroOpBits::B64);
        builder.emitLoadMemReg(base, 8, value, MicroOpBits::B64);
        builder.emitLoadMemReg(base, 16, flag, MicroOpBits::B8);
        builder.emitOpBinaryRegImm(count, ApInt(uint64_t{1}, 64), MicroOp::Add, MicroOpBits::B64);
        builder.emitCmpRegImm(count, ApInt(uint64_t{4}, 64), MicroOpBits::B64);
        builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loop);
        builder.emitRet();
        SWC_RESULT(runLicmPass(builder));
        if (firstPositionOf(builder, MicroInstrOpcode::ClearReg) <= firstPositionOf(builder, MicroInstrOpcode::Label))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(LICM_HoistsScalarLiteralLoadsButKeepsZeroLocal)
{
    for (const MicroOpBits bits : {MicroOpBits::B32, MicroOpBits::B64})
    {
        for (const bool zero : {false, true})
        {
            constexpr MicroReg  base    = MicroReg::virtualIntReg(1);
            constexpr MicroReg  count   = MicroReg::virtualIntReg(2);
            constexpr MicroReg  value   = MicroReg::virtualFloatReg(1);
            constexpr MicroReg  literal = MicroReg::virtualFloatReg(2);
            const uint64_t      half    = bits == MicroOpBits::B32 ? 0x3F000000ULL : 0x3FE0000000000000ULL;
            MicroBuilder        builder(ctx);
            const MicroLabelRef loop = builder.createLabel();
            builder.emitLoadRegReg(base, MicroReg::intReg(2), MicroOpBits::B64);
            builder.emitLoadRegImm(count, ApInt(0, 64), MicroOpBits::B64);
            builder.placeLabel(loop);
            builder.emitLoadRegMem(value, base, 0, bits);
            builder.emitLoadRegImm(literal, ApInt(zero ? 0 : half, 64), bits);
            builder.emitOpBinaryRegReg(value, literal, MicroOp::FloatMultiply, bits);
            builder.emitLoadMemReg(base, 0, value, bits);
            builder.emitOpBinaryRegImm(base, ApInt(getNumBits(bits) / 8, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitOpBinaryRegImm(count, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
            builder.emitCmpRegImm(count, ApInt(4, 64), MicroOpBits::B64);
            builder.emitJumpToLabel(MicroCond::Below, MicroOpBits::B32, loop);
            builder.emitRet();
            SWC_RESULT(runLicmPass(builder));

            const uint32_t header   = firstPositionOf(builder, MicroInstrOpcode::Label);
            uint32_t       position = 0;
            bool           found    = false;
            for (const MicroInstr& inst : builder.instructions().view())
            {
                const MicroInstrOperand* ops = inst.ops(builder.operands());
                if (inst.op == MicroInstrOpcode::LoadRegImm && ops[0].reg == literal)
                {
                    found = true;
                    if ((position < header) == zero)
                        return Result::Error;
                }
                ++position;
            }
            if (!found)
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroDomTree_MatchesPathsThroughDiamondAndLoop)
{
    MicroBuilder        builder(ctx);
    const MicroLabelRef loop  = builder.createLabel();
    const MicroLabelRef right = builder.createLabel();
    const MicroLabelRef join  = builder.createLabel();
    builder.placeLabel(loop);
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, right);
    builder.emitClearReg(MicroReg::virtualIntReg(1), MicroOpBits::B64);
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B64, join);
    builder.placeLabel(right);
    builder.emitClearReg(MicroReg::virtualIntReg(2), MicroOpBits::B64);
    builder.placeLabel(join);
    builder.emitJumpToLabel(MicroCond::NotZero, MicroOpBits::B64, loop);
    builder.emitRet();
    builder.emitClearReg(MicroReg::virtualIntReg(3), MicroOpBits::B64);
    builder.emitRet();

    const auto& cfg = builder.controlFlowGraph();
    const auto  n   = cfg.instructionCount();
    for (uint32_t entry = 0; entry < n; ++entry)
    {
        const auto dom       = MicroPassHelpers::computeInstructionDominators(cfg, entry);
        const auto reachable = reachableWithoutInstruction(cfg, n, entry);
        for (uint32_t a = 0; a < n; ++a)
        {
            // A dominates B precisely when removing A leaves no entry-to-B path.
            // Try every entry, including roots after unreachable instructions.
            const auto without = reachableWithoutInstruction(cfg, a, entry);
            if (dom.reachable(a) != (reachable[a] != 0))
                return Result::Error;
            for (uint32_t b = 0; b < n; ++b)
            {
                const bool expected = reachable[a] && reachable[b] && !without[b];
                if (dom.dominates(a, b) != expected)
                    return Result::Error;
            }
        }
        if (dom.dominates(n, entry) || dom.dominates(entry, n))
            return Result::Error;
    }
    const auto invalid = MicroPassHelpers::computeInstructionDominators(cfg, n);
    if (invalid.reachable(0) || invalid.dominates(0, 0))
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
