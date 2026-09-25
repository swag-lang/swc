#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoopUnroll.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"

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
    // Ordinary loops stop at sixteen trips. A loop indexing immutable
    // constant storage can go further when the body-size budget admits it:
    // every fixed index exposes a constant lookup to later passes. The total
    // instruction caps bound growth in both cases.
    constexpr uint64_t K_MAX_TRIPS       = 16;
    constexpr uint32_t K_MAX_BODY_INSTR  = 96;
    constexpr uint32_t K_MAX_TOTAL_INSTR = 384;
    // A body with branches usually keeps its tests and jumps after unrolling.
    // The exception below is a short loop over constant tables: each fixed
    // index lets later passes fold a table lookup despite those branches.
    constexpr uint32_t K_MAX_TOTAL_INSTR_WITH_BRANCHES = 96;

    struct LabelInfo
    {
        uint32_t ordinal   = std::numeric_limits<uint32_t>::max();
        uint32_t firstJump = std::numeric_limits<uint32_t>::max();
        uint32_t lastJump  = std::numeric_limits<uint32_t>::max();
    };

    bool defsRegister(const MicroInstr& inst, const MicroOperandStorage& operands, const Encoder* encoder, const MicroReg reg)
    {
        const MicroInstrUseDef useDef = inst.collectUseDef(operands, encoder);
        return std::ranges::find(useDef.defs, reg) != useDef.defs.end();
    }

    // A short, straight-line indexed read loop can pay one bound test for four
    // reads. Keep the original loop as the scalar tail, and use displacements
    // for the other three reads so its induction value advances only once.
    bool partiallyUnrollIndexedReadLoop(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands,
                                        MicroBuilder& builder, const std::vector<MicroInstrRef>& order,
                                        const std::unordered_map<uint32_t, SmallVector<MicroRelocation, 2>>& relocsBySlot,
                                        const uint32_t headerOrdinal, const uint32_t jumpOrdinal, const uint64_t headerId)
    {
        if (headerOrdinal + 4 > jumpOrdinal || jumpOrdinal + 1 >= order.size())
            return false;
        const MicroInstr*        compare = storage.ptr(order[jumpOrdinal - 1]);
        const MicroInstr*        step    = storage.ptr(order[jumpOrdinal - 2]);
        const MicroInstr*        jump    = storage.ptr(order[jumpOrdinal]);
        const MicroInstrOperand* cmpOps  = compare ? compare->ops(operands) : nullptr;
        const MicroInstrOperand* stepOps = step ? step->ops(operands) : nullptr;
        const MicroInstrOperand* jumpOps = jump ? jump->ops(operands) : nullptr;
        if (!compare || compare->op != MicroInstrOpcode::CmpRegReg || !cmpOps ||
            !step || step->op != MicroInstrOpcode::OpBinaryRegImm || !stepOps ||
            !jumpOps || jumpOps[0].cpuCond != MicroCond::Below ||
            stepOps[2].microOp != MicroOp::Add || stepOps[3].hasWideImmediateValue() || stepOps[3].valueU64 != 1 ||
            cmpOps[0].reg != stepOps[0].reg || cmpOps[0].reg == cmpOps[1].reg ||
            !cmpOps[0].reg.isVirtualInt() || !cmpOps[1].reg.isVirtualInt() ||
            cmpOps[2].opBits != MicroOpBits::B64 || stepOps[1].opBits != MicroOpBits::B64)
            return false;

        const MicroReg counter = cmpOps[0].reg;
        const MicroReg bound   = cmpOps[1].reg;
        bool haveZeroInit = false;
        for (uint32_t back = 1; back <= 8 && back <= headerOrdinal; ++back)
        {
            const MicroInstr* inst = storage.ptr(order[headerOrdinal - back]);
            if (!inst || inst->op == MicroInstrOpcode::Label)
                break;
            if (!defsRegister(*inst, operands, context.encoder, counter))
                continue;
            const MicroInstrOperand* ops = inst->ops(operands);
            haveZeroInit = inst->op == MicroInstrOpcode::ClearReg ||
                           (inst->op == MicroInstrOpcode::LoadRegImm && ops && ops[1].opBits == MicroOpBits::B64 &&
                            !ops[2].hasWideImmediateValue() && ops[2].valueU64 == 0);
            break;
        }
        if (!haveZeroInit)
            return false;

        const uint32_t bodyBegin = headerOrdinal + 1;
        const uint32_t bodyEnd   = jumpOrdinal - 2;
        const uint32_t bodyCount = bodyEnd - bodyBegin;
        if (!bodyCount || bodyCount > 12)
            return false;
        bool indexedRead = false;
        std::unordered_set<MicroReg> indexedBases;
        std::unordered_set<MicroReg> bodyDefs;
        for (uint32_t ordinal = bodyBegin; ordinal < bodyEnd; ++ordinal)
        {
            const MicroInstrRef      ref  = order[ordinal];
            const MicroInstr*        inst = storage.ptr(ref);
            const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!inst || !ops || relocsBySlot.contains(ref.get()))
                return false;
            const MicroInstrDef& info = MicroInstr::info(inst->op);
            if (inst->op == MicroInstrOpcode::Label ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::WritesMemory) ||
                MicroPassHelpers::instructionActuallyUsesCpuFlags(*inst, ops))
                return false;
            const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
            bodyDefs.insert(useDef.defs.begin(), useDef.defs.end());
            if (std::ranges::find(useDef.defs, counter) != useDef.defs.end() ||
                std::ranges::find(useDef.defs, bound) != useDef.defs.end())
                return false;
            if (std::ranges::find(useDef.uses, counter) == useDef.uses.end())
                continue;
            if ((inst->op != MicroInstrOpcode::LoadAmcRegMem && inst->op != MicroInstrOpcode::LoadZeroExtAmcRegMem) ||
                ops[1].reg == counter ||
                ops[2].reg != counter || ops[5].valueU64 != 1 ||
                ops[6].hasWideImmediateValue() || ops[6].valueU64 > static_cast<uint64_t>(INT32_MAX - 3))
                return false;
            indexedRead = true;
            indexedBases.insert(ops[1].reg);
        }
        if (!indexedRead)
            return false;
        for (const MicroReg base : indexedBases)
        {
            if (bodyDefs.contains(base))
                return false;
        }

        const uint32_t nextVirtual = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
        if (nextVirtual >= MicroReg::K_MAX_INDEX)
            return false;
        const MicroReg limit = MicroReg::virtualIntReg(nextVirtual);
        const uint64_t groupId = builder.createLabel().get();
        const uint64_t exitId  = builder.createLabel().get();
        const MicroInstrRef headerRef = order[headerOrdinal];
        const MicroInstrRef afterRef  = order[jumpOrdinal + 1];
        const MicroInstrOperand jumpBits = jumpOps[1];
        const MicroInstrOperand originalCmp[3] = {cmpOps[0], cmpOps[1], cmpOps[2]};
        const MicroInstrOperand originalStep[4] = {stepOps[0], stepOps[1], stepOps[2], stepOps[3]};

        MicroInstrOperand boundCheck[3] = {};
        boundCheck[0].reg = bound;
        boundCheck[1].opBits = MicroOpBits::B64;
        boundCheck[2].setImmediateValue(ApInt(4, 64));
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::CmpRegImm, boundCheck);
        MicroInstrOperand shortJump[3] = {};
        shortJump[0].cpuCond  = MicroCond::Below;
        shortJump[1]          = jumpBits;
        shortJump[2].valueU64 = headerId;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::JumpCond, shortJump);
        MicroInstrOperand limitCopy[3] = {};
        limitCopy[0].reg = limit;
        limitCopy[1].reg = bound;
        limitCopy[2].opBits = MicroOpBits::B64;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::LoadRegReg, limitCopy);
        MicroInstrOperand limitSub[4] = {};
        limitSub[0].reg = limit;
        limitSub[1].opBits = MicroOpBits::B64;
        limitSub[2].microOp = MicroOp::Subtract;
        limitSub[3].setImmediateValue(ApInt(3, 64));
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::OpBinaryRegImm, limitSub);
        MicroInstrOperand groupLabel[1] = {};
        groupLabel[0].valueU64 = groupId;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::Label, groupLabel);

        for (uint64_t copy = 0; copy < 4; ++copy)
        {
            for (uint32_t ordinal = bodyBegin; ordinal < bodyEnd; ++ordinal)
            {
                const MicroInstr* src = storage.ptr(order[ordinal]);
                const MicroInstrOperand* srcOps = src->ops(operands);
                SmallVector<MicroInstrOperand, 8> cloned;
                for (uint32_t index = 0; index < src->numOperands; ++index)
                    cloned.push_back(srcOps[index]);
                if ((src->op == MicroInstrOpcode::LoadAmcRegMem || src->op == MicroInstrOpcode::LoadZeroExtAmcRegMem) &&
                    cloned[2].reg == counter)
                    cloned[6].valueU64 += copy;
                storage.insertDerivedBefore(operands, headerRef, src->op, {cloned.data(), cloned.size()});
            }
        }
        MicroInstrOperand groupStep[4] = {originalStep[0], originalStep[1], originalStep[2], originalStep[3]};
        groupStep[3].setImmediateValue(ApInt(4, 64));
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::OpBinaryRegImm, groupStep);
        MicroInstrOperand groupCmp[3] = {};
        groupCmp[0].reg = counter;
        groupCmp[1].reg = limit;
        groupCmp[2].opBits = MicroOpBits::B64;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::CmpRegReg, groupCmp);
        MicroInstrOperand groupJump[3] = {};
        groupJump[0].cpuCond  = MicroCond::Below;
        groupJump[1]          = jumpBits;
        groupJump[2].valueU64 = groupId;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::JumpCond, groupJump);
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::CmpRegReg, originalCmp);
        MicroInstrOperand exitJump[3] = {};
        exitJump[0].cpuCond  = MicroCond::AboveOrEqual;
        exitJump[1]          = jumpBits;
        exitJump[2].valueU64 = exitId;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::JumpCond, exitJump);
        MicroInstrOperand exitLabel[1] = {};
        exitLabel[0].valueU64 = exitId;
        storage.insertDerivedBefore(operands, afterRef, MicroInstrOpcode::Label, exitLabel);

        builder.invalidateControlFlowGraph();
        context.passChanged = true;
        return true;
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

    // Unroll every candidate in this one run: leaving the rest for later runs
    // would spend one fixed-point iteration per loop, and a function with
    // many small counted loops then exhausts the optimization loop's budget
    // before reaching its fixed point. Each unroll invalidates the layout, so
    // the scan restarts from a fresh one until a sweep finds nothing.
    for (bool unrolledOne = true; unrolledOne;)
    {
        unrolledOne = false;

        // Program layout: ordinals, label positions, and every jump with its target.
        std::vector<MicroInstrRef>                 order;
        std::unordered_map<uint64_t, LabelInfo>    labels;
        std::vector<std::pair<uint32_t, uint64_t>> jumps;
        order.reserve(storage.count());

        for (auto it = storage.view().begin(), endIt = storage.view().end(); it != endIt; ++it)
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
                labels[ops[0].valueU64].ordinal = ord;
            else if (inst.op == MicroInstrOpcode::JumpCond && inst.numOperands >= 3)
            {
                jumps.emplace_back(ord, ops[2].valueU64);
                LabelInfo& target = labels[ops[2].valueU64];
                if (target.firstJump == std::numeric_limits<uint32_t>::max())
                    target.firstJump = ord;
                target.lastJump = ord;
            }
        }

        // Labels a relocation points at are pinned; relocations by owning slot
        // let clones keep the tables and constants the body reads.
        std::unordered_set<uint64_t>                                  relocLabels;
        std::unordered_map<uint32_t, SmallVector<MicroRelocation, 2>> relocsBySlot;
        bool                                                          relocationsIndexed = false;

        for (const auto& [jccOrdinal, headerId] : jumps)
        {
            const LabelInfo& label = labels.at(headerId);
            if (label.ordinal == std::numeric_limits<uint32_t>::max())
                continue;
            const uint32_t h = label.ordinal;
            // Backward jump with room for add/cmp plus at least one body instruction.
            if (h + 4 > jccOrdinal)
                continue;
            // No candidate can use the tables before this point. The layout
            // and relocations are unchanged until a successful unroll ends the sweep.
            if (!relocationsIndexed)
            {
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
                relocationsIndexed = true;
            }
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
            if (label.firstJump != label.lastJump)
                continue;

            // The latch: add %i, step / cmp %i, N / jcc H.
            const MicroInstr* cmp = storage.ptr(order[jccOrdinal - 1]);
            const MicroInstr* add = storage.ptr(order[jccOrdinal - 2]);
            if (cmp && add && cmp->op == MicroInstrOpcode::CmpRegReg && add->op == MicroInstrOpcode::OpBinaryRegImm &&
                partiallyUnrollIndexedReadLoop(context, storage, operands, builder, order, relocsBySlot, h, jccOrdinal, headerId))
            {
                unrolledOne = true;
                break;
            }
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
            if (trips < 2)
                continue;

            const uint32_t bodyBegin = h + 1;
            const uint32_t bodyEnd   = jccOrdinal - 2;
            const uint32_t bodyCount = bodyEnd - bodyBegin;
            if (!bodyCount || bodyCount > K_MAX_BODY_INSTR || trips > K_MAX_TOTAL_INSTR / bodyCount)
                continue;

            // Body scan: collect internal labels, verify every branch is either
            // internal (remappable) or a forward exit, and that nothing but the
            // latch touches the counter.
            std::unordered_set<uint64_t> internalLabels;
            bool                         ok = true;
            SmallVector<MicroReg, 4>     constantTableBases;
            SmallVector<MicroReg, 4>     indexValues;
            indexValues.push_back(counter);
            uint32_t                    indexedConstantLoads = 0;
            for (uint32_t o = bodyBegin; o < bodyEnd && ok; ++o)
            {
                const MicroInstr*        inst = storage.ptr(order[o]);
                const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
                if (!inst)
                {
                    ok = false;
                    break;
                }
                if (ops && inst->op == MicroInstrOpcode::LoadRegPtrReloc)
                {
                    const auto relocIt = relocsBySlot.find(order[o].get());
                    if (relocIt != relocsBySlot.end() && std::ranges::any_of(relocIt->second, [](const MicroRelocation& reloc) {
                            return reloc.kind == MicroRelocation::Kind::ConstantAddress;
                        }))
                        constantTableBases.push_back(ops[0].reg);
                }
                if (ops && (inst->op == MicroInstrOpcode::LoadSignedExtRegReg ||
                            inst->op == MicroInstrOpcode::LoadZeroExtRegReg || inst->op == MicroInstrOpcode::LoadRegReg) &&
                    std::ranges::find(indexValues, ops[1].reg) != indexValues.end())
                    indexValues.push_back(ops[0].reg);
                if (ops && inst->op == MicroInstrOpcode::LoadAmcRegMem &&
                    std::ranges::find(constantTableBases, ops[1].reg) != constantTableBases.end() &&
                    std::ranges::find(indexValues, ops[2].reg) != indexValues.end())
                    ++indexedConstantLoads;

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
                        const auto targetIt = labels.find(ops[2].valueU64);
                        if (targetIt == labels.end() || targetIt->second.ordinal == std::numeric_limits<uint32_t>::max())
                        {
                            ok = false;
                            break;
                        }
                        const uint32_t targetOrdinal = targetIt->second.ordinal;
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

            // A counted index into immutable storage becomes a constant offset in
            // each copy. This can repay the branch duplication within the overall
            // code-size cap; ordinary branched loops keep the smaller budget.
            const bool foldsTableIndices = indexedConstantLoads != 0;
            if (trips > K_MAX_TRIPS && !foldsTableIndices)
                continue;
            if (!internalLabels.empty() && bodyCount * trips > K_MAX_TOTAL_INSTR_WITH_BRANCHES && !foldsTableIndices)
                continue;

            // No jump from outside the body may land on an internal label.
            // The layout is ordered, so its first and last incoming jumps
            // bound every source without rescanning all function jumps.
            for (const uint64_t target : internalLabels)
            {
                const LabelInfo& internal = labels.at(target);
                if (internal.firstJump != std::numeric_limits<uint32_t>::max() &&
                    (internal.firstJump < bodyBegin || internal.lastJump >= bodyEnd))
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

            // A copy defines the body's temporaries anew. A register the body
            // writes outright before it reads it, and nothing outside the body
            // reads, is a temporary of one trip: it takes a fresh name at each
            // such write, so the copies are distinct values the passes behind
            // can reason about — value numbering merges the same computation
            // across copies, the peephole folds an address into its one
            // reader — where one name written eight times is opaque to both.
            // A register the body reads before writing carries a value from
            // the trip before, around an enclosing loop too, so it keeps its
            // name, and so does an in-place update and a register the
            // allocator has constraints on. Internal control flow makes a
            // linear renaming wrong at a join, so a body with labels keeps
            // every name.
            std::unordered_set<MicroReg> renamable;
            bool                         hasRenamableFloat = false;
            MicroInstrRegOperandRefs regOps;
            if (internalLabels.empty())
            {
                std::unordered_set<MicroReg> seenInBody;
                for (uint32_t o = bodyBegin; o < bodyEnd; ++o)
                {
                    MicroInstr* inst = storage.ptr(order[o]);
                    if (!inst || !inst->numOperands)
                        continue;
                    const MicroInstrOperand* ops = inst->ops(operands);
                    const auto modes = MicroInstr::info(inst->op).resolvedRegModes(ops);
                    // The reads of an instruction come before its writes: a
                    // register first met as a read, or as an in-place update,
                    // is carried; one first met as an outright write is a
                    // temporary.
                    for (size_t i = 0; i < modes.size(); ++i)
                        if ((modes[i] == MicroInstrRegMode::Use || modes[i] == MicroInstrRegMode::UseDef) && ops[i].reg.isVirtual())
                            seenInBody.insert(ops[i].reg);
                    for (size_t i = 0; i < modes.size(); ++i)
                    {
                        if (modes[i] != MicroInstrRegMode::Def || !ops[i].reg.isVirtual())
                            continue;
                        if (seenInBody.insert(ops[i].reg).second)
                            renamable.insert(ops[i].reg);
                    }
                }

                // Only the body's candidates matter outside it. Remove them
                // directly instead of recording every unrelated register read.
                const auto excludeOutsideReads = [&](uint32_t begin, uint32_t end) {
                    for (uint32_t o = begin; o < end && !renamable.empty(); ++o)
                    {
                        const MicroInstr* inst = storage.ptr(order[o]);
                        if (!inst || !inst->numOperands)
                            continue;
                        const MicroInstrOperand* ops = inst->ops(operands);
                        const auto modes = MicroInstr::info(inst->op).resolvedRegModes(ops);
                        for (size_t i = 0; i < modes.size(); ++i)
                            if ((modes[i] == MicroInstrRegMode::Use || modes[i] == MicroInstrRegMode::UseDef) && ops[i].reg.isVirtual())
                                renamable.erase(ops[i].reg);
                    }
                };
                excludeOutsideReads(0, bodyBegin);
                excludeOutsideReads(bodyEnd, static_cast<uint32_t>(order.size()));
                renamable.erase(counter);
                std::erase_if(renamable, [&](const MicroReg reg) {
                    if (builder.virtualRegForbiddenPhysRegs().contains(reg) || builder.shouldPreserveVirtualCopy(reg))
                        return true;
                    hasRenamableFloat = hasRenamableFloat || reg.isVirtualFloat();
                    return false;
                });
            }

            // The renaming analysis is read-only, so both files can share one
            // scan here while still observing the original instruction stream.
            uint32_t firstFreshVirtual = 0;
            uint32_t nextFreshFloat    = 0;
            if (hasRenamableFloat)
                MicroPassHelpers::computeNextVirtualRegIndices(context, firstFreshVirtual, nextFreshFloat);
            else
                firstFreshVirtual = MicroPassHelpers::computeNextVirtualIntRegIndex(context);

            std::unordered_map<MicroReg, MicroReg> currentName;
            uint32_t                               nextFreshInt = firstFreshVirtual + static_cast<uint32_t>(trips) - 1;
            std::unordered_map<uint64_t, uint64_t> labelMap;
            labelMap.reserve(internalLabels.size());
            SmallVector<MicroInstrOperand, 8> newOps;

            for (uint64_t k = 1; k < trips; ++k)
            {
                const MicroReg copyCounter = MicroReg::virtualIntReg(firstFreshVirtual + static_cast<uint32_t>(k) - 1);

                MicroInstrOperand counterOps[3];
                counterOps[0].reg    = copyCounter;
                counterOps[1].opBits = counterBits;
                counterOps[2].setImmediateValue(ApInt(initValue + k * step, getNumBits(counterBits)));
                storage.insertDerivedBefore(operands, addRef, MicroInstrOpcode::LoadRegImm, counterOps);

                labelMap.clear();
                for (const uint64_t id : internalLabels)
                    labelMap.emplace(id, builder.createLabel().get());

                for (uint32_t o = bodyBegin; o < bodyEnd; ++o)
                {
                    const MicroInstrRef      srcRef = order[o];
                    const MicroInstr*        src    = storage.ptr(srcRef);
                    const MicroInstrOperand* srcOps = src->ops(operands);

                    newOps.clear();
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
                        regOps.clear();
                        inserted->collectRegOperands(operands, regOps, context.encoder);

                        // The reads first, under the name the previous write
                        // gave the register, then the outright writes under a
                        // fresh one: an instruction that reads a register and
                        // writes it anew reads the old name.
                        for (const MicroInstrRegOperandRef& regOp : regOps)
                        {
                            if (*regOp.reg == counter)
                                *regOp.reg = copyCounter;
                            else if (regOp.use && renamable.contains(*regOp.reg))
                            {
                                const auto nameIt = currentName.find(*regOp.reg);
                                if (nameIt != currentName.end())
                                    *regOp.reg = nameIt->second;
                            }
                        }
                        for (const MicroInstrRegOperandRef& regOp : regOps)
                        {
                            if (!regOp.def || regOp.use || !renamable.contains(*regOp.reg))
                                continue;
                            const MicroReg original = *regOp.reg;
                            MicroReg       fresh;
                            if (original.isVirtualFloat())
                            {
                                SWC_ASSERT(nextFreshFloat < MicroReg::K_MAX_INDEX);
                                fresh = MicroReg::virtualFloatReg(nextFreshFloat++);
                            }
                            else
                            {
                                SWC_ASSERT(nextFreshInt < MicroReg::K_MAX_INDEX);
                                fresh = MicroReg::virtualIntReg(nextFreshInt++);
                            }
                            currentName[original] = fresh;
                            *regOp.reg            = fresh;
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

            // Layout is stale: restart the scan for the next candidate.
            unrolledOne = true;
            break;
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
