#include "pch.h"
#include "Backend/Micro/Passes/Pass.SinkToUse.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroInstrInfo.h"
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

        // Block ids from the linear listing: a label opens a block, a
        // terminator closes one.
        std::vector<uint32_t> blockId(n, 0);
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
                blockId[i] = current;
                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    openBlock = false;
            }
        }

        // Whole-function def and use counts per virtual register, and the one
        // use's position when there is exactly one.
        std::unordered_map<MicroReg, uint32_t> defCount;
        std::unordered_map<MicroReg, uint32_t> useCount;
        std::unordered_map<MicroReg, uint32_t> onlyUseIndex;
        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
            if (!useDef)
                return false;
            for (const MicroReg def : useDef->defs)
            {
                if (def.isVirtual())
                    ++defCount[def];
            }
            for (const MicroReg used : useDef->uses)
            {
                if (!used.isVirtual())
                    continue;
                ++useCount[used];
                onlyUseIndex[used] = i;
            }
        }

        std::unordered_set<uint32_t> relocRefs;
        for (const MicroRelocation& reloc : context.builder->codeRelocations())
        {
            if (reloc.instructionRef.isValid())
                relocRefs.insert(reloc.instructionRef.get());
        }

        struct Move
        {
            MicroInstrRef                  ref;
            MicroInstrRef                  beforeRef;
            MicroInstrOpcode               op = MicroInstrOpcode::Nop;
            SmallVector<MicroInstrOperand> ops;
        };
        std::vector<Move>            moves;
        std::unordered_set<uint32_t> movedRefs;

        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            if (!inst || relocRefs.contains(instrRefs[i].get()))
                continue;

            const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
            if (!useDef || !isSinkableDefinition(*inst, *useDef))
                continue;

            const MicroReg value = useDef->defs[0];
            if (defCount[value] != 1 || useCount[value] != 1)
                continue;

            const uint32_t useIdx = onlyUseIndex[value];
            if (useIdx <= i + 1 || useIdx - i > K_MAX_SINK_DISTANCE)
                continue;
            if (blockId[useIdx] != blockId[i])
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

                const bool feedsSameConsumer = betweenUseDef->defs.size() == 1 &&
                                               betweenUseDef->defs[0].isVirtual() &&
                                               defCount[betweenUseDef->defs[0]] == 1 &&
                                               useCount[betweenUseDef->defs[0]] == 1 &&
                                               onlyUseIndex[betweenUseDef->defs[0]] == useIdx;
                meaningfulGap = meaningfulGap || !feedsSameConsumer;
            }
            if (blocked || !meaningfulGap)
                continue;

            // A consumer that is itself moved this round loses its slot; its
            // producer sinks on the next round instead.
            if (movedRefs.contains(instrRefs[useIdx].get()))
                continue;

            const MicroInstrOperand* ops = inst->ops(operands);
            Move                     move;
            move.ref       = instrRefs[i];
            move.beforeRef = instrRefs[useIdx];
            move.op        = inst->op;
            if (ops && inst->numOperands)
                move.ops.assign(ops, ops + inst->numOperands);
            movedRefs.insert(instrRefs[i].get());
            moves.push_back(std::move(move));
        }

        if (moves.empty())
            return false;

        for (const Move& move : moves)
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
