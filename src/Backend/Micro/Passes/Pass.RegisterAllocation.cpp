#include "pch.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Math/Helpers.h"

// Assigns physical registers to virtual registers and handles spills.
// Example: v3 -> rax when a free compatible register exists.
// Example: under pressure, v7 lives on stack: store v7 before conflict, reload before use.
// This pass converts virtual microcode into concrete register form.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool hasVirtualRegisters(const MicroPassContext& context)
    {
        SWC_ASSERT(context.instructions != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        MicroOperandStorage& storeOps = *SWC_NOT_NULL(context.operands);
        for (const MicroInstr& inst : context.instructions->view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(storeOps, refs, context.encoder);
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg)
                    continue;
                if (ref.reg->isVirtual())
                    return true;
            }
        }

        return false;
    }

    struct VRegState
    {
        MicroReg    phys;
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
        MicroReg virtReg;
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
        bool     hasControlFlow   = false;

        std::vector<std::vector<uint32_t>>                  liveOut;
        std::vector<std::vector<uint32_t>>                  concreteLiveOut;
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
        std::unordered_map<uint32_t, uint32_t>  liveStamp;
        std::unordered_map<uint32_t, uint32_t>  concreteLiveStamp;
        std::unordered_set<uint32_t>            callSpillVregs;
    };

    void initState(PassState& state, MicroPassContext& context)
    {
        state.context          = &context;
        state.conv             = &CallConv::get(context.callConvKind);
        state.instructions     = SWC_NOT_NULL(context.instructions);
        state.operands         = SWC_NOT_NULL(context.operands);
        state.instructionCount = state.instructions->count();
        state.hasControlFlow   = false;

        const size_t reserveCount = static_cast<size_t>(state.instructionCount) * 2ull + 8ull;
        state.vregsLiveAcrossCall.reserve(reserveCount);
        state.usePositions.reserve(static_cast<size_t>(state.instructionCount) + 8ull);
        state.states.reserve(reserveCount);
        state.mapping.reserve(reserveCount);
        state.liveStamp.reserve(reserveCount);
        state.concreteLiveStamp.reserve(reserveCount);
        state.callSpillVregs.reserve(reserveCount);

        for (const auto& inst : state.instructions->view())
        {
            if (inst.op == MicroInstrOpcode::Label || MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::JumpInstruction))
            {
                state.hasControlFlow = true;
                break;
            }
        }
    }

    bool isLiveOut(const PassState& state, uint32_t key, uint32_t stamp)
    {
        const auto it = state.liveStamp.find(key);
        if (it == state.liveStamp.end())
            return false;
        return it->second == stamp;
    }

    bool isConcreteLiveOut(const PassState& state, MicroReg reg, uint32_t stamp)
    {
        if (!reg.isInt() && !reg.isFloat())
            return false;

        const auto it = state.concreteLiveStamp.find(reg.packed);
        if (it == state.concreteLiveStamp.end())
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

    bool tryTakeAllowedPhysical(SmallVector<MicroReg>& pool,
                                const PassState&       state,
                                uint32_t               virtKey,
                                uint32_t               stamp,
                                bool                   allowConcreteLive,
                                MicroReg&              outPhys)
    {
        for (size_t index = pool.size(); index > 0; --index)
        {
            const size_t candidateIndex = index - 1;
            const auto   candidateReg   = pool[candidateIndex];
            if (isPhysRegForbiddenForVirtual(state, virtKey, candidateReg))
                continue;
            if (!allowConcreteLive && isConcreteLiveOut(state, candidateReg, stamp))
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
        // CFG-aware backward liveness: captures live-out sets even across back-edges.
        state.liveOut.clear();
        state.liveOut.resize(state.instructionCount);
        state.concreteLiveOut.clear();
        state.concreteLiveOut.resize(state.instructionCount);
        state.vregsLiveAcrossCall.clear();

        if (!state.instructionCount)
            return;

        std::vector<const MicroInstr*>            instructions;
        std::vector<MicroInstrUseDef>             useDefs;
        std::vector<std::vector<uint32_t>>        useVirtual;
        std::vector<std::vector<uint32_t>>        defVirtual;
        std::vector<std::vector<uint32_t>>        useConcrete;
        std::vector<std::vector<uint32_t>>        defConcrete;
        std::vector<SmallVector<uint32_t>>        successors;
        std::unordered_map<uint32_t, uint32_t>    labelToIndex;
        std::vector<std::unordered_set<uint32_t>> liveInVirtual;
        std::vector<std::unordered_set<uint32_t>> liveOutVirtual;
        std::vector<std::unordered_set<uint32_t>> liveInConcrete;
        std::vector<std::unordered_set<uint32_t>> liveOutConcrete;
        const auto                                reserveCount = static_cast<size_t>(state.instructionCount);

        instructions.reserve(reserveCount);
        useDefs.resize(state.instructionCount);
        useVirtual.resize(state.instructionCount);
        defVirtual.resize(state.instructionCount);
        useConcrete.resize(state.instructionCount);
        defConcrete.resize(state.instructionCount);
        successors.resize(state.instructionCount);
        labelToIndex.reserve(reserveCount / 2 + 1);
        liveInVirtual.resize(state.instructionCount);
        liveOutVirtual.resize(state.instructionCount);
        liveInConcrete.resize(state.instructionCount);
        liveOutConcrete.resize(state.instructionCount);

        uint32_t idx = 0;
        for (const auto& inst : state.instructions->view())
        {
            instructions.push_back(&inst);
            useDefs[idx] = inst.collectUseDef(*state.operands, state.context->encoder);

            auto& usesV = useVirtual[idx];
            auto& defsV = defVirtual[idx];
            auto& usesC = useConcrete[idx];
            auto& defsC = defConcrete[idx];
            usesV.reserve(useDefs[idx].uses.size());
            defsV.reserve(useDefs[idx].defs.size());
            usesC.reserve(useDefs[idx].uses.size());
            defsC.reserve(useDefs[idx].defs.size());

            for (const auto& reg : useDefs[idx].uses)
            {
                if (reg.isVirtual())
                    usesV.push_back(reg.packed);
                else if (reg.isInt() || reg.isFloat())
                    usesC.push_back(reg.packed);
            }

            for (const auto& reg : useDefs[idx].defs)
            {
                if (reg.isVirtual())
                    defsV.push_back(reg.packed);
                else if (reg.isInt() || reg.isFloat())
                    defsC.push_back(reg.packed);
            }

            if (inst.op == MicroInstrOpcode::Label && inst.numOperands >= 1)
            {
                const MicroInstrOperand* const ops                   = inst.ops(*state.operands);
                labelToIndex[static_cast<uint32_t>(ops[0].valueU64)] = idx;
            }

            ++idx;
        }

        idx = 0;
        for (const MicroInstr* inst : instructions)
        {
            SWC_ASSERT(inst != nullptr);
            const MicroInstrOperand* const ops  = inst->ops(*state.operands);
            auto&                          succ = successors[idx];
            succ.clear();
            succ.reserve(2);

            if ((inst->op == MicroInstrOpcode::JumpCond || inst->op == MicroInstrOpcode::JumpCondImm) && inst->numOperands >= 3)
            {
                const uint32_t labelId = static_cast<uint32_t>(ops[2].valueU64);
                const auto     itLabel = labelToIndex.find(labelId);
                if (itLabel != labelToIndex.end())
                    succ.push_back(itLabel->second);

                if (!MicroInstrInfo::isUnconditionalJumpInstruction(*inst, ops) && idx + 1 < state.instructionCount)
                    succ.push_back(idx + 1);
            }
            else if (!MicroInstrInfo::isTerminatorInstruction(*inst) && idx + 1 < state.instructionCount)
            {
                succ.push_back(idx + 1);
            }

            ++idx;
        }

        bool changed = true;
        while (changed)
        {
            changed = false;

            for (int64_t rev = static_cast<int64_t>(state.instructionCount) - 1; rev >= 0; --rev)
            {
                const uint32_t i = static_cast<uint32_t>(rev);

                std::unordered_set<uint32_t> newOutV;
                std::unordered_set<uint32_t> newOutC;
                for (const auto succIdx : successors[i])
                {
                    newOutV.insert(liveInVirtual[succIdx].begin(), liveInVirtual[succIdx].end());
                    newOutC.insert(liveInConcrete[succIdx].begin(), liveInConcrete[succIdx].end());
                }

                std::unordered_set<uint32_t> newInV = newOutV;
                for (const auto defKey : defVirtual[i])
                    newInV.erase(defKey);
                for (const auto useKey : useVirtual[i])
                    newInV.insert(useKey);

                std::unordered_set<uint32_t> newInC = newOutC;
                for (const auto defKey : defConcrete[i])
                    newInC.erase(defKey);
                for (const auto useKey : useConcrete[i])
                    newInC.insert(useKey);

                if (newOutV != liveOutVirtual[i] ||
                    newOutC != liveOutConcrete[i] ||
                    newInV != liveInVirtual[i] ||
                    newInC != liveInConcrete[i])
                {
                    changed            = true;
                    liveOutVirtual[i]  = std::move(newOutV);
                    liveOutConcrete[i] = std::move(newOutC);
                    liveInVirtual[i]   = std::move(newInV);
                    liveInConcrete[i]  = std::move(newInC);
                }
            }
        }

        for (uint32_t i = 0; i < state.instructionCount; ++i)
        {
            auto& outVirtual = state.liveOut[i];
            outVirtual.clear();
            outVirtual.reserve(liveOutVirtual[i].size());
            for (const auto key : liveOutVirtual[i])
                outVirtual.push_back(key);

            auto& outConcrete = state.concreteLiveOut[i];
            outConcrete.clear();
            outConcrete.reserve(liveOutConcrete[i].size());
            for (const auto key : liveOutConcrete[i])
                outConcrete.push_back(key);

            if (useDefs[i].isCall)
            {
                for (const auto key : liveOutVirtual[i])
                    state.vregsLiveAcrossCall.insert(key);
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
        state.freeIntTransient.reserve(state.conv->intRegs.size());
        state.freeIntPersistent.reserve(state.conv->intRegs.size());
        state.freeFloatTransient.reserve(state.conv->floatRegs.size());
        state.freeFloatPersistent.reserve(state.conv->floatRegs.size());

        for (const auto reg : state.conv->intRegs)
        {
            if (reg == state.conv->framePointer)
                continue;

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

    uint64_t spillMemOffset(uint64_t spillOffset, int64_t stackDepth)
    {
        SWC_ASSERT(spillOffset <= static_cast<uint64_t>(std::numeric_limits<int64_t>::max()));
        auto finalOffset = static_cast<int64_t>(spillOffset);
        finalOffset += stackDepth;
        SWC_ASSERT(finalOffset >= std::numeric_limits<int32_t>::min());
        SWC_ASSERT(finalOffset <= std::numeric_limits<int32_t>::max());
        return static_cast<uint64_t>(finalOffset);
    }

    void queueSpillStore(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth, const CallConv& conv)
    {
        out.op              = MicroInstrOpcode::LoadMemReg;
        out.numOps          = 4;
        out.ops[0].reg      = conv.stackPointer;
        out.ops[1].reg      = physReg;
        out.ops[2].opBits   = regState.spillBits;
        out.ops[3].valueU64 = spillMemOffset(regState.spillOffset, stackDepth);
    }

    void queueSpillLoad(PendingInsert& out, MicroReg physReg, const VRegState& regState, int64_t stackDepth, const CallConv& conv)
    {
        out.op              = MicroInstrOpcode::LoadRegMem;
        out.numOps          = 4;
        out.ops[0].reg      = physReg;
        out.ops[1].reg      = conv.stackPointer;
        out.ops[2].opBits   = regState.spillBits;
        out.ops[3].valueU64 = spillMemOffset(regState.spillOffset, stackDepth);
    }

    void applyStackPointerDelta(int64_t& stackDepth, const MicroInstr& inst, const MicroOperandStorage& operands, const CallConv& conv)
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

        const MicroInstrOperand* ops = inst.ops(operands);
        if (ops[0].reg != conv.stackPointer)
            return;
        if (ops[1].opBits != MicroOpBits::B64)
            return;

        const auto immValue = static_cast<int64_t>(ops[3].valueU64);
        if (ops[2].microOp == MicroOp::Subtract)
            stackDepth += immValue;
        else if (ops[2].microOp == MicroOp::Add)
            stackDepth -= immValue;
    }

    void mergeLabelStackDepth(std::unordered_map<MicroLabelRef, int64_t>& labelStackDepth, MicroLabelRef labelRef, int64_t stackDepth)
    {
        const auto it = labelStackDepth.find(labelRef);
        if (it == labelStackDepth.end())
        {
            labelStackDepth.emplace(labelRef, stackDepth);
            return;
        }

        // Keep the first observed depth. Mismatches can happen on dead edges
        // (for example after a return in linearized IR).
        if (it->second != stackDepth)
            return;
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
                                 bool                      allowConcreteLive,
                                 uint32_t&                 outVirtKey,
                                 MicroReg&                 outPhys)
    {
        // Choose mapped virtual reg that is cheapest to evict under current constraints.
        outVirtKey = 0;
        outPhys    = MicroReg{};

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
            if (!allowConcreteLive && isConcreteLiveOut(state, physReg, stamp))
                continue;

            if (isCandidateBetter(state, virtKey, physReg, outVirtKey, outPhys, instructionIndex, stamp))
            {
                outVirtKey = virtKey;
                outPhys    = physReg;
            }
        }

        return outPhys.isValid();
    }

    struct FreePools
    {
        SmallVector<MicroReg>* primary   = nullptr;
        SmallVector<MicroReg>* secondary = nullptr;
    };

    FreePools pickFreePools(PassState& state, const AllocRequest& request)
    {
        if (request.virtReg.isVirtualInt())
        {
            if (request.needsPersistent)
                return FreePools{&state.freeIntPersistent, &state.freeIntTransient};

            return FreePools{&state.freeIntTransient, nullptr};
        }

        SWC_ASSERT(request.virtReg.isVirtualFloat());
        if (request.needsPersistent)
            return FreePools{&state.freeFloatPersistent, &state.freeFloatTransient};

        return FreePools{&state.freeFloatTransient, nullptr};
    }

    bool tryTakeFreePhysical(PassState&          state,
                             const AllocRequest& request,
                             uint32_t            stamp,
                             bool                allowConcreteLive,
                             MicroReg&           outPhys)
    {
        const FreePools pools = pickFreePools(state, request);
        SWC_ASSERT(pools.primary != nullptr);

        if (tryTakeAllowedPhysical(*pools.primary, state, request.virtKey, stamp, allowConcreteLive, outPhys))
            return true;

        if (pools.secondary)
            return tryTakeAllowedPhysical(*pools.secondary, state, request.virtKey, stamp, allowConcreteLive, outPhys);

        return false;
    }

    void unmapVirtReg(PassState& state, uint32_t virtKey)
    {
        const auto mapIt = state.mapping.find(virtKey);
        if (mapIt == state.mapping.end())
            return;

        state.mapping.erase(mapIt);

        const auto stateIt = state.states.find(virtKey);
        if (stateIt != state.states.end())
            stateIt->second.mapped = false;
    }

    void mapVirtReg(PassState& state, uint32_t virtKey, MicroReg physReg)
    {
        state.mapping[virtKey] = physReg;

        auto& regState  = state.states[virtKey];
        regState.mapped = true;
        regState.phys   = physReg;
    }

    bool selectEvictionCandidateWithFallback(const PassState&          state,
                                             uint32_t                  requestVirtKey,
                                             uint32_t                  instructionIndex,
                                             bool                      isFloatReg,
                                             bool                      preferPersistentPool,
                                             std::span<const uint32_t> protectedKeys,
                                             uint32_t                  stamp,
                                             bool                      allowConcreteLive,
                                             uint32_t&                 outVirtKey,
                                             MicroReg&                 outPhys)
    {
        if (selectEvictionCandidate(state, requestVirtKey, instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, stamp, allowConcreteLive, outVirtKey, outPhys))
            return true;

        return selectEvictionCandidate(state, requestVirtKey, instructionIndex, isFloatReg, !preferPersistentPool, protectedKeys, stamp, allowConcreteLive, outVirtKey, outPhys);
    }

    MicroReg allocatePhysical(PassState&                  state,
                              const AllocRequest&         request,
                              std::span<const uint32_t>   protectedKeys,
                              uint32_t                    stamp,
                              int64_t                     stackDepth,
                              std::vector<PendingInsert>& pending)
    {
        // Prefer free registers; otherwise evict one candidate and spill if needed.
        MicroReg physReg;
        if (tryTakeFreePhysical(state, request, stamp, false, physReg))
            return physReg;

        uint32_t victimKey = 0;
        MicroReg victimReg;

        const bool isFloatReg           = request.virtReg.isVirtualFloat();
        const bool preferPersistentPool = request.needsPersistent;
        SWC_INTERNAL_CHECK(selectEvictionCandidateWithFallback(state, request.virtKey, request.instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, stamp, false, victimKey, victimReg));

        auto&      victimState   = state.states[victimKey];
        const bool victimLiveOut = isLiveOut(state, victimKey, stamp);
        if (victimLiveOut)
        {
            const bool hadSpillSlot = victimState.hasSpill;
            ensureSpillSlot(state, victimState, victimReg.isFloat());
            if (victimState.dirty || !hadSpillSlot)
            {
                PendingInsert spillPending;
                queueSpillStore(spillPending, victimReg, victimState, stackDepth, *state.conv);
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
                           int64_t                     stackDepth,
                           std::vector<PendingInsert>& pending)
    {
        // Reuse existing mapping when possible, otherwise allocate and load from spill on use.
        const auto& regState = state.states[request.virtKey];
        if (regState.mapped)
            return regState.phys;

        const auto physReg = allocatePhysical(state, request, protectedKeys, stamp, stackDepth, pending);
        mapVirtReg(state, request.virtKey, physReg);

        auto& mappedState = state.states[request.virtKey];
        if (request.isUse)
        {
            SWC_ASSERT(mappedState.hasSpill);
            PendingInsert loadPending;
            queueSpillLoad(loadPending, physReg, mappedState, stackDepth, *state.conv);
            pending.push_back(loadPending);
            mappedState.dirty = false;
        }

        return physReg;
    }

    void spillCallLiveOut(PassState& state, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
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
                queueSpillStore(spillPending, physReg, regState, stackDepth, *state.conv);
                pending.push_back(spillPending);
                regState.dirty = false;
            }

            regState.mapped = false;
            it              = state.mapping.erase(it);
            returnToFreePool(state, physReg);
        }
    }

    void flushAllMappedVirtuals(PassState& state, int64_t stackDepth, std::vector<PendingInsert>& pending)
    {
        // Control-flow boundaries require a stable memory state for all mapped values.
        for (const auto& [virtKey, physReg] : state.mapping)
        {
            auto& regState = state.states[virtKey];
            if (regState.dirty || !regState.hasSpill)
            {
                ensureSpillSlot(state, regState, physReg.isFloat());
                PendingInsert spillPending;
                queueSpillStore(spillPending, physReg, regState, stackDepth, *state.conv);
                pending.push_back(spillPending);
                regState.dirty = false;
            }

            regState.mapped = false;
            returnToFreePool(state, physReg);
        }

        state.mapping.clear();
    }

    void clearAllMappedVirtuals(PassState& state)
    {
        for (const auto& [virtKey, physReg] : state.mapping)
        {
            auto& regState  = state.states[virtKey];
            regState.mapped = false;
            returnToFreePool(state, physReg);
        }

        state.mapping.clear();
    }

    void expireDeadMappings(PassState& state, uint32_t stamp)
    {
        // Linear dead-expiry is only safe when the instruction stream has no control-flow joins.
        if (state.hasControlFlow)
            return;

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
                stateIt->second.mapped = false;

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
        state.concreteLiveStamp.clear();
        state.concreteLiveStamp.reserve(state.instructionCount * 2ull);

        uint32_t                                   stamp      = 1;
        uint32_t                                   idx        = 0;
        int64_t                                    stackDepth = 0;
        std::unordered_map<MicroLabelRef, int64_t> labelStackDepth;
        if (state.hasControlFlow)
            labelStackDepth.reserve(state.instructions->count() / 2 + 1);
        for (auto it = state.instructions->view().begin(); it != state.instructions->view().end() && idx < state.instructionCount; ++it)
        {
            if (stamp == std::numeric_limits<uint32_t>::max())
            {
                state.liveStamp.clear();
                state.concreteLiveStamp.clear();
                stamp = 1;
            }
            ++stamp;

            if (it->op == MicroInstrOpcode::Label && it->numOperands >= 1)
            {
                const MicroInstrOperand* const ops = it->ops(*state.operands);
                const MicroLabelRef            labelRef(static_cast<uint32_t>(ops[0].valueU64));
                const auto                     labelIt = labelStackDepth.find(labelRef);
                if (labelIt != labelStackDepth.end())
                    stackDepth = labelIt->second;
            }

            for (const auto key : state.liveOut[idx])
                state.liveStamp[key] = stamp;
            for (const auto key : state.concreteLiveOut[idx])
                state.concreteLiveStamp[key] = stamp;

            const MicroInstrRef instructionRef = it.current;
            const bool          isCall         = it->collectUseDef(*state.operands, state.context->encoder).isCall;
            const bool          isTerminator   = MicroInstrInfo::isTerminatorInstruction(*it);

            if (state.hasControlFlow && (it->op == MicroInstrOpcode::Label || isTerminator))
            {
                std::vector<PendingInsert> boundaryPending;
                boundaryPending.reserve(state.mapping.size());
                flushAllMappedVirtuals(state, stackDepth, boundaryPending);
                for (const auto& pendingInst : boundaryPending)
                {
                    state.instructions->insertBefore(*state.operands, instructionRef, pendingInst.op, std::span(pendingInst.ops, pendingInst.numOps));
                }
            }

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

                const auto physReg        = assignVirtReg(state, request, protectedKeys, stamp, stackDepth, pending);
                *SWC_NOT_NULL(regRef.reg) = physReg;

                if (liveAcrossCall && !isPersistentPhysReg(state, physReg))
                    state.callSpillVregs.insert(request.virtKey);

                if (request.isDef)
                    state.states[request.virtKey].dirty = true;
            }

            if (isCall)
                spillCallLiveOut(state, stamp, stackDepth, pending);

            for (const auto& pendingInst : pending)
            {
                state.instructions->insertBefore(*state.operands, instructionRef, pendingInst.op, std::span(pendingInst.ops, pendingInst.numOps));
            }

            expireDeadMappings(state, stamp);

            if (it->op == MicroInstrOpcode::JumpCond && it->numOperands >= 3)
            {
                const MicroInstrOperand* const ops = it->ops(*state.operands);
                const MicroLabelRef            labelRef(static_cast<uint32_t>(ops[2].valueU64));
                mergeLabelStackDepth(labelStackDepth, labelRef, stackDepth);
            }

            applyStackPointerDelta(stackDepth, *it, *state.operands, *state.conv);

            if (state.hasControlFlow && isTerminator)
                clearAllMappedVirtuals(state);

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

        const MicroInstrRef firstRef = beginIt.current;

        MicroInstrOperand subOps[4];
        subOps[0].reg      = state.conv->stackPointer;
        subOps[1].opBits   = MicroOpBits::B64;
        subOps[2].microOp  = MicroOp::Subtract;
        subOps[3].valueU64 = spillFrameSize;
        state.instructions->insertBefore(*state.operands, firstRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

        std::vector<MicroInstrRef> retRefs;
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

Result MicroRegisterAllocationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);

    // Order matters: liveness/use analysis informs allocation, then we patch IR and finalize frame.
    PassState state;
    initState(state, context);

    if (!state.instructionCount)
    {
        context.passChanged = false;
        return Result::Continue;
    }

    const bool hadVirtualRegisters = hasVirtualRegisters(context);

    analyzeLiveness(state);
    buildUsePositions(state);
    setupPools(state);
    rewriteInstructions(state);
    insertSpillFrame(state);

    context.passChanged = hadVirtualRegisters || state.spillFrameUsed != 0;
    return Result::Continue;
}

SWC_END_NAMESPACE();
