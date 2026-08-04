#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoopUnroll.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Math/ApsInt.h"

// Full unrolling of small counted loops, pre-RA.
//
// The recognized shape is what the code generator emits for a counted `for`:
//
//     LoadRegImm/ClearReg  %i, C          ; straight-line preheader
//   H:                                    ; single back-edge target
//     ...body (may branch internally or exit forward)...
//     OpBinaryRegImm add   %i, step
//     CmpRegImm            %i, N
//     JumpCond   l/b, H
//
// With C, step and N constant the trip count is exact, so the loop becomes
// `trips` copies of the body laid end to end. The counter is not carried
// between copies: each copy k reads its own fresh register materialized as
// the constant C + k*step, and the original counter is re-materialized once
// after the last copy for any post-loop reader. Handing every copy a
// constant counter is what lets the rest of the pre-RA loop finish the job -
// constant folding collapses the per-copy extends, and the constant-index
// fold turns every `[base + i*scale]` into a direct displacement.
//
// Cloned instructions keep their relocations: any table the body reads
// through a materialized address is re-attached to each copy. Labels inside
// the body are duplicated with fresh ids per copy, so internal control flow
// (a `continue`, an `if`) lands in the right copy; jumps that leave the loop
// forward keep their external target untouched.

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_MAX_TRIPS       = 8;
    constexpr uint32_t K_MAX_BODY_INSTR  = 96;
    constexpr uint32_t K_MAX_TOTAL_INSTR = 384;

    bool defsRegister(const MicroInstr& inst, const MicroOperandStorage& operands, const Encoder* encoder, const MicroReg reg)
    {
        const MicroInstrUseDef useDef = inst.collectUseDef(operands, encoder);
        return std::ranges::find(useDef.defs, reg) != useDef.defs.end();
    }
}

Result MicroLoopUnrollPass::run(MicroPassContext& context)
{
    context.passChanged = false;
    if (!context.instructions || !context.operands || !context.builder)
        return Result::Continue;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    MicroBuilder&        builder  = *context.builder;

    // Program layout: ordinals, label positions, and every jump with its target.
    std::vector<MicroInstrRef>                 order;
    std::unordered_map<uint64_t, uint32_t>     labelOrdinal;
    std::vector<std::pair<uint32_t, uint64_t>> jumps;
    order.reserve(storage.count());

    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const MicroInstr& inst = *it;
        const uint32_t    ord  = static_cast<uint32_t>(order.size());
        order.push_back(it.current);

        // Computed control flow hides edges from the layout scan; sit the
        // whole function out.
        if (inst.op == MicroInstrOpcode::JumpReg)
            return Result::Continue;

        const MicroInstrOperand* ops = inst.ops(operands);
        if (!ops)
            continue;
        if (inst.op == MicroInstrOpcode::Label)
            labelOrdinal[ops[0].valueU64] = ord;
        else if (inst.op == MicroInstrOpcode::JumpCond && inst.numOperands >= 3)
            jumps.push_back({ord, ops[2].valueU64});
    }

    // Labels a relocation points at are pinned; relocations by owning slot
    // let clones keep the tables and constants the body reads.
    std::unordered_set<uint64_t>                                  relocLabels;
    std::unordered_map<uint32_t, SmallVector<MicroRelocation, 2>> relocsBySlot;
    for (const MicroRelocation& reloc : builder.codeRelocations())
    {
        if (!reloc.instructionRef.isValid())
            continue;
        relocsBySlot[reloc.instructionRef.get()].push_back(reloc);
        const MicroInstr* inst = storage.ptr(reloc.instructionRef);
        if (inst && inst->op == MicroInstrOpcode::Label)
        {
            const MicroInstrOperand* ops = inst->ops(operands);
            if (ops)
                relocLabels.insert(ops[0].valueU64);
        }
    }

    for (const auto& [jccOrdinal, headerId] : jumps)
    {
        const auto labelIt = labelOrdinal.find(headerId);
        if (labelIt == labelOrdinal.end())
            continue;
        const uint32_t h = labelIt->second;
        // Backward jump with room for add/cmp plus at least one body instruction.
        if (h + 4 > jccOrdinal)
            continue;
        if (relocLabels.contains(headerId))
            continue;

        const MicroInstr*        jcc    = storage.ptr(order[jccOrdinal]);
        const MicroInstrOperand* jccOps = jcc ? jcc->ops(operands) : nullptr;
        if (!jccOps)
            continue;
        const MicroCond cond = jccOps[0].cpuCond;
        if (cond != MicroCond::Less && cond != MicroCond::Below)
            continue;

        // The back-edge must be the header's only way in besides fall-through.
        uint32_t headerJumpCount = 0;
        for (const auto& [o, t] : jumps)
        {
            if (t == headerId)
                ++headerJumpCount;
        }
        if (headerJumpCount != 1)
            continue;

        // The latch: add %i, step / cmp %i, N / jcc H.
        const MicroInstr* cmp = storage.ptr(order[jccOrdinal - 1]);
        const MicroInstr* add = storage.ptr(order[jccOrdinal - 2]);
        if (!cmp || !add || cmp->op != MicroInstrOpcode::CmpRegImm || add->op != MicroInstrOpcode::OpBinaryRegImm)
            continue;
        const MicroInstrOperand* cmpOps = cmp->ops(operands);
        const MicroInstrOperand* addOps = add->ops(operands);
        if (!cmpOps || !addOps || addOps[2].microOp != MicroOp::Add)
            continue;

        const MicroReg counter = addOps[0].reg;
        if (!counter.isVirtualInt() || cmpOps[0].reg != counter)
            continue;
        const MicroOpBits counterBits = cmpOps[1].opBits;
        if ((counterBits != MicroOpBits::B32 && counterBits != MicroOpBits::B64) || addOps[1].opBits != counterBits)
            continue;
        if (cmpOps[2].hasWideImmediateValue() || addOps[3].hasWideImmediateValue())
            continue;
        const uint64_t bound = cmpOps[2].valueU64;
        const uint64_t step  = addOps[3].valueU64;
        if (step < 1 || step > 64 || bound > 1000000)
            continue;

        // The counter's starting constant, from the straight-line preheader.
        uint64_t initValue = 0;
        bool     haveInit  = false;
        for (uint32_t back = 1; back <= 8 && back <= h; ++back)
        {
            const MicroInstr* cand = storage.ptr(order[h - back]);
            if (!cand)
                break;
            const MicroInstrDef& info = MicroInstr::info(cand->op);
            if (cand->op == MicroInstrOpcode::Label ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                break;
            if (!defsRegister(*cand, operands, context.encoder, counter))
                continue;

            if (cand->op == MicroInstrOpcode::ClearReg)
            {
                initValue = 0;
                haveInit  = true;
            }
            else if (cand->op == MicroInstrOpcode::LoadRegImm)
            {
                const MicroInstrOperand* initOps = cand->ops(operands);
                if (initOps && !initOps[2].hasWideImmediateValue() && initOps[1].opBits == counterBits)
                {
                    initValue = initOps[2].valueU64;
                    haveInit  = true;
                }
            }
            break;
        }
        if (!haveInit || initValue >= bound || (bound - initValue) % step != 0)
            continue;
        const uint64_t trips = (bound - initValue) / step;
        if (trips < 2 || trips > K_MAX_TRIPS)
            continue;

        const uint32_t bodyBegin = h + 1;
        const uint32_t bodyEnd   = jccOrdinal - 2;
        const uint32_t bodyCount = bodyEnd - bodyBegin;
        if (!bodyCount || bodyCount > K_MAX_BODY_INSTR || bodyCount * trips > K_MAX_TOTAL_INSTR)
            continue;

        // Body scan: collect internal labels, verify every branch is either
        // internal (remappable) or a forward exit, and that nothing but the
        // latch touches the counter.
        std::unordered_set<uint64_t> internalLabels;
        bool ok = true;
        for (uint32_t o = bodyBegin; o < bodyEnd && ok; ++o)
        {
            const MicroInstr*        inst = storage.ptr(order[o]);
            const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!inst)
            {
                ok = false;
                break;
            }

            switch (inst->op)
            {
                case MicroInstrOpcode::Label:
                    if (!ops || relocLabels.contains(ops[0].valueU64))
                        ok = false;
                    else
                        internalLabels.insert(ops[0].valueU64);
                    break;

                case MicroInstrOpcode::JumpCond:
                {
                    if (!ops || inst->numOperands < 3)
                    {
                        ok = false;
                        break;
                    }
                    const auto targetIt = labelOrdinal.find(ops[2].valueU64);
                    if (targetIt == labelOrdinal.end())
                    {
                        ok = false;
                        break;
                    }
                    const uint32_t targetOrdinal = targetIt->second;
                    // Internal target or forward exit past the latch; anything
                    // aimed at the header, the latch, or behind the loop bails.
                    if (targetOrdinal <= h || (targetOrdinal >= bodyEnd && targetOrdinal <= jccOrdinal))
                        ok = false;
                    break;
                }

                default:
                {
                    const MicroInstrDef& info = MicroInstr::info(inst->op);
                    if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) || info.flags.has(MicroInstrFlagsE::JumpInstruction))
                    {
                        ok = false;
                        break;
                    }
                    if (defsRegister(*inst, operands, context.encoder, counter))
                        ok = false;
                    break;
                }
            }
        }
        if (!ok)
            continue;

        // No jump from outside the body may land on an internal label.
        for (const auto& [o, t] : jumps)
        {
            if (internalLabels.contains(t) && (o < bodyBegin || o >= bodyEnd))
            {
                ok = false;
                break;
            }
        }
        if (!ok)
            continue;

        // ------------------------------------------------------------------
        // Unroll. The original body stays in place as copy zero, reading the
        // original counter (still materialized as C in the preheader). Copies
        // 1..trips-1 are inserted before the latch, then the latch goes away.
        const MicroInstrRef addRef = order[jccOrdinal - 2];
        const MicroInstrRef cmpRef = order[jccOrdinal - 1];
        const MicroInstrRef jccRef = order[jccOrdinal];

        const uint32_t firstFreshVirtual = MicroPassHelpers::computeNextVirtualIntRegIndex(context);

        for (uint64_t k = 1; k < trips; ++k)
        {
            const MicroReg copyCounter = MicroReg::virtualIntReg(firstFreshVirtual + static_cast<uint32_t>(k) - 1);

            MicroInstrOperand counterOps[3];
            counterOps[0].reg    = copyCounter;
            counterOps[1].opBits = counterBits;
            counterOps[2].setImmediateValue(ApInt(initValue + k * step, getNumBits(counterBits)));
            storage.insertDerivedBefore(operands, addRef, MicroInstrOpcode::LoadRegImm, counterOps);

            std::unordered_map<uint64_t, uint64_t> labelMap;
            labelMap.reserve(internalLabels.size());
            for (const uint64_t id : internalLabels)
                labelMap.emplace(id, builder.createLabel().get());

            for (uint32_t o = bodyBegin; o < bodyEnd; ++o)
            {
                const MicroInstrRef      srcRef = order[o];
                const MicroInstr*        src    = storage.ptr(srcRef);
                const MicroInstrOperand* srcOps = src->ops(operands);

                SmallVector<MicroInstrOperand, 8> newOps;
                for (uint32_t oi = 0; oi < src->numOperands; ++oi)
                    newOps.push_back(srcOps[oi]);

                if (src->op == MicroInstrOpcode::Label)
                {
                    newOps[0].valueU64 = labelMap[newOps[0].valueU64];
                }
                else if (src->op == MicroInstrOpcode::JumpCond)
                {
                    const auto remapIt = labelMap.find(newOps[2].valueU64);
                    if (remapIt != labelMap.end())
                        newOps[2].valueU64 = remapIt->second;
                }

                const MicroInstrRef newRef = storage.insertDerivedBefore(operands, addRef, src->op, {newOps.data(), newOps.size()});

                MicroInstr* inserted = storage.ptr(newRef);
                if (inserted && inserted->numOperands)
                {
                    SmallVector<MicroInstrRegOperandRef> regOps;
                    inserted->collectRegOperands(operands, regOps, context.encoder);
                    for (const MicroInstrRegOperandRef& regOp : regOps)
                    {
                        if (*regOp.reg == counter)
                            *regOp.reg = copyCounter;
                    }
                }

                const auto relocIt = relocsBySlot.find(srcRef.get());
                if (relocIt != relocsBySlot.end())
                {
                    for (MicroRelocation reloc : relocIt->second)
                    {
                        reloc.instructionRef = newRef;
                        builder.addRelocation(reloc);
                    }
                }
            }
        }

        // Post-loop readers of the counter see its exit value.
        MicroInstrOperand exitOps[3];
        exitOps[0].reg    = counter;
        exitOps[1].opBits = counterBits;
        exitOps[2].setImmediateValue(ApInt(initValue + trips * step, getNumBits(counterBits)));
        storage.insertDerivedBefore(operands, addRef, MicroInstrOpcode::LoadRegImm, exitOps);

        storage.erase(addRef);
        storage.erase(cmpRef);
        storage.erase(jccRef);

        builder.invalidateControlFlowGraph();
        context.passChanged = true;

        // One unroll per run: the pass manager's loop cleans the copies and
        // brings us back for any remaining candidate.
        return Result::Continue;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
