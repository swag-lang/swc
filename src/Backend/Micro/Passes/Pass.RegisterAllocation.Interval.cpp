#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Support/Core/DenseBits.h"

// compiler.optimization.024: the interval-splitting linear scan of Wimmer & Mössenböck (VEE 2005,
// the allocator of HotSpot's client compiler), as a second allocation path the
// pass selects per function, with the existing scan as the always-available
// fallback. This file owns everything interval-shaped; the walk mutates
// nothing until it has fully succeeded, so a bail at any point falls back to
// the existing allocator with the function untouched.

SWC_BEGIN_NAMESPACE();

bool MicroRegisterAllocationPass::intervalAllocationAccepts() const
{
    if (!context_ || !context_->builder || !context_->isFirstAllocationSweep)
        return false;

    // Which allocator a function gets is the optimization level's decision, and
    // the level alone: `-O0` keeps the scan below, every level above it splits.
    const Runtime::BuildCfgBackend& backendCfg = context_->builder->backendBuildCfg();
    if (!backendCfg.splitsLiveRanges())
        return false;
    // The same CFG precision the write-back protocol needs: every edge into
    // every block known. keepAcrossBoundaries_ is not computed yet at this
    // point, so the condition is tested directly.
    return controlFlowGraph_ != nullptr &&
           !controlFlowGraph_->hasUnsupportedControlFlowForCfgLiveness() &&
           controlFlowGraph_->supportsDeadCodeLiveness();
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
    out.clear();
    out.resize(virtualCount);

    const uint32_t wordCount = denseVirtualRegs_.wordCount();

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
        // A plain copy has one definition and one use. Liveness already
        // resolved their dense indices before interval construction.
        SWC_ASSERT(defVirtualIndices_[idx].size() == 1);
        LiveInterval& dst = out[defVirtualIndices_[idx].front()];
        if (ops[1].reg.isVirtual())
        {
            SWC_ASSERT(useVirtualIndices_[idx].size() == 1);
            if (dst.hintDense == std::numeric_limits<uint32_t>::max())
                dst.hintDense = useVirtualIndices_[idx].front();
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

        const uint32_t wordIndex = denseIndex >> 6u;
        const uint64_t bitMask   = 1ull << (denseIndex & 63u);

        size_t   useCursor = 0;
        size_t   defCursor = 0;
        bool     open      = false;
        uint32_t openFrom  = 0;
        bool     liveIn    = (liveInVirtualBits_[static_cast<size_t>(spanLo) * wordCount + wordIndex] & bitMask) != 0;

        for (uint32_t idx = spanLo; idx <= spanHi; ++idx)
        {
            // Event positions are unique, ordered, and included in this span.
            const bool usedHere = useCursor < interval.usePositions.size() && interval.usePositions[useCursor] == idx * 2;
            if (usedHere)
                ++useCursor;
            const bool definedHere = defCursor < interval.defPositions.size() && interval.defPositions[defCursor] == idx * 2 + 1;
            if (definedHere)
                ++defCursor;

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
            // Live into the next instruction keeps the range open across the
            // gap; otherwise it closes at the last slot this instruction
            // holds the value.
            const bool liveNext = idx + 1 < instructionCount_ &&
                                  (liveInVirtualBits_[static_cast<size_t>(idx + 1) * wordCount + wordIndex] & bitMask) != 0;
            if (open && !liveNext)
            {
                const uint32_t to = definedHere ? idx * 2 + 2 : idx * 2 + 1;
                interval.ranges.push_back({openFrom, to});
                open = false;
            }
            liveIn = liveNext;
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
    // writes at output slots both name a register. Build and split preserve
    // the sorted event lists, so repeated elections need not rescan their prefix.
    const auto     use     = std::ranges::lower_bound(usePositions, pos);
    const auto     def     = std::ranges::lower_bound(defPositions, pos);
    const uint32_t nextUse = use == usePositions.end() ? std::numeric_limits<uint32_t>::max() : *use;
    const uint32_t nextDef = def == defPositions.end() ? std::numeric_limits<uint32_t>::max() : *def;
    return std::min(nextUse, nextDef);
}

uint32_t MicroRegisterAllocationPass::LiveInterval::lastAccessBefore(const uint32_t pos) const
{
    const auto use = std::ranges::lower_bound(usePositions, pos);
    const auto def = std::ranges::lower_bound(defPositions, pos);
    if (use == usePositions.begin())
        return def == defPositions.begin() ? std::numeric_limits<uint32_t>::max() : *(def - 1);
    if (def == defPositions.begin())
        return *(use - 1);
    return std::max(*(use - 1), *(def - 1));
}

uint32_t MicroRegisterAllocationPass::LiveInterval::firstRangeStartAfter(const uint32_t pos) const
{
    const auto range = std::ranges::lower_bound(ranges, pos, {}, &IntervalRange::from);
    return range == ranges.end() ? std::numeric_limits<uint32_t>::max() : range->from;
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
    const MicroReg excludedBase = context_->debugStackBaseVirtualReg.isValid() || context_->keepLocalStackBase ? conv_->preferredLocalStackBaseReg() : MicroReg::invalid();

    const auto admit = [&](const MicroReg reg) {
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

    // A definition-only claim starts when the result is produced. This includes
    // MUL's RDX output: its dying source may occupy RDX at the input slot. RAX,
    // division's RDX and shift counts still read their fixed register and keep
    // their full claim. Liveness likewise keeps every carried value protected.
    const auto definesAtOutput = [&](const uint32_t idx) {
        const MicroInstr* inst = instructions_->ptr(controlFlowGraph_->instructionRefs()[idx]);
        return inst && MicroInstrInfo::registerDefsAtOutput(*inst);
    };

    outByPoolIndex.clear();
    outByPoolIndex.resize(outPoolRegs.size());
    const uint32_t concreteWordCount = denseConcreteRegs_.wordCount();
    for (size_t poolIndex = 0; poolIndex < outPoolRegs.size(); ++poolIndex)
    {
        const uint32_t denseConcrete = denseConcreteRegs_.find(outPoolRegs[poolIndex]);
        if (denseConcrete == MicroDenseRegIndex::K_INVALID_INDEX)
            continue;

        const uint32_t wordIndex = denseConcrete >> 6u;
        const uint64_t bitMask   = 1ull << (denseConcrete & 63u);

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
            const bool usedHere    = std::ranges::find(useConcreteIndices_[idx], denseConcrete) != useConcreteIndices_[idx].end();
            const bool definedHere = std::ranges::find(defConcreteIndices_[idx], denseConcrete) != defConcreteIndices_[idx].end();
            const bool liveInHere  = (liveInConcreteBits_[static_cast<size_t>(idx) * concreteWordCount + wordIndex] & bitMask) != 0;
            const bool definedOnly = definedHere && !usedHere && !liveInHere && definesAtOutput(idx);

            // A call the straight-line path steps over clobbers nothing the hot path has to
            // give up. A value may keep its caller-saved register across it and be parked in
            // its home for the call's duration (walkIntervals), so the cold block pays the
            // traffic. The registers the call reads and the one it hands back stay claims:
            // those are named at the call or read right after it.
            if (definedOnly && isGuardedCall(idx))
                continue;

            // A dying physical copy source is needed only at the input slot.
            // Its virtual destination can occupy that register at the output slot.
            bool copiedLastUse = false;
            if (usedHere && !definedHere)
            {
                const MicroInstr* inst = instructions_->ptr(controlFlowGraph_->instructionRefs()[idx]);
                if (inst && inst->op == MicroInstrOpcode::LoadRegReg)
                {
                    const MicroInstrOperand* ops = inst->ops(*operands_);
                    copiedLastUse                = ops[0].reg.isVirtualInt() && ops[1].reg == outPoolRegs[poolIndex] && ops[2].opBits == MicroOpBits::B64;
                    if (copiedLastUse)
                    {
                        for (const uint32_t successor : controlFlowGraph_->successors(idx))
                        {
                            if (liveInConcreteBits_[static_cast<size_t>(successor) * concreteWordCount + wordIndex] & bitMask)
                            {
                                copiedLastUse = false;
                                break;
                            }
                        }
                    }
                }
            }

            const uint32_t from = definedOnly ? idx * 2 + 1 : idx * 2;
            const uint32_t to   = copiedLastUse ? idx * 2 + 1 : idx * 2 + 2;
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
        for (uint32_t idx = hiIdx; idx > loIdx && bestDepth != 0; --idx)
        {
            if (depth[idx - 1] < bestDepth)
            {
                bestIdx   = idx - 1;
                bestDepth = depth[idx - 1];
            }
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
    // keeps everything before, the child takes everything from `pos` on.
    // The caller queues children that compete for a register; a spilled child
    // stays out of the queue. Returns K_IV_INVALID when the split is impossible.
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
            const auto keep = static_cast<size_t>(std::ranges::lower_bound(fromList, pos) - fromList.begin());
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
        return childIndex;
    }

    // Cuts node `nodeIndex` at `pos`: the head keeps everything before, a new node takes
    // everything from `pos` on and inherits the register. Nothing is queued - the walk is over
    // when this runs, and the caller decides what the child holds.
    uint32_t cutNodeAt(std::vector<MicroRegisterAllocationPass::LiveInterval>& nodes, const uint32_t nodeIndex, const uint32_t pos)
    {
        if (pos <= nodes[nodeIndex].start() || pos >= nodes[nodeIndex].end())
            return K_IV_INVALID;

        MicroRegisterAllocationPass::LiveInterval child;
        child.denseIndex  = nodes[nodeIndex].denseIndex;
        child.assignedReg = nodes[nodeIndex].assignedReg;
        child.hintPhys    = nodes[nodeIndex].assignedReg;

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
            return K_IV_INVALID;

        const auto moveTail = [pos](auto& fromList, auto& toList) {
            const auto keep = static_cast<size_t>(std::ranges::lower_bound(fromList, pos) - fromList.begin());
            toList.append(fromList.begin() + static_cast<ptrdiff_t>(keep),
                          static_cast<uint32_t>(fromList.size() - keep));
            fromList.resize(keep);
        };
        moveTail(parent.usePositions, child.usePositions);
        moveTail(parent.defPositions, child.defPositions);

        nodes.push_back(std::move(child));
        return static_cast<uint32_t>(nodes.size() - 1);
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
        SWC_ASSERT((from & 1u) == 0);
        uint32_t next = node.firstUseAfter(from);
        // Elections start at input slots. An enclosing loop's even tail
        // cannot precede an access already at this input.
        if (next == from || !walk.loops)
            return next;
        uint32_t lastAccess = K_IV_INVALID;
        for (const LoopRange& loop : *walk.loops)
        {
            const uint32_t headPos = loop.head * 2;
            const uint32_t tailPos = loop.tail * 2;
            if (from < headPos || from > tailPos + 1 || tailPos >= next)
                continue;
            if (!node.covers(headPos) || !node.covers(tailPos))
                continue;
            // All enclosing loops ask about the same interval and position.
            // Resolve its previous access only when one loop needs it.
            if (lastAccess == K_IV_INVALID)
            {
                lastAccess = node.lastAccessBefore(from);
                if (lastAccess == K_IV_INVALID)
                    return next;
            }
            if (lastAccess < headPos)
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
        if (splitPos <= nodes[ownerIndex].start() || splitPos >= nodes[ownerIndex].end())
            return false;
        // The next access rules out both this instruction's input and output
        // slots. A separate backward search for an input-slot access repeats
        // a case already rejected by the same rounded-forward boundary.
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
        if (splitPos <= nodes[ownerIndex].start())
            return false;
        const uint32_t lastUse = nodes[ownerIndex].lastAccessBefore(splitPos + 1);
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

            // This child carries in memory. Only the part from its next access
            // on competes for a register again, so only that later split queues.
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
                // A request born at an instruction's output slot may spill its
                // owner at that instruction's input. Requeueing the reload at
                // that earlier input would move the walk backward and could
                // assign a still-live input value's register to the reload.
                const uint32_t earliestReload = (pos & 1u) ? pos + 1 : splitPos;
                const uint32_t reloadPos      = chooseSplitPos(walk, std::max(nodes[spilledIndex].start() + 1, earliestReload), firstAccess);
                const uint32_t reloadIndex    = splitNodeAt(walk, spilledIndex, reloadPos);
                ok                            = reloadIndex != K_IV_INVALID;
                if (ok)
                    pushUnhandled(walk, reloadIndex);
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
    buildFixedIntervals(fixed, out.poolRegs);
    const auto& poolRegs = out.poolRegs;

    out.nodes = std::move(intervals);

    // The loops, from the back-edges of the instruction CFG, for the
    // election's view of a loop-carried access.
    std::vector<LoopRange> loops;
    if (hasControlFlow_ && functionHasLoop_)
    {
        SWC_ASSERT(predecessors_.size() == instructionCount_);
        for (uint32_t s = 0; s < instructionCount_; ++s)
        {
            for (const uint32_t p : predecessors_[s])
            {
                SWC_ASSERT(p < instructionCount_);
                if (p >= s)
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
            walk.unhandled.push_back(nodeIndex);
    }
    // Repeated ordered insertion shifts the initial queue for every interval.
    // Dense-index ties preserve the order upper_bound gave those insertions.
    std::ranges::sort(walk.unhandled, [&](const uint32_t a, const uint32_t b) {
        const uint32_t startA = out.nodes[a].start();
        const uint32_t startB = out.nodes[b].start();
        return startA != startB ? startA > startB : a < b;
    });

    SmallVector<uint32_t, 32> electionPositions(poolCount);
    const auto&               forbiddenRegsByVirtual = context_->builder->virtualRegForbiddenPhysRegs();

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
        const auto forbiddenRegs       = forbiddenRegsByVirtual.find(currentVirtual);
        const auto forbiddenForCurrent = [&](const size_t poolIndex) {
            return forbiddenRegs != forbiddenRegsByVirtual.end() && microRegSpanContains(forbiddenRegs->second.span(), poolRegs[poolIndex]);
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
        auto& freeUntilPos = electionPositions;
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
        if (bestFree < poolCount)
        {
            MicroReg hint = out.nodes[currentIndex].hintPhys;
            if (!hint.isValid() && out.nodes[currentIndex].hintDense != std::numeric_limits<uint32_t>::max())
            {
                const uint32_t      at        = out.nodes[currentIndex].start() & ~1u;
                const uint32_t      hintDense = out.nodes[currentIndex].hintDense;
                const LiveInterval& root      = out.nodes[hintDense];
                if (!root.spilled && root.assignedReg.isValid() && root.covers(at))
                {
                    hint = root.assignedReg;
                }
                else
                {
                    // Original intervals have their dense register's index. Only
                    // appended split children can hold another piece of this value.
                    for (size_t otherIndex = denseVirtualRegs_.regs().size(); otherIndex < out.nodes.size(); ++otherIndex)
                    {
                        const LiveInterval& other = out.nodes[otherIndex];
                        if (other.denseIndex == hintDense && !other.spilled && other.assignedReg.isValid() && other.covers(at))
                        {
                            hint = other.assignedReg;
                            break;
                        }
                    }
                }
            }
            if (hint.isValid())
            {
                const size_t hintIdx = poolIndexOf(hint);
                if (hintIdx < poolCount && freeUntilPos[hintIdx] &&
                    (freeUntilPos[hintIdx] >= out.nodes[currentIndex].end() ||
                     freeUntilPos[hintIdx] >= freeUntilPos[bestFree]))
                    bestFree = hintIdx;
            }
        }

        // A free register that ends at a call can split a loop value at the
        // call even when a less-used value occupies a persistent register.
        // Try the blocked election first in that case; retain the partial
        // free register as a fallback when no owner can be displaced.
        const uint32_t bestFreeUntil   = bestFree < poolCount ? freeUntilPos[bestFree] : 0;
        const bool     freeServesWhole = bestFree < poolCount && bestFreeUntil >= out.nodes[currentIndex].end();
        const bool     freeSplittable  = bestFree < poolCount && (bestFreeUntil & ~1u) > position;
        bool           freeEndsAtCall  = false;
        if (freeSplittable && !freeServesWhole && !fixed[bestFree].ranges.empty())
        {
            const uint32_t    blockIndex = bestFreeUntil / 2;
            const MicroInstr* blockInst  = instructions_->ptr(controlFlowGraph_->instructionRefs()[blockIndex]);
            freeEndsAtCall               = blockInst && MicroInstr::info(blockInst->op).flags.has(MicroInstrFlagsE::IsCallInstruction) &&
                             fixed[bestFree].nextIntersection(out.nodes[currentIndex], position) == bestFreeUntil;
        }
        const auto allocateFree = [&] {
            out.nodes[currentIndex].assignedReg = poolRegs[bestFree];
            if (bestFreeUntil < out.nodes[currentIndex].end())
            {
                const uint32_t splitPos   = chooseSplitPos(walk, position + 1, bestFreeUntil);
                const uint32_t childIndex = splitNodeAt(walk, currentIndex, splitPos);
                if (childIndex != K_IV_INVALID)
                    pushUnhandled(walk, childIndex);
                else if (!walk.failed)
                {
                    walk.failed     = true;
                    walk.failReason = "free-reg split landed outside the interval";
                }
            }
            walk.active.push_back(currentIndex);
        };
        if (freeServesWhole || (freeSplittable && !freeEndsAtCall))
        {
            allocateFree();
            continue;
        }

        // allocateBlockedReg. Owners are measured from the instruction's
        // INPUT slot: an owner the very same instruction still reads must
        // never win the election, since its register cannot be vacated
        // between the read and the write.
        // This phase overwrites every position. The fallback retains its chosen
        // free boundary in bestFreeUntil even when a candidate is disqualified.
        auto&          nextUsePos   = electionPositions;
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
                if (out.nodes[activeIndex].assignedReg == poolRegs[best] &&
                    !canSplitAndSpillOwner(walk, activeIndex, position))
                {
                    feasible = false;
                    break;
                }
            }
            if (feasible)
            {
                for (const uint32_t inactiveIndex : walk.inactive)
                {
                    if (out.nodes[inactiveIndex].assignedReg != poolRegs[best])
                        continue;
                    const uint32_t intersection = out.nodes[inactiveIndex].nextIntersection(out.nodes[currentIndex], position);
                    if (intersection != std::numeric_limits<uint32_t>::max() &&
                        !canSplitAndSpillOwner(walk, inactiveIndex, intersection))
                    {
                        feasible = false;
                        break;
                    }
                }
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
            if (freeSplittable)
            {
                allocateFree();
                continue;
            }
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
                const uint32_t reloadPos   = chooseSplitPos(walk, out.nodes[currentIndex].start() + 1, currentFirstUse);
                const uint32_t reloadIndex = splitNodeAt(walk, currentIndex, reloadPos);
                if (reloadIndex != K_IV_INVALID)
                    pushUnhandled(walk, reloadIndex);
                else if (!walk.failed)
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
                const uint32_t childIndex = splitNodeAt(walk, currentIndex, chooseSplitPos(walk, position + 1, fixedClash));
                if (childIndex != K_IV_INVALID)
                    pushUnhandled(walk, childIndex);
                else if (!walk.failed)
                {
                    walk.failed     = true;
                    walk.failReason = "cannot split before a fixed clash";
                }
            }
        }
        if (!walk.failed)
            walk.active.push_back(currentIndex);
    }

    // A value holding a caller-saved register across a call the hot path steps over is parked:
    // its node is cut into a register head, a memory-resident middle spanning the call, and a
    // register tail in the same register. The adjacent-node connector stores the head before
    // the call, and the edge resolution reloads the tail before the join on the fall-through
    // side alone - the side that made the call - while the jump that steps over the block
    // finds the value where it left it. A value the call itself reads keeps its register up to
    // the call's input, so the head ends at the output slot.
    if (!walk.failed && hasControlFlow_)
    {
        for (uint32_t idx = 0; idx + 1 < instructionCount_ && !walk.failed; ++idx)
        {
            if (!isGuardedCall(idx))
                continue;
            const auto&    clobbers = instructionUseDefs_[idx].defs;
            const uint32_t callIn   = idx * 2;
            const uint32_t callOut  = idx * 2 + 1;
            const uint32_t after    = idx * 2 + 2;
            for (size_t n = 0; n < out.nodes.size(); ++n)
            {
                const LiveInterval& node = out.nodes[n];
                // The register must hold the value past the call's output slot: a node that ends
                // there dies at the call's input, one that hands over right after the call still
                // expects its register to carry the value across it.
                if (node.spilled || !node.assignedReg.isValid() || !node.covers(callIn) || node.end() <= callOut)
                    continue;
                if (std::ranges::find(clobbers, node.assignedReg) == clobbers.end())
                    continue;

                // A value that reaches this call in memory - parked at the call just before it,
                // or due for a reload here - stays there through this call as well, and the tail
                // reloads it once after. Cutting a head off would order its store after the
                // reload at the same point and park the clobbered register instead.
                uint32_t middleIndex = static_cast<uint32_t>(n);
                if (node.start() != callIn)
                {
                    middleIndex = cutNodeAt(out.nodes, static_cast<uint32_t>(n), callOut);
                    if (middleIndex == K_IV_INVALID)
                    {
                        walk.failed     = true;
                        walk.failReason = "cannot park a value across a guarded call";
                        break;
                    }
                }

                // The tail keeps the register from the instruction after the call on; a node that
                // hands over exactly there has none, and the handover reads the home instead.
                if (out.nodes[middleIndex].end() > after && cutNodeAt(out.nodes, middleIndex, after) == K_IV_INVALID)
                {
                    walk.failed     = true;
                    walk.failReason = "cannot park a value across a guarded call";
                    break;
                }

                out.nodes[middleIndex].spilled     = true;
                out.nodes[middleIndex].assignedReg = MicroReg::invalid();
                ++out.parkCount;
            }
        }
    }

    out.splitCount = walk.splitCount;
    out.spillCount = walk.spillCount;

    if (walk.failed)
        return false;

    const size_t virtualCount = denseVirtualRegs_.regs().size();
    // The initial nodes are already in dense-value order. Only a split (or a
    // parked call range) appends nodes and requires regrouping them.
    if (out.nodes.size() == virtualCount)
    {
        out.valueNodesBegin.resize(virtualCount + 1);
        for (uint32_t i = 0; i <= virtualCount; ++i)
            out.valueNodesBegin[i] = i;
        return true;
    }

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
    // Splitting retains an initial node for every dense value. Sorted groups therefore visit
    // every dense index in order, and its offset fits in the already-consumed prefix of order.
    // Reuse that prefix so the group table need not coexist with both node arrays.
    uint32_t nextDenseIndex = 0;
    for (uint32_t position = 0; position < order.size(); ++position)
    {
        LiveInterval& node = out.nodes[order[position]];
        if (node.denseIndex == nextDenseIndex)
        {
            SWC_ASSERT(nextDenseIndex <= position);
            order[nextDenseIndex++] = position;
        }
        sorted.push_back(std::move(node));
    }
    SWC_ASSERT(nextDenseIndex == virtualCount && virtualCount < order.size());
    order[virtualCount] = static_cast<uint32_t>(sorted.size());

    out.nodes = std::move(sorted);
    out.valueNodesBegin.assign(order.begin(), order.begin() + static_cast<ptrdiff_t>(virtualCount + 1));

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
    SWC_ASSERT(predecessors_.size() == instructionCount_);

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
                SWC_ASSERT(succ < instructionCount_);
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
        uint32_t            beforeIndex = 0;
        uint32_t            order       = 0; // parallel-copy order within the point
        MicroReg            dst;             // invalid => store to home
        MicroReg            src;             // invalid => load from home
        uint32_t            denseIndex = 0;
        uint32_t            trampJump  = std::numeric_limits<uint32_t>::max();
        bool                exchange   = false;   // swap dst and src: the head of a copy cycle
        const LiveInterval* from       = nullptr; // the register node a register move reads
        // Two kinds of connector meet at one point. A split connector (and a
        // spill store placed after a definition) realizes the location the
        // value takes at the instruction's input; an edge connector then
        // reads that input state to reconcile it with the successor's. The
        // parallel-copy order holds within a phase only: an edge move that
        // reads the register a split reload writes at the same point must
        // read the RELOADED value, not the one the register held before.
        uint8_t phase = 0; // 0: split or definition store, 1: edge
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
                                  const LiveInterval* fromNode, const LiveInterval* toNode, const uint8_t phase) {
        const MicroReg fromReg = (fromNode && !fromNode->spilled) ? fromNode->assignedReg : MicroReg::invalid();
        const MicroReg toReg   = (toNode && !toNode->spilled) ? toNode->assignedReg : MicroReg::invalid();
        if (fromReg == toReg)
            return; // same register, or memory-to-memory
        if (!fromReg.isValid() && !toReg.isValid())
            return;
        Connector& connector  = connectors.emplace_back();
        connector.beforeIndex = beforeIndex;
        connector.dst         = toReg;
        connector.src         = fromReg;
        connector.denseIndex  = denseIndex;
        connector.from        = fromReg.isValid() && toReg.isValid() ? fromNode : nullptr;
        connector.phase       = phase;
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
            addConnector(beforeIndex, denseIndex, &a, &b, 0);
        }
    }

    // Edge connectors. For each label, each predecessor edge reconciles the
    // location at the predecessor's end with the location at the label.
    struct EdgeMove
    {
        uint32_t            denseIndex = 0;
        const LiveInterval* from       = nullptr;
        const LiveInterval* to         = nullptr;
    };
    SmallVector<EdgeMove, 8> edgeMoves;
    const uint32_t           wordCount = denseVirtualRegs_.wordCount();
    // Without split children every value has one location across all edges.
    const uint32_t edgeInstructionCount = result.nodes.size() == virtualCount ? 0 : instructionCount_;
    for (uint32_t s = 0; s < edgeInstructionCount; ++s)
    {
        const MicroInstr* labelInst = instructions_->ptr(controlFlowGraph_->instructionRefs()[s]);
        if (!labelInst || labelInst->op != MicroInstrOpcode::Label)
            continue;
        const std::span<const uint64_t> liveRow = DenseBits::row(liveInVirtualBits_, s, wordCount);
        for (const uint32_t p : predecessors_[s])
        {
            SWC_ASSERT(p < instructionCount_);
            const MicroInstr* predInst = instructions_->ptr(controlFlowGraph_->instructionRefs()[p]);
            if (!predInst)
                return false;

            const bool isJump = MicroInstr::info(predInst->op).flags.has(MicroInstrFlagsE::JumpInstruction);
            // Where the edge leaves the predecessor. The edge leaves at the
            // jump's INPUT slot: a value dead on the jump's other side closes
            // its range at p*2+1 exclusive, so the output slot may sit in a
            // hole even though the value crosses this edge. A fall-through
            // predecessor is an ordinary instruction that may define the
            // value, so its end state is the output slot.
            const uint32_t predEndPos = isJump ? p * 2 : p * 2 + 1;

            // Collect this edge's moves first; placement is decided for the
            // edge as a whole.
            edgeMoves.clear();

            for (size_t wordIndex = 0; wordIndex < liveRow.size(); ++wordIndex)
            {
                uint64_t wordBits = liveRow[wordIndex];
                while (wordBits)
                {
                    const auto denseIndex = static_cast<uint32_t>(wordIndex * 64ull + std::countr_zero(wordBits));
                    wordBits &= wordBits - 1ull;
                    SWC_ASSERT(denseIndex < virtualCount);

                    // An unsplit value can only stay in its one node or
                    // be absent on one side; neither case needs a move.
                    if (result.valueNodesBegin[denseIndex + 1] == result.valueNodesBegin[denseIndex] + 1)
                        continue;
                    const LiveInterval* atLabel = locate(denseIndex, s * 2);
                    if (!atLabel)
                        continue;
                    const LiveInterval* atPred = locate(denseIndex, predEndPos);
                    if (!atPred || atLabel == atPred)
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

            // Conditionality lives in the operand, not the opcode: an
            // unconditional jump is a JumpCond carrying Unconditional, and it
            // has no fall-through side to protect.
            const MicroInstrOperand* predOpsEarly  = predInst->ops(*operands_);
            const bool               isConditional = MicroInstr::info(predInst->op).flags.has(MicroInstrFlagsE::ConditionalJump) &&
                                       predOpsEarly && predOpsEarly[0].cpuCond != MicroCond::Unconditional;

            // A conditional jump falls through to the label right after it:
            // that edge is its not-taken side, and its moves belong before the
            // label, on that side alone. Placed before the jump, or in the
            // taken edge's trampoline, they would run where the jump goes
            // instead. Only a jump to that very label reaches it both ways.
            const MicroInstrOperand* labelOps        = labelInst->ops(*operands_);
            const bool               jumpsToLabel    = isConditional && predOpsEarly && labelOps && predOpsEarly[2].valueU64 == labelOps[0].valueU64;
            const bool               fallThroughPred = p + 1 == s && (!MicroInstrInfo::isTerminatorInstruction(*predInst) || (isConditional && !jumpsToLabel));

            // The insertion point: before the label for the fall-through
            // edge (jumps land past it), before the jump otherwise.
            const uint32_t beforeIndex = fallThroughPred ? s : p;

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
                const bool     checkFallThrough = isConditional && p + 1 < instructionCount_;
                const uint32_t claimEnd         = checkFallThrough ? p + 1 : p;
                for (const EdgeMove& move : edgeMoves)
                {
                    const MicroReg toReg = move.to->spilled ? MicroReg::invalid() : move.to->assignedReg;
                    if (!toReg.isValid())
                        continue;
                    // One range query covers the adjacent branch and fall-through positions.
                    if (containsKey(instructionUseDefs_[p].uses, toReg) || concreteClaimsOverlap(toReg, p, claimEnd))
                    {
                        plainOk = false;
                        break;
                    }
                    if (checkFallThrough)
                    {
                        // The write runs on the fall-through side too: any
                        // OTHER value holding that register there, or this
                        // value expecting it from a different source, kills
                        // the plain placement.
                        //
                        // Holding it *at the branch* counts as much as holding
                        // it after: a value the fall-through side keeps in
                        // memory is put there by a store that reads the
                        // register it still occupies here, and that store is
                        // emitted after this branch. Writing the register
                        // first would store the wrong value - which is what
                        // sent an MP4 sample table through the wrong bounds.
                        // Input-slot coverage comes from live-in. Values absent
                        // from this row cannot own the fall-through register.
                        const auto fallThroughLive = DenseBits::row(liveInVirtualBits_, p + 1, wordCount);
                        for (size_t wordIndex = 0; plainOk && wordIndex < fallThroughLive.size(); ++wordIndex)
                        {
                            uint64_t wordBits = fallThroughLive[wordIndex];
                            while (plainOk && wordBits)
                            {
                                const auto other = static_cast<uint32_t>(wordIndex * 64ull + std::countr_zero(wordBits));
                                wordBits &= wordBits - 1ull;
                                if (other == move.denseIndex)
                                    continue;
                                const LiveInterval* node = locate(other, p * 2 + 2);
                                if (!node)
                                    continue;
                                if (!node->spilled && node->assignedReg == toReg)
                                {
                                    plainOk = false;
                                    break;
                                }
                                const LiveInterval* atBranch = locate(other, predEndPos);
                                if (atBranch && !atBranch->spilled && atBranch->assignedReg == toReg)
                                    plainOk = false;
                            }
                        }
                        if (!plainOk)
                            break;
                        const LiveInterval* ownFall = locate(move.denseIndex, p * 2 + 2);
                        if (ownFall && !ownFall->spilled && ownFall->assignedReg == toReg && ownFall != move.from &&
                            (move.from->spilled || ownFall->assignedReg != move.from->assignedReg))
                            plainOk = false;
                    }
                    if (!plainOk)
                        break;
                }
            }

            // The moves belong to the taken edge alone, but the plain spot sits
            // before the jump, where the fall-through path executes them too.
            // That is pure waste on the hot side of a branch: an edge that
            // leaves a loop pays it on every iteration, and an in-loop edge
            // with several moves pays several dead stores per pass. Prefer the
            // trampoline for both whenever the branch can be inverted, and
            // keep the plain spot when it cannot.
            bool useTrampoline = !plainOk;
            if (plainOk && isConditional && !fallThroughPred &&
                ((!loopDepth_.empty() && loopDepth_[p] > loopDepth_[s]) || edgeMoves.size() >= 2))
                useTrampoline = true;

            uint32_t trampJump = std::numeric_limits<uint32_t>::max();
            if (useTrampoline)
            {
                MicroCond                inverted = MicroCond::Unconditional;
                const MicroInstrOperand* predOps  = predInst->ops(*operands_);
                if (!isConditional || !predOps || !MicroPassHelpers::invertLayoutBranchCondition(inverted, predOps[0].cpuCond))
                {
                    if (!plainOk)
                        return false; // uninvertible edge
                    useTrampoline = false;
                }
                else
                {
                    Trampoline& trampoline = trampolines.emplace_back();
                    trampoline.jumpIndex   = p;
                    trampoline.inverted    = inverted;
                    trampoline.opBits      = predOps[1].opBits;
                    trampoline.origTarget  = predOps[2].valueU64;
                    trampoline.newLabel    = context_->builder->createLabel();
                    trampJump              = p;
                }
            }

            for (const EdgeMove& move : edgeMoves)
            {
                const size_t before = connectors.size();
                addConnector(useTrampoline ? p + 1 : beforeIndex, move.denseIndex, move.from, move.to, 1);
                if (connectors.size() != before)
                    connectors.back().trampJump = trampJump;
            }
        }
    }

    // Rematerialization. A value with one definition that is an immediate,
    // a cleared register or a relocated address is never given a home: its
    // reloads remake the definition where they stand, exactly as the existing
    // scan and LLVM's InlineSpiller do, and every store of it goes. An
    // integer zero is remade as a mov, not a clear: the clear writes the
    // flags, and a connector may sit between a compare and its branch.
    struct RematRecipe
    {
        MicroInstrOpcode  op = MicroInstrOpcode::Nop;
        MicroInstrOperand immediate;
        MicroOpBits       bits = MicroOpBits::B64;
        MicroRelocation   relocation;
        bool              relocated = false;
        bool              valid     = false;
        // The defining instruction, and whether it is dead once the value is
        // only ever remade: its register node has no use and no move reads it.
        uint32_t defIndex = std::numeric_limits<uint32_t>::max();
        bool     defDead  = false;
    };
    std::vector<RematRecipe> remat(virtualCount);
    {
        std::optional<std::unordered_map<uint32_t, const MicroRelocation*>> relocationByInstruction;
        // Only relocation-backed rematerializations need this function-wide index.
        const auto findRelocation = [&](const MicroInstrRef ref) -> const MicroRelocation* {
            if (!relocationByInstruction)
            {
                relocationByInstruction.emplace();
                for (const MicroRelocation& relocation : context_->builder->codeRelocations())
                {
                    if (relocation.instructionRef.isValid())
                        (*relocationByInstruction)[relocation.instructionRef.get()] = &relocation;
                }
            }
            const auto found = relocationByInstruction->find(ref.get());
            return found == relocationByInstruction->end() ? nullptr : found->second;
        };
        for (uint32_t denseIndex = 0; denseIndex < virtualCount; ++denseIndex)
        {
            if (definitionCounts_[denseIndex] != 1)
                continue;
            const uint32_t first = result.valueNodesBegin[denseIndex];
            const uint32_t last  = result.valueNodesBegin[denseIndex + 1];
            // A used value kept in one register needs neither a remade load
            // nor a dead-definition proof. No connector can read this node.
            if (last == first + 1 && !result.nodes[first].spilled && !result.nodes[first].usePositions.empty())
                continue;
            RematRecipe& recipe = remat[denseIndex];
            // Index definitions only when a value needs a recipe. Every candidate has one
            // definition, so filling the table once also clears every later candidate's sentinel.
            if (recipe.defIndex == invalid)
            {
                for (uint32_t idx = 0; idx < instructionCount_; ++idx)
                {
                    for (const uint32_t definedDenseIndex : defVirtualIndices_[idx])
                        remat[definedDenseIndex].defIndex = idx;
                }
            }
            const MicroInstrRef      defRef = controlFlowGraph_->instructionRefs()[recipe.defIndex];
            const MicroInstr*        inst   = instructions_->ptr(defRef);
            const MicroInstrOperand* ops    = inst ? inst->ops(*operands_) : nullptr;
            if (!ops || ops[0].reg != virtualRegs[denseIndex])
                continue;
            switch (inst->op)
            {
                case MicroInstrOpcode::LoadRegImm:
                    if (ops[2].hasWideImmediateValue())
                        break;
                    recipe.op        = MicroInstrOpcode::LoadRegImm;
                    recipe.immediate = ops[2];
                    recipe.bits      = ops[1].opBits;
                    recipe.valid     = true;
                    break;
                case MicroInstrOpcode::ClearReg:
                    recipe.bits = ops[1].opBits;
                    if (virtualRegs[denseIndex].isAnyFloat())
                    {
                        recipe.op = MicroInstrOpcode::ClearReg;
                    }
                    else
                    {
                        recipe.op = MicroInstrOpcode::LoadRegImm;
                        recipe.immediate.setImmediateValue(ApInt(0, getNumBits(recipe.bits)));
                    }
                    recipe.valid = true;
                    break;
                case MicroInstrOpcode::LoadRegPtrReloc:
                {
                    const MicroRelocation* relocation = findRelocation(defRef);
                    if (!relocation)
                        break;
                    recipe.op         = MicroInstrOpcode::LoadRegPtrReloc;
                    recipe.immediate  = ops[2];
                    recipe.bits       = ops[1].opBits;
                    recipe.relocation = *relocation;
                    recipe.relocated  = true;
                    recipe.valid      = true;
                    break;
                }
                case MicroInstrOpcode::LoadRegMem:
                {
                    // A read of the constant pool, reached from the
                    // instruction pointer: it depends on no register and the
                    // bytes never change, so remaking it costs one
                    // instruction where a spill costs a store and a load. A
                    // global is written, so only a constant qualifies.
                    // ops: [0] dst, [1] base, [2] opBits, [3] offset
                    if (!ops[1].reg.isInstructionPointer())
                        break;
                    const MicroRelocation* relocation = findRelocation(defRef);
                    if (!relocation || relocation->kind != MicroRelocation::Kind::ConstantAddress)
                        break;
                    recipe.op         = MicroInstrOpcode::LoadRegMem;
                    recipe.bits       = ops[2].opBits;
                    recipe.relocation = *relocation;
                    recipe.relocated  = true;
                    recipe.valid      = true;
                    break;
                }
                default:
                    break;
            }
        }
        std::erase_if(connectors, [&](const Connector& connector) { return !connector.dst.isValid() && remat[connector.denseIndex].valid; });
        // A register node the definition's register flows into without a
        // connector still reads the definition: a split child that kept the
        // register, or a label the value crosses in the same register on
        // some edge (resolution emits no move for either). The definition is
        // dead only when nothing along that continuity uses the value and no
        // register move reads a node on it.
        struct LabelEdge
        {
            uint32_t label       = 0;
            uint32_t predecessor = 0;
            bool     isJump      = false;
        };
        std::vector<LabelEdge> labelEdges;
        bool                   labelEdgesReady = false;
        // The edge walk is needed only for a rematerializable definition with no direct uses.
        const auto ensureLabelEdges = [&] {
            if (labelEdgesReady)
                return;
            labelEdgesReady = true;
            for (uint32_t s = 0; s < instructionCount_; ++s)
            {
                const MicroInstr* labelInst = instructions_->ptr(controlFlowGraph_->instructionRefs()[s]);
                if (!labelInst || labelInst->op != MicroInstrOpcode::Label)
                    continue;
                for (const uint32_t p : predecessors_[s])
                {
                    SWC_ASSERT(p < instructionCount_);
                    const MicroInstr* predInst = instructions_->ptr(controlFlowGraph_->instructionRefs()[p]);
                    if (!predInst)
                        continue;
                    labelEdges.push_back({s, p, MicroInstr::info(predInst->op).flags.has(MicroInstrFlagsE::JumpInstruction)});
                }
            }
        };
        std::vector<bool> reached;
        for (uint32_t denseIndex = 0; denseIndex < virtualCount; ++denseIndex)
        {
            RematRecipe& recipe = remat[denseIndex];
            if (!recipe.valid)
                continue;
            const LiveInterval* defNode = locate(denseIndex, recipe.defIndex * 2 + 1);
            if (!defNode || !defNode->usePositions.empty())
                continue;
            const uint32_t first = result.valueNodesBegin[denseIndex];
            const uint32_t last  = result.valueNodesBegin[denseIndex + 1];
            // This node has no direct use and no other node can carry its
            // definition onward or require a connector from it.
            if (last == first + 1)
            {
                recipe.defDead = true;
                continue;
            }
            ensureLabelEdges();
            const LiveInterval* firstNode = result.nodes.data() + first;
            const auto          nodeSlot  = [&](const LiveInterval* node) -> int64_t {
                const int64_t slot = node - firstNode;
                return slot >= 0 && slot < static_cast<int64_t>(last - first) ? slot : -1;
            };
            reached.assign(last - first, false);
            reached[nodeSlot(defNode)] = true;
            for (bool changed = true; changed;)
            {
                changed = false;
                for (uint32_t n = first; n + 1 < last; ++n)
                {
                    const LiveInterval& a = result.nodes[n];
                    const LiveInterval& b = result.nodes[n + 1];
                    if (!reached[n - first] || reached[n + 1 - first])
                        continue;
                    if (a.spilled || b.spilled || a.assignedReg != b.assignedReg || a.end() != b.start())
                        continue;
                    reached[n + 1 - first] = true;
                    changed                = true;
                }
                for (const LabelEdge& edge : labelEdges)
                {
                    const LiveInterval* atLabel = locate(denseIndex, edge.label * 2);
                    if (!atLabel || atLabel->spilled)
                        continue;
                    const uint32_t      predEndPos = edge.isJump ? edge.predecessor * 2 : edge.predecessor * 2 + 1;
                    const LiveInterval* atPred     = locate(denseIndex, predEndPos);
                    if (!atPred || atLabel == atPred || atPred->spilled || atPred->assignedReg != atLabel->assignedReg)
                        continue;
                    const int64_t from = nodeSlot(atPred);
                    const int64_t to   = nodeSlot(atLabel);
                    if (from < 0 || to < 0 || !reached[from] || reached[to])
                        continue;
                    reached[to] = true;
                    changed     = true;
                }
            }

            bool dead = true;
            for (uint32_t n = first; dead && n < last; ++n)
            {
                if (reached[n - first] && !result.nodes[n].usePositions.empty())
                    dead = false;
            }
            for (const Connector& connector : connectors)
            {
                if (!dead)
                    break;
                const int64_t slot = connector.from ? nodeSlot(connector.from) : -1;
                if (slot >= 0 && reached[slot])
                    dead = false;
            }
            recipe.defDead = dead;
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
        // A store parking a value at a guarded call belongs to the cold block and is left out
        // of the trade: moved to the definition it would land on the hot path.
        const auto isParkStore = [&](const Connector& connector) {
            return !connector.dst.isValid() && isGuardedCall(connector.beforeIndex);
        };
        std::vector<uint64_t> resolutionStoreCost;
        for (const Connector& connector : connectors)
        {
            if (!connector.dst.isValid() && !isParkStore(connector))
            {
                if (resolutionStoreCost.empty())
                    resolutionStoreCost.assign(virtualCount, 0);
                resolutionStoreCost[connector.denseIndex] += weightAt(connector.beforeIndex);
            }
        }
        if (!resolutionStoreCost.empty())
        {
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
                std::erase_if(connectors, [&](const Connector& connector) { return connector.denseIndex == denseIndex && !connector.dst.isValid() && !isParkStore(connector); });
                connectors.insert(connectors.end(), defStores.begin(), defStores.end());
            }
        }
    }

    // Parallel-copy ordering per insertion point: a connector reading a
    // register another one writes must run first. A cycle needs a bounce and
    // stage 1 declines it. A trampoline is its own point even when it shares
    // the physical insertion spot with a fall-through edge's connectors.
    // With at most one connector, its default order zero is already final.
    if (connectors.size() > 1)
    {
        std::map<uint64_t, std::vector<size_t>> byPoint;
        for (size_t i = 0; i < connectors.size(); ++i)
        {
            const bool isTramp = connectors[i].trampJump != std::numeric_limits<uint32_t>::max();
            byPoint[(static_cast<uint64_t>(connectors[i].beforeIndex) << 2) | (isTramp ? 0u : 2u) | connectors[i].phase].push_back(i);
        }
        std::vector<bool> emitted;
        for (auto& [point, list] : byPoint)
        {
            // A lone connector already has order zero and cannot form a copy dependency.
            if (list.size() == 1)
                continue;
            uint32_t order = 0;
            emitted.assign(list.size(), false);
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
                        if (candidate.dst.isValid())
                        {
                            for (size_t j = 0; j < list.size(); ++j)
                            {
                                if (i == j || emitted[j])
                                    continue;
                                if (connectors[list[j]].src == candidate.dst)
                                {
                                    readLater = true;
                                    break;
                                }
                            }
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
        for (auto it = instructions_->view().begin(), endIt = instructions_->view().end(); it != endIt && idx < instructionCount_; ++it, ++idx)
        {
            const MicroInstrOperand* ops = it->ops(*operands_);
            if (!ops)
                continue;
            const auto modes = MicroInstr::info(it->op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] == MicroInstrRegMode::None || !ops[i].reg.isVirtual())
                    continue;
                const uint32_t      denseIndex = denseVirtualIndex(ops[i].reg);
                const uint32_t      pos        = modes[i] == MicroInstrRegMode::Def ? idx * 2 + 1 : idx * 2;
                const LiveInterval* node       = locate(denseIndex, pos);
                if (!node || node->spilled || !node->assignedReg.isValid())
                    return false;
            }
        }
    }

    // Every spilled node's value needs its home, unless it is remade.
    for (const LiveInterval& node : result.nodes)
    {
        if (node.spilled && !remat[node.denseIndex].valid)
            ensureSpillSlot(states_[node.denseIndex], virtualRegs[node.denseIndex].isAnyFloat());
    }
    for (const Connector& connector : connectors)
    {
        if ((!connector.dst.isValid() || !connector.src.isValid()) && !remat[connector.denseIndex].valid)
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
        if (a.phase != b.phase)
            return a.phase < b.phase;
        return a.order < b.order;
    });

    // Both store-removal stages can orphan a trampoline. Its connectors all sit
    // immediately after its jump and sort before plain connectors at that point,
    // so the final ordering answers membership without a full scan per trampoline.
    std::erase_if(trampolines, [&](const Trampoline& trampoline) {
        const uint32_t beforeIndex = trampoline.jumpIndex + 1;
        const auto     connector   = std::ranges::lower_bound(connectors, beforeIndex, {}, &Connector::beforeIndex);
        return connector == connectors.end() || connector->trampJump != trampoline.jumpIndex;
    });
    std::ranges::sort(trampolines, {}, &Trampoline::jumpIndex);
    const auto trampolineFor = [&](const uint32_t jumpIndex) -> const Trampoline* {
        const auto it = std::ranges::lower_bound(trampolines, jumpIndex, {}, &Trampoline::jumpIndex);
        return it != trampolines.end() && it->jumpIndex == jumpIndex ? &*it : nullptr;
    };

    size_t   nextConnector  = 0;
    size_t   nextTrampoline = 0;
    uint32_t idx            = 0;
    for (auto it = instructions_->view().begin(), endIt = instructions_->view().end(); it != endIt && idx < instructionCount_; ++it, ++idx)
    {
        const MicroInstrRef instructionRef = it.current;

        // A jcc that owns a trampoline is inverted and retargeted to the
        // fresh label closing the trampoline block just below it.
        if (nextTrampoline < trampolines.size() && trampolines[nextTrampoline].jumpIndex == idx)
        {
            const Trampoline*  trampoline = &trampolines[nextTrampoline++];
            MicroInstrOperand* jccOps     = it->ops(*operands_);
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
            else if (connector.dst.isValid() && remat[connector.denseIndex].valid)
            {
                const RematRecipe& recipe = remat[connector.denseIndex];
                pendingInst.op            = recipe.op;
                pendingInst.ops[0].reg    = connector.dst;
                if (recipe.op == MicroInstrOpcode::LoadRegMem)
                {
                    // The displacement stays at zero: the relocation the
                    // insertion binds to this instruction is what names the
                    // constant.
                    pendingInst.numOps          = 4;
                    pendingInst.ops[1].reg      = MicroReg::instructionPointer();
                    pendingInst.ops[2].opBits   = recipe.bits;
                    pendingInst.ops[3].valueU64 = 0;
                }
                else if (recipe.op == MicroInstrOpcode::ClearReg)
                {
                    pendingInst.numOps        = 2;
                    pendingInst.ops[1].opBits = recipe.bits;
                }
                else
                {
                    pendingInst.numOps        = 3;
                    pendingInst.ops[1].opBits = recipe.bits;
                    pendingInst.ops[2]        = recipe.immediate;
                }
                if (recipe.relocated)
                {
                    pendingInst.relocation                = recipe.relocation;
                    pendingInst.relocation.instructionRef = MicroInstrRef::invalid();
                    pendingInst.relocation.codeOffset     = 0;
                    pendingInst.hasRelocation             = true;
                }
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

        MicroInstrOperand* ops = it->ops(*operands_);
        if (ops)
        {
            const auto modes = MicroInstr::info(it->op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] == MicroInstrRegMode::None || !ops[i].reg.isVirtual())
                    continue;
                const uint32_t      denseIndex = denseVirtualIndex(ops[i].reg);
                const uint32_t      pos        = modes[i] == MicroInstrRegMode::Def ? idx * 2 + 1 : idx * 2;
                const LiveInterval* node       = locate(denseIndex, pos);
                SWC_ASSERT(node && !node->spilled && node->assignedReg.isValid()); // pre-validated
                ops[i].reg = node->assignedReg;
            }
        }

        // A copy both sides of which took the same register is a no-op and
        // goes, except a 32-bit integer one: `mov eax, eax` clears the upper
        // half, and the combiner does rely on a 32-bit copy for that (it drops
        // an explicit extension of such a copy, and a field read out of a
        // spilled word is exactly such a copy). The combiner widens the 32-bit
        // copies nothing reads above bit 31, so those still go here. A
        // definition every read of which is remade is dead as well.
        if (it->op == MicroInstrOpcode::LoadRegReg)
        {
            const MicroInstrOperand* copyOps = it->ops(*operands_);
            if (copyOps && copyOps[0].reg == copyOps[1].reg && !(copyOps[0].reg.isInt() && copyOps[2].opBits == MicroOpBits::B32))
                queueErase(instructionRef);
        }
        for (const uint32_t denseIndex : defVirtualIndices_[idx])
        {
            if (remat[denseIndex].defDead && remat[denseIndex].defIndex == idx)
            {
                context_->builder->invalidateRelocationForInstruction(instructionRef);
                queueErase(instructionRef);
            }
        }
    }

    return true;
}

// compiler.optimization.099: joins the two values of a copy whose source stays live after it,
// when the two never hold different contents while both are live, as LLVM's register coalescer
// joins a copy's intervals through value numbers. The walk sees one interval per value and treats
// any overlap as interference, so `d = s` with `s` still read later occupies two registers and
// keeps the move even where both hold the same bits.
//
// The test is Chaitin's: two values interfere when one of them is defined at a point where the
// other is live afterwards, except by a full copy of the other one; both live at the function
// entry counts as such a definition. Any other definition while the partner is live is where the
// contents diverge. A join never raises the register demand at any point: where both were live,
// one value now is. Only a copy whose source is live after it is a candidate, since the copy of
// a value that dies there is the hint's business and needs no join.
//
// What a join may cost is the shape of the interval the walk splits: one value now carries both
// roles. So a join is kept to copies whose overlap crosses control flow, inside the copy's own
// loop nest, with a source that does not outlive that loop; the guards below say why each one.
//
// Returns whether a value was renamed, in which case every analysis of the pass is stale.
bool MicroRegisterAllocationPass::coalesceSameValueCopies()
{
    if (!intervalAllocationAccepts() || !instructionCount_)
        return false;

    const auto&    virtualRegs = denseVirtualRegs_.regs();
    const uint32_t wordCount   = denseVirtualRegs_.wordCount();
    const auto     instrRefs   = controlFlowGraph_->instructionRefs();

    // The integer values whose every definition clears the top half of the
    // register, and which no caller hands in: a 32-bit copy of one of them
    // copies every bit.
    std::vector<uint8_t> zeroHigh(virtualRegs.size(), 1);
    {
        const auto liveInEntry = DenseBits::row(liveInVirtualBits_, 0, wordCount);
        for (uint32_t dense = 0; dense < virtualRegs.size(); ++dense)
        {
            if (DenseBits::contains(liveInEntry, dense))
                zeroHigh[dense] = 0;
        }
        for (uint32_t idx = 0; idx < instructionCount_; ++idx)
        {
            if (defVirtualIndices_[idx].empty())
                continue;
            const MicroInstr*        inst = instructions_->ptr(instrRefs[idx]);
            const MicroInstrOperand* ops  = inst ? inst->ops(*operands_) : nullptr;
            for (const uint32_t dense : defVirtualIndices_[idx])
            {
                if (!ops || ops[0].reg != virtualRegs[dense] || !MicroPassHelpers::definesZeroHighBits(*inst, ops))
                    zeroHigh[dense] = 0;
            }
        }
    }

    // A copy between two distinct virtual registers of one class that copies
    // every bit: the only definition that leaves both holding the same contents.
    const auto fullCopyOperands = [&](MicroReg& outDst, MicroReg& outSrc, const MicroInstr* inst, const uint32_t idx) {
        if (!inst || inst->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrOperand* ops = inst->ops(*operands_);
        if (!ops || !ops[0].reg.isVirtual() || !ops[1].reg.isVirtual() || ops[0].reg == ops[1].reg || !ops[0].reg.isSameClass(ops[1].reg))
            return false;
        if (ops[0].reg.isVirtualInt())
        {
            if (ops[2].opBits != MicroOpBits::B64)
            {
                SWC_ASSERT(useVirtualIndices_[idx].size() == 1);
                const uint32_t src = useVirtualIndices_[idx].front();
                if (ops[2].opBits != MicroOpBits::B32 || !zeroHigh[src])
                    return false;
            }
        }
        else if (ops[2].opBits != MicroOpBits::B128)
        {
            return false;
        }
        outDst = ops[0].reg;
        outSrc = ops[1].reg;
        return true;
    };

    struct Candidate
    {
        uint32_t dst;
        uint32_t src;
        uint32_t copyDepth;
        bool     rejected;
    };
    const auto depthAt = [&](const uint32_t idx) {
        return idx < loopDepth_.size() ? loopDepth_[idx] : 0u;
    };

    // Inside a loop, the source of a joined copy must die in the loop: outside
    // it, the joined value then lives exactly where the destination did, and
    // the walk sees the destination's interval there unchanged. A source that
    // leaves the loop would stretch the destination's register past its exits,
    // where the walk splits and stores it on every exit edge rather than once
    // at the definition it spilled from before.
    const auto sourceStaysInCopyLoop = [&](const uint32_t copyIdx, const uint32_t src) {
        SWC_ASSERT(copyIdx < predecessors_.size());
        uint32_t head   = 0;
        uint32_t tail   = 0;
        bool     inLoop = false;
        for (uint32_t s = 0; s <= copyIdx; ++s)
        {
            for (const uint32_t p : predecessors_[s])
            {
                SWC_ASSERT(p < instructionCount_);
                if (p < copyIdx)
                    continue;
                if (!inLoop || p - s < tail - head)
                {
                    head   = s;
                    tail   = p;
                    inLoop = true;
                }
            }
        }
        if (!inLoop)
            return true;

        for (uint32_t idx = head; idx <= tail; ++idx)
        {
            for (const uint32_t succ : controlFlowGraph_->successors(idx))
            {
                SWC_ASSERT(succ < instructionCount_);
                if (succ >= head && succ <= tail)
                    continue;
                if (DenseBits::contains(DenseBits::row(liveInVirtualBits_, succ, wordCount), src))
                    return false;
            }
        }
        return true;
    };

    // A source that dies in the copy's own block overlaps the destination on a
    // straight line, which the forwarding after allocation already folds: it
    // reads the destination there and drops the copy, while the two values
    // keep their short intervals. Only a source still live where the block
    // ends makes the walk hold both across control flow.
    const auto sourceLeavesCopyBlock = [&](const uint32_t copyIdx, const uint32_t src) {
        for (uint32_t idx = copyIdx + 1; idx < instructionCount_; ++idx)
        {
            if (!DenseBits::contains(DenseBits::row(liveInVirtualBits_, idx, wordCount), src))
                return false;
            const MicroInstr* inst = instructions_->ptr(instrRefs[idx]);
            if (!inst || inst->op == MicroInstrOpcode::Label)
                return true;
            const MicroInstrFlags flags = MicroInstr::info(inst->op).flags;
            if (flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::TerminatorInstruction))
                return true;
        }
        return false;
    };

    SmallVector<Candidate> candidates;
    const MicroReg         debugBase = context_->debugStackBaseVirtualReg;
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        MicroReg          dstReg;
        MicroReg          srcReg;
        const MicroInstr* inst = instructions_->ptr(instrRefs[idx]);
        if (!fullCopyOperands(dstReg, srcReg, inst, idx))
            continue;
        if (dstReg == debugBase || srcReg == debugBase)
            continue;
        if (context_->builder->shouldPreserveVirtualCopy(dstReg) || context_->builder->shouldPreserveVirtualCopy(srcReg))
            continue;

        SWC_ASSERT(defVirtualIndices_[idx].size() == 1 && useVirtualIndices_[idx].size() == 1);
        const uint32_t dst = defVirtualIndices_[idx].front();
        const uint32_t src = useVirtualIndices_[idx].front();

        // A register copy only falls through. Its live-out is the next row;
        // probing two bits needs no copies of the virtual and concrete rows.
        if (idx + 1 == instructionCount_)
            continue;
        const auto liveOut = DenseBits::row(liveInVirtualBits_, idx + 1, wordCount);
        if (!DenseBits::contains(liveOut, src) || !DenseBits::contains(liveOut, dst))
            continue;

        if (!sourceLeavesCopyBlock(idx, src))
            continue;

        // Depth counts the same back-edge ranges searched by the confinement
        // check. At depth zero no enclosing loop can constrain this copy.
        const uint32_t copyDepth = depthAt(idx);
        const bool     confined  = !copyDepth || sourceStaysInCopyLoop(idx, src);
        const auto     known     = std::ranges::find_if(candidates, [&](const Candidate& c) { return (c.dst == dst && c.src == src) || (c.dst == src && c.src == dst); });
        if (known != candidates.end())
        {
            known->copyDepth = std::max(known->copyDepth, copyDepth);
            known->rejected |= !confined;
            continue;
        }
        candidates.push_back({.dst = dst, .src = src, .copyDepth = copyDepth, .rejected = !confined});
    }

    if (candidates.empty())
        return false;

    const auto liveInEntry = DenseBits::row(liveInVirtualBits_, 0, wordCount);
    for (Candidate& c : candidates)
        c.rejected |= DenseBits::contains(liveInEntry, c.dst) && DenseBits::contains(liveInEntry, c.src);

    MicroInstrRegOperandRefs regRefs;
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        const auto& defs = defVirtualIndices_[idx];
        const auto& uses = useVirtualIndices_[idx];

        MicroReg          copyDst;
        MicroReg          copySrc;
        const MicroInstr* inst   = instructions_->ptr(instrRefs[idx]);
        const bool        isCopy = fullCopyOperands(copyDst, copySrc, inst, idx);

        // A value an instruction names outside its register operands (an
        // encoder-implied use or definition) cannot be renamed there.
        regRefs.clear();
        if (inst)
            inst->collectRegOperands(*operands_, regRefs, context_->encoder);
        const auto namedByOperand = [&](const uint32_t dense) {
            return std::ranges::any_of(regRefs, [&](const MicroInstrRegOperandRef& ref) { return *ref.reg == virtualRegs[dense]; });
        };

        bool           haveLiveOut = false;
        const auto     liveIn      = DenseBits::row(liveInVirtualBits_, idx, wordCount);
        const uint32_t depth       = depthAt(idx);
        for (Candidate& c : candidates)
        {
            if (c.rejected)
                continue;

            // Where both are live inside a loop deeper than every copy, the
            // two values meet more often than the copy runs: the walk may keep
            // one of them in memory there and the other in a register, and
            // one joined value would make it split, and store, inside that
            // loop to save a move outside it.
            if (depth > c.copyDepth && DenseBits::contains(liveIn, c.dst) && DenseBits::contains(liveIn, c.src))
            {
                c.rejected = true;
                continue;
            }

            const bool defDst     = std::ranges::find(defs, c.dst) != defs.end();
            const bool touchesDst = defDst || std::ranges::find(uses, c.dst) != uses.end();
            if (touchesDst && !namedByOperand(c.dst))
            {
                c.rejected = true;
                continue;
            }

            const bool defSrc     = std::ranges::find(defs, c.src) != defs.end();
            const bool touchesSrc = defSrc || std::ranges::find(uses, c.src) != uses.end();
            if (touchesSrc && !namedByOperand(c.src))
            {
                c.rejected = true;
                continue;
            }

            if (!defDst && !defSrc)
                continue;
            if (defDst && defSrc)
            {
                c.rejected = true;
                continue;
            }

            if (!haveLiveOut)
            {
                computeCurrentLiveOutBits(idx);
                haveLiveOut = true;
            }

            const uint32_t defined = defDst ? c.dst : c.src;
            const uint32_t partner = defDst ? c.src : c.dst;
            if (!DenseBits::contains(tempOutVirtual_, partner))
                continue;
            if (isCopy && copyDst == virtualRegs[defined] && copySrc == virtualRegs[partner])
                continue;
            c.rejected = true;
        }
    }

    // Join each accepted pair, the destination renamed to the source. A value
    // joined once is left out of every later pair: the test above compared the
    // original values two at a time, which says nothing about three of them.
    SmallVector<std::pair<MicroReg, MicroReg>> renames;
    std::vector<uint8_t>                       joined(virtualRegs.size(), 0);
    for (const Candidate& c : candidates)
    {
        if (c.rejected || joined[c.dst] || joined[c.src])
            continue;
        joined[c.dst] = 1;
        joined[c.src] = 1;
        renames.push_back({virtualRegs[c.dst], virtualRegs[c.src]});
    }

    if (renames.empty())
        return false;

    for (const auto& [fromReg, toReg] : renames)
        context_->builder->mergeVirtualRegForbiddenPhysRegs(fromReg, toReg);

    for (auto it = instructions_->view().begin(), endIt = instructions_->view().end(); it != endIt;)
    {
        const MicroInstrRef instructionRef = it.current;
        MicroInstr&         inst           = *it;
        ++it;

        MicroInstrOperand* ops = inst.ops(*operands_);
        if (!ops)
            continue;
        bool copiesWhole = false;
        if (inst.op == MicroInstrOpcode::LoadRegReg && ops[1].reg.isVirtual())
        {
            if (ops[1].reg.isVirtualInt())
            {
                copiesWhole = ops[2].opBits == MicroOpBits::B64;
                if (ops[2].opBits == MicroOpBits::B32)
                {
                    const uint32_t src = denseVirtualRegs_.find(ops[1].reg);
                    copiesWhole        = src != MicroDenseRegIndex::K_INVALID_INDEX && zeroHigh[src];
                }
            }
            else
            {
                copiesWhole = ops[2].opBits == MicroOpBits::B128;
            }
        }

        const auto modes   = MicroInstr::info(inst.op).resolvedRegModes(ops);
        bool       renamed = false;
        for (size_t operandIndex = 0; operandIndex < modes.size(); ++operandIndex)
        {
            if (modes[operandIndex] == MicroInstrRegMode::None)
                continue;
            MicroReg& reg = ops[operandIndex].reg;
            if (!reg.isValid() || reg.isNoBase())
                continue;
            for (const auto& [fromReg, toReg] : renames)
            {
                if (reg == fromReg)
                {
                    reg     = toReg;
                    renamed = true;
                    break;
                }
            }
        }

        // A joined copy that copied every bit is now a move of the value onto
        // itself. A narrower one still truncates.
        if (renamed && copiesWhole && ops[0].reg == ops[1].reg)
            instructions_->erase(instructionRef);
    }

    context_->passChanged = true;
    return true;
}

bool MicroRegisterAllocationPass::runIntervalAllocation()
{
    if (!intervalAllocationAccepts())
        return false;

    // A function with no virtual register has nothing to allocate; the
    // existing scan keeps it, scratch choices of its legalization included.
    if (denseVirtualRegs_.regs().empty())
        return false;

    // The walk consults fixed intervals built from concrete claims; the
    // existing scan computes them later (inside assignGlobalRegisters), and
    // the computation is idempotent.
    computeConcreteClaimPositions();

    IntervalWalkResult result;
    {
        std::vector<LiveInterval> intervals;
        buildLiveIntervals(intervals);
        if (!walkIntervals(std::move(intervals), result))
            return false;
    }

    // Later legalization borrows a register only around its short staging
    // sequence, preserving the concrete occupant in a frame slot.
    if (!applyIntervalAllocation(result))
        return false;

    // What the later sweeps need from the first: the registers a scratch may
    // borrow around when nothing is free, and the debug local-stack base.
    context_->intervalAllocated  = true;
    context_->globalReservedRegs = std::move(result.poolRegs);
    if (result.debugStackBasePhys.isValid())
        context_->debugStackBasePhysReg = result.debugStackBasePhys;

    context_->passChanged = true;
    return true;
}

SWC_END_NAMESPACE();
