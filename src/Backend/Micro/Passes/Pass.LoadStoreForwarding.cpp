#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroInstrInfo.h"

// Forwards recent store values into matching following loads.
// Example: store [rbp+8], r1; load r2, [rbp+8] -> mov r2, r1.
// Example: store [rbp+8], 5;  load r2, [rbp+8] -> load r2, 5.
// This removes redundant memory traffic when aliasing is provably safe.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct StackSlotKey
    {
        MicroReg    baseReg;
        uint64_t    offset = 0;
        MicroOpBits opBits = MicroOpBits::Zero;

        bool operator==(const StackSlotKey& other) const
        {
            return baseReg == other.baseReg &&
                   offset == other.offset &&
                   opBits == other.opBits;
        }
    };

    struct StackSlotKeyHash
    {
        size_t operator()(const StackSlotKey& key) const
        {
            size_t hashValue = std::hash<uint32_t>{}(key.baseReg.packed);
            hashValue ^= std::hash<uint64_t>{}(key.offset) + 0x9e3779b97f4a7c15ull + (hashValue << 6) + (hashValue >> 2);
            hashValue ^= std::hash<uint8_t>{}(static_cast<uint8_t>(key.opBits)) + 0x9e3779b97f4a7c15ull + (hashValue << 6) + (hashValue >> 2);
            return hashValue;
        }
    };

    enum class StackSlotValueKind : uint8_t
    {
        Unknown,
        Register,
        Immediate,
    };

    struct StackSlotValue
    {
        StackSlotValueKind kind      = StackSlotValueKind::Unknown;
        MicroReg           reg       = MicroReg::invalid();
        uint64_t           immediate = 0;
    };

    using StackSlotMap = std::unordered_map<StackSlotKey, StackSlotValue, StackSlotKeyHash>;

    struct LabelPredEdge
    {
        MicroInstrRef insertionBeforeRef = MicroInstrRef::invalid();
        MicroInstrRef scanStartRef       = MicroInstrRef::invalid();
    };

    struct LabelPredInfo
    {
        std::vector<LabelPredEdge> edges;
        bool                       hasJumpPredecessor        = false;
        bool                       hasUnsupportedPredecessor = false;
    };

    bool containsDef(std::span<const MicroReg> defs, const MicroReg reg)
    {
        for (const MicroReg defReg : defs)
        {
            if (defReg == reg)
                return true;
        }

        return false;
    }

    uint32_t opBitsNumBytes(const MicroOpBits opBits)
    {
        switch (opBits)
        {
            case MicroOpBits::B8:
                return 1;
            case MicroOpBits::B16:
                return 2;
            case MicroOpBits::B32:
                return 4;
            case MicroOpBits::B64:
                return 8;
            case MicroOpBits::B128:
                return 16;
            default:
                return 0;
        }
    }

    bool rangesOverlap(const uint64_t lhsOffset, const uint32_t lhsSize, const uint64_t rhsOffset, const uint32_t rhsSize)
    {
        if (!lhsSize || !rhsSize)
            return false;

        const uint64_t lhsEnd = lhsOffset + lhsSize;
        const uint64_t rhsEnd = rhsOffset + rhsSize;
        return lhsOffset < rhsEnd && rhsOffset < lhsEnd;
    }

    bool writesMemory(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::LoadMemImm:
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
            case MicroInstrOpcode::OpUnaryMem:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::Pop:
                return true;
            default:
                return false;
        }
    }

    bool isStackBaseRegister(const MicroPassContext& context, const MicroReg reg)
    {
        const CallConv& conv = CallConv::get(context.callConvKind);
        if (reg == conv.stackPointer)
            return true;

        if (conv.framePointer.isValid() && reg == conv.framePointer)
            return true;

        if (context.encoder)
        {
            const MicroReg stackPointerReg = context.encoder->stackPointerReg();
            if (stackPointerReg.isValid() && reg == stackPointerReg)
                return true;
        }

        return false;
    }

    bool getMemAccessOpBits(MicroOpBits& outOpBits, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
                outOpBits = ops[2].opBits;
                return true;
            case MicroInstrOpcode::LoadMemReg:
                outOpBits = ops[2].opBits;
                return true;
            case MicroInstrOpcode::LoadMemImm:
                outOpBits = ops[1].opBits;
                return true;
            case MicroInstrOpcode::LoadSignedExtRegMem:
                outOpBits = ops[3].opBits;
                return true;
            case MicroInstrOpcode::LoadZeroExtRegMem:
                outOpBits = ops[3].opBits;
                return true;
            case MicroInstrOpcode::CmpMemReg:
                outOpBits = ops[2].opBits;
                return true;
            case MicroInstrOpcode::CmpMemImm:
                outOpBits = ops[1].opBits;
                return true;
            case MicroInstrOpcode::OpUnaryMem:
                outOpBits = ops[1].opBits;
                return true;
            case MicroInstrOpcode::OpBinaryRegMem:
                outOpBits = ops[2].opBits;
                return true;
            case MicroInstrOpcode::OpBinaryMemReg:
                outOpBits = ops[2].opBits;
                return true;
            case MicroInstrOpcode::OpBinaryMemImm:
                outOpBits = ops[1].opBits;
                return true;
            default:
                return false;
        }
    }

    bool getStackSlotKey(StackSlotKey& outKey, const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops)
            return false;

        uint8_t baseIndex   = 0;
        uint8_t offsetIndex = 0;
        if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, inst))
            return false;

        const MicroReg baseReg = ops[baseIndex].reg;
        if (!isStackBaseRegister(context, baseReg))
            return false;

        MicroOpBits opBits = MicroOpBits::Zero;
        if (!getMemAccessOpBits(opBits, inst, ops))
            return false;

        outKey.baseReg = baseReg;
        outKey.offset  = ops[offsetIndex].valueU64;
        outKey.opBits  = opBits;
        return true;
    }

    void invalidateOverlappingSlots(StackSlotMap& slots, const StackSlotKey& targetKey)
    {
        const uint32_t targetSize = opBitsNumBytes(targetKey.opBits);
        if (!targetSize)
        {
            slots.clear();
            return;
        }

        for (auto it = slots.begin(); it != slots.end();)
        {
            const StackSlotKey& slotKey  = it->first;
            const uint32_t      slotSize = opBitsNumBytes(slotKey.opBits);
            if (slotSize &&
                slotKey.baseReg == targetKey.baseReg &&
                rangesOverlap(slotKey.offset, slotSize, targetKey.offset, targetSize))
            {
                it = slots.erase(it);
            }
            else
            {
                ++it;
            }
        }
    }

    void invalidateSlotsUsingRegister(StackSlotMap& slots, const MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;

        for (auto it = slots.begin(); it != slots.end();)
        {
            const StackSlotValue& slotValue = it->second;
            if (slotValue.kind == StackSlotValueKind::Register && slotValue.reg == reg)
            {
                it = slots.erase(it);
            }
            else
            {
                ++it;
            }
        }
    }

    bool isUnsupportedControlFlowForEdgePromotion(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::JumpCondImm:
                return true;
            default:
                return false;
        }
    }

    bool collectLabelPredecessors(const MicroStorage&                          storage,
                                  const MicroOperandStorage&                   operands,
                                  std::vector<MicroInstrRef>&                  outRefs,
                                  std::unordered_map<uint32_t, size_t>&        outRefToIndex,
                                  std::unordered_map<uint32_t, LabelPredInfo>& outLabelPredInfo)
    {
        outRefs.clear();
        outRefToIndex.clear();
        outLabelPredInfo.clear();

        outRefs.reserve(storage.count());
        outRefToIndex.reserve(storage.count());
        outLabelPredInfo.reserve(storage.count());

        std::unordered_map<uint32_t, MicroInstrRef> labelIdToInstructionRef;
        labelIdToInstructionRef.reserve(storage.count());

        size_t index = 0;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const MicroInstrRef instRef = it.current;
            const MicroInstr&   inst    = *it;
            outRefs.push_back(instRef);
            outRefToIndex[instRef.get()] = index++;

            if (inst.op != MicroInstrOpcode::Label)
                continue;

            const MicroInstrOperand* labelOps = inst.ops(operands);
            if (!labelOps || labelOps[0].valueU64 > std::numeric_limits<uint32_t>::max())
                return false;

            const uint32_t labelId           = static_cast<uint32_t>(labelOps[0].valueU64);
            labelIdToInstructionRef[labelId] = instRef;
            outLabelPredInfo[instRef.get()];
        }

        const size_t instructionCount = outRefs.size();
        for (size_t i = 0; i < instructionCount; ++i)
        {
            const MicroInstrRef instRef = outRefs[i];
            const MicroInstr*   inst    = storage.ptr(instRef);
            if (!inst)
                return false;

            if (isUnsupportedControlFlowForEdgePromotion(*inst))
                return false;

            const bool hasNextInstruction = i + 1 < instructionCount;
            const auto addFallthroughPred = [&]() {
                if (!hasNextInstruction)
                    return;

                const MicroInstrRef nextRef  = outRefs[i + 1];
                const MicroInstr*   nextInst = storage.ptr(nextRef);
                if (!nextInst || nextInst->op != MicroInstrOpcode::Label)
                    return;

                LabelPredInfo& predInfo = outLabelPredInfo[nextRef.get()];
                predInfo.edges.push_back({
                    .insertionBeforeRef = nextRef,
                    .scanStartRef       = instRef,
                });
            };

            if (inst->op == MicroInstrOpcode::JumpCond)
            {
                const MicroInstrOperand* jumpOps = inst->ops(operands);
                if (!jumpOps || jumpOps[2].valueU64 > std::numeric_limits<uint32_t>::max())
                    return false;

                const uint32_t targetLabelId = static_cast<uint32_t>(jumpOps[2].valueU64);
                const auto     targetRefIt   = labelIdToInstructionRef.find(targetLabelId);
                if (targetRefIt == labelIdToInstructionRef.end())
                    return false;

                LabelPredInfo& predInfo = outLabelPredInfo[targetRefIt->second.get()];
                if (MicroInstrInfo::isUnconditionalJumpInstruction(*inst, jumpOps))
                {
                    predInfo.edges.push_back({
                        .insertionBeforeRef = instRef,
                        .scanStartRef       = instRef,
                    });
                    predInfo.hasJumpPredecessor = true;
                }
                else
                {
                    predInfo.hasUnsupportedPredecessor = true;
                    addFallthroughPred();
                }

                continue;
            }

            if (MicroInstrInfo::isTerminatorInstruction(*inst))
                continue;

            addFallthroughPred();
        }

        return true;
    }

    bool findReachingStoreValueForEdge(StackSlotValue&            outValue,
                                       const MicroPassContext&    context,
                                       const MicroStorage&        storage,
                                       const MicroOperandStorage& operands,
                                       const LabelPredEdge&       edge,
                                       const StackSlotKey&        targetSlot)
    {
        std::unordered_set<uint32_t> defsAfterStore;
        defsAfterStore.reserve(16);

        const uint32_t targetSize = opBitsNumBytes(targetSlot.opBits);
        if (!targetSize)
            return false;

        for (MicroInstrRef scanRef = edge.scanStartRef; scanRef.isValid(); scanRef = storage.findPreviousInstructionRef(scanRef))
        {
            const MicroInstr* scanInst = storage.ptr(scanRef);
            if (!scanInst)
                return false;

            if (scanRef != edge.scanStartRef && scanInst->op == MicroInstrOpcode::Label)
                break;

            const MicroInstrUseDef useDef = scanInst->collectUseDef(operands, context.encoder);
            for (const MicroReg defReg : useDef.defs)
            {
                if (defReg.isValid() && !defReg.isNoBase())
                    defsAfterStore.insert(defReg.packed);
            }

            if (!writesMemory(*scanInst))
                continue;

            const MicroInstrOperand* scanOps = scanInst->ops(operands);
            if (!scanOps)
                return false;

            StackSlotKey writtenSlot;
            if (!getStackSlotKey(writtenSlot, context, *scanInst, scanOps))
                return false;

            if (writtenSlot.baseReg != targetSlot.baseReg)
                continue;

            const uint32_t writtenSize = opBitsNumBytes(writtenSlot.opBits);
            if (!rangesOverlap(writtenSlot.offset, writtenSize, targetSlot.offset, targetSize))
                continue;

            if (!(writtenSlot == targetSlot))
                return false;

            if (scanInst->op == MicroInstrOpcode::LoadMemReg)
            {
                const MicroReg srcReg = scanOps[1].reg;
                if (!srcReg.isValid() || srcReg.isNoBase())
                    return false;
                if (defsAfterStore.contains(srcReg.packed))
                    return false;

                outValue.kind = StackSlotValueKind::Register;
                outValue.reg  = srcReg;
                return true;
            }

            if (scanInst->op == MicroInstrOpcode::LoadMemImm)
            {
                outValue.kind      = StackSlotValueKind::Immediate;
                outValue.immediate = scanOps[3].valueU64;
                return true;
            }

            return false;
        }

        return false;
    }

    void insertEdgeAssignment(const StackSlotValue& value,
                              const StackSlotKey&   slotKey,
                              const MicroReg        dstReg,
                              MicroStorage&         storage,
                              MicroOperandStorage&  operands,
                              const LabelPredEdge&  edge)
    {
        if (value.kind == StackSlotValueKind::Register)
        {
            if (value.reg == dstReg)
                return;

            std::array<MicroInstrOperand, 3> newOps{};
            newOps[0].reg    = dstReg;
            newOps[1].reg    = value.reg;
            newOps[2].opBits = slotKey.opBits;
            storage.insertBefore(operands, edge.insertionBeforeRef, MicroInstrOpcode::LoadRegReg, newOps);
            return;
        }

        if (value.kind == StackSlotValueKind::Immediate)
        {
            std::array<MicroInstrOperand, 3> newOps{};
            newOps[0].reg      = dstReg;
            newOps[1].opBits   = slotKey.opBits;
            newOps[2].valueU64 = value.immediate;
            storage.insertBefore(operands, edge.insertionBeforeRef, MicroInstrOpcode::LoadRegImm, newOps);
            return;
        }
    }

    bool promoteLoopHeaderStackLoads(const MicroPassContext& context)
    {
        SWC_ASSERT(context.instructions != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        MicroStorage&        storage  = *SWC_NOT_NULL(context.instructions);
        MicroOperandStorage& operands = *SWC_NOT_NULL(context.operands);

        std::vector<MicroInstrRef>                  refs;
        std::unordered_map<uint32_t, size_t>        refToIndex;
        std::unordered_map<uint32_t, LabelPredInfo> labelPredInfo;
        if (!collectLabelPredecessors(storage, operands, refs, refToIndex, labelPredInfo))
            return false;

        bool changed = false;
        for (const MicroInstrRef labelRef : refs)
        {
            const MicroInstr* labelInst = storage.ptr(labelRef);
            if (!labelInst || labelInst->op != MicroInstrOpcode::Label)
                continue;

            const auto predInfoIt = labelPredInfo.find(labelRef.get());
            if (predInfoIt == labelPredInfo.end())
                continue;

            const LabelPredInfo& predInfo = predInfoIt->second;
            if (predInfo.edges.empty() || !predInfo.hasJumpPredecessor || predInfo.hasUnsupportedPredecessor)
                continue;

            const auto labelIndexIt = refToIndex.find(labelRef.get());
            if (labelIndexIt == refToIndex.end())
                continue;

            for (size_t i = labelIndexIt->second + 1; i < refs.size(); ++i)
            {
                const MicroInstrRef candidateRef = refs[i];
                MicroInstr*         candidate    = storage.ptr(candidateRef);
                if (!candidate)
                    continue;
                if (candidate->op == MicroInstrOpcode::Label)
                    break;
                if (candidate->op != MicroInstrOpcode::LoadRegMem)
                    break;

                const MicroInstrOperand* candidateOps = candidate->ops(operands);
                if (!candidateOps)
                    break;

                StackSlotKey slotKey;
                if (!getStackSlotKey(slotKey, context, *candidate, candidateOps))
                    break;

                const MicroReg              dstReg = candidateOps[0].reg;
                std::vector<StackSlotValue> edgeValues;
                edgeValues.reserve(predInfo.edges.size());

                bool canPromote = true;
                for (const LabelPredEdge& edge : predInfo.edges)
                {
                    StackSlotValue value;
                    if (!findReachingStoreValueForEdge(value, context, storage, operands, edge, slotKey))
                    {
                        canPromote = false;
                        break;
                    }

                    if (value.kind == StackSlotValueKind::Register)
                    {
                        if (!value.reg.isValid() || !dstReg.isSameClass(value.reg))
                        {
                            canPromote = false;
                            break;
                        }
                    }
                    else if (value.kind == StackSlotValueKind::Immediate)
                    {
                        if (!dstReg.isInt() || getNumBits(slotKey.opBits) > 64)
                        {
                            canPromote = false;
                            break;
                        }
                    }
                    else
                    {
                        canPromote = false;
                        break;
                    }

                    edgeValues.push_back(value);
                }

                if (!canPromote)
                    continue;

                for (size_t edgeIndex = 0; edgeIndex < predInfo.edges.size(); ++edgeIndex)
                    insertEdgeAssignment(edgeValues[edgeIndex], slotKey, dstReg, storage, operands, predInfo.edges[edgeIndex]);

                storage.erase(candidateRef);
                changed = true;
            }
        }

        return changed;
    }

    bool isSameMemoryAddress(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps)
    {
        return storeOps[0].reg == loadOps[1].reg &&
               storeOps[3].valueU64 == loadOps[3].valueU64 &&
               storeOps[2].opBits == loadOps[2].opBits;
    }

    bool isSameMemoryAddressForImmediateStore(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps)
    {
        return storeOps[0].reg == loadOps[1].reg &&
               storeOps[2].valueU64 == loadOps[3].valueU64 &&
               storeOps[1].opBits == loadOps[2].opBits;
    }

    bool canCrossInstruction(const MicroPassContext& context, const MicroInstr& store, const MicroInstrOperand* storeOps, const MicroInstr& scanInst)
    {
        const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
        if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
            return false;
        if (writesMemory(scanInst))
            return false;

        const MicroReg storeBaseReg = storeOps[0].reg;
        if (containsDef(useDef.defs, storeBaseReg))
            return false;

        if (store.op == MicroInstrOpcode::LoadMemReg)
        {
            const MicroReg storeValueReg = storeOps[1].reg;
            if (containsDef(useDef.defs, storeValueReg))
                return false;
        }

        return true;
    }

    bool promoteStackSlotLoads(const MicroPassContext& context)
    {
        SWC_ASSERT(context.instructions != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        bool                 changed  = false;
        MicroStorage&        storage  = *SWC_NOT_NULL(context.instructions);
        MicroOperandStorage& operands = *SWC_NOT_NULL(context.operands);
        StackSlotMap         slotValues;

        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            MicroInstr&        inst = *it;
            MicroInstrOperand* ops  = inst.ops(operands);
            if (!ops)
            {
                slotValues.clear();
                continue;
            }

            const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
            if (MicroInstrInfo::isLocalDataflowBarrier(inst, useDef))
            {
                slotValues.clear();
                continue;
            }

            if (inst.op == MicroInstrOpcode::LoadRegMem)
            {
                StackSlotKey slotKey;
                if (getStackSlotKey(slotKey, context, inst, ops))
                {
                    const auto valueIt = slotValues.find(slotKey);
                    if (valueIt != slotValues.end())
                    {
                        const StackSlotValue& slotValue = valueIt->second;
                        if (slotValue.kind == StackSlotValueKind::Register &&
                            slotValue.reg.isValid() &&
                            ops[0].reg.isSameClass(slotValue.reg))
                        {
                            inst.op          = MicroInstrOpcode::LoadRegReg;
                            inst.numOperands = 3;
                            ops[1].reg       = slotValue.reg;
                            ops[2].opBits    = slotKey.opBits;
                            changed          = true;
                        }
                        else if (slotValue.kind == StackSlotValueKind::Immediate &&
                                 ops[0].reg.isInt() &&
                                 getNumBits(slotKey.opBits) <= 64)
                        {
                            inst.op          = MicroInstrOpcode::LoadRegImm;
                            inst.numOperands = 3;
                            ops[1].opBits    = slotKey.opBits;
                            ops[2].valueU64  = slotValue.immediate;
                            changed          = true;
                        }
                    }
                }
            }

            bool clearAllSlots = false;
            for (const MicroReg defReg : useDef.defs)
            {
                if (isStackBaseRegister(context, defReg))
                {
                    clearAllSlots = true;
                    break;
                }
            }

            if (clearAllSlots)
            {
                slotValues.clear();
            }
            else
            {
                for (const MicroReg defReg : useDef.defs)
                    invalidateSlotsUsingRegister(slotValues, defReg);
            }

            if (!writesMemory(inst))
                continue;

            StackSlotKey slotKey;
            if (!getStackSlotKey(slotKey, context, inst, ops))
            {
                slotValues.clear();
                continue;
            }

            invalidateOverlappingSlots(slotValues, slotKey);

            if (inst.op == MicroInstrOpcode::LoadMemReg)
            {
                StackSlotValue slotValue;
                slotValue.kind      = StackSlotValueKind::Register;
                slotValue.reg       = ops[1].reg;
                slotValues[slotKey] = slotValue;
            }
            else if (inst.op == MicroInstrOpcode::LoadMemImm)
            {
                StackSlotValue slotValue;
                slotValue.kind      = StackSlotValueKind::Immediate;
                slotValue.immediate = ops[3].valueU64;
                slotValues[slotKey] = slotValue;
            }
        }

        return changed;
    }
}

Result MicroLoadStoreForwardingPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                 changed  = false;
    MicroStorage&        storage  = *SWC_NOT_NULL(context.instructions);
    MicroOperandStorage& operands = *SWC_NOT_NULL(context.operands);

    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const MicroInstr& first = *it;
        if (first.op != MicroInstrOpcode::LoadMemReg && first.op != MicroInstrOpcode::LoadMemImm)
            continue;

        const MicroInstrOperand* firstOps = first.ops(operands);
        if (!firstOps)
            continue;

        for (auto scanIt = std::next(it); scanIt != storage.view().end(); ++scanIt)
        {
            MicroInstr& scanInst = *scanIt;
            if (scanInst.op == MicroInstrOpcode::LoadRegMem)
            {
                MicroInstrOperand* scanOps = scanInst.ops(operands);
                if (!scanOps)
                    break;

                if (first.op == MicroInstrOpcode::LoadMemReg && isSameMemoryAddress(firstOps, scanOps))
                {
                    scanInst.op          = MicroInstrOpcode::LoadRegReg;
                    scanInst.numOperands = 3;
                    scanOps[1].reg       = firstOps[1].reg;
                    scanOps[2].opBits    = firstOps[2].opBits;
                    changed              = true;
                    break;
                }

                if (first.op == MicroInstrOpcode::LoadMemImm &&
                    scanOps[0].reg.isInt() &&
                    isSameMemoryAddressForImmediateStore(firstOps, scanOps))
                {
                    scanInst.op          = MicroInstrOpcode::LoadRegImm;
                    scanInst.numOperands = 3;
                    scanOps[1].opBits    = firstOps[1].opBits;
                    scanOps[2].valueU64  = firstOps[3].valueU64;
                    changed              = true;
                    break;
                }
            }

            if (!canCrossInstruction(context, first, firstOps, scanInst))
                break;
        }
    }

    if (promoteStackSlotLoads(context))
        changed = true;

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
