#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRALoopHoist.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Support/Report/Assert.h"

// Post-RA loop-invariant reload hoisting. See the header for why this exists.

SWC_BEGIN_NAMESPACE();

namespace
{
    using MicroPassHelpers::MicroPhysLiveness;
    using MicroPassHelpers::NaturalLoop;

    // How many times the pass lifts a load one loop level. A load hoisted out of
    // an inner loop lands in the enclosing loop's body and may be invariant
    // there too; three levels covers every loop nest in the standard library
    // and bounds the cost on a pathological one.
    constexpr uint32_t K_MAX_LEVELS = 3;

    struct FrameRef
    {
        MicroReg base;
        uint64_t lo = 0;
        uint64_t hi = 0;
    };

    bool isFrameBaseRegister(const MicroReg reg, const CallConv& conv)
    {
        return reg.isValid() && (reg == conv.stackPointer || reg == conv.framePointer);
    }

    // A constant-offset frame write, the only memory write shape this pass
    // tolerates inside a loop it hoists from. Anything else — a store through a
    // program pointer, an indexed write, a vector store — could alias the slot
    // being hoisted, and post-RA there is no aliasing information left to
    // prove otherwise.
    bool frameWriteRange(FrameRef& out, const MicroInstr& inst, const MicroInstrOperand* ops, const CallConv& conv)
    {
        if (!ops)
            return false;

        auto     bits   = MicroOpBits::Zero;
        uint64_t offset = 0;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
                bits   = ops[2].opBits;
                offset = ops[3].valueU64;
                break;
            case MicroInstrOpcode::LoadMemImm:
                bits   = ops[1].opBits;
                offset = ops[2].valueU64;
                break;
            case MicroInstrOpcode::OpBinaryMemReg:
                bits   = ops[2].opBits;
                offset = ops[4].valueU64;
                break;
            case MicroInstrOpcode::OpBinaryMemImm:
                bits   = ops[1].opBits;
                offset = ops[3].valueU64;
                break;
            case MicroInstrOpcode::OpUnaryMem:
                bits   = ops[1].opBits;
                offset = ops[3].valueU64;
                break;
            default:
                return false;
        }

        if (!isFrameBaseRegister(ops[0].reg, conv))
            return false;

        out.base = ops[0].reg;
        out.lo   = offset;
        out.hi   = offset + getNumBytes(bits);
        return true;
    }

    bool isFrameLoad(FrameRef& out, const MicroInstr& inst, const MicroInstrOperand* ops, const CallConv& conv)
    {
        if (inst.op != MicroInstrOpcode::LoadRegMem || !ops)
            return false;
        if (!isFrameBaseRegister(ops[1].reg, conv))
            return false;

        out.base = ops[1].reg;
        out.lo   = ops[3].valueU64;
        out.hi   = out.lo + getNumBytes(ops[2].opBits);
        return true;
    }

    bool overlaps(const FrameRef& a, const FrameRef& b)
    {
        return a.base == b.base && a.lo < b.hi && b.lo < a.hi;
    }

    struct Hoist
    {
        MicroInstrRef ref;
        MicroInstrRef beforeRef;
    };

    // One loop-carried slot promoted out of memory: its load and store inside
    // the body go away, the register is seeded before the loop and written back
    // once after it.
    struct Carried
    {
        MicroInstrRef loadRef;
        MicroInstrRef storeRef;
        MicroInstrRef seedBeforeRef;  // insert the seeding load before this, or invalid if not needed
        MicroInstrRef writeBackAfter; // insert the write-back after this
        MicroReg      reg;
        MicroReg      base;
        uint64_t      offset = 0;
        MicroOpBits   bits   = MicroOpBits::Zero;
    };

    // A redundant reload whose destination is reused right afterwards for
    // something else: rather than leaving a register copy behind, point its
    // readers at the register the slot was hoisted into and report that the
    // load itself can go.
    //
    // The scan is linear and stops at anything that could bring in a different
    // value for the destination: a label (a join arrives with its own), a call,
    // an unconditional jump, or the end of the body. A conditional exit is
    // allowed through only when the destination is dead on the way out, so
    // nothing outside the loop can observe the register we stopped writing.
    // Success means a redefinition was reached, which is what makes the load
    // dead rather than merely redundant.
    bool redirectUsesToHoistedRegister(MicroStorage&                                 storage,
                                       MicroOperandStorage&                          operands,
                                       const MicroControlFlowGraph&                  cfg,
                                       const MicroPhysLiveness&                      liveness,
                                       const std::vector<uint8_t>&                   inBody,
                                       const std::unordered_map<uint32_t, uint32_t>& refToIndex,
                                       const uint32_t                                loadIndex,
                                       const MicroReg                                hoisted,
                                       const Encoder*                                encoder)
    {
        const auto     instrRefs = cfg.instructionRefs();
        const uint32_t n         = cfg.instructionCount();

        const MicroInstr*        loadInst = storage.ptr(instrRefs[loadIndex]);
        const MicroInstrOperand* loadOps  = loadInst ? loadInst->ops(operands) : nullptr;
        if (!loadOps)
            return false;
        const MicroReg dead = loadOps[0].reg;

        // Pass one decides; nothing is rewritten until the whole stretch is known
        // to be safe.
        SmallVector<uint32_t> useSites;
        bool                  redefined = false;
        for (uint32_t k = loadIndex + 1; k < n && !redefined; ++k)
        {
            if (!inBody[k])
                return false;
            const MicroInstr* inst = storage.ptr(instrRefs[k]);
            if (!inst)
                return false;
            if (inst->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrDef&   info   = MicroInstr::info(inst->op);
            const MicroInstrUseDef useDef = liveness.useDefs[k];
            if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) || useDef.isCall)
                return false;

            bool usesDead = false;
            bool defsDead = false;
            for (const MicroReg use : useDef.uses)
                usesDead = usesDead || use == dead;
            for (const MicroReg def : useDef.defs)
                defsDead = defsDead || def == dead;

            // A read-modify-write of the destination is both, and rewriting only
            // its read half would change what it writes.
            if (defsDead && usesDead)
                return false;
            if (defsDead)
            {
                redefined = true;
                break;
            }
            if (usesDead)
                useSites.push_back(k);

            if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
            {
                if (!info.flags.has(MicroInstrFlagsE::ConditionalJump))
                    return false;
                const uint32_t deadBit = MicroPhysLiveness::bitOf(dead);
                if (deadBit >= MicroPhysLiveness::K_INVALID_BIT)
                    return false;
                for (const uint32_t succ : cfg.successors(k))
                {
                    if (succ < n && !inBody[succ] && (liveness.liveIn[succ] & (1ull << deadBit)) != 0)
                        return false;
                }
            }
        }

        if (!redefined)
            return false;

        // Every rewritten instruction has to remain encodable with the hoisted
        // register in place of the dead one.
        for (const uint32_t k : useSites)
        {
            const MicroInstr*        inst = storage.ptr(instrRefs[k]);
            const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!ops)
                return false;

            MicroInstrOperand probe[8] = {};
            if (inst->numOperands > 8)
                return false;
            for (uint8_t o = 0; o < inst->numOperands; ++o)
            {
                probe[o] = ops[o];
                if (probe[o].reg == dead)
                    probe[o].reg = hoisted;
            }

            if (encoder)
            {
                MicroInstr probeInst;
                probeInst.op          = inst->op;
                probeInst.numOperands = inst->numOperands;

                MicroConformanceIssue issue;
                if (encoder->queryConformanceIssue(issue, probeInst, probe))
                    return false;
            }
        }

        for (const uint32_t k : useSites)
        {
            const MicroInstr*        inst = storage.ptr(instrRefs[k]);
            const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!ops)
                continue;
            SmallVector<MicroInstrRegOperandRef> refs;
            inst->collectRegOperands(operands, refs, encoder);
            for (const auto& ref : refs)
            {
                if (ref.reg && *ref.reg == dead && ref.use)
                    *ref.reg = hoisted;
            }
        }

        return true;
    }

    // The register allocator hands every non-pinned loop-carried value a stable
    // memory home and writes it back at each control-flow boundary, so an
    // accumulator is loaded and stored on every iteration even when one register
    // could have carried it. This finds that shape and keeps the value in the
    // register the allocator already chose.
    //
    // What has to hold, and all of it is checked on the emitted code:
    //   - the body touches the slot exactly twice, one load then one store, at
    //     the same width and through the same register;
    //   - that register carries nothing else across the iteration: every
    //     definition of it in the body lies between the load and the store, and
    //     it is neither read before the load nor read after the store;
    //   - every way out of the loop lands on one instruction that nothing
    //     outside the loop jumps to, so a single write-back covers them all;
    //   - the register is dead where the seeding load and the write-back land.
    void promoteCarriedSlots(MicroStorage&                storage,
                             MicroOperandStorage&         operands,
                             const MicroControlFlowGraph& cfg,
                             const MicroPhysLiveness&     liveness,
                             const NaturalLoop&           loop,
                             const MicroInstrRef          headerRef,
                             const uint32_t               preheaderIndex,
                             const CallConv&              conv,
                             std::vector<Carried>&        out)
    {
        const auto     instrRefs = cfg.instructionRefs();
        const uint32_t n         = cfg.instructionCount();
        const auto&    inBody    = loop.inBody;

        // Every way out of the loop must converge on one instruction that only
        // the loop reaches.
        uint32_t exitTarget = std::numeric_limits<uint32_t>::max();
        for (uint32_t i = 0; i < n; ++i)
        {
            if (!inBody[i])
                continue;
            for (const uint32_t succ : cfg.successors(i))
            {
                if (succ < n && inBody[succ])
                    continue;
                if (exitTarget != std::numeric_limits<uint32_t>::max() && exitTarget != succ)
                    return;
                exitTarget = succ;
            }
        }
        if (exitTarget >= n)
            return;
        for (const uint32_t pred : cfg.predecessors(exitTarget))
        {
            if (pred < n && !inBody[pred])
                return;
        }

        const MicroInstrRef writeBackAfter = instrRefs[exitTarget];
        if (!storage.findNextInstructionRef(writeBackAfter).isValid())
            return;

        // Index every constant-offset frame access of the body by slot.
        struct SlotUse
        {
            uint32_t    loadIndex  = std::numeric_limits<uint32_t>::max();
            uint32_t    storeIndex = std::numeric_limits<uint32_t>::max();
            uint32_t    accesses   = 0;
            MicroReg    reg;
            MicroReg    base;
            MicroOpBits bits = MicroOpBits::Zero;
        };
        std::unordered_map<uint64_t, SlotUse> slots;

        for (uint32_t i = 0; i < n; ++i)
        {
            if (!inBody[i])
                continue;
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            if (!inst)
                return;
            const MicroInstrOperand* ops = inst->ops(operands);

            FrameRef ref;
            if (isFrameLoad(ref, *inst, ops, conv))
            {
                SlotUse& use = slots[ref.lo];
                ++use.accesses;
                use.base = ref.base;
                if (use.loadIndex != std::numeric_limits<uint32_t>::max())
                    use.accesses = 99; // a second load: not the shape
                use.loadIndex = i;
                use.reg       = ops[0].reg;
                use.bits      = ops[2].opBits;
                continue;
            }

            if (inst->op == MicroInstrOpcode::LoadMemReg && ops && isFrameBaseRegister(ops[0].reg, conv))
            {
                SlotUse& use = slots[ops[3].valueU64];
                ++use.accesses;
                if (use.storeIndex != std::numeric_limits<uint32_t>::max())
                    use.accesses = 99;
                use.storeIndex = i;
                continue;
            }

            // Any other frame access at all disqualifies the slot it touches;
            // the caller has already refused bodies with opaque writes.
            FrameRef written;
            if (frameWriteRange(written, *inst, ops, conv))
                slots[written.lo].accesses = 99;
        }

        for (auto& [offset, use] : slots)
        {
            if (use.accesses != 2)
                continue;
            if (use.loadIndex == std::numeric_limits<uint32_t>::max() ||
                use.storeIndex == std::numeric_limits<uint32_t>::max())
                continue;
            if (use.loadIndex > use.storeIndex)
                continue;

            const MicroInstr*        loadInst  = storage.ptr(instrRefs[use.loadIndex]);
            const MicroInstr*        storeInst = storage.ptr(instrRefs[use.storeIndex]);
            const MicroInstrOperand* storeOps  = storeInst ? storeInst->ops(operands) : nullptr;
            if (!loadInst || !storeOps)
                continue;
            if (storeOps[1].reg != use.reg || storeOps[2].opBits != use.bits)
                continue;
            if (!use.reg.isInt() && !use.reg.isFloat())
                continue;
            if (isFrameBaseRegister(use.reg, conv))
                continue;

            // The register must carry nothing else around the iteration.
            bool usable = true;
            for (uint32_t k = 0; k < n && usable; ++k)
            {
                if (!inBody[k] || k == use.loadIndex || k == use.storeIndex)
                    continue;
                const bool inside = k > use.loadIndex && k < use.storeIndex;
                for (const MicroReg def : liveness.useDefs[k].defs)
                {
                    if (def == use.reg && !inside)
                        usable = false;
                }
                for (const MicroReg used : liveness.useDefs[k].uses)
                {
                    if (used == use.reg && !inside)
                        usable = false;
                }
            }
            if (!usable)
                continue;

            // Nothing outside may read the register we now leave holding the
            // accumulator, and nothing may be holding a live value where the
            // seeding load lands.
            if (liveness.isLiveOut(exitTarget, use.reg))
                continue;
            if (liveness.isLiveOut(preheaderIndex, use.reg))
                continue;

            // The preheader usually stores the initial value into the slot
            // already, in which case the register still holds it and no seeding
            // load is needed.
            MicroInstrRef     seedBefore = headerRef;
            const MicroInstr* prev       = storage.ptr(instrRefs[preheaderIndex]);
            if (prev && prev->op == MicroInstrOpcode::LoadMemReg)
            {
                const MicroInstrOperand* prevOps = prev->ops(operands);
                if (prevOps && isFrameBaseRegister(prevOps[0].reg, conv) && prevOps[3].valueU64 == offset &&
                    prevOps[1].reg == use.reg && prevOps[2].opBits == use.bits)
                    seedBefore = MicroInstrRef::invalid();
            }

            out.push_back({.loadRef        = instrRefs[use.loadIndex],
                           .storeRef       = instrRefs[use.storeIndex],
                           .seedBeforeRef  = seedBefore,
                           .writeBackAfter = writeBackAfter,
                           .reg            = use.reg,
                           .base           = use.base,
                           .offset         = offset,
                           .bits           = use.bits});
        }
    }

    // One sweep: hoist every qualifying reload out of every loop whose body it
    // is invariant in. Returns true when the IR changed.
    bool hoistRound(MicroPassContext& context, const CallConv& conv)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        if (!cfg.hasLoop() || cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;

        const uint32_t n = cfg.instructionCount();
        if (!n)
            return false;

        const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
        if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
            return false;

        const auto instrRefs = cfg.instructionRefs();

        // Cheap pre-scan: no frame reload anywhere means no work, and the
        // dominator, loop and liveness analyses below are never paid for.
        bool anyFrameLoad = false;
        for (uint32_t i = 0; i < n && !anyFrameLoad; ++i)
        {
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            FrameRef          slot;
            if (inst && isFrameLoad(slot, *inst, inst->ops(operands), conv))
                anyFrameLoad = true;
        }
        if (!anyFrameLoad)
            return false;

        const auto dom           = MicroPassHelpers::computeInstructionDominators(cfg, entry);
        auto       loopsByHeader = MicroPassHelpers::findNaturalLoops(cfg, dom);
        if (loopsByHeader.empty())
            return false;

        MicroPhysLiveness liveness;
        MicroPassHelpers::computePhysicalLiveness(liveness, context);
        if (!liveness.valid)
            return false;

        std::unordered_map<uint32_t, uint32_t> refToIndex;
        refToIndex.reserve(n);
        for (uint32_t i = 0; i < n; ++i)
            refToIndex[instrRefs[i].get()] = i;

        // Innermost first, so a load leaves the loop it costs most in before the
        // enclosing one is considered.
        std::vector<const NaturalLoop*> loops;
        loops.reserve(loopsByHeader.size());
        for (const auto& loop : loopsByHeader | std::views::values)
            loops.push_back(&loop);
        std::ranges::sort(loops, [](const NaturalLoop* a, const NaturalLoop* b) { return a->bodySize < b->bodySize; });

        struct Rewrite
        {
            MicroInstrRef ref;
            MicroReg      source;
        };

        std::vector<Hoist>           hoists;
        std::vector<MicroInstrRef>   erasures;
        std::vector<Rewrite>         rewrites;
        std::vector<Carried>         carried;
        std::unordered_set<uint32_t> claimed;

        for (const NaturalLoop* loop : loops)
        {
            const uint32_t      header    = loop->header;
            const auto&         inBody    = loop->inBody;
            const MicroInstrRef headerRef = instrRefs[header];

            // A clean preheader: exactly one predecessor from outside the loop,
            // and it is the immediate linear predecessor falling through into
            // the header. Anything else and the instruction we insert before the
            // header would sit on a path that does not always reach it, or would
            // be skipped by a jump that does.
            uint32_t externalPredCount = 0;
            for (const uint32_t p : cfg.predecessors(header))
            {
                if (p < n && !inBody[p])
                    ++externalPredCount;
            }
            if (externalPredCount != 1)
                continue;

            const MicroInstrRef prevRef = storage.findPreviousInstructionRef(headerRef);
            if (!prevRef.isValid())
                continue;
            const auto prevIdxIt = refToIndex.find(prevRef.get());
            if (prevIdxIt == refToIndex.end() || inBody[prevIdxIt->second])
                continue;
            const MicroInstr* prevInst = storage.ptr(prevRef);
            if (!prevInst)
                continue;
            const MicroInstrFlags prevFlags = MicroInstr::info(prevInst->op).flags;
            if (prevFlags.has(MicroInstrFlagsE::TerminatorInstruction) &&
                !prevFlags.has(MicroInstrFlagsE::ConditionalJump))
                continue;
            if (prevFlags.has(MicroInstrFlagsE::JumpInstruction) &&
                !prevFlags.has(MicroInstrFlagsE::ConditionalJump))
                continue;

            const uint32_t preheaderIndex = prevIdxIt->second;

            // Classify the body once: every frame slot it writes, and whether it
            // does anything the slot analysis cannot account for.
            bool                  bodyOpaque = false;
            std::vector<FrameRef> writes;
            for (uint32_t i = 0; i < n && !bodyOpaque; ++i)
            {
                if (!inBody[i])
                    continue;
                const MicroInstr* inst = storage.ptr(instrRefs[i]);
                if (!inst)
                {
                    bodyOpaque = true;
                    break;
                }
                const MicroInstrDef& info = MicroInstr::info(inst->op);
                if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) || liveness.useDefs[i].isCall)
                {
                    bodyOpaque = true;
                    break;
                }
                if (inst->op == MicroInstrOpcode::Push || inst->op == MicroInstrOpcode::Pop)
                {
                    bodyOpaque = true;
                    break;
                }
                // The frame base must mean the same thing on every iteration.
                for (const MicroReg def : liveness.useDefs[i].defs)
                {
                    if (isFrameBaseRegister(def, conv))
                        bodyOpaque = true;
                }
                if (bodyOpaque)
                    break;
                if (!info.flags.has(MicroInstrFlagsE::WritesMemory))
                    continue;
                FrameRef written;
                if (!frameWriteRange(written, *inst, inst->ops(operands), conv))
                {
                    bodyOpaque = true;
                    break;
                }
                writes.push_back(written);
            }
            if (bodyOpaque)
                continue;

            for (uint32_t i = 0; i < n; ++i)
            {
                if (!inBody[i])
                    continue;
                if (claimed.contains(i))
                    continue;

                const MicroInstr* inst = storage.ptr(instrRefs[i]);
                if (!inst)
                    continue;
                const MicroInstrOperand* ops = inst->ops(operands);
                FrameRef                 slot;
                if (!isFrameLoad(slot, *inst, ops, conv))
                    continue;

                const MicroReg dst = ops[0].reg;
                if (!dst.isInt() && !dst.isFloat())
                    continue;
                if (isFrameBaseRegister(dst, conv))
                    continue;

                bool aliased = false;
                for (const FrameRef& written : writes)
                {
                    if (overlaps(slot, written))
                    {
                        aliased = true;
                        break;
                    }
                }
                if (aliased)
                    continue;

                // The destination must be written by nothing else in the body,
                // or the value carried across iterations is not this one, and
                // it must hold nothing live where the load is about to land.
                bool otherDef = false;
                for (uint32_t k = 0; k < n && !otherDef; ++k)
                {
                    if (!inBody[k] || k == i)
                        continue;
                    for (const MicroReg def : liveness.useDefs[k].defs)
                    {
                        if (def == dst)
                        {
                            otherDef = true;
                            break;
                        }
                    }
                }
                if (otherDef)
                    continue;
                if (liveness.isLiveOut(preheaderIndex, dst))
                    continue;

                // The hoisted register now holds this slot for the whole body:
                // nothing in the body writes the slot, and nothing writes the
                // register. So every other load of the same slot in the body is
                // reading a value already in a register — redundant when it
                // targets that same register, and a register copy rather than a
                // memory access when it targets another one.
                hoists.push_back({instrRefs[i], headerRef});
                claimed.insert(i);
                for (uint32_t k = 0; k < n; ++k)
                {
                    if (!inBody[k] || k == i || claimed.contains(k))
                        continue;
                    const MicroInstr* other = storage.ptr(instrRefs[k]);
                    if (!other)
                        continue;
                    const MicroInstrOperand* otherOps = other->ops(operands);
                    FrameRef                 otherSlot;
                    if (!isFrameLoad(otherSlot, *other, otherOps, conv))
                        continue;
                    if (otherSlot.base != slot.base || otherSlot.lo != slot.lo || otherSlot.hi != slot.hi)
                        continue;
                    if (otherOps[0].reg == dst)
                    {
                        erasures.push_back(instrRefs[k]);
                    }
                    else
                    {
                        // A copy only replaces the load when both ends live in
                        // the same register class; across classes the move is a
                        // different instruction entirely.
                        if (otherOps[0].reg.isAnyFloat() != dst.isAnyFloat())
                            continue;
                        // Better than a copy: point the readers at the hoisted
                        // register and let the load go. Only worth attempting
                        // when the register is reused right after for something
                        // else, which is the shape that makes the copy pure
                        // overhead — and freeing it is what lets a later pass
                        // keep a loop-carried value there.
                        if (!redirectUsesToHoistedRegister(storage, operands, cfg, liveness, inBody, refToIndex, k, dst, context.encoder))
                            rewrites.push_back({instrRefs[k], dst});
                        else
                            erasures.push_back(instrRefs[k]);
                    }
                    claimed.insert(k);
                }
            }

            // Second phase for this loop: a slot the body both reads and writes
            // once, through one register that carries nothing else across the
            // iteration. The allocator gives every non-pinned loop-carried value
            // a memory home and writes it back at each boundary, so an
            // accumulator round-trips through the frame on every iteration; this
            // keeps it in its register for the whole loop and writes it back once
            // on the way out.
            promoteCarriedSlots(storage, operands, cfg, liveness, *loop, headerRef, preheaderIndex, conv, carried);
        }

        if (hoists.empty() && carried.empty())
            return false;

        for (const MicroInstrRef ref : erasures)
            storage.erase(ref);

        for (const Rewrite& rewrite : rewrites)
        {
            MicroInstr* inst = storage.ptr(rewrite.ref);
            if (!inst)
                continue;
            MicroInstrOperand* ops = inst->ops(operands);
            if (!ops)
                continue;

            // `mov D, [slot]` becomes `mov D, R`, the register the slot was
            // hoisted into. LoadRegMem is (dst, base, bits, offset) and
            // LoadRegReg is (dst, src, bits), so the base becomes the source
            // and the offset is dropped.
            ops[1].reg        = rewrite.source;
            inst->op          = MicroInstrOpcode::LoadRegReg;
            inst->numOperands = 3;
        }

        for (const Carried& promo : carried)
        {
            // Seed the register before the loop when the preheader has not
            // already left the value in it.
            if (promo.seedBeforeRef.isValid())
            {
                MicroInstrOperand seedOps[4] = {};
                seedOps[0].reg               = promo.reg;
                seedOps[1].reg               = promo.base;
                seedOps[2].opBits            = promo.bits;
                seedOps[3].valueU64          = promo.offset;
                storage.insertDerivedBefore(operands, promo.seedBeforeRef, MicroInstrOpcode::LoadRegMem, std::span(seedOps, 4));
            }

            // Write it back once, on the single instruction every exit reaches.
            const MicroInstrRef afterRef = storage.findNextInstructionRef(promo.writeBackAfter);
            if (!afterRef.isValid())
                continue;

            MicroInstrOperand backOps[4] = {};
            backOps[0].reg               = promo.base;
            backOps[1].reg               = promo.reg;
            backOps[2].opBits            = promo.bits;
            backOps[3].valueU64          = promo.offset;
            storage.insertDerivedBefore(operands, afterRef, MicroInstrOpcode::LoadMemReg, std::span(backOps, 4));

            storage.erase(promo.loadRef);
            storage.erase(promo.storeRef);
        }

        for (const Hoist& hoist : hoists)
        {
            const MicroInstr* inst = storage.ptr(hoist.ref);
            if (!inst)
                continue;
            const MicroInstrOperand* ops = inst->ops(operands);
            if (!ops)
                continue;

            MicroInstrOperand copied[4] = {};
            const uint8_t     numOps    = inst->numOperands;
            SWC_ASSERT(numOps <= 4);
            for (uint8_t k = 0; k < numOps; ++k)
                copied[k] = ops[k];

            storage.insertDerivedBefore(operands, hoist.beforeRef, MicroInstrOpcode::LoadRegMem, std::span(copied, numOps));
            storage.erase(hoist.ref);
        }

        context.builder->invalidateControlFlowGraph();
        return true;
    }
}

Result MicroPostRaLoopHoistPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    SWC_ASSERT(context.builder != nullptr);

    // Only the first post-RA sweep: what this hoists is the shape register
    // allocation just produced, and a later sweep would pay for the dominator,
    // loop and liveness analyses to find nothing.
    if (!context.isFirstOptimizationSweep)
        return Result::Continue;

    const CallConv& conv = CallConv::get(context.callConvKind);

    for (uint32_t level = 0; level < K_MAX_LEVELS; ++level)
    {
        if (!hoistRound(context, conv))
            break;
        context.passChanged = true;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
