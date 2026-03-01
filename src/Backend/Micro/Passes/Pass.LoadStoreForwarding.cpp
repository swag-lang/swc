#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"

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

        auto opBits = MicroOpBits::Zero;
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

        for (auto& inst : storage.view())
        {
            MicroInstrOperand* ops = inst.ops(operands);
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
