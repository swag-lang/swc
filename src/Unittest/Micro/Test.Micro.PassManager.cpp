#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Backend/Micro/MicroVerify.h"
#include "Main/Stats.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct Rewrite
    {
        uint64_t from;
        uint64_t to;
    };

    class ImmediateRewritePass final : public MicroPass
    {
    public:
        ImmediateRewritePass(MicroInstrRef ref, std::span<const Rewrite> rewrites, bool laterSweepsOnly = false) :
            ref_(ref),
            rewrites_(rewrites),
            laterSweepsOnly_(laterSweepsOnly)
        {
        }

        std::string_view name() const override { return "test-immediate-rewrite"; }

        Result run(MicroPassContext& context) override
        {
            ++calls;
            if (laterSweepsOnly_ && context.isFirstOptimizationSweep)
                return Result::Continue;
            auto* ops = context.instructions->ptr(ref_)->ops(*context.operands);
            for (const auto& rewrite : rewrites_)
            {
                if (ops[2].immediateValue().as64() != rewrite.from)
                    continue;
                ops[2].setImmediateValue(ApInt(rewrite.to, 64));
                context.passChanged = true;
                break;
            }
            return Result::Continue;
        }

        uint32_t calls = 0;

    private:
        MicroInstrRef            ref_;
        std::span<const Rewrite> rewrites_;
        bool                     laterSweepsOnly_;
    };

    // Moves the same immediate one step further on every sweep, so the loop keeps seeing a
    // function it has not seen before and can never settle.
    class NeverSettlingPass final : public MicroPass
    {
    public:
        explicit NeverSettlingPass(MicroInstrRef ref) :
            ref_(ref)
        {
        }

        std::string_view name() const override { return "test-never-settling"; }

        Result run(MicroPassContext& context) override
        {
            ++calls;
            auto* ops = context.instructions->ptr(ref_)->ops(*context.operands);
            ops[2].setImmediateValue(ApInt(ops[2].immediateValue().as64() + 1, 64));
            context.passChanged = true;
            return Result::Continue;
        }

        uint32_t calls = 0;

    private:
        MicroInstrRef ref_;
    };

    // The reported error belongs to the fixture, not to the run that hosts it.
    class RestoreErrorCount
    {
    public:
        RestoreErrorCount() :
            saved_(Stats::get().numErrors.load(std::memory_order_relaxed))
        {
        }

        ~RestoreErrorCount()
        {
            Stats::get().numErrors.store(saved_, std::memory_order_relaxed);
        }

    private:
        size_t saved_;
    };
}

SWC_TEST_BEGIN(MicroPassManager_PostRa_RechecksSuffixAfterEachMutation)
{
    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(0, 64), MicroOpBits::B64);
    const auto value = builder.instructions().lastInstructionRef();
    builder.emitRet();

    constexpr Rewrite    steps[] = {{0, 1}, {1, 2}, {2, 3}};
    ImmediateRewritePass prefix(value, steps);
    ImmediateRewritePass suffix(value, {});
    MicroPassManager     manager;
    manager.addPostRaOptimPass(prefix);
    manager.addPostRaOptimPass(suffix);
    MicroPassContext passContext;
    passContext.callConvKind               = CallConvKind::Swag;
    passContext.optimizationIterationLimit = 8;
    SWC_RESULT(builder.runPasses(manager, nullptr, passContext));

    if (builder.instructions().ptr(value)->ops(builder.operands())[2].immediateValue().as64() != 3)
        return Result::Error;
    // Every mutation reactivates the suffix; only the final unchanged sweep skips it.
    if (prefix.calls != 4 || suffix.calls != 3)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPassManager_PostRa_RechecksSuffixWhenFirstSweepPolicyChanges)
{
    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(0, 64), MicroOpBits::B64);
    const auto value = builder.instructions().lastInstructionRef();
    builder.emitRet();

    constexpr Rewrite    first[] = {{0, 1}};
    constexpr Rewrite    later[] = {{1, 2}};
    ImmediateRewritePass prefix(value, first);
    ImmediateRewritePass suffix(value, later, true);
    MicroPassManager     manager;
    manager.addPostRaOptimPass(prefix);
    manager.addPostRaOptimPass(suffix);
    MicroPassContext passContext;
    passContext.callConvKind               = CallConvKind::Swag;
    passContext.optimizationIterationLimit = 8;
    SWC_RESULT(builder.runPasses(manager, nullptr, passContext));

    if (builder.instructions().ptr(value)->ops(builder.operands())[2].immediateValue().as64() != 2)
        return Result::Error;
    if (prefix.calls != 3 || suffix.calls != 3)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroPassManager_PreRa_ReportsALoopThatNeverSettles)
{
    // A loop that runs out of sweeps used to return an error that said nothing outside a
    // micro-validating build, so the caller reported whatever it made of it - for the compile-time
    // evaluations lowered through this loop, a semantic error about the user's own source.
    MicroBuilder builder(ctx);
    builder.emitLoadRegImm(MicroReg::intReg(0), ApInt(0, 64), MicroOpBits::B64);
    const auto value = builder.instructions().lastInstructionRef();
    builder.emitRet();

    NeverSettlingPass never(value);
    MicroPassManager  manager;
    manager.addPreRaLoopPass(never);

    MicroPassContext passContext;
    passContext.callConvKind               = CallConvKind::Swag;
    passContext.optimizationIterationLimit = 3;

    const RestoreErrorCount restoreErrors;
    const uint64_t          errorsBefore = Stats::getNumErrors();
    const bool              savedMute    = ctx.muteOutput();
    ctx.setMuteOutput(true);
    const Result result = builder.runPasses(manager, nullptr, passContext);
    ctx.setMuteOutput(savedMute);

    if (result != Result::Error)
        return Result::Error;
    if (never.calls != 3)
        return Result::Error;
    if (Stats::getNumErrors() != errorsBefore + 1)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroBuilder_ReleaseMemoryDropsTransientStorageAndCanBeReused)
{
    MicroBuilder builder(ctx);
    const size_t forbiddenBuckets = builder.virtualRegForbiddenPhysRegs().bucket_count();
    const size_t preservedBuckets = builder.preservedVirtualCopyRegs().bucket_count();
    for (uint32_t index = 1; index <= 1024; ++index)
    {
        const MicroReg reg = MicroReg::virtualIntReg(index);
        builder.addVirtualRegForbiddenPhysReg(reg, MicroReg::intReg(0));
        builder.preserveVirtualCopy(reg);
    }
    builder.emitNop();
    builder.codeRelocations().reserve(4096);
    MicroRelocation relocation;
    relocation.instructionRef = builder.instructions().lastInstructionRef();
    builder.codeRelocations().push_back(relocation);

    builder.releaseMemory();
    if (builder.instructions().allocatedBytes() || builder.operands().allocatedBytes() || builder.codeRelocations().capacity())
        return Result::Error;
    if (!builder.virtualRegForbiddenPhysRegs().empty() || !builder.preservedVirtualCopyRegs().empty() ||
        builder.virtualRegForbiddenPhysRegs().bucket_count() > forbiddenBuckets ||
        builder.preservedVirtualCopyRegs().bucket_count() > preservedBuckets)
        return Result::Error;

    builder.emitNop();
    const MicroLabelRef label = builder.createLabel();
    builder.placeLabel(label);
    builder.emitRet();
    if (builder.instructions().count() != 3 || !builder.codeRelocations().empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroBuilder_PruneRelocationsBeforeRecyclingSlots)
{
    MicroBuilder builder(ctx);
    builder.emitNop();
    const auto first = builder.instructions().lastInstructionRef();
    builder.emitNop();
    const auto dead = builder.instructions().lastInstructionRef();
    builder.emitNop();
    const auto       last = builder.instructions().lastInstructionRef();
    const std::array refs{first, dead, MicroInstrRef::invalid(), first, last, MicroInstrRef(1000)};
    for (uint32_t i = 0; i < refs.size(); ++i)
    {
        MicroRelocation reloc;
        reloc.instructionRef = refs[i];
        reloc.targetAddress  = i;
        builder.codeRelocations().push_back(reloc);
    }

    builder.instructions().erase(dead);
    builder.emitNop();
    if (builder.instructions().lastInstructionRef() == dead)
        return Result::Error;
    if (!builder.pruneDeadRelocations())
        return Result::Error;
    const auto& relocs = builder.codeRelocations();
    if (relocs.size() != 3 || relocs[0].targetAddress != 0 || relocs[1].targetAddress != 3 || relocs[2].targetAddress != 4)
        return Result::Error;
    if (builder.pruneDeadRelocations())
        return Result::Error;

    builder.emitNop();
    if (builder.instructions().lastInstructionRef() != dead)
        return Result::Error;
    for (const auto& reloc : relocs)
    {
        if (reloc.instructionRef == dead)
            return Result::Error;
    }
    builder.instructions().erase(first);
    builder.instructions().erase(last);
    if (!builder.pruneDeadRelocations() || !relocs.empty())
        return Result::Error;

    // Even an empty relocation list must release newly quarantined slots.
    builder.instructions().erase(dead);
    if (builder.pruneDeadRelocations())
        return Result::Error;
    builder.emitNop();
    if (builder.instructions().lastInstructionRef() != dead)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroControlFlowGraph_KeepsEdgeOrderAcrossRebuilds)
{
    MicroBuilder builder(ctx);
    const auto   entry  = builder.createLabel();
    const auto   middle = builder.createLabel();
    const auto   end    = builder.createLabel();
    builder.placeLabel(entry);
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, middle);
    builder.emitNop();
    const std::array targets{end, middle, end, entry};
    builder.emitJumpReg(MicroReg::virtualIntReg(1), targets);
    const auto backJump = builder.instructions().lastInstructionRef();
    builder.placeLabel(middle);
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, end);
    builder.placeLabel(end);
    builder.emitRet();

    // The indirect jump keeps first-target order and deduplicates end. The
    // second conditional's explicit target equals its fallthrough destination.
    const std::vector<std::vector<uint32_t>> successors{{1}, {4, 2}, {3}, {6, 4, 0}, {5}, {6}, {7}, {}};
    const std::vector<std::vector<uint32_t>> predecessors{{3}, {0}, {1}, {2}, {1, 3}, {4}, {3, 5}, {6}};
    const auto&                              cfg = builder.controlFlowGraph();
    if (cfg.instructionCount() != successors.size() || !cfg.hasLoop() || !cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
        return Result::Error;
    for (uint32_t i = 0; i < successors.size(); ++i)
    {
        if (!std::ranges::equal(cfg.successors(i), successors[i]) || !std::ranges::equal(cfg.predecessors(i), predecessors[i]))
            return Result::Error;
    }

    builder.instructions().erase(backJump);
    const std::vector<std::vector<uint32_t>> linearSuccessors{{1}, {3, 2}, {3}, {4}, {5}, {6}, {}};
    const std::vector<std::vector<uint32_t>> linearPredecessors{{}, {0}, {1}, {1, 2}, {3}, {4}, {5}};
    const auto&                              rebuilt = builder.controlFlowGraph();
    if (rebuilt.instructionCount() != linearSuccessors.size() || rebuilt.hasLoop())
        return Result::Error;
    for (uint32_t i = 0; i < linearSuccessors.size(); ++i)
    {
        if (!std::ranges::equal(rebuilt.successors(i), linearSuccessors[i]) || !std::ranges::equal(rebuilt.predecessors(i), linearPredecessors[i]))
            return Result::Error;
    }

    builder.emitJumpReg(MicroReg::virtualIntReg(1));
    builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, builder.createLabel());
    builder.emitRet();
    const auto& unsupported = builder.controlFlowGraph();
    if (!unsupported.hasUnsupportedControlFlowForCfgLiveness() || unsupported.supportsDeadCodeLiveness() || unsupported.hasLoop())
        return Result::Error;
    if (!unsupported.successors(7).empty() || unsupported.successors(8).size() != 1 || unsupported.successors(8)[0] != 9)
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroControlFlowGraph_RebuildsLargeBranchesAndRemovedLabels)
{
    MicroBuilder builder(ctx);
    if (builder.controlFlowGraph().instructionCount())
        return Result::Error;

    std::array<MicroLabelRef, 32> targets;
    for (auto& target : targets)
        target = builder.createLabel();
    const auto                    end = builder.createLabel();
    std::array<MicroLabelRef, 64> repeatedTargets;
    for (uint32_t i = 0; i < targets.size(); ++i)
    {
        repeatedTargets[i]                  = targets[i];
        repeatedTargets[targets.size() + i] = targets[targets.size() - 1 - i];
    }
    builder.emitJumpReg(MicroReg::virtualIntReg(1), repeatedTargets);
    MicroInstrRef removedLabel;
    for (uint32_t i = 0; i < targets.size(); ++i)
    {
        builder.placeLabel(targets[i]);
        if (i == 16)
            removedLabel = builder.instructions().lastInstructionRef();
        builder.emitJumpToLabel(MicroCond::Zero, MicroOpBits::B64, end);
    }
    builder.placeLabel(end);
    builder.emitRet();

    for (uint32_t rebuild = 0; rebuild < 3; ++rebuild)
    {
        const auto& cfg = builder.controlFlowGraph();
        if (cfg.instructionCount() != 67 || !cfg.supportsDeadCodeLiveness() || cfg.hasLoop())
            return Result::Error;
        if (cfg.successors(0).size() != targets.size() || cfg.predecessors(65).size() != targets.size())
            return Result::Error;
        for (uint32_t i = 0; i < targets.size(); ++i)
        {
            if (cfg.successors(0)[i] != 1 + 2 * i || cfg.predecessors(65)[i] != 2 + 2 * i)
                return Result::Error;
        }
        builder.invalidateControlFlowGraph();
    }

    // A removed label must not retain its old instruction index in the reused table.
    builder.instructions().erase(removedLabel);
    const auto& cfg = builder.controlFlowGraph();
    if (cfg.supportsDeadCodeLiveness() || cfg.instructionCount() != 66 || cfg.successors(0).size() != 31)
        return Result::Error;
    for (uint32_t i = 0; i < cfg.successors(0).size(); ++i)
    {
        const uint32_t expected = i < 16 ? 1 + 2 * i : 2 + 2 * i;
        if (cfg.successors(0)[i] != expected)
            return Result::Error;
    }

    const std::vector<MicroInstrRef> refs(cfg.instructionRefs().begin(), cfg.instructionRefs().end());
    for (const auto ref : refs)
        builder.instructions().erase(ref);
    const auto& empty = builder.controlFlowGraph();
    if (empty.instructionCount() || !empty.successors().empty() || !empty.predecessors().empty() || !empty.supportsDeadCodeLiveness() || empty.hasLoop())
        return Result::Error;
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroDenseRegIndex_ReusesMixedDirectAndSparseRegisters)
{
    MicroDenseRegIndex index;
    const std::array   regs = {
        MicroReg::intReg(3),
        MicroReg::floatReg(3),
        MicroReg::virtualIntReg(3),
        MicroReg::virtualFloatReg(3),
        MicroReg::virtualIntReg(MicroReg::K_MAX_INDEX),
        MicroReg::virtualFloatReg(MicroReg::K_MAX_INDEX),
        MicroReg::instructionPointer(),
        MicroReg::noBase(),
    };

    for (uint32_t round = 0; round < 3; ++round)
    {
        index.clear();
        index.reserve(round ? 2 : 512);
        if (!index.regs().empty() || index.wordCount())
            return Result::Error;
        for (const MicroReg reg : regs)
            if (index.contains(reg))
                return Result::Error;

        for (uint32_t i = 0; i < regs.size(); ++i)
            if (index.ensure(regs[i]) != i || index.ensure(regs[i]) != i)
                return Result::Error;

        // Force the fallback to grow, then verify direct and sparse lookups
        // still share one insertion order across repeated clear/reserve cycles.
        for (uint32_t i = 0; i < 130; ++i)
        {
            const MicroReg reg = MicroReg::virtualIntReg(MicroReg::K_MAX_INDEX - i - 1);
            if (index.contains(reg) || index.ensure(reg) != regs.size() + i)
                return Result::Error;
        }
        if (index.regs().size() != regs.size() + 130 || index.wordCount() != 3)
            return Result::Error;
        for (uint32_t i = 0; i < index.regs().size(); ++i)
            if (index.find(index.regs()[i]) != i || index.ensure(index.regs()[i]) != i)
                return Result::Error;
        if (index.contains(MicroReg::virtualFloatReg(MicroReg::K_MAX_INDEX - 1)))
            return Result::Error;
    }
}
SWC_TEST_END()

#if SWC_HAS_VALIDATE_MICRO

namespace
{
    Result verifyMicroFixture(MicroBuilder& builder, bool virtualOnly = false)
    {
        MicroPassContext context;
        context.instructions  = &builder.instructions();
        context.operands      = &builder.operands();
        context.validateMicro = true;
        // Expected rejections must not print diagnostics into the hosting test run.
        return virtualOnly ? MicroVerify::verifyAllRegistersVirtual(context, "register-fixture") : MicroVerify::verify(context, "register-fixture");
    }
}

SWC_TEST_BEGIN(MicroVerify_AmcRegistersFollowTheirOperandRoles)
{
    struct Case
    {
        MicroInstrOpcode op;
        uint8_t          baseIndex;
        uint8_t          indexIndex;
        uint8_t          valueIndex;
    };
    constexpr Case cases[] = {
        {MicroInstrOpcode::LoadAmcRegMem, 1, 2, 0},
        {MicroInstrOpcode::LoadSignedExtAmcRegMem, 1, 2, 0},
        {MicroInstrOpcode::LoadZeroExtAmcRegMem, 1, 2, 0},
        {MicroInstrOpcode::LoadAddrAmcRegMem, 1, 2, 0},
        {MicroInstrOpcode::VecUnaryAmcRegMem, 1, 2, 0},
        {MicroInstrOpcode::LoadAmcMemReg, 0, 1, 2},
        {MicroInstrOpcode::LoadAmcMemImm, 0, 1, UINT8_MAX},
        {MicroInstrOpcode::CmpAmcImm, 0, 1, UINT8_MAX},
    };
    for (const Case& test : cases)
        for (const bool physical : {false, true})
        {
            const MicroReg base   = physical ? MicroReg::intReg(1) : MicroReg::virtualIntReg(1);
            const MicroReg index  = physical ? MicroReg::intReg(2) : MicroReg::virtualIntReg(2);
            const MicroReg value  = physical ? MicroReg::intReg(3) : MicroReg::virtualIntReg(3);
            const MicroReg vector = physical ? MicroReg::floatReg(3) : MicroReg::virtualFloatReg(3);
            MicroBuilder   builder(ctx);
            builder.emitLoadAmcRegMem(value, MicroOpBits::B64, base, index, 4, 16, MicroOpBits::B64);
            MicroInstr*        inst = builder.instructions().ptr(builder.instructions().lastInstructionRef());
            MicroInstrOperand* ops  = inst->ops(builder.operands());
            if (inst->numOperands != 8)
                return Result::Error;
            inst->op = test.op;
            if (test.baseIndex == 0)
            {
                ops[0].reg = base;
                ops[1].reg = index;
                ops[2].reg = value;
            }
            if (test.op == MicroInstrOpcode::LoadAmcMemReg)
            {
                // The stored value is operand two, not the address index, and may be SIMD.
                ops[2].reg    = vector;
                ops[4].opBits = MicroOpBits::B128;
            }
            if (test.op == MicroInstrOpcode::LoadAmcMemImm)
                ops[7].setImmediateValue(ApInt(42, 64));
            if (test.op == MicroInstrOpcode::LoadSignedExtAmcRegMem || test.op == MicroInstrOpcode::LoadZeroExtAmcRegMem)
            {
                ops[4].opBits     = test.op == MicroInstrOpcode::LoadSignedExtAmcRegMem ? MicroOpBits::B32 : MicroOpBits::B8;
                inst->numOperands = 7;
            }
            if (test.op == MicroInstrOpcode::VecUnaryAmcRegMem)
            {
                ops[0].reg     = vector;
                ops[3].opBits  = MicroOpBits::B128;
                ops[7].microOp = MicroOp::VecWidenLoU8;
            }
            if (test.op == MicroInstrOpcode::CmpAmcImm)
            {
                ops[2].opBits   = MicroOpBits::B32;
                ops[3].opBits   = MicroOpBits::B64;
                ops[4].valueU64 = 4;
                ops[5].valueU64 = 16;
                ops[6].setImmediateValue(ApInt(42, 32));
                inst->numOperands = 7;
            }
            SWC_RESULT(verifyMicroFixture(builder));

            ops[test.baseIndex].reg     = MicroReg::noBase();
            const Result noBaseExpected = test.op == MicroInstrOpcode::VecUnaryAmcRegMem ? Result::Error : Result::Continue;
            if (verifyMicroFixture(builder) != noBaseExpected)
                return Result::Error;
            ops[test.baseIndex].reg = base;

            for (const MicroReg bad : {MicroReg::invalid(), MicroReg::instructionPointer(), MicroReg::floatReg(1), MicroReg::virtualFloatReg(1)})
                for (const uint8_t slot : {test.baseIndex, test.indexIndex})
                {
                    const MicroReg saved = ops[slot].reg;
                    ops[slot].reg        = bad;
                    if (verifyMicroFixture(builder) != Result::Error)
                        return Result::Error;
                    ops[slot].reg = saved;
                }
            ops[test.indexIndex].reg = MicroReg::noBase();
            if (verifyMicroFixture(builder) != Result::Error)
                return Result::Error;
            ops[test.indexIndex].reg = index;

            if (test.valueIndex != UINT8_MAX)
                for (const MicroReg special : {MicroReg::noBase(), MicroReg::instructionPointer()})
                {
                    const MicroReg saved     = ops[test.valueIndex].reg;
                    ops[test.valueIndex].reg = special;
                    if (verifyMicroFixture(builder) != Result::Error)
                        return Result::Error;
                    ops[test.valueIndex].reg = saved;
                }

            // Address scale legalization follows structural verification.
            if (test.op == MicroInstrOpcode::LoadAddrAmcRegMem)
            {
                ops[5].valueU64 = 3;
                SWC_RESULT(verifyMicroFixture(builder));
            }
            for (const uint8_t count : {0, 1, 6})
            {
                inst->numOperands = count;
                if (verifyMicroFixture(builder) != Result::Error)
                    return Result::Error;
            }
        }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroVerify_RejectsSpecialScalarRegisters)
{
    MicroBuilder builder(ctx);
    builder.emitLoadRegReg(MicroReg::virtualIntReg(1), MicroReg::intReg(2), MicroOpBits::B64);
    MicroInstrOperand* ops = builder.instructions().ptr(builder.instructions().lastInstructionRef())->ops(builder.operands());
    SWC_RESULT(verifyMicroFixture(builder));
    for (const uint8_t slot : {0, 1})
        for (const MicroReg bad : {MicroReg::invalid(), MicroReg::noBase(), MicroReg::instructionPointer(), MicroReg(MicroRegKind::Special, 2)})
        {
            const MicroReg saved = ops[slot].reg;
            ops[slot].reg        = bad;
            if (verifyMicroFixture(builder) != Result::Error)
                return Result::Error;
            ops[slot].reg = saved;
        }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MicroVerify_VirtualRegistersIgnoreUnusedAmcStoreSlot)
{
    constexpr MicroReg base  = MicroReg::virtualIntReg(1);
    constexpr MicroReg index = MicroReg::virtualIntReg(2);
    MicroBuilder       builder(ctx);
    builder.emitLoadAmcMemImm(base, index, 4, 16, MicroOpBits::B64, ApInt(42, 32), MicroOpBits::B32);
    MicroInstrOperand* ops = builder.instructions().ptr(builder.instructions().lastInstructionRef())->ops(builder.operands());
    // Operand two is unused in an immediate store. Its bits are not a register use.
    ops[2].reg = MicroReg::intReg(7);
    SWC_RESULT(verifyMicroFixture(builder));
    SWC_RESULT(verifyMicroFixture(builder, true));
    ops[0].reg = MicroReg::noBase();
    SWC_RESULT(verifyMicroFixture(builder));
    SWC_RESULT(verifyMicroFixture(builder, true));
    ops[0].reg = base;
    for (const uint8_t slot : {0, 1})
    {
        const MicroReg saved = ops[slot].reg;
        ops[slot].reg        = MicroReg::intReg(7);
        if (verifyMicroFixture(builder, true) != Result::Error)
            return Result::Error;
        ops[slot].reg = saved;
    }
    return Result::Continue;
}
SWC_TEST_END()

#endif

SWC_END_NAMESPACE();

#endif
