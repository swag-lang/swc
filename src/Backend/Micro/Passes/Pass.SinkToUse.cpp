#include "pch.h"
#include "Backend/Micro/Passes/Pass.SinkToUse.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

// See the header for why this exists. One round finds every definition that
// can legally sit just before its single consumer and moves it there; chains
// resolve over the optimization loop's iterations, since a moved consumer is
// left alone in the round that moves its producer.

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_MAX_ROUNDS = 4;

    // How far a definition may sink. The point is collapsing the long
    // materialize-everything-then-compute runs a block is emitted as; a bound
    // keeps the barrier scans linear in practice.
    constexpr uint32_t K_MAX_SINK_DISTANCE = 96;

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
    };

    struct SinkScratch
    {
        std::vector<uint32_t>        blockIds;
        MicroDenseRegIndex           virtualRegs;
        std::vector<RegCounts>       regCounts;
        std::unordered_set<uint32_t> relocationRefs;
        std::vector<Move>            moves;
        std::unordered_set<uint32_t> movedRefs;
    };

    thread_local SinkScratch sinkScratch;

    bool instructionReadsMemory(const MicroInstr& inst)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
            !info.flags.has(MicroInstrFlagsE::WritesMemory) &&
            inst.op != MicroInstrOpcode::LoadAddrRegMem)
            return true;

        return inst.op == MicroInstrOpcode::LoadAmcRegMem ||
               inst.op == MicroInstrOpcode::LoadSignedExtAmcRegMem ||
               inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem;
    }

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
        for (const MicroReg used : useDef.uses)
        {
            if (!used.isVirtual() && !used.isInt() && !used.isFloat())
                return false;
        }

        return true;
    }

    bool sinkRound(MicroPassContext& context)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        MicroSsaState        localSsaState;
        const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
        if (!ssaState || !ssaState->isValid())
            return false;

        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        const uint32_t               n   = cfg.instructionCount();
        if (!n)
            return false;

        const auto instrRefs = cfg.instructionRefs();
        auto&      scratch   = sinkScratch;

        // Block ids from the linear listing: a label opens a block, a
        // terminator closes one.
        scratch.blockIds.assign(n, 0);
        {
            uint32_t current   = 0;
            bool     openBlock = true;
            for (uint32_t i = 0; i < n; ++i)
            {
                const MicroInstr* inst = storage.ptr(instrRefs[i]);
                if (!inst)
                    return false;
                const MicroInstrDef& info = MicroInstr::info(inst->op);
                if (inst->op == MicroInstrOpcode::Label || !openBlock)
                {
                    ++current;
                    openBlock = true;
                }
                scratch.blockIds[i] = current;
                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    openBlock = false;
            }
        }

        // Whole-function def and use counts per virtual register, and the one
        // use's position when there is exactly one.
        scratch.virtualRegs.clear();
        scratch.virtualRegs.reserve(n / 2);
        scratch.regCounts.clear();
        scratch.regCounts.reserve(n / 2);
        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
            if (!useDef)
                return false;
            for (const MicroReg def : useDef->defs)
            {
                if (!def.isVirtual())
                    continue;

                const uint32_t denseIndex = scratch.virtualRegs.ensure(def);
                if (denseIndex == scratch.regCounts.size())
                    scratch.regCounts.emplace_back();
                ++scratch.regCounts[denseIndex].definitions;
            }
            for (const MicroReg used : useDef->uses)
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

        scratch.relocationRefs.clear();
        for (const MicroRelocation& reloc : context.builder->codeRelocations())
        {
            if (reloc.instructionRef.isValid())
                scratch.relocationRefs.insert(reloc.instructionRef.get());
        }

        scratch.moves.clear();
        scratch.movedRefs.clear();

        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            if (!inst || scratch.relocationRefs.contains(instrRefs[i].get()))
                continue;

            const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
            if (!useDef || !isSinkableDefinition(*inst, *useDef))
                continue;

            const MicroReg value           = useDef->defs[0];
            const uint32_t valueDenseIndex = scratch.virtualRegs.find(value);
            if (valueDenseIndex == MicroDenseRegIndex::K_INVALID_INDEX)
                continue;
            const RegCounts& valueCounts = scratch.regCounts[valueDenseIndex];
            if (valueCounts.definitions != 1 || valueCounts.uses != 1)
                continue;

            const uint32_t useIdx = valueCounts.onlyUseIndex;
            if (useIdx <= i + 1 || useIdx - i > K_MAX_SINK_DISTANCE)
                continue;
            if (scratch.blockIds[useIdx] != scratch.blockIds[i])
                continue;

            // Nothing between the definition and its consumer may redefine
            // what the definition reads, and a memory read may not cross a
            // memory write or a call. The move must also cross something that
            // is not just another operand of the same consumer: the operand
            // cluster in front of a consumer must reach a stable order, or the
            // members endlessly rotate past one another and the optimization
            // loop never converges.
            const bool readsMemory   = instructionReadsMemory(*inst);
            bool       blocked       = false;
            bool       meaningfulGap = false;
            for (uint32_t k = i + 1; k < useIdx && !blocked; ++k)
            {
                const MicroInstr*       between       = storage.ptr(instrRefs[k]);
                const MicroInstrUseDef* betweenUseDef = ssaState->instrUseDef(instrRefs[k]);
                if (!between || !betweenUseDef)
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
                    for (const MicroReg used : useDef->uses)
                        blocked = blocked || def == used;
                }

                const MicroReg betweenDef        = betweenUseDef->defs.size() == 1 ? betweenUseDef->defs[0] : MicroReg::invalid();
                const uint32_t betweenDenseIdx   = scratch.virtualRegs.find(betweenDef);
                const bool     feedsSameConsumer = betweenDenseIdx != MicroDenseRegIndex::K_INVALID_INDEX &&
                                               scratch.regCounts[betweenDenseIdx].definitions == 1 &&
                                               scratch.regCounts[betweenDenseIdx].uses == 1 &&
                                               scratch.regCounts[betweenDenseIdx].onlyUseIndex == useIdx;
                meaningfulGap = meaningfulGap || !feedsSameConsumer;
            }
            if (blocked || !meaningfulGap)
                continue;

            // A consumer that is itself moved this round loses its slot; its
            // producer sinks on the next round instead.
            if (scratch.movedRefs.contains(instrRefs[useIdx].get()))
                continue;

            const MicroInstrOperand* ops = inst->ops(operands);
            Move                     move;
            move.ref       = instrRefs[i];
            move.beforeRef = instrRefs[useIdx];
            move.op        = inst->op;
            if (ops && inst->numOperands)
                move.ops.assign(ops, ops + inst->numOperands);
            scratch.movedRefs.insert(instrRefs[i].get());
            scratch.moves.push_back(std::move(move));
        }

        if (scratch.moves.empty())
            return false;

        for (const Move& move : scratch.moves)
        {
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

    bool changedAny = false;
    for (uint32_t round = 0; round < K_MAX_ROUNDS; ++round)
    {
        if (!sinkRound(context))
            break;
        changedAny = true;
    }

    if (changedAny)
        context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
