#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Support/Core/DenseBits.h"
#include "Support/Os/Os.h"

// B-012: the interval-splitting linear scan of Wimmer & Mössenböck (VEE 2005,
// the allocator of HotSpot's client compiler), as a second allocation path the
// pass selects per function, with the existing scan as the always-available
// fallback. This file owns everything interval-shaped; the walk mutates
// nothing until it has fully succeeded, so a bail at any point falls back to
// the existing allocator with the function untouched.

SWC_BEGIN_NAMESPACE();

namespace
{
    // Development gate: SWC_INTERVAL_RA is unset for everyone else, "*" for
    // every eligible function, or a substring of the function names to take.
    const Utf8* intervalGateFilter()
    {
        static const std::optional<Utf8> filter = Os::readEnvironmentVariable("SWC_INTERVAL_RA");
        return filter ? &*filter : nullptr;
    }
}

bool MicroRegisterAllocationPass::intervalGateAccepts() const
{
    const Utf8* filter = intervalGateFilter();
    if (!filter || !context_ || !context_->isFirstAllocationSweep)
        return false;

    // The same CFG precision the write-back protocol needs: every edge into
    // every block known. keepAcrossBoundaries_ is not computed yet at this
    // point, so the condition is tested directly.
    const bool preciseCfg = controlFlowGraph_ != nullptr &&
                            !controlFlowGraph_->hasUnsupportedControlFlowForCfgLiveness() &&
                            controlFlowGraph_->supportsDeadCodeLiveness();
    if (!preciseCfg)
        return false;

    const std::string_view filterView{*filter};
    if (filterView == "*")
        return true;
    const std::string_view symbolName{context_->builder->printSymbolName()};
    return symbolName.find(filterView) != std::string_view::npos;
}

void MicroRegisterAllocationPass::buildLiveIntervals(std::vector<LiveInterval>& out) const
{
    // One interval per dense virtual register, covering every definition of it
    // (Micro virtuals are not SSA: a multi-def web is one interval, as in the
    // paper's LIR). Ranges are assembled forward from the per-instruction
    // live-in rows, refined to slot precision at the endpoints: a value enters
    // an instruction at its input slot and a definition starts at the output
    // slot, so copy-shaped instructions can chain source and destination in
    // one register.
    const size_t virtualCount = denseVirtualRegs_.regs().size();
    out.assign(virtualCount, LiveInterval{});

    const uint32_t wordCount = denseVirtualRegs_.wordCount();

    std::vector<uint8_t> defHere(virtualCount, 0);
    std::vector<uint8_t> useHere(virtualCount, 0);

    for (uint32_t denseIndex = 0; denseIndex < virtualCount; ++denseIndex)
        out[denseIndex].denseIndex = denseIndex;

    // Per-position events first: use and def positions per value, and copy
    // hints - a value born from a register copy prefers its source's
    // register, physical or by value.
    const auto instrRefs = controlFlowGraph_->instructionRefs();
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        for (const uint32_t denseIndex : useVirtualIndices_[idx])
            out[denseIndex].usePositions.push_back(idx * 2);
        for (const uint32_t denseIndex : defVirtualIndices_[idx])
            out[denseIndex].defPositions.push_back(idx * 2 + 1);

        const MicroInstr* inst = instructions_->ptr(instrRefs[idx]);
        if (!inst || inst->op != MicroInstrOpcode::LoadRegReg)
            continue;
        const MicroInstrOperand* ops = inst->ops(*operands_);
        if (!ops || !ops[0].reg.isVirtual())
            continue;
        LiveInterval& dst = out[denseVirtualIndex(ops[0].reg)];
        if (ops[1].reg.isVirtual())
        {
            if (dst.hintDense == std::numeric_limits<uint32_t>::max())
                dst.hintDense = denseVirtualIndex(ops[1].reg);
        }
        else if ((ops[1].reg.isInt() || ops[1].reg.isFloat()) && !dst.hintPhys.isValid())
        {
            dst.hintPhys = ops[1].reg;
        }
    }

    // Ranges: scan each value's hull once, testing its live-in bit per row.
    for (uint32_t denseIndex = 0; denseIndex < virtualCount; ++denseIndex)
    {
        LiveInterval&  interval = out[denseIndex];
        const uint32_t spanLo   = virtualSpanLo_[denseIndex];
        const uint32_t spanHi   = virtualSpanHi_[denseIndex];
        if (spanLo > spanHi)
            continue; // never occupied

        size_t   useCursor = 0;
        size_t   defCursor = 0;
        bool     open      = false;
        uint32_t openFrom  = 0;

        for (uint32_t idx = spanLo; idx <= spanHi; ++idx)
        {
            const bool liveIn = DenseBits::contains(DenseBits::row(liveInVirtualBits_, idx, wordCount), denseIndex);

            bool usedHere = false;
            while (useCursor < interval.usePositions.size() && interval.usePositions[useCursor] < idx * 2)
                ++useCursor;
            if (useCursor < interval.usePositions.size() && interval.usePositions[useCursor] == idx * 2)
                usedHere = true;

            bool definedHere = false;
            while (defCursor < interval.defPositions.size() && interval.defPositions[defCursor] < idx * 2 + 1)
                ++defCursor;
            if (defCursor < interval.defPositions.size() && interval.defPositions[defCursor] == idx * 2 + 1)
                definedHere = true;

            const bool occupiedInput = liveIn || usedHere;
            if (occupiedInput && !open)
            {
                open     = true;
                openFrom = idx * 2;
            }
            if (definedHere && !open)
            {
                open     = true;
                openFrom = idx * 2 + 1;
            }
            if (!open)
                continue;

            // Live into the next instruction keeps the range open across the
            // gap; otherwise it closes at the last slot this instruction
            // holds the value.
            const bool liveNext = idx + 1 < instructionCount_ &&
                                  DenseBits::contains(DenseBits::row(liveInVirtualBits_, idx + 1, wordCount), denseIndex);
            if (liveNext)
                continue;

            const uint32_t to = definedHere ? idx * 2 + 2 : idx * 2 + 1;
            interval.ranges.push_back({openFrom, to});
            open = false;
        }

        if (open)
            interval.ranges.push_back({openFrom, spanHi * 2 + 2});
    }
}

bool MicroRegisterAllocationPass::LiveInterval::covers(const uint32_t pos) const
{
    for (const IntervalRange& range : ranges)
    {
        if (pos < range.from)
            return false;
        if (pos < range.to)
            return true;
    }
    return false;
}

uint32_t MicroRegisterAllocationPass::LiveInterval::nextIntersection(const LiveInterval& other, const uint32_t from) const
{
    // First position >= from covered by both, or UINT32_MAX.
    size_t a = 0;
    size_t b = 0;
    while (a < ranges.size() && b < other.ranges.size())
    {
        const IntervalRange& ra = ranges[a];
        const IntervalRange& rb = other.ranges[b];
        const uint32_t       lo = std::max({ra.from, rb.from, from});
        const uint32_t       hi = std::min(ra.to, rb.to);
        if (lo < hi)
            return lo;
        if (ra.to <= rb.to)
            ++a;
        else
            ++b;
    }
    return std::numeric_limits<uint32_t>::max();
}

uint32_t MicroRegisterAllocationPass::LiveInterval::firstUseAfter(const uint32_t pos) const
{
    // Every access is must-have-register in Micro: reads at input slots and
    // writes at output slots both name a register.
    uint32_t best = std::numeric_limits<uint32_t>::max();
    for (const uint32_t use : usePositions)
    {
        if (use >= pos)
        {
            best = use;
            break;
        }
    }
    for (const uint32_t def : defPositions)
    {
        if (def >= pos)
        {
            best = std::min(best, def);
            break;
        }
    }
    return best;
}

uint32_t MicroRegisterAllocationPass::LiveInterval::firstRangeStartAfter(const uint32_t pos) const
{
    for (const IntervalRange& range : ranges)
    {
        if (range.from >= pos)
            return range.from;
    }
    return std::numeric_limits<uint32_t>::max();
}

void MicroRegisterAllocationPass::buildFixedIntervals(std::vector<LiveInterval>& outByPoolIndex, SmallVector<MicroReg>& outPoolRegs) const
{
    // Candidate registers are the pools setupPools just built, minus the
    // frame pointer and the preferred local stack base in every case:
    // setupPools keeps the base in the pools when no debug stack base exists,
    // but PrologEpilog may still commandeer it after allocation (its own
    // stack-base helper, float save addressing), and a register cannot serve
    // both as that and as an ordinary value. Each candidate gets one fixed
    // interval: a unit range per concrete-claim position, adjacent units
    // coalesced. Claim positions already include call clobbers and concrete
    // liveness between touches.
    outPoolRegs.clear();
    const MicroReg excludedBase = conv_->preferredLocalStackBaseReg();
    const auto     admit        = [&](const MicroReg reg) {
        if (reg == conv_->framePointer || reg == excludedBase)
            return;
        outPoolRegs.push_back(reg);
    };
    for (const MicroReg reg : freeIntTransient_)
        admit(reg);
    for (const MicroReg reg : freeIntPersistent_)
        admit(reg);
    for (const MicroReg reg : freeFloatTransient_)
        admit(reg);
    for (const MicroReg reg : freeFloatPersistent_)
        admit(reg);

    // A claim starts at the output slot only where the definition is a
    // plain write: a copy or a load into the register, or a call's clobber.
    // An arithmetic form that names the register implicitly (a multiply
    // through rax:rdx, a shift by cl, a compare-exchange) reads it or
    // forbids its other operands from it, and the encoder's legalization
    // of the physical form pays a save and restore around it when an
    // operand landed there - so those keep the whole instruction.
    const auto isPlainDefinition = [&](const uint32_t idx) {
        const MicroInstr* inst = instructions_->ptr(controlFlowGraph_->instructionRefs()[idx]);
        if (!inst)
            return false;
        if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
            return true;
        switch (inst->op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::LoadRegPtrImm:
            case MicroInstrOpcode::LoadRegPtrReloc:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
            case MicroInstrOpcode::ClearReg:
                return true;
            default:
                return false;
        }
    };

    outByPoolIndex.assign(outPoolRegs.size(), LiveInterval{});
    const uint32_t concreteWordCount = denseConcreteRegs_.wordCount();
    for (size_t poolIndex = 0; poolIndex < outPoolRegs.size(); ++poolIndex)
    {
        const uint32_t denseConcrete = denseConcreteRegs_.find(outPoolRegs[poolIndex]);
        if (denseConcrete == MicroDenseRegIndex::K_INVALID_INDEX)
            continue;

        // A claim that only defines the register - an ABI argument copy, a
        // call's clobber - starts at the output slot, like a value's own
        // definition: the input slot stays free, so a value read for the
        // last time by that very instruction keeps its register to the end
        // instead of being split one position short of it, which put a pair
        // of connectors in front of every call argument (raytrace's pixel
        // loop: 20 moves against 10). Every other claim (read, or carried
        // through) spans the whole instruction: a register live across an
        // instruction must own its output slot too, or a definition there
        // would clobber it.
        LiveInterval& fixed = outByPoolIndex[poolIndex];
        for (const uint32_t idx : concreteClaimPositionsByDenseIndex_[denseConcrete])
        {
            const bool     usedHere    = std::ranges::find(useConcreteIndices_[idx], denseConcrete) != useConcreteIndices_[idx].end();
            const bool     definedHere = std::ranges::find(defConcreteIndices_[idx], denseConcrete) != defConcreteIndices_[idx].end();
            const bool     liveInHere  = DenseBits::contains(DenseBits::row(liveInConcreteBits_, idx, concreteWordCount), denseConcrete);
            const bool     definedOnly = definedHere && !usedHere && !liveInHere && isPlainDefinition(idx);
            const uint32_t from        = definedOnly ? idx * 2 + 1 : idx * 2;
            const uint32_t to          = idx * 2 + 2;
            if (!fixed.ranges.empty() && fixed.ranges.back().to >= from)
                fixed.ranges.back().to = to;
            else
                fixed.ranges.push_back({from, to});
        }
    }
}

namespace
{
    constexpr uint32_t K_IV_INVALID = std::numeric_limits<uint32_t>::max();

    // A loop as the CFG back-edges draw it: the instruction range from the
    // header to the tail the back-edge leaves from.
    struct LoopRange
    {
        uint32_t head = 0;
        uint32_t tail = 0;
    };

    // Split-tree node bookkeeping shared by the walk below.
    struct WalkState
    {
        std::vector<MicroRegisterAllocationPass::LiveInterval>* nodes = nullptr;
        std::vector<uint32_t>                                   unhandled; // node indices, sorted by start DESCENDING
        std::vector<uint32_t>                                   active;
        std::vector<uint32_t>                                   inactive;
        const std::vector<uint32_t>*                            loopDepth  = nullptr;
        const std::vector<LoopRange>*                           loops      = nullptr;
        uint32_t                                                splitCount = 0;
        uint32_t                                                spillCount = 0;
        bool                                                    failed     = false;
        const char*                                             failReason = nullptr;
    };

    // The paper's optimal split position (section 5.3): a split is legal
    // anywhere in [minPos, maxPos], and every split materializes a connector
    // there, so it belongs at the shallowest loop depth available - the
    // latest such position, so the register serves as long as possible.
    // Positions are even (instruction input boundaries).
    uint32_t chooseSplitPos(const WalkState& walk, const uint32_t minPos, const uint32_t maxPos)
    {
        const uint32_t fallback = maxPos & ~1u;
        if (!walk.loopDepth || walk.loopDepth->empty())
            return fallback;

        const auto&    depth = *walk.loopDepth;
        const uint32_t hiIdx = std::min(static_cast<uint32_t>(depth.size()) - 1, (maxPos & ~1u) / 2);
        const uint32_t loIdx = (minPos + 1) / 2; // first idx with idx*2 >= minPos
        if (loIdx > hiIdx)
            return fallback;

        uint32_t bestIdx   = hiIdx;
        uint32_t bestDepth = depth[hiIdx];
        for (uint32_t idx = hiIdx; idx > loIdx; --idx)
        {
            if (depth[idx - 1] < bestDepth)
            {
                bestIdx   = idx - 1;
                bestDepth = depth[idx - 1];
            }
            if (bestDepth == 0)
                break;
        }
        return bestIdx * 2;
    }

    void pushUnhandled(WalkState& walk, const uint32_t nodeIndex)
    {
        const auto& nodes = *walk.nodes;
        const auto  pos   = std::ranges::upper_bound(walk.unhandled, nodes[nodeIndex].start(),
                                                     [&](const uint32_t start, const uint32_t idx) { return start > nodes[idx].start(); });
        walk.unhandled.insert(pos, nodeIndex);
    }

    // Split `nodeIndex` at even position `pos` (strictly inside it): the node
    // keeps everything before, the child takes everything from `pos` on and is
    // re-queued. Returns the child index, or K_IV_INVALID when the split is
    // impossible there.
    uint32_t splitNodeAt(WalkState& walk, const uint32_t nodeIndex, uint32_t pos)
    {
        auto& nodes = *walk.nodes;
        pos &= ~1u; // even: instruction input boundary
        if (pos <= nodes[nodeIndex].start() || pos >= nodes[nodeIndex].end())
            return K_IV_INVALID;

        MicroRegisterAllocationPass::LiveInterval child;
        child.denseIndex = nodes[nodeIndex].denseIndex;

        auto& parent = nodes[nodeIndex];
        for (size_t rangeIndex = 0; rangeIndex < parent.ranges.size(); ++rangeIndex)
        {
            auto& range = parent.ranges[rangeIndex];
            if (range.to <= pos)
                continue;
            if (range.from >= pos)
            {
                child.ranges.append(parent.ranges.begin() + static_cast<ptrdiff_t>(rangeIndex),
                                    static_cast<uint32_t>(parent.ranges.size() - rangeIndex));
                parent.ranges.resize(rangeIndex);
            }
            else
            {
                child.ranges.push_back({pos, range.to});
                child.ranges.append(parent.ranges.begin() + static_cast<ptrdiff_t>(rangeIndex) + 1,
                                    static_cast<uint32_t>(parent.ranges.size() - rangeIndex - 1));
                range.to = pos;
                parent.ranges.resize(rangeIndex + 1);
            }
            break;
        }
        if (child.ranges.empty() || parent.ranges.empty())
        {
            walk.failed     = true;
            walk.failReason = "degenerate split";
            return K_IV_INVALID;
        }

        const auto moveTail = [pos](auto& fromList, auto& toList) {
            size_t keep = 0;
            while (keep < fromList.size() && fromList[keep] < pos)
                ++keep;
            toList.append(fromList.begin() + static_cast<ptrdiff_t>(keep),
                          static_cast<uint32_t>(fromList.size() - keep));
            fromList.resize(keep);
        };
        moveTail(parent.usePositions, child.usePositions);
        moveTail(parent.defPositions, child.defPositions);

        // The child prefers the register its parent holds (or was itself
        // hinted to): winning it back erases the connector at the cut.
        child.hintPhys = nodes[nodeIndex].assignedReg.isValid() ? nodes[nodeIndex].assignedReg
                                                                : nodes[nodeIndex].hintPhys;

        const auto childIndex = static_cast<uint32_t>(nodes.size());
        nodes.push_back(std::move(child));
        ++walk.splitCount;
        pushUnhandled(walk, childIndex);
        return childIndex;
    }

    // The last access strictly before `pos`, or K_IV_INVALID when the node
    // has none there.
    uint32_t lastAccessBefore(const MicroRegisterAllocationPass::LiveInterval& node, const uint32_t pos)
    {
        uint32_t best = K_IV_INVALID;
        for (const uint32_t use : node.usePositions)
        {
            if (use >= pos)
                break;
            best = best == K_IV_INVALID ? use : std::max(best, use);
        }
        for (const uint32_t def : node.defPositions)
        {
            if (def >= pos)
                break;
            best = best == K_IV_INVALID ? def : std::max(best, def);
        }
        return best;
    }

    // The next access of an owner as the election must see it. Linear order
    // hides a loop: a value a loop reads every iteration has no access after
    // a pressure point late in the body, its next one being at the top of
    // the next iteration, behind the back-edge. Ranked by linear distance it
    // is the farthest candidate of all and the one evicted, and its reload
    // lands on the back-edge of the hottest loop of the function (leven's
    // `g_Bytes` and `bo`, interpolateLuma's parameters). LLVM prices the
    // same use with block frequency in its spill weight; the walk can read
    // it directly: a node live across the back-edge of a loop enclosing the
    // point, with an access earlier in that iteration, is needed again at
    // the back-edge.
    uint32_t nextAccessForElection(const WalkState& walk, const MicroRegisterAllocationPass::LiveInterval& node, const uint32_t from)
    {
        uint32_t next = node.firstUseAfter(from);
        if (!walk.loops)
            return next;
        for (const LoopRange& loop : *walk.loops)
        {
            const uint32_t headPos = loop.head * 2;
            const uint32_t tailPos = loop.tail * 2;
            if (from < headPos || from > tailPos + 1 || tailPos >= next)
                continue;
            if (!node.covers(headPos) || !node.covers(tailPos))
                continue;
            const uint32_t lastAccess = lastAccessBefore(node, from);
            if (lastAccess == K_IV_INVALID || lastAccess < headPos)
                continue;
            next = tailPos;
        }
        return next;
    }

    // Whether split_and_spill below can succeed, decided before any
    // mutation, so a caller may probe several candidate registers.
    bool canSplitAndSpillOwner(const WalkState& walk, const uint32_t ownerIndex, const uint32_t pos)
    {
        const auto&    nodes    = *walk.nodes;
        const uint32_t splitPos = pos & ~1u;
        const uint32_t lastUse  = lastAccessBefore(nodes[ownerIndex], splitPos + 1);
        if (splitPos <= nodes[ownerIndex].start() || splitPos >= nodes[ownerIndex].end())
            return false;
        if (lastUse != K_IV_INVALID && splitPos <= lastUse)
            return false;
        const uint32_t firstAccess = nodes[ownerIndex].firstUseAfter(splitPos);
        if (firstAccess != K_IV_INVALID && (firstAccess & ~1u) <= splitPos)
            return false;
        return true;
    }

    // c1_LinearScan's split_and_spill: the owner loses its register from
    // `pos` on. The tail is split off and spilled to the value's home; the
    // part from its next access on is split again and re-queued so that
    // access gets a register back. The split may land anywhere after the
    // owner's last access before `pos` (nothing between an access and the
    // spill store observes the register).
    bool splitAndSpillOwner(WalkState& walk, const uint32_t ownerIndex, const uint32_t pos)
    {
        auto&          nodes    = *walk.nodes;
        const uint32_t splitPos = pos & ~1u;
        // No access may sit at or beyond the cut on the register side: the
        // spilled child re-earns a register only from its first access on.
        const uint32_t lastUse = lastAccessBefore(nodes[ownerIndex], splitPos + 1);
        if (splitPos <= nodes[ownerIndex].start())
            return false;
        if (lastUse != K_IV_INVALID && splitPos <= lastUse)
            return false;

        // An owner that has not been accessed since it took the register is
        // spilled whole (c1_LinearScan's split_for_spilling when no usage
        // precedes the split): a register node with no access would only
        // pay a reload and a store for nothing, and its memory-to-memory
        // seam with the node before it costs no connector at all.
        uint32_t spilledIndex = ownerIndex;
        if (lastUse == K_IV_INVALID)
        {
            nodes[ownerIndex].spilled = true;
        }
        else
        {
            // The spill store belongs at the shallowest loop depth the
            // interval allows, not at the pressure point itself (paper
            // section 5.3).
            const uint32_t optimalPos = chooseSplitPos(walk, std::max(nodes[ownerIndex].start() + 1, lastUse + 1), splitPos);

            spilledIndex = splitNodeAt(walk, ownerIndex, optimalPos);
            if (spilledIndex == K_IV_INVALID)
                return false;

            // The child was queued as an ordinary competitor by splitNodeAt;
            // it carries in memory instead, and only the part from its first
            // access on competes for a register again.
            auto queued = std::ranges::find(walk.unhandled, spilledIndex);
            if (queued != walk.unhandled.end())
                walk.unhandled.erase(queued);
            nodes[spilledIndex].spilled = true;
        }
        ++walk.spillCount;

        // The reload child is queued as unhandled, and the walk only ever
        // moves forward: a child starting before the request would be
        // walked against active and inactive lists that no longer hold the
        // nodes it overlaps (the owner's own earlier register node among
        // them, already retired), and could be handed their register. So
        // the reload lands no earlier than the request, whatever the loop
        // depth further back would have preferred.
        const uint32_t firstAccess = nodes[spilledIndex].firstUseAfter(nodes[spilledIndex].start());
        bool           ok          = true;
        if (firstAccess != K_IV_INVALID)
        {
            if ((firstAccess & ~1u) <= nodes[spilledIndex].start())
                ok = false; // an access immediately at the takeover point: the register was not takeable
            else
            {
                const uint32_t reloadPos = chooseSplitPos(walk, std::max(nodes[spilledIndex].start() + 1, splitPos), firstAccess);
                ok                       = splitNodeAt(walk, spilledIndex, reloadPos) != K_IV_INVALID;
            }
        }
        // A whole-node spill gives the register up only now, so the reload
        // child inherited it as its hint.
        if (spilledIndex == ownerIndex)
            nodes[ownerIndex].assignedReg = MicroReg::invalid();
        return ok;
    }
}

bool MicroRegisterAllocationPass::walkIntervals(std::vector<LiveInterval>&& intervals, IntervalWalkResult& out) const
{
    // The walk of Wimmer & Mössenböck section 5: unhandled by increasing
    // start; tryAllocateFreeReg with freeUntilPos, else allocateBlockedReg
    // with nextUsePos; splitting instead of whole-value eviction. Pure
    // analysis - nothing here mutates the function.
    std::vector<LiveInterval> fixed;
    SmallVector<MicroReg>     poolRegs;
    buildFixedIntervals(fixed, poolRegs);

    out.nodes = std::move(intervals);

    // The loops, from the back-edges of the instruction CFG, for the
    // election's view of a loop-carried access.
    std::vector<LoopRange> loops;
    if (hasControlFlow_)
    {
        for (uint32_t s = 0; s < instructionCount_ && s < predecessors_.size(); ++s)
        {
            for (const uint32_t p : predecessors_[s])
            {
                if (p >= s && p < instructionCount_)
                    loops.push_back({.head = s, .tail = p});
            }
        }
    }

    WalkState walk;
    walk.nodes     = &out.nodes;
    walk.loopDepth = &loopDepth_;
    walk.loops     = &loops;

    // Per-register ownership among active/inactive is tracked through the
    // node's assignedReg; fixed intervals are consulted by pool index.
    const size_t poolCount = poolRegs.size();
    out.poolRegs           = poolRegs;

    // The debug local-stack base lives in the register the ABI keeps outside
    // both pools for it, for its whole life and never split, exactly as
    // assignGlobalRegisters pins it: the debug records name that register
    // for every local, and PrologEpilog keeps it in step afterwards.
    uint32_t pinnedIndex = K_IV_INVALID;
    if (context_->debugStackBaseVirtualReg.isValid())
    {
        const uint32_t denseIndex = denseVirtualRegs_.find(context_->debugStackBaseVirtualReg);
        const MicroReg baseReg    = conv_->preferredLocalStackBaseReg();
        if (denseIndex != MicroDenseRegIndex::K_INVALID_INDEX && baseReg.isValid() &&
            !out.nodes[denseIndex].ranges.empty() &&
            !isPhysRegForbiddenForVirtual(context_->debugStackBaseVirtualReg, baseReg) &&
            !concreteClaimsOverlap(baseReg, virtualSpanLo_[denseIndex], virtualSpanHi_[denseIndex]))
        {
            out.nodes[denseIndex].assignedReg = baseReg;
            out.debugStackBasePhys            = baseReg;
            pinnedIndex                       = denseIndex;
        }
    }

    for (uint32_t nodeIndex = 0; nodeIndex < out.nodes.size(); ++nodeIndex)
    {
        if (!out.nodes[nodeIndex].ranges.empty() && nodeIndex != pinnedIndex)
            pushUnhandled(walk, nodeIndex);
    }

    std::vector<uint32_t> freeUntilPos(poolCount);
    std::vector<uint32_t> nextUsePos(poolCount);

    // A livelock backstop: a legitimate walk processes each node once, plus
    // one requeue per split. Anything far beyond that is the walk arguing
    // with itself over one register, and the function falls back.
    const uint32_t iterationBudget = 16 * static_cast<uint32_t>(out.nodes.size()) + 256;
    uint32_t       iterations      = 0;

    while (!walk.unhandled.empty() && !walk.failed)
    {
        if (++iterations > iterationBudget)
        {
            walk.failed     = true;
            walk.failReason = "walk iteration budget exhausted";
            break;
        }
        const uint32_t currentIndex = walk.unhandled.back();
        walk.unhandled.pop_back();
        const uint32_t position       = out.nodes[currentIndex].start();
        const MicroReg currentVirtual = denseVirtualRegs_.regs()[out.nodes[currentIndex].denseIndex];
        const bool     isFloat        = currentVirtual.isAnyFloat();

        // The registers the lowering forbade for this value (an argument
        // register a value must stay out of while the arguments are being
        // marshalled, and the like) are off the table in both elections, as
        // they are in the existing scan.
        const auto forbiddenForCurrent = [&](const size_t poolIndex) {
            return isPhysRegForbiddenForVirtual(currentVirtual, poolRegs[poolIndex]);
        };

        // Retire and reclassify.
        const auto refresh = [&](std::vector<uint32_t>& list, const bool wantCovers) {
            for (size_t i = 0; i < list.size();)
            {
                const LiveInterval& node = out.nodes[list[i]];
                if (node.end() <= position)
                {
                    list[i] = list.back();
                    list.pop_back();
                    continue;
                }
                if (node.covers(position) != wantCovers)
                {
                    (wantCovers ? walk.inactive : walk.active).push_back(list[i]);
                    list[i] = list.back();
                    list.pop_back();
                    continue;
                }
                ++i;
            }
        };
        refresh(walk.active, true);
        refresh(walk.inactive, false);

        const auto poolIndexOf = [&](const MicroReg reg) -> size_t {
            for (size_t i = 0; i < poolCount; ++i)
            {
                if (poolRegs[i] == reg)
                    return i;
            }
            return poolCount;
        };

        // tryAllocateFreeReg
        for (size_t i = 0; i < poolCount; ++i)
            freeUntilPos[i] = poolRegs[i].isAnyFloat() == isFloat && !forbiddenForCurrent(i) ? std::numeric_limits<uint32_t>::max() : 0;
        for (const uint32_t activeIndex : walk.active)
        {
            const size_t poolIndex = poolIndexOf(out.nodes[activeIndex].assignedReg);
            if (poolIndex < poolCount)
                freeUntilPos[poolIndex] = 0;
        }
        for (const uint32_t inactiveIndex : walk.inactive)
        {
            const size_t poolIndex = poolIndexOf(out.nodes[inactiveIndex].assignedReg);
            if (poolIndex >= poolCount || !freeUntilPos[poolIndex])
                continue;
            freeUntilPos[poolIndex] = std::min(freeUntilPos[poolIndex],
                                               out.nodes[inactiveIndex].nextIntersection(out.nodes[currentIndex], position));
        }
        for (size_t i = 0; i < poolCount; ++i)
        {
            if (!freeUntilPos[i] || fixed[i].ranges.empty())
                continue;
            freeUntilPos[i] = std::min(freeUntilPos[i], fixed[i].nextIntersection(out.nodes[currentIndex], position));
        }

        size_t bestFree = poolCount;
        for (size_t i = 0; i < poolCount; ++i)
        {
            if (freeUntilPos[i] && (bestFree == poolCount || freeUntilPos[i] > freeUntilPos[bestFree]))
                bestFree = i;
        }

        // The hint register wins ties, and wins outright when it serves the
        // whole interval: coming back to the register an earlier node held -
        // or taking the copy source's register - erases a move.
        MicroReg hint = out.nodes[currentIndex].hintPhys;
        if (!hint.isValid() && out.nodes[currentIndex].hintDense != std::numeric_limits<uint32_t>::max())
        {
            const uint32_t at = out.nodes[currentIndex].start() & ~1u;
            for (const LiveInterval& other : out.nodes)
            {
                if (other.denseIndex == out.nodes[currentIndex].hintDense &&
                    !other.spilled && other.assignedReg.isValid() && other.covers(at))
                {
                    hint = other.assignedReg;
                    break;
                }
            }
        }
        if (hint.isValid() && bestFree < poolCount)
        {
            const size_t hintIdx = poolIndexOf(hint);
            if (hintIdx < poolCount && freeUntilPos[hintIdx] &&
                (freeUntilPos[hintIdx] >= out.nodes[currentIndex].end() ||
                 freeUntilPos[hintIdx] >= freeUntilPos[bestFree]))
                bestFree = hintIdx;
        }

        // Usable only when the register serves the whole interval, or the
        // partial allocation leaves a legal even split position strictly
        // inside it.
        const bool freeServesWhole = bestFree < poolCount && freeUntilPos[bestFree] >= out.nodes[currentIndex].end();
        const bool freeSplittable  = bestFree < poolCount && (freeUntilPos[bestFree] & ~1u) > position;
        if (freeServesWhole || freeSplittable)
        {
            out.nodes[currentIndex].assignedReg = poolRegs[bestFree];
            if (freeUntilPos[bestFree] < out.nodes[currentIndex].end())
            {
                const uint32_t splitPos = chooseSplitPos(walk, position + 1, freeUntilPos[bestFree]);
                if (splitNodeAt(walk, currentIndex, splitPos) == K_IV_INVALID && !walk.failed)
                {
                    walk.failed     = true;
                    walk.failReason = "free-reg split landed outside the interval";
                }
            }
            walk.active.push_back(currentIndex);
            continue;
        }

        // allocateBlockedReg. Owners are measured from the instruction's
        // INPUT slot: an owner the very same instruction still reads must
        // never win the election, since its register cannot be vacated
        // between the read and the write.
        const uint32_t electionFrom = position & ~1u;
        for (size_t i = 0; i < poolCount; ++i)
            nextUsePos[i] = poolRegs[i].isAnyFloat() == isFloat && !forbiddenForCurrent(i) ? std::numeric_limits<uint32_t>::max() : 0;
        for (const uint32_t activeIndex : walk.active)
        {
            const size_t poolIndex = poolIndexOf(out.nodes[activeIndex].assignedReg);
            if (poolIndex < poolCount && nextUsePos[poolIndex])
                nextUsePos[poolIndex] = std::min(nextUsePos[poolIndex], nextAccessForElection(walk, out.nodes[activeIndex], electionFrom));
        }
        for (const uint32_t inactiveIndex : walk.inactive)
        {
            const size_t poolIndex = poolIndexOf(out.nodes[inactiveIndex].assignedReg);
            if (poolIndex >= poolCount || !nextUsePos[poolIndex])
                continue;
            if (out.nodes[inactiveIndex].nextIntersection(out.nodes[currentIndex], position) != std::numeric_limits<uint32_t>::max())
                nextUsePos[poolIndex] = std::min(nextUsePos[poolIndex], nextAccessForElection(walk, out.nodes[inactiveIndex], electionFrom));
        }
        // A fixed claim is a hard block (c1_LinearScan's blockPos): the
        // register cannot serve current past it, so it caps the election the
        // same way a competitor's next use does.
        for (size_t i = 0; i < poolCount; ++i)
        {
            if (!nextUsePos[i] || fixed[i].ranges.empty())
                continue;
            const uint32_t clash = fixed[i].nextIntersection(out.nodes[currentIndex], position);
            if (clash != std::numeric_limits<uint32_t>::max())
                nextUsePos[i] = std::min(nextUsePos[i], clash);
        }

        // Choose among candidates by farthest next use, but only a register
        // whose every owner can actually be split-and-spilled at the takeover
        // qualifies - the runner-up serves when the best owner is pinned to
        // this very instruction by its own access.
        const uint32_t currentFirstUse = out.nodes[currentIndex].firstUseAfter(position);

        size_t chosen = poolCount;
        for (;;)
        {
            size_t best = poolCount;
            for (size_t i = 0; i < poolCount; ++i)
            {
                if (nextUsePos[i] && (best == poolCount || nextUsePos[i] > nextUsePos[best]))
                    best = i;
            }
            if (best == poolCount || currentFirstUse > nextUsePos[best])
                break; // no candidate helps more than spilling current

            bool feasible = true;
            for (const uint32_t activeIndex : walk.active)
            {
                if (out.nodes[activeIndex].assignedReg == poolRegs[best])
                    feasible = feasible && canSplitAndSpillOwner(walk, activeIndex, position);
            }
            for (const uint32_t inactiveIndex : walk.inactive)
            {
                if (out.nodes[inactiveIndex].assignedReg != poolRegs[best])
                    continue;
                const uint32_t intersection = out.nodes[inactiveIndex].nextIntersection(out.nodes[currentIndex], position);
                if (intersection != std::numeric_limits<uint32_t>::max())
                    feasible = feasible && canSplitAndSpillOwner(walk, inactiveIndex, intersection);
            }
            if (feasible)
            {
                chosen = best;
                break;
            }
            nextUsePos[best] = 0; // disqualified: try the runner-up
        }

        if (chosen == poolCount)
        {
            // Spill current: it carries, others compute. Split before its
            // first access; the head is register-free.
            if (currentFirstUse != std::numeric_limits<uint32_t>::max() &&
                (currentFirstUse & ~1u) <= out.nodes[currentIndex].start())
            {
                walk.failed     = true;
                walk.failReason = "no register and current is accessed at its start";
                break;
            }
            out.nodes[currentIndex].spilled = true;
            ++walk.spillCount;
            if (currentFirstUse != std::numeric_limits<uint32_t>::max())
            {
                const uint32_t reloadPos = chooseSplitPos(walk, out.nodes[currentIndex].start() + 1, currentFirstUse);
                if (splitNodeAt(walk, currentIndex, reloadPos) == K_IV_INVALID && !walk.failed)
                {
                    walk.failed     = true;
                    walk.failReason = "spill split before first access failed";
                }
            }
            continue;
        }

        // Take the register: its owners are split-and-spilled from here on,
        // pre-validated above so the splits cannot fail.
        out.nodes[currentIndex].assignedReg = poolRegs[chosen];
        for (size_t i = 0; i < walk.active.size(); ++i)
        {
            const uint32_t activeIndex = walk.active[i];
            if (out.nodes[activeIndex].assignedReg != poolRegs[chosen])
                continue;
            if (!splitAndSpillOwner(walk, activeIndex, position) && !walk.failed)
            {
                walk.failed     = true;
                walk.failReason = "cannot split the active owner at the request";
            }
            break;
        }
        if (walk.failed)
            break;
        for (const uint32_t inactiveIndex : walk.inactive)
        {
            if (out.nodes[inactiveIndex].assignedReg != poolRegs[chosen])
                continue;
            const uint32_t intersection = out.nodes[inactiveIndex].nextIntersection(out.nodes[currentIndex], position);
            if (intersection == std::numeric_limits<uint32_t>::max())
                continue;
            if (!splitAndSpillOwner(walk, inactiveIndex, intersection) && !walk.failed)
            {
                walk.failed     = true;
                walk.failReason = "cannot split an inactive owner at the intersection";
            }
        }
        if (walk.failed)
            break;
        if (!fixed[chosen].ranges.empty())
        {
            const uint32_t fixedClash = fixed[chosen].nextIntersection(out.nodes[currentIndex], position);
            if (fixedClash != std::numeric_limits<uint32_t>::max())
            {
                // A claim that only defines the register clashes at an output
                // slot; the walk splits at input slots only, so the split
                // lands at the latest legal even position before the clash.
                if (splitNodeAt(walk, currentIndex, chooseSplitPos(walk, position + 1, fixedClash)) == K_IV_INVALID && !walk.failed)
                {
                    walk.failed     = true;
                    walk.failReason = "cannot split before a fixed clash";
                }
            }
        }
        if (!walk.failed)
            walk.active.push_back(currentIndex);
    }

    out.splitCount = walk.splitCount;
    out.spillCount = walk.spillCount;

    if (walk.failed)
        return false;

    // Group nodes per value for the consumers (rewrite, resolution, dump).
    std::vector<uint32_t> order(out.nodes.size());
    for (uint32_t i = 0; i < order.size(); ++i)
        order[i] = i;
    std::ranges::sort(order, [&](const uint32_t a, const uint32_t b) {
        if (out.nodes[a].denseIndex != out.nodes[b].denseIndex)
            return out.nodes[a].denseIndex < out.nodes[b].denseIndex;
        return out.nodes[a].start() < out.nodes[b].start();
    });
    std::vector<LiveInterval> sorted;
    sorted.reserve(out.nodes.size());
    for (const uint32_t i : order)
        sorted.push_back(std::move(out.nodes[i]));
    out.nodes = std::move(sorted);

    const size_t virtualCount = denseVirtualRegs_.regs().size();
    out.valueNodesBegin.assign(virtualCount + 1, 0);
    for (const LiveInterval& node : out.nodes)
        ++out.valueNodesBegin[node.denseIndex + 1];
    for (size_t i = 1; i <= virtualCount; ++i)
        out.valueNodesBegin[i] += out.valueNodesBegin[i - 1];

    return true;
}

bool MicroRegisterAllocationPass::applyIntervalAllocation(IntervalWalkResult& result)
{
    // Commit the walk's assignment: rewrite every virtual operand to the
    // register of the node covering its position, and reconcile locations at
    // node boundaries and CFG edges with moves, stores and loads. Everything
    // is planned first and only then applied, so a bail leaves the function
    // untouched for the existing allocator.
    const auto&    virtualRegs  = denseVirtualRegs_.regs();
    const size_t   virtualCount = virtualRegs.size();
    const uint32_t invalid      = std::numeric_limits<uint32_t>::max();

    const auto locate = [&](const uint32_t denseIndex, const uint32_t pos) -> const LiveInterval* {
        for (uint32_t n = result.valueNodesBegin[denseIndex]; n < result.valueNodesBegin[denseIndex + 1]; ++n)
        {
            if (result.nodes[n].covers(pos))
                return &result.nodes[n];
        }
        return nullptr;
    };

    // Stack depth per instruction, propagated over the CFG (mid-body rsp
    // deltas are call-argument staging; a connector's spill offset must use
    // the depth at its insertion point).
    std::vector<int64_t> depthAt(instructionCount_, std::numeric_limits<int64_t>::min());
    {
        std::vector<uint32_t> worklist;
        depthAt[0] = 0;
        worklist.push_back(0);
        while (!worklist.empty())
        {
            const uint32_t idx = worklist.back();
            worklist.pop_back();
            int64_t depth = depthAt[idx];

            const MicroInstr* inst = instructions_->ptr(controlFlowGraph_->instructionRefs()[idx]);
            if (!inst)
                return false;
            applyStackPointerDelta(depth, *inst);
            for (const uint32_t succ : controlFlowGraph_->successors(idx))
            {
                if (succ >= instructionCount_)
                    continue;
                if (depthAt[succ] == std::numeric_limits<int64_t>::min())
                {
                    depthAt[succ] = depth;
                    worklist.push_back(succ);
                }
                else if (depthAt[succ] != depth)
                {
                    return false; // stack depth disagrees at a join
                }
            }
        }
    }

    // One planned insertion: a connector before an instruction. A connector
    // carrying a trampJump belongs to that conditional jump's taken-edge
    // trampoline: the jcc is inverted around an inline block holding the
    // moves and an unconditional jump to the original target.
    struct Connector
    {
        uint32_t beforeIndex = 0;
        uint32_t order       = 0; // parallel-copy order within the point
        MicroReg dst;             // invalid => store to home
        MicroReg src;             // invalid => load from home
        uint32_t denseIndex = 0;
        uint32_t trampJump  = std::numeric_limits<uint32_t>::max();
        bool     exchange   = false; // swap dst and src: the head of a copy cycle
    };
    std::vector<Connector> connectors;

    struct Trampoline
    {
        uint32_t      jumpIndex  = 0;
        MicroCond     inverted   = MicroCond::Unconditional;
        MicroOpBits   opBits     = MicroOpBits::B32;
        uint64_t      origTarget = 0;
        MicroLabelRef newLabel;
    };
    std::vector<Trampoline> trampolines;

    const auto invertMicroCond = [](const MicroCond cond, MicroCond& outInverted) {
        switch (cond)
        {
            case MicroCond::Equal: outInverted = MicroCond::NotEqual; return true;
            case MicroCond::NotEqual: outInverted = MicroCond::Equal; return true;
            case MicroCond::Zero: outInverted = MicroCond::NotZero; return true;
            case MicroCond::NotZero: outInverted = MicroCond::Zero; return true;
            case MicroCond::Below: outInverted = MicroCond::AboveOrEqual; return true;
            case MicroCond::AboveOrEqual: outInverted = MicroCond::Below; return true;
            case MicroCond::BelowOrEqual: outInverted = MicroCond::Above; return true;
            case MicroCond::Above: outInverted = MicroCond::BelowOrEqual; return true;
            case MicroCond::Less: outInverted = MicroCond::GreaterOrEqual; return true;
            case MicroCond::GreaterOrEqual: outInverted = MicroCond::Less; return true;
            case MicroCond::LessOrEqual: outInverted = MicroCond::Greater; return true;
            case MicroCond::Greater: outInverted = MicroCond::LessOrEqual; return true;
            default: return false;
        }
    };

    // The width a register move carries: the whole value, 128 bits for a
    // float some instruction names that wide and 64 otherwise - the width
    // ensureSpillSlot gives a home, whether or not this value ever gets one.
    // spillBits is only set by ensureSpillSlot, so a value moved between
    // registers and never spilled would otherwise move as 64 bits and lose
    // its upper lanes.
    const auto valueBits = [&](const uint32_t denseIndex) {
        const bool wide = virtualRegs[denseIndex].isAnyFloat() && states_[denseIndex].wideFloat;
        return wide ? MicroOpBits::B128 : MicroOpBits::B64;
    };

    const auto addConnector = [&](const uint32_t beforeIndex, const uint32_t denseIndex,
                                  const LiveInterval* fromNode, const LiveInterval* toNode) {
        const MicroReg fromReg = (fromNode && !fromNode->spilled) ? fromNode->assignedReg : MicroReg::invalid();
        const MicroReg toReg   = (toNode && !toNode->spilled) ? toNode->assignedReg : MicroReg::invalid();
        if (fromReg == toReg)
            return; // same register, or memory-to-memory
        if (!fromReg.isValid() && !toReg.isValid())
            return;
        connectors.push_back({beforeIndex, 0, toReg, fromReg, denseIndex});
    };

    // Adjacent-node connectors: a true split (A.end == B.start) inside a
    // block. Splits land on even positions only, so the point is an
    // instruction input boundary; label positions belong to edge resolution.
    for (uint32_t denseIndex = 0; denseIndex < virtualCount; ++denseIndex)
    {
        for (uint32_t n = result.valueNodesBegin[denseIndex]; n + 1 < result.valueNodesBegin[denseIndex + 1]; ++n)
        {
            const LiveInterval& a = result.nodes[n];
            const LiveInterval& b = result.nodes[n + 1];
            if (a.end() != b.start())
                continue; // hole: the next node starts at a def, nothing carried
            const uint32_t beforeIndex = b.start() / 2;
            if (beforeIndex >= instructionCount_)
                return false;
            const MicroInstr* inst = instructions_->ptr(controlFlowGraph_->instructionRefs()[beforeIndex]);
            if (!inst)
                return false;
            if (inst->op == MicroInstrOpcode::Label)
                continue; // edge resolution owns label positions
            addConnector(beforeIndex, denseIndex, &a, &b);
        }
    }

    // Edge connectors. For each label, each predecessor edge reconciles the
    // location at the predecessor's end with the location at the label.
    const uint32_t wordCount = denseVirtualRegs_.wordCount();
    for (uint32_t s = 0; s < instructionCount_; ++s)
    {
        const MicroInstr* labelInst = instructions_->ptr(controlFlowGraph_->instructionRefs()[s]);
        if (!labelInst || labelInst->op != MicroInstrOpcode::Label)
            continue;
        if (s >= predecessors_.size())
            return false;

        const std::span<const uint64_t> liveRow = DenseBits::row(liveInVirtualBits_, s, wordCount);
        for (const uint32_t p : predecessors_[s])
        {
            if (p >= instructionCount_)
                return false;
            const MicroInstr* predInst = instructions_->ptr(controlFlowGraph_->instructionRefs()[p]);
            if (!predInst)
                return false;

            const bool fallThroughPred = p + 1 == s && !MicroInstrInfo::isTerminatorInstruction(*predInst);
            const bool isJump          = MicroInstr::info(predInst->op).flags.has(MicroInstrFlagsE::JumpInstruction);
            // Conditionality lives in the operand, not the opcode: an
            // unconditional jump is a JumpCond carrying Unconditional, and it
            // has no fall-through side to protect.
            const MicroInstrOperand* predOpsEarly  = predInst->ops(*operands_);
            const bool               isConditional = MicroInstr::info(predInst->op).flags.has(MicroInstrFlagsE::ConditionalJump) &&
                                       predOpsEarly && predOpsEarly[0].cpuCond != MicroCond::Unconditional;

            // The insertion point: before the label for the fall-through
            // edge (jumps land past it), before the jump otherwise.
            const uint32_t beforeIndex = fallThroughPred ? s : p;

            // Collect this edge's moves first; placement is decided for the
            // edge as a whole.
            struct EdgeMove
            {
                uint32_t            denseIndex = 0;
                const LiveInterval* from       = nullptr;
                const LiveInterval* to         = nullptr;
            };
            SmallVector<EdgeMove, 8> edgeMoves;

            for (size_t wordIndex = 0; wordIndex < liveRow.size(); ++wordIndex)
            {
                uint64_t wordBits = liveRow[wordIndex];
                while (wordBits)
                {
                    const auto denseIndex = static_cast<uint32_t>(wordIndex * 64ull + std::countr_zero(wordBits));
                    wordBits &= wordBits - 1ull;
                    if (denseIndex >= virtualCount)
                        break;

                    // The edge leaves at the jump's INPUT slot: a value dead
                    // on the jump's other side closes its range at p*2+1
                    // exclusive, so the output slot may sit in a hole even
                    // though the value crosses this edge. A fall-through
                    // predecessor is an ordinary instruction that may define
                    // the value, so its end state is the output slot.
                    const uint32_t      predEndPos = isJump ? p * 2 : p * 2 + 1;
                    const LiveInterval* atLabel    = locate(denseIndex, s * 2);
                    const LiveInterval* atPred     = locate(denseIndex, predEndPos);
                    if (!atLabel || !atPred || atLabel == atPred)
                        continue;
                    const MicroReg fromReg = atPred->spilled ? MicroReg::invalid() : atPred->assignedReg;
                    const MicroReg toReg   = atLabel->spilled ? MicroReg::invalid() : atLabel->assignedReg;
                    if (fromReg == toReg)
                        continue;

                    edgeMoves.push_back({denseIndex, atPred, atLabel});
                }
            }

            if (edgeMoves.empty())
                continue;
            if (!isJump && !fallThroughPred)
                return false; // an edge shape this stage does not model

            // Placement for the edge as a whole. The fall-through edge
            // inserts before the label - jumps land past it, so it runs on
            // this edge alone. A jump edge prefers the spot before the jump;
            // when a written register is not free there, the edge gets a
            // trampoline instead: the jcc inverted around an inline block of
            // the moves plus a jump to the original target, which runs on
            // the taken path alone.
            bool plainOk = isJump || fallThroughPred;
            if (!fallThroughPred)
            {
                for (const EdgeMove& move : edgeMoves)
                {
                    const MicroReg toReg = move.to->spilled ? MicroReg::invalid() : move.to->assignedReg;
                    if (!toReg.isValid())
                        continue;
                    for (const MicroReg use : instructionUseDefs_[p].uses)
                        plainOk = plainOk && use != toReg; // an indirect jump's own read
                    if (concreteClaimsOverlap(toReg, p, p))
                        plainOk = false;
                    if (isConditional && p + 1 < instructionCount_)
                    {
                        if (concreteClaimsOverlap(toReg, p + 1, p + 1))
                            plainOk = false;
                        // The write runs on the fall-through side too: any
                        // OTHER value holding that register there, or this
                        // value expecting it from a different source, kills
                        // the plain placement.
                        for (uint32_t other = 0; plainOk && other < virtualCount; ++other)
                        {
                            if (other == move.denseIndex)
                                continue;
                            const LiveInterval* node = locate(other, p * 2 + 2);
                            if (node && !node->spilled && node->assignedReg == toReg)
                                plainOk = false;
                        }
                        const LiveInterval* ownFall = locate(move.denseIndex, p * 2 + 2);
                        if (ownFall && !ownFall->spilled && ownFall->assignedReg == toReg && ownFall != move.from &&
                            (move.from->spilled || ownFall->assignedReg != move.from->assignedReg))
                            plainOk = false;
                    }
                    if (!plainOk)
                        break;
                }
            }

            uint32_t trampJump = std::numeric_limits<uint32_t>::max();
            if (!plainOk)
            {
                MicroCond                inverted = MicroCond::Unconditional;
                const MicroInstrOperand* predOps  = predInst->ops(*operands_);
                if (!isConditional || !predOps || !invertMicroCond(predOps[0].cpuCond, inverted))
                    return false; // uninvertible edge
                Trampoline trampoline;
                trampoline.jumpIndex  = p;
                trampoline.inverted   = inverted;
                trampoline.opBits     = predOps[1].opBits;
                trampoline.origTarget = predOps[2].valueU64;
                trampoline.newLabel   = context_->builder->createLabel();
                trampolines.push_back(trampoline);
                trampJump = p;
            }

            for (const EdgeMove& move : edgeMoves)
            {
                const size_t before = connectors.size();
                addConnector(plainOk ? beforeIndex : p + 1, move.denseIndex, move.from, move.to);
                if (connectors.size() != before)
                    connectors.back().trampJump = trampJump;
            }
        }
    }

    // Spill-store placement. The home of a value is written either where
    // resolution put its stores (a register node handing over to a spilled
    // one, an edge from a register to memory), or once after every
    // definition - after which every resolution store is redundant, since
    // the home already holds the value the path defined last. The second is
    // c1_LinearScan's storeAtDefinition for one definition and LLVM's
    // InlineSpiller spilling at every def in general; the cheaper placement
    // by loop depth wins, so a loop-invariant value reloaded and spilled
    // again inside a loop pays no store there, while a loop-carried value
    // spilled only at the loop exit keeps that one store. A trampoline left
    // without connectors is dropped with them.
    {
        const auto weightAt = [&](const uint32_t idx) -> uint64_t {
            const uint32_t depth = idx < loopDepth_.size() ? std::min(loopDepth_[idx], 8u) : 0u;
            return 1ull << (3 * depth);
        };
        std::vector<uint64_t> resolutionStoreCost(virtualCount, 0);
        for (const Connector& connector : connectors)
        {
            if (!connector.dst.isValid())
                resolutionStoreCost[connector.denseIndex] += weightAt(connector.beforeIndex);
        }
        bool rewritten = false;
        for (uint32_t denseIndex = 0; denseIndex < virtualCount; ++denseIndex)
        {
            if (!resolutionStoreCost[denseIndex])
                continue;
            SmallVector<Connector, 4> defStores;
            uint64_t                  defStoreCost = 0;
            bool                      placeable    = true;
            for (uint32_t n = result.valueNodesBegin[denseIndex]; placeable && n < result.valueNodesBegin[denseIndex + 1]; ++n)
            {
                const LiveInterval& node = result.nodes[n];
                for (const uint32_t defPos : node.defPositions)
                {
                    const uint32_t defIndex = defPos / 2;
                    if (defIndex + 1 >= instructionCount_ || node.spilled || !node.assignedReg.isValid())
                    {
                        placeable = false;
                        break;
                    }
                    defStores.push_back({defIndex + 1, 0, MicroReg::invalid(), node.assignedReg, denseIndex});
                    defStoreCost += weightAt(defIndex);
                }
            }
            if (!placeable || defStores.empty() || defStoreCost > resolutionStoreCost[denseIndex])
                continue;
            std::erase_if(connectors, [&](const Connector& connector) { return connector.denseIndex == denseIndex && !connector.dst.isValid(); });
            for (const Connector& store : defStores)
                connectors.push_back(store);
            rewritten = true;
        }
        if (rewritten)
        {
            std::erase_if(trampolines, [&](const Trampoline& trampoline) {
                return std::ranges::none_of(connectors, [&](const Connector& connector) { return connector.trampJump == trampoline.jumpIndex; });
            });
        }
    }

    // Parallel-copy ordering per insertion point: a connector reading a
    // register another one writes must run first. A cycle needs a bounce and
    // stage 1 declines it. A trampoline is its own point even when it shares
    // the physical insertion spot with a fall-through edge's connectors.
    {
        std::map<uint64_t, std::vector<size_t>> byPoint;
        for (size_t i = 0; i < connectors.size(); ++i)
        {
            const bool isTramp = connectors[i].trampJump != std::numeric_limits<uint32_t>::max();
            byPoint[(static_cast<uint64_t>(connectors[i].beforeIndex) << 1) | (isTramp ? 0u : 1u)].push_back(i);
        }
        for (auto& [point, list] : byPoint)
        {
            uint32_t          order = 0;
            std::vector<bool> emitted(list.size(), false);
            for (;;)
            {
                bool progressed = true;
                while (progressed)
                {
                    progressed = false;
                    for (size_t i = 0; i < list.size(); ++i)
                    {
                        if (emitted[i])
                            continue;
                        const Connector& candidate = connectors[list[i]];
                        bool             readLater = false;
                        for (size_t j = 0; j < list.size(); ++j)
                        {
                            if (i == j || emitted[j])
                                continue;
                            readLater = readLater ||
                                        (candidate.dst.isValid() && connectors[list[j]].src == candidate.dst);
                        }
                        if (readLater)
                            continue;
                        connectors[list[i]].order = order++;
                        emitted[i]                = true;
                        progressed                = true;
                    }
                }

                size_t cycleHead = list.size();
                for (size_t i = 0; i < list.size(); ++i)
                {
                    if (!emitted[i])
                    {
                        cycleHead = i;
                        break;
                    }
                }
                if (cycleHead == list.size())
                    break;

                // What remains is a register cycle: a home load reads no
                // register and a home store writes none, so neither sits on
                // one. It is broken at its head by an exchange (the standard
                // parallel-move sequentialization): the head's destination
                // receives its source, and the source register then holds the
                // destination's former value, so every pending reader of
                // either register is redirected; a reader that becomes its
                // own source is done. The exchange writes nothing the plain
                // moves would not have, so the edge's placement stays legal.
                Connector& head = connectors[list[cycleHead]];
                if (!head.dst.isValid() || !head.src.isValid())
                    return false;
                const MicroReg headDst = head.dst;
                const MicroReg headSrc = head.src;
                head.exchange          = true;
                head.order             = order++;
                emitted[cycleHead]     = true;
                for (size_t j = 0; j < list.size(); ++j)
                {
                    if (emitted[j])
                        continue;
                    Connector& other = connectors[list[j]];
                    if (other.src == headDst)
                        other.src = headSrc;
                    else if (other.src == headSrc)
                        other.src = headDst;
                    if (other.src.isValid() && other.src == other.dst)
                        emitted[j] = true;
                }
            }
        }
    }

    // Pre-validate every operand's coverage before anything mutates: each
    // virtual access must resolve to a register node.
    {
        uint32_t idx = 0;
        for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it, ++idx)
        {
            SmallVector<MicroInstrRegOperandRef> regRefs;
            it->collectRegOperands(*operands_, regRefs, context_->encoder);
            for (const MicroInstrRegOperandRef& ref : regRefs)
            {
                if (!ref.reg || !ref.reg->isVirtual())
                    continue;
                const uint32_t      denseIndex = denseVirtualIndex(*ref.reg);
                const uint32_t      pos        = ref.def && !ref.use ? idx * 2 + 1 : idx * 2;
                const LiveInterval* node       = locate(denseIndex, pos);
                if (!node || node->spilled || !node->assignedReg.isValid())
                    return false;
            }
        }
    }

    // Every spilled node's value needs its home.
    for (const LiveInterval& node : result.nodes)
    {
        if (node.spilled)
            ensureSpillSlot(states_[node.denseIndex], virtualRegs[node.denseIndex].isAnyFloat());
    }
    for (const Connector& connector : connectors)
    {
        if (!connector.dst.isValid() || !connector.src.isValid())
            ensureSpillSlot(states_[connector.denseIndex], virtualRegs[connector.denseIndex].isAnyFloat());
    }

    // Commit: operand rewrite plus connector insertion, in listing order. A
    // trampoline's moves come before any fall-through connectors sharing the
    // same physical spot: the inverted jcc jumps past the whole trampoline
    // block onto them.
    std::ranges::sort(connectors, [](const Connector& a, const Connector& b) {
        if (a.beforeIndex != b.beforeIndex)
            return a.beforeIndex < b.beforeIndex;
        const bool aTramp = a.trampJump != std::numeric_limits<uint32_t>::max();
        const bool bTramp = b.trampJump != std::numeric_limits<uint32_t>::max();
        if (aTramp != bTramp)
            return aTramp;
        return a.order < b.order;
    });

    const auto trampolineFor = [&](const uint32_t jumpIndex) -> const Trampoline* {
        for (const Trampoline& trampoline : trampolines)
        {
            if (trampoline.jumpIndex == jumpIndex)
                return &trampoline;
        }
        return nullptr;
    };

    size_t   nextConnector = 0;
    uint32_t idx           = 0;
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it, ++idx)
    {
        const MicroInstrRef instructionRef = it.current;

        // A jcc that owns a trampoline is inverted and retargeted to the
        // fresh label closing the trampoline block just below it.
        if (const Trampoline* trampoline = trampolineFor(idx))
        {
            MicroInstrOperand* jccOps = it->ops(*operands_);
            SWC_ASSERT(jccOps);
            jccOps[0].cpuCond  = trampoline->inverted;
            jccOps[2].valueU64 = trampoline->newLabel.get();
        }

        uint32_t openTrampoline = std::numeric_limits<uint32_t>::max();
        for (; nextConnector < connectors.size() && connectors[nextConnector].beforeIndex == idx; ++nextConnector)
        {
            const Connector& connector = connectors[nextConnector];

            if (connector.trampJump != openTrampoline && openTrampoline != std::numeric_limits<uint32_t>::max())
            {
                // Close the trampoline: jump to the original target, then
                // the label the inverted jcc lands on.
                const Trampoline* trampoline = trampolineFor(openTrampoline);
                SWC_ASSERT(trampoline);
                PendingInsert jumpInst;
                jumpInst.op              = MicroInstrOpcode::JumpCond;
                jumpInst.numOps          = 3;
                jumpInst.ops[0].cpuCond  = MicroCond::Unconditional;
                jumpInst.ops[1].opBits   = trampoline->opBits;
                jumpInst.ops[2].valueU64 = trampoline->origTarget;
                insertPending(instructionRef, jumpInst);
                PendingInsert labelInst;
                labelInst.op              = MicroInstrOpcode::Label;
                labelInst.numOps          = 1;
                labelInst.ops[0].valueU64 = trampoline->newLabel.get();
                insertPending(instructionRef, labelInst);
                openTrampoline = std::numeric_limits<uint32_t>::max();
            }
            if (connector.trampJump != std::numeric_limits<uint32_t>::max())
                openTrampoline = connector.trampJump;

            const int64_t depth = depthAt[idx] == std::numeric_limits<int64_t>::min() ? 0 : depthAt[idx];
            if (connector.exchange)
            {
                // An integer pair swaps in one exchange; a float pair in the
                // three bitwise xors, full width whatever the value's own.
                // Neither writes the flags, and the post-RA scans know it.
                if (connector.dst.isFloat())
                {
                    for (uint32_t step = 0; step < 3; ++step)
                    {
                        PendingInsert xorInst;
                        xorInst.op             = MicroInstrOpcode::OpBinaryRegReg;
                        xorInst.numOps         = 4;
                        xorInst.ops[0].reg     = step == 1 ? connector.src : connector.dst;
                        xorInst.ops[1].reg     = step == 1 ? connector.dst : connector.src;
                        xorInst.ops[2].opBits  = MicroOpBits::B64;
                        xorInst.ops[3].microOp = MicroOp::FloatXor;
                        insertPending(instructionRef, xorInst);
                    }
                }
                else
                {
                    PendingInsert exchangeInst;
                    exchangeInst.op             = MicroInstrOpcode::OpBinaryRegReg;
                    exchangeInst.numOps         = 4;
                    exchangeInst.ops[0].reg     = connector.dst;
                    exchangeInst.ops[1].reg     = connector.src;
                    exchangeInst.ops[2].opBits  = MicroOpBits::B64;
                    exchangeInst.ops[3].microOp = MicroOp::Exchange;
                    insertPending(instructionRef, exchangeInst);
                }
                continue;
            }
            if (connector.dst.isValid() && connector.src.isValid() && connector.dst == connector.src)
                continue; // a cycle break left it a no-op
            PendingInsert pendingInst;
            if (connector.dst.isValid() && connector.src.isValid())
            {
                pendingInst.op            = MicroInstrOpcode::LoadRegReg;
                pendingInst.numOps        = 3;
                pendingInst.ops[0].reg    = connector.dst;
                pendingInst.ops[1].reg    = connector.src;
                pendingInst.ops[2].opBits = valueBits(connector.denseIndex);
            }
            else if (connector.dst.isValid())
            {
                queueSpillLoad(pendingInst, connector.dst, states_[connector.denseIndex], depth);
            }
            else
            {
                queueSpillStore(pendingInst, connector.src, states_[connector.denseIndex], depth);
            }
            insertPending(instructionRef, pendingInst);
        }
        if (openTrampoline != std::numeric_limits<uint32_t>::max())
        {
            const Trampoline* trampoline = trampolineFor(openTrampoline);
            SWC_ASSERT(trampoline);
            PendingInsert jumpInst;
            jumpInst.op              = MicroInstrOpcode::JumpCond;
            jumpInst.numOps          = 3;
            jumpInst.ops[0].cpuCond  = MicroCond::Unconditional;
            jumpInst.ops[1].opBits   = trampoline->opBits;
            jumpInst.ops[2].valueU64 = trampoline->origTarget;
            insertPending(instructionRef, jumpInst);
            PendingInsert labelInst;
            labelInst.op              = MicroInstrOpcode::Label;
            labelInst.numOps          = 1;
            labelInst.ops[0].valueU64 = trampoline->newLabel.get();
            insertPending(instructionRef, labelInst);
        }

        SmallVector<MicroInstrRegOperandRef> regRefs;
        it->collectRegOperands(*operands_, regRefs, context_->encoder);
        for (const MicroInstrRegOperandRef& ref : regRefs)
        {
            if (!ref.reg || !ref.reg->isVirtual())
                continue;
            const uint32_t      denseIndex = denseVirtualIndex(*ref.reg);
            const uint32_t      pos        = ref.def && !ref.use ? idx * 2 + 1 : idx * 2;
            const LiveInterval* node       = locate(denseIndex, pos);
            SWC_ASSERT(node && !node->spilled && node->assignedReg.isValid()); // pre-validated
            *ref.reg = node->assignedReg;
        }
    }

    return true;
}

bool MicroRegisterAllocationPass::runIntervalAllocationIfGated()
{
    if (!intervalGateAccepts())
        return false;

    // The walk consults fixed intervals built from concrete claims; the
    // existing scan computes them later (inside assignGlobalRegisters), and
    // the computation is idempotent.
    computeConcreteClaimPositions();

    std::vector<LiveInterval> intervals;
    buildLiveIntervals(intervals);

    IntervalWalkResult result;
    if (!walkIntervals(std::move(intervals), result))
        return false;

    if (!applyIntervalAllocation(result))
        return false;

    // What the later sweeps need from the first: the registers a scratch may
    // borrow around when nothing is free, and the debug local-stack base.
    context_->intervalAllocated  = true;
    context_->globalReservedRegs = result.poolRegs;
    if (result.debugStackBasePhys.isValid())
        context_->debugStackBasePhysReg = result.debugStackBasePhys;

    context_->passChanged = true;
    return true;
}

SWC_END_NAMESPACE();
