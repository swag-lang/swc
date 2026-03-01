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

// Assigns physical registers to virtual registers and handles spills.
// Example: v3 -> rax when a free compatible register exists.
// Example: under pressure, v7 lives on stack: store v7 before conflict, reload before use.
// This pass converts virtual microcode into concrete register form.

SWC_BEGIN_NAMESPACE();

void MicroRegisterAllocationPass::initState(MicroPassContext& context)
{
    context_          = &context;
    conv_             = &CallConv::get(context.callConvKind);
    instructions_     = SWC_NOT_NULL(context.instructions);
    operands_         = SWC_NOT_NULL(context.operands);
    instructionCount_ = instructions_->count();
    spillFrameUsed_   = 0;
    hasControlFlow_   = false;

    const size_t reserveCount = static_cast<size_t>(instructionCount_) * 2ull + 8ull;
    vregsLiveAcrossCall_.reserve(reserveCount);
    usePositions_.reserve(static_cast<size_t>(instructionCount_) + 8ull);
    instructionUseDefs_.clear();
    instructionUseDefs_.resize(instructionCount_);
    useVirtualIndices_.reserve(instructionCount_);
    defVirtualIndices_.reserve(instructionCount_);
    useConcreteIndices_.reserve(instructionCount_);
    defConcreteIndices_.reserve(instructionCount_);
    predecessors_.reserve(instructionCount_);
    worklist_.reserve(instructionCount_);
    inWorklist_.reserve(instructionCount_);
    states_.reserve(reserveCount);
    mapping_.reserve(reserveCount);
    liveStamp_.reserve(reserveCount);
    concreteLiveStamp_.reserve(reserveCount);
    callSpillVregs_.reserve(reserveCount);

    for (const auto& inst : instructions_->view())
    {
        if (inst.op == MicroInstrOpcode::Label || MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::JumpInstruction))
        {
            hasControlFlow_ = true;
            break;
        }
    }
}

bool MicroRegisterAllocationPass::isLiveOut(MicroReg key, uint32_t stamp) const
{
    const auto it = liveStamp_.find(key);
    if (it == liveStamp_.end())
        return false;
    return it->second == stamp;
}

bool MicroRegisterAllocationPass::isConcreteLiveOut(MicroReg reg, uint32_t stamp) const
{
    if (!reg.isInt() && !reg.isFloat())
        return false;

    const auto it = concreteLiveStamp_.find(reg);
    if (it == concreteLiveStamp_.end())
        return false;
    return it->second == stamp;
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

bool MicroRegisterAllocationPass::tryTakeAllowedPhysical(SmallVector<MicroReg>& pool,
                                                         MicroReg               virtKey,
                                                         uint32_t               stamp,
                                                         bool                   allowConcreteLive,
                                                         MicroReg&              outPhys) const
{
    for (size_t index = pool.size(); index > 0; --index)
    {
        const size_t candidateIndex = index - 1;
        const auto   candidateReg   = pool[candidateIndex];
        if (isPhysRegForbiddenForVirtual(virtKey, candidateReg))
            continue;
        if (!allowConcreteLive && isConcreteLiveOut(candidateReg, stamp))
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

    const MicroControlFlowGraph&         controlFlowGraph = SWC_NOT_NULL(context_->builder)->controlFlowGraph();
    const std::span<const MicroInstrRef> instructionRefs  = controlFlowGraph.instructionRefs();
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

    context_->passChanged = hasVirtual;
}

void MicroRegisterAllocationPass::analyzeLiveness()
{
    // CFG-aware backward liveness: captures live-out sets even across back-edges.
    liveOut_.clear();
    liveOut_.resize(instructionCount_);
    concreteLiveOut_.clear();
    concreteLiveOut_.resize(instructionCount_);
    vregsLiveAcrossCall_.clear();

    if (!instructionCount_)
        return;

    const MicroControlFlowGraph&         controlFlowGraph = context_->builder->controlFlowGraph();
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

    liveInVirtualBits_.assign(static_cast<size_t>(instructionCount_) * virtualWordCount, 0);
    liveInConcreteBits_.assign(static_cast<size_t>(instructionCount_) * concreteWordCount, 0);

    predecessors_.resize(instructionCount_);
    for (uint32_t idx = 0; idx < instructionCount_; ++idx)
    {
        predecessors_[idx].clear();
        const SmallVector<uint32_t>& successors = controlFlowGraph.successors(idx);
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

        const SmallVector<uint32_t>& successors = controlFlowGraph.successors(instructionIndex);
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

        const SmallVector<uint32_t>& successors = controlFlowGraph.successors(idx);
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

        auto& outVirtual = liveOut_[idx];
        outVirtual.clear();
        outVirtual.reserve(DenseBits::count(tempOutVirtual_));
        for (size_t wordIndex = 0; wordIndex < tempOutVirtual_.size(); ++wordIndex)
        {
            uint64_t wordBits = tempOutVirtual_[wordIndex];
            while (wordBits)
            {
                const uint32_t bitInWord = std::countr_zero(wordBits);
                const size_t   bitIndex  = wordIndex * 64ull + bitInWord;
                if (bitIndex >= virtualRegs.size())
                    break;
                outVirtual.push_back(virtualRegs[bitIndex]);
                wordBits &= (wordBits - 1ull);
            }
        }

        auto& outConcrete = concreteLiveOut_[idx];
        outConcrete.clear();
        outConcrete.reserve(DenseBits::count(tempOutConcrete_));
        for (size_t wordIndex = 0; wordIndex < tempOutConcrete_.size(); ++wordIndex)
        {
            uint64_t wordBits = tempOutConcrete_[wordIndex];
            while (wordBits)
            {
                const uint32_t bitInWord = std::countr_zero(wordBits);
                const size_t   bitIndex  = wordIndex * 64ull + bitInWord;
                if (bitIndex >= concreteRegs.size())
                    break;
                outConcrete.push_back(concreteRegs[bitIndex]);
                wordBits &= (wordBits - 1ull);
            }
        }

        if (!instructionUseDefs_[idx].isCall)
            continue;

        for (const MicroReg key : outVirtual)
            vregsLiveAcrossCall_.insert(key);
    }
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

    const auto candidateIt = states_.find(candidateKey);
    const auto bestIt      = states_.find(currentBestKey);
    SWC_ASSERT(candidateIt != states_.end());
    SWC_ASSERT(bestIt != states_.end());

    const bool candidateCleanSpill = candidateIt->second.hasSpill && !candidateIt->second.dirty;
    const bool bestCleanSpill      = bestIt->second.hasSpill && !bestIt->second.dirty;
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
                                                          uint32_t     stamp,
                                                          bool         allowConcreteLive,
                                                          MicroReg&    outVirtKey,
                                                          MicroReg&    outPhys) const
{
    // Choose mapped virtual reg that is cheapest to evict under current constraints.
    outVirtKey = MicroReg::invalid();
    outPhys    = MicroReg::invalid();

    for (const auto& [virtKey, physReg] : mapping_)
    {
        if (containsKey(protectedKeys, virtKey))
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
        if (!allowConcreteLive && isConcreteLiveOut(physReg, stamp))
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

        return FreePools{&freeIntTransient_, nullptr};
    }

    SWC_ASSERT(request.virtReg.isVirtualFloat());
    if (request.needsPersistent)
        return FreePools{&freeFloatPersistent_, &freeFloatTransient_};

    return FreePools{&freeFloatTransient_, nullptr};
}

bool MicroRegisterAllocationPass::tryTakeFreePhysical(const AllocRequest& request,
                                                      uint32_t            stamp,
                                                      bool                allowConcreteLive,
                                                      MicroReg&           outPhys)
{
    const FreePools pools = pickFreePools(request);
    SWC_ASSERT(pools.primary != nullptr);

    if (tryTakeAllowedPhysical(*pools.primary, request.virtKey, stamp, allowConcreteLive, outPhys))
        return true;

    if (pools.secondary)
        return tryTakeAllowedPhysical(*pools.secondary, request.virtKey, stamp, allowConcreteLive, outPhys);

    return false;
}

void MicroRegisterAllocationPass::unmapVirtReg(MicroReg virtKey)
{
    const auto mapIt = mapping_.find(virtKey);
    if (mapIt == mapping_.end())
        return;

    mapping_.erase(mapIt);

    const auto stateIt = states_.find(virtKey);
    if (stateIt != states_.end())
        stateIt->second.mapped = false;
}

void MicroRegisterAllocationPass::mapVirtReg(MicroReg virtKey, MicroReg physReg)
{
    mapping_[virtKey] = physReg;

    auto& regState  = states_[virtKey];
    regState.mapped = true;
    regState.phys   = physReg;
}

bool MicroRegisterAllocationPass::selectEvictionCandidateWithFallback(MicroReg     requestVirtKey,
                                                                      uint32_t     instructionIndex,
                                                                      bool         isFloatReg,
                                                                      bool         preferPersistentPool,
                                                                      MicroRegSpan protectedKeys,
                                                                      uint32_t     stamp,
                                                                      bool         allowConcreteLive,
                                                                      MicroReg&    outVirtKey,
                                                                      MicroReg&    outPhys) const
{
    if (selectEvictionCandidate(requestVirtKey, instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, stamp, allowConcreteLive, outVirtKey, outPhys))
        return true;

    return selectEvictionCandidate(requestVirtKey, instructionIndex, isFloatReg, !preferPersistentPool, protectedKeys, stamp, allowConcreteLive, outVirtKey, outPhys);
}

MicroReg MicroRegisterAllocationPass::allocatePhysical(const AllocRequest&         request,
                                                       MicroRegSpan                protectedKeys,
                                                       uint32_t                    stamp,
                                                       int64_t                     stackDepth,
                                                       std::vector<PendingInsert>& pending)
{
    // Prefer free registers; otherwise evict one candidate and spill if needed.
    MicroReg physReg;
    if (tryTakeFreePhysical(request, stamp, false, physReg))
        return physReg;

    MicroReg victimKey = MicroReg::invalid();
    MicroReg victimReg;

    const bool isFloatReg           = request.virtReg.isVirtualFloat();
    const bool preferPersistentPool = request.needsPersistent;
    SWC_INTERNAL_CHECK(selectEvictionCandidateWithFallback(request.virtKey, request.instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, stamp, false, victimKey, victimReg));

    auto&      victimState   = states_[victimKey];
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

MicroReg MicroRegisterAllocationPass::assignVirtReg(const AllocRequest&         request,
                                                    MicroRegSpan                protectedKeys,
                                                    uint32_t                    stamp,
                                                    int64_t                     stackDepth,
                                                    std::vector<PendingInsert>& pending)
{
    // Reuse existing mapping when possible, otherwise allocate and load from spill on use.
    const auto& regState = states_[request.virtKey];
    if (regState.mapped)
        return regState.phys;

    const auto physReg = allocatePhysical(request, protectedKeys, stamp, stackDepth, pending);
    mapVirtReg(request.virtKey, physReg);

    auto& mappedState = states_[request.virtKey];
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

void MicroRegisterAllocationPass::spillCallLiveOut(uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // Calls may clobber transient regs; force spill of vulnerable live values before call.
    for (auto it = mapping_.begin(); it != mapping_.end();)
    {
        const MicroReg virtKey = it->first;
        const MicroReg physReg = it->second;

        if (!callSpillVregs_.contains(virtKey) || !isLiveOut(virtKey, stamp))
        {
            ++it;
            continue;
        }

        auto& regState = states_[virtKey];
        if (regState.dirty || !regState.hasSpill)
        {
            ensureSpillSlot(regState, physReg.isFloat());
            PendingInsert spillPending;
            queueSpillStore(spillPending, physReg, regState, stackDepth);
            pending.push_back(spillPending);
            regState.dirty = false;
        }

        regState.mapped = false;
        it              = mapping_.erase(it);
        returnToFreePool(physReg);
    }
}

void MicroRegisterAllocationPass::flushAllMappedVirtuals(int64_t stackDepth, std::vector<PendingInsert>& pending)
{
    // Control-flow boundaries require a stable memory state for all mapped values.
    for (const auto& [virtKey, physReg] : mapping_)
    {
        auto& regState = states_[virtKey];
        if (regState.dirty || !regState.hasSpill)
        {
            ensureSpillSlot(regState, physReg.isFloat());
            PendingInsert spillPending;
            queueSpillStore(spillPending, physReg, regState, stackDepth);
            pending.push_back(spillPending);
            regState.dirty = false;
        }

        regState.mapped = false;
        returnToFreePool(physReg);
    }

    mapping_.clear();
}

void MicroRegisterAllocationPass::clearAllMappedVirtuals()
{
    for (const auto& [virtKey, physReg] : mapping_)
    {
        auto& regState  = states_[virtKey];
        regState.mapped = false;
        returnToFreePool(physReg);
    }

    mapping_.clear();
}

void MicroRegisterAllocationPass::expireDeadMappings(uint32_t stamp)
{
    // Linear dead-expiry is only safe when the instruction stream has no control-flow joins.
    if (hasControlFlow_)
        return;

    for (auto it = mapping_.begin(); it != mapping_.end();)
    {
        if (isLiveOut(it->first, stamp))
        {
            ++it;
            continue;
        }

        const auto deadReg = it->second;
        auto       stateIt = states_.find(it->first);
        if (stateIt != states_.end())
            stateIt->second.mapped = false;

        it = mapping_.erase(it);
        returnToFreePool(deadReg);
    }
}

void MicroRegisterAllocationPass::rewriteInstructions()
{
    // Main rewrite pass:
    // 1) assign physical registers for each virtual operand,
    // 2) queue spill loads/stores around the instruction,
    // 3) release dead mappings.
    liveStamp_.clear();
    liveStamp_.reserve(instructionCount_ * 2ull);
    concreteLiveStamp_.clear();
    concreteLiveStamp_.reserve(instructionCount_ * 2ull);

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
            liveStamp_.clear();
            concreteLiveStamp_.clear();
            stamp = 1;
        }
        ++stamp;

        if (it->op == MicroInstrOpcode::Label && it->numOperands >= 1)
        {
            const MicroInstrOperand* const ops = it->ops(*operands_);
            const MicroLabelRef            labelRef(static_cast<uint32_t>(ops[0].valueU64));
            const auto                     labelIt = labelStackDepth.find(labelRef);
            if (labelIt != labelStackDepth.end())
                stackDepth = labelIt->second;
        }

        for (const auto key : liveOut_[idx])
            liveStamp_[key] = stamp;
        for (const auto key : concreteLiveOut_[idx])
            concreteLiveStamp_[key] = stamp;

        const MicroInstrRef instructionRef = it.current;
        const bool          isCall         = instructionUseDefs_[idx].isCall;
        const bool          isTerminator   = MicroInstrInfo::isTerminatorInstruction(*it);

        if (hasControlFlow_ && (it->op == MicroInstrOpcode::Label || isTerminator))
        {
            std::vector<PendingInsert> boundaryPending;
            boundaryPending.reserve(mapping_.size());
            flushAllMappedVirtuals(stackDepth, boundaryPending);
            for (const auto& pendingInst : boundaryPending)
            {
                instructions_->insertBefore(*operands_, instructionRef, pendingInst.op, std::span(pendingInst.ops, pendingInst.numOps));
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

        std::vector<PendingInsert> pending;
        pending.reserve(4);

        for (const auto& regRef : regRefs)
        {
            if (!regRef.reg)
                continue;

            const auto reg = *regRef.reg;
            if (!reg.isVirtual())
                continue;

            AllocRequest request;
            request.virtReg          = reg;
            request.virtKey          = reg;
            request.isUse            = regRef.use;
            request.isDef            = regRef.def;
            request.instructionIndex = idx;

            const bool liveAcrossCall = vregsLiveAcrossCall_.contains(request.virtKey);
            if (reg.isVirtualInt())
                request.needsPersistent = liveAcrossCall && !conv_->intPersistentRegs.empty();
            else
                request.needsPersistent = liveAcrossCall && !conv_->floatPersistentRegs.empty();

            // If no persistent class exists, remember to spill around call boundaries.
            if (liveAcrossCall && !request.needsPersistent)
                callSpillVregs_.insert(request.virtKey);

            const auto physReg        = assignVirtReg(request, protectedKeys, stamp, stackDepth, pending);
            *SWC_NOT_NULL(regRef.reg) = physReg;

            if (liveAcrossCall && !isPersistentPhysReg(physReg))
                callSpillVregs_.insert(request.virtKey);

            if (request.isDef)
                states_[request.virtKey].dirty = true;
        }

        if (isCall)
            spillCallLiveOut(stamp, stackDepth, pending);

        for (const auto& pendingInst : pending)
        {
            instructions_->insertBefore(*operands_, instructionRef, pendingInst.op, std::span(pendingInst.ops, pendingInst.numOps));
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
    instructions_->insertBefore(*operands_, firstRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

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
        instructions_->insertBefore(*operands_, retRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
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

    liveOut_.clear();
    concreteLiveOut_.clear();
    vregsLiveAcrossCall_.clear();
    usePositions_.clear();
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
    intPersistentSet_.clear();
    floatPersistentSet_.clear();
    freeIntTransient_.clear();
    freeIntPersistent_.clear();
    freeFloatTransient_.clear();
    freeFloatPersistent_.clear();
    states_.clear();
    mapping_.clear();
    liveStamp_.clear();
    concreteLiveStamp_.clear();
    callSpillVregs_.clear();
}

Result MicroRegisterAllocationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);

    clearState();
    initState(context);

    prepareInstructionData();
    analyzeLiveness();
    setupPools();
    rewriteInstructions();
    insertSpillFrame();

    return Result::Continue;
}

SWC_END_NAMESPACE();
