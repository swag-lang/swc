#include "pch.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/DenseBits.h"
#include "Support/Core/SmallVector.h"
#include "Support/Math/Helpers.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Assert.h"

// Linear-scan style register allocation for the micro IR.
//
// Overall flow (driven by `run()`):
//
//   clearState           : drop all per-function caches.
//   initState            : capture context, sizes, and reset bookkeeping.
//   coalesceLocalCopies  : remove `mov vDst, vSrc` copies whose source can
//                          take over the destination's role within the same
//                          local flow region. This both shrinks live ranges
//                          and avoids needless register-to-register moves
//                          in the assigned output.
//   prepareInstructionData
//                        : build the per-instruction use/def descriptor
//                          (`instructionUseDefs_`) and the dense-index
//                          tables that map MicroReg -> compact integer for
//                          the liveness bitsets and state arrays.
//   analyzeLiveness      : iterative dataflow over the local CFG; computes
//                          live-in / live-out bit sets per instruction,
//                          tracks call sites for caller-saved spilling, and
//                          builds the per-virtual position lists used for
//                          `distanceToNextUse` heuristics during eviction.
//   setupPools           : seed the free-register pools (one per register
//                          class) from the calling-convention's allocatable
//                          regs, honoring per-virtual forbidden-physreg
//                          constraints recorded by Legalize.
//   rewriteInstructions  : single forward pass that, at each instruction:
//                            1. expires mappings whose virtual is no longer
//                               live, returning their phys reg to the pool;
//                            2. spills caller-saved live values around calls;
//                            3. assigns physical regs for use/def operands,
//                               possibly evicting a less-valuable mapping
//                               (chosen by `selectEvictionCandidate`) into a
//                               spill slot or rematerializing a known constant;
//                            4. mutates operand registers in place and queues
//                               any pending spill stores/loads to insert
//                               before/after the instruction.
//   insertSpillFrame     : if any spill slots were used, insert the matching
//                          `sub sp, frameSize` at function entry and the
//                          matching `add sp, frameSize` before each Ret.
//
// Spill / rematerialize policy (see VRegState):
//   - When a virtual is evicted, prefer rematerialization if it has a known
//     constant origin (LoadRegImm/ClearReg) â€” emit a fresh load at the use
//     site instead of hitting memory.
//   - Otherwise allocate (lazily) a stack slot via `ensureSpillSlot` and
//     emit store-before-eviction / load-before-use as PendingInsert entries.
//   - `spillMemOffset` resolves the slot to a SP-relative offset, accounting
//     for inline pushes/pops between function entry and the access point.
//
// Eviction heuristic (`isCandidateBetter`):
//   - Prefer evicting a value that is dead soon (largest distanceToNextUse).
//   - Prefer evicting a value that already has a spill slot (no extra store).
//   - Prefer evicting a value that is rematerializable from an immediate.
//   - Penalize evicting a value live across a call (it would need a save
//     even if it survives this allocation point).
//
// Constraints honored:
//   - Per-virtual forbidden physical registers (Legalize-supplied; e.g. for
//     fixed shift-count operands).
//   - Caller-saved registers spilled across CallInstruction sites.
//   - Persistent (callee-saved) physical registers tracked separately so
//     PrologEpilog can later push/pop them.
//   - Memory base registers used by destructive load forms are kept off the
//     destination's candidate list (`recordDestructiveAlias`).
//
// The pass converts virtual microcode into concrete register form.

SWC_BEGIN_NAMESPACE();

namespace
{
    void appendUniqueDenseIndex(SmallVector<uint32_t, 4>& indices, const uint32_t value)
    {
        for (const auto existing : indices)
        {
            if (existing == value)
                return;
        }

        indices.push_back(value);
    }

    void appendUniquePosition(std::vector<uint32_t>& positions, const uint32_t instructionIndex)
    {
        if (positions.empty() || positions.back() != instructionIndex)
            positions.push_back(instructionIndex);
    }

    void advancePositionCursor(uint32_t& cursor, const std::vector<uint32_t>& positions, const uint32_t instructionIndex)
    {
        while (cursor < positions.size() && positions[cursor] <= instructionIndex)
            ++cursor;
    }

    // Widens [lo, hi] for every register set in a liveness row, so that after a
    // full scan each register carries the hull of the range it is live over.
    void widenSpansFromLiveRow(std::vector<uint32_t>& lo, std::vector<uint32_t>& hi, const std::span<const uint64_t> row, const uint32_t instructionIndex)
    {
        for (size_t wordIndex = 0; wordIndex < row.size(); ++wordIndex)
        {
            uint64_t wordBits = row[wordIndex];
            while (wordBits)
            {
                const size_t denseIndex = wordIndex * 64ull + std::countr_zero(wordBits);
                wordBits &= wordBits - 1ull;
                if (denseIndex >= lo.size())
                    break;

                lo[denseIndex] = std::min(lo[denseIndex], instructionIndex);
                hi[denseIndex] = std::max(hi[denseIndex], instructionIndex);
            }
        }
    }

    bool isRegisterCopyLike(const MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                return true;

            default:
                return false;
        }
    }
}

void MicroRegisterAllocationPass::initState(MicroPassContext& context)
{
    context_          = &context;
    conv_             = &CallConv::get(context.callConvKind);
    instructions_     = (context.instructions);
    operands_         = (context.operands);
    instructionCount_ = instructions_->count();
    spillFrameUsed_   = 0;
    hasControlFlow_   = false;
    hasVirtualRegs_   = false;
    controlFlowGraph_ = nullptr;

    instructionUseDefs_.clear();
    instructionUseDefs_.resize(instructionCount_);
    useVirtualIndices_.reserve(instructionCount_);
    defVirtualIndices_.reserve(instructionCount_);
    useConcreteIndices_.reserve(instructionCount_);
    defConcreteIndices_.reserve(instructionCount_);
    predecessors_.reserve(instructionCount_);
    worklist_.reserve(instructionCount_);
    inWorklist_.reserve(instructionCount_);

    for (const auto& inst : instructions_->view())
    {
        if (inst.op == MicroInstrOpcode::Label || MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::JumpInstruction))
        {
            hasControlFlow_ = true;
            break;
        }
    }

    // What each address load points at, so rematerializing one can carry its
    // relocation along. Snapshotted by value: the builder's vector grows every
    // time a remade load is inserted.
    relocationByDefInstruction_.clear();
    for (const MicroRelocation& reloc : (context.builder)->codeRelocations())
    {
        if (reloc.instructionRef.isValid())
            relocationByDefInstruction_[reloc.instructionRef] = reloc;
    }
}

uint32_t MicroRegisterAllocationPass::allocRequestPriority(const AllocRequest& request)
{
    if (request.isUse && request.isDef)
        return 0;
    if (request.isUse)
        return 1;

    return 2;
}

bool MicroRegisterAllocationPass::compareAllocRequests(const AllocRequest& lhs, const AllocRequest& rhs)
{
    return allocRequestPriority(lhs) < allocRequestPriority(rhs);
}

void MicroRegisterAllocationPass::coalesceLocalCopies() const
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(context_->builder != nullptr);
    SWC_ASSERT(instructions_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    for (auto it = instructions_->view().begin(); it != instructions_->view().end();)
    {
        const MicroInstrRef instructionRef = it.current;
        MicroInstr&         inst           = *it;
        ++it;

        if (inst.op != MicroInstrOpcode::LoadRegReg)
            continue;

        const MicroInstrOperand* ops = inst.ops(*operands_);
        if (!ops)
            continue;

        const MicroReg dstReg = ops[0].reg;
        const MicroReg srcReg = ops[1].reg;
        if (!dstReg.isVirtual() || !srcReg.isVirtual())
            continue;
        if (!dstReg.isSameClass(srcReg))
            continue;
        if (context_->builder &&
            (context_->builder->shouldPreserveVirtualCopy(dstReg) || context_->builder->shouldPreserveVirtualCopy(srcReg)))
            continue;

        if (dstReg == srcReg)
        {
            instructions_->erase(instructionRef);
            context_->passChanged = true;
            continue;
        }

        bool replacedUses = false;
        for (auto scanIt = it; scanIt != instructions_->view().end(); ++scanIt)
        {
            const MicroInstrUseDef useDef = scanIt->collectUseDef(*operands_, context_->encoder);
            if (containsKey(useDef.defs, srcReg) || containsKey(useDef.defs, dstReg))
                break;

            if (containsKey(useDef.uses, dstReg))
            {
                SmallVector<MicroInstrRegOperandRef> refs;
                scanIt->collectRegOperands(*operands_, refs, context_->encoder);
                for (const MicroInstrRegOperandRef& ref : refs)
                {
                    if (!ref.reg || *ref.reg != dstReg || !ref.use || ref.def)
                        continue;

                    *ref.reg     = srcReg;
                    replacedUses = true;
                }
            }

            if (MicroInstrInfo::isLocalDataflowBarrier(*scanIt, useDef))
                break;
        }

        if (!replacedUses)
            continue;

        context_->builder->mergeVirtualRegForbiddenPhysRegs(dstReg, srcReg);
        if (canEraseCoalescedCopy(instructionRef, dstReg))
            instructions_->erase(instructionRef);

        context_->passChanged = true;
    }
}

uint32_t MicroRegisterAllocationPass::denseVirtualIndex(MicroReg key) const
{
    const uint32_t denseIndex = denseVirtualRegs_.find(key);
    SWC_ASSERT(denseIndex != MicroDenseRegIndex::K_INVALID_INDEX);
    return denseIndex;
}

MicroRegisterAllocationPass::VRegState& MicroRegisterAllocationPass::stateForVirtual(MicroReg key)
{
    return states_[denseVirtualIndex(key)];
}

const MicroRegisterAllocationPass::VRegState& MicroRegisterAllocationPass::stateForVirtual(MicroReg key) const
{
    return states_[denseVirtualIndex(key)];
}

bool MicroRegisterAllocationPass::isLiveOut(MicroReg key, uint32_t stamp) const
{
    const uint32_t denseIndex = denseVirtualRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= liveStampByDenseIndex_.size())
        return false;
    return liveStampByDenseIndex_[denseIndex] == stamp;
}

bool MicroRegisterAllocationPass::isLiveAcrossCall(MicroReg key) const
{
    const uint32_t denseIndex = denseVirtualRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= vregsLiveAcrossCall_.size())
        return false;
    return vregsLiveAcrossCall_[denseIndex] != 0;
}

bool MicroRegisterAllocationPass::isLiveAcrossHotCall(MicroReg key) const
{
    // A callee-saved float register costs a fixed 16-byte store/load pair on
    // every function entry; spilling around calls costs one pair per executed
    // crossing. Flat crossings never repay that reliably â€” only a call
    // crossed inside a loop does, where the spill pair would run every
    // iteration.
    const uint32_t denseIndex = denseVirtualRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= vregsLiveAcrossHotCall_.size())
        return false;
    return vregsLiveAcrossHotCall_[denseIndex] >= 10;
}

void MicroRegisterAllocationPass::markLiveAcrossCall(MicroReg key)
{
    const uint32_t denseIndex        = denseVirtualIndex(key);
    vregsLiveAcrossCall_[denseIndex] = 1;
}

bool MicroRegisterAllocationPass::requiresCallSpill(MicroReg key) const
{
    const uint32_t denseIndex = denseVirtualRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= callSpillFlags_.size())
        return false;
    return callSpillFlags_[denseIndex] != 0;
}

void MicroRegisterAllocationPass::markCallSpill(MicroReg key)
{
    const uint32_t denseIndex   = denseVirtualIndex(key);
    callSpillFlags_[denseIndex] = 1;
}

void MicroRegisterAllocationPass::clearCallSpill(MicroReg key)
{
    const uint32_t denseIndex = denseVirtualRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= callSpillFlags_.size())
        return;
    callSpillFlags_[denseIndex] = 0;
}

bool MicroRegisterAllocationPass::containsKey(const MicroRegSpan keys, MicroReg key)
{
    for (const auto value : keys)
    {
        if (value == key)
            return true;
    }

    return false;
}

void MicroRegisterAllocationPass::appendUniqueReg(SmallVector<MicroReg>& regs, MicroReg reg)
{
    if (!containsKey(regs, reg))
        regs.push_back(reg);
}

bool MicroRegisterAllocationPass::isPersistentPhysReg(MicroReg reg) const
{
    if (reg.isInt())
        return containsKey(intPersistentRegs_, reg);

    if (reg.isFloat())
        return containsKey(floatPersistentRegs_, reg);

    SWC_UNREACHABLE();
}

bool MicroRegisterAllocationPass::isPhysRegForbiddenForVirtual(MicroReg virtKey, MicroReg physReg) const
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(context_->builder != nullptr);
    return context_->builder->isVirtualRegPhysRegForbidden(virtKey, physReg);
}

bool MicroRegisterAllocationPass::isLiveInAt(MicroReg key, uint32_t instructionIndex) const
{
    if (instructionIndex >= instructionCount_)
        return false;

    const uint32_t denseIndex = denseVirtualRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX)
        return false;

    const uint32_t wordCount = denseVirtualRegs_.wordCount();
    if (!wordCount)
        return false;

    const std::span<const uint64_t> liveInRow = DenseBits::row(liveInVirtualBits_, instructionIndex, wordCount);
    return DenseBits::contains(liveInRow, denseIndex);
}

void MicroRegisterAllocationPass::computeConcreteLoopCarried()
{
    // A concrete register whose value is live-in at a loop header crosses that
    // loop's back-edge, so its uses can precede the point that wants it.
    concreteLoopCarried_.assign(denseConcreteRegs_.regs().size(), 0);

    const uint32_t wordCount = denseConcreteRegs_.wordCount();
    if (!wordCount)
        return;

    for (uint32_t header = 0; header < instructionCount_; ++header)
    {
        bool isLoopHeader = false;
        for (const uint32_t pred : predecessors_[header])
            isLoopHeader = isLoopHeader || pred >= header;
        if (!isLoopHeader)
            continue;

        const std::span<const uint64_t> liveRow = DenseBits::row(liveInConcreteBits_, header, wordCount);
        for (size_t wordIndex = 0; wordIndex < liveRow.size(); ++wordIndex)
        {
            uint64_t wordBits = liveRow[wordIndex];
            while (wordBits)
            {
                const size_t denseIndex = wordIndex * 64ull + std::countr_zero(wordBits);
                wordBits &= wordBits - 1ull;
                if (denseIndex >= concreteLoopCarried_.size())
                    break;

                concreteLoopCarried_[denseIndex] = 1;
            }
        }
    }
}

bool MicroRegisterAllocationPass::isConcreteLoopCarried(const MicroReg physReg) const
{
    const uint32_t denseIndex = denseConcreteRegs_.find(physReg);
    return denseIndex != MicroDenseRegIndex::K_INVALID_INDEX && denseIndex < concreteLoopCarried_.size() && concreteLoopCarried_[denseIndex] != 0;
}

bool MicroRegisterAllocationPass::isConcreteLiveInAt(MicroReg key, uint32_t instructionIndex) const
{
    if (instructionIndex >= instructionCount_)
        return false;

    const uint32_t denseIndex = denseConcreteRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX)
        return false;

    const uint32_t wordCount = denseConcreteRegs_.wordCount();
    if (!wordCount)
        return false;

    const std::span<const uint64_t> liveInRow = DenseBits::row(liveInConcreteBits_, instructionIndex, wordCount);
    return DenseBits::contains(liveInRow, denseIndex);
}

bool MicroRegisterAllocationPass::hasFutureConcreteTouchConflict(MicroReg virtKey, MicroReg physReg, uint32_t instructionIndex) const
{
    if (!physReg.isInt() && !physReg.isFloat())
        return false;

    const uint32_t denseIndex = denseConcreteRegs_.find(physReg);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= concreteTouchPositionsByDenseIndex_.size())
        return false;

    const auto& positions = concreteTouchPositionsByDenseIndex_[denseIndex];
    auto        cursor    = nextConcreteTouchCursor_[denseIndex];
    advancePositionCursor(cursor, positions, instructionIndex);
    if (cursor >= positions.size())
        return false;

    return isLiveInAt(virtKey, positions[cursor]);
}

bool MicroRegisterAllocationPass::canUsePhysical(MicroReg virtKey, uint32_t instructionIndex, MicroReg physReg, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive) const
{
    if (!physReg.isInt() && !physReg.isFloat())
        return false;
    if (containsKey(forbiddenPhysRegs, physReg))
        return false;
    if (isPhysRegForbiddenForVirtual(virtKey, physReg))
        return false;
    if (!allowConcreteLive && hasFutureConcreteTouchConflict(virtKey, physReg, instructionIndex))
        return false;

    // The future-touch test above asks whether the REQUESTING value is still
    // alive at the register's next concrete touch â€” it cannot see a concrete
    // value alive across this very point (defined above, read below) when the
    // requester dies first. The reload or mapping inserted here would clobber
    // that live value: an argument register already loaded for an imminent
    // call is the canonical victim (arg set up first, another arg's reload
    // asks for a register in between). This refusal is absolute â€” no relaxed
    // path can make the clobber safe â€” and by construction it only triggers
    // between a concrete definition and its read, so registers stay available
    // before their setup and after their last concrete read.
    if (isConcreteLiveInAt(physReg, instructionIndex))
        return false;

    // The scan above walks forward in layout order, so it is blind to a value
    // a loop carries around its back-edge: every touch of it lies behind the
    // point that wants the register, and the register looks free. Taking it is
    // unrecoverable â€” a value living under a register's own name has no home to
    // be spilled to, so no later repair can put it back. For those registers
    // only, ask the liveness fixpoint, which answers for the CFG instead of for
    // the listing, and refuse even on the relaxed paths that otherwise tolerate
    // a live concrete register.
    if (isConcreteLoopCarried(physReg) && isConcreteLiveInAt(physReg, instructionIndex))
        return false;

    // A register the first sweep reserved for a whole live range stays
    // off limits for every later sweep: the value it holds is not in this
    // sweep's mapping, so displacing it would go unnoticed and unrepaired.
    if (!context_->isFirstAllocationSweep && containsKey(context_->globalReservedRegs, physReg))
        return false;

    // Unconditional, unlike the concrete-touch test above: a globally reserved
    // register is owned by its value over the whole range, and the fallback
    // paths that tolerate a concrete conflict have no way to make that one safe.
    if (isReservedByGlobalFor(virtKey, physReg, instructionIndex))
        return false;

    return true;
}

bool MicroRegisterAllocationPass::tryTakeSpecificPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroReg preferredPhysReg, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const
{
    for (size_t candidateIndex = 0; candidateIndex < pool.size(); ++candidateIndex)
    {
        if (pool[candidateIndex] != preferredPhysReg)
            continue;
        if (!canUsePhysical(virtKey, instructionIndex, preferredPhysReg, forbiddenPhysRegs, allowConcreteLive))
            return false;

        outPhys = preferredPhysReg;
        if (candidateIndex != pool.size() - 1)
            pool[candidateIndex] = pool.back();
        pool.pop_back();
        return true;
    }

    return false;
}

bool MicroRegisterAllocationPass::tryTakeAllowedPhysical(SmallVector<MicroReg>& pool, MicroReg virtKey, uint32_t instructionIndex, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys) const
{
    for (size_t index = pool.size(); index > 0; --index)
    {
        const size_t candidateIndex = index - 1;
        const auto   candidateReg   = pool[candidateIndex];
        if (!canUsePhysical(virtKey, instructionIndex, candidateReg, forbiddenPhysRegs, allowConcreteLive))
            continue;

        outPhys = candidateReg;
        if (candidateIndex != pool.size() - 1)
            pool[candidateIndex] = pool.back();
        pool.pop_back();
        return true;
    }

    return false;
}

void MicroRegisterAllocationPass::returnToFreePool(MicroReg reg)
{
    if (reg.isInt())
    {
        if (containsKey(intPersistentRegs_, reg))
            freeIntPersistent_.push_back(reg);
        else
            freeIntTransient_.push_back(reg);
        return;
    }

    if (reg.isFloat())
    {
        if (containsKey(floatPersistentRegs_, reg))
            freeFloatPersistent_.push_back(reg);
        else
            freeFloatTransient_.push_back(reg);
        return;
    }

    SWC_UNREACHABLE();
}

void MicroRegisterAllocationPass::computeLoopDepth()
{
    // Approximate loop-nesting depth per instruction from CFG back-edges. A
    // back-edge is a predecessor p of instruction s with p >= s; the loop body
    // it forms spans [s, p]. Depth is the number of such ranges covering an
    // instruction. Used to rank pin candidates (deeper uses benefit most from
    // staying register-resident).
    loopDepth_.assign(instructionCount_, 0);
    functionHasLoop_ = false;
    if (!hasControlFlow_ || instructionCount_ == 0)
        return;

    std::vector delta(static_cast<size_t>(instructionCount_) + 1, 0);
    bool        anyBackEdge = false;
    for (uint32_t s = 0; s < instructionCount_; ++s)
    {
        for (const uint32_t p : predecessors_[s])
        {
            if (p >= s && p < instructionCount_)
            {
                ++delta[s];
                --delta[p + 1];
                anyBackEdge = true;
            }
        }
    }
    functionHasLoop_ = anyBackEdge;
    if (!anyBackEdge)
        return;

    int32_t running = 0;
    for (uint32_t i = 0; i < instructionCount_; ++i)
    {
        running += delta[i];
        loopDepth_[i] = running > 0 ? static_cast<uint32_t>(running) : 0;
    }
}

bool MicroRegisterAllocationPass::functionHasCalls() const
{
    for (const MicroInstrUseDef& useDef : instructionUseDefs_)
    {
        if (useDef.isCall)
            return true;
    }

    return false;
}

bool MicroRegisterAllocationPass::isFlushBoundary(const uint32_t instructionIndex, const MicroInstr& inst) const
{
    if (!hasControlFlow_)
        return false;
    if (MicroInstrInfo::isTerminatorInstruction(inst))
        return true;
    if (inst.op != MicroInstrOpcode::Label)
        return false;

    // A label reached only by falling through from the instruction before it is
    // not a join: the mapping carried across it is the one its predecessor left.
    if (instructionIndex == 0 || instructionIndex >= predecessors_.size())
        return true;

    const auto& predecessors = predecessors_[instructionIndex];
    return predecessors.size() != 1 || predecessors.front() != instructionIndex - 1;
}

void MicroRegisterAllocationPass::computeVirtualLiveSpans()
{
    // The span of instruction indices over which a value occupies its home. It
    // is the hull of its live range, holes included: a global keeps one
    // register for the whole span, so a hole is given away rather than reused.
    // That costs some packing and buys the property the whole design rests on â€”
    // one value, one register, everywhere it is live.
    virtualSpanLo_.assign(denseVirtualRegs_.regs().size(), std::numeric_limits<uint32_t>::max());
    virtualSpanHi_.assign(denseVirtualRegs_.regs().size(), 0);

    const uint32_t wordCount = denseVirtualRegs_.wordCount();
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        widenSpansFromLiveRow(virtualSpanLo_, virtualSpanHi_, DenseBits::row(liveInVirtualBits_, idx, wordCount), idx);

        // A def is not live-in at its own instruction, and a last use is not
        // live-in at the one after it, so neither endpoint appears in the
        // liveness rows. Both still hold the register.
        for (const uint32_t denseIndex : defVirtualIndices_[idx])
        {
            virtualSpanLo_[denseIndex] = std::min(virtualSpanLo_[denseIndex], idx);
            virtualSpanHi_[denseIndex] = std::max(virtualSpanHi_[denseIndex], idx);
        }

        for (const uint32_t denseIndex : useVirtualIndices_[idx])
        {
            virtualSpanLo_[denseIndex] = std::min(virtualSpanLo_[denseIndex], idx);
            virtualSpanHi_[denseIndex] = std::max(virtualSpanHi_[denseIndex], idx);
        }
    }
}

void MicroRegisterAllocationPass::computeConcreteClaimPositions()
{
    // Every instruction at which a fixed register is spoken for: named as an
    // operand, defined by an ABI shuffle, clobbered by a call, or merely live
    // between two of those. A global may not take a register over any of them.
    concreteClaimPositionsByDenseIndex_.clear();
    concreteClaimPositionsByDenseIndex_.resize(denseConcreteRegs_.regs().size());

    const uint32_t wordCount = denseConcreteRegs_.wordCount();
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        for (const uint32_t denseIndex : useConcreteIndices_[idx])
            appendUniquePosition(concreteClaimPositionsByDenseIndex_[denseIndex], idx);
        for (const uint32_t denseIndex : defConcreteIndices_[idx])
            appendUniquePosition(concreteClaimPositionsByDenseIndex_[denseIndex], idx);

        const std::span<const uint64_t> liveRow = DenseBits::row(liveInConcreteBits_, idx, wordCount);
        for (size_t wordIndex = 0; wordIndex < liveRow.size(); ++wordIndex)
        {
            uint64_t wordBits = liveRow[wordIndex];
            while (wordBits)
            {
                const size_t denseIndex = wordIndex * 64ull + std::countr_zero(wordBits);
                wordBits &= wordBits - 1ull;
                if (denseIndex >= concreteClaimPositionsByDenseIndex_.size())
                    break;

                appendUniquePosition(concreteClaimPositionsByDenseIndex_[denseIndex], idx);
            }
        }
    }

    for (auto& positions : concreteClaimPositionsByDenseIndex_)
        std::ranges::sort(positions);
}

void MicroRegisterAllocationPass::computeGlobalBenefits(std::vector<uint64_t>& outBenefit) const
{
    // A value is worth a global register exactly when the boundary flush would
    // otherwise push it through memory, and the benefit is what that costs: one
    // spill plus one reload per boundary it is live across, weighted by how
    // often the boundary runs. A value never live across a boundary gets zero â€”
    // the local allocator already keeps it in a register for its whole life.
    //
    // The weight grows by an order of magnitude per loop nesting level, the
    // usual static estimate of trip count. A linear weight would rank a value
    // spanning many outer boundaries above one crossing a few innermost ones,
    // inverting the real cost.
    constexpr uint64_t K_DEPTH_WEIGHT     = 10;
    constexpr uint32_t K_MAX_WEIGHT_DEPTH = 9;

    outBenefit.assign(denseVirtualRegs_.regs().size(), 0);

    const uint32_t wordCount = denseVirtualRegs_.wordCount();
    uint32_t       idx       = 0;
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it, ++idx)
    {
        if (!isFlushBoundary(idx, *it))
            continue;

        // Only a boundary inside a loop is worth anything. Reserving a register
        // for a value's whole live range to save one round-trip on a path taken
        // once is a bad trade â€” it denies the local allocator that register
        // everywhere, forever, for a single spill and reload. It also keeps a
        // value that is merely a copy from being handed a register of its own
        // instead of being coalesced away.
        // A boundary inside a loop earns by trip count. In a function with
        // no loop at all — the shape full unrolling produces — every
        // boundary counts at unit weight instead: a value live across a
        // dozen label stitches between unrolled copies pays a dozen
        // round-trips without a register. In a function that does have
        // loops, depth-zero boundaries stay worthless, so cold-path
        // crossings cannot buy a register they would waste.
        const uint32_t depth = idx < loopDepth_.size() ? loopDepth_[idx] : 0u;
        if (!depth && functionHasLoop_)
            continue;

        uint64_t weight = 1;
        for (uint32_t level = 0; level < std::min(depth, K_MAX_WEIGHT_DEPTH); ++level)
            weight *= K_DEPTH_WEIGHT;

        const std::span<const uint64_t> liveRow = DenseBits::row(liveInVirtualBits_, idx, wordCount);
        for (size_t wordIndex = 0; wordIndex < liveRow.size(); ++wordIndex)
        {
            uint64_t wordBits = liveRow[wordIndex];
            while (wordBits)
            {
                const size_t denseIndex = wordIndex * 64ull + std::countr_zero(wordBits);
                wordBits &= wordBits - 1ull;
                if (denseIndex >= outBenefit.size())
                    break;

                outBenefit[denseIndex] += weight;
            }
        }
    }
}

void MicroRegisterAllocationPass::computeGlobalAccessBenefits(std::vector<uint64_t>& outBenefit) const
{
    // Once a boundary-crossing value is given a stable register, every use and
    // definition in its live range can stay there. Rank those accesses by the
    // loop depth at which they execute. Boundary count alone cannot distinguish
    // a loop cursor used on every iteration from a hoisted address that merely
    // remains live across the same boundaries.
    constexpr uint64_t K_DEPTH_WEIGHT     = 10;
    constexpr uint32_t K_MAX_WEIGHT_DEPTH = 9;

    outBenefit.assign(denseVirtualRegs_.regs().size(), 0);

    for (uint32_t idx = 0; idx < instructionUseDefs_.size(); ++idx)
    {
        const uint32_t depth  = idx < loopDepth_.size() ? loopDepth_[idx] : 0u;
        uint64_t       weight = 1;
        for (uint32_t level = 0; level < std::min(depth, K_MAX_WEIGHT_DEPTH); ++level)
            weight *= K_DEPTH_WEIGHT;

        const auto addAccess = [&](const MicroReg reg) {
            if (!reg.isVirtual())
                return;

            const uint32_t denseIndex = denseVirtualRegs_.find(reg);
            if (denseIndex != MicroDenseRegIndex::K_INVALID_INDEX && denseIndex < outBenefit.size())
                outBenefit[denseIndex] += weight;
        };

        for (const MicroReg reg : instructionUseDefs_[idx].uses)
            addAccess(reg);
        for (const MicroReg reg : instructionUseDefs_[idx].defs)
            addAccess(reg);
    }
}

bool MicroRegisterAllocationPass::intervalHasCall(const uint32_t lo, const uint32_t hi) const
{
    for (uint32_t idx = lo; idx <= hi && idx < instructionCount_; ++idx)
    {
        if (instructionUseDefs_[idx].isCall)
            return true;
    }

    return false;
}

bool MicroRegisterAllocationPass::intervalHasHotCall(const uint32_t lo, const uint32_t hi) const
{
    for (uint32_t idx = lo; idx <= hi && idx < instructionCount_; ++idx)
    {
        if (instructionUseDefs_[idx].isCall && (idx >= guardedCallPositions_.size() || !guardedCallPositions_[idx]))
            return true;
    }

    return false;
}

void MicroRegisterAllocationPass::computeGuardedCallPositions()
{
    // A call is guarded when a conditional jump before it targets a label
    // after it: the fall-through path steps over the call, which is the shape
    // of every compiler-emitted safety check (bounds, null, math) and of
    // hand-written error paths. Guarded calls are presumed cold.
    guardedCallPositions_.assign(instructionCount_, 0);
    if (!hasControlFlow_ || !instructionCount_)
        return;

    std::unordered_map<uint64_t, uint32_t> labelIndexByRef;
    uint32_t                               idx = 0;
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it, ++idx)
    {
        if (it->op != MicroInstrOpcode::Label)
            continue;
        const MicroInstrOperand* ops = it->ops(*operands_);
        if (ops)
            labelIndexByRef[ops[0].valueU64] = idx;
    }

    idx = 0;
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it, ++idx)
    {
        if (it->op != MicroInstrOpcode::JumpCond && it->op != MicroInstrOpcode::JumpCondImm)
            continue;
        if (MicroInstrInfo::isUnconditionalJumpInstruction(*it, it->ops(*operands_)))
            continue;

        const MicroInstrOperand* ops = it->ops(*operands_);
        if (!ops)
            continue;

        const auto targetIt = labelIndexByRef.find(ops[2].valueU64);
        if (targetIt == labelIndexByRef.end() || targetIt->second <= idx)
            continue;

        // Only a region that falls into the join right after its call is a
        // guard shadow: that is the emitted shape of a safety check (argument
        // loads, then the panic call, then the label the jump targets). A
        // then-block of an if/else ends with its own jump instead, and a
        // region with an interior label has other ways in â€” either could be
        // hot, so neither is marked.
        const uint32_t targetIdx     = targetIt->second;
        bool           regionIsGuard = targetIdx > idx + 1;
        uint32_t       inner         = idx + 1;
        for (auto innerIt = std::next(it); regionIsGuard && inner < targetIdx; ++innerIt, ++inner)
        {
            if (innerIt->op == MicroInstrOpcode::Label)
                regionIsGuard = false;
            else if (inner + 1 == targetIdx)
                regionIsGuard = instructionUseDefs_[inner].isCall;
            else if (MicroInstrInfo::isTerminatorInstruction(*innerIt))
                regionIsGuard = false;
        }

        if (!regionIsGuard)
            continue;

        for (inner = idx + 1; inner < targetIdx; ++inner)
        {
            if (instructionUseDefs_[inner].isCall)
                guardedCallPositions_[inner] = 1;
        }
    }

    // Second emitted shape: the hot path jumps OVER the panic block with an
    // unconditional jump, and the guards branch INTO it. The region between
    // that jump and its target starts with the panic label, ends with the
    // panic call, and falls into the join â€” same signature, different entry.
    idx = 0;
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it, ++idx)
    {
        if (!MicroInstrInfo::isUnconditionalJumpInstruction(*it, it->ops(*operands_)))
            continue;
        if (it->op != MicroInstrOpcode::JumpCond && it->op != MicroInstrOpcode::JumpCondImm)
            continue;

        const MicroInstrOperand* ops = it->ops(*operands_);
        if (!ops)
            continue;

        const auto targetIt = labelIndexByRef.find(ops[2].valueU64);
        if (targetIt == labelIndexByRef.end() || targetIt->second <= idx)
            continue;

        const uint32_t targetIdx     = targetIt->second;
        bool           regionIsGuard = targetIdx > idx + 2;
        uint32_t       inner         = idx + 1;
        for (auto innerIt = std::next(it); regionIsGuard && inner < targetIdx; ++innerIt, ++inner)
        {
            if (inner == idx + 1)
                regionIsGuard = innerIt->op == MicroInstrOpcode::Label;
            else if (innerIt->op == MicroInstrOpcode::Label)
                regionIsGuard = false;
            else if (inner + 1 == targetIdx)
                regionIsGuard = instructionUseDefs_[inner].isCall;
            else if (MicroInstrInfo::isTerminatorInstruction(*innerIt))
                regionIsGuard = false;
        }

        if (!regionIsGuard)
            continue;

        for (inner = idx + 2; inner < targetIdx; ++inner)
        {
            if (instructionUseDefs_[inner].isCall)
                guardedCallPositions_[inner] = 1;
        }
    }
}

bool MicroRegisterAllocationPass::concreteClaimsOverlap(const MicroReg physReg, const uint32_t lo, const uint32_t hi) const
{
    const uint32_t denseIndex = denseConcreteRegs_.find(physReg);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= concreteClaimPositionsByDenseIndex_.size())
        return false;

    const auto& positions = concreteClaimPositionsByDenseIndex_[denseIndex];
    const auto  it        = std::ranges::lower_bound(positions, lo);
    return it != positions.end() && *it <= hi;
}

bool MicroRegisterAllocationPass::isProvenFreeRegister(const MicroReg physReg) const
{
    // Named nowhere in the whole function: never an operand, never an ABI
    // shuffle, never a call clobber, never live as a concrete value. A clash
    // between a global reservation and the rest of allocation would need a
    // concrete claim on the register somewhere, and there are none â€” which
    // makes the absence of interference a property of the selection, not an
    // outcome to be defended by overlap checks on every path.
    const uint32_t denseIndex = denseConcreteRegs_.find(physReg);
    return denseIndex == MicroDenseRegIndex::K_INVALID_INDEX ||
           denseIndex >= concreteClaimPositionsByDenseIndex_.size() ||
           concreteClaimPositionsByDenseIndex_[denseIndex].empty();
}

bool MicroRegisterAllocationPass::hullConcreteClaimsBlock(const MicroReg physReg, const uint32_t lo, const uint32_t hi) const
{
    // Range-scoped variant of the proven-free rule, for the float class only.
    // A claim inside the hull blocks the register, with one exception: a call
    // that merely clobbers it. The value is parked in its slot around every
    // call inside its hull (saveRestorePinnedAcrossCall), so the clobber hits
    // a register whose value is safe in memory. A call that actually reads the
    // register â€” an argument, an indirect target â€” still blocks it, as does
    // any concrete contact outside a call. Claims outside the hull are the
    // local allocator's business: the reservation is range-scoped and the
    // value is dead there.
    const uint32_t denseIndex = denseConcreteRegs_.find(physReg);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= concreteClaimPositionsByDenseIndex_.size())
        return false;

    const auto& positions = concreteClaimPositionsByDenseIndex_[denseIndex];
    for (auto it = std::ranges::lower_bound(positions, lo); it != positions.end() && *it <= hi; ++it)
    {
        const uint32_t position = *it;
        if (position >= instructionUseDefs_.size())
            return true;

        const MicroInstrUseDef& useDef = instructionUseDefs_[position];
        if (!useDef.isCall)
            return true;
        if (containsKey(useDef.uses, physReg))
            return true;
    }

    return false;
}

bool MicroRegisterAllocationPass::isPinnedCallSavedOwner(const uint32_t denseIndex) const
{
    return std::ranges::find(pinnedCallSavedDense_, denseIndex) != pinnedCallSavedDense_.end();
}

bool MicroRegisterAllocationPass::globalRangesOverlap(const MicroReg physReg, const uint32_t lo, const uint32_t hi) const
{
    const uint32_t denseIndex = denseGlobalPhysRegs_.find(physReg);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= globalRangesByPhysDense_.size())
        return false;

    for (const GlobalRange& range : globalRangesByPhysDense_[denseIndex])
    {
        if (range.lo <= hi && lo <= range.hi)
            return true;
    }

    return false;
}

void MicroRegisterAllocationPass::addGlobalRange(const MicroReg physReg, const uint32_t lo, const uint32_t hi, const uint32_t ownerDense)
{
    const uint32_t denseIndex = denseGlobalPhysRegs_.ensure(physReg);
    if (denseIndex >= globalRangesByPhysDense_.size())
        globalRangesByPhysDense_.resize(denseIndex + 1);

    globalRangesByPhysDense_[denseIndex].push_back({.lo = lo, .hi = hi, .ownerDense = ownerDense});
}

bool MicroRegisterAllocationPass::isReservedByGlobalFor(const MicroReg virtKey, const MicroReg physReg, const uint32_t instructionIndex) const
{
    const uint32_t denseIndex = denseGlobalPhysRegs_.find(physReg);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= globalRangesByPhysDense_.size())
        return false;

    // The local allocator may take a globally reserved register only where the
    // value it wants to hold dies before the reservation begins. Its span hull
    // is the conservative end of that life.
    const uint32_t virtDense = denseVirtualIndex(virtKey);
    const uint32_t liveUntil = virtDense < virtualSpanHi_.size() ? std::max(virtualSpanHi_[virtDense], instructionIndex) : instructionCount_;

    for (const GlobalRange& range : globalRangesByPhysDense_[denseIndex])
    {
        if (range.lo <= liveUntil && instructionIndex <= range.hi)
            return true;
    }

    return false;
}

void MicroRegisterAllocationPass::assignGlobalRegisters()
{
    // Give every value that crosses a control-flow boundary one physical
    // register for the whole hull of its live range. That is what makes the
    // boundary flush vacuous: a value still live at a boundary is either a
    // global â€” which never enters the mapping, so the flush cannot touch it â€”
    // or one that failed to get a register and keeps the old memory home.
    //
    // Holding one register everywhere is also what lets this skip edge
    // resolution entirely. The usual cost of keeping values in registers across
    // a jump is reconciling the two sides of every edge, which needs critical
    // edges split and parallel copies emitted. Here both sides agree by
    // construction, because there is only ever one place the value lives.
    //
    // This is the whole difference from a whole-function reservation, which was
    // measured to lose: a register is only withheld from the local allocator
    // over the reserving value's own span, so the rest of the function still
    // has the full machine.
    //
    // Only proven-free registers â€” named nowhere in the function â€” may be
    // handed out. An earlier variant also granted registers with concrete
    // claims outside the hull, defended by overlap checks; every one of its
    // miscompiles came from a claim interaction those checks missed (a
    // back-edge, a later sweep, an ABI shuffle). Restricting the supply makes
    // that entire class of clash impossible instead of guarded against.
    if (!hasControlFlow_)
        return;

    // A whole-range reservation is only sound when the liveness underneath it is
    // exact, and the fixpoint is only exact when the CFG knows every edge. A
    // computed jump (JumpReg / JumpCondImm) or an unresolvable target leaves
    // successors incomplete, so live ranges come out too short and a hull would
    // free its register while the value is still needed. The local allocator
    // tolerates that imprecision â€” every boundary flush re-homes values in
    // memory â€” so only this mechanism has to stand down.
    SWC_ASSERT(controlFlowGraph_ != nullptr);
    if (controlFlowGraph_->hasUnsupportedControlFlowForCfgLiveness() || !controlFlowGraph_->supportsDeadCodeLiveness())
        return;

    // Only the sweep that allocates the whole function may reserve a register
    // for a value's entire live range. Legalizing this pass's own output
    // introduces fresh virtual scratch registers and sends the legalize/allocate
    // loop round again; that later sweep sees a function whose registers are
    // already committed, and its state carries no record of the reservations
    // made here. Handing one of those scratch values a whole-range register
    // silently overwrites a value the first sweep parked there. Later sweeps
    // fall back to purely local allocation, which is what they need anyway.
    if (!context_->isFirstAllocationSweep)
        return;

    computeConcreteClaimPositions();

    std::vector<uint64_t> benefits;
    computeGlobalBenefits(benefits);
    std::vector<uint64_t> accessBenefits;
    computeGlobalAccessBenefits(accessBenefits);

    // Fixed-point scale for the density ranking below, so the comparison
    // stays in integers.
    constexpr uint64_t K_DENSITY_SCALE = 1024;

    // How far below the best candidate a value may rank and still be granted a register the
    // function names elsewhere (the span-scoped path further down). Measured on bench/: without a
    // bound the extra supply reached every candidate that earns anything at all, and the local
    // allocator pressure that caused cost more than the reservations returned - sha256 and leven
    // each lost 7%. Bounding it kept their gains and left wordfreq and csvagg's intact.
    constexpr uint64_t K_SPAN_SCOPED_DENSITY_DIVISOR = 2;

    struct GlobalCandidate
    {
        uint32_t denseIndex    = 0;
        uint64_t density       = 0;
        uint64_t rawBenefit    = 0;
        uint64_t accessBenefit = 0;
    };
    SmallVector<GlobalCandidate> candidates;

    const auto& vregs = denseVirtualRegs_.regs();
    for (uint32_t denseIndex = 0; denseIndex < vregs.size(); ++denseIndex)
    {
        if (!vregs[denseIndex].isVirtual() || !benefits[denseIndex])
            continue;
        if (virtualSpanLo_[denseIndex] > virtualSpanHi_[denseIndex])
            continue;

        // Density remains the admission threshold for span-scoped registers.
        // A register is held for the whole hull, holes included, so a value
        // that crosses many boundaries while spread over the entire function
        // can otherwise deny the local allocator a register everywhere in
        // exchange for savings in one place.
        const uint64_t spanLength = virtualSpanHi_[denseIndex] - virtualSpanLo_[denseIndex] + 1;
        const uint64_t density    = benefits[denseIndex] * K_DENSITY_SCALE / spanLength;
        if (!density)
            continue;

        candidates.push_back({
            .denseIndex    = denseIndex,
            .density       = density,
            .rawBenefit    = benefits[denseIndex],
            .accessBenefit = accessBenefits[denseIndex],
        });
    }
    if (candidates.empty())
        return;

    // Grant the scarce carriers to values accessed most often in the hottest
    // loops. Density breaks ties without pushing long-lived cursors behind
    // short-lived values that are merely carried across the same back-edge.
    std::ranges::stable_sort(candidates, [](const GlobalCandidate& a, const GlobalCandidate& b) {
        if (a.accessBenefit != b.accessBenefit)
            return a.accessBenefit > b.accessBenefit;
        return a.density > b.density;
    });

    // Supply and budget are two different things. Widening which registers may be granted (below)
    // is worth it for the values that dominate a hot loop; handing one to every candidate that
    // merely earns something starves the local allocator instead, because a hull holds its
    // register across its holes as well.
    const auto     maxDensityIt         = std::ranges::max_element(candidates, {}, &GlobalCandidate::density);
    const uint64_t spanScopedMinDensity = maxDensityIt->density / K_SPAN_SCOPED_DENSITY_DIVISOR;

    // The local allocator must keep enough of each class to satisfy the worst
    // single instruction â€” its register operands plus what a destructive
    // lowering needs â€” because it cannot spill its way out of an empty pool:
    // it reports an internal error. The floor differs per class: the worst int
    // instruction names four registers and destructive lowerings add three,
    // while the widest float shape is the ternary multiply-add (three
    // registers) plus one legalization scratch. A single shared floor sized
    // for ints would exclude the whole float class, whose pool is smaller
    // than that floor. A function with calls additionally needs callee-saved
    // registers left for its own values live across one.
    constexpr uint32_t K_MIN_FREE_INT_CLASS   = 7;
    constexpr uint32_t K_MIN_FREE_FLOAT_CLASS = 4;
    // Callee-saved registers kept out of the hulls for the local allocator's
    // own call-crossing values. Ints need two: their first allocation sweep
    // has no other escape hatch, and one proved insolvent. Floats make do
    // with one â€” they fall back to caller-saved registers spilled around
    // calls, and allocatePhysical has a last-resort valve into the
    // nonvolatile pool.
    constexpr uint32_t K_MIN_FREE_PERSISTENT_INT   = 2;
    constexpr uint32_t K_MIN_FREE_PERSISTENT_FLOAT = 1;

    const bool            hasCalls = functionHasCalls();
    std::vector<uint32_t> reservedInt(instructionCount_, 0);
    std::vector<uint32_t> reservedFloat(instructionCount_, 0);
    std::vector<uint32_t> reservedIntPersistent(instructionCount_, 0);
    std::vector<uint32_t> reservedFloatPersistent(instructionCount_, 0);

    const size_t totalInt         = freeIntPersistent_.size() + freeIntTransient_.size();
    const size_t totalFloat       = freeFloatPersistent_.size() + freeFloatTransient_.size();
    const size_t totalIntPersist  = freeIntPersistent_.size();
    const size_t totalFloatPersit = freeFloatPersistent_.size();

    for (const GlobalCandidate& cand : candidates)
    {
        const MicroReg vreg    = vregs[cand.denseIndex];
        const bool     isFloat = vreg.isVirtualFloat();
        const uint32_t lo      = virtualSpanLo_[cand.denseIndex];
        const uint32_t hi      = std::min(virtualSpanHi_[cand.denseIndex], instructionCount_ ? instructionCount_ - 1 : 0);

        // The ABI keeps one callee-saved register outside both allocation
        // pools specifically for the local-stack base. Put that value in its
        // dedicated register instead of consuming one of the general global
        // carriers while the dedicated register sits idle.
        const MicroReg localStackBaseReg = conv_->preferredLocalStackBaseReg();
        const bool     isLocalStackBase  = context_->debugStackBaseVirtualReg.isValid() &&
                                      vreg == context_->debugStackBaseVirtualReg;
        if (isLocalStackBase &&
            localStackBaseReg.isValid() &&
            !isPhysRegForbiddenForVirtual(vreg, localStackBaseReg) &&
            !concreteClaimsOverlap(localStackBaseReg, lo, hi) &&
            !globalRangesOverlap(localStackBaseReg, lo, hi))
        {
            addGlobalRange(localStackBaseReg, lo, hi, cand.denseIndex);
            appendUniqueReg(context_->globalReservedRegs, localStackBaseReg);

            auto& regState                  = states_[cand.denseIndex];
            regState.pinned                 = true;
            regState.mapped                 = false;
            regState.phys                   = localStackBaseReg;
            context_->debugStackBasePhysReg = localStackBaseReg;
            continue;
        }

        std::vector<uint32_t>& reserved           = isFloat ? reservedFloat : reservedInt;
        std::vector<uint32_t>& reservedPersistent = isFloat ? reservedFloatPersistent : reservedIntPersistent;
        const size_t           total              = isFloat ? freeFloatTransient_.size() : totalInt;
        const size_t           totalPersistent    = isFloat ? totalFloatPersit : totalIntPersist;
        const uint32_t         minFreeClass       = isFloat ? K_MIN_FREE_FLOAT_CLASS : K_MIN_FREE_INT_CLASS;

        // A hull crossing a call that actually runs prefers a callee-saved
        // register; one whose calls are all guard-shadowed prefers a
        // caller-saved register, whose parking cost runs only if a guard
        // fires â€” a callee-saved save/restore would run on every entry. A
        // caller-saved pick crossing any call parks the value in its slot for
        // the call's duration (saveRestorePinnedAcrossCall).
        const bool crossesCall     = intervalHasCall(lo, hi);
        const bool needsPersistent = isFloat ? intervalHasHotCall(lo, hi) : crossesCall;

        // Headroom is accounted per pool, not per class. The caller-saved
        // budget protects the local allocator's scratch supply â€” every
        // transient hull is one fewer register for straight-line code. The
        // callee-saved budget only has to keep the escape-hatch floor free:
        // a persistent hull costs one prologue save, it does not starve the
        // scratch pool. Folding both pools under the transient floor capped
        // the whole float class at two carriers while ten callee-saved
        // registers sat idle, which is exactly the boundary flush this
        // mechanism exists to remove.
        const uint32_t transientBudget  = total > minFreeClass ? static_cast<uint32_t>(total - minFreeClass) : 0u;
        const uint32_t persistentBudget = totalPersistent > K_MIN_FREE_PERSISTENT_FLOAT ? static_cast<uint32_t>(totalPersistent - K_MIN_FREE_PERSISTENT_FLOAT) : 0u;

        uint32_t transientHeadroom  = transientBudget;
        uint32_t persistentHeadroom = persistentBudget;
        if (isFloat)
        {
            // Guard-shadowed call crossings never take a persistent register
            // (the prologue save would run on every entry for a cold path).
            if (crossesCall && !needsPersistent)
                persistentHeadroom = 0;
            for (uint32_t idx = lo; idx <= hi; ++idx)
            {
                const uint32_t persistentUsed = reservedPersistent[idx];
                const uint32_t transientUsed  = reserved[idx] - std::min(reserved[idx], persistentUsed);
                transientHeadroom             = std::min(transientHeadroom, transientBudget - std::min(transientUsed, transientBudget));
                persistentHeadroom            = std::min(persistentHeadroom, persistentBudget - std::min(persistentUsed, persistentBudget));
            }
            if (!transientHeadroom && !persistentHeadroom)
                continue;
        }
        else
        {
            if (total <= minFreeClass)
                continue;

            uint32_t headroom = std::numeric_limits<uint32_t>::max();
            for (uint32_t idx = lo; idx <= hi; ++idx)
                headroom = std::min(headroom, transientBudget - std::min(reserved[idx], transientBudget));
            if (!headroom)
                continue;
        }

        // Both pools must come from setupPools, never from the calling
        // convention's raw lists: those still contain the frame pointer and the
        // local stack base, and handing either to a value is a crash, not a
        // slowdown. A value not crossing a call is offered caller-saved
        // registers first, so it does not force a prologue push.
        const SmallVector<MicroReg>& persistentPool = isFloat ? freeFloatPersistent_ : freeIntPersistent_;
        const SmallVector<MicroReg>& transientPool  = isFloat ? freeFloatTransient_ : freeIntTransient_;

        MicroReg picked = MicroReg::invalid();
        for (int pass = 0; pass < 2 && !picked.isValid(); ++pass)
        {
            // A value not crossing a call is offered caller-saved registers
            // first, so it does not force a prologue push for nothing. One
            // crossing a hot call prefers callee-saved, and falls back to
            // caller-saved with call-site parking. One crossing only guarded
            // calls takes caller-saved with parking or nothing: promoting the
            // overflow to callee-saved was measured to lose â€” the prologue
            // save/restore runs on every entry of a hot small function, while
            // the memory home it replaces was only touched a few times per
            // iteration.
            if (pass == 1 && isFloat && !needsPersistent && crossesCall)
                break;
            // A float hull prefers a callee-saved register even without a call
            // in its span: the caller-saved pool doubles as the local
            // allocator's scratch supply, and a hull parked there starves the
            // straight-line code inside the very loop the hull serves. The
            // prologue save it costs runs once per entry; the scratch register
            // it frees pays on every iteration. Only guard-shadowed call
            // crossings stay caller-saved (their parking is free until a
            // guard fires, while a prologue save would run every entry).
            const bool preferPersistent = isFloat ? (needsPersistent || !crossesCall) : needsPersistent;

            const SmallVector<MicroReg>& pool             = preferPersistent == (pass == 0) ? persistentPool : transientPool;
            const bool                   poolIsPersistent = &pool == &persistentPool;
            if (isFloat && (poolIsPersistent ? !persistentHeadroom : !transientHeadroom))
                continue;
            for (const MicroReg reg : pool)
            {
                // Int hulls take only proven-free registers: later legalize
                // sweeps conjure fixed int registers (shift counts, division
                // pairs) that no claim check at grant time can see. Float
                // shapes have no late fixed-register lowerings â€” their only
                // concrete contacts are ABI moves and call clobbers, both in
                // the stream already â€” so a claim check scoped to the hull is
                // sound for them, and it is what lets a float hull take a
                // caller-saved register at all: in a function with any call,
                // every volatile float register carries clobber claims
                // somewhere.
                if (isFloat)
                {
                    if (hullConcreteClaimsBlock(reg, lo, hi))
                        continue;
                }
                else if (isProvenFreeRegister(reg))
                {
                    SWC_ASSERT(!concreteClaimsOverlap(reg, lo, hi));
                }
                else
                {
                    // A register the function names elsewhere may still be granted, on the same
                    // terms the float class already uses: a claim check scoped to the hull. What
                    // made that unsound for ints is that legalization can still demand a fixed
                    // register after allocation, announced by nothing visible here - so the
                    // registers it can demand are excluded, and only those.
                    //
                    // A hull crossing a call may only ride a callee-saved register: the call
                    // preserves it, so the clobber argument that bars caller-saved picks does
                    // not apply. Refusing call-crossing hulls outright instead - which is what
                    // a single call anywhere in the function used to do - kept a parse loop's
                    // base pointers reloading from their stack homes on every byte scanned,
                    // because the one call per parsed record poisoned every hull in the loop.
                    // The density gate protects the caller-saved scratch supply, so it
                    // only applies to caller-saved picks. A callee-saved pick costs one
                    // prologue push however long the hull is, which an absolute benefit
                    // floor covers: the value must cross at least one inner-loop
                    // boundary (or a depth-one boundary ten times over). Density would
                    // veto exactly the values this path exists for â€” a parse loop's
                    // base pointers live across the whole function, whose density is
                    // microscopic while their reload count is millions.
                    // 100 = one depth-two boundary crossing under computeGlobalBenefits'
                    // order-of-magnitude-per-level weighting.
                    constexpr uint64_t K_PERSISTENT_MIN_RAW_BENEFIT = 100;

                    const bool persistentPick  = isPersistentPhysReg(reg);
                    const bool benefitClears   = persistentPick ? cand.rawBenefit >= K_PERSISTENT_MIN_RAW_BENEFIT
                                                                : cand.density >= spanScopedMinDensity;
                    const bool spanScopedGrant = benefitClears &&
                                                 (!crossesCall || persistentPick) &&
                                                 context_->encoder &&
                                                 !context_->encoder->mayDemandFixedRegisterLate(reg) &&
                                                 !hullConcreteClaimsBlock(reg, lo, hi);
                    if (!spanScopedGrant)
                        continue;
                }
                if (isPhysRegForbiddenForVirtual(vreg, reg))
                    continue;
                if (globalRangesOverlap(reg, lo, hi))
                    continue;

                const bool     isPersistent      = isPersistentPhysReg(reg);
                const uint32_t minFreePersistent = isFloat ? K_MIN_FREE_PERSISTENT_FLOAT : K_MIN_FREE_PERSISTENT_INT;
                if (hasCalls && isPersistent && totalPersistent <= minFreePersistent)
                    continue;

                if (hasCalls && isPersistent)
                {
                    const uint32_t cap  = static_cast<uint32_t>(totalPersistent - minFreePersistent);
                    bool           fits = true;
                    for (uint32_t idx = lo; idx <= hi && fits; ++idx)
                        fits = reservedPersistent[idx] < cap;
                    if (!fits)
                        continue;
                }

                // The per-index floors above bound how many reservations overlap any
                // one instruction, but reservations on disjoint ranges can still land
                // on distinct registers until every register of the class carries one
                // somewhere. A value whose own span covers the whole function is then
                // vetoed on all of them at once and the local allocator has nowhere
                // left to put it â€” it reports an internal error, it cannot spill its
                // way out. So the floors must also hold function-wide: keep the
                // class floor's worth of registers (and the per-class persistent
                // floor's worth of callee-saved ones) carrying no reservation at all. Registers that
                // already hold one may keep stacking disjoint hulls freely.
                const uint32_t regDense      = denseGlobalPhysRegs_.find(reg);
                const bool     carriesRanges = regDense != MicroDenseRegIndex::K_INVALID_INDEX &&
                                           regDense < globalRangesByPhysDense_.size() &&
                                           !globalRangesByPhysDense_[regDense].empty();
                if (!carriesRanges)
                {
                    uint32_t distinctClass      = 0;
                    uint32_t distinctPersistent = 0;
                    for (const MicroReg used : context_->globalReservedRegs)
                    {
                        if (used.isFloat() != isFloat)
                            continue;
                        ++distinctClass;
                        if (isPersistentPhysReg(used))
                            ++distinctPersistent;
                    }

                    // The function-wide floor mirrors the per-index one: per
                    // pool for floats, per class for ints.
                    if (isFloat)
                    {
                        const uint32_t distinctTransient = distinctClass - std::min(distinctClass, distinctPersistent);
                        if (isPersistent ? distinctPersistent >= persistentBudget : distinctTransient >= transientBudget)
                            continue;
                    }
                    else if (distinctClass >= static_cast<uint32_t>(total - minFreeClass))
                    {
                        continue;
                    }
                    if (hasCalls && isPersistent &&
                        distinctPersistent >= static_cast<uint32_t>(totalPersistent - minFreePersistent))
                        continue;
                }

                picked = reg;
                break;
            }
        }
        if (!picked.isValid())
            continue;

        addGlobalRange(picked, lo, hi, cand.denseIndex);
        appendUniqueReg(context_->globalReservedRegs, picked);
        for (uint32_t idx = lo; idx <= hi; ++idx)
        {
            ++reserved[idx];
            if (isPersistentPhysReg(picked))
                ++reservedPersistent[idx];
        }

        auto& regState  = states_[cand.denseIndex];
        regState.pinned = true;
        regState.mapped = false; // never tracked by the spill machinery
        regState.phys   = picked;

        // A caller-saved register does not survive the calls inside the hull on
        // its own: give the value a slot now, and rewriteInstructions parks it
        // there for exactly the duration of each such call.
        if (crossesCall && !isPersistentPhysReg(picked))
        {
            ensureSpillSlot(regState, isFloat);
            pinnedCallSavedDense_.push_back(cand.denseIndex);
        }

        // Globals bypass mapVirtReg, so capture the debug local-stack base here
        // too: it is a boundary-crossing value like any other, and without this
        // every local and parameter would be dropped from the debug info.
        if (context_->debugStackBaseVirtualReg.isValid() && vreg == context_->debugStackBaseVirtualReg && !context_->debugStackBasePhysReg.isValid())
            context_->debugStackBasePhysReg = picked;
    }
}

void MicroRegisterAllocationPass::preallocateLoopCarriedSlots()
{
    // A virtual register whose value is live-in at a loop header crosses the
    // back-edge. Unless it was given a global register (assignGlobalRegisters), the
    // linear scan round-trips it through memory at the loop's control-flow
    // boundaries: it is reloaded at the header and re-spilled at the back-edge
    // tail. Spill slots are otherwise allocated lazily, so the header reload and
    // the tail store can end up resolving to *different* slots â€” the home drifts
    // across the back-edge and the carried value (e.g. a reduction accumulator)
    // is silently lost.
    //
    // Fix the home up front: give every non-pinned loop-carried value one stable
    // slot before allocation begins, so every reload, every spill, and the
    // boundary flush all target the same memory location. This degrades a
    // non-pinned loop-carried value to consistent memory residence (identical to
    // how it behaved before mem2reg promoted it); pinned values keep the register
    // fast path. Rematerialization is left untouched: the existing multi-def
    // guard already forbids rematerializing a value redefined across the loop,
    // while a single-def loop-invariant constant must stay rematerializable.
    if (!hasControlFlow_ || instructionCount_ == 0)
        return;

    const auto&    vregs     = denseVirtualRegs_.regs();
    const uint32_t wordCount = denseVirtualRegs_.wordCount();

    SmallVector<uint32_t> loopHeaders;
    for (uint32_t s = 0; s < instructionCount_; ++s)
    {
        for (const uint32_t p : predecessors_[s])
        {
            if (p >= s)
            {
                loopHeaders.push_back(s);
                break;
            }
        }
    }
    if (loopHeaders.empty())
        return;

    for (uint32_t denseIndex = 0; denseIndex < vregs.size(); ++denseIndex)
    {
        const MicroReg vreg = vregs[denseIndex];
        if (!vreg.isVirtual())
            continue;

        auto& regState = states_[denseIndex];
        if (regState.pinned)
            continue;

        bool loopCarried = false;
        for (const uint32_t header : loopHeaders)
        {
            const std::span<const uint64_t> liveRow = DenseBits::row(liveInVirtualBits_, header, wordCount);
            if (DenseBits::contains(liveRow, denseIndex))
            {
                loopCarried = true;
                break;
            }
        }
        if (!loopCarried)
            continue;

        regState.loopCarriedHome = true;
        ensureSpillSlot(regState, vreg.isVirtualFloat());
    }
}

uint32_t MicroRegisterAllocationPass::distanceToNextUse(MicroReg key, uint32_t instructionIndex) const
{
    const uint32_t denseIndex = denseVirtualRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= usePositionsByDenseVirtual_.size())
        return std::numeric_limits<uint32_t>::max();

    const auto& positions = usePositionsByDenseVirtual_[denseIndex];
    auto        cursor    = nextUsePositionCursor_[denseIndex];
    advancePositionCursor(cursor, positions, instructionIndex);
    if (cursor >= positions.size())
        return std::numeric_limits<uint32_t>::max();

    return positions[cursor] - instructionIndex;
}

void MicroRegisterAllocationPass::advanceCurrentPositionCursors(const uint32_t instructionIndex)
{
    for (const uint32_t denseIndex : useVirtualIndices_[instructionIndex])
    {
        SWC_ASSERT(denseIndex < usePositionsByDenseVirtual_.size());
        advancePositionCursor(nextUsePositionCursor_[denseIndex], usePositionsByDenseVirtual_[denseIndex], instructionIndex);
    }

    for (const uint32_t denseIndex : useConcreteIndices_[instructionIndex])
    {
        SWC_ASSERT(denseIndex < concreteTouchPositionsByDenseIndex_.size());
        advancePositionCursor(nextConcreteTouchCursor_[denseIndex], concreteTouchPositionsByDenseIndex_[denseIndex], instructionIndex);
    }

    for (const uint32_t denseIndex : defConcreteIndices_[instructionIndex])
    {
        SWC_ASSERT(denseIndex < concreteTouchPositionsByDenseIndex_.size());
        advancePositionCursor(nextConcreteTouchCursor_[denseIndex], concreteTouchPositionsByDenseIndex_[denseIndex], instructionIndex);
    }
}

bool MicroRegisterAllocationPass::canEraseCoalescedCopy(const MicroInstrRef copyRef, const MicroReg dstReg) const
{
    if (copyRef.isInvalid())
        return false;

    auto it = instructions_->view().begin();
    while (it != instructions_->view().end() && it.current != copyRef)
        ++it;
    if (it == instructions_->view().end())
        return false;

    ++it;
    for (; it != instructions_->view().end(); ++it)
    {
        const MicroInstrUseDef useDef = it->collectUseDef(*operands_, context_->encoder);
        if (containsKey(useDef.uses, dstReg))
            return false;
        if (containsKey(useDef.defs, dstReg))
            return true;
        if (!MicroInstrInfo::isLocalDataflowBarrier(*it, useDef))
            continue;

        return it->op == MicroInstrOpcode::Ret;
    }

    return true;
}

void MicroRegisterAllocationPass::prepareInstructionData()
{
    controlFlowGraph_                                    = &((context_->builder)->controlFlowGraph());
    const std::span<const MicroInstrRef> instructionRefs = controlFlowGraph_->instructionRefs();
    SWC_ASSERT(instructionRefs.size() == instructionCount_);
    if (instructionRefs.size() != instructionCount_)
        return;

    bool hasVirtual = false;
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        const MicroInstr* inst = instructions_->ptr(instructionRefs[idx]);
        if (!inst)
            continue;

        MicroInstrUseDef useDef = inst->collectUseDef(*operands_, context_->encoder);
        for (const MicroReg reg : useDef.uses)
        {
            if (!reg.isVirtual())
                continue;

            hasVirtual = true;
        }

        for (const MicroReg reg : useDef.defs)
        {
            if (reg.isVirtual())
                hasVirtual = true;
        }

        instructionUseDefs_[idx] = std::move(useDef);
    }

    hasVirtualRegs_       = hasVirtual;
    context_->passChanged = context_->passChanged || hasVirtual;
}

void MicroRegisterAllocationPass::analyzeLiveness()
{
    // CFG-aware backward liveness: captures live-out sets even across back-edges.
    if (!instructionCount_)
        return;

    SWC_ASSERT(controlFlowGraph_ != nullptr);
    const MicroControlFlowGraph&         controlFlowGraph = *controlFlowGraph_;
    const std::span<const MicroInstrRef> instructionRefs  = controlFlowGraph.instructionRefs();
    SWC_ASSERT(instructionRefs.size() == instructionCount_);
    if (instructionRefs.size() != instructionCount_)
        return;

    const size_t denseReserve = static_cast<size_t>(instructionCount_) * 2ull + 8ull;
    denseVirtualRegs_.clear();
    denseConcreteRegs_.clear();
    denseVirtualRegs_.reserve(denseReserve);
    denseConcreteRegs_.reserve(denseReserve);

    useVirtualIndices_.resize(instructionCount_);
    defVirtualIndices_.resize(instructionCount_);
    useConcreteIndices_.resize(instructionCount_);
    defConcreteIndices_.resize(instructionCount_);

    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        const MicroInstrUseDef& useDef = instructionUseDefs_[idx];
        auto&                   usesV  = useVirtualIndices_[idx];
        auto&                   defsV  = defVirtualIndices_[idx];
        auto&                   usesC  = useConcreteIndices_[idx];
        auto&                   defsC  = defConcreteIndices_[idx];
        usesV.clear();
        defsV.clear();
        usesC.clear();
        defsC.clear();

        for (const MicroReg reg : useDef.uses)
        {
            if (reg.isVirtual())
            {
                const uint32_t regIndex = denseVirtualRegs_.ensure(reg);
                appendUniqueDenseIndex(usesV, regIndex);
            }
            else if (reg.isInt() || reg.isFloat())
            {
                const uint32_t regIndex = denseConcreteRegs_.ensure(reg);
                appendUniqueDenseIndex(usesC, regIndex);
            }
        }

        for (const MicroReg reg : useDef.defs)
        {
            if (reg.isVirtual())
            {
                const uint32_t regIndex = denseVirtualRegs_.ensure(reg);
                appendUniqueDenseIndex(defsV, regIndex);
            }
            else if (reg.isInt() || reg.isFloat())
            {
                const uint32_t regIndex = denseConcreteRegs_.ensure(reg);
                appendUniqueDenseIndex(defsC, regIndex);
            }
        }

        if (useDef.isCall)
        {
            const CallConv& callConv = CallConv::get(useDef.callConv);
            for (const MicroReg reg : callConv.intTransientRegs)
            {
                const uint32_t regIndex = denseConcreteRegs_.ensure(reg);
                appendUniqueDenseIndex(defsC, regIndex);
            }
            for (const MicroReg reg : callConv.floatTransientRegs)
            {
                const uint32_t regIndex = denseConcreteRegs_.ensure(reg);
                appendUniqueDenseIndex(defsC, regIndex);
            }
        }
    }

    const uint32_t virtualWordCount  = denseVirtualRegs_.wordCount();
    const uint32_t concreteWordCount = denseConcreteRegs_.wordCount();
    const auto&    virtualRegs       = denseVirtualRegs_.regs();
    const auto&    concreteRegs      = denseConcreteRegs_.regs();

    states_.clear();
    states_.resize(virtualRegs.size());
    usePositionsByDenseVirtual_.clear();
    usePositionsByDenseVirtual_.resize(virtualRegs.size());
    concreteTouchPositionsByDenseIndex_.clear();
    concreteTouchPositionsByDenseIndex_.resize(concreteRegs.size());
    definitionCounts_.assign(virtualRegs.size(), 0);

    // Size each float value's spill slot from the widest operand that ever names
    // it. Sizing every one of them for a vector is safe â€” a float register can
    // hold 128 bits â€” and it is what this pass used to do, but it makes a scalar
    // double pay a 16-byte movdqu and 16 bytes of frame for eight bytes of
    // value, on every spill and every reload. An instruction carrying a 128-bit
    // operand marks everything it names as wide; anything else is a scalar.
    uint32_t wideScanIndex = 0;
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && wideScanIndex < instructionCount_; ++it, ++wideScanIndex)
    {
        const MicroInstrOperand* ops = it->ops(*operands_);

        bool wide = false;
        for (uint8_t opIndex = 0; opIndex < it->numOperands && !wide; ++opIndex)
            wide = ops[opIndex].opBits == MicroOpBits::B128;
        if (!wide)
            continue;

        for (const uint32_t denseIndex : useVirtualIndices_[wideScanIndex])
            states_[denseIndex].wideFloat = true;
        for (const uint32_t denseIndex : defVirtualIndices_[wideScanIndex])
            states_[denseIndex].wideFloat = true;
    }

    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        for (const uint32_t denseIndex : useVirtualIndices_[idx])
        {
            SWC_ASSERT(denseIndex < usePositionsByDenseVirtual_.size());
            appendUniquePosition(usePositionsByDenseVirtual_[denseIndex], idx);
        }

        for (const uint32_t denseIndex : defVirtualIndices_[idx])
        {
            SWC_ASSERT(denseIndex < definitionCounts_.size());
            definitionCounts_[denseIndex]++;
        }

        for (const uint32_t denseIndex : useConcreteIndices_[idx])
        {
            SWC_ASSERT(denseIndex < concreteTouchPositionsByDenseIndex_.size());
            appendUniquePosition(concreteTouchPositionsByDenseIndex_[denseIndex], idx);
        }

        for (const uint32_t denseIndex : defConcreteIndices_[idx])
        {
            SWC_ASSERT(denseIndex < concreteTouchPositionsByDenseIndex_.size());
            appendUniquePosition(concreteTouchPositionsByDenseIndex_[denseIndex], idx);
        }
    }

    nextUsePositionCursor_.assign(virtualRegs.size(), 0);
    nextConcreteTouchCursor_.assign(concreteRegs.size(), 0);
    liveStampByDenseIndex_.assign(virtualRegs.size(), 0);
    vregsLiveAcrossCall_.assign(virtualRegs.size(), 0);
    vregsLiveAcrossHotCall_.assign(virtualRegs.size(), 0);
    callSpillFlags_.assign(virtualRegs.size(), 0);
    mappedVirtualIndices_.clear();
    mappedVirtualIndices_.reserve(virtualRegs.size());
    currentConcreteLiveOut_.clear();

    liveInVirtualBits_.assign(static_cast<size_t>(instructionCount_) * virtualWordCount, 0);
    liveInConcreteBits_.assign(static_cast<size_t>(instructionCount_) * concreteWordCount, 0);

    // Clear every row before pushing any edge: clearing inside the push loop
    // wipes the forward edges lower-indexed instructions already recorded, which
    // leaves only back-edges in the lists. The liveness worklist then never
    // reprocesses an instruction after its layout successor changes, and the
    // fixpoint silently under-approximates around nested loops.
    predecessors_.resize(instructionCount_);
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
        predecessors_[idx].clear();

    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        const auto& successors = controlFlowGraph.successors(idx);
        for (const uint32_t succIdx : successors)
        {
            if (succIdx >= instructionCount_)
                continue;
            predecessors_[succIdx].push_back(idx);
        }
    }

    computeReachability();
    computeLoopDepth();

    worklist_.clear();
    worklist_.reserve(instructionCount_);
    inWorklist_.assign(instructionCount_, 0);
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        worklist_.push_back(idx);
        inWorklist_[idx] = 1;
    }

    tempOutVirtual_.assign(virtualWordCount, 0);
    tempInVirtual_.assign(virtualWordCount, 0);
    tempOutConcrete_.assign(concreteWordCount, 0);
    tempInConcrete_.assign(concreteWordCount, 0);

    while (!worklist_.empty())
    {
        const uint32_t instructionIndex = worklist_.back();
        worklist_.pop_back();
        inWorklist_[instructionIndex] = 0;

        for (uint64_t& value : tempOutVirtual_)
            value = 0;
        for (uint64_t& value : tempOutConcrete_)
            value = 0;

        const auto& successors = controlFlowGraph.successors(instructionIndex);
        for (const uint32_t succIdx : successors)
        {
            if (succIdx >= instructionCount_)
                continue;

            const std::span<const uint64_t> succInVirtual  = DenseBits::row(liveInVirtualBits_, succIdx, virtualWordCount);
            const std::span<const uint64_t> succInConcrete = DenseBits::row(liveInConcreteBits_, succIdx, concreteWordCount);
            for (size_t word = 0; word < tempOutVirtual_.size(); ++word)
                tempOutVirtual_[word] |= succInVirtual[word];
            for (size_t word = 0; word < tempOutConcrete_.size(); ++word)
                tempOutConcrete_[word] |= succInConcrete[word];
        }

        tempInVirtual_  = tempOutVirtual_;
        tempInConcrete_ = tempOutConcrete_;
        {
            const std::span inVirtual = tempInVirtual_;
            for (const uint32_t bitIndex : defVirtualIndices_[instructionIndex])
                DenseBits::clear(inVirtual, bitIndex);
            for (const uint32_t bitIndex : useVirtualIndices_[instructionIndex])
                DenseBits::set(inVirtual, bitIndex);
        }
        {
            const std::span inConcrete = tempInConcrete_;
            for (const uint32_t bitIndex : defConcreteIndices_[instructionIndex])
                DenseBits::clear(inConcrete, bitIndex);
            for (const uint32_t bitIndex : useConcreteIndices_[instructionIndex])
                DenseBits::set(inConcrete, bitIndex);
        }

        const bool changedVirtual  = DenseBits::copyIfChanged(DenseBits::row(liveInVirtualBits_, instructionIndex, virtualWordCount), tempInVirtual_);
        const bool changedConcrete = DenseBits::copyIfChanged(DenseBits::row(liveInConcreteBits_, instructionIndex, concreteWordCount), tempInConcrete_);
        if (!changedVirtual && !changedConcrete)
            continue;

        for (const uint32_t predIdx : predecessors_[instructionIndex])
        {
            if (inWorklist_[predIdx])
                continue;

            worklist_.push_back(predIdx);
            inWorklist_[predIdx] = 1;
        }
    }

    computeConcreteLoopCarried();

    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        for (uint64_t& value : tempOutVirtual_)
            value = 0;
        for (uint64_t& value : tempOutConcrete_)
            value = 0;

        const auto& successors = controlFlowGraph.successors(idx);
        for (const uint32_t succIdx : successors)
        {
            if (succIdx >= instructionCount_)
                continue;

            const std::span<const uint64_t> succInVirtual  = DenseBits::row(liveInVirtualBits_, succIdx, virtualWordCount);
            const std::span<const uint64_t> succInConcrete = DenseBits::row(liveInConcreteBits_, succIdx, concreteWordCount);
            for (size_t word = 0; word < tempOutVirtual_.size(); ++word)
                tempOutVirtual_[word] |= succInVirtual[word];
            for (size_t word = 0; word < tempOutConcrete_.size(); ++word)
                tempOutConcrete_[word] |= succInConcrete[word];
        }

        if (!instructionUseDefs_[idx].isCall)
            continue;

        for (size_t wordIndex = 0; wordIndex < tempOutVirtual_.size(); ++wordIndex)
        {
            uint64_t wordBits = tempOutVirtual_[wordIndex];
            while (wordBits)
            {
                const uint32_t bitInWord = std::countr_zero(wordBits);
                const size_t   bitIndex  = wordIndex * 64ull + bitInWord;
                if (bitIndex >= virtualRegs.size())
                    break;
                vregsLiveAcrossCall_[bitIndex] = 1;
                if (idx >= guardedCallPositions_.size() || !guardedCallPositions_[idx])
                {
                    // Weight one flat crossing per call, and any in-loop call
                    // enough to dominate: the count decides below whether a
                    // callee-saved register amortizes its prologue traffic.
                    const uint32_t depth              = idx < loopDepth_.size() ? loopDepth_[idx] : 0u;
                    const uint32_t weight             = depth ? 10u : 1u;
                    const uint32_t current            = vregsLiveAcrossHotCall_[bitIndex];
                    vregsLiveAcrossHotCall_[bitIndex] = static_cast<uint8_t>(std::min<uint32_t>(current + weight, 255u));
                }
                wordBits &= (wordBits - 1ull);
            }
        }
    }
}

void MicroRegisterAllocationPass::computeReachability()
{
    reachableInstructions_.assign(instructionCount_, 0);
    if (!instructionCount_ || controlFlowGraph_ == nullptr)
        return;

    SmallVector<uint32_t> pending;
    pending.push_back(0);
    reachableInstructions_[0] = 1;

    while (!pending.empty())
    {
        const uint32_t instructionIndex = pending.back();
        pending.pop_back();

        for (const uint32_t succIdx : controlFlowGraph_->successors(instructionIndex))
        {
            if (succIdx >= instructionCount_ || reachableInstructions_[succIdx])
                continue;

            reachableInstructions_[succIdx] = 1;
            pending.push_back(succIdx);
        }
    }
}

void MicroRegisterAllocationPass::computeCurrentLiveOutBits(const uint32_t instructionIndex)
{
    SWC_ASSERT(controlFlowGraph_ != nullptr);

    for (uint64_t& value : tempOutVirtual_)
        value = 0;
    for (uint64_t& value : tempOutConcrete_)
        value = 0;

    const auto& successors = controlFlowGraph_->successors(instructionIndex);
    for (const uint32_t succIdx : successors)
    {
        if (succIdx >= instructionCount_)
            continue;

        const std::span<const uint64_t> succInVirtual  = DenseBits::row(liveInVirtualBits_, succIdx, denseVirtualRegs_.wordCount());
        const std::span<const uint64_t> succInConcrete = DenseBits::row(liveInConcreteBits_, succIdx, denseConcreteRegs_.wordCount());
        for (size_t word = 0; word < tempOutVirtual_.size(); ++word)
            tempOutVirtual_[word] |= succInVirtual[word];
        for (size_t word = 0; word < tempOutConcrete_.size(); ++word)
            tempOutConcrete_[word] |= succInConcrete[word];
    }
}

void MicroRegisterAllocationPass::markCurrentVirtualLiveOut(const uint32_t stamp)
{
    const auto& virtualRegs = denseVirtualRegs_.regs();
    for (size_t wordIndex = 0; wordIndex < tempOutVirtual_.size(); ++wordIndex)
    {
        uint64_t wordBits = tempOutVirtual_[wordIndex];
        while (wordBits)
        {
            const uint32_t bitInWord = std::countr_zero(wordBits);
            const size_t   bitIndex  = wordIndex * 64ull + bitInWord;
            if (bitIndex >= virtualRegs.size())
                break;
            liveStampByDenseIndex_[bitIndex] = stamp;
            wordBits &= (wordBits - 1ull);
        }
    }
}

void MicroRegisterAllocationPass::rebuildCurrentConcreteLiveOutRegs()
{
    const auto& concreteRegs = denseConcreteRegs_.regs();
    currentConcreteLiveOut_.clear();
    currentConcreteLiveOut_.reserve(DenseBits::count(tempOutConcrete_));
    for (size_t wordIndex = 0; wordIndex < tempOutConcrete_.size(); ++wordIndex)
    {
        uint64_t wordBits = tempOutConcrete_[wordIndex];
        while (wordBits)
        {
            const uint32_t bitInWord = std::countr_zero(wordBits);
            const size_t   bitIndex  = wordIndex * 64ull + bitInWord;
            if (bitIndex >= concreteRegs.size())
                break;
            currentConcreteLiveOut_.push_back(concreteRegs[bitIndex]);
            wordBits &= (wordBits - 1ull);
        }
    }
}

bool MicroRegisterAllocationPass::isCurrentConcreteLiveOut(MicroReg key) const
{
    const uint32_t denseIndex = denseConcreteRegs_.find(key);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX)
        return false;
    return DenseBits::contains(tempOutConcrete_, denseIndex);
}

bool MicroRegisterAllocationPass::isInstructionReachable(uint32_t instructionIndex) const
{
    if (instructionIndex >= reachableInstructions_.size())
        return false;

    return reachableInstructions_[instructionIndex] != 0;
}

void MicroRegisterAllocationPass::setupPools()
{
    // Build free lists split by class (int/float) and persistence (transient/persistent).
    intPersistentRegs_.clear();
    floatPersistentRegs_.clear();

    for (const auto reg : conv_->intPersistentRegs)
        intPersistentRegs_.push_back(reg);

    for (const auto reg : conv_->floatPersistentRegs)
        floatPersistentRegs_.push_back(reg);

    freeIntTransient_.clear();
    freeIntPersistent_.clear();
    freeFloatTransient_.clear();
    freeFloatPersistent_.clear();
    freeIntTransient_.reserve(conv_->intRegs.size());
    freeIntPersistent_.reserve(conv_->intRegs.size());
    freeFloatTransient_.reserve(conv_->floatRegs.size());
    freeFloatPersistent_.reserve(conv_->floatRegs.size());

    for (const auto reg : conv_->intRegs)
    {
        if (reg == conv_->framePointer)
            continue;
        if (reg == conv_->preferredLocalStackBaseReg())
            continue;

        if (containsKey(intPersistentRegs_, reg))
            freeIntPersistent_.push_back(reg);
        else
            freeIntTransient_.push_back(reg);
    }

    for (const auto reg : conv_->floatRegs)
    {
        if (containsKey(floatPersistentRegs_, reg))
            freeFloatPersistent_.push_back(reg);
        else
            freeFloatTransient_.push_back(reg);
    }
}

void MicroRegisterAllocationPass::ensureSpillSlot(VRegState& regState, bool isFloat)
{
    // Allocate spill slots lazily to avoid stack growth for registers that never spill.
    if (regState.hasSpill)
        return;

    // Only a value some instruction actually names 128 bits wide needs a
    // 128-bit home; every scalar float and double round-trips through eight
    // bytes instead, which halves both the spill frame and the bytes moved on
    // each spill and reload.
    const MicroOpBits bits     = isFloat && regState.wideFloat ? MicroOpBits::B128 : MicroOpBits::B64;
    const uint64_t    slotSize = bits == MicroOpBits::B128 ? 16u : 8u;
    spillFrameUsed_            = Math::alignUpU64(spillFrameUsed_, slotSize);

    regState.spillOffset = spillFrameUsed_;
    regState.spillBits   = bits;
    regState.hasSpill    = true;
    spillFrameUsed_ += slotSize;
    context_->passChanged = true;
}

void MicroRegisterAllocationPass::clearRematerialization(VRegState& regState)
{
    regState.rematerializable = false;
    regState.rematImmediate   = {};
    regState.rematBits        = MicroOpBits::B64;
    regState.rematDefInstRef  = MicroInstrRef::invalid();
    regState.rematDefConsumed = false;
    regState.rematIsRelocated = false;
    regState.rematRelocation  = {};
}

void MicroRegisterAllocationPass::noteRematDefConsumed(VRegState& regState)
{
    if (regState.rematDefInstRef.isValid())
        regState.rematDefConsumed = true;
}

void MicroRegisterAllocationPass::retireRematDef(VRegState& regState)
{
    if (!regState.rematDefInstRef.isValid())
        return;

    if (!regState.rematDefConsumed)
        queueErase(regState.rematDefInstRef);

    regState.rematDefInstRef  = MicroInstrRef::invalid();
    regState.rematDefConsumed = false;
}

void MicroRegisterAllocationPass::insertPending(const MicroInstrRef beforeRef, const PendingInsert& pendingInst)
{
    const MicroInstrRef insertedRef = instructions_->insertSyntheticBefore(*operands_, beforeRef, pendingInst.op, std::span(pendingInst.ops, pendingInst.numOps));
    if (!pendingInst.hasRelocation)
        return;

    MicroRelocation reloc = pendingInst.relocation;
    reloc.instructionRef  = insertedRef;
    (context_->builder)->addRelocation(reloc);
}

void MicroRegisterAllocationPass::queueErase(const MicroInstrRef instRef)
{
    if (instRef.isValid())
        pendingErasures_.push_back(instRef);
}

void MicroRegisterAllocationPass::flushQueuedErasures()
{
    if (pendingErasures_.empty() || !instructions_)
        return;

    bool erased = false;
    for (const MicroInstrRef ref : pendingErasures_)
        erased |= instructions_->erase(ref);

    if (erased && context_)
        context_->passChanged = true;

    pendingErasures_.clear();
}

void MicroRegisterAllocationPass::setRematerializedImmediate(VRegState& regState, const MicroInstrOperand& immediate, const MicroOpBits opBits)
{
    regState.rematerializable = true;
    regState.rematImmediate   = immediate;
    regState.rematBits        = opBits;
    regState.rematDefConsumed = false;
}

uint64_t MicroRegisterAllocationPass::spillMemOffset(uint64_t spillOffset, int64_t stackDepth)
{
    SWC_ASSERT(spillOffset <= static_cast<uint64_t>(std::numeric_limits<int64_t>::max()));
    auto finalOffset = static_cast<int64_t>(spillOffset);
    finalOffset += stackDepth;
    SWC_ASSERT(finalOffset >= std::numeric_limits<int32_t>::min());
    SWC_ASSERT(finalOffset <= std::numeric_limits<int32_t>::max());
    return static_cast<uint64_t>(finalOffset);
}

void MicroRegisterAllocationPass::queueRematerializedLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState)
{
    SWC_ASSERT(regState.rematerializable);

    // Remaking a float zero as an immediate means staging it through an integer
    // register, because no instruction moves a constant straight into an xmm
    // one. Clearing is a single instruction. Only floats: the integer clear is
    // an xor, and it would wipe flags this insertion point may have live.
    if (!regState.rematIsRelocated && physReg.isAnyFloat() && !regState.rematImmediate.hasWideImmediateValue() && regState.rematImmediate.valueU64 == 0)
    {
        out.op            = MicroInstrOpcode::ClearReg;
        out.numOps        = 2;
        out.ops[0].reg    = physReg;
        out.ops[1].opBits = regState.rematBits;
        return;
    }

    out.op            = regState.rematIsRelocated ? MicroInstrOpcode::LoadRegPtrReloc : MicroInstrOpcode::LoadRegImm;
    out.numOps        = 3;
    out.ops[0].reg    = physReg;
    out.ops[1].opBits = regState.rematBits;
    out.ops[2]        = regState.rematImmediate;

    if (regState.rematIsRelocated)
    {
        out.relocation                = regState.rematRelocation;
        out.relocation.instructionRef = MicroInstrRef::invalid();
        out.relocation.codeOffset     = 0;
        out.hasRelocation             = true;
    }
}

void MicroRegisterAllocationPass::queueSpillStore(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth) const
{
    out.op              = MicroInstrOpcode::LoadMemReg;
    out.numOps          = 4;
    out.ops[0].reg      = conv_->stackPointer;
    out.ops[1].reg      = physReg;
    out.ops[2].opBits   = regState.spillBits;
    out.ops[3].valueU64 = spillMemOffset(regState.spillOffset, stackDepth);
}

void MicroRegisterAllocationPass::queueSpillLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth) const
{
    out.op              = MicroInstrOpcode::LoadRegMem;
    out.numOps          = 4;
    out.ops[0].reg      = physReg;
    out.ops[1].reg      = conv_->stackPointer;
    out.ops[2].opBits   = regState.spillBits;
    out.ops[3].valueU64 = spillMemOffset(regState.spillOffset, stackDepth);
}

bool MicroRegisterAllocationPass::spillOrRematerializeLiveValue(MicroReg physReg, VRegState& regState, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    if (regState.rematerializable)
    {
        regState.dirty = false;
        return false;
    }

    const bool hadSpillSlot = regState.hasSpill;
    ensureSpillSlot(regState, physReg.isFloat());
    if (!regState.dirty && hadSpillSlot)
        return false;

    PendingInsert spillPending;
    queueSpillStore(spillPending, physReg, regState, stackDepth);
    pending.push_back(spillPending);
    regState.dirty = false;
    return true;
}

void MicroRegisterAllocationPass::updateRematerializationForDef(VRegState& regState, MicroReg virtKey, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* instOps) const
{
    clearRematerialization(regState);
    if (!instOps)
        return;
    if (hasControlFlow_)
    {
        const uint32_t denseIndex = denseVirtualIndex(virtKey);
        if (denseIndex >= definitionCounts_.size() || definitionCounts_[denseIndex] != 1)
            return;
    }

    switch (inst.op)
    {
        case MicroInstrOpcode::LoadRegImm:
            if (instOps[0].reg == virtKey)
            {
                setRematerializedImmediate(regState, instOps[2], instOps[1].opBits);
                regState.rematDefInstRef = instRef;
            }
            return;

        case MicroInstrOpcode::ClearReg:
            if (instOps[0].reg == virtKey)
            {
                MicroInstrOperand zeroImm;
                zeroImm.setImmediateValue(ApInt(0, getNumBits(instOps[1].opBits)));
                setRematerializedImmediate(regState, zeroImm, instOps[1].opBits);
                regState.rematDefInstRef = instRef;
            }
            return;

        case MicroInstrOpcode::LoadRegPtrReloc:
        {
            // Remaking one of these costs the same single instruction it cost
            // the first time, so it must never reach a spill slot. Without this
            // an address shared by several uses â€” which common-subexpression
            // elimination is what creates â€” turns into a store plus a reload.
            if (instOps[0].reg != virtKey)
                return;
            const auto relocIt = relocationByDefInstruction_.find(instRef);
            if (relocIt == relocationByDefInstruction_.end())
                return;

            setRematerializedImmediate(regState, instOps[2], instOps[1].opBits);
            regState.rematDefInstRef  = instRef;
            regState.rematIsRelocated = true;
            regState.rematRelocation  = relocIt->second;
            return;
        }

        case MicroInstrOpcode::LoadRegReg:
            if (instOps[0].reg == virtKey && instOps[1].reg.isVirtual())
            {
                const auto& srcState = stateForVirtual(instOps[1].reg);
                if (srcState.rematerializable && srcState.rematBits == instOps[2].opBits)
                {
                    regState.rematerializable = srcState.rematerializable;
                    regState.rematImmediate   = srcState.rematImmediate;
                    regState.rematBits        = srcState.rematBits;
                    // A relocated address is only an immediate once the emitter
                    // has patched it; carrying the recipe without its relocation
                    // would remake the unpatched word.
                    regState.rematIsRelocated = srcState.rematIsRelocated;
                    regState.rematRelocation  = srcState.rematRelocation;
                    // Don't track this copy as a remat-def: cleaning it up belongs
                    // to the pre-RA copy elimination pass, not to RA's own bookkeeping.
                }
            }
            return;

        default:
            return;
    }
}

void MicroRegisterAllocationPass::applyStackPointerDelta(int64_t& stackDepth, const MicroInstr& inst) const
{
    if (inst.op == MicroInstrOpcode::Push)
    {
        stackDepth += static_cast<int64_t>(sizeof(uint64_t));
        return;
    }

    if (inst.op == MicroInstrOpcode::Pop)
    {
        stackDepth -= static_cast<int64_t>(sizeof(uint64_t));
        return;
    }

    if (inst.op != MicroInstrOpcode::OpBinaryRegImm)
        return;

    const MicroInstrOperand* ops = inst.ops(*operands_);
    if (ops[0].reg != conv_->stackPointer)
        return;
    if (ops[1].opBits != MicroOpBits::B64)
        return;

    const auto immValue = static_cast<int64_t>(ops[3].valueU64);
    if (ops[2].microOp == MicroOp::Subtract)
        stackDepth += immValue;
    else if (ops[2].microOp == MicroOp::Add)
        stackDepth -= immValue;
}

void MicroRegisterAllocationPass::mergeLabelStackDepth(std::unordered_map<MicroLabelRef, int64_t>& labelStackDepth, MicroLabelRef labelRef, int64_t stackDepth)
{
    const auto it = labelStackDepth.find(labelRef);
    if (it == labelStackDepth.end())
    {
        labelStackDepth.emplace(labelRef, stackDepth);
        return;
    }

    // Keep the first observed depth. Mismatches can happen on dead edges
    // (for example, after a return in linearized IR).
    if (it->second != stackDepth)
        return;
}

bool MicroRegisterAllocationPass::isCandidateBetter(MicroReg candidateKey, MicroReg candidateReg, MicroReg currentBestKey, MicroReg currentBestReg, uint32_t instructionIndex, uint32_t stamp) const
{
    if (!currentBestReg.isValid())
        return true;

    const bool candidateDead = !isLiveOut(candidateKey, stamp);
    const bool bestDead      = !isLiveOut(currentBestKey, stamp);
    if (candidateDead != bestDead)
        return candidateDead;

    const auto& candidateState = stateForVirtual(candidateKey);
    const auto& bestState      = stateForVirtual(currentBestKey);

    const bool candidateCleanSpill = candidateState.hasSpill && !candidateState.dirty;
    const bool bestCleanSpill      = bestState.hasSpill && !bestState.dirty;
    if (candidateCleanSpill != bestCleanSpill)
        return candidateCleanSpill;

    const uint32_t candidateDistance = distanceToNextUse(candidateKey, instructionIndex);
    const uint32_t bestDistance      = distanceToNextUse(currentBestKey, instructionIndex);
    if (candidateDistance != bestDistance)
        return candidateDistance > bestDistance;

    const bool candidatePersistent = isPersistentPhysReg(candidateReg);
    const bool bestPersistent      = isPersistentPhysReg(currentBestReg);
    if (candidatePersistent != bestPersistent)
        return !candidatePersistent;

    return candidateKey.hash() > currentBestKey.hash();
}

bool MicroRegisterAllocationPass::selectEvictionCandidate(MicroReg requestVirtKey, uint32_t instructionIndex, bool isFloatReg, bool fromPersistentPool, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, bool allowConcreteLive, MicroReg& outVirtKey, MicroReg& outPhys) const
{
    // Choose mapped virtual reg that is cheapest to evict under current constraints.
    outVirtKey = MicroReg::invalid();
    outPhys    = MicroReg::invalid();

    const auto& virtualRegs = denseVirtualRegs_.regs();
    for (const uint32_t mappedDenseIndex : mappedVirtualIndices_)
    {
        SWC_ASSERT(mappedDenseIndex < virtualRegs.size());
        const MicroReg virtKey  = virtualRegs[mappedDenseIndex];
        const auto&    regState = states_[mappedDenseIndex];
        SWC_ASSERT(regState.mapped);
        const MicroReg physReg = regState.phys;

        if (containsKey(protectedKeys, virtKey))
            continue;
        if (containsKey(forbiddenPhysRegs, physReg))
            continue;
        if (isFloatReg)
        {
            if (!physReg.isFloat())
                continue;
        }
        else
        {
            if (!physReg.isInt())
                continue;
        }

        const bool isPersistent = isPersistentPhysReg(physReg);
        if (isPersistent != fromPersistentPool)
            continue;

        // Same eligibility as taking a free register: evicting a value does not
        // make its register any more usable. In particular a register a global
        // owns from here on is off limits even though the global itself is
        // never mapped, so it can never be the victim that reveals the clash.
        if (!canUsePhysical(requestVirtKey, instructionIndex, physReg, forbiddenPhysRegs, allowConcreteLive))
            continue;

        if (isCandidateBetter(virtKey, physReg, outVirtKey, outPhys, instructionIndex, stamp))
        {
            outVirtKey = virtKey;
            outPhys    = physReg;
        }
    }

    return outPhys.isValid();
}

MicroRegisterAllocationPass::FreePools MicroRegisterAllocationPass::pickFreePools(const AllocRequest& request)
{
    if (request.virtReg.isVirtualInt())
    {
        if (request.needsPersistent)
            return FreePools{&freeIntPersistent_, &freeIntTransient_};

        return FreePools{&freeIntTransient_, freeIntPersistent_.empty() ? nullptr : &freeIntPersistent_};
    }

    SWC_ASSERT(request.virtReg.isVirtualFloat());
    if (request.needsPersistent)
        return FreePools{&freeFloatPersistent_, &freeFloatTransient_};

    // No callee-saved fallback for an ordinary float: every nonvolatile float
    // taken costs the prologue a 16-byte store/load pair, which a short-lived
    // value never repays. Momentary pressure is better served by evicting a
    // caller-saved mapping â€” the class floor keeps enough of them hull-free.
    return FreePools{&freeFloatTransient_, nullptr};
}

bool MicroRegisterAllocationPass::tryTakePreferredPhysical(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, const bool allowConcreteLive, MicroReg& outPhys)
{
    if (!request.preferredPhysReg.isValid())
        return false;

    const FreePools pools = pickFreePools(request);
    SWC_ASSERT(pools.primary != nullptr);

    if (tryTakeSpecificPhysical(*pools.primary, request.virtKey, request.instructionIndex, request.preferredPhysReg, forbiddenPhysRegs, allowConcreteLive, outPhys))
        return true;

    if (!pools.secondary)
        return false;

    return tryTakeSpecificPhysical(*pools.secondary, request.virtKey, request.instructionIndex, request.preferredPhysReg, forbiddenPhysRegs, allowConcreteLive, outPhys);
}

bool MicroRegisterAllocationPass::tryTakeFreePhysical(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, bool allowConcreteLive, MicroReg& outPhys)
{
    const FreePools pools = pickFreePools(request);
    SWC_ASSERT(pools.primary != nullptr);

    if (tryTakeAllowedPhysical(*pools.primary, request.virtKey, request.instructionIndex, forbiddenPhysRegs, allowConcreteLive, outPhys))
        return true;

    if (pools.secondary)
        return tryTakeAllowedPhysical(*pools.secondary, request.virtKey, request.instructionIndex, forbiddenPhysRegs, allowConcreteLive, outPhys);

    return false;
}

void MicroRegisterAllocationPass::unmapVirtReg(MicroReg virtKey)
{
    auto& regState = stateForVirtual(virtKey);
    if (!regState.mapped)
        return;

    // The original mapping is going away; if nothing ever read it, the defining
    // instruction produced a value no one observed and can be erased post-RA.
    retireRematDef(regState);

    SWC_ASSERT(regState.mappedListIndex != std::numeric_limits<uint32_t>::max());
    SWC_ASSERT(regState.mappedListIndex < mappedVirtualIndices_.size());

    const uint32_t removedListIndex         = regState.mappedListIndex;
    const uint32_t lastDenseIndex           = mappedVirtualIndices_.back();
    mappedVirtualIndices_[removedListIndex] = lastDenseIndex;
    mappedVirtualIndices_.pop_back();

    if (removedListIndex < mappedVirtualIndices_.size())
        states_[lastDenseIndex].mappedListIndex = removedListIndex;

    regState.mapped          = false;
    regState.mappedListIndex = std::numeric_limits<uint32_t>::max();
    regState.phys            = MicroReg::invalid();
}

void MicroRegisterAllocationPass::mapVirtReg(MicroReg virtKey, MicroReg physReg)
{
    SWC_ASSERT(!isPhysRegForbiddenForVirtual(virtKey, physReg));

    auto& regState = stateForVirtual(virtKey);
    if (!regState.mapped)
    {
        regState.mappedListIndex = static_cast<uint32_t>(mappedVirtualIndices_.size());
        mappedVirtualIndices_.push_back(denseVirtualIndex(virtKey));
        regState.mapped = true;
    }

    regState.phys = physReg;

    // Record the physical home the debug local-stack base resolves to. The base is defined once
    // in the prologue and stays resident for the whole function, so its first (defining) mapping
    // is the home all locals are addressed against; capture that and ignore any later reload.
    if (context_->debugStackBaseVirtualReg.isValid() && virtKey == context_->debugStackBaseVirtualReg && !context_->debugStackBasePhysReg.isValid())
        context_->debugStackBasePhysReg = physReg;
}

bool MicroRegisterAllocationPass::tryTransferCopySource(const AllocRequest& request, MicroRegSpan forbiddenPhysRegs, const uint32_t stamp, const int64_t stackDepth, std::vector<PendingInsert>& pending, const bool allowLiveSourceSpill, const bool allowConcreteLive, MicroReg& outPhys)
{
    if (!request.transferSource.isVirtual() || request.transferSource == request.virtKey)
        return false;

    auto& sourceState = stateForVirtual(request.transferSource);
    if (!sourceState.mapped)
        return false;

    const bool sourceLiveOut = isLiveOut(request.transferSource, stamp);
    if (sourceLiveOut && !allowLiveSourceSpill)
        return false;

    const MicroReg sourcePhys = sourceState.phys;
    if (!canUsePhysical(request.virtKey, request.instructionIndex, sourcePhys, forbiddenPhysRegs, allowConcreteLive))
        return false;

    const auto& dstState = stateForVirtual(request.virtKey);
    if (dstState.mapped && dstState.phys != sourcePhys)
    {
        const MicroReg dstPhys = dstState.phys;
        unmapVirtReg(request.virtKey);
        returnToFreePool(dstPhys);
    }

    if (sourceLiveOut)
        spillOrRematerializeLiveValue(sourcePhys, sourceState, stackDepth, pending);

    unmapVirtReg(request.transferSource);
    mapVirtReg(request.virtKey, sourcePhys);
    outPhys = sourcePhys;
    return true;
}

bool MicroRegisterAllocationPass::selectEvictionCandidateWithFallback(MicroReg requestVirtKey, uint32_t instructionIndex, bool isFloatReg, bool preferPersistentPool, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, bool allowConcreteLive, MicroReg& outVirtKey, MicroReg& outPhys) const
{
    if (selectEvictionCandidate(requestVirtKey, instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, forbiddenPhysRegs, stamp, allowConcreteLive, outVirtKey, outPhys))
        return true;

    return selectEvictionCandidate(requestVirtKey, instructionIndex, isFloatReg, !preferPersistentPool, protectedKeys, forbiddenPhysRegs, stamp, allowConcreteLive, outVirtKey, outPhys);
}

bool MicroRegisterAllocationPass::hasConcreteTouchInRange(const MicroReg physReg, const uint32_t lo, const uint32_t hi) const
{
    const uint32_t denseIndex = denseConcreteRegs_.find(physReg);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= concreteTouchPositionsByDenseIndex_.size())
        return false;

    const auto& positions = concreteTouchPositionsByDenseIndex_[denseIndex];
    const auto  it        = std::ranges::lower_bound(positions, lo);
    return it != positions.end() && *it <= hi;
}

bool MicroRegisterAllocationPass::isStraightLineRange(const uint32_t lo, const uint32_t hi) const
{
    // Straight-line means control enters at lo and leaves past hi, exactly once:
    // no branch out, no label to jump into, no call, and nothing that moves the
    // stack pointer. The first three make the save and the restore run as a
    // pair; the last keeps both of them addressing the same slot, since spill
    // addresses are stack-pointer relative and biased by the running depth.
    for (uint32_t idx = lo; idx <= hi && idx < instructionCount_; ++idx)
    {
        if (instructionUseDefs_[idx].isCall)
            return false;
    }

    uint32_t idx = 0;
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it, ++idx)
    {
        if (idx < lo || idx > hi)
            continue;
        if (it->op == MicroInstrOpcode::Label || MicroInstrInfo::isTerminatorInstruction(*it))
            return false;
        if (it->op == MicroInstrOpcode::Push || it->op == MicroInstrOpcode::Pop)
            return false;

        int64_t probeDepth = 0;
        applyStackPointerDelta(probeDepth, *it);
        if (probeDepth != 0)
            return false;
    }

    return true;
}

bool MicroRegisterAllocationPass::tryBorrowReservedRegister(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, int64_t stackDepth, std::vector<PendingInsert>& pending, MicroReg& outPhys)
{
    // Last resort for a sweep that is not the one which allocated the function.
    // Legalizing the allocator's output asks for a scratch value in a function
    // whose registers are all committed, and the reserved ones are closed to it
    // â€” so there can be nothing free. The values in the way live under a
    // register's own name and have no spill home, which is exactly what makes
    // taking their register unrecoverable. So give one a home for the length of
    // the borrow: save it to a slot before, read it back after.
    if (context_->isFirstAllocationSweep || context_->globalReservedRegs.empty())
        return false;

    const uint32_t lo         = request.instructionIndex;
    const uint32_t denseIndex = denseVirtualRegs_.find(request.virtKey);
    if (denseIndex == MicroDenseRegIndex::K_INVALID_INDEX || denseIndex >= virtualSpanHi_.size())
        return false;

    const uint32_t hi = virtualSpanHi_[denseIndex];
    if (hi < lo || hi + 1 >= instructionCount_)
        return false;
    if (!isStraightLineRange(lo, hi))
        return false;

    const bool isFloat = request.virtReg.isVirtualFloat();
    for (const MicroReg reg : context_->globalReservedRegs)
    {
        if (reg.isFloat() != isFloat)
            continue;
        if (containsKey(forbiddenPhysRegs, reg) || containsKey(protectedKeys, reg))
            continue;
        if (isPhysRegForbiddenForVirtual(request.virtKey, reg))
            continue;
        if (reg == context_->debugStackBasePhysReg)
            continue;

        // The borrow overwrites the register, so nothing inside the range may
        // read or write it under its own name.
        if (hasConcreteTouchInRange(reg, lo, hi))
            continue;

        bool alreadyBorrowed = false;
        for (const BorrowRestore& restore : pendingBorrowRestores_)
            alreadyBorrowed = alreadyBorrowed || restore.physReg == reg;
        if (alreadyBorrowed)
            continue;

        const MicroOpBits bits     = isFloat ? MicroOpBits::B128 : MicroOpBits::B64;
        const uint64_t    slotSize = bits == MicroOpBits::B128 ? 16u : 8u;
        spillFrameUsed_            = Math::alignUpU64(spillFrameUsed_, slotSize);

        const uint64_t slotOffset = spillFrameUsed_;
        spillFrameUsed_ += slotSize;
        context_->passChanged = true;

        PendingInsert save;
        save.op              = MicroInstrOpcode::LoadMemReg;
        save.numOps          = 4;
        save.ops[0].reg      = conv_->stackPointer;
        save.ops[1].reg      = reg;
        save.ops[2].opBits   = bits;
        save.ops[3].valueU64 = spillMemOffset(slotOffset, stackDepth);
        pending.push_back(save);

        pendingBorrowRestores_.push_back({.physReg = reg, .slotOffset = slotOffset, .slotBits = bits, .atIndex = hi + 1});

        outPhys = reg;
        return true;
    }

    return false;
}

MicroReg MicroRegisterAllocationPass::allocatePhysical(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // Prefer free registers; otherwise evict one candidate and spill if needed.
    MicroReg physReg;
    if (tryTakePreferredPhysical(request, forbiddenPhysRegs, false, physReg))
        return physReg;
    if (tryTakeFreePhysical(request, forbiddenPhysRegs, false, physReg))
        return physReg;
    if (tryTakePreferredPhysical(request, forbiddenPhysRegs, true, physReg))
        return physReg;
    if (tryTakeFreePhysical(request, forbiddenPhysRegs, true, physReg))
        return physReg;
    if (tryTransferCopySource(request, forbiddenPhysRegs, stamp, stackDepth, pending, true, true, physReg))
        return physReg;

    MicroReg victimKey = MicroReg::invalid();
    MicroReg victimReg;

    const bool isFloatReg           = request.virtReg.isVirtualFloat();
    const bool preferPersistentPool = request.needsPersistent;
    if (!selectEvictionCandidateWithFallback(request.virtKey, request.instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, forbiddenPhysRegs, stamp, false, victimKey, victimReg))
    {
        if (!selectEvictionCandidateWithFallback(request.virtKey, request.instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, forbiddenPhysRegs, stamp, true, victimKey, victimReg))
        {
            MicroReg borrowed;
            if (tryBorrowReservedRegister(request, protectedKeys, forbiddenPhysRegs, stackDepth, pending, borrowed))
                return borrowed;

            // Solvency valve: ordinary floats are kept away from the
            // nonvolatile pool (each taken register costs the prologue a
            // 16-byte store/load pair), but an unallocatable request costs
            // the compile. Only when every caller-saved avenue â€” free,
            // transfer, eviction, borrow â€” is exhausted may one be taken.
            if (isFloatReg && tryTakeAllowedPhysical(freeFloatPersistent_, request.virtKey, request.instructionIndex, forbiddenPhysRegs, true, physReg))
                return physReg;

            SWC_INTERNAL_CHECK(false);
        }
    }

    auto&      victimState   = stateForVirtual(victimKey);
    const bool victimLiveOut = isLiveOut(victimKey, stamp);
    if (victimLiveOut)
        spillOrRematerializeLiveValue(victimReg, victimState, stackDepth, pending);

    unmapVirtReg(victimKey);
    return victimReg;
}

void MicroRegisterAllocationPass::recordDestructiveAlias(SmallVector<MicroReg>& liveBases, SmallVector<DestructiveAlias>& concreteAliases, MicroReg dstReg, MicroReg baseReg, const uint32_t stamp, const bool trackVirtualDestConflict) const
{
    if (!baseReg.isVirtual() || !isLiveOut(baseReg, stamp))
        return;

    if (trackVirtualDestConflict && dstReg.isVirtual())
    {
        if (dstReg != baseReg)
            appendUniqueReg(liveBases, baseReg);
        return;
    }

    if (!dstReg.isInt() && !dstReg.isFloat())
        return;

    for (const auto& alias : concreteAliases)
    {
        if (alias.virtKey == baseReg && alias.physReg == dstReg)
            return;
    }

    DestructiveAlias alias;
    alias.virtKey = baseReg;
    alias.physReg = dstReg;
    concreteAliases.push_back(alias);
}

void MicroRegisterAllocationPass::collectDestructiveLoadConstraints(SmallVector<MicroReg>& liveBases, SmallVector<DestructiveAlias>& concreteAliases, const MicroInstr& inst, const MicroInstrOperand* instOps, const uint32_t stamp) const
{
    if (!instOps)
        return;

    switch (inst.op)
    {
        case MicroInstrOpcode::LoadRegMem:
        case MicroInstrOpcode::LoadSignedExtRegMem:
        case MicroInstrOpcode::LoadZeroExtRegMem:
            recordDestructiveAlias(liveBases, concreteAliases, instOps[0].reg, instOps[1].reg, stamp, true);
            break;

        case MicroInstrOpcode::LoadAddrRegMem:
            if (instOps[3].valueU64)
                recordDestructiveAlias(liveBases, concreteAliases, instOps[0].reg, instOps[1].reg, stamp, false);
            break;

        case MicroInstrOpcode::LoadAddrAmcRegMem:
            recordDestructiveAlias(liveBases, concreteAliases, instOps[0].reg, instOps[1].reg, stamp, false);
            recordDestructiveAlias(liveBases, concreteAliases, instOps[0].reg, instOps[2].reg, stamp, false);
            break;

        default:
            break;
    }
}

MicroReg MicroRegisterAllocationPass::assignVirtReg(const AllocRequest& request, MicroRegSpan protectedKeys, MicroRegSpan forbiddenPhysRegs, MicroRegSpan remapForbiddenPhysRegs, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // Reuse existing mapping when possible, otherwise allocate and load from spill on use.
    auto& regState = stateForVirtual(request.virtKey);

    // Pinned values permanently live in their reserved register: no allocation,
    // transfer, spill, or reload â€” every def/use simply resolves to that register.
    if (regState.pinned)
        return regState.phys;

    if (!request.isUse && tryTransferCopySource(request, forbiddenPhysRegs, stamp, stackDepth, pending, false, false, regState.phys))
        return regState.phys;

    if (regState.mapped &&
        ((request.isDef && containsKey(forbiddenPhysRegs, regState.phys)) ||
         containsKey(remapForbiddenPhysRegs, regState.phys)))
    {
        const MicroReg conflictedPhys = regState.phys;
        if (request.isUse)
            spillOrRematerializeLiveValue(conflictedPhys, regState, stackDepth, pending);

        unmapVirtReg(request.virtKey);
        returnToFreePool(conflictedPhys);
    }

    if (regState.mapped)
    {
        // Reusing the original mapping for a use means the defining instruction's
        // physical write is actually observed; keep its remat def alive.
        if (request.isUse)
            noteRematDefConsumed(regState);
        return regState.phys;
    }

    const auto physReg = allocatePhysical(request, protectedKeys, forbiddenPhysRegs, stamp, stackDepth, pending);
    SWC_ASSERT(!isReservedByGlobalFor(request.virtKey, physReg, request.instructionIndex));
    mapVirtReg(request.virtKey, physReg);

    auto& mappedState = stateForVirtual(request.virtKey);
    if (request.isUse)
    {
        PendingInsert loadPending;
        if (mappedState.rematerializable)
            queueRematerializedLoad(loadPending, physReg, mappedState);
        else
            queueSpillLoad(loadPending, physReg, mappedState, stackDepth);
        pending.push_back(loadPending);
        mappedState.dirty = false;
    }

    return physReg;
}

void MicroRegisterAllocationPass::spillMappedVirtualsForConcreteTouches(const MicroInstrUseDef& useDef, MicroRegSpan protectedKeys, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    SmallVector<MicroReg> touchedRegs;
    touchedRegs.reserve(useDef.uses.size() + useDef.defs.size());

    for (const MicroReg reg : useDef.uses)
    {
        if ((!reg.isInt() && !reg.isFloat()) || containsKey(touchedRegs, reg))
            continue;

        touchedRegs.push_back(reg);
    }

    for (const MicroReg reg : useDef.defs)
    {
        if ((!reg.isInt() && !reg.isFloat()) || containsKey(touchedRegs, reg))
            continue;

        touchedRegs.push_back(reg);
    }

    if (touchedRegs.empty())
        return;

    const auto& virtualRegs = denseVirtualRegs_.regs();
    for (size_t mappedIndex = 0; mappedIndex < mappedVirtualIndices_.size();)
    {
        const uint32_t denseIndex = mappedVirtualIndices_[mappedIndex];
        SWC_ASSERT(denseIndex < virtualRegs.size());
        const MicroReg virtKey  = virtualRegs[denseIndex];
        auto&          regState = states_[denseIndex];
        SWC_ASSERT(regState.mapped);
        const MicroReg physReg = regState.phys;
        if (containsKey(protectedKeys, virtKey) || !containsKey(touchedRegs, physReg))
        {
            ++mappedIndex;
            continue;
        }

        if (isLiveOut(virtKey, stamp))
            spillOrRematerializeLiveValue(physReg, regState, stackDepth, pending);

        unmapVirtReg(virtKey);
        returnToFreePool(physReg);
    }
}

void MicroRegisterAllocationPass::spillCallLiveOut(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // Calls may clobber transient regs; force spill of vulnerable live values before call.
    const auto& virtualRegs = denseVirtualRegs_.regs();
    for (size_t mappedIndex = 0; mappedIndex < mappedVirtualIndices_.size();)
    {
        const uint32_t denseIndex = mappedVirtualIndices_[mappedIndex];
        SWC_ASSERT(denseIndex < virtualRegs.size());
        const MicroReg virtKey  = virtualRegs[denseIndex];
        auto&          regState = states_[denseIndex];
        SWC_ASSERT(regState.mapped);
        const MicroReg physReg = regState.phys;

        if (!requiresCallSpill(virtKey) || !isLiveOut(virtKey, stamp))
        {
            ++mappedIndex;
            continue;
        }

        spillOrRematerializeLiveValue(physReg, regState, stackDepth, pending);

        unmapVirtReg(virtKey);
        returnToFreePool(physReg);
    }
}

void MicroRegisterAllocationPass::saveRestorePinnedAcrossCall(const uint32_t instructionIndex, const int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // A value pinned in a caller-saved register does not survive a call on its
    // own: park it in its slot for exactly the call's duration â€” store before
    // the call, read back before the next instruction (through
    // pendingBorrowRestores_). The memory traffic lands on the call paths
    // alone; in the common shape those are cold safety-panic blocks, and the
    // straight-line code keeps the pure register form. This stays correct even
    // when a panic call returns through a user panic hook: the value is back
    // in its register before the next instruction runs.
    for (const uint32_t denseIndex : pinnedCallSavedDense_)
    {
        if (instructionIndex < virtualSpanLo_[denseIndex] || instructionIndex > virtualSpanHi_[denseIndex])
            continue;

        auto&         regState = states_[denseIndex];
        PendingInsert save;
        queueSpillStore(save, regState.phys, regState, stackDepth);
        pending.push_back(save);
        pendingBorrowRestores_.push_back({.physReg = regState.phys, .slotOffset = regState.spillOffset, .slotBits = regState.spillBits, .atIndex = instructionIndex + 1});
    }
}

void MicroRegisterAllocationPass::flushAllMappedVirtuals(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // Control-flow boundaries require a stable memory state for all mapped values.
    const auto& virtualRegs = denseVirtualRegs_.regs();
    for (const uint32_t denseIndex : mappedVirtualIndices_)
    {
        SWC_ASSERT(denseIndex < virtualRegs.size());
        const MicroReg virtKey  = virtualRegs[denseIndex];
        auto&          regState = states_[denseIndex];
        SWC_ASSERT(regState.mapped);
        const MicroReg physReg = regState.phys;
        const bool     liveOut = isLiveOut(virtKey, stamp);
        if (liveOut)
            spillOrRematerializeLiveValue(physReg, regState, stackDepth, pending);

        regState.mapped          = false;
        regState.mappedListIndex = std::numeric_limits<uint32_t>::max();
        regState.phys            = MicroReg::invalid();
        returnToFreePool(physReg);
    }

    mappedVirtualIndices_.clear();
}

void MicroRegisterAllocationPass::dropMappedVirtualNoStore(const uint32_t denseIndex)
{
    // Same unmapping as the full flush - no rematerialization retirement, the
    // register goes back to its pool - for a value whose memory home is
    // already coherent, so no store is owed.
    auto& regState = states_[denseIndex];
    SWC_ASSERT(regState.mapped);

    const MicroReg physReg          = regState.phys;
    const uint32_t removedListIndex = regState.mappedListIndex;
    SWC_ASSERT(removedListIndex < mappedVirtualIndices_.size());

    const uint32_t lastDenseIndex           = mappedVirtualIndices_.back();
    mappedVirtualIndices_[removedListIndex] = lastDenseIndex;
    mappedVirtualIndices_.pop_back();
    if (removedListIndex < mappedVirtualIndices_.size())
        states_[lastDenseIndex].mappedListIndex = removedListIndex;

    regState.mapped          = false;
    regState.mappedListIndex = std::numeric_limits<uint32_t>::max();
    regState.phys            = MicroReg::invalid();
    returnToFreePool(physReg);
}

void MicroRegisterAllocationPass::flushAtBoundary(const uint32_t instructionIndex, const MicroInstr& inst, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // The write-back protocol. Memory stays the truth at every control-flow
    // boundary - live dirty values are stored, exactly as the full flush
    // did - but the register mapping is a cache that survives the boundary
    // instead of being dropped:
    //
    //   - On the fall-through of a conditional jump, the mapping is simply
    //     still valid: the store made memory coherent, the register still
    //     holds the value.
    //   - On the taken edge, the register ALSO still holds that edge's value
    //     when the target's join keeps the mapping (below); otherwise the
    //     target reloads from the coherent home, which is the old behavior.
    //   - At a join label, a mapping survives only if every incoming edge
    //     agrees on it: the fall-through edge contributes the current state,
    //     and each jump edge contributed a snapshot recorded when the jump
    //     was processed. A register kept this way holds a per-path value the
    //     same way the home slot would, so agreement on (value, register) is
    //     the whole requirement. Everything else is dropped without a store,
    //     because the store phase above already made memory coherent.
    //   - A label with a back-edge predecessor drops everything: the linear
    //     scan has not seen the back-edge state yet. Loop-resident values are
    //     the hull mechanism's job; this path serves forward joins - if/else
    //     merges inside hot loops, and the label stitches of fully unrolled
    //     code.
    //
    // Nothing here emits a reconciliation copy: a mapping either agrees on
    // every edge or dies. That is what keeps this sound without splitting
    // critical edges.
    const auto& virtualRegs = denseVirtualRegs_.regs();

    // A kept mapping holds its register until the value's next use; a far
    // next use makes that a hostage, not a cache — the local allocator loses
    // a scratch register for dozens of instructions to save one reload. The
    // bound keeps the tight-loop and join-heavy shapes (next use within a
    // few instructions) and releases the rest, clean, to the pool.
    constexpr uint32_t K_KEEP_MAX_NEXT_USE_DISTANCE = 48;

    // Store phase: identical coverage to the full flush.
    for (size_t listIndex = 0; listIndex < mappedVirtualIndices_.size();)
    {
        const uint32_t denseIndex = mappedVirtualIndices_[listIndex];
        SWC_ASSERT(denseIndex < virtualRegs.size());
        const MicroReg virtKey  = virtualRegs[denseIndex];
        auto&          regState = states_[denseIndex];
        SWC_ASSERT(regState.mapped);

        if (!isLiveOut(virtKey, stamp))
        {
            dropMappedVirtualNoStore(denseIndex);
            continue; // swap-erase: same listIndex now holds another entry
        }

        spillOrRematerializeLiveValue(regState.phys, regState, stackDepth, pending);

        if (distanceToNextUse(virtKey, instructionIndex) > K_KEEP_MAX_NEXT_USE_DISTANCE)
        {
            dropMappedVirtualNoStore(denseIndex);
            continue;
        }

        ++listIndex;
    }

    if (inst.op == MicroInstrOpcode::Label)
    {
        // Join: intersect the surviving mappings with every incoming edge.
        bool dropAll = false;

        SmallVector<const BoundarySnapshot*, 4> edgeSnapshots;
        if (instructionIndex < predecessors_.size())
        {
            for (const uint32_t pred : predecessors_[instructionIndex])
            {
                if (pred >= instructionIndex)
                {
                    dropAll = true; // back-edge: state unseen
                    break;
                }
                if (pred + 1 == instructionIndex)
                    continue; // fall-through edge: the current state
                const auto snapshotIt = boundarySnapshots_.find(pred);
                if (snapshotIt == boundarySnapshots_.end())
                {
                    dropAll = true; // edge with no recorded state
                    break;
                }
                edgeSnapshots.push_back(&snapshotIt->second);
            }
        }
        else
        {
            dropAll = true;
        }

        for (size_t listIndex = 0; listIndex < mappedVirtualIndices_.size();)
        {
            const uint32_t denseIndex = mappedVirtualIndices_[listIndex];
            const MicroReg physReg    = states_[denseIndex].phys;

            bool keep = !dropAll;
            for (const BoundarySnapshot* snapshot : edgeSnapshots)
            {
                if (!keep)
                    break;
                bool found = false;
                for (const auto& [snapDense, snapPhys] : *snapshot)
                {
                    if (snapDense == denseIndex)
                    {
                        found = snapPhys == physReg;
                        break;
                    }
                }
                keep = found;
            }

            if (keep)
            {
                ++listIndex;
                continue;
            }
            dropMappedVirtualNoStore(denseIndex);
        }
    }
    else if (inst.op == MicroInstrOpcode::JumpCond)
    {
        // Record this edge's state for the target label's join. The store
        // phase ran, so every recorded mapping has a coherent home on this
        // edge as well.
        BoundarySnapshot& snapshot = boundarySnapshots_[instructionIndex];
        snapshot.clear();
        for (const uint32_t denseIndex : mappedVirtualIndices_)
            snapshot.push_back({denseIndex, states_[denseIndex].phys});
    }
}

void MicroRegisterAllocationPass::clearAllMappedVirtuals()
{
    for (const uint32_t denseIndex : mappedVirtualIndices_)
    {
        auto& regState = states_[denseIndex];
        SWC_ASSERT(regState.mapped);
        retireRematDef(regState);
        const MicroReg physReg   = regState.phys;
        regState.mapped          = false;
        regState.mappedListIndex = std::numeric_limits<uint32_t>::max();
        regState.phys            = MicroReg::invalid();
        returnToFreePool(physReg);
    }

    mappedVirtualIndices_.clear();
}

void MicroRegisterAllocationPass::expireDeadMappings(uint32_t stamp)
{
    // Eager expiry is an optimization of this pass's bookkeeping, not of the
    // emitted code, so skipping it under control flow costs nothing: a dead
    // mapping is already reclaimable for free on demand. isCandidateBetter
    // ranks dead victims first, and allocatePhysical evicts one without
    // emitting a spill, so the allocator never spills a live value while a dead
    // one holds a register. flushAllMappedVirtuals and
    // spillMappedVirtualsForConcreteTouches likewise skip dead values.
    //
    // Lifting the guard was measured (2026-07-31) on the six bench/ tasks: same
    // instruction count, same stack-access count, only different register
    // names. The real cost in those loops is the boundary flush in
    // rewriteInstructions, which round-trips every live value through memory at
    // each terminator and join.
    if (hasControlFlow_)
        return;

    const auto& virtualRegs = denseVirtualRegs_.regs();
    for (size_t mappedIndex = 0; mappedIndex < mappedVirtualIndices_.size();)
    {
        const uint32_t denseIndex = mappedVirtualIndices_[mappedIndex];
        SWC_ASSERT(denseIndex < virtualRegs.size());
        const MicroReg virtKey = virtualRegs[denseIndex];
        if (isLiveOut(virtKey, stamp))
        {
            ++mappedIndex;
            continue;
        }

        const MicroReg deadReg = states_[denseIndex].phys;
        unmapVirtReg(virtKey);
        returnToFreePool(deadReg);
    }
}

void MicroRegisterAllocationPass::rewriteInstructions()
{
    // Main rewrite pass:
    // 1) assign physical registers for each virtual operand,
    // 2) queue spill loads/stores around the instruction,
    // 3) release dead mappings.
    std::ranges::fill(liveStampByDenseIndex_, 0);
    uint32_t stamp      = 1;
    uint32_t idx        = 0;
    int64_t  stackDepth = 0;
    labelStackDepth_.clear();
    deferredLoopCarriedStores_.clear();
    if (hasControlFlow_)
        labelStackDepth_.reserve(instructions_->count() / 2 + 1);

    // Register mappings may survive a control-flow boundary only when the CFG
    // is precise: the join intersection walks predecessor lists, and an edge
    // the CFG cannot see (computed jump, unresolvable target) would make a
    // kept register silently wrong. When the gate is off, every boundary
    // falls back to the full flush.
    boundarySnapshots_.clear();
    keepAcrossBoundaries_ = hasControlFlow_ &&
                            controlFlowGraph_ != nullptr &&
                            !controlFlowGraph_->hasUnsupportedControlFlowForCfgLiveness() &&
                            controlFlowGraph_->supportsDeadCodeLiveness();
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it)
    {
        if (stamp == std::numeric_limits<uint32_t>::max())
        {
            std::ranges::fill(liveStampByDenseIndex_, 0);
            stamp = 1;
        }
        ++stamp;

        computeCurrentLiveOutBits(idx);
        markCurrentVirtualLiveOut(stamp);
        rebuildCurrentConcreteLiveOutRegs();
        advanceCurrentPositionCursors(idx);
        const bool currentReachable = !hasControlFlow_ || isInstructionReachable(idx);

        if (it->op == MicroInstrOpcode::Label)
        {
            if (currentReachable)
            {
                const MicroInstrOperand* ops = it->ops(*operands_);
                const MicroLabelRef      labelRef(static_cast<uint32_t>(ops[0].valueU64));
                const auto               labelIt = labelStackDepth_.find(labelRef);
                if (labelIt != labelStackDepth_.end())
                    stackDepth = labelIt->second;
            }
        }

        const MicroInstrRef instructionRef = it.current;
        const bool          isCall         = instructionUseDefs_[idx].isCall;
        const bool          isTerminator   = MicroInstrInfo::isTerminatorInstruction(*it);

        // Flush the write-through stores queued by the previous instruction's
        // loop-carried defs. They land right after that instruction (before this
        // one) so the value's home slot is updated before any boundary flush,
        // call, or branch of the current instruction can act on it.
        for (const auto& storeInst : deferredLoopCarriedStores_)
            insertPending(instructionRef, storeInst);
        deferredLoopCarriedStores_.clear();

        // Give back a register borrowed from a previous sweep, now that the
        // value that borrowed it is past its last use. The range was checked to
        // be straight-line, so this reload runs exactly once for its save, and
        // at the same stack depth.
        for (size_t restoreIndex = 0; restoreIndex < pendingBorrowRestores_.size();)
        {
            const BorrowRestore& restore = pendingBorrowRestores_[restoreIndex];
            if (restore.atIndex != idx)
            {
                ++restoreIndex;
                continue;
            }

            PendingInsert reload;
            reload.op              = MicroInstrOpcode::LoadRegMem;
            reload.numOps          = 4;
            reload.ops[0].reg      = restore.physReg;
            reload.ops[1].reg      = conv_->stackPointer;
            reload.ops[2].opBits   = restore.slotBits;
            reload.ops[3].valueU64 = spillMemOffset(restore.slotOffset, stackDepth);
            insertPending(instructionRef, reload);
            pendingBorrowRestores_.erase(pendingBorrowRestores_.begin() + restoreIndex);
        }

        // With globals assigned, this is expected to spill nothing: a value
        // still live here either owns a register for its whole range or kept a
        // memory home. It stays as the fallback for the latter.
        if (isFlushBoundary(idx, *it))
        {
            boundaryPending_.clear();
            if (keepAcrossBoundaries_)
                flushAtBoundary(idx, *it, stamp, stackDepth, boundaryPending_);
            else
                flushAllMappedVirtuals(stamp, stackDepth, boundaryPending_);
            for (const auto& pendingInst : boundaryPending_)
            {
                insertPending(instructionRef, pendingInst);
            }
        }

        // A fixed-register write must never land on a register a global owns at
        // this point: the global is not in the mapping, so nothing else would
        // notice the clobber.
        for (const uint32_t concreteDense : defConcreteIndices_[idx])
        {
            const MicroReg concreteReg = denseConcreteRegs_.regs()[concreteDense];
            const uint32_t globalDense = denseGlobalPhysRegs_.find(concreteReg);
            if (globalDense == MicroDenseRegIndex::K_INVALID_INDEX || globalDense >= globalRangesByPhysDense_.size())
                continue;
            for (const GlobalRange& range : globalRangesByPhysDense_[globalDense])
            {
                // A call's implicit clobber of a call-saved pinned register is
                // the one expected overlap: the value sits parked in its slot
                // for exactly the call's duration.
                if (isCall && isPinnedCallSavedOwner(range.ownerDense))
                    continue;
                SWC_ASSERT(idx < range.lo || idx > range.hi);
            }
        }

        SmallVector<MicroInstrRegOperandRef> regRefs;
        it->collectRegOperands(*operands_, regRefs, context_->encoder);

        SmallVector<MicroReg> protectedKeys;
        protectedKeys.reserve(regRefs.size());
        for (const auto& regRef : regRefs)
        {
            if (!regRef.reg)
                continue;

            const auto reg = *regRef.reg;
            if (!reg.isVirtual())
                continue;

            if (!containsKey(protectedKeys, reg))
                protectedKeys.push_back(reg);
        }

        SmallVector<AllocRequest> allocRequests;
        allocRequests.reserve(protectedKeys.size());
        for (const auto& regRef : regRefs)
        {
            if (!regRef.reg)
                continue;

            const auto reg = *regRef.reg;
            if (!reg.isVirtual())
                continue;

            AllocRequest* existing = nullptr;
            for (auto& request : allocRequests)
            {
                if (request.virtKey == reg)
                {
                    existing = &request;
                    break;
                }
            }

            if (!existing)
            {
                auto& request            = allocRequests.emplace_back();
                request.virtReg          = reg;
                request.virtKey          = reg;
                request.instructionIndex = idx;
                existing                 = &request;
            }

            existing->isUse = existing->isUse || regRef.use;
            existing->isDef = existing->isDef || regRef.def;
        }

        const MicroInstrOperand* instOps = it->ops(*operands_);
        for (auto& request : allocRequests)
        {
            if (!instOps || !request.isDef || request.isUse)
                continue;
            if (!isRegisterCopyLike(it->op) || instOps[0].reg != request.virtKey)
                continue;

            const MicroReg srcReg = instOps[1].reg;
            if (!request.virtKey.isSameClass(srcReg))
                continue;

            if (srcReg.isVirtual())
                request.transferSource = srcReg;
            else if (srcReg.isInt() || srcReg.isFloat())
                request.preferredPhysReg = srcReg;
        }

        std::ranges::stable_sort(allocRequests, compareAllocRequests);

        SmallVector<MicroReg> mentionedConcreteRegs;
        mentionedConcreteRegs.reserve(instructionUseDefs_[idx].uses.size() + instructionUseDefs_[idx].defs.size());
        for (const MicroReg reg : instructionUseDefs_[idx].uses)
        {
            if ((!reg.isInt() && !reg.isFloat()) || containsKey(mentionedConcreteRegs, reg))
                continue;
            mentionedConcreteRegs.push_back(reg);
        }

        for (const MicroReg reg : instructionUseDefs_[idx].defs)
        {
            if ((!reg.isInt() && !reg.isFloat()) || containsKey(mentionedConcreteRegs, reg))
                continue;
            mentionedConcreteRegs.push_back(reg);
        }

        SmallVector<MicroReg> addressSourceRegs;
        addressSourceRegs.reserve(2);
        if (instOps)
        {
            if (it->op == MicroInstrOpcode::LoadAddrRegMem)
            {
                const MicroReg baseReg = instOps[1].reg;
                if ((baseReg.isInt() || baseReg.isFloat()) && isCurrentConcreteLiveOut(baseReg))
                    appendUniqueReg(addressSourceRegs, baseReg);
            }
            else if (it->op == MicroInstrOpcode::LoadAddrAmcRegMem)
            {
                const MicroReg baseReg = instOps[1].reg;
                if ((baseReg.isInt() || baseReg.isFloat()) && isCurrentConcreteLiveOut(baseReg))
                    appendUniqueReg(addressSourceRegs, baseReg);

                const MicroReg mulReg = instOps[2].reg;
                if ((mulReg.isInt() || mulReg.isFloat()) && isCurrentConcreteLiveOut(mulReg))
                    appendUniqueReg(addressSourceRegs, mulReg);
            }
        }

        SmallVector<MicroReg> destructiveLoadLiveBases;
        destructiveLoadLiveBases.reserve(1);
        SmallVector<DestructiveAlias> destructiveConcreteAliases;
        destructiveConcreteAliases.reserve(2);
        collectDestructiveLoadConstraints(destructiveLoadLiveBases, destructiveConcreteAliases, *it, instOps, stamp);

        pending_.clear();

        spillMappedVirtualsForConcreteTouches(instructionUseDefs_[idx], protectedKeys, stamp, stackDepth, pending_);

        struct AssignedPhysReg
        {
            MicroReg virtKey = MicroReg::invalid();
            MicroReg physReg = MicroReg::invalid();
        };

        SmallVector<AssignedPhysReg> assignedPhysRegs;
        assignedPhysRegs.reserve(allocRequests.size());

        for (const auto& requestInfo : allocRequests)
        {
            AllocRequest request = requestInfo;
            const bool   defOnlyCopyFromConcrete =
                request.isDef &&
                !request.isUse &&
                instOps &&
                instOps[0].reg == request.virtKey &&
                ((it->op == MicroInstrOpcode::LoadRegReg && !instOps[1].reg.isVirtual()) ||
                 (it->op == MicroInstrOpcode::LoadSignedExtRegReg && !instOps[1].reg.isVirtual()) ||
                 (it->op == MicroInstrOpcode::LoadZeroExtRegReg && !instOps[1].reg.isVirtual()));

            SmallVector<MicroReg> forbiddenPhysRegs;
            forbiddenPhysRegs.reserve((defOnlyCopyFromConcrete ? currentConcreteLiveOut_.size() : 0) + addressSourceRegs.size() + mentionedConcreteRegs.size() + assignedPhysRegs.size());
            SmallVector<MicroReg> remapForbiddenPhysRegs;
            remapForbiddenPhysRegs.reserve(1 + mentionedConcreteRegs.size() + assignedPhysRegs.size());
            if (defOnlyCopyFromConcrete)
            {
                for (const MicroReg key : currentConcreteLiveOut_)
                {
                    if (!request.virtReg.isSameClass(key))
                        continue;
                    if (!isConcreteLiveInAt(key, idx))
                        continue;
                    if (containsKey(mentionedConcreteRegs, key))
                        continue;
                    forbiddenPhysRegs.push_back(key);
                }
            }

            for (const MicroReg key : addressSourceRegs)
            {
                appendUniqueReg(forbiddenPhysRegs, key);
            }

            for (const MicroReg key : destructiveLoadLiveBases)
            {
                if (!request.isDef || key == request.virtKey)
                    continue;

                const auto& protectedState = stateForVirtual(key);
                if (!protectedState.mapped)
                    continue;

                const MicroReg protectedPhys = protectedState.phys;
                appendUniqueReg(forbiddenPhysRegs, protectedPhys);
            }

            for (const auto& alias : destructiveConcreteAliases)
            {
                if (alias.virtKey != request.virtKey || containsKey(forbiddenPhysRegs, alias.physReg))
                    continue;

                appendUniqueReg(forbiddenPhysRegs, alias.physReg);
                appendUniqueReg(remapForbiddenPhysRegs, alias.physReg);
            }

            if (!isRegisterCopyLike(it->op))
            {
                for (const MicroReg key : mentionedConcreteRegs)
                {
                    if (!request.virtReg.isSameClass(key))
                        continue;

                    appendUniqueReg(forbiddenPhysRegs, key);
                    appendUniqueReg(remapForbiddenPhysRegs, key);
                }

                for (const auto& assigned : assignedPhysRegs)
                {
                    if (assigned.virtKey == request.virtKey)
                        continue;
                    if (!request.virtReg.isSameClass(assigned.physReg))
                        continue;

                    appendUniqueReg(forbiddenPhysRegs, assigned.physReg);
                    appendUniqueReg(remapForbiddenPhysRegs, assigned.physReg);
                }
            }

            const bool liveAcrossCall = isLiveAcrossCall(request.virtKey);
            // A callee-saved FLOAT register is only worth its prologue
            // save/restore for a value that crosses calls which actually run
            // and do so more than once flat (or inside a loop); one whose
            // calls are guard-shadowed or rare is cheaper spilled around
            // them. Ints keep the simple any-call rule: their persistent
            // save is a one-byte push, not a two-instruction 16-byte slot
            // round-trip.
            if (request.virtReg.isVirtualInt())
                request.needsPersistent = liveAcrossCall && !conv_->intPersistentRegs.empty();
            else
                request.needsPersistent = isLiveAcrossHotCall(request.virtKey) && !conv_->floatPersistentRegs.empty();

            // If no persistent class exists, remember to spill around call boundaries.
            clearCallSpill(request.virtKey);
            if (liveAcrossCall && !request.needsPersistent)
                markCallSpill(request.virtKey);

            const auto      physReg = assignVirtReg(request, protectedKeys, forbiddenPhysRegs, remapForbiddenPhysRegs, stamp, stackDepth, pending_);
            AssignedPhysReg assignedPhysReg;
            assignedPhysReg.virtKey = request.virtKey;
            assignedPhysReg.physReg = physReg;
            assignedPhysRegs.push_back(assignedPhysReg);

            if (liveAcrossCall && !isPersistentPhysReg(physReg))
                markCallSpill(request.virtKey);
            else
                clearCallSpill(request.virtKey);

            if (request.isDef)
            {
                auto& regState = stateForVirtual(request.virtKey);
                updateRematerializationForDef(regState, request.virtKey, it.current, *it, instOps);
                regState.dirty = true;

                // Write-through a loop-carried value to its stable home right after
                // this defining instruction. The home then always holds the latest
                // value, so the reload at the loop header is correct no matter where
                // the register mapping is later dropped (call clobber, concrete-reg
                // eviction, boundary flush) â€” the linear, loop-unaware live-out
                // estimate cannot be trusted to spill it at those points. Pinned
                // values stay register-resident across the loop and are exempt.
                if (regState.loopCarriedHome && !regState.pinned && regState.mapped && regState.hasSpill)
                {
                    PendingInsert storePending;
                    queueSpillStore(storePending, physReg, regState, stackDepth);
                    deferredLoopCarriedStores_.push_back(storePending);
                    regState.dirty = false;
                }
            }
        }

        for (const auto& regRef : regRefs)
        {
            if (!regRef.reg)
                continue;

            const auto reg = *regRef.reg;
            if (!reg.isVirtual())
                continue;

            for (const auto& assigned : assignedPhysRegs)
            {
                if (assigned.virtKey != reg)
                    continue;

                *(regRef.reg) = assigned.physReg;
                break;
            }
        }

        if (it->op == MicroInstrOpcode::LoadRegReg)
        {
            const MicroInstrOperand* rewrittenOps = it->ops(*operands_);
            if (rewrittenOps && rewrittenOps[0].reg == rewrittenOps[1].reg)
            {
                // mov rX, rX: drop the instruction entirely. We can't erase here
                // because the iterator would become invalid; queue for end-of-pass.
                queueErase(instructionRef);
            }
        }

        if (isCall)
        {
            spillCallLiveOut(stamp, stackDepth, pending_);
            saveRestorePinnedAcrossCall(idx, stackDepth, pending_);
        }

        for (const auto& pendingInst : pending_)
        {
            insertPending(instructionRef, pendingInst);
        }

        expireDeadMappings(stamp);

        if (it->op == MicroInstrOpcode::JumpCond)
        {
            if (currentReachable)
            {
                const MicroInstrOperand* ops = it->ops(*operands_);
                const MicroLabelRef      labelRef(static_cast<uint32_t>(ops[2].valueU64));
                mergeLabelStackDepth(labelStackDepth_, labelRef, stackDepth);
            }
        }

        if (currentReachable)
            applyStackPointerDelta(stackDepth, *it);

        if (hasControlFlow_ && isTerminator)
            clearAllMappedVirtuals();

        ++idx;
    }
}

void MicroRegisterAllocationPass::insertSpillFrame() const
{
    // Materialize one function-level spill frame and balance it before every return.
    if (!spillFrameUsed_)
        return;

    const uint64_t stackAlignment = conv_->stackAlignment ? conv_->stackAlignment : 16;
    const uint64_t spillFrameSize = Math::alignUpU64(spillFrameUsed_, stackAlignment);
    if (!spillFrameSize)
        return;

    const auto beginIt = instructions_->view().begin();
    if (beginIt == instructions_->view().end())
        return;

    const MicroInstrRef firstRef = beginIt.current;

    MicroInstrOperand subOps[4];
    subOps[0].reg      = conv_->stackPointer;
    subOps[1].opBits   = MicroOpBits::B64;
    subOps[2].microOp  = MicroOp::Subtract;
    subOps[3].valueU64 = spillFrameSize;
    instructions_->insertSyntheticBefore(*operands_, firstRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

    SmallVector<MicroInstrRef> retRefs;
    for (auto it = instructions_->view().begin(); it != instructions_->view().end(); ++it)
    {
        if (it->op == MicroInstrOpcode::Ret)
            retRefs.push_back(it.current);
    }

    for (const auto retRef : retRefs)
    {
        MicroInstrOperand addOps[4];
        addOps[0].reg      = conv_->stackPointer;
        addOps[1].opBits   = MicroOpBits::B64;
        addOps[2].microOp  = MicroOp::Add;
        addOps[3].valueU64 = spillFrameSize;
        instructions_->insertSyntheticBefore(*operands_, retRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
    }
}

void MicroRegisterAllocationPass::clearState()
{
    context_          = nullptr;
    conv_             = nullptr;
    instructions_     = nullptr;
    operands_         = nullptr;
    instructionCount_ = 0;
    spillFrameUsed_   = 0;
    hasControlFlow_   = false;
    hasVirtualRegs_   = false;
    controlFlowGraph_ = nullptr;

    vregsLiveAcrossCall_.clear();
    vregsLiveAcrossHotCall_.clear();
    guardedCallPositions_.clear();
    instructionUseDefs_.clear();
    denseVirtualRegs_.clear();
    denseConcreteRegs_.clear();
    useVirtualIndices_.clear();
    defVirtualIndices_.clear();
    useConcreteIndices_.clear();
    defConcreteIndices_.clear();
    usePositionsByDenseVirtual_.clear();
    concreteTouchPositionsByDenseIndex_.clear();
    nextUsePositionCursor_.clear();
    nextConcreteTouchCursor_.clear();
    liveInVirtualBits_.clear();
    liveInConcreteBits_.clear();
    predecessors_.clear();
    loopDepth_.clear();
    concreteLoopCarried_.clear();
    virtualSpanLo_.clear();
    virtualSpanHi_.clear();
    concreteClaimPositionsByDenseIndex_.clear();
    denseGlobalPhysRegs_.clear();
    pendingBorrowRestores_.clear();
    pinnedCallSavedDense_.clear();
    globalRangesByPhysDense_.clear();
    reachableInstructions_.clear();
    worklist_.clear();
    inWorklist_.clear();
    tempOutVirtual_.clear();
    tempInVirtual_.clear();
    tempOutConcrete_.clear();
    tempInConcrete_.clear();
    definitionCounts_.clear();
    liveStampByDenseIndex_.clear();
    callSpillFlags_.clear();
    mappedVirtualIndices_.clear();
    currentConcreteLiveOut_.clear();
    intPersistentRegs_.clear();
    floatPersistentRegs_.clear();
    freeIntTransient_.clear();
    freeIntPersistent_.clear();
    freeFloatTransient_.clear();
    freeFloatPersistent_.clear();
    states_.clear();
    pendingErasures_.clear();
    pending_.clear();
    boundaryPending_.clear();
    labelStackDepth_.clear();
}

Result MicroRegisterAllocationPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/RegAlloc");
    SWC_ASSERT(context.instructions);

    clearState();
    initState(context);
    coalesceLocalCopies();
    instructionCount_ = instructions_->count();
    instructionUseDefs_.clear();
    instructionUseDefs_.resize(instructionCount_);

    prepareInstructionData();
    if (!hasVirtualRegs_)
        return Result::Continue;

    computeGuardedCallPositions();
    analyzeLiveness();
    computeVirtualLiveSpans();
    setupPools();
    assignGlobalRegisters();
    preallocateLoopCarriedSlots();

    rewriteInstructions();
    flushQueuedErasures();
    insertSpillFrame();

    return Result::Continue;
}

SWC_END_NAMESPACE();
