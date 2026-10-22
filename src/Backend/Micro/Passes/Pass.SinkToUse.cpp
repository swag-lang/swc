#include "pch.h"
#include "Backend/Micro/Passes/Pass.SinkToUse.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroOptimizationLimits.h"
#include "Backend/Micro/MicroOptimizerStats.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.Peephole.Core.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

// See the header for why this exists. One round finds every definition that
// can legally sit just before its single consumer and moves it there; chains
// resolve over successive rounds when a consumer moves farther than its
// producer's destination in the current instruction listing.

SWC_BEGIN_NAMESPACE();

namespace
{

    // How far a definition may sink. The point is collapsing the long
    // materialize-everything-then-compute runs a block is emitted as; a bound
    // keeps the barrier scans linear in practice.
    using MicroOptimizationLimits::SinkToUse::K_MAX_SINK_DISTANCE;

    struct RegCounts
    {
        uint32_t definitions  = 0;
        uint32_t uses         = 0;
        uint32_t onlyUseIndex = 0;
    };

    struct Move
    {
        MicroInstrRef                  ref;
        MicroInstrRef                  beforeRef;
        MicroInstrOpcode               op = MicroInstrOpcode::Nop;
        SmallVector<MicroInstrOperand> ops;
        bool                           foldAddress = false;
    };

    struct SinkScratch
    {
        std::vector<uint32_t>         blockIds;
        std::vector<MicroInstrUseDef> useDefs;
        MicroDenseRegIndex            virtualRegs;
        std::vector<RegCounts>        regCounts;
        FlatKeySet                    relocationRefs;
        std::vector<Move>             moves;
        MicroPeephole::LazyU32Set     foldedConsumers;
    };

    thread_local SinkScratch sinkScratch;

    // A definition this pass may move: writes exactly one virtual register,
    // reads and writes no CPU flags, has no side effect beyond that write,
    // and stays inside one block by construction of the checks around it.
    bool isSinkableDefinition(const MicroInstr& inst, const MicroInstrUseDef& useDef)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (info.flags.has(MicroInstrFlagsE::DefinesCpuFlags) ||
            info.flags.has(MicroInstrFlagsE::UsesCpuFlags) ||
            info.flags.has(MicroInstrFlagsE::WritesMemory) ||
            info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
            info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
            info.flags.has(MicroInstrFlagsE::JumpInstruction))
            return false;
        if (inst.op == MicroInstrOpcode::Label ||
            inst.op == MicroInstrOpcode::Push ||
            inst.op == MicroInstrOpcode::Pop)
            return false;
        if (useDef.isCall)
            return false;

        if (useDef.defs.size() != 1 || !useDef.defs[0].isVirtual())
            return false;
        // Sinking a definition to its reader ends its result's live range
        // there but stretches every register it reads down to the same
        // point. A materialization reads nothing, a load one base register:
        // the move costs nothing or breaks even. A compute over two registers
        // sunk to the end of a chain keeps both alive across everything in
        // between; a run of them turns a block into every load first and
        // every compute last, and the allocator pays the width of the run.
        uint32_t virtualReads = 0;
        for (const MicroReg used : useDef.uses)
        {
            if (used.isVirtual())
            {
                if (++virtualReads > 1)
                    return false;
            }
            else if (!used.isInt() && !used.isFloat())
                return false;
        }
        return true;
    }

    bool sourceDiesAtCopy(const MicroPassContext& context, MicroInstrRef copy, MicroReg source)
    {
        const auto& cfg = context.builder->controlFlowGraph();
        if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
            return false;
        const auto refs = cfg.instructionRefs();
        const auto at   = cfg.indexOf(copy);
        if (at == MicroControlFlowGraph::K_NO_INDEX)
            return false;
        SmallVector<uint8_t, 128> visited(refs.size(), 0);
        SmallVector<uint32_t>     pending;
        pending.append(cfg.successors(at).data(), cfg.successors(at).size());
        while (!pending.empty())
        {
            const auto index = pending.back();
            pending.pop_back();
            if (visited[index])
                continue;
            visited[index]          = 1;
            const auto* instruction = context.instructions->ptr(refs[index]);
            const auto  touch       = MicroPassHelpers::regTouch(*instruction, *context.operands, source, context.encoder);
            if (touch.use)
                return false;
            if (!touch.def)
                pending.append(cfg.successors(index).data(), cfg.successors(index).size());
        }
        return true;
    }

    // Argument staging has already consumed the old destination. Copying a
    // virtual value before a call can therefore end the source's live range at
    // the call, while the destination already needs to survive it. Neither
    // register may participate in the call itself, including an indirect target.
    bool hoistCopiesAcrossCalls(MicroPassContext& context)
    {
        auto&                      storage  = *context.instructions;
        auto&                      operands = *context.operands;
        std::vector<MicroInstrRef> calls;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
            if (MicroInstr::info(it->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                calls.push_back(it.current);

        bool changed = false;
        for (const auto callRef : calls)
        {
            const auto*      call = storage.ptr(callRef);
            MicroInstrUseDef callUseDef;
            call->collectUseDef(callUseDef, operands, context.encoder);
            auto copyRef = storage.findNextInstructionRef(callRef);
            while (copyRef.isValid())
            {
                const auto* copy = storage.ptr(copyRef);
                if (!copy || copy->op != MicroInstrOpcode::LoadRegReg)
                    break;
                const auto* ops = copy->ops(operands);
                if (!ops[0].reg.isVirtualInt() || !ops[1].reg.isVirtualInt() || ops[2].opBits != MicroOpBits::B64)
                    break;
                bool conflict = false;
                for (const auto reg : {ops[0].reg, ops[1].reg})
                    if (std::ranges::find(callUseDef.uses, reg) != callUseDef.uses.end() ||
                        std::ranges::find(callUseDef.defs, reg) != callUseDef.defs.end())
                        conflict = true;
                if (conflict || !sourceDiesAtCopy(context, copyRef, ops[1].reg))
                    break;
                const auto              next          = storage.findNextInstructionRef(copyRef);
                const MicroInstrOperand replacement[] = {ops[0], ops[1], ops[2]};
                storage.insertDerivedBefore(operands, callRef, MicroInstrOpcode::LoadRegReg, replacement);
                storage.erase(copyRef);
                context.builder->invalidateControlFlowGraph();
                copyRef = next;
                changed = true;
            }
        }
        if (changed)
        {
            if (context.ssaState)
                context.ssaState->invalidate();
            context.builder->invalidateControlFlowGraph();
        }
        return changed;
    }

    bool sinkRound(MicroPassContext& context)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        const uint32_t               n   = cfg.instructionCount();
        if (!n)
            return false;

        const auto instrRefs = cfg.instructionRefs();
        auto&      scratch   = sinkScratch;

        // Block ids from the linear listing: a label opens a block, a
        // terminator closes one.
        scratch.blockIds.resize(n);
        // Sinking only needs instruction-local register effects. Building SSA
        // here would also compute dominators, phis and reaching values on each
        // round, none of which participates in the movement checks below.
        scratch.useDefs.resize(n);
        scratch.virtualRegs.clear();
        scratch.virtualRegs.reserve(n / 2);
        scratch.regCounts.clear();
        scratch.regCounts.reserve(n / 2);
        {
            uint32_t current   = 0;
            bool     openBlock = true;
            for (uint32_t i = 0; i < n; ++i)
            {
                const MicroInstr* inst = storage.ptr(instrRefs[i]);
                if (!inst)
                    return false;
                // Release the old backing stores before filling this entry directly.
                scratch.useDefs[i] = {};
                inst->collectUseDef(scratch.useDefs[i], operands, context.encoder);
                const MicroInstrDef& info = MicroInstr::info(inst->op);
                if (inst->op == MicroInstrOpcode::Label || !openBlock)
                {
                    ++current;
                    openBlock = true;
                }
                scratch.blockIds[i] = current;
                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    openBlock = false;

                // Counts span the whole function even though each move stays
                // inside one block. Preserve definition-before-use indexing.
                const MicroInstrUseDef& useDef = scratch.useDefs[i];
                for (const MicroReg def : useDef.defs)
                {
                    if (!def.isVirtual())
                        continue;

                    const uint32_t denseIndex = scratch.virtualRegs.ensure(def);
                    if (denseIndex == scratch.regCounts.size())
                        scratch.regCounts.emplace_back();
                    ++scratch.regCounts[denseIndex].definitions;
                }
                for (const MicroReg used : useDef.uses)
                {
                    if (!used.isVirtual())
                        continue;

                    const uint32_t denseIndex = scratch.virtualRegs.ensure(used);
                    if (denseIndex == scratch.regCounts.size())
                        scratch.regCounts.emplace_back();
                    ++scratch.regCounts[denseIndex].uses;
                    scratch.regCounts[denseIndex].onlyUseIndex = i;
                }
            }
        }

        scratch.relocationRefs.clear();
        scratch.moves.clear();
        scratch.foldedConsumers.clear();
        bool                       relocationsReady = false;
        thread_local MicroSsaState addressSsa;
        bool                       addressSsaReady = false;

        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            if (!inst || scratch.foldedConsumers.contains(i))
                continue;

            const MicroInstrUseDef* useDef = &scratch.useDefs[i];
            if (!isSinkableDefinition(*inst, *useDef))
                continue;

            const MicroReg value           = useDef->defs[0];
            const uint32_t valueDenseIndex = scratch.virtualRegs.find(value);
            if (valueDenseIndex == MicroDenseRegIndex::K_INVALID_INDEX)
                continue;
            const RegCounts& valueCounts = scratch.regCounts[valueDenseIndex];
            if (valueCounts.definitions != 1 || valueCounts.uses != 1)
                continue;

            const uint32_t useIdx = valueCounts.onlyUseIndex;
            if (useIdx <= i || useIdx - i > K_MAX_SINK_DISTANCE ||
                (useIdx == i + 1 && inst->op != MicroInstrOpcode::LoadAddrRegMem))
                continue;
            const MicroInstrOperand*    ops      = inst->ops(operands);
            const MicroInstr*           consumer = storage.ptr(instrRefs[useIdx]);
            MicroPassHelpers::AmcLayout layout;
            bool                        foldAddress  = false;
            uint64_t                    displacement = 0;
            if (inst->op == MicroInstrOpcode::LoadAddrRegMem && ops[2].opBits == MicroOpBits::B64 &&
                consumer->op != MicroInstrOpcode::LoadAddrRegMem && consumer->op != MicroInstrOpcode::LoadAddrAmcRegMem)
            {
                const auto& info             = MicroInstr::info(consumer->op);
                bool        hasMemoryAddress = MicroPassHelpers::amcLayoutFor(layout, consumer->op);
                if (!hasMemoryAddress && info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
                {
                    hasMemoryAddress = true;
                    layout.baseIdx   = info.memBaseOperandIndex;
                    layout.addIdx    = info.memOffsetOperandIndex;
                }
                if (hasMemoryAddress)
                {
                    const auto* consumerOps = consumer->ops(operands);
                    displacement            = consumerOps[layout.addIdx].valueU64 + ops[3].valueU64;
                    foldAddress             = consumerOps[layout.baseIdx].reg == value && static_cast<int64_t>(displacement) == static_cast<int64_t>(static_cast<int32_t>(displacement));
                }
            }
            const bool crossesBlocks = scratch.blockIds[useIdx] != scratch.blockIds[i];
            if (crossesBlocks)
            {
                if (!foldAddress)
                    continue;
                // Address substitution can cross a branch without moving a load.
                // Only build SSA when such a candidate needs an all-path proof.
                if (!addressSsaReady)
                {
                    addressSsa.clear();
                    addressSsa.build(*context.builder, storage, operands, context.encoder);
                    if (context.optimizerStats && context.optimizerStats->activePass)
                        ++context.optimizerStats->activePass->ssaBuilds;
                    addressSsaReady = true;
                }
                if (!addressSsa.sameValueAt(ops[1].reg, instrRefs[i], instrRefs[useIdx]))
                    continue;
            }

            if (!relocationsReady)
            {
                for (const MicroRelocation& reloc : context.builder->codeRelocations())
                {
                    if (reloc.instructionRef.isValid())
                        scratch.relocationRefs.insert(reloc.instructionRef.get());
                }
                relocationsReady = true;
            }
            if (scratch.relocationRefs.contains(instrRefs[i].get()))
                continue;

            // Nothing between the definition and its consumer may redefine
            // what the definition reads, and a memory read may not cross a
            // memory write or a call. The move must also cross something that
            // is not just another operand of the same consumer: the operand
            // cluster in front of a consumer must reach a stable order, or the
            // members endlessly rotate past one another and the optimization
            // loop never converges.
            const bool readsMemory   = MicroPassHelpers::instructionReadsMemory(*inst);
            bool       blocked       = false;
            bool       meaningfulGap = false;
            for (uint32_t k = i + 1; !crossesBlocks && k < useIdx && !blocked; ++k)
            {
                const MicroInstr*       between       = storage.ptr(instrRefs[k]);
                const MicroInstrUseDef* betweenUseDef = &scratch.useDefs[k];
                if (!between)
                {
                    blocked = true;
                    break;
                }
                const MicroInstrDef& betweenInfo = MicroInstr::info(between->op);
                if (betweenInfo.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                    between->op == MicroInstrOpcode::Label)
                {
                    blocked = true;
                    break;
                }
                if (readsMemory &&
                    (betweenInfo.flags.has(MicroInstrFlagsE::WritesMemory) || betweenUseDef->isCall))
                {
                    blocked = true;
                    break;
                }
                for (const MicroReg def : betweenUseDef->defs)
                {
                    if (std::ranges::find(useDef->uses, def) != useDef->uses.end())
                    {
                        blocked = true;
                        break;
                    }
                }
                if (blocked)
                    break;

                if (!meaningfulGap)
                {
                    const MicroReg betweenDef      = betweenUseDef->defs.size() == 1 ? betweenUseDef->defs[0] : MicroReg::invalid();
                    const uint32_t betweenDenseIdx = scratch.virtualRegs.find(betweenDef);

                    const bool feedsSameConsumer = betweenDenseIdx != MicroDenseRegIndex::K_INVALID_INDEX &&
                                                   scratch.regCounts[betweenDenseIdx].definitions == 1 &&
                                                   scratch.regCounts[betweenDenseIdx].uses == 1 &&
                                                   scratch.regCounts[betweenDenseIdx].onlyUseIndex == useIdx;

                    meaningfulGap = !feedsSameConsumer;
                }
            }
            if (blocked)
                continue;

            // Promotion and vectorization have already consumed the original
            // frame-array shape. Only the address changes; the memory access
            // keeps its position, width, flags and volatile/atomic semantics.
            if (foldAddress)
            {
                const auto* consumerOps = consumer->ops(operands);
                Move        fold;
                fold.ref         = instrRefs[i];
                fold.beforeRef   = instrRefs[useIdx];
                fold.foldAddress = true;
                fold.ops.assign(consumerOps, consumerOps + consumer->numOperands);
                fold.ops[layout.baseIdx].reg     = ops[1].reg;
                fold.ops[layout.addIdx].valueU64 = displacement;
                scratch.moves.push_back(std::move(fold));
                // Do not later sink a snapshot of the consumer's old operands.
                scratch.foldedConsumers.insert(useIdx);
                continue;
            }
            if (!meaningfulGap)
                continue;

            Move move;
            move.ref       = instrRefs[i];
            move.beforeRef = instrRefs[useIdx];
            move.op        = inst->op;
            if (ops && inst->numOperands)
                move.ops.assign(ops, ops + inst->numOperands);
            scratch.moves.push_back(std::move(move));
        }

        if (scratch.moves.empty())
            return false;

        // Moves follow the original instruction order, and every destination
        // lies after its producer. A destination therefore still exists when
        // its producer moves, even if the destination itself moves later.
        for (const Move& move : scratch.moves)
        {
            if (move.foldAddress)
                std::ranges::copy(move.ops, storage.ptr(move.beforeRef)->ops(operands));
            else
                storage.insertDerivedBefore(operands, move.beforeRef, move.op, move.ops);
            storage.erase(move.ref);
        }

        if (context.ssaState)
            context.ssaState->invalidate();
        context.builder->invalidateControlFlowGraph();
        return true;
    }
}

Result MicroSinkToUsePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    if (!context.builder)
        return Result::Continue;

    // Once, on the converged pre-RA IR. Reordering reduces nothing a fixed
    // point measures, so this pass must not participate in one: later sweeps
    // of the legalize/allocate loop see it as a no-op.
    if (!context.isFirstAllocationSweep)
        return Result::Continue;
    if (context.instructions->count() < 3)
        return Result::Continue;

    bool       changedAny   = false;
    const auto K_MAX_ROUNDS = MicroOptimizationLimits::configured(context.optimizer().iterations.sinkToUseRounds, MicroOptimizationLimits::SinkToUse::K_MAX_ROUNDS);
    uint32_t   rounds       = 0;
    bool       stopped      = false;
    for (uint32_t round = 0; round < K_MAX_ROUNDS; ++round)
    {
        ++rounds;
        stopped = sinkRound(context);
        if (!stopped)
            break;
        changedAny = true;
    }
    if (context.optimizerStats)
        context.optimizerStats->observeBudget("sink-to-use-rounds", rounds, K_MAX_ROUNDS, stopped);

    changedAny |= hoistCopiesAcrossCalls(context);
    if (changedAny)
        context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
