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
//
// A nest unrolls from the outside in. An inner counted loop whose start is
// the outer counter plus a constant - `for j in i + 1 until N` - has no
// constant trip count of its own, but each copy of the outer body hands it
// one: the sweep after the outer unroll folds the start, drops the zero-trip
// guard that tested it, and the inner loop is then an ordinary candidate.

SWC_BEGIN_NAMESPACE();

namespace
{
    // Ordinary loops stop at sixteen trips. Four or fewer trips over constant
    // tables admit a larger body: fixed indices expose constant loads to later
    // passes, even when branches make the original body fairly large.
    constexpr uint64_t K_MAX_TRIPS                = 16;
    constexpr uint64_t K_MAX_WIDE_TABLE_TRIPS     = 4;
    constexpr uint32_t K_MAX_BODY_INSTR           = 144;
    constexpr uint32_t K_MAX_TOTAL_INSTR          = 576;
    constexpr uint32_t K_MAX_ORDINARY_BODY_INSTR  = 96;
    constexpr uint32_t K_MAX_ORDINARY_TOTAL_INSTR = 384;
    // A body with branches usually keeps its tests and jumps after unrolling.
    // The exception below is a short loop over constant tables: each fixed
    // index lets later passes fold a table lookup despite those branches.
    constexpr uint32_t K_MAX_TOTAL_INSTR_WITH_BRANCHES = 96;
    // A nest whose inner loops all flatten leaves no branch behind, and both
    // element indices of a pair become constants. It may take twice an
    // ordinary loop's budget, counted on the code that remains once every
    // inner loop has been unrolled in its turn.
    constexpr uint32_t K_MAX_NEST_TOTAL_INSTR = 2 * K_MAX_ORDINARY_TOTAL_INSTR;

    struct LabelInfo
    {
        uint32_t ordinal   = std::numeric_limits<uint32_t>::max();
        uint32_t firstJump = std::numeric_limits<uint32_t>::max();
        uint32_t lastJump  = std::numeric_limits<uint32_t>::max();
    };

    bool defsRegister(const MicroInstr& inst, const MicroOperandStorage& operands, const Encoder* encoder, const MicroReg reg)
    {
        SWC_ASSERT(reg.isVirtualInt());
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
            (encoder && info.flags.has(MicroInstrFlagsE::EncoderRegUseDef)))
        {
            const MicroInstrUseDef useDef = inst.collectUseDef(operands, encoder);
            return std::ranges::find(useDef.defs, reg) != useDef.defs.end();
        }

        const MicroInstrOperand* ops = inst.ops(operands);
        if (!ops)
            return false;
        const auto modes = info.resolvedRegModes(ops);
        for (size_t operand = 0; operand < modes.size(); ++operand)
        {
            if ((modes[operand] == MicroInstrRegMode::Def || modes[operand] == MicroInstrRegMode::UseDef) && ops[operand].reg == reg)
                return true;
        }
        return false;
    }

    // Whether the jump a compare of the two values feeds is taken.
    bool evaluateCompare(bool& outTaken, const MicroCond cond, const int64_t lhs, const int64_t rhs)
    {
        const uint64_t ulhs = static_cast<uint64_t>(lhs);
        const uint64_t urhs = static_cast<uint64_t>(rhs);
        switch (cond)
        {
            case MicroCond::Equal:
            case MicroCond::Zero:
                outTaken = lhs == rhs;
                return true;
            case MicroCond::NotEqual:
            case MicroCond::NotZero:
                outTaken = lhs != rhs;
                return true;
            case MicroCond::Less:
                outTaken = lhs < rhs;
                return true;
            case MicroCond::LessOrEqual:
                outTaken = lhs <= rhs;
                return true;
            case MicroCond::Greater:
                outTaken = lhs > rhs;
                return true;
            case MicroCond::GreaterOrEqual:
                outTaken = lhs >= rhs;
                return true;
            case MicroCond::Below:
                outTaken = ulhs < urhs;
                return true;
            case MicroCond::BelowOrEqual:
            case MicroCond::NotAbove:
                outTaken = ulhs <= urhs;
                return true;
            case MicroCond::Above:
                outTaken = ulhs > urhs;
                return true;
            case MicroCond::AboveOrEqual:
                outTaken = ulhs >= urhs;
                return true;
            default:
                return false;
        }
    }

    // A counted loop: its body, from the instruction after the header to the
    // one before the latch, and what decides how often the latch jumps.
    struct CountedLoop
    {
        uint32_t bodyBegin = 0;
        uint32_t bodyEnd   = 0;
        MicroReg counter   = MicroReg::invalid();
        uint64_t initValue = 0;
        uint64_t step      = 0;
        uint64_t trips     = 0;
    };

    // The size of a nest once the outer loop and then every inner loop are
    // unrolled. The body qualifies when its only control flow is inner counted
    // loops that start at the outer counter plus a constant, and the guards
    // that compare such a value with a constant: each copy of the outer body
    // then knows every trip count and every guard's outcome. An inner loop
    // must also pass the limits it will meet as an ordinary candidate, or the
    // outer unroll would only multiply loops.
    bool flattenedNestSize(uint64_t& outTotal, const MicroPassContext& context, const MicroStorage& storage, const MicroOperandStorage& operands, const std::vector<MicroInstrRef>& order, const std::unordered_map<uint64_t, LabelInfo>& labels, const CountedLoop& outer)
    {
        struct InnerLoop
        {
            uint32_t jump       = 0;
            uint64_t step       = 0;
            uint64_t bound      = 0;
            int64_t  initOffset = 0;
        };
        struct Guard
        {
            uint32_t  target = 0;
            MicroCond cond   = MicroCond::Equal;
            int64_t   offset = 0;
            int64_t   value  = 0;
        };
        std::unordered_map<uint32_t, InnerLoop> innerByHeader;
        std::unordered_map<uint32_t, Guard>     guardByJump;
        std::unordered_map<MicroReg, int64_t>   offsets;
        offsets.emplace(outer.counter, 0);

        const auto labelOrdinal = [&](const uint64_t id) {
            const auto it = labels.find(id);
            return it == labels.end() ? std::numeric_limits<uint32_t>::max() : it->second.ordinal;
        };

        // Inner latches first: the walk below meets a header before its latch.
        for (uint32_t o = outer.bodyBegin; o < outer.bodyEnd; ++o)
        {
            const MicroInstr*        inst = storage.ptr(order[o]);
            const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!inst || inst->op != MicroInstrOpcode::JumpCond || !ops || inst->numOperands < 3)
                continue;
            const uint32_t target = labelOrdinal(ops[2].valueU64);
            if (target >= o)
                continue;
            if (target < outer.bodyBegin || o < target + 4)
                return false;

            const MicroInstr*        cmp    = storage.ptr(order[o - 1]);
            const MicroInstr*        add    = storage.ptr(order[o - 2]);
            const MicroInstrOperand* cmpOps = cmp ? cmp->ops(operands) : nullptr;
            const MicroInstrOperand* addOps = add ? add->ops(operands) : nullptr;
            if (!cmpOps || !addOps || cmp->op != MicroInstrOpcode::CmpRegImm || add->op != MicroInstrOpcode::OpBinaryRegImm ||
                (ops[0].cpuCond != MicroCond::Less && ops[0].cpuCond != MicroCond::Below) ||
                addOps[2].microOp != MicroOp::Add || addOps[0].reg != cmpOps[0].reg || !cmpOps[0].reg.isVirtualInt() ||
                cmpOps[2].hasWideImmediateValue() || addOps[3].hasWideImmediateValue() ||
                addOps[3].valueU64 < 1 || addOps[3].valueU64 > 64 || cmpOps[2].valueU64 > 1000000)
                return false;
            const LabelInfo& header = labels.at(ops[2].valueU64);
            if (header.firstJump != o || header.lastJump != o)
                return false;

            // A straight-line inner body: the ordinary unroll then renames its temporaries.
            for (uint32_t b = target + 1; b + 2 < o; ++b)
            {
                const MicroInstr* body = storage.ptr(order[b]);
                if (!body || body->op == MicroInstrOpcode::Label)
                    return false;
                const MicroInstrDef& info = MicroInstr::info(body->op);
                if (info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    return false;
            }
            innerByHeader.emplace(target, InnerLoop{.jump = o, .step = addOps[3].valueU64, .bound = cmpOps[2].valueU64});
        }
        if (innerByHeader.empty())
            return false;

        // One walk in layout order: which registers hold the outer counter
        // plus a constant, where each inner counter starts, what each guard tests.
        for (uint32_t o = outer.bodyBegin; o < outer.bodyEnd; ++o)
        {
            const MicroInstr*        inst = storage.ptr(order[o]);
            const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!inst)
                return false;

            if (inst->op == MicroInstrOpcode::Label)
            {
                const auto innerIt = innerByHeader.find(o);
                if (innerIt == innerByHeader.end())
                    continue;
                const MicroInstrOperand* cmpOps   = storage.ptr(order[innerIt->second.jump - 1])->ops(operands);
                const auto               offsetIt = offsets.find(cmpOps[0].reg);
                if (offsetIt == offsets.end())
                    return false;
                innerIt->second.initOffset = offsetIt->second;
                continue;
            }

            if (inst->op == MicroInstrOpcode::JumpCond)
            {
                if (!ops || inst->numOperands < 3)
                    return false;
                const uint32_t target = labelOrdinal(ops[2].valueU64);
                if (target < o)
                    continue;
                const MicroInstr*        cmp    = storage.ptr(order[o - 1]);
                const MicroInstrOperand* cmpOps = cmp ? cmp->ops(operands) : nullptr;
                if (target >= outer.bodyEnd || !cmpOps || cmp->op != MicroInstrOpcode::CmpRegImm || cmpOps[2].hasWideImmediateValue())
                    return false;
                const auto offsetIt = offsets.find(cmpOps[0].reg);
                bool       probe    = false;
                if (offsetIt == offsets.end() || !evaluateCompare(probe, ops[0].cpuCond, 0, 0))
                    return false;
                guardByJump.emplace(o, Guard{.target = target, .cond = ops[0].cpuCond, .offset = offsetIt->second, .value = static_cast<int64_t>(cmpOps[2].valueU64)});
                continue;
            }

            if (!ops)
                continue;
            std::optional<std::pair<MicroReg, int64_t>> derived;
            switch (inst->op)
            {
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadSignedExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegReg:
                    if (const auto it = offsets.find(ops[1].reg); it != offsets.end())
                        derived.emplace(ops[0].reg, it->second);
                    break;
                case MicroInstrOpcode::LoadAddrRegMem:
                    if (const auto it = offsets.find(ops[1].reg); it != offsets.end() && ops[3].valueU64 <= 1000000)
                        derived.emplace(ops[0].reg, it->second + static_cast<int64_t>(ops[3].valueU64));
                    break;
                default:
                    break;
            }

            const MicroInstrUseDef useDef = inst->collectUseDef(operands, context.encoder);
            for (const MicroReg def : useDef.defs)
                offsets.erase(def);
            if (derived && derived->first.isVirtualInt())
                offsets.insert_or_assign(derived->first, derived->second);
        }

        // Replay every copy of the outer body with its counter value.
        uint64_t total = 0;
        for (uint64_t k = 0; k < outer.trips; ++k)
        {
            const int64_t outerValue = static_cast<int64_t>(outer.initValue + k * outer.step);
            for (uint32_t o = outer.bodyBegin; o < outer.bodyEnd;)
            {
                if (const auto guardIt = guardByJump.find(o); guardIt != guardByJump.end())
                {
                    bool taken = false;
                    evaluateCompare(taken, guardIt->second.cond, outerValue + guardIt->second.offset, guardIt->second.value);
                    o = taken ? guardIt->second.target : o + 1;
                    continue;
                }

                const auto innerIt = innerByHeader.find(o);
                if (innerIt == innerByHeader.end())
                {
                    ++total;
                    ++o;
                    continue;
                }

                const InnerLoop& inner     = innerIt->second;
                const int64_t    start     = outerValue + inner.initOffset;
                const uint64_t   bodyCount = inner.jump - 2 - (o + 1);
                if (start < 0 || static_cast<uint64_t>(start) >= inner.bound || (inner.bound - static_cast<uint64_t>(start)) % inner.step != 0)
                    return false;
                const uint64_t innerTrips = (inner.bound - static_cast<uint64_t>(start)) / inner.step;
                if (!bodyCount || bodyCount > K_MAX_ORDINARY_BODY_INSTR || innerTrips > K_MAX_TRIPS || bodyCount * innerTrips > K_MAX_ORDINARY_TOTAL_INSTR)
                    return false;
                total += bodyCount * innerTrips;
                o = inner.jump + 1;
            }
        }

        outTotal = total;
        return true;
    }

    // A counted XOR checksum over 32-bit words can process four consecutive
    // words at once. The add wraps at 32 bits before each word is XORed into
    // the 64-bit accumulator, so the four packed lanes have identical values.
    bool vectorizeIndexedXorLoop(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, MicroBuilder& builder, const std::vector<MicroInstrRef>& order, const std::unordered_map<uint32_t, SmallVector<MicroRelocation, 2>>& relocsBySlot, const uint32_t headerOrdinal, const uint32_t jumpOrdinal)
    {
        if (jumpOrdinal != headerOrdinal + 7 || jumpOrdinal + 1 >= order.size())
            return false;

        const MicroInstr* load = storage.ptr(order[headerOrdinal + 1]);
        const MicroInstr* copy = storage.ptr(order[headerOrdinal + 2]);
        const MicroInstr* sum  = storage.ptr(order[headerOrdinal + 3]);
        const MicroInstr* fold = storage.ptr(order[headerOrdinal + 4]);
        const MicroInstr* step = storage.ptr(order[headerOrdinal + 5]);
        const MicroInstr* cmp  = storage.ptr(order[headerOrdinal + 6]);
        const MicroInstr* jump = storage.ptr(order[jumpOrdinal]);
        if (!load || !copy || !sum || !fold || !step || !cmp || !jump ||
            load->op != MicroInstrOpcode::LoadAmcRegMem || copy->op != MicroInstrOpcode::LoadRegReg ||
            sum->op != MicroInstrOpcode::OpBinaryRegReg || fold->op != MicroInstrOpcode::OpBinaryRegReg ||
            step->op != MicroInstrOpcode::OpBinaryRegImm || cmp->op != MicroInstrOpcode::CmpRegImm)
            return false;
        for (uint32_t o = headerOrdinal + 1; o <= jumpOrdinal; ++o)
            if (relocsBySlot.contains(order[o].get()))
                return false;

        const auto* loadOps = load->ops(operands);
        const auto* copyOps = copy->ops(operands);
        const auto* sumOps  = sum->ops(operands);
        const auto* foldOps = fold->ops(operands);
        const auto* stepOps = step->ops(operands);
        const auto* cmpOps  = cmp->ops(operands);
        const auto* jumpOps = jump->ops(operands);
        if (!loadOps || !copyOps || !sumOps || !foldOps || !stepOps || !cmpOps || !jumpOps ||
            loadOps[3].opBits != MicroOpBits::B32 || loadOps[4].opBits != MicroOpBits::B64 ||
            loadOps[5].valueU64 != 4 || loadOps[6].hasWideImmediateValue() || loadOps[6].valueU64 != 0 ||
            copyOps[2].opBits != MicroOpBits::B64 || copyOps[1].reg != loadOps[0].reg ||
            sumOps[0].reg != copyOps[0].reg || sumOps[1].reg != loadOps[2].reg ||
            sumOps[2].opBits != MicroOpBits::B32 || sumOps[3].microOp != MicroOp::Add ||
            foldOps[1].reg != copyOps[0].reg || foldOps[2].opBits != MicroOpBits::B64 || foldOps[3].microOp != MicroOp::Xor ||
            stepOps[0].reg != loadOps[2].reg || stepOps[1].opBits != MicroOpBits::B64 ||
            stepOps[2].microOp != MicroOp::Add || stepOps[3].hasWideImmediateValue() || stepOps[3].valueU64 != 1 ||
            cmpOps[0].reg != loadOps[2].reg || cmpOps[1].opBits != MicroOpBits::B64 ||
            cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 < 64 ||
            cmpOps[2].valueU64 % 4 != 0 || cmpOps[2].valueU64 > UINT32_MAX ||
            jumpOps[0].cpuCond != MicroCond::Below)
            return false;

        const MicroReg base    = loadOps[1].reg;
        const MicroReg counter = loadOps[2].reg;
        const MicroReg loaded  = loadOps[0].reg;
        const MicroReg value   = copyOps[0].reg;
        const MicroReg accum   = foldOps[0].reg;
        if (!base.isVirtualInt() || !counter.isVirtualInt() || !loaded.isVirtualInt() ||
            !value.isVirtualInt() || !accum.isVirtualInt() ||
            base == counter || base == loaded || base == value || base == accum ||
            counter == loaded || counter == value || counter == accum ||
            loaded == value || loaded == accum || value == accum)
            return false;

        bool haveZeroInit = false;
        for (uint32_t back = 1; back <= 8 && back <= headerOrdinal; ++back)
        {
            const MicroInstr* inst = storage.ptr(order[headerOrdinal - back]);
            if (!inst || inst->op == MicroInstrOpcode::Label)
                break;
            if (!defsRegister(*inst, operands, context.encoder, counter))
                continue;
            const auto* ops = inst->ops(operands);
            haveZeroInit    = inst->op == MicroInstrOpcode::ClearReg ||
                           (inst->op == MicroInstrOpcode::LoadRegImm && ops && ops[1].opBits == MicroOpBits::B64 &&
                            !ops[2].hasWideImmediateValue() && ops[2].valueU64 == 0);
            break;
        }
        if (!haveZeroInit)
            return false;

        // The scalar temporaries disappear with the body. Neither may have a
        // reader outside it, including a reader after the loop.
        for (uint32_t o = 0; o < order.size(); ++o)
        {
            if (o >= headerOrdinal + 1 && o <= headerOrdinal + 4)
                continue;
            const MicroInstr* inst = storage.ptr(order[o]);
            if (!inst)
                return false;
            const auto& uses = inst->collectUseDef(operands, context.encoder).uses;
            if (std::ranges::find(uses, loaded) != uses.end() || std::ranges::find(uses, value) != uses.end())
                return false;
        }

        // Two independent packed accumulators shorten the XOR dependency chain
        // when an exact group of eight is available.
        const bool twoVectors = cmpOps[2].valueU64 >= 128 && cmpOps[2].valueU64 % 8 == 0;
        uint32_t   nextInt    = 0;
        uint32_t   nextFloat  = 0;
        MicroPassHelpers::computeNextVirtualRegIndices(context, nextInt, nextFloat);
        if (nextInt > MicroReg::K_MAX_INDEX - 3 || nextFloat > MicroReg::K_MAX_INDEX - (twoVectors ? 6u : 4u))
            return false;
        const MicroReg      scalar        = MicroReg::virtualIntReg(nextInt++);
        const MicroReg      ptr           = MicroReg::virtualIntReg(nextInt++);
        const MicroReg      lane          = MicroReg::virtualIntReg(nextInt);
        const MicroReg      index         = MicroReg::virtualFloatReg(nextFloat++);
        const MicroReg      stride        = MicroReg::virtualFloatReg(nextFloat++);
        const MicroReg      packed        = MicroReg::virtualFloatReg(nextFloat++);
        const MicroReg      temp          = MicroReg::virtualFloatReg(nextFloat++);
        const MicroReg      upperIndex    = twoVectors ? MicroReg::virtualFloatReg(nextFloat++) : MicroReg::invalid();
        const MicroReg      upperAccum    = twoVectors ? MicroReg::virtualFloatReg(nextFloat) : MicroReg::invalid();
        const MicroInstrRef headerRef     = order[headerOrdinal];
        const MicroInstrRef bodyRef       = order[headerOrdinal + 1];
        const MicroInstrRef afterRef      = order[jumpOrdinal + 1];
        MicroInstrOperand   vectorStep[4] = {stepOps[0], stepOps[1], stepOps[2], stepOps[3]};
        vectorStep[3].setImmediateValue(ApInt(twoVectors ? 8 : 4, 64));
        const auto insert = [&](MicroInstrRef before, MicroInstrOpcode op, std::span<const MicroInstrOperand> args) {
            storage.insertDerivedBefore(operands, before, op, args);
        };
        const auto emitImmediate = [&](MicroInstrRef before, MicroReg dst, uint32_t imm) {
            MicroInstrOperand args[3] = {};
            args[0].reg               = dst;
            args[1].opBits            = MicroOpBits::B32;
            args[2].setImmediateValue(ApInt(imm, 32));
            insert(before, MicroInstrOpcode::LoadRegImm, args);
        };
        const auto emitBinary = [&](MicroInstrRef before, MicroReg dst, MicroReg src, MicroOp op, MicroOpBits bits) {
            MicroInstrOperand args[4] = {};
            args[0].reg               = dst;
            args[1].reg               = src;
            args[2].opBits            = bits;
            args[3].microOp           = op;
            insert(before, MicroInstrOpcode::OpBinaryRegReg, args);
        };
        const auto emitShuffle = [&](MicroInstrRef before, MicroReg dst, MicroReg src, uint8_t control) {
            MicroInstrOperand args[4] = {};
            args[0].reg               = dst;
            args[1].reg               = src;
            args[2].opBits            = MicroOpBits::B128;
            args[3].valueU64          = control;
            insert(before, MicroInstrOpcode::VecShuffleRegRegImm, args);
        };
        const auto emitCopy = [&](MicroInstrRef before, MicroReg dst, MicroReg src, MicroOpBits bits) {
            MicroInstrOperand args[3] = {};
            args[0].reg               = dst;
            args[1].reg               = src;
            args[2].opBits            = bits;
            insert(before, MicroInstrOpcode::LoadRegReg, args);
        };

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = index;
        clear[1].opBits            = MicroOpBits::B128;
        insert(headerRef, MicroInstrOpcode::ClearReg, clear);
        for (uint32_t laneIndex = 1; laneIndex < 4; ++laneIndex)
        {
            emitImmediate(headerRef, scalar, laneIndex);
            MicroInstrOperand args[6] = {};
            args[0].reg               = index;
            args[1].reg               = index;
            args[2].reg               = scalar;
            args[3].opBits            = MicroOpBits::B128;
            args[4].microOp           = MicroOp::VecInsert32;
            args[5].valueU64          = laneIndex;
            insert(headerRef, MicroInstrOpcode::OpTernaryRegRegRegImm, args);
        }
        emitImmediate(headerRef, scalar, 4);
        emitCopy(headerRef, stride, scalar, MicroOpBits::B32);
        emitShuffle(headerRef, stride, stride, 0);
        if (twoVectors)
        {
            emitCopy(headerRef, upperIndex, index, MicroOpBits::B128);
            emitBinary(headerRef, upperIndex, stride, MicroOp::VecAdd32, MicroOpBits::B128);
            emitImmediate(headerRef, scalar, 8);
            emitCopy(headerRef, stride, scalar, MicroOpBits::B32);
            emitShuffle(headerRef, stride, stride, 0);
        }
        clear[0].reg = packed;
        insert(headerRef, MicroInstrOpcode::ClearReg, clear);
        if (twoVectors)
        {
            clear[0].reg = upperAccum;
            insert(headerRef, MicroInstrOpcode::ClearReg, clear);
        }

        MicroInstrOperand address[8] = {};
        address[0].reg               = ptr;
        address[1].reg               = base;
        address[2].reg               = counter;
        address[3].opBits            = MicroOpBits::B64;
        address[4].opBits            = MicroOpBits::B64;
        address[5].valueU64          = 4;
        insert(bodyRef, MicroInstrOpcode::LoadAddrAmcRegMem, address);
        MicroInstrOperand vecLoad[4] = {};
        vecLoad[0].reg               = temp;
        vecLoad[1].reg               = ptr;
        vecLoad[2].opBits            = MicroOpBits::B128;
        insert(bodyRef, MicroInstrOpcode::LoadVecRegMem, vecLoad);
        emitBinary(bodyRef, temp, index, MicroOp::VecAdd32, MicroOpBits::B128);
        emitBinary(bodyRef, packed, temp, MicroOp::VecXor, MicroOpBits::B128);
        if (twoVectors)
        {
            vecLoad[3].valueU64 = 16;
            insert(bodyRef, MicroInstrOpcode::LoadVecRegMem, vecLoad);
            emitBinary(bodyRef, temp, upperIndex, MicroOp::VecAdd32, MicroOpBits::B128);
            emitBinary(bodyRef, upperAccum, temp, MicroOp::VecXor, MicroOpBits::B128);
            emitBinary(bodyRef, upperIndex, stride, MicroOp::VecAdd32, MicroOpBits::B128);
        }
        emitBinary(bodyRef, index, stride, MicroOp::VecAdd32, MicroOpBits::B128);

        insert(order[headerOrdinal + 5], MicroInstrOpcode::OpBinaryRegImm, vectorStep);
        for (uint32_t o = headerOrdinal + 1; o <= headerOrdinal + 5; ++o)
            storage.erase(order[o]);

        if (twoVectors)
            emitBinary(afterRef, packed, upperAccum, MicroOp::VecXor, MicroOpBits::B128);
        emitShuffle(afterRef, temp, packed, 0x4E);
        emitBinary(afterRef, packed, temp, MicroOp::VecXor, MicroOpBits::B128);
        emitShuffle(afterRef, temp, packed, 0xB1);
        emitBinary(afterRef, packed, temp, MicroOp::VecXor, MicroOpBits::B128);
        emitCopy(afterRef, lane, packed, MicroOpBits::B32);
        emitBinary(afterRef, accum, lane, MicroOp::Xor, MicroOpBits::B64);

        builder.invalidateControlFlowGraph();
        context.passChanged = true;
        return true;
    }

    // A short, straight-line indexed read loop can pay one bound test for four
    // reads. Keep the original loop as the scalar tail, and use displacements
    // for the other three reads so its induction value advances only once.
    bool partiallyUnrollIndexedReadLoop(MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, MicroBuilder& builder, const std::vector<MicroInstrRef>& order, const std::unordered_map<uint32_t, SmallVector<MicroRelocation, 2>>& relocsBySlot, const uint32_t headerOrdinal, const uint32_t jumpOrdinal, const uint64_t headerId)
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

        const MicroReg counter      = cmpOps[0].reg;
        const MicroReg bound        = cmpOps[1].reg;
        bool           haveZeroInit = false;
        for (uint32_t back = 1; back <= 8 && back <= headerOrdinal; ++back)
        {
            const MicroInstr* inst = storage.ptr(order[headerOrdinal - back]);
            if (!inst || inst->op == MicroInstrOpcode::Label)
                break;
            if (!defsRegister(*inst, operands, context.encoder, counter))
                continue;
            const MicroInstrOperand* ops = inst->ops(operands);
            haveZeroInit                 = inst->op == MicroInstrOpcode::ClearReg ||
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
        bool                         indexedRead = false;
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
        const MicroReg          limit           = MicroReg::virtualIntReg(nextVirtual);
        const uint64_t          groupId         = builder.createLabel().get();
        const uint64_t          exitId          = builder.createLabel().get();
        const MicroInstrRef     headerRef       = order[headerOrdinal];
        const MicroInstrRef     afterRef        = order[jumpOrdinal + 1];
        const MicroInstrOperand jumpBits        = jumpOps[1];
        const MicroInstrOperand originalCmp[3]  = {cmpOps[0], cmpOps[1], cmpOps[2]};
        const MicroInstrOperand originalStep[4] = {stepOps[0], stepOps[1], stepOps[2], stepOps[3]};

        MicroInstrOperand boundCheck[3] = {};
        boundCheck[0].reg               = bound;
        boundCheck[1].opBits            = MicroOpBits::B64;
        boundCheck[2].setImmediateValue(ApInt(4, 64));
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::CmpRegImm, boundCheck);
        MicroInstrOperand shortJump[3] = {};
        shortJump[0].cpuCond           = MicroCond::Below;
        shortJump[1]                   = jumpBits;
        shortJump[2].valueU64          = headerId;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::JumpCond, shortJump);
        MicroInstrOperand limitCopy[3] = {};
        limitCopy[0].reg               = limit;
        limitCopy[1].reg               = bound;
        limitCopy[2].opBits            = MicroOpBits::B64;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::LoadRegReg, limitCopy);
        MicroInstrOperand limitSub[4] = {};
        limitSub[0].reg               = limit;
        limitSub[1].opBits            = MicroOpBits::B64;
        limitSub[2].microOp           = MicroOp::Subtract;
        limitSub[3].setImmediateValue(ApInt(3, 64));
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::OpBinaryRegImm, limitSub);
        MicroInstrOperand groupLabel[1] = {};
        groupLabel[0].valueU64          = groupId;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::Label, groupLabel);

        for (uint64_t copy = 0; copy < 4; ++copy)
        {
            for (uint32_t ordinal = bodyBegin; ordinal < bodyEnd; ++ordinal)
            {
                const MicroInstr*                 src    = storage.ptr(order[ordinal]);
                const MicroInstrOperand*          srcOps = src->ops(operands);
                SmallVector<MicroInstrOperand, 8> cloned;
                cloned.append(srcOps, src->numOperands);
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
        groupCmp[0].reg               = counter;
        groupCmp[1].reg               = limit;
        groupCmp[2].opBits            = MicroOpBits::B64;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::CmpRegReg, groupCmp);
        MicroInstrOperand groupJump[3] = {};
        groupJump[0].cpuCond           = MicroCond::Below;
        groupJump[1]                   = jumpBits;
        groupJump[2].valueU64          = groupId;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::JumpCond, groupJump);
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::CmpRegReg, originalCmp);
        MicroInstrOperand exitJump[3] = {};
        exitJump[0].cpuCond           = MicroCond::AboveOrEqual;
        exitJump[1]                   = jumpBits;
        exitJump[2].valueU64          = exitId;
        storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::JumpCond, exitJump);
        MicroInstrOperand exitLabel[1] = {};
        exitLabel[0].valueU64          = exitId;
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
    if (storage.count() < 5)
        return Result::Continue;

    // Unroll every candidate in this one run: leaving the rest for later runs
    // would spend one fixed-point iteration per loop, and a function with
    // many small counted loops then exhausts the optimization loop's budget
    // before reaching its fixed point. Each unroll invalidates the layout, so
    // the scan restarts from a fresh one until a sweep finds nothing.
    for (bool unrolledOne = true; unrolledOne;)
    {
        unrolledOne = false;

        // Program layout: ordinals, label positions, and plausible back-edge jumps.
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
                LabelInfo& target = labels[ops[2].valueU64];
                if (target.ordinal != std::numeric_limits<uint32_t>::max() && target.ordinal + 4 <= ord)
                    jumps.emplace_back(ord, ops[2].valueU64);
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
            if (!cmp || !add || add->op != MicroInstrOpcode::OpBinaryRegImm ||
                (cmp->op != MicroInstrOpcode::CmpRegReg && cmp->op != MicroInstrOpcode::CmpRegImm))
                continue;

            // Only a plausible latch can use the relocation tables. The layout
            // and relocations are unchanged until an unroll ends this sweep.
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

            if (cmp->op == MicroInstrOpcode::CmpRegImm &&
                vectorizeIndexedXorLoop(context, storage, operands, builder, order, relocsBySlot, h, jccOrdinal))
            {
                unrolledOne = true;
                break;
            }
            if (cmp->op == MicroInstrOpcode::CmpRegReg &&
                partiallyUnrollIndexedReadLoop(context, storage, operands, builder, order, relocsBySlot, h, jccOrdinal, headerId))
            {
                unrolledOne = true;
                break;
            }
            if (cmp->op != MicroInstrOpcode::CmpRegImm)
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
            // A single trip still loses its latch: the body runs once either way.
            const uint64_t trips = (bound - initValue) / step;

            const uint32_t bodyBegin = h + 1;
            const uint32_t bodyEnd   = jccOrdinal - 2;
            const uint32_t bodyCount = bodyEnd - bodyBegin;
            if (!bodyCount || bodyCount > K_MAX_BODY_INSTR)
                continue;

            // A pure addition or subtraction of the induction values has a
            // closed form. Folding it avoids the code growth of full unrolling.
            // The bound limits each term to one million, so the progression
            // calculation below fits in 64 bits before the accumulator's
            // intentional modular addition.
            if (bodyCount == 1 && cond == MicroCond::Below)
            {
                const MicroInstrRef bodyRef = order[bodyBegin];
                const MicroInstr*   body    = storage.ptr(bodyRef);
                const auto*         bodyOps = body ? body->ops(operands) : nullptr;
                if (body && body->op == MicroInstrOpcode::OpBinaryRegReg && bodyOps &&
                    (bodyOps[3].microOp == MicroOp::Add || bodyOps[3].microOp == MicroOp::Subtract) &&
                    (bodyOps[2].opBits == MicroOpBits::B32 || bodyOps[2].opBits == MicroOpBits::B64) &&
                    bodyOps[0].reg.isVirtualInt() && bodyOps[0].reg != counter && bodyOps[1].reg == counter &&
                    !relocsBySlot.contains(bodyRef.get()) &&
                    MicroPassHelpers::areCpuFlagsDeadAfterInCfg(builder, order[jccOrdinal]))
                {
                    const MicroReg    accumulator = bodyOps[0].reg;
                    const MicroOpBits sumBits     = bodyOps[2].opBits;
                    uint64_t          initialSum  = 0;
                    bool              haveSumInit = false;
                    for (uint32_t back = 1; back <= 16 && back <= h; ++back)
                    {
                        const MicroInstr* init = storage.ptr(order[h - back]);
                        if (!init)
                            break;
                        const MicroInstrDef& info = MicroInstr::info(init->op);
                        if (init->op == MicroInstrOpcode::Label ||
                            info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                            info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                            info.flags.has(MicroInstrFlagsE::IsCallInstruction))
                            break;
                        if (!defsRegister(*init, operands, context.encoder, accumulator))
                            continue;
                        const auto* initOps = init->ops(operands);
                        if (initOps && initOps[1].opBits == sumBits)
                        {
                            if (init->op == MicroInstrOpcode::ClearReg)
                                haveSumInit = true;
                            else if (init->op == MicroInstrOpcode::LoadRegImm && !initOps[2].hasWideImmediateValue())
                            {
                                initialSum  = initOps[2].valueU64;
                                haveSumInit = true;
                            }
                        }
                        break;
                    }
                    if (haveSumInit)
                    {
                        const uint64_t    progression  = trips * (2 * initValue + (trips - 1) * step) / 2;
                        const uint64_t    updatedSum   = bodyOps[3].microOp == MicroOp::Add ? initialSum + progression : initialSum - progression;
                        const uint64_t    finalSum     = sumBits == MicroOpBits::B32 ? static_cast<uint32_t>(updatedSum) : updatedSum;
                        const uint32_t    sumWidth     = sumBits == MicroOpBits::B32 ? 32 : 64;
                        const uint32_t    counterWidth = counterBits == MicroOpBits::B32 ? 32 : 64;
                        MicroInstrOperand resultOps[3] = {};
                        resultOps[0].reg               = accumulator;
                        resultOps[1].opBits            = sumBits;
                        resultOps[2].setImmediateValue(ApInt(finalSum, sumWidth));
                        storage.insertDerivedBefore(operands, bodyRef, MicroInstrOpcode::LoadRegImm, resultOps);

                        MicroInstrOperand exitOps[3] = {};
                        exitOps[0].reg               = counter;
                        exitOps[1].opBits            = counterBits;
                        exitOps[2].setImmediateValue(ApInt(initValue + trips * step, counterWidth));
                        storage.insertDerivedBefore(operands, order[jccOrdinal - 2], MicroInstrOpcode::LoadRegImm, exitOps);
                        storage.erase(bodyRef);
                        storage.erase(order[jccOrdinal - 2]);
                        storage.erase(order[jccOrdinal - 1]);
                        storage.erase(order[jccOrdinal]);
                        builder.invalidateControlFlowGraph();
                        context.passChanged = true;
                        unrolledOne         = true;
                        break;
                    }
                }
            }
            if (trips > K_MAX_TOTAL_INSTR / bodyCount)
                continue;

            // Body scan: collect internal labels, verify every branch is either
            // internal (remappable) or a forward exit, and that nothing but the
            // latch touches the counter.
            std::unordered_set<uint64_t> internalLabels;
            bool                         ok = true;
            SmallVector<MicroReg, 4>     constantTableBases;
            SmallVector<MicroReg, 4>     indexValues;
            indexValues.push_back(counter);
            uint32_t indexedConstantLoads = 0;
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
                if (ops && (inst->op == MicroInstrOpcode::LoadSignedExtRegReg || inst->op == MicroInstrOpcode::LoadZeroExtRegReg || inst->op == MicroInstrOpcode::LoadRegReg) &&
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

            // A nest that flattens completely is judged on its flattened size.
            bool flattensNest = false;
            if (!internalLabels.empty() && trips > 1 && !foldsTableIndices && bodyCount * trips > K_MAX_TOTAL_INSTR_WITH_BRANCHES)
            {
                const CountedLoop outer{.bodyBegin = bodyBegin, .bodyEnd = bodyEnd, .counter = counter, .initValue = initValue, .step = step, .trips = trips};
                uint64_t          flattened = 0;
                flattensNest                = flattenedNestSize(flattened, context, storage, operands, order, labels, outer) && flattened <= K_MAX_NEST_TOTAL_INSTR;
            }

            // One trip copies nothing, so no size limit applies to it.
            const bool growsCode = trips > 1 && !flattensNest;
            if (growsCode && (!foldsTableIndices || trips > K_MAX_WIDE_TABLE_TRIPS) &&
                (bodyCount > K_MAX_ORDINARY_BODY_INSTR || bodyCount * trips > K_MAX_ORDINARY_TOTAL_INSTR))
                continue;
            if (growsCode && !internalLabels.empty() && bodyCount * trips > K_MAX_TOTAL_INSTR_WITH_BRANCHES && !foldsTableIndices)
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
            MicroInstrRegOperandRefs     regOps;
            if (internalLabels.empty())
            {
                std::unordered_set<MicroReg> seenInBody;
                for (uint32_t o = bodyBegin; o < bodyEnd; ++o)
                {
                    MicroInstr* inst = storage.ptr(order[o]);
                    if (!inst || !inst->numOperands)
                        continue;
                    const MicroInstrOperand* ops   = inst->ops(operands);
                    const auto               modes = MicroInstr::info(inst->op).resolvedRegModes(ops);
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
                        const MicroInstrOperand* ops   = inst->ops(operands);
                        const auto               modes = MicroInstr::info(inst->op).resolvedRegModes(ops);
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
                    newOps.append(srcOps, src->numOperands);

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
                            else if (regOp.use)
                            {
                                // Only renamable definitions enter this map.
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
