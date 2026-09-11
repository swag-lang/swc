#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Support/Core/SmallVector.h"

// A vector literal built through the frame.
//
//     LoadMemReg   [fb+o],    a, b16        (a store per lane, from registers
//     LoadMemReg   [fb+o+2],  a, b16         and immediates, in any order)
//     ...
//     LoadMemReg   [fb+o+14], b, b16
//     LoadRegMem   v, [fb+o], b128
//   ->
//     LoadRegReg            t0, a, b32           movd:   a . . . . . . .
//     OpTernaryRegRegRegImm t1, t0, b, 1, ins16  pinsrw: a b . . . . . .
//     OpBinaryRegRegReg     t2, t1, t1, unpkLo16         a a b b . . . .
//     OpBinaryRegRegReg     v,  t2, t2, unpkLo16         a a a a b b b b
//
// The front end builds a vector from scalars by storing every lane into a
// frame temporary and loading the whole: a store per lane, a load, and a
// store-forwarding stall on the wide load behind the narrow stores. The same
// vector comes out of the register file. The first lane arrives through
// movd, the others are inserted; a lane repeated over its neighbor comes from
// interleaving the half-built vector with itself, and a unit that repeats
// across the vector is built once and broadcast. Nothing else may read the
// bytes the stores wrote, since the stores go with the load.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_BUILD_WINDOW = 64;

        struct Lane
        {
            bool     isImm   = false;
            uint64_t imm     = 0;
            MicroReg reg     = MicroReg::invalid();
            uint32_t valueId = 0;
        };

        bool sameLane(const Lane& a, const Lane& b)
        {
            if (a.isImm != b.isImm)
                return false;
            return a.isImm ? a.imm == b.imm : a.valueId == b.valueId;
        }

        bool isZeroLane(const Lane& lane)
        {
            return lane.isImm && lane.imm == 0;
        }

        // The bits a memory access reads or writes, for the opcodes whose
        // width sits in a known operand; sixteen bytes for the rest, which
        // errs on the side of overlap.
        uint32_t accessBytes(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            switch (inst.op)
            {
                case MicroInstrOpcode::LoadRegMem:
                case MicroInstrOpcode::LoadVecRegMem:
                case MicroInstrOpcode::LoadMemReg:
                case MicroInstrOpcode::StoreVecMemReg:
                    return static_cast<uint32_t>(ops[2].opBits) / 8;
                case MicroInstrOpcode::LoadMemImm:
                    return static_cast<uint32_t>(ops[1].opBits) / 8;
                default:
                    return 16;
            }
        }

        bool rangesOverlap(const uint64_t aBegin, const uint64_t aBytes, const uint64_t bBegin, const uint64_t bBytes)
        {
            return aBegin < bBegin + bBytes && bBegin < aBegin + aBytes;
        }

        // A store that reads nothing from memory: what it writes to the slot
        // outside the walk has no bearing on the value the load sees.
        bool isPureStore(const MicroInstrOpcode op)
        {
            switch (op)
            {
                case MicroInstrOpcode::LoadMemReg:
                case MicroInstrOpcode::LoadMemImm:
                case MicroInstrOpcode::StoreVecMemReg:
                case MicroInstrOpcode::LoadAmcMemReg:
                case MicroInstrOpcode::LoadAmcMemImm:
                    return true;
                default:
                    return false;
            }
        }

        // Whether the register holds a cleared vector where `atRef` reads it.
        bool isClearedVectorAt(const Context& ctx, const MicroReg reg, const MicroInstrRef atRef)
        {
            if (!reg.isVirtualFloat())
                return false;
            const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::ClearReg)
                return false;
            const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
            return ops && ops[1].opBits == MicroOpBits::B128;
        }

        // Whether any instruction other than the load and its stores reads
        // the slot's bytes, or could: a read through the base at an
        // overlapping offset, an indexed read through the base at an unknown
        // offset, or an address that may reach the slot escaping - the
        // address of the slot itself, or of anything before it, since the
        // slot may be an element of a larger object whose address is what
        // escapes (the fourth vector of a cipher state, passed as a whole to
        // the rounds); the base as a plain value is the address of the first
        // local. An address computed after the slot cannot reach back into
        // it. Stores elsewhere do not matter - the walk already refused any
        // between the lane stores and the load.
        bool slotHasOtherReaders(const Context& ctx, const MicroReg base, const uint64_t slotOffset, const MicroInstrRef loadRef, const SmallVector<MicroInstrRef, 16>& storeRefs)
        {
            const auto view = ctx.storage->view();
            for (auto it = view.begin(); it != view.end(); ++it)
            {
                const MicroInstrRef ref = it.current;
                if (ref == loadRef || std::ranges::find(storeRefs, ref) != storeRefs.end())
                    continue;
                const MicroInstrUseDef* useDef = ctx.ssa->instrUseDef(ref);
                if (!useDef || std::ranges::find(useDef->uses, base) == useDef->uses.end())
                    continue;

                const MicroInstr&        inst = *it;
                const MicroInstrOperand* ops  = inst.ops(*ctx.operands);
                if (!ops)
                    return true;
                const MicroInstrDef& info = MicroInstr::info(inst.op);

                MicroPassHelpers::AmcLayout layout;
                if (MicroPassHelpers::amcLayoutFor(layout, inst.op) || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
                    return true;
                if (inst.op == MicroInstrOpcode::LoadAddrRegMem)
                {
                    // ops: [0] dst, [1] base, [2] opBits, [3] offset
                    if (ops[1].reg != base || ops[3].valueU64 < slotOffset + 16)
                        return true;
                    continue;
                }

                // The base read anywhere but as the memory base - copied,
                // compared, stored, added to - is its address escaping.
                const bool asMemBase = info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) && ops[info.memBaseOperandIndex].reg == base;
                uint32_t   baseReads = 0;
                for (const MicroReg use : useDef->uses)
                    baseReads += use == base ? 1 : 0;
                if (!asMemBase || baseReads > 1)
                    return true;
                if (isPureStore(inst.op))
                    continue;
                if (rangesOverlap(ops[info.memOffsetOperandIndex].valueU64, accessBytes(inst, ops), slotOffset, 16))
                    return true;
            }
            return false;
        }

        // The stores covering the slot, walked backwards from the load in a
        // straight line. The latest store to a lane wins; every lane must be
        // written once the walk is over, with one width for all of them.
        bool collectStores(const Context& ctx, const MicroInstrRef loadRef, const MicroReg base, const uint64_t slotOffset, SmallVector<Lane, 16>& outLanes, uint32_t& outLaneBytes, SmallVector<MicroInstrRef, 16>& outStoreRefs)
        {
            bool     covered[16] = {};
            uint32_t coveredBytes = 0;
            outLaneBytes          = 0;

            MicroInstrRef ref = ctx.storage->findPreviousInstructionRef(loadRef);
            for (uint32_t step = 0; ref.isValid() && step < K_MAX_BUILD_WINDOW && coveredBytes < 16; ++step, ref = ctx.storage->findPreviousInstructionRef(ref))
            {
                const MicroInstr* inst = ctx.storage->ptr(ref);
                if (!inst || isControlOrCall(*inst))
                    return false;
                const MicroInstrOperand* ops = inst->ops(*ctx.operands);
                if (!ops)
                    return false;

                const MicroInstrUseDef* useDef = ctx.ssa->instrUseDef(ref);
                if (useDef && std::ranges::find(useDef->defs, base) != useDef->defs.end())
                    return false;

                const bool storeReg = inst->op == MicroInstrOpcode::LoadMemReg || inst->op == MicroInstrOpcode::StoreVecMemReg;
                const bool storeImm = inst->op == MicroInstrOpcode::LoadMemImm;
                if (!storeReg && !storeImm)
                {
                    if (writesMemory(*inst))
                        return false;
                    continue;
                }

                // LoadMemReg, StoreVecMemReg: [0] base, [1] src, [2] opBits, [3] offset
                // LoadMemImm:                [0] base, [1] opBits, [2] offset, [3] imm
                const MicroReg    storeBase = ops[0].reg;
                const MicroOpBits bits      = storeReg ? ops[2].opBits : ops[1].opBits;
                const uint64_t    offset    = storeReg ? ops[3].valueU64 : ops[2].valueU64;
                const uint32_t    bytes     = static_cast<uint32_t>(bits) / 8;
                if (storeBase != base)
                {
                    // Another frame object, or memory this store may alias:
                    // only a store into the frame elsewhere is harmless.
                    if (!isFrameDerivedAddress(ctx, storeBase, ref))
                        return false;
                    continue;
                }
                if (!rangesOverlap(offset, bytes, slotOffset, 16))
                    continue;

                // The whole slot cleared before the lanes were stored: the
                // lanes no store wrote are zero. The front end clears an
                // aggregate before filling the lanes it names.
                if (bytes == 16 && offset == slotOffset && storeReg && isClearedVectorAt(ctx, ops[1].reg, ref))
                {
                    if (outLaneBytes == 0)
                        return false; // no lane stored yet: a cleared vector alone is another rule's
                    for (uint32_t laneIndex = 0; laneIndex < outLanes.size(); ++laneIndex)
                    {
                        if (covered[laneIndex])
                            continue;
                        outLanes[laneIndex]       = Lane{};
                        outLanes[laneIndex].isImm = true;
                        covered[laneIndex]        = true;
                        coveredBytes += outLaneBytes;
                    }
                    outStoreRefs.push_back(ref);
                    continue;
                }
                if (offset < slotOffset || offset + bytes > slotOffset + 16 || bytes == 0 || bytes > 4)
                    return false;
                if (outLaneBytes == 0)
                {
                    outLaneBytes = bytes;
                    outLanes.resize(16 / bytes);
                }
                if (bytes != outLaneBytes || (offset - slotOffset) % bytes != 0)
                    return false;

                const uint32_t laneIndex = static_cast<uint32_t>((offset - slotOffset) / bytes);
                if (covered[laneIndex])
                    continue; // an earlier store to a lane a later one overwrote

                Lane lane;
                if (storeImm)
                {
                    lane.isImm = true;
                    lane.imm   = ops[3].valueU64 & ((1ULL << (bytes * 8)) - 1);
                }
                else
                {
                    lane.reg = ops[1].reg;
                    if (!lane.reg.isVirtualInt())
                        return false;
                    const MicroSsaState::ReachingDef atStore = ctx.ssa->reachingDef(lane.reg, ref);
                    const MicroSsaState::ReachingDef atLoad  = ctx.ssa->reachingDef(lane.reg, loadRef);
                    if (!atStore.valid() || !atLoad.valid() || atStore.valueId != atLoad.valueId)
                        return false;
                    lane.valueId = atStore.valueId;
                }
                outLanes[laneIndex] = lane;
                covered[laneIndex]  = true;
                coveredBytes += bytes;
                outStoreRefs.push_back(ref);
            }
            return coveredBytes == 16;
        }

        // The instructions that build the vector, each defining a fresh
        // register the next reads; the last one is rewritten onto the load.
        struct Step
        {
            MicroInstrOpcode  op     = MicroInstrOpcode::Nop;
            uint8_t           numOps = 0;
            MicroInstrOperand ops[6] = {};
        };

        struct Plan
        {
            Context&                ctx;
            uint32_t                laneBytes;
            SmallVector<Step, 24>   steps;
            bool                    failed = false;

            MicroReg freshFloat()
            {
                if (ctx.nextVirtualFloatRegIndex >= MicroReg::K_MAX_INDEX)
                    failed = true;
                return MicroReg::virtualFloatReg(ctx.nextVirtualFloatRegIndex++);
            }

            MicroReg freshInt()
            {
                if (ctx.nextVirtualIntRegIndex >= MicroReg::K_MAX_INDEX)
                    failed = true;
                return MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);
            }

            MicroOp insertOp() const { return laneBytes == 1 ? MicroOp::VecInsert8 : laneBytes == 2 ? MicroOp::VecInsert16 : MicroOp::VecInsert32; }
            MicroOp unpackOp(const uint32_t bytes) const { return bytes == 1 ? MicroOp::VecUnpackLo8 : bytes == 2 ? MicroOp::VecUnpackLo16 : bytes == 4 ? MicroOp::VecUnpackLo32 : MicroOp::VecUnpackLo64; }

            // The lane's scalar in an integer register: the register it came
            // from, or an immediate materialized.
            MicroReg scalarReg(const Lane& lane)
            {
                if (!lane.isImm)
                    return lane.reg;
                const MicroReg reg = freshInt();
                Step&          s   = steps.emplace_back();
                s.op               = MicroInstrOpcode::LoadRegImm;
                s.numOps           = 3;
                s.ops[0].reg       = reg;
                s.ops[1].opBits    = MicroOpBits::B32;
                s.ops[2].setImmediateValue(ApInt(lane.imm, 32));
                return reg;
            }

            MicroReg clear()
            {
                const MicroReg reg = freshFloat();
                Step&          s   = steps.emplace_back();
                s.op               = MicroInstrOpcode::ClearReg;
                s.numOps           = 2;
                s.ops[0].reg       = reg;
                s.ops[1].opBits    = MicroOpBits::B128;
                return reg;
            }

            MicroReg movd(const Lane& lane)
            {
                const MicroReg src = scalarReg(lane);
                const MicroReg reg = freshFloat();
                Step&          s   = steps.emplace_back();
                s.op               = MicroInstrOpcode::LoadRegReg;
                s.numOps           = 3;
                s.ops[0].reg       = reg;
                s.ops[1].reg       = src;
                s.ops[2].opBits    = MicroOpBits::B32;
                return reg;
            }

            MicroReg insert(const MicroReg into, const Lane& lane, const uint32_t laneIndex)
            {
                const MicroReg src = scalarReg(lane);
                const MicroReg reg = freshFloat();
                Step&          s   = steps.emplace_back();
                s.op               = MicroInstrOpcode::OpTernaryRegRegRegImm;
                s.numOps           = 6;
                s.ops[0].reg       = reg;
                s.ops[1].reg       = into;
                s.ops[2].reg       = src;
                s.ops[3].opBits    = MicroOpBits::B128;
                s.ops[4].microOp   = insertOp();
                s.ops[5].valueU64  = laneIndex;
                return reg;
            }

            MicroReg unpackWithSelf(const MicroReg src, const uint32_t bytes)
            {
                const MicroReg reg = freshFloat();
                Step&          s   = steps.emplace_back();
                s.op               = MicroInstrOpcode::OpBinaryRegRegReg;
                s.numOps           = 5;
                s.ops[0].reg       = reg;
                s.ops[1].reg       = src;
                s.ops[2].reg       = src;
                s.ops[3].opBits    = MicroOpBits::B128;
                s.ops[4].microOp   = unpackOp(bytes);
                return reg;
            }

            MicroReg broadcastDword(const MicroReg src)
            {
                const MicroReg reg = freshFloat();
                Step&          s   = steps.emplace_back();
                s.op               = MicroInstrOpcode::VecShuffleRegRegImm;
                s.numOps           = 4;
                s.ops[0].reg       = reg;
                s.ops[1].reg       = src;
                s.ops[2].opBits    = MicroOpBits::B128;
                s.ops[3].valueU64  = 0;
                return reg;
            }

            // A register whose first `count` lanes are the given ones; the
            // lanes beyond are unspecified, and every later step reads only
            // the lanes this one defines. movd defines lane zero and clears
            // the rest of its dword, so a zero lane inside that dword still
            // has to be written, and a zero lane beyond it comes free.
            MicroReg buildDirect(std::span<const Lane> lanes)
            {
                const uint32_t count      = static_cast<uint32_t>(lanes.size());
                const uint32_t dwordLanes = 4 / laneBytes;

                // An immediate costs its materialization on top of the insert.
                uint32_t viaMovd  = lanes[0].isImm ? 2 : 1;
                uint32_t viaClear = 1;
                for (uint32_t i = 0; i < count; ++i)
                {
                    const bool     zero = isZeroLane(lanes[i]);
                    const uint32_t cost = lanes[i].isImm ? 2 : 1;
                    if (i > 0 && (!zero || i < dwordLanes))
                        viaMovd += cost;
                    if (!zero)
                        viaClear += cost;
                }

                if (viaClear <= viaMovd)
                {
                    MicroReg reg = clear();
                    for (uint32_t i = 0; i < count; ++i)
                    {
                        if (!isZeroLane(lanes[i]))
                            reg = insert(reg, lanes[i], i);
                    }
                    return reg;
                }

                MicroReg reg = movd(lanes[0]);
                for (uint32_t i = 1; i < count; ++i)
                {
                    if (!isZeroLane(lanes[i]) || i < dwordLanes)
                        reg = insert(reg, lanes[i], i);
                }
                return reg;
            }

            // A register whose first lanes are the given ones. Lanes equal to
            // their neighbor in pairs come from interleaving the vector of
            // one lane per pair with itself.
            MicroReg build(std::span<const Lane> lanes)
            {
                const uint32_t count = static_cast<uint32_t>(lanes.size());
                if (count >= 2 && count % 2 == 0)
                {
                    bool pairs = true;
                    for (uint32_t i = 0; i < count && pairs; i += 2)
                        pairs = sameLane(lanes[i], lanes[i + 1]);
                    if (pairs)
                    {
                        SmallVector<Lane, 16> half;
                        for (uint32_t i = 0; i < count; i += 2)
                            half.push_back(lanes[i]);
                        const MicroReg reg = build(half.span());
                        return unpackWithSelf(reg, laneBytes);
                    }
                }
                return buildDirect(lanes);
            }

            // The whole vector: the smallest repeating unit built, then
            // broadcast over the sixteen bytes.
            MicroReg buildVector(std::span<const Lane> lanes)
            {
                const uint32_t count = static_cast<uint32_t>(lanes.size());

                bool allZero = true;
                for (const Lane& lane : lanes)
                    allZero = allZero && isZeroLane(lane);
                if (allZero)
                    return clear();

                uint32_t period = count;
                for (uint32_t p = 1; p < count; ++p)
                {
                    if (count % p != 0)
                        continue;
                    bool repeats = true;
                    for (uint32_t i = 0; i + p < count && repeats; ++i)
                        repeats = sameLane(lanes[i], lanes[i + p]);
                    if (repeats)
                    {
                        period = p;
                        break;
                    }
                }

                MicroReg reg       = build(lanes.subspan(0, period));
                uint32_t unitBytes = period * laneBytes;
                while (unitBytes < 4)
                {
                    reg = unpackWithSelf(reg, unitBytes);
                    unitBytes *= 2;
                }
                if (unitBytes == 4)
                    return broadcastDword(reg);
                if (unitBytes == 8)
                    return unpackWithSelf(reg, 8);
                return reg;
            }
        };
    }

    bool tryBuildVectorFromStores(Context& ctx, const MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || ctx.isRelocated(loadRef) || !ctx.ssa)
            return false;

        // ops: [0] dst, [1] base, [2] opBits, [3] offset
        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps || loadOps[2].opBits != MicroOpBits::B128)
            return false;
        const MicroReg dst        = loadOps[0].reg;
        const MicroReg base       = loadOps[1].reg;
        const uint64_t slotOffset = loadOps[3].valueU64;
        if (!dst.isVirtualFloat() || !base.isVirtualInt() || !isFrameDerivedAddress(ctx, base, loadRef))
            return false;

        SmallVector<Lane, 16>          lanes;
        SmallVector<MicroInstrRef, 16> storeRefs;
        uint32_t                       laneBytes = 0;
        if (!collectStores(ctx, loadRef, base, slotOffset, lanes, laneBytes, storeRefs))
            return false;
        for (const MicroInstrRef ref : storeRefs)
        {
            if (ctx.isClaimed(ref) || ctx.isRelocated(ref))
                return false;
        }
        if (slotHasOtherReaders(ctx, base, slotOffset, loadRef, storeRefs))
            return false;

        const uint32_t savedFloat = ctx.nextVirtualFloatRegIndex;
        const uint32_t savedInt   = ctx.nextVirtualIntRegIndex;
        Plan           plan{ctx, laneBytes};
        plan.buildVector(lanes.span());
        if (plan.failed || plan.steps.empty() || plan.steps.size() > storeRefs.size() + 1)
        {
            ctx.nextVirtualFloatRegIndex = savedFloat;
            ctx.nextVirtualIntRegIndex   = savedInt;
            return false;
        }

        if (!ctx.claimAll({loadRef}))
        {
            ctx.nextVirtualFloatRegIndex = savedFloat;
            ctx.nextVirtualIntRegIndex   = savedInt;
            return false;
        }
        for (const MicroInstrRef ref : storeRefs)
        {
            if (!ctx.claimAll({ref}))
                return false;
        }

        // Every step but the last goes before the load; the last becomes the
        // load, writing its register.
        for (size_t i = 0; i + 1 < plan.steps.size(); ++i)
        {
            const Step& step = plan.steps[i];
            ctx.emitInsertBefore(loadRef, step.op, std::span<const MicroInstrOperand>(step.ops, step.numOps));
        }
        Step last       = plan.steps.back();
        last.ops[0].reg = dst;
        ctx.emitRewrite(loadRef, last.op, std::span<const MicroInstrOperand>(last.ops, last.numOps), true);
        for (const MicroInstrRef ref : storeRefs)
            ctx.emitErase(ref);
        return true;
    }
}

SWC_END_NAMESPACE();
