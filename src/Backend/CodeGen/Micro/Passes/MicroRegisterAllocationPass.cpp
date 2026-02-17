#include "pch.h"
#include "Backend/CodeGen/Micro/Passes/MicroRegisterAllocationPass.h"
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/MicroInstrStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct VRegState
    {
        MicroReg    phys        = MicroReg::invalid();
        uint64_t    spillOffset = 0;
        MicroOpBits spillBits   = MicroOpBits::B64;
        bool        mapped      = false;
        bool        hasSpill    = false;
        bool        dirty       = false;
    };

    struct PendingInsert
    {
        MicroInstrOpcode  op        = MicroInstrOpcode::Nop;
        EncodeFlags       emitFlags = EncodeFlagsE::Zero;
        uint8_t           numOps    = 0;
        MicroInstrOperand ops[4]    = {};
    };

    struct AllocRequest
    {
        MicroReg    virtReg          = MicroReg::invalid();
        uint32_t    virtKey          = 0;
        bool        needsPersistent  = false;
        bool        isUse            = false;
        bool        isDef            = false;
        uint32_t    instructionIndex = 0;
        EncodeFlags emitFlags        = EncodeFlagsE::Zero;
    };

    class RegAllocEngine
    {
    public:
        explicit RegAllocEngine(MicroPassContext& context) :
            context_(context),
            conv_(CallConv::get(context.callConvKind)),
            instructions_(*SWC_CHECK_NOT_NULL(context.instructions)),
            operands_(*SWC_CHECK_NOT_NULL(context.operands))
        {
        }

        void run()
        {
            if (!instructions_.count())
                return;

            analyzeLiveness();
            buildUsePositions();
            setupPools();
            rewriteInstructions();
            insertSpillFrame();
        }

    private:
        void analyzeLiveness()
        {
            const uint32_t instructionCount = instructions_.count();
            liveOut_.clear();
            liveOut_.resize(instructionCount);

            std::unordered_set<uint32_t> live;
            live.reserve(instructionCount * 2ull);

            uint32_t idx = instructionCount;
            for (const auto& inst : std::ranges::reverse_view(instructions_.view()))
            {
                --idx;

                auto& out = liveOut_[idx];
                out.clear();
                out.reserve(live.size());
                for (uint32_t regKey : live)
                    out.push_back(regKey);

                const MicroInstrUseDef useDef = inst.collectUseDef(operands_, context_.encoder);
                if (useDef.isCall)
                {
                    for (uint32_t regKey : live)
                        vregsLiveAcrossCall_.insert(regKey);
                }

                for (const auto& reg : useDef.defs)
                {
                    if (reg.isVirtual())
                        live.erase(reg.packed);
                }

                for (const auto& reg : useDef.uses)
                {
                    if (reg.isVirtual())
                        live.insert(reg.packed);
                }
            }
        }

        void buildUsePositions()
        {
            usePositions_.clear();
            uint32_t idx = 0;
            for (const auto& inst : instructions_.view())
            {
                const auto info = inst.collectUseDef(operands_, context_.encoder);
                for (const auto& reg : info.uses)
                {
                    if (!reg.isVirtual())
                        continue;
                    usePositions_[reg.packed].push_back(idx);
                }
                ++idx;
            }
        }

        void setupPools()
        {
            intPersistentSet_.clear();
            floatPersistentSet_.clear();

            intPersistentSet_.reserve(conv_.intPersistentRegs.size() * 2 + 8);
            floatPersistentSet_.reserve(conv_.floatPersistentRegs.size() * 2 + 8);

            for (const auto reg : conv_.intPersistentRegs)
                intPersistentSet_.insert(reg.packed);

            for (const auto reg : conv_.floatPersistentRegs)
                floatPersistentSet_.insert(reg.packed);

            freeIntTransient_.clear();
            freeIntPersistent_.clear();
            freeFloatTransient_.clear();
            freeFloatPersistent_.clear();

            for (const auto reg : conv_.intRegs)
            {
                if (intPersistentSet_.contains(reg.packed))
                    freeIntPersistent_.push_back(reg);
                else
                    freeIntTransient_.push_back(reg);
            }

            for (const auto reg : conv_.floatRegs)
            {
                if (floatPersistentSet_.contains(reg.packed))
                    freeFloatPersistent_.push_back(reg);
                else
                    freeFloatTransient_.push_back(reg);
            }
        }

        bool isPersistentPhysReg(MicroReg reg) const
        {
            if (reg.isInt())
                return intPersistentSet_.contains(reg.packed);
            if (reg.isFloat())
                return floatPersistentSet_.contains(reg.packed);
            SWC_ASSERT(false);
            return false;
        }

        void returnToFreePool(MicroReg reg)
        {
            if (reg.isInt())
            {
                if (intPersistentSet_.contains(reg.packed))
                    freeIntPersistent_.push_back(reg);
                else
                    freeIntTransient_.push_back(reg);
                return;
            }

            if (reg.isFloat())
            {
                if (floatPersistentSet_.contains(reg.packed))
                    freeFloatPersistent_.push_back(reg);
                else
                    freeFloatTransient_.push_back(reg);
                return;
            }

            SWC_ASSERT(false);
        }

        bool isInstructionLiveOut(uint32_t key, uint32_t stamp) const
        {
            const auto it = liveStamp_.find(key);
            if (it == liveStamp_.end())
                return false;
            return it->second == stamp;
        }

        bool isProtectedKey(std::span<const uint32_t> protectedKeys, uint32_t key) const
        {
            for (const auto value : protectedKeys)
            {
                if (value == key)
                    return true;
            }

            return false;
        }

        uint32_t distanceToNextUse(uint32_t key, uint32_t instructionIndex) const
        {
            const auto useIt = usePositions_.find(key);
            if (useIt == usePositions_.end())
                return std::numeric_limits<uint32_t>::max();

            const auto& positions = useIt->second;
            const auto  it        = std::upper_bound(positions.begin(), positions.end(), instructionIndex);
            if (it == positions.end())
                return std::numeric_limits<uint32_t>::max();

            return *it - instructionIndex;
        }

        bool isEvictionCandidateBetter(uint32_t candidateKey, MicroReg candidateReg, uint32_t currentBestKey, MicroReg currentBestReg, uint32_t instructionIndex, uint32_t stamp) const
        {
            if (!currentBestReg.isValid())
                return true;

            const bool candidateDead = !isInstructionLiveOut(candidateKey, stamp);
            const bool bestDead      = !isInstructionLiveOut(currentBestKey, stamp);
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

            return candidateKey > currentBestKey;
        }

        bool selectEvictionCandidate(uint32_t instructionIndex, bool isFloatReg, bool fromPersistentPool, std::span<const uint32_t> protectedKeys, uint32_t stamp, uint32_t& outVirtKey, MicroReg& outPhys) const
        {
            outVirtKey = 0;
            outPhys    = MicroReg::invalid();

            for (const auto& [virtKey, physReg] : mapping_)
            {
                if (isProtectedKey(protectedKeys, virtKey))
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

                if (isEvictionCandidateBetter(virtKey, physReg, outVirtKey, outPhys, instructionIndex, stamp))
                {
                    outVirtKey = virtKey;
                    outPhys    = physReg;
                }
            }

            return outPhys.isValid();
        }

        void ensureSpillSlot(VRegState& state, bool isFloat)
        {
            if (state.hasSpill)
                return;

            const MicroOpBits bits     = isFloat ? MicroOpBits::B128 : MicroOpBits::B64;
            const uint64_t    slotSize = bits == MicroOpBits::B128 ? 16u : 8u;
            spillFrameUsed_            = Math::alignUpU64(spillFrameUsed_, slotSize);

            state.spillOffset = spillFrameUsed_;
            state.spillBits   = bits;
            state.hasSpill    = true;
            spillFrameUsed_ += slotSize;
        }

        void queueSpillStore(PendingInsert& out, MicroReg physReg, const VRegState& state, EncodeFlags emitFlags) const
        {
            out.op              = MicroInstrOpcode::LoadMemReg;
            out.emitFlags       = emitFlags;
            out.numOps          = 4;
            out.ops[0].reg      = conv_.stackPointer;
            out.ops[1].reg      = physReg;
            out.ops[2].opBits   = state.spillBits;
            out.ops[3].valueU64 = state.spillOffset;
        }

        void queueSpillLoad(PendingInsert& out, MicroReg physReg, const VRegState& state, EncodeFlags emitFlags) const
        {
            out.op              = MicroInstrOpcode::LoadRegMem;
            out.emitFlags       = emitFlags;
            out.numOps          = 4;
            out.ops[0].reg      = physReg;
            out.ops[1].reg      = conv_.stackPointer;
            out.ops[2].opBits   = state.spillBits;
            out.ops[3].valueU64 = state.spillOffset;
        }

        void unmapVReg(uint32_t key)
        {
            const auto it = mapping_.find(key);
            if (it == mapping_.end())
                return;

            const auto physIt = physToVirt_.find(it->second.packed);
            if (physIt != physToVirt_.end())
                physToVirt_.erase(physIt);

            mapping_.erase(it);

            auto stateIt = states_.find(key);
            if (stateIt != states_.end())
            {
                stateIt->second.mapped = false;
                stateIt->second.phys   = MicroReg::invalid();
            }
        }

        void mapVReg(uint32_t key, MicroReg physReg)
        {
            mapping_[key]               = physReg;
            physToVirt_[physReg.packed] = key;

            auto& state  = states_[key];
            state.mapped = true;
            state.phys   = physReg;
        }

        bool tryTakeFreePhysical(MicroReg virtReg, bool needsPersistent, MicroReg& outPhys)
        {
            outPhys = MicroReg::invalid();

            if (virtReg.isVirtualInt())
            {
                if (needsPersistent)
                {
                    if (freeIntPersistent_.empty())
                        return false;

                    outPhys = freeIntPersistent_.back();
                    freeIntPersistent_.pop_back();
                    return true;
                }

                if (!freeIntTransient_.empty())
                {
                    outPhys = freeIntTransient_.back();
                    freeIntTransient_.pop_back();
                    return true;
                }

                if (!freeIntPersistent_.empty())
                {
                    outPhys = freeIntPersistent_.back();
                    freeIntPersistent_.pop_back();
                    return true;
                }

                return false;
            }

            SWC_ASSERT(virtReg.isVirtualFloat());

            if (needsPersistent)
            {
                if (freeFloatPersistent_.empty())
                    return false;

                outPhys = freeFloatPersistent_.back();
                freeFloatPersistent_.pop_back();
                return true;
            }

            if (!freeFloatTransient_.empty())
            {
                outPhys = freeFloatTransient_.back();
                freeFloatTransient_.pop_back();
                return true;
            }

            if (!freeFloatPersistent_.empty())
            {
                outPhys = freeFloatPersistent_.back();
                freeFloatPersistent_.pop_back();
                return true;
            }

            return false;
        }

        bool tryEvictOne(const AllocRequest& request, std::span<const uint32_t> protectedKeys, uint32_t stamp, PendingInsert* outPending, MicroReg& outPhys)
        {
            outPhys = MicroReg::invalid();

            const bool isFloatReg = request.virtReg.isVirtualFloat();

            uint32_t victimKey = 0;
            MicroReg victimReg = MicroReg::invalid();

            if (request.needsPersistent)
            {
                if (!selectEvictionCandidate(request.instructionIndex, isFloatReg, true, protectedKeys, stamp, victimKey, victimReg))
                    return false;
            }
            else
            {
                if (!selectEvictionCandidate(request.instructionIndex, isFloatReg, false, protectedKeys, stamp, victimKey, victimReg))
                {
                    if (!selectEvictionCandidate(request.instructionIndex, isFloatReg, true, protectedKeys, stamp, victimKey, victimReg))
                        return false;
                }
            }

            auto stateIt = states_.find(victimKey);
            SWC_ASSERT(stateIt != states_.end());
            auto& victimState = stateIt->second;

            const bool victimLiveOut = isInstructionLiveOut(victimKey, stamp);
            if (victimLiveOut)
            {
                const bool hadSpillSlot = victimState.hasSpill;
                ensureSpillSlot(victimState, victimReg.isFloat());

                if (victimState.dirty || !hadSpillSlot)
                {
                    SWC_ASSERT(outPending);
                    queueSpillStore(*outPending, victimReg, victimState, request.emitFlags);
                    victimState.dirty = false;
                }
            }

            unmapVReg(victimKey);
            outPhys = victimReg;
            return true;
        }

        MicroReg allocatePhysical(const AllocRequest& request, std::span<const uint32_t> protectedKeys, uint32_t stamp, std::vector<PendingInsert>& pending)
        {
            MicroReg physReg;
            if (tryTakeFreePhysical(request.virtReg, request.needsPersistent, physReg))
                return physReg;

            PendingInsert spillPending;
            if (tryEvictOne(request, protectedKeys, stamp, &spillPending, physReg))
            {
                if (spillPending.numOps)
                    pending.push_back(spillPending);
                return physReg;
            }

            SWC_ASSERT(false);
            return MicroReg::invalid();
        }

        void processVirtualOperand(const AllocRequest& request, std::span<const uint32_t> protectedKeys, uint32_t stamp, std::vector<PendingInsert>& pending, MicroReg* regOperand)
        {
            auto& state = states_[request.virtKey];
            if (!state.mapped)
            {
                const MicroReg physReg = allocatePhysical(request, protectedKeys, stamp, pending);
                mapVReg(request.virtKey, physReg);

                if (request.isUse)
                {
                    if (!state.hasSpill)
                    {
                        SWC_ASSERT(false);
                    }
                    else
                    {
                        PendingInsert loadPending;
                        queueSpillLoad(loadPending, physReg, state, request.emitFlags);
                        pending.push_back(loadPending);
                        state.dirty = false;
                    }
                }
            }

            *SWC_CHECK_NOT_NULL(regOperand) = states_[request.virtKey].phys;

            if (request.isDef)
                states_[request.virtKey].dirty = true;
        }

        bool hasPersistentRegsFor(MicroReg virtReg) const
        {
            if (virtReg.isVirtualInt())
                return !conv_.intPersistentRegs.empty();
            SWC_ASSERT(virtReg.isVirtualFloat());
            return !conv_.floatPersistentRegs.empty();
        }

        void spillCallClobberedLiveOut(uint32_t stamp, EncodeFlags emitFlags, std::vector<PendingInsert>& pending)
        {
            for (auto it = mapping_.begin(); it != mapping_.end();)
            {
                const uint32_t virtKey = it->first;
                const MicroReg physReg = it->second;

                if (!callSpillVregs_.contains(virtKey) || !isInstructionLiveOut(virtKey, stamp))
                {
                    ++it;
                    continue;
                }

                auto stateIt = states_.find(virtKey);
                SWC_ASSERT(stateIt != states_.end());
                auto& state = stateIt->second;

                if (state.dirty || !state.hasSpill)
                {
                    const bool hadSpillSlot = state.hasSpill;
                    ensureSpillSlot(state, physReg.isFloat());

                    PendingInsert spillPending;
                    queueSpillStore(spillPending, physReg, state, emitFlags);
                    pending.push_back(spillPending);
                    state.dirty = false;
                    SWC_ASSERT(state.hasSpill || hadSpillSlot);
                }

                state.mapped = false;
                state.phys   = MicroReg::invalid();
                physToVirt_.erase(physReg.packed);
                it = mapping_.erase(it);
                returnToFreePool(physReg);
            }
        }

        void expireDeadMappings(uint32_t stamp)
        {
            for (auto it = mapping_.begin(); it != mapping_.end();)
            {
                if (isInstructionLiveOut(it->first, stamp))
                {
                    ++it;
                    continue;
                }

                const MicroReg deadReg = it->second;
                auto           stateIt = states_.find(it->first);
                if (stateIt != states_.end())
                {
                    stateIt->second.mapped = false;
                    stateIt->second.phys   = MicroReg::invalid();
                }

                physToVirt_.erase(deadReg.packed);
                it = mapping_.erase(it);
                returnToFreePool(deadReg);
            }
        }

        void rewriteInstructions()
        {
            const uint32_t instructionCount = instructions_.count();
            liveStamp_.clear();
            liveStamp_.reserve(instructionCount * 2ull);

            uint32_t stamp = 1;
            uint32_t idx   = 0;

            for (auto it = instructions_.view().begin(); it != instructions_.view().end() && idx < instructionCount; ++it)
            {
                if (stamp == std::numeric_limits<uint32_t>::max())
                {
                    liveStamp_.clear();
                    stamp = 1;
                }
                ++stamp;

                for (uint32_t key : liveOut_[idx])
                    liveStamp_[key] = stamp;

                const Ref         instructionRef = it.current;
                const EncodeFlags emitFlags      = it->emitFlags;

                SmallVector<MicroInstrRegOperandRef> regRefs;
                it->collectRegOperands(operands_, regRefs, context_.encoder);

                SmallVector<uint32_t> protectedKeys;
                protectedKeys.reserve(regRefs.size());
                for (const auto& regRef : regRefs)
                {
                    if (!regRef.reg)
                        continue;

                    const MicroReg reg = *regRef.reg;
                    if (!reg.isVirtual())
                        continue;

                    bool exists = false;
                    for (const auto key : protectedKeys)
                    {
                        if (key == reg.packed)
                        {
                            exists = true;
                            break;
                        }
                    }

                    if (!exists)
                        protectedKeys.push_back(reg.packed);
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

                    const uint32_t key = reg.packed;

                    AllocRequest request;
                    request.virtReg           = reg;
                    request.virtKey           = key;
                    const bool liveAcrossCall = vregsLiveAcrossCall_.contains(key);
                    request.needsPersistent   = liveAcrossCall && hasPersistentRegsFor(reg);
                    request.isUse             = regRef.use;
                    request.isDef             = regRef.def;
                    request.instructionIndex  = idx;
                    request.emitFlags         = emitFlags;

                    if (liveAcrossCall && !request.needsPersistent)
                        callSpillVregs_.insert(key);

                    processVirtualOperand(request, protectedKeys, stamp, pending, regRef.reg);
                }

                const auto useDef = it->collectUseDef(operands_, context_.encoder);
                if (useDef.isCall)
                    spillCallClobberedLiveOut(stamp, emitFlags, pending);

                for (const auto& insert : pending)
                {
                    instructions_.insertInstructionBefore(operands_, instructionRef, insert.op, insert.emitFlags, std::span(insert.ops, insert.numOps));
                }

                expireDeadMappings(stamp);
                ++idx;
            }
        }

        void insertSpillFrame()
        {
            if (!spillFrameUsed_)
                return;

            const uint64_t stackAlignment = conv_.stackAlignment ? conv_.stackAlignment : 16;
            const uint64_t spillFrameSize = Math::alignUpU64(spillFrameUsed_, stackAlignment);
            if (!spillFrameSize)
                return;

            auto beginIt = instructions_.view().begin();
            if (beginIt == instructions_.view().end())
                return;

            const Ref firstRef = beginIt.current;

            MicroInstrOperand subOps[4];
            subOps[0].reg      = conv_.stackPointer;
            subOps[1].opBits   = MicroOpBits::B64;
            subOps[2].microOp  = MicroOp::Subtract;
            subOps[3].valueU64 = spillFrameSize;
            instructions_.insertInstructionBefore(operands_, firstRef, MicroInstrOpcode::OpBinaryRegImm, EncodeFlagsE::Zero, subOps);

            std::vector<std::pair<Ref, EncodeFlags>> retRefs;
            for (auto it = instructions_.view().begin(); it != instructions_.view().end(); ++it)
            {
                if (it->op == MicroInstrOpcode::Ret)
                    retRefs.emplace_back(it.current, it->emitFlags);
            }

            for (const auto [retRef, emitFlags] : retRefs)
            {
                MicroInstrOperand addOps[4];
                addOps[0].reg      = conv_.stackPointer;
                addOps[1].opBits   = MicroOpBits::B64;
                addOps[2].microOp  = MicroOp::Add;
                addOps[3].valueU64 = spillFrameSize;
                instructions_.insertInstructionBefore(operands_, retRef, MicroInstrOpcode::OpBinaryRegImm, emitFlags, addOps);
            }
        }

        MicroPassContext&    context_;
        const CallConv&      conv_;
        MicroInstrStorage&   instructions_;
        MicroOperandStorage& operands_;

        std::vector<std::vector<uint32_t>>                  liveOut_;
        std::unordered_set<uint32_t>                        vregsLiveAcrossCall_;
        std::unordered_map<uint32_t, std::vector<uint32_t>> usePositions_;

        std::unordered_set<uint32_t> intPersistentSet_;
        std::unordered_set<uint32_t> floatPersistentSet_;

        SmallVector<MicroReg> freeIntTransient_;
        SmallVector<MicroReg> freeIntPersistent_;
        SmallVector<MicroReg> freeFloatTransient_;
        SmallVector<MicroReg> freeFloatPersistent_;

        std::unordered_map<uint32_t, VRegState> states_;
        std::unordered_map<uint32_t, MicroReg>  mapping_;
        std::unordered_map<uint32_t, uint32_t>  physToVirt_;

        std::unordered_map<uint32_t, uint32_t> liveStamp_;
        std::unordered_set<uint32_t>           callSpillVregs_;

        uint64_t spillFrameUsed_ = 0;
    };
}

void MicroRegisterAllocationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);

    RegAllocEngine engine(context);
    engine.run();
}

SWC_END_NAMESPACE();
