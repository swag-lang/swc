#include "pch.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
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

// Assigns physical registers to virtual registers and handles spills.
// Example: v3 -> rax when a free compatible register exists.
// Example: under pressure, v7 lives on stack: store v7 before conflict, reload before use.
// This pass converts virtual microcode into concrete register form.

SWC_BEGIN_NAMESPACE();

namespace
{
    template<typename T>
    size_t vectorStorageReserved(const std::vector<T>& values)
    {
        return values.capacity() * sizeof(T);
    }

    template<typename T, size_t InlineCapacity>
    size_t smallVectorStorageReserved(const SmallVector<T, InlineCapacity>& values)
    {
        if (values.isInline())
            return 0;
        return values.capacity() * sizeof(T);
    }

    template<typename K, typename V, typename H, typename E, typename A>
    size_t unorderedMapStorageReserved(const std::unordered_map<K, V, H, E, A>& map)
    {
        return map.bucket_count() * sizeof(void*) +
               map.size() * (sizeof(std::pair<const K, V>) + sizeof(void*));
    }

    template<typename K, typename H, typename E, typename A>
    size_t unorderedSetStorageReserved(const std::unordered_set<K, H, E, A>& set)
    {
        return set.bucket_count() * sizeof(void*) +
               set.size() * (sizeof(K) + sizeof(void*));
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
    usePositions_.reserve(128);
    concreteTouchPositions_.reserve(32);

    for (const auto& inst : instructions_->view())
    {
        if (inst.op == MicroInstrOpcode::Label || MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::JumpInstruction))
        {
            hasControlFlow_ = true;
            break;
        }
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

void MicroRegisterAllocationPass::markLiveAcrossCall(MicroReg key)
{
    const uint32_t denseIndex = denseVirtualIndex(key);
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
    const uint32_t denseIndex = denseVirtualIndex(key);
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
        return intPersistentSet_.contains(reg);

    if (reg.isFloat())
        return floatPersistentSet_.contains(reg);

    SWC_ASSERT(false);
    return false;
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

    const auto it = concreteTouchPositions_.find(physReg);
    if (it == concreteTouchPositions_.end())
        return false;

    const auto nextTouchIt = std::ranges::upper_bound(it->second, instructionIndex);
    if (nextTouchIt == it->second.end())
        return false;

    return isLiveInAt(virtKey, *nextTouchIt);
}

bool MicroRegisterAllocationPass::tryTakeAllowedPhysical(SmallVector<MicroReg>& pool,
                                                         MicroReg               virtKey,
                                                         uint32_t               instructionIndex,
                                                         MicroRegSpan           forbiddenPhysRegs,
                                                         bool                   allowConcreteLive,
                                                         MicroReg&              outPhys) const
{
    for (size_t index = pool.size(); index > 0; --index)
    {
        const size_t candidateIndex = index - 1;
        const auto   candidateReg   = pool[candidateIndex];
        if (containsKey(forbiddenPhysRegs, candidateReg))
            continue;
        if (isPhysRegForbiddenForVirtual(virtKey, candidateReg))
            continue;
        if (!allowConcreteLive && hasFutureConcreteTouchConflict(virtKey, candidateReg, instructionIndex))
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
        if (intPersistentSet_.contains(reg))
            freeIntPersistent_.push_back(reg);
        else
            freeIntTransient_.push_back(reg);
        return;
    }

    if (reg.isFloat())
    {
        if (floatPersistentSet_.contains(reg))
            freeFloatPersistent_.push_back(reg);
        else
            freeFloatTransient_.push_back(reg);
        return;
    }

    SWC_ASSERT(false);
}

uint32_t MicroRegisterAllocationPass::distanceToNextUse(MicroReg key, uint32_t instructionIndex) const
{
    const auto useIt = usePositions_.find(key);
    if (useIt == usePositions_.end())
        return std::numeric_limits<uint32_t>::max();

    const auto& positions = useIt->second;
    const auto  it        = std::ranges::upper_bound(positions, instructionIndex);
    if (it == positions.end())
        return std::numeric_limits<uint32_t>::max();

    return *it - instructionIndex;
}

void MicroRegisterAllocationPass::prepareInstructionData()
{
    usePositions_.clear();

    controlFlowGraph_ = &((context_->builder)->controlFlowGraph());
    const std::span<const MicroInstrRef> instructionRefs = controlFlowGraph_->instructionRefs();
    SWC_ASSERT(instructionRefs.size() == instructionCount_);
    if (instructionRefs.size() != instructionCount_)
        return;

    bool hasVirtual = false;
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        const MicroInstr* const inst = instructions_->ptr(instructionRefs[idx]);
        if (!inst)
            continue;

        MicroInstrUseDef useDef = inst->collectUseDef(*operands_, context_->encoder);
        for (const MicroReg reg : useDef.uses)
        {
            if (!reg.isVirtual())
                continue;

            hasVirtual = true;
            usePositions_[reg].push_back(idx);
        }

        for (const MicroReg reg : useDef.defs)
        {
            if (reg.isVirtual())
                hasVirtual = true;
        }

        instructionUseDefs_[idx] = std::move(useDef);
    }

    hasVirtualRegs_       = hasVirtual;
    context_->passChanged = hasVirtual;
}

void MicroRegisterAllocationPass::analyzeLiveness()
{
    // CFG-aware backward liveness: captures live-out sets even across back-edges.
    concreteTouchPositions_.clear();

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
                usesV.push_back(regIndex);
            }
            else if (reg.isInt() || reg.isFloat())
            {
                const uint32_t regIndex = denseConcreteRegs_.ensure(reg);
                usesC.push_back(regIndex);
                auto& concreteTouches = concreteTouchPositions_[reg];
                if (concreteTouches.empty() || concreteTouches.back() != idx)
                    concreteTouches.push_back(idx);
            }
        }

        for (const MicroReg reg : useDef.defs)
        {
            if (reg.isVirtual())
            {
                const uint32_t regIndex = denseVirtualRegs_.ensure(reg);
                defsV.push_back(regIndex);
            }
            else if (reg.isInt() || reg.isFloat())
            {
                const uint32_t regIndex = denseConcreteRegs_.ensure(reg);
                defsC.push_back(regIndex);
                auto& concreteTouches = concreteTouchPositions_[reg];
                if (concreteTouches.empty() || concreteTouches.back() != idx)
                    concreteTouches.push_back(idx);
            }
        }

        if (useDef.isCall)
        {
            const CallConv& callConv = CallConv::get(useDef.callConv);
            for (const MicroReg reg : callConv.intTransientRegs)
            {
                const uint32_t regIndex = denseConcreteRegs_.ensure(reg);
                defsC.push_back(regIndex);
            }
            for (const MicroReg reg : callConv.floatTransientRegs)
            {
                const uint32_t regIndex = denseConcreteRegs_.ensure(reg);
                defsC.push_back(regIndex);
            }
        }
    }

    const uint32_t virtualWordCount  = denseVirtualRegs_.wordCount();
    const uint32_t concreteWordCount = denseConcreteRegs_.wordCount();
    const auto&    virtualRegs       = denseVirtualRegs_.regs();
    const auto&    concreteRegs      = denseConcreteRegs_.regs();

    states_.clear();
    states_.resize(virtualRegs.size());
    liveStampByDenseIndex_.assign(virtualRegs.size(), 0);
    vregsLiveAcrossCall_.assign(virtualRegs.size(), 0);
    callSpillFlags_.assign(virtualRegs.size(), 0);
    mappedVirtualIndices_.clear();
    mappedVirtualIndices_.reserve(virtualRegs.size());
    currentConcreteLiveOut_.clear();

    liveInVirtualBits_.assign(static_cast<size_t>(instructionCount_) * virtualWordCount, 0);
    liveInConcreteBits_.assign(static_cast<size_t>(instructionCount_) * concreteWordCount, 0);

    predecessors_.resize(instructionCount_);
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        predecessors_[idx].clear();
        const auto& successors = controlFlowGraph.successors(idx);
        for (const uint32_t succIdx : successors)
        {
            if (succIdx >= instructionCount_)
                continue;
            predecessors_[succIdx].push_back(idx);
        }
    }

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
                wordBits &= (wordBits - 1ull);
            }
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

void MicroRegisterAllocationPass::setupPools()
{
    // Build free lists split by class (int/float) and persistence (transient/persistent).
    intPersistentSet_.clear();
    floatPersistentSet_.clear();
    intPersistentSet_.reserve(conv_->intPersistentRegs.size() * 2 + 8);
    floatPersistentSet_.reserve(conv_->floatPersistentRegs.size() * 2 + 8);

    for (const auto reg : conv_->intPersistentRegs)
        intPersistentSet_.insert(reg);

    for (const auto reg : conv_->floatPersistentRegs)
        floatPersistentSet_.insert(reg);

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

        if (intPersistentSet_.contains(reg))
            freeIntPersistent_.push_back(reg);
        else
            freeIntTransient_.push_back(reg);
    }

    for (const auto reg : conv_->floatRegs)
    {
        if (floatPersistentSet_.contains(reg))
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

    const MicroOpBits bits     = isFloat ? MicroOpBits::B128 : MicroOpBits::B64;
    const uint64_t    slotSize = bits == MicroOpBits::B128 ? 16u : 8u;
    spillFrameUsed_            = Math::alignUpU64(spillFrameUsed_, slotSize);

    regState.spillOffset = spillFrameUsed_;
    regState.spillBits   = bits;
    regState.hasSpill    = true;
    spillFrameUsed_ += slotSize;
    context_->passChanged = true;
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

bool MicroRegisterAllocationPass::isCandidateBetter(MicroReg candidateKey,
                                                    MicroReg candidateReg,
                                                    MicroReg currentBestKey,
                                                    MicroReg currentBestReg,
                                                    uint32_t instructionIndex,
                                                    uint32_t stamp) const
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

bool MicroRegisterAllocationPass::selectEvictionCandidate(MicroReg     requestVirtKey,
                                                          uint32_t     instructionIndex,
                                                          bool         isFloatReg,
                                                          bool         fromPersistentPool,
                                                          MicroRegSpan protectedKeys,
                                                          MicroRegSpan forbiddenPhysRegs,
                                                          uint32_t     stamp,
                                                          bool         allowConcreteLive,
                                                          MicroReg&    outVirtKey,
                                                          MicroReg&    outPhys) const
{
    // Choose mapped virtual reg that is cheapest to evict under current constraints.
    outVirtKey = MicroReg::invalid();
    outPhys    = MicroReg::invalid();

    const auto& virtualRegs = denseVirtualRegs_.regs();
    for (const uint32_t mappedDenseIndex : mappedVirtualIndices_)
    {
        SWC_ASSERT(mappedDenseIndex < virtualRegs.size());
        const MicroReg virtKey = virtualRegs[mappedDenseIndex];
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

        if (isPhysRegForbiddenForVirtual(requestVirtKey, physReg))
            continue;
        if (!allowConcreteLive && hasFutureConcreteTouchConflict(requestVirtKey, physReg, instructionIndex))
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

    return FreePools{&freeFloatTransient_, freeFloatPersistent_.empty() ? nullptr : &freeFloatPersistent_};
}

bool MicroRegisterAllocationPass::tryTakeFreePhysical(const AllocRequest& request,
                                                      MicroRegSpan        forbiddenPhysRegs,
                                                      bool                allowConcreteLive,
                                                      MicroReg&           outPhys)
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

    SWC_ASSERT(regState.mappedListIndex != std::numeric_limits<uint32_t>::max());
    SWC_ASSERT(regState.mappedListIndex < mappedVirtualIndices_.size());

    const uint32_t removedListIndex = regState.mappedListIndex;
    const uint32_t lastDenseIndex   = mappedVirtualIndices_.back();
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
    auto& regState = stateForVirtual(virtKey);
    if (!regState.mapped)
    {
        regState.mappedListIndex = static_cast<uint32_t>(mappedVirtualIndices_.size());
        mappedVirtualIndices_.push_back(denseVirtualIndex(virtKey));
        regState.mapped = true;
    }

    regState.phys   = physReg;
}

bool MicroRegisterAllocationPass::selectEvictionCandidateWithFallback(MicroReg     requestVirtKey,
                                                                      uint32_t     instructionIndex,
                                                                      bool         isFloatReg,
                                                                      bool         preferPersistentPool,
                                                                      MicroRegSpan protectedKeys,
                                                                      MicroRegSpan forbiddenPhysRegs,
                                                                      uint32_t     stamp,
                                                                      bool         allowConcreteLive,
                                                                      MicroReg&    outVirtKey,
                                                                      MicroReg&    outPhys) const
{
    if (selectEvictionCandidate(requestVirtKey, instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, forbiddenPhysRegs, stamp, allowConcreteLive, outVirtKey, outPhys))
        return true;

    return selectEvictionCandidate(requestVirtKey, instructionIndex, isFloatReg, !preferPersistentPool, protectedKeys, forbiddenPhysRegs, stamp, allowConcreteLive, outVirtKey, outPhys);
}

MicroReg MicroRegisterAllocationPass::allocatePhysical(const AllocRequest&         request,
                                                       MicroRegSpan                protectedKeys,
                                                       MicroRegSpan                forbiddenPhysRegs,
                                                       uint32_t                    stamp,
                                                       int64_t                     stackDepth,
                                                       std::vector<PendingInsert>& pending)
{
    // Prefer free registers; otherwise evict one candidate and spill if needed.
    MicroReg physReg;
    if (tryTakeFreePhysical(request, forbiddenPhysRegs, false, physReg))
        return physReg;
    if (tryTakeFreePhysical(request, forbiddenPhysRegs, true, physReg))
        return physReg;

    MicroReg victimKey = MicroReg::invalid();
    MicroReg victimReg;

    const bool isFloatReg           = request.virtReg.isVirtualFloat();
    const bool preferPersistentPool = request.needsPersistent;
    if (!selectEvictionCandidateWithFallback(request.virtKey, request.instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, forbiddenPhysRegs, stamp, false, victimKey, victimReg))
    {
        if (!selectEvictionCandidateWithFallback(request.virtKey, request.instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, forbiddenPhysRegs, stamp, true, victimKey, victimReg))
        {
            SWC_INTERNAL_CHECK(false);
        }
    }

    auto&      victimState   = stateForVirtual(victimKey);
    const bool victimLiveOut = isLiveOut(victimKey, stamp);
    if (victimLiveOut)
    {
        const bool hadSpillSlot = victimState.hasSpill;
        ensureSpillSlot(victimState, victimReg.isFloat());
        if (victimState.dirty || !hadSpillSlot)
        {
            PendingInsert spillPending;
            queueSpillStore(spillPending, victimReg, victimState, stackDepth);
            pending.push_back(spillPending);
            victimState.dirty = false;
        }
    }

    unmapVirtReg(victimKey);
    return victimReg;
}

void MicroRegisterAllocationPass::recordDestructiveAlias(SmallVector<MicroReg>&         liveBases,
                                                         SmallVector<DestructiveAlias>& concreteAliases,
                                                         const MicroReg                 dstReg,
                                                         const MicroReg                 baseReg,
                                                         const uint32_t                 stamp,
                                                         const bool                     trackVirtualDestConflict) const
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

    concreteAliases.push_back({baseReg, dstReg});
}

void MicroRegisterAllocationPass::collectDestructiveLoadConstraints(SmallVector<MicroReg>&         liveBases,
                                                                    SmallVector<DestructiveAlias>& concreteAliases,
                                                                    const MicroInstr&              inst,
                                                                    const MicroInstrOperand*       instOps,
                                                                    const uint32_t                 stamp) const
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

MicroReg MicroRegisterAllocationPass::assignVirtReg(const AllocRequest&         request,
                                                    MicroRegSpan                protectedKeys,
                                                    MicroRegSpan                forbiddenPhysRegs,
                                                    MicroRegSpan                remapForbiddenPhysRegs,
                                                    uint32_t                    stamp,
                                                    int64_t                     stackDepth,
                                                    std::vector<PendingInsert>& pending)
{
    // Reuse existing mapping when possible, otherwise allocate and load from spill on use.
    auto& regState = stateForVirtual(request.virtKey);
    if (regState.mapped &&
        ((request.isDef && containsKey(forbiddenPhysRegs, regState.phys)) ||
         containsKey(remapForbiddenPhysRegs, regState.phys)))
    {
        const MicroReg conflictedPhys = regState.phys;
        if (request.isUse)
        {
            const bool hadSpillSlot = regState.hasSpill;
            ensureSpillSlot(regState, conflictedPhys.isFloat());
            if (regState.dirty || !hadSpillSlot)
            {
                PendingInsert spillPending;
                queueSpillStore(spillPending, conflictedPhys, regState, stackDepth);
                pending.push_back(spillPending);
                regState.dirty = false;
            }
        }

        unmapVirtReg(request.virtKey);
        returnToFreePool(conflictedPhys);
    }

    if (regState.mapped)
        return regState.phys;

    const auto physReg = allocatePhysical(request, protectedKeys, forbiddenPhysRegs, stamp, stackDepth, pending);
    mapVirtReg(request.virtKey, physReg);

    auto& mappedState = stateForVirtual(request.virtKey);
    if (request.isUse)
    {
        SWC_ASSERT(mappedState.hasSpill);
        PendingInsert loadPending;
        queueSpillLoad(loadPending, physReg, mappedState, stackDepth);
        pending.push_back(loadPending);
        mappedState.dirty = false;
    }

    return physReg;
}

void MicroRegisterAllocationPass::spillMappedVirtualsForConcreteTouches(const MicroInstrUseDef&     useDef,
                                                                        MicroRegSpan                protectedKeys,
                                                                        uint32_t                    stamp,
                                                                        int64_t                     stackDepth,
                                                                        std::vector<PendingInsert>& pending)
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
        const MicroReg virtKey = virtualRegs[denseIndex];
        auto&          regState = states_[denseIndex];
        SWC_ASSERT(regState.mapped);
        const MicroReg physReg = regState.phys;
        if (containsKey(protectedKeys, virtKey) || !containsKey(touchedRegs, physReg))
        {
            ++mappedIndex;
            continue;
        }

        if (isLiveOut(virtKey, stamp) && (regState.dirty || !regState.hasSpill))
        {
            ensureSpillSlot(regState, physReg.isFloat());
            PendingInsert spillPending;
            queueSpillStore(spillPending, physReg, regState, stackDepth);
            pending.push_back(spillPending);
            regState.dirty = false;
        }

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
        const MicroReg virtKey = virtualRegs[denseIndex];
        auto&          regState = states_[denseIndex];
        SWC_ASSERT(regState.mapped);
        const MicroReg physReg = regState.phys;

        if (!requiresCallSpill(virtKey) || !isLiveOut(virtKey, stamp))
        {
            ++mappedIndex;
            continue;
        }

        if (regState.dirty || !regState.hasSpill)
        {
            ensureSpillSlot(regState, physReg.isFloat());
            PendingInsert spillPending;
            queueSpillStore(spillPending, physReg, regState, stackDepth);
            pending.push_back(spillPending);
            regState.dirty = false;
        }

        unmapVirtReg(virtKey);
        returnToFreePool(physReg);
    }
}

void MicroRegisterAllocationPass::flushAllMappedVirtuals(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // Control-flow boundaries require a stable memory state for all mapped values.
    const auto& virtualRegs = denseVirtualRegs_.regs();
    for (const uint32_t denseIndex : mappedVirtualIndices_)
    {
        SWC_ASSERT(denseIndex < virtualRegs.size());
        const MicroReg virtKey = virtualRegs[denseIndex];
        auto&          regState = states_[denseIndex];
        SWC_ASSERT(regState.mapped);
        const MicroReg physReg = regState.phys;
        const bool liveOut  = isLiveOut(virtKey, stamp);
        if (liveOut && (regState.dirty || !regState.hasSpill))
        {
            ensureSpillSlot(regState, physReg.isFloat());
            PendingInsert spillPending;
            queueSpillStore(spillPending, physReg, regState, stackDepth);
            pending.push_back(spillPending);
            regState.dirty = false;
        }

        regState.mapped          = false;
        regState.mappedListIndex = std::numeric_limits<uint32_t>::max();
        regState.phys            = MicroReg::invalid();
        returnToFreePool(physReg);
    }

    mappedVirtualIndices_.clear();
}

void MicroRegisterAllocationPass::clearAllMappedVirtuals()
{
    for (const uint32_t denseIndex : mappedVirtualIndices_)
    {
        auto& regState           = states_[denseIndex];
        SWC_ASSERT(regState.mapped);
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
    // Linear dead-expiry is only safe when the instruction stream has no control-flow joins.
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
    std::fill(liveStampByDenseIndex_.begin(), liveStampByDenseIndex_.end(), 0);
    uint32_t                                   stamp      = 1;
    uint32_t                                   idx        = 0;
    int64_t                                    stackDepth = 0;
    std::unordered_map<MicroLabelRef, int64_t> labelStackDepth;
    if (hasControlFlow_)
        labelStackDepth.reserve(instructions_->count() / 2 + 1);
    for (auto it = instructions_->view().begin(); it != instructions_->view().end() && idx < instructionCount_; ++it)
    {
        if (stamp == std::numeric_limits<uint32_t>::max())
        {
            std::fill(liveStampByDenseIndex_.begin(), liveStampByDenseIndex_.end(), 0);
            stamp = 1;
        }
        ++stamp;

        computeCurrentLiveOutBits(idx);
        markCurrentVirtualLiveOut(stamp);
        rebuildCurrentConcreteLiveOutRegs();

        if (it->op == MicroInstrOpcode::Label && it->numOperands >= 1)
        {
            const MicroInstrOperand* const ops = it->ops(*operands_);
            const MicroLabelRef            labelRef(static_cast<uint32_t>(ops[0].valueU64));
            const auto                     labelIt = labelStackDepth.find(labelRef);
            if (labelIt != labelStackDepth.end())
                stackDepth = labelIt->second;
        }

        const MicroInstrRef instructionRef = it.current;
        const bool          isCall         = instructionUseDefs_[idx].isCall;
        const bool          isTerminator   = MicroInstrInfo::isTerminatorInstruction(*it);

        bool flushBoundary = false;
        if (hasControlFlow_)
        {
            if (isTerminator)
            {
                flushBoundary = true;
            }
            else if (it->op == MicroInstrOpcode::Label)
            {
                flushBoundary = true;
                if (idx > 0 && idx < predecessors_.size())
                {
                    const auto& predecessors = predecessors_[idx];
                    if (predecessors.size() == 1 && predecessors.front() == idx - 1)
                        flushBoundary = false;
                }
            }
        }

        if (flushBoundary)
        {
            std::vector<PendingInsert> boundaryPending;
            boundaryPending.reserve(mappedVirtualIndices_.size());
            flushAllMappedVirtuals(stamp, stackDepth, boundaryPending);
            for (const auto& pendingInst : boundaryPending)
            {
                instructions_->insertBefore(*operands_, instructionRef, pendingInst.op, std::span(pendingInst.ops, pendingInst.numOps), true);
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
        SmallVector<MicroReg>    mentionedConcreteRegs;
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

        std::vector<PendingInsert> pending;
        pending.reserve(4);

        spillMappedVirtualsForConcreteTouches(instructionUseDefs_[idx], protectedKeys, stamp, stackDepth, pending);

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
            forbiddenPhysRegs.reserve(((request.isUse || defOnlyCopyFromConcrete) ? currentConcreteLiveOut_.size() : 0) + addressSourceRegs.size());
            SmallVector<MicroReg> remapForbiddenPhysRegs;
            remapForbiddenPhysRegs.reserve(1);
            if (request.isUse || defOnlyCopyFromConcrete)
            {
                for (const MicroReg key : currentConcreteLiveOut_)
                {
                    if (!key.isInt())
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

            const bool liveAcrossCall = isLiveAcrossCall(request.virtKey);
            if (request.virtReg.isVirtualInt())
                request.needsPersistent = liveAcrossCall && !conv_->intPersistentRegs.empty();
            else
                request.needsPersistent = liveAcrossCall && !conv_->floatPersistentRegs.empty();

            // If no persistent class exists, remember to spill around call boundaries.
            clearCallSpill(request.virtKey);
            if (liveAcrossCall && !request.needsPersistent)
                markCallSpill(request.virtKey);

            const auto physReg = assignVirtReg(request, protectedKeys, forbiddenPhysRegs, remapForbiddenPhysRegs, stamp, stackDepth, pending);
            assignedPhysRegs.push_back({request.virtKey, physReg});

            if (liveAcrossCall && !isPersistentPhysReg(physReg))
                markCallSpill(request.virtKey);
            else
                clearCallSpill(request.virtKey);

            if (request.isDef)
                stateForVirtual(request.virtKey).dirty = true;
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

        if (isCall)
            spillCallLiveOut(stamp, stackDepth, pending);

        for (const auto& pendingInst : pending)
        {
            instructions_->insertBefore(*operands_, instructionRef, pendingInst.op, std::span(pendingInst.ops, pendingInst.numOps), true);
        }

        expireDeadMappings(stamp);

        if (it->op == MicroInstrOpcode::JumpCond && it->numOperands >= 3)
        {
            const MicroInstrOperand* const ops = it->ops(*operands_);
            const MicroLabelRef            labelRef(static_cast<uint32_t>(ops[2].valueU64));
            mergeLabelStackDepth(labelStackDepth, labelRef, stackDepth);
        }

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
    instructions_->insertBefore(*operands_, firstRef, MicroInstrOpcode::OpBinaryRegImm, subOps, true);

    std::vector<MicroInstrRef> retRefs;
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
        instructions_->insertBefore(*operands_, retRef, MicroInstrOpcode::OpBinaryRegImm, addOps, true);
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
    usePositions_.clear();
    concreteTouchPositions_.clear();
    instructionUseDefs_.clear();
    denseVirtualRegs_.clear();
    denseConcreteRegs_.clear();
    useVirtualIndices_.clear();
    defVirtualIndices_.clear();
    useConcreteIndices_.clear();
    defConcreteIndices_.clear();
    liveInVirtualBits_.clear();
    liveInConcreteBits_.clear();
    predecessors_.clear();
    worklist_.clear();
    inWorklist_.clear();
    tempOutVirtual_.clear();
    tempInVirtual_.clear();
    tempOutConcrete_.clear();
    tempInConcrete_.clear();
    liveStampByDenseIndex_.clear();
    callSpillFlags_.clear();
    mappedVirtualIndices_.clear();
    currentConcreteLiveOut_.clear();
    intPersistentSet_.clear();
    floatPersistentSet_.clear();
    freeIntTransient_.clear();
    freeIntPersistent_.clear();
    freeFloatTransient_.clear();
    freeFloatPersistent_.clear();
    states_.clear();
}

Result MicroRegisterAllocationPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/RegAlloc");
    SWC_ASSERT(context.instructions);

    clearState();
    initState(context);

    prepareInstructionData();
    if (!hasVirtualRegs_)
        return Result::Continue;

    analyzeLiveness();
    setupPools();
    rewriteInstructions();
    insertSpillFrame();

    return Result::Continue;
}

SWC_END_NAMESPACE();
