#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRALoopHoist.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Support/Memory/MemoryProfile.h"
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

        MicroOpBits bits   = MicroOpBits::Zero;
        uint64_t    offset = 0;
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
                        rewrites.push_back({instrRefs[k], dst});
                    }
                    claimed.insert(k);
                }
            }
        }

        if (hoists.empty())
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
    SWC_MEM_SCOPE("Backend/MicroLower/PostRALoopHoist");
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
