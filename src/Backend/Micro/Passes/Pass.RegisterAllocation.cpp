#include "pch.h"
#include "Backend/Micro/Passes/Pass.RegisterAllocation.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
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
    using VRegState = MicroRegisterAllocationPass::VRegState;

    struct PendingInsert
    {
        MicroInstrOpcode  op     = MicroInstrOpcode::Nop;
        uint8_t           numOps = 0;
        MicroInstrOperand ops[4] = {};
    };

    struct AllocRequest
    {
        MicroReg virtReg;
        MicroReg virtKey          = MicroReg::invalid();
        bool     needsPersistent  = false;
        bool     isUse            = false;
        bool     isDef            = false;
        uint32_t instructionIndex = 0;
    };

    struct PassState
    {
        MicroPassContext*&                                                    context;
        const CallConv*&                                                      conv;
        MicroStorage*&                                                        instructions;
        MicroOperandStorage*&                                                 operands;
        uint32_t&                                                             instructionCount;
        uint64_t&                                                             spillFrameUsed;
        bool&                                                                 hasControlFlow;
        std::vector<std::vector<MicroReg>>&                                   liveOut;
        std::vector<std::vector<MicroReg>>&                                   concreteLiveOut;
        std::unordered_set<MicroReg>&                                         vregsLiveAcrossCall;
        std::unordered_map<MicroReg, std::vector<uint32_t>>&                  usePositions;
        std::vector<MicroInstrUseDef>&                                        instructionUseDefs;
        std::unordered_set<MicroReg>&                                         intPersistentSet;
        std::unordered_set<MicroReg>&                                         floatPersistentSet;
        SmallVector<MicroReg>&                                                freeIntTransient;
        SmallVector<MicroReg>&                                                freeIntPersistent;
        SmallVector<MicroReg>&                                                freeFloatTransient;
        SmallVector<MicroReg>&                                                freeFloatPersistent;
        std::unordered_map<MicroReg, MicroRegisterAllocationPass::VRegState>& states;
        std::unordered_map<MicroReg, MicroReg>&                               mapping;
        std::unordered_map<MicroReg, uint32_t>&                               liveStamp;
        std::unordered_map<MicroReg, uint32_t>&                               concreteLiveStamp;
        std::unordered_set<MicroReg>&                                         callSpillVregs;
    };

    uint32_t ensureDenseRegIndex(std::unordered_map<MicroReg, uint32_t>& regToIndex,
                                 std::vector<MicroReg>&                  regs,
                                 const MicroReg                          reg)
    {
        const auto it = regToIndex.find(reg);
        if (it != regToIndex.end())
            return it->second;

        const uint32_t newIndex = static_cast<uint32_t>(regs.size());
        regToIndex.emplace(reg, newIndex);
        regs.push_back(reg);
        return newIndex;
    }

    void denseBitSet(std::span<uint64_t> bits, uint32_t bitIndex)
    {
        if (bits.empty())
            return;

        const uint32_t wordIndex = bitIndex >> 6u;
        SWC_ASSERT(wordIndex < bits.size());
        bits[wordIndex] |= (1ull << (bitIndex & 63u));
    }

    void denseBitClear(std::span<uint64_t> bits, uint32_t bitIndex)
    {
        if (bits.empty())
            return;

        const uint32_t wordIndex = bitIndex >> 6u;
        SWC_ASSERT(wordIndex < bits.size());
        bits[wordIndex] &= ~(1ull << (bitIndex & 63u));
    }

    std::span<uint64_t> denseBitRow(std::vector<uint64_t>& bits, uint32_t row, uint32_t rowWordCount)
    {
        if (!rowWordCount)
            return {};

        const size_t offset = static_cast<size_t>(row) * rowWordCount;
        return std::span<uint64_t>(bits.data() + offset, rowWordCount);
    }

    std::span<const uint64_t> denseBitRow(const std::vector<uint64_t>& bits, uint32_t row, uint32_t rowWordCount)
    {
        if (!rowWordCount)
            return {};

        const size_t offset = static_cast<size_t>(row) * rowWordCount;
        return std::span<const uint64_t>(bits.data() + offset, rowWordCount);
    }

    bool copyDenseRowIfChanged(std::span<uint64_t> dst, const std::span<const uint64_t> src)
    {
        SWC_ASSERT(dst.size() == src.size());
        bool changed = false;
        for (size_t i = 0; i < dst.size(); ++i)
        {
            if (dst[i] != src[i])
            {
                changed = true;
                break;
            }
        }

        if (!changed)
            return false;

        for (size_t i = 0; i < dst.size(); ++i)
            dst[i] = src[i];
        return true;
    }

    uint32_t denseBitCount(const std::span<const uint64_t> bits)
    {
        uint32_t result = 0;
        for (const uint64_t value : bits)
            result += std::popcount(value);
        return result;
    }

    void initState(const PassState& state, MicroPassContext& context)
    {
        state.context          = &context;
        state.conv             = &CallConv::get(context.callConvKind);
        state.instructions     = SWC_NOT_NULL(context.instructions);
        state.operands         = SWC_NOT_NULL(context.operands);
        state.instructionCount = state.instructions->count();
        state.spillFrameUsed   = 0;
        state.hasControlFlow   = false;

        const size_t reserveCount = static_cast<size_t>(state.instructionCount) * 2ull + 8ull;
        state.vregsLiveAcrossCall.reserve(reserveCount);
        state.usePositions.reserve(static_cast<size_t>(state.instructionCount) + 8ull);
        state.instructionUseDefs.clear();
        state.instructionUseDefs.resize(state.instructionCount);
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

    bool isLiveOut(const PassState& state, MicroReg key, uint32_t stamp)
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

        const auto it = state.concreteLiveStamp.find(reg);
        if (it == state.concreteLiveStamp.end())
            return false;
        return it->second == stamp;
    }

    bool containsKey(std::span<const MicroReg> keys, MicroReg key)
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
            return state.intPersistentSet.contains(reg);

        if (reg.isFloat())
            return state.floatPersistentSet.contains(reg);

        SWC_ASSERT(false);
        return false;
    }

    bool isPhysRegForbiddenForVirtual(const PassState& state, MicroReg virtKey, MicroReg physReg)
    {
        SWC_ASSERT(state.context != nullptr);
        SWC_ASSERT(state.context->builder != nullptr);
        return state.context->builder->isVirtualRegPhysRegForbidden(virtKey, physReg);
    }

    bool tryTakeAllowedPhysical(SmallVector<MicroReg>& pool,
                                const PassState&       state,
                                MicroReg               virtKey,
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

    void returnToFreePool(const PassState& state, MicroReg reg)
    {
        if (reg.isInt())
        {
            if (state.intPersistentSet.contains(reg))
                state.freeIntPersistent.push_back(reg);
            else
                state.freeIntTransient.push_back(reg);
            return;
        }

        if (reg.isFloat())
        {
            if (state.floatPersistentSet.contains(reg))
                state.freeFloatPersistent.push_back(reg);
            else
                state.freeFloatTransient.push_back(reg);
            return;
        }

        SWC_ASSERT(false);
    }

    uint32_t distanceToNextUse(const PassState& state, MicroReg key, uint32_t instructionIndex)
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

    bool prepareInstructionData(const PassState& state)
    {
        state.usePositions.clear();

        if (!state.instructionCount)
            return false;

        const MicroControlFlowGraph&         controlFlowGraph = SWC_NOT_NULL(state.context->builder)->controlFlowGraph();
        const std::span<const MicroInstrRef> instructionRefs  = controlFlowGraph.instructionRefs();
        SWC_ASSERT(instructionRefs.size() == state.instructionCount);
        if (instructionRefs.size() != state.instructionCount)
            return false;

        bool hasVirtual = false;
        for (uint32_t idx = 0; idx < state.instructionCount; ++idx)
        {
            const MicroInstr* const inst = state.instructions->ptr(instructionRefs[idx]);
            if (!inst)
                continue;

            MicroInstrUseDef useDef = inst->collectUseDef(*state.operands, state.context->encoder);
            for (const MicroReg reg : useDef.uses)
            {
                if (!reg.isVirtual())
                    continue;

                hasVirtual = true;
                state.usePositions[reg].push_back(idx);
            }

            for (const MicroReg reg : useDef.defs)
            {
                if (reg.isVirtual())
                    hasVirtual = true;
            }

            state.instructionUseDefs[idx] = std::move(useDef);
        }

        return hasVirtual;
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

        const MicroControlFlowGraph&         controlFlowGraph = SWC_NOT_NULL(state.context->builder)->controlFlowGraph();
        const std::span<const MicroInstrRef> instructionRefs  = controlFlowGraph.instructionRefs();
        SWC_ASSERT(instructionRefs.size() == state.instructionCount);
        if (instructionRefs.size() != state.instructionCount)
            return;

        std::unordered_map<MicroReg, uint32_t> denseVirtual;
        std::vector<MicroReg>                  virtualRegs;
        std::unordered_map<MicroReg, uint32_t> denseConcrete;
        std::vector<MicroReg>                  concreteRegs;
        const size_t                           denseReserve = static_cast<size_t>(state.instructionCount) * 2ull + 8ull;
        denseVirtual.reserve(denseReserve);
        denseConcrete.reserve(denseReserve);
        virtualRegs.reserve(denseReserve);
        concreteRegs.reserve(denseReserve);

        std::vector<SmallVector<uint32_t, 4>> useVirtualIndices(state.instructionCount);
        std::vector<SmallVector<uint32_t, 4>> defVirtualIndices(state.instructionCount);
        std::vector<SmallVector<uint32_t, 4>> useConcreteIndices(state.instructionCount);
        std::vector<SmallVector<uint32_t, 4>> defConcreteIndices(state.instructionCount);

        for (uint32_t idx = 0; idx < state.instructionCount; ++idx)
        {
            const MicroInstrUseDef& useDef = state.instructionUseDefs[idx];
            auto&                   usesV  = useVirtualIndices[idx];
            auto&                   defsV  = defVirtualIndices[idx];
            auto&                   usesC  = useConcreteIndices[idx];
            auto&                   defsC  = defConcreteIndices[idx];

            for (const MicroReg reg : useDef.uses)
            {
                if (reg.isVirtual())
                {
                    const uint32_t regIndex = ensureDenseRegIndex(denseVirtual, virtualRegs, reg);
                    usesV.push_back(regIndex);
                }
                else if (reg.isInt() || reg.isFloat())
                {
                    const uint32_t regIndex = ensureDenseRegIndex(denseConcrete, concreteRegs, reg);
                    usesC.push_back(regIndex);
                }
            }

            for (const MicroReg reg : useDef.defs)
            {
                if (reg.isVirtual())
                {
                    const uint32_t regIndex = ensureDenseRegIndex(denseVirtual, virtualRegs, reg);
                    defsV.push_back(regIndex);
                }
                else if (reg.isInt() || reg.isFloat())
                {
                    const uint32_t regIndex = ensureDenseRegIndex(denseConcrete, concreteRegs, reg);
                    defsC.push_back(regIndex);
                }
            }

            if (useDef.isCall)
            {
                const CallConv& callConv = CallConv::get(useDef.callConv);
                for (const MicroReg reg : callConv.intTransientRegs)
                {
                    const uint32_t regIndex = ensureDenseRegIndex(denseConcrete, concreteRegs, reg);
                    defsC.push_back(regIndex);
                }
                for (const MicroReg reg : callConv.floatTransientRegs)
                {
                    const uint32_t regIndex = ensureDenseRegIndex(denseConcrete, concreteRegs, reg);
                    defsC.push_back(regIndex);
                }
            }
        }

        const uint32_t virtualWordCount  = static_cast<uint32_t>((virtualRegs.size() + 63ull) / 64ull);
        const uint32_t concreteWordCount = static_cast<uint32_t>((concreteRegs.size() + 63ull) / 64ull);

        std::vector<uint64_t> liveInVirtualBits(static_cast<size_t>(state.instructionCount) * virtualWordCount, 0);
        std::vector<uint64_t> liveInConcreteBits(static_cast<size_t>(state.instructionCount) * concreteWordCount, 0);

        std::vector<SmallVector<uint32_t>> predecessors(state.instructionCount);
        for (uint32_t idx = 0; idx < state.instructionCount; ++idx)
        {
            const SmallVector<uint32_t>& successors = controlFlowGraph.successors(idx);
            for (const uint32_t succIdx : successors)
            {
                if (succIdx >= state.instructionCount)
                    continue;
                predecessors[succIdx].push_back(idx);
            }
        }

        std::vector<uint32_t> worklist;
        worklist.reserve(state.instructionCount);
        std::vector<uint8_t> inWorklist(state.instructionCount, 0);
        for (uint32_t idx = 0; idx < state.instructionCount; ++idx)
        {
            worklist.push_back(idx);
            inWorklist[idx] = 1;
        }

        std::vector<uint64_t> tempOutVirtual(virtualWordCount, 0);
        std::vector<uint64_t> tempInVirtual(virtualWordCount, 0);
        std::vector<uint64_t> tempOutConcrete(concreteWordCount, 0);
        std::vector<uint64_t> tempInConcrete(concreteWordCount, 0);

        while (!worklist.empty())
        {
            const uint32_t instructionIndex = worklist.back();
            worklist.pop_back();
            inWorklist[instructionIndex] = 0;

            for (uint64_t& value : tempOutVirtual)
                value = 0;
            for (uint64_t& value : tempOutConcrete)
                value = 0;

            const SmallVector<uint32_t>& successors = controlFlowGraph.successors(instructionIndex);
            for (const uint32_t succIdx : successors)
            {
                if (succIdx >= state.instructionCount)
                    continue;

                const std::span<const uint64_t> succInVirtual  = denseBitRow(liveInVirtualBits, succIdx, virtualWordCount);
                const std::span<const uint64_t> succInConcrete = denseBitRow(liveInConcreteBits, succIdx, concreteWordCount);
                for (size_t word = 0; word < tempOutVirtual.size(); ++word)
                    tempOutVirtual[word] |= succInVirtual[word];
                for (size_t word = 0; word < tempOutConcrete.size(); ++word)
                    tempOutConcrete[word] |= succInConcrete[word];
            }

            tempInVirtual  = tempOutVirtual;
            tempInConcrete = tempOutConcrete;
            {
                std::span<uint64_t> inVirtual = tempInVirtual;
                for (const uint32_t bitIndex : defVirtualIndices[instructionIndex])
                    denseBitClear(inVirtual, bitIndex);
                for (const uint32_t bitIndex : useVirtualIndices[instructionIndex])
                    denseBitSet(inVirtual, bitIndex);
            }
            {
                std::span<uint64_t> inConcrete = tempInConcrete;
                for (const uint32_t bitIndex : defConcreteIndices[instructionIndex])
                    denseBitClear(inConcrete, bitIndex);
                for (const uint32_t bitIndex : useConcreteIndices[instructionIndex])
                    denseBitSet(inConcrete, bitIndex);
            }

            const bool changedVirtual  = copyDenseRowIfChanged(denseBitRow(liveInVirtualBits, instructionIndex, virtualWordCount), tempInVirtual);
            const bool changedConcrete = copyDenseRowIfChanged(denseBitRow(liveInConcreteBits, instructionIndex, concreteWordCount), tempInConcrete);
            if (!changedVirtual && !changedConcrete)
                continue;

            for (const uint32_t predIdx : predecessors[instructionIndex])
            {
                if (inWorklist[predIdx])
                    continue;

                worklist.push_back(predIdx);
                inWorklist[predIdx] = 1;
            }
        }

        for (uint32_t idx = 0; idx < state.instructionCount; ++idx)
        {
            for (uint64_t& value : tempOutVirtual)
                value = 0;
            for (uint64_t& value : tempOutConcrete)
                value = 0;

            const SmallVector<uint32_t>& successors = controlFlowGraph.successors(idx);
            for (const uint32_t succIdx : successors)
            {
                if (succIdx >= state.instructionCount)
                    continue;

                const std::span<const uint64_t> succInVirtual  = denseBitRow(liveInVirtualBits, succIdx, virtualWordCount);
                const std::span<const uint64_t> succInConcrete = denseBitRow(liveInConcreteBits, succIdx, concreteWordCount);
                for (size_t word = 0; word < tempOutVirtual.size(); ++word)
                    tempOutVirtual[word] |= succInVirtual[word];
                for (size_t word = 0; word < tempOutConcrete.size(); ++word)
                    tempOutConcrete[word] |= succInConcrete[word];
            }

            auto& outVirtual = state.liveOut[idx];
            outVirtual.clear();
            outVirtual.reserve(denseBitCount(tempOutVirtual));
            for (size_t wordIndex = 0; wordIndex < tempOutVirtual.size(); ++wordIndex)
            {
                uint64_t wordBits = tempOutVirtual[wordIndex];
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

            auto& outConcrete = state.concreteLiveOut[idx];
            outConcrete.clear();
            outConcrete.reserve(denseBitCount(tempOutConcrete));
            for (size_t wordIndex = 0; wordIndex < tempOutConcrete.size(); ++wordIndex)
            {
                uint64_t wordBits = tempOutConcrete[wordIndex];
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

            if (!state.instructionUseDefs[idx].isCall)
                continue;

            for (const MicroReg key : outVirtual)
                state.vregsLiveAcrossCall.insert(key);
        }
    }

    void setupPools(const PassState& state)
    {
        // Build free lists split by class (int/float) and persistence (transient/persistent).
        state.intPersistentSet.clear();
        state.floatPersistentSet.clear();
        state.intPersistentSet.reserve(state.conv->intPersistentRegs.size() * 2 + 8);
        state.floatPersistentSet.reserve(state.conv->floatPersistentRegs.size() * 2 + 8);

        for (const auto reg : state.conv->intPersistentRegs)
            state.intPersistentSet.insert(reg);

        for (const auto reg : state.conv->floatPersistentRegs)
            state.floatPersistentSet.insert(reg);

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

            if (state.intPersistentSet.contains(reg))
                state.freeIntPersistent.push_back(reg);
            else
                state.freeIntTransient.push_back(reg);
        }

        for (const auto reg : state.conv->floatRegs)
        {
            if (state.floatPersistentSet.contains(reg))
                state.freeFloatPersistent.push_back(reg);
            else
                state.freeFloatTransient.push_back(reg);
        }
    }

    void ensureSpillSlot(const PassState& state, VRegState& regState, bool isFloat)
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

    bool isCandidateBetter(const PassState& state, MicroReg candidateKey, MicroReg candidateReg, MicroReg currentBestKey, MicroReg currentBestReg, uint32_t instructionIndex, uint32_t stamp)
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

        return candidateKey.hash() > currentBestKey.hash();
    }

    bool selectEvictionCandidate(const PassState&          state,
                                 MicroReg                  requestVirtKey,
                                 uint32_t                  instructionIndex,
                                 bool                      isFloatReg,
                                 bool                      fromPersistentPool,
                                 std::span<const MicroReg> protectedKeys,
                                 uint32_t                  stamp,
                                 bool                      allowConcreteLive,
                                 MicroReg&                 outVirtKey,
                                 MicroReg&                 outPhys)
    {
        // Choose mapped virtual reg that is cheapest to evict under current constraints.
        outVirtKey = MicroReg::invalid();
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

    FreePools pickFreePools(const PassState& state, const AllocRequest& request)
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

    bool tryTakeFreePhysical(const PassState&    state,
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

    void unmapVirtReg(const PassState& state, MicroReg virtKey)
    {
        const auto mapIt = state.mapping.find(virtKey);
        if (mapIt == state.mapping.end())
            return;

        state.mapping.erase(mapIt);

        const auto stateIt = state.states.find(virtKey);
        if (stateIt != state.states.end())
            stateIt->second.mapped = false;
    }

    void mapVirtReg(const PassState& state, MicroReg virtKey, MicroReg physReg)
    {
        state.mapping[virtKey] = physReg;

        auto& regState  = state.states[virtKey];
        regState.mapped = true;
        regState.phys   = physReg;
    }

    bool selectEvictionCandidateWithFallback(const PassState&          state,
                                             MicroReg                  requestVirtKey,
                                             uint32_t                  instructionIndex,
                                             bool                      isFloatReg,
                                             bool                      preferPersistentPool,
                                             std::span<const MicroReg> protectedKeys,
                                             uint32_t                  stamp,
                                             bool                      allowConcreteLive,
                                             MicroReg&                 outVirtKey,
                                             MicroReg&                 outPhys)
    {
        if (selectEvictionCandidate(state, requestVirtKey, instructionIndex, isFloatReg, preferPersistentPool, protectedKeys, stamp, allowConcreteLive, outVirtKey, outPhys))
            return true;

        return selectEvictionCandidate(state, requestVirtKey, instructionIndex, isFloatReg, !preferPersistentPool, protectedKeys, stamp, allowConcreteLive, outVirtKey, outPhys);
    }

    MicroReg allocatePhysical(const PassState&            state,
                              const AllocRequest&         request,
                              std::span<const MicroReg>   protectedKeys,
                              uint32_t                    stamp,
                              int64_t                     stackDepth,
                              std::vector<PendingInsert>& pending)
    {
        // Prefer free registers; otherwise evict one candidate and spill if needed.
        MicroReg physReg;
        if (tryTakeFreePhysical(state, request, stamp, false, physReg))
            return physReg;

        MicroReg victimKey = MicroReg::invalid();
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
                           std::span<const MicroReg>   protectedKeys,
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

    void spillCallLiveOut(const PassState& state, uint32_t stamp, int64_t stackDepth, std::vector<PendingInsert>& pending)
    {
        // Calls may clobber transient regs; force spill of vulnerable live values before call.
        for (auto it = state.mapping.begin(); it != state.mapping.end();)
        {
            const MicroReg virtKey = it->first;
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

    void flushAllMappedVirtuals(const PassState& state, int64_t stackDepth, std::vector<PendingInsert>& pending)
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

    void clearAllMappedVirtuals(const PassState& state)
    {
        for (const auto& [virtKey, physReg] : state.mapping)
        {
            auto& regState  = state.states[virtKey];
            regState.mapped = false;
            returnToFreePool(state, physReg);
        }

        state.mapping.clear();
    }

    void expireDeadMappings(const PassState& state, uint32_t stamp)
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
            const bool          isCall         = state.instructionUseDefs[idx].isCall;
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

    std::vector<MicroInstrUseDef> instructionUseDefs;

    // Order matters: liveness/use analysis informs allocation, then we patch IR and finalize frame.
    PassState state = {
        context_,
        conv_,
        instructions_,
        operands_,
        instructionCount_,
        spillFrameUsed_,
        hasControlFlow_,
        liveOut_,
        concreteLiveOut_,
        vregsLiveAcrossCall_,
        usePositions_,
        instructionUseDefs,
        intPersistentSet_,
        floatPersistentSet_,
        freeIntTransient_,
        freeIntPersistent_,
        freeFloatTransient_,
        freeFloatPersistent_,
        states_,
        mapping_,
        liveStamp_,
        concreteLiveStamp_,
        callSpillVregs_,
    };
    initState(state, context);

    if (!state.instructionCount)
        return Result::Continue;

    const bool hadVirtualRegisters = prepareInstructionData(state);

    analyzeLiveness(state);
    setupPools(state);
    rewriteInstructions(state);
    insertSpillFrame(state);

    context.passChanged = hadVirtualRegisters || state.spillFrameUsed != 0;
    return Result::Continue;
}

SWC_END_NAMESPACE();
