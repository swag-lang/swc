#include "pch.h"
#include "Backend/CodeGen/Micro/Passes/MicroRegisterAllocationPass.h"
#include "Backend/CodeGen/Encoder/Encoder.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Backend/CodeGen/Micro/MicroStorage.h"
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
        MicroInstrOpcode  op     = MicroInstrOpcode::Nop;
        uint8_t           numOps = 0;
        MicroInstrOperand ops[4] = {};
    };

    struct AllocRequest
    {
        MicroReg virtReg          = MicroReg::invalid();
        uint32_t virtKey          = 0;
        bool     needsPersistent  = false;
        bool     isUse            = false;
        bool     isDef            = false;
        uint32_t instructionIndex = 0;
    };

    struct PassState
    {
        MicroPassContext*    context      = nullptr;
        const CallConv*      conv         = nullptr;
        MicroStorage*        instructions = nullptr;
        MicroOperandStorage* operands     = nullptr;

        uint32_t instructionCount = 0;
        uint64_t spillFrameUsed   = 0;

        std::vector<std::vector<uint32_t>>                  liveOut;
        std::unordered_set<uint32_t>                        vregsLiveAcrossCall;
        std::unordered_map<uint32_t, std::vector<uint32_t>> usePositions;

        std::unordered_set<uint32_t> intPersistentSet;
        std::unordered_set<uint32_t> floatPersistentSet;

        SmallVector<MicroReg> freeIntTransient;
        SmallVector<MicroReg> freeIntPersistent;
        SmallVector<MicroReg> freeFloatTransient;
        SmallVector<MicroReg> freeFloatPersistent;

        std::unordered_map<uint32_t, VRegState> states;
        std::unordered_map<uint32_t, MicroReg>  mapping;
        std::unordered_map<uint32_t, uint32_t>  physToVirt;
        std::unordered_map<uint32_t, uint32_t>  liveStamp;
        std::unordered_set<uint32_t>            callSpillVregs;
    };

    void initState(PassState& state, MicroPassContext& context)
    {
        state.context          = &context;
        state.conv             = &CallConv::get(context.callConvKind);
        state.instructions     = SWC_CHECK_NOT_NULL(context.instructions);
        state.operands         = SWC_CHECK_NOT_NULL(context.operands);
        state.instructionCount = state.instructions->count();
    }

    bool isLiveOut(const PassState& state, uint32_t key, uint32_t stamp)
    {
        const auto it = state.liveStamp.find(key);
        if (it == state.liveStamp.end())
            return false;
        return it->second == stamp;
    }

    bool containsKey(std::span<const uint32_t> keys, uint32_t key)
    {
        for (const auto value : keys)
        {
            if (value == key)
                return true;
        }

        return false;
    }

    bool isPersistentPhysReg(const PassState& state, MicroReg reg)
    {
        if (reg.isInt())
            return state.intPersistentSet.contains(reg.packed);

        if (reg.isFloat())
            return state.floatPersistentSet.contains(reg.packed);

        SWC_ASSERT(false);
        return false;
    }

    bool isPhysRegForbiddenForVirtual(const PassState& state, uint32_t virtKey, MicroReg physReg)
    {
        SWC_ASSERT(state.context != nullptr);
        SWC_ASSERT(state.context->builder != nullptr);
        return state.context->builder->isVirtualRegPhysRegForbidden(virtKey, physReg);
    }

    bool tryTakeAllowedPhysical(SmallVector<MicroReg>& pool, const PassState& state, uint32_t virtKey, MicroReg& outPhys)
    {
        outPhys = MicroReg::invalid();

        for (size_t index = pool.size(); index > 0; --index)
        {
            const size_t candidateIndex = index - 1;
            const auto   candidateReg   = pool[candidateIndex];
            if (isPhysRegForbiddenForVirtual(state, virtKey, candidateReg))
                continue;

            outPhys = candidateReg;
            if (candidateIndex != pool.size() - 1)
                pool[candidateIndex] = pool.back();
            pool.pop_back();
            return true;
        }

        return false;
    }

    void returnToFreePool(PassState& state, MicroReg reg)
    {
        if (reg.isInt())
        {
            if (state.intPersistentSet.contains(reg.packed))
                state.freeIntPersistent.push_back(reg);
            else
                state.freeIntTransient.push_back(reg);
            return;
        }

        if (reg.isFloat())
        {
            if (state.floatPersistentSet.contains(reg.packed))
                state.freeFloatPersistent.push_back(reg);
            else
                state.freeFloatTransient.push_back(reg);
            return;
        }

        SWC_ASSERT(false);
    }

    uint32_t distanceToNextUse(const PassState& state, uint32_t key, uint32_t instructionIndex)
    {
        const auto useIt = state.usePositions.find(key);
        if (useIt == state.usePositions.end())
            return std::numeric_limits<uint32_t>::max();

        const auto& positions = useIt->second;
        const auto  it        = std::ranges::upper_bound(positions, instructionIndex);
        if (it == positions.end())
            return std::numeric_limits<uint32_t>::max();

        return *it - instructionIndex;
    }

    void analyzeLiveness(PassState& state)
    {
        // Backward liveness: capture live-out set per instruction and detect values live across calls.
        state.liveOut.clear();
        state.liveOut.resize(state.instructionCount);
        state.vregsLiveAcrossCall.clear();

        std::unordered_set<uint32_t> live;
        live.reserve(state.instructionCount * 2ull);

        uint32_t idx = state.instructionCount;
        for (const auto& inst : std::ranges::reverse_view(state.instructions->view()))
        {
            --idx;

            auto& out = state.liveOut[idx];
            out.clear();
            out.reserve(live.size());
            for (uint32_t regKey : live)
                out.push_back(regKey);

            const auto useDef = inst.collectUseDef(*state.operands, state.context->encoder);
            if (useDef.isCall)
            {
                for (const auto regKey : live)
                    state.vregsLiveAcrossCall.insert(regKey);
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

    void buildUsePositions(PassState& state)
    {
        // Forward index of uses to pick better eviction victims (furthest next use first).
        state.usePositions.clear();

        uint32_t idx = 0;
        for (const auto& inst : state.instructions->view())
        {
            const auto useDef = inst.collectUseDef(*state.operands, state.context->encoder);
            for (const auto& reg : useDef.uses)
            {
                if (!reg.isVirtual())
                    continue;

                state.usePositions[reg.packed].push_back(idx);
            }

            ++idx;
        }
    }

    void setupPools(PassState& state)
    {
        // Build free lists split by class (int/float) and persistence (transient/persistent).
        state.intPersistentSet.clear();
        state.floatPersistentSet.clear();
        state.intPersistentSet.reserve(state.conv->intPersistentRegs.size() * 2 + 8);
        state.floatPersistentSet.reserve(state.conv->floatPersistentRegs.size() * 2 + 8);

        for (const auto reg : state.conv->intPersistentRegs)
            state.intPersistentSet.insert(reg.packed);

        for (const auto reg : state.conv->floatPersistentRegs)
            state.floatPersistentSet.insert(reg.packed);

        state.freeIntTransient.clear();
        state.freeIntPersistent.clear();
        state.freeFloatTransient.clear();
        state.freeFloatPersistent.clear();

        for (const auto reg : state.conv->intRegs)
        {
            if (state.intPersistentSet.contains(reg.packed))
                state.freeIntPersistent.push_back(reg);
            else
                state.freeIntTransient.push_back(reg);
        }

        for (const auto reg : state.conv->floatRegs)
        {
            if (state.floatPersistentSet.contains(reg.packed))
                state.freeFloatPersistent.push_back(reg);
            else
                state.freeFloatTransient.push_back(reg);
        }
    }

    void ensureSpillSlot(PassState& state, VRegState& regState, bool isFloat)
    {
        // Allocate spill slots lazily to avoid stack growth for registers that never spill.
        if (regState.hasSpill)
            return;

        const MicroOpBits bits     = isFloat ? MicroOpBits::B128 : MicroOpBits::B64;
        const uint64_t    slotSize = bits == MicroOpBits::B128 ? 16u : 8u;
        state.spillFrameUsed       = Math::alignUpU64(state.spillFrameUsed, slotSize);

        regState.spillOffset = state.spillFrameUsed;
        regState.spillBits   = bits;
        regState.hasSpill    = true;
        state.spillFrameUsed += slotSize;
    }

    void queueSpillStore(PendingInsert& out, MicroReg physReg, const VRegState& regState, const CallConv& conv)
    {
        out.op              = MicroInstrOpcode::LoadMemReg;
        out.numOps          = 4;
        out.ops[0].reg      = conv.stackPointer;
        out.ops[1].reg      = physReg;
        out.ops[2].opBits   = regState.spillBits;
        out.ops[3].valueU64 = regState.spillOffset;
    }

    void queueSpillLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState, const CallConv& conv)
    {
        out.op              = MicroInstrOpcode::LoadRegMem;
        out.numOps          = 4;
        out.ops[0].reg      = physReg;
        out.ops[1].reg      = conv.stackPointer;
        out.ops[2].opBits   = regState.spillBits;
        out.ops[3].valueU64 = regState.spillOffset;
    }

    bool isCandidateBetter(const PassState& state, uint32_t candidateKey, MicroReg candidateReg, uint32_t currentBestKey, MicroReg currentBestReg, uint32_t instructionIndex, uint32_t stamp)
    {
        if (!currentBestReg.isValid())
            return true;

        const bool candidateDead = !isLiveOut(state, candidateKey, stamp);
        const bool bestDead      = !isLiveOut(state, currentBestKey, stamp);
        if (candidateDead != bestDead)
            return candidateDead;

        const auto candidateIt = state.states.find(candidateKey);
        const auto bestIt      = state.states.find(currentBestKey);
        SWC_ASSERT(candidateIt != state.states.end());
        SWC_ASSERT(bestIt != state.states.end());

        const bool candidateCleanSpill = candidateIt->second.hasSpill && !candidateIt->second.dirty;
        const bool bestCleanSpill      = bestIt->second.hasSpill && !bestIt->second.dirty;
        if (candidateCleanSpill != bestCleanSpill)
            return candidateCleanSpill;

        const uint32_t candidateDistance = distanceToNextUse(state, candidateKey, instructionIndex);
        const uint32_t bestDistance      = distanceToNextUse(state, currentBestKey, instructionIndex);
        if (candidateDistance != bestDistance)
            return candidateDistance > bestDistance;

        const bool candidatePersistent = isPersistentPhysReg(state, candidateReg);
        const bool bestPersistent      = isPersistentPhysReg(state, currentBestReg);
        if (candidatePersistent != bestPersistent)
            return !candidatePersistent;

        return candidateKey > currentBestKey;
    }

    bool selectEvictionCandidate(const PassState&          state,
                                 uint32_t                  requestVirtKey,
                                 uint32_t                  instructionIndex,
                                 bool                      isFloatReg,
                                 bool                      fromPersistentPool,
                                 std::span<const uint32_t> protectedKeys,
                                 uint32_t                  stamp,
                                 uint32_t&                 outVirtKey,
                                 MicroReg&                 outPhys)
    {
        // Choose mapped virtual reg that is cheapest to evict under current constraints.
        outVirtKey = 0;
        outPhys    = MicroReg::invalid();

        for (const auto& [virtKey, physReg] : state.mapping)
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

            const bool isPersistent = isPersistentPhysReg(state, physReg);
            if (isPersistent != fromPersistentPool)
                continue;

            if (isPhysRegForbiddenForVirtual(state, requestVirtKey, physReg))
                continue;

            if (isCandidateBetter(state, virtKey, physReg, outVirtKey, outPhys, instructionIndex, stamp))
            {
                outVirtKey = virtKey;
                outPhys    = physReg;
            }
        }

        return outPhys.isValid();
    }

    bool tryTakeFreePhysical(PassState& state, const AllocRequest& request, MicroReg& outPhys)
    {
        outPhys = MicroReg::invalid();

        if (request.virtReg.isVirtualInt())
        {
            if (request.needsPersistent)
                return tryTakeAllowedPhysical(state.freeIntPersistent, state, request.virtKey, outPhys);

            if (tryTakeAllowedPhysical(state.freeIntTransient, state, request.virtKey, outPhys))
                return true;

            if (tryTakeAllowedPhysical(state.freeIntPersistent, state, request.virtKey, outPhys))
                return true;

            return false;
        }

        SWC_ASSERT(request.virtReg.isVirtualFloat());

        if (request.needsPersistent)
            return tryTakeAllowedPhysical(state.freeFloatPersistent, state, request.virtKey, outPhys);

        if (tryTakeAllowedPhysical(state.freeFloatTransient, state, request.virtKey, outPhys))
            return true;

        if (tryTakeAllowedPhysical(state.freeFloatPersistent, state, request.virtKey, outPhys))
            return true;

        return false;
    }

    void unmapVirtReg(PassState& state, uint32_t virtKey)
    {
        const auto mapIt = state.mapping.find(virtKey);
        if (mapIt == state.mapping.end())
            return;

        const auto physReg = mapIt->second;
        state.mapping.erase(mapIt);
        state.physToVirt.erase(physReg.packed);

        const auto stateIt = state.states.find(virtKey);
        if (stateIt != state.states.end())
        {
            stateIt->second.mapped = false;
            stateIt->second.phys   = MicroReg::invalid();
        }
    }

    void mapVirtReg(PassState& state, uint32_t virtKey, MicroReg physReg)
    {
        state.mapping[virtKey]           = physReg;
        state.physToVirt[physReg.packed] = virtKey;

        auto& regState  = state.states[virtKey];
        regState.mapped = true;
        regState.phys   = physReg;
    }

    MicroReg allocatePhysical(PassState&                  state,
                              const AllocRequest&         request,
                              std::span<const uint32_t>   protectedKeys,
                              uint32_t                    stamp,
                              std::vector<PendingInsert>& pending)
    {
        // Prefer free registers; otherwise evict one candidate and spill if needed.
        MicroReg physReg;
        if (tryTakeFreePhysical(state, request, physReg))
            return physReg;

        uint32_t victimKey = 0;
        MicroReg victimReg = MicroReg::invalid();

        const bool isFloatReg = request.virtReg.isVirtualFloat();

        if (request.needsPersistent)
        {
            SWC_ASSERT(selectEvictionCandidate(state, request.virtKey, request.instructionIndex, isFloatReg, true, protectedKeys, stamp, victimKey, victimReg));
        }
        else
        {
            if (!selectEvictionCandidate(state, request.virtKey, request.instructionIndex, isFloatReg, false, protectedKeys, stamp, victimKey, victimReg))
            {
                SWC_ASSERT(selectEvictionCandidate(state, request.virtKey, request.instructionIndex, isFloatReg, true, protectedKeys, stamp, victimKey, victimReg));
            }
        }

        auto& victimState = state.states[victimKey];
        if (isLiveOut(state, victimKey, stamp))
        {
            const bool hadSpillSlot = victimState.hasSpill;
            ensureSpillSlot(state, victimState, victimReg.isFloat());

            if (victimState.dirty || !hadSpillSlot)
            {
                PendingInsert spillPending;
                queueSpillStore(spillPending, victimReg, victimState, *state.conv);
                pending.push_back(spillPending);
                victimState.dirty = false;
            }
        }

        unmapVirtReg(state, victimKey);
        return victimReg;
    }

    MicroReg assignVirtReg(PassState&                  state,
                           const AllocRequest&         request,
                           std::span<const uint32_t>   protectedKeys,
                           uint32_t                    stamp,
                           std::vector<PendingInsert>& pending)
    {
        // Reuse existing mapping when possible, otherwise allocate and load from spill on use.
        const auto& regState = state.states[request.virtKey];
        if (regState.mapped)
            return regState.phys;

        const auto physReg = allocatePhysical(state, request, protectedKeys, stamp, pending);
        mapVirtReg(state, request.virtKey, physReg);

        auto& mappedState = state.states[request.virtKey];
        if (request.isUse)
        {
            SWC_ASSERT(mappedState.hasSpill);
            PendingInsert loadPending;
            queueSpillLoad(loadPending, physReg, mappedState, *state.conv);
            pending.push_back(loadPending);
            mappedState.dirty = false;
        }

        return physReg;
    }

    void spillCallLiveOut(PassState& state, uint32_t stamp, std::vector<PendingInsert>& pending)
    {
        // Calls may clobber transient regs; force spill of vulnerable live values before call.
        for (auto it = state.mapping.begin(); it != state.mapping.end();)
        {
            const uint32_t virtKey = it->first;
            const MicroReg physReg = it->second;

            if (!state.callSpillVregs.contains(virtKey) || !isLiveOut(state, virtKey, stamp))
            {
                ++it;
                continue;
            }

            auto& regState = state.states[virtKey];
            if (regState.dirty || !regState.hasSpill)
            {
                ensureSpillSlot(state, regState, physReg.isFloat());
                PendingInsert spillPending;
                queueSpillStore(spillPending, physReg, regState, *state.conv);
                pending.push_back(spillPending);
                regState.dirty = false;
            }

            regState.mapped = false;
            regState.phys   = MicroReg::invalid();
            state.physToVirt.erase(physReg.packed);
            it = state.mapping.erase(it);
            returnToFreePool(state, physReg);
        }
    }

    void expireDeadMappings(PassState& state, uint32_t stamp)
    {
        for (auto it = state.mapping.begin(); it != state.mapping.end();)
        {
            if (isLiveOut(state, it->first, stamp))
            {
                ++it;
                continue;
            }

            const auto deadReg = it->second;
            auto       stateIt = state.states.find(it->first);
            if (stateIt != state.states.end())
            {
                stateIt->second.mapped = false;
                stateIt->second.phys   = MicroReg::invalid();
            }

            state.physToVirt.erase(deadReg.packed);
            it = state.mapping.erase(it);
            returnToFreePool(state, deadReg);
        }
    }

    void rewriteInstructions(PassState& state)
    {
        // Main rewrite pass:
        // 1) assign physical registers for each virtual operand,
        // 2) queue spill loads/stores around the instruction,
        // 3) release dead mappings.
        state.liveStamp.clear();
        state.liveStamp.reserve(state.instructionCount * 2ull);

        uint32_t stamp = 1;
        uint32_t idx   = 0;
        for (auto it = state.instructions->view().begin(); it != state.instructions->view().end() && idx < state.instructionCount; ++it)
        {
            if (stamp == std::numeric_limits<uint32_t>::max())
            {
                state.liveStamp.clear();
                stamp = 1;
            }
            ++stamp;

            for (const auto key : state.liveOut[idx])
                state.liveStamp[key] = stamp;

            const Ref instructionRef = it.current;

            SmallVector<MicroInstrRegOperandRef> regRefs;
            it->collectRegOperands(*state.operands, regRefs, state.context->encoder);

            SmallVector<uint32_t> protectedKeys;
            protectedKeys.reserve(regRefs.size());
            for (const auto& regRef : regRefs)
            {
                if (!regRef.reg)
                    continue;

                const auto reg = *regRef.reg;
                if (!reg.isVirtual())
                    continue;

                if (!containsKey(protectedKeys, reg.packed))
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

                AllocRequest request;
                request.virtReg          = reg;
                request.virtKey          = reg.packed;
                request.isUse            = regRef.use;
                request.isDef            = regRef.def;
                request.instructionIndex = idx;

                const bool liveAcrossCall = state.vregsLiveAcrossCall.contains(request.virtKey);
                if (reg.isVirtualInt())
                    request.needsPersistent = liveAcrossCall && !state.conv->intPersistentRegs.empty();
                else
                    request.needsPersistent = liveAcrossCall && !state.conv->floatPersistentRegs.empty();

                // If no persistent class exists, remember to spill around call boundaries.
                if (liveAcrossCall && !request.needsPersistent)
                    state.callSpillVregs.insert(request.virtKey);

                const auto physReg              = assignVirtReg(state, request, protectedKeys, stamp, pending);
                *SWC_CHECK_NOT_NULL(regRef.reg) = physReg;

                if (request.isDef)
                    state.states[request.virtKey].dirty = true;
            }

            const auto useDef = it->collectUseDef(*state.operands, state.context->encoder);
            if (useDef.isCall)
                spillCallLiveOut(state, stamp, pending);

            for (const auto& pendingInst : pending)
            {
                state.instructions->insertBefore(*state.operands, instructionRef, pendingInst.op, std::span(pendingInst.ops, pendingInst.numOps));
            }

            expireDeadMappings(state, stamp);
            ++idx;
        }
    }

    void insertSpillFrame(const PassState& state)
    {
        // Materialize one function-level spill frame and balance it before every return.
        if (!state.spillFrameUsed)
            return;

        const uint64_t stackAlignment = state.conv->stackAlignment ? state.conv->stackAlignment : 16;
        const uint64_t spillFrameSize = Math::alignUpU64(state.spillFrameUsed, stackAlignment);
        if (!spillFrameSize)
            return;

        const auto beginIt = state.instructions->view().begin();
        if (beginIt == state.instructions->view().end())
            return;

        const Ref firstRef = beginIt.current;

        MicroInstrOperand subOps[4];
        subOps[0].reg      = state.conv->stackPointer;
        subOps[1].opBits   = MicroOpBits::B64;
        subOps[2].microOp  = MicroOp::Subtract;
        subOps[3].valueU64 = spillFrameSize;
        state.instructions->insertBefore(*state.operands, firstRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

        std::vector<Ref> retRefs;
        for (auto it = state.instructions->view().begin(); it != state.instructions->view().end(); ++it)
        {
            if (it->op == MicroInstrOpcode::Ret)
                retRefs.push_back(it.current);
        }

        for (const auto retRef : retRefs)
        {
            MicroInstrOperand addOps[4];
            addOps[0].reg      = state.conv->stackPointer;
            addOps[1].opBits   = MicroOpBits::B64;
            addOps[2].microOp  = MicroOp::Add;
            addOps[3].valueU64 = spillFrameSize;
            state.instructions->insertBefore(*state.operands, retRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
        }
    }
}

void MicroRegisterAllocationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);

    // Order matters: liveness/use analysis informs allocation, then we patch IR and finalize frame.
    PassState state;
    initState(state, context);

    if (!state.instructionCount)
        return;

    analyzeLiveness(state);
    buildUsePositions(state);
    setupPools(state);
    rewriteInstructions(state);
    insertSpillFrame(state);
}

SWC_END_NAMESPACE();
