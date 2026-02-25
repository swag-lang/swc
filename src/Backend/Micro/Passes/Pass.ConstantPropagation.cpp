#include "pch.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"

// Propagates known integer constants through register operations.
// Example: load r1, 5; add r2, r1  ->  add r2, 5.
// Example: load r1, 5; shl r1, 1    ->  load r1, 10.
// This removes dynamic work and creates simpler instruction forms.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct KnownConstant
    {
        uint64_t value = 0;
    };

    struct KnownConstantPointer
    {
        uint64_t pointer = 0;
        uint64_t offset  = 0;
    };

    struct StackSlotKey
    {
        uint64_t    offset = 0;
        MicroOpBits opBits = MicroOpBits::Zero;

        bool operator==(const StackSlotKey&) const = default;
    };

    struct StackSlotKeyHash
    {
        size_t operator()(const StackSlotKey& key) const
        {
            size_t hash = std::hash<uint64_t>{}(key.offset);
            hash ^= std::hash<uint32_t>{}(static_cast<uint32_t>(key.opBits) + 0x9e3779b9u);
            return hash;
        }
    };

    using KnownRegMap             = std::unordered_map<uint32_t, KnownConstant>;
    using KnownStackSlotMap       = std::unordered_map<StackSlotKey, KnownConstant, StackSlotKeyHash>;
    using KnownAddressMap         = std::unordered_map<uint32_t, uint64_t>;
    using KnownConstantPointerMap = std::unordered_map<uint32_t, KnownConstantPointer>;

    uint32_t opBitsNumBytes(MicroOpBits opBits)
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

    bool rangesOverlap(uint64_t lhsOffset, uint32_t lhsSize, uint64_t rhsOffset, uint32_t rhsSize)
    {
        if (!lhsSize || !rhsSize)
            return false;

        const uint64_t lhsEnd = lhsOffset + lhsSize;
        const uint64_t rhsEnd = rhsOffset + rhsSize;
        return lhsOffset < rhsEnd && rhsOffset < lhsEnd;
    }

    void eraseOverlappingStackSlots(KnownStackSlotMap& knownSlots, uint64_t offset, MicroOpBits opBits)
    {
        const uint32_t slotSize = opBitsNumBytes(opBits);
        if (!slotSize)
        {
            knownSlots.clear();
            return;
        }

        for (auto it = knownSlots.begin(); it != knownSlots.end();)
        {
            const uint32_t knownSize = opBitsNumBytes(it->first.opBits);
            if (rangesOverlap(offset, slotSize, it->first.offset, knownSize))
                it = knownSlots.erase(it);
            else
                ++it;
        }
    }

    void setKnownStackSlot(KnownStackSlotMap& knownSlots, uint64_t offset, MicroOpBits opBits, uint64_t value)
    {
        eraseOverlappingStackSlots(knownSlots, offset, opBits);
        knownSlots[{.offset = offset, .opBits = opBits}] = {
            .value = MicroOptimization::normalizeToOpBits(value, opBits),
        };
    }

    bool tryGetKnownStackSlotValue(uint64_t& outValue, const KnownStackSlotMap& knownSlots, uint64_t offset, MicroOpBits opBits)
    {
        const auto it = knownSlots.find({.offset = offset, .opBits = opBits});
        if (it != knownSlots.end())
        {
            outValue = it->second.value;
            return true;
        }

        const uint32_t wantedSize = opBitsNumBytes(opBits);
        if (!wantedSize || wantedSize > sizeof(uint64_t))
            return false;

        for (const auto& [knownKey, knownValue] : knownSlots)
        {
            const uint32_t knownSize = opBitsNumBytes(knownKey.opBits);
            if (!knownSize || knownSize > sizeof(uint64_t))
                continue;

            if (knownKey.offset > offset)
                continue;

            const uint64_t knownEnd  = knownKey.offset + knownSize;
            const uint64_t wantedEnd = offset + wantedSize;
            if (wantedEnd > knownEnd)
                continue;

            const uint64_t shiftBytes = offset - knownKey.offset;
            const uint64_t shifted    = knownValue.value >> (shiftBytes * 8);
            outValue                  = MicroOptimization::normalizeToOpBits(shifted, opBits);
            return true;
        }

        return false;
    }

    bool tryResolveStackOffset(uint64_t& outOffset, const KnownAddressMap& knownAddresses, MicroReg stackPointerReg, MicroReg baseReg, uint64_t baseOffset)
    {
        if (baseReg == stackPointerReg)
        {
            outOffset = baseOffset;
            return true;
        }

        const auto itAddress = knownAddresses.find(baseReg.packed);
        if (itAddress == knownAddresses.end())
            return false;

        outOffset = itAddress->second + baseOffset;
        return true;
    }

    bool tryResolveStackOffsetForAmc(uint64_t&              outOffset,
                                     const KnownAddressMap& knownAddresses,
                                     const KnownRegMap&     known,
                                     MicroReg               stackPointerReg,
                                     MicroReg               baseReg,
                                     MicroReg               mulReg,
                                     uint64_t               mulValue,
                                     uint64_t               addValue)
    {
        uint64_t baseOffset = 0;
        if (!tryResolveStackOffset(baseOffset, knownAddresses, stackPointerReg, baseReg, 0))
            return false;

        const auto itKnownMul = known.find(mulReg.packed);
        if (itKnownMul == known.end())
            return false;

        const uint64_t mulInput = itKnownMul->second.value;
        if (mulValue && mulInput > (std::numeric_limits<uint64_t>::max() - addValue) / mulValue)
            return false;

        const uint64_t mulAddOffset = mulInput * mulValue + addValue;
        if (baseOffset > std::numeric_limits<uint64_t>::max() - mulAddOffset)
            return false;

        outOffset = baseOffset + mulAddOffset;
        return true;
    }

    bool callHasStackAddressArgument(const KnownAddressMap& knownAddresses, CallConvKind callConvKind)
    {
        const CallConv& callConv = CallConv::get(callConvKind);
        for (const MicroReg argReg : callConv.intArgRegs)
        {
            if (knownAddresses.contains(argReg.packed))
                return true;
        }

        return false;
    }

    bool tryRewriteMemoryBaseToStack(const MicroPassContext& context, const MicroInstr& inst, MicroInstrOperand* ops, MicroReg stackPointerReg, const KnownAddressMap& knownAddresses)
    {
        if (!ops || !stackPointerReg.isValid())
            return false;

        uint8_t memBaseIndex   = 0;
        uint8_t memOffsetIndex = 0;
        if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(memBaseIndex, memOffsetIndex, inst))
            return false;

        const MicroReg baseReg = ops[memBaseIndex].reg;
        if (!baseReg.isInt() || baseReg == stackPointerReg)
            return false;

        uint64_t stackOffset = 0;
        if (!tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, baseReg, ops[memOffsetIndex].valueU64))
            return false;

        const MicroReg originalBase   = ops[memBaseIndex].reg;
        const uint64_t originalOffset = ops[memOffsetIndex].valueU64;
        ops[memBaseIndex].reg         = stackPointerReg;
        ops[memOffsetIndex].valueU64  = stackOffset;
        if (MicroOptimization::violatesEncoderConformance(context, inst, ops))
        {
            ops[memBaseIndex].reg        = originalBase;
            ops[memOffsetIndex].valueU64 = originalOffset;
            return false;
        }

        return true;
    }

    bool definesRegister(std::span<const MicroReg> defs, MicroReg reg)
    {
        for (const MicroReg defReg : defs)
        {
            if (defReg == reg)
                return true;
        }

        return false;
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

    void eraseKnownDefs(KnownRegMap& known, std::span<const MicroReg> defs)
    {
        for (const MicroReg reg : defs)
        {
            known.erase(reg.packed);
        }
    }

    void eraseKnownAddressDefs(KnownAddressMap& knownAddresses, std::span<const MicroReg> defs)
    {
        for (const MicroReg reg : defs)
        {
            knownAddresses.erase(reg.packed);
        }
    }

    void eraseKnownConstantPointerDefs(KnownConstantPointerMap& knownConstantPointers, std::span<const MicroReg> defs)
    {
        for (const MicroReg reg : defs)
            knownConstantPointers.erase(reg.packed);
    }

    bool tryGetPointerBytesRange(std::array<std::byte, 16>& outBytes, uint32_t numBytes, uint64_t pointer, uint64_t offset)
    {
        if (!numBytes || numBytes > outBytes.size())
            return false;
        if (!pointer)
            return false;
        if (pointer > std::numeric_limits<uint64_t>::max() - offset)
            return false;

        const uint64_t byteAddress = pointer + offset;
        std::memcpy(outBytes.data(), reinterpret_cast<const void*>(byteAddress), numBytes);
        return true;
    }

    void setKnownStackSlotsFromBytes(KnownStackSlotMap& knownSlots, uint64_t baseOffset, std::span<const std::byte> bytes)
    {
        uint64_t byteOffset = 0;
        while (byteOffset < bytes.size())
        {
            const uint32_t remaining = static_cast<uint32_t>(bytes.size() - byteOffset);

            uint32_t chunkSize = 1;
            if (remaining >= 8)
                chunkSize = 8;
            else if (remaining >= 4)
                chunkSize = 4;
            else if (remaining >= 2)
                chunkSize = 2;

            const MicroOpBits chunkBits = microOpBitsFromChunkSize(chunkSize);
            if (chunkBits == MicroOpBits::Zero)
                return;

            uint64_t chunkValue = 0;
            std::memcpy(&chunkValue, bytes.data() + byteOffset, chunkSize);
            setKnownStackSlot(knownSlots, baseOffset + byteOffset, chunkBits, chunkValue);
            byteOffset += chunkSize;
        }
    }

    uint64_t signExtendToBits(uint64_t value, MicroOpBits srcBits, MicroOpBits dstBits)
    {
        const uint64_t normalizedSrc = MicroOptimization::normalizeToOpBits(value, srcBits);

        switch (srcBits)
        {
            case MicroOpBits::B8:
                return MicroOptimization::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int8_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B16:
                return MicroOptimization::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int16_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B32:
                return MicroOptimization::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B64:
                return MicroOptimization::normalizeToOpBits(normalizedSrc, dstBits);
            default:
                return MicroOptimization::normalizeToOpBits(normalizedSrc, dstBits);
        }
    }
}

Result MicroConstantPropagationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                    changed = false;
    KnownRegMap             known;
    KnownStackSlotMap       knownStackSlots;
    KnownAddressMap         knownAddresses;
    KnownConstantPointerMap knownConstantPointers;
    known.reserve(64);
    knownStackSlots.reserve(64);
    knownAddresses.reserve(32);
    knownConstantPointers.reserve(32);

    MicroReg stackPointerReg = CallConv::get(context.callConvKind).stackPointer;
    if (context.encoder)
        stackPointerReg = context.encoder->stackPointerReg();

    MicroStorage&        storage  = *SWC_NOT_NULL(context.instructions);
    MicroOperandStorage& operands = *SWC_NOT_NULL(context.operands);
    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const Ref          instRef = it.current;
        MicroInstr&        inst    = *it;
        MicroInstrOperand* ops     = inst.ops(operands);

        if (tryRewriteMemoryBaseToStack(context, inst, ops, stackPointerReg, knownAddresses))
            changed = true;

        if (inst.op == MicroInstrOpcode::LoadAmcRegMem &&
            stackPointerReg.isValid() &&
            ops[0].reg.isInt() &&
            ops[1].reg.isInt() &&
            ops[2].reg.isInt())
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetForAmc(stackOffset,
                                            knownAddresses,
                                            known,
                                            stackPointerReg,
                                            ops[1].reg,
                                            ops[2].reg,
                                            ops[5].valueU64,
                                            ops[6].valueU64))
            {
                const MicroInstrOpcode originalOp = inst.op;
                const std::array       originalOps{ops[0], ops[1], ops[2], ops[3], ops[4], ops[5], ops[6], ops[7]};
                bool                   rewritten = false;

                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[4].opBits))
                {
                    inst.op          = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands = 3;
                    ops[1].opBits    = ops[3].opBits;
                    ops[2].valueU64  = MicroOptimization::normalizeToOpBits(knownValue, ops[3].opBits);
                    rewritten        = true;
                }
                else if (ops[3].opBits == ops[4].opBits)
                {
                    inst.op          = MicroInstrOpcode::LoadRegMem;
                    inst.numOperands = 4;
                    ops[1].reg       = stackPointerReg;
                    ops[2].opBits    = ops[4].opBits;
                    ops[3].valueU64  = stackOffset;
                    rewritten        = true;
                }

                if (rewritten)
                {
                    if (MicroOptimization::violatesEncoderConformance(context, inst, ops))
                    {
                        inst.op = originalOp;
                        for (uint32_t opIdx = 0; opIdx < originalOps.size(); ++opIdx)
                            ops[opIdx] = originalOps[opIdx];
                    }
                    else
                    {
                        changed = true;
                    }
                }
            }
        }

        if (inst.op == MicroInstrOpcode::LoadRegMem && ops[0].reg.isInt())
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[1].reg, ops[3].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[2].opBits))
                {
                    inst.op          = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands = 3;
                    ops[1].opBits    = ops[2].opBits;
                    ops[2].valueU64  = knownValue;
                    changed          = true;
                }
            }
        }

        if ((inst.op == MicroInstrOpcode::LoadSignedExtRegMem || inst.op == MicroInstrOpcode::LoadZeroExtRegMem) && ops[0].reg.isInt())
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[1].reg, ops[4].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[3].opBits))
                {
                    uint64_t immValue = 0;
                    if (inst.op == MicroInstrOpcode::LoadSignedExtRegMem)
                        immValue = signExtendToBits(knownValue, ops[3].opBits, ops[2].opBits);
                    else
                        immValue = MicroOptimization::normalizeToOpBits(knownValue, ops[2].opBits);

                    inst.op          = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands = 3;
                    ops[1].opBits    = ops[2].opBits;
                    ops[2].valueU64  = immValue;
                    changed          = true;
                }
            }
        }

        if (inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[0].reg.isInt() && ops[1].reg.isInt() && !ops[1].reg.isInstructionPointer())
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end())
            {
                inst.op          = MicroInstrOpcode::LoadRegImm;
                inst.numOperands = 3;
                ops[1].opBits    = ops[2].opBits;
                ops[2].valueU64  = MicroOptimization::normalizeToOpBits(itKnown->second.value + ops[3].valueU64, ops[2].opBits);
                changed          = true;
            }
        }

        if (inst.op == MicroInstrOpcode::LoadRegReg)
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end() && ops[0].reg.isInt())
            {
                inst.op         = MicroInstrOpcode::LoadRegImm;
                ops[1].opBits   = ops[2].opBits;
                ops[2].valueU64 = MicroOptimization::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                changed         = true;
            }
        }
        else if ((inst.op == MicroInstrOpcode::LoadSignedExtRegReg || inst.op == MicroInstrOpcode::LoadZeroExtRegReg) && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end())
            {
                uint64_t immValue = 0;
                if (inst.op == MicroInstrOpcode::LoadSignedExtRegReg)
                    immValue = signExtendToBits(itKnown->second.value, ops[3].opBits, ops[2].opBits);
                else
                    immValue = MicroOptimization::normalizeToOpBits(itKnown->second.value, ops[2].opBits);

                inst.op          = MicroInstrOpcode::LoadRegImm;
                inst.numOperands = 3;
                ops[1].opBits    = ops[2].opBits;
                ops[2].valueU64  = immValue;
                changed          = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegMem && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[1].reg, ops[4].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[2].opBits))
                {
                    const uint64_t immValue   = MicroOptimization::normalizeToOpBits(knownValue, ops[2].opBits);
                    const auto     itKnownDst = known.find(ops[0].reg.packed);

                    if (itKnownDst != known.end())
                    {
                        uint64_t               foldedValue = 0;
                        const Math::FoldStatus foldStatus  = MicroOptimization::foldBinaryImmediate(foldedValue, itKnownDst->second.value, immValue, ops[3].microOp, ops[2].opBits);
                        if (foldStatus == Math::FoldStatus::Ok)
                        {
                            inst.op          = MicroInstrOpcode::LoadRegImm;
                            inst.numOperands = 3;
                            ops[1].opBits    = ops[2].opBits;
                            ops[2].valueU64  = foldedValue;
                            changed          = true;
                        }
                        else if (Math::isSafetyError(foldStatus))
                        {
                            return MicroOptimization::raiseFoldSafetyError(context, instRef, foldStatus);
                        }
                    }
                    else
                    {
                        const MicroInstrOpcode originalOp  = inst.op;
                        const std::array       originalOps = {ops[0], ops[1], ops[2], ops[3], ops[4]};

                        inst.op          = MicroInstrOpcode::OpBinaryRegImm;
                        inst.numOperands = 4;
                        ops[1].opBits    = originalOps[2].opBits;
                        ops[2].microOp   = originalOps[3].microOp;
                        ops[3].valueU64  = immValue;
                        if (MicroOptimization::violatesEncoderConformance(context, inst, ops))
                        {
                            inst.op = originalOp;
                            for (uint32_t opIdx = 0; opIdx < originalOps.size(); ++opIdx)
                                ops[opIdx] = originalOps[opIdx];
                        }
                        else
                        {
                            changed = true;
                        }
                    }
                }
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnownSrc = known.find(ops[1].reg.packed);
            if (itKnownSrc != known.end())
            {
                const uint64_t immValue   = MicroOptimization::normalizeToOpBits(itKnownSrc->second.value, ops[2].opBits);
                const auto     itKnownDst = known.find(ops[0].reg.packed);

                if (itKnownDst != known.end())
                {
                    uint64_t               foldedValue = 0;
                    const Math::FoldStatus foldStatus  = MicroOptimization::foldBinaryImmediate(foldedValue, itKnownDst->second.value, immValue, ops[3].microOp, ops[2].opBits);
                    if (foldStatus == Math::FoldStatus::Ok)
                    {
                        inst.op          = MicroInstrOpcode::LoadRegImm;
                        inst.numOperands = 3;
                        ops[1].opBits    = ops[2].opBits;
                        ops[2].valueU64  = foldedValue;
                        changed          = true;
                    }
                    else if (Math::isSafetyError(foldStatus))
                    {
                        return MicroOptimization::raiseFoldSafetyError(context, instRef, foldStatus);
                    }
                }
                else
                {
                    const MicroInstrOpcode originalOp  = inst.op;
                    const std::array       originalOps = {ops[0], ops[1], ops[2], ops[3]};

                    inst.op          = MicroInstrOpcode::OpBinaryRegImm;
                    inst.numOperands = 4;
                    ops[1].opBits    = originalOps[2].opBits;
                    ops[2].microOp   = originalOps[3].microOp;
                    ops[3].valueU64  = immValue;
                    if (MicroOptimization::violatesEncoderConformance(context, inst, ops))
                    {
                        inst.op = originalOp;
                        for (uint32_t opIdx = 0; opIdx < originalOps.size(); ++opIdx)
                            ops[opIdx] = originalOps[opIdx];
                    }
                    else
                    {
                        changed = true;
                    }
                }
            }
        }
        else if (inst.op == MicroInstrOpcode::CmpRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end())
            {
                const uint64_t         immValue    = MicroOptimization::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                const MicroInstrOpcode originalOp  = inst.op;
                const std::array       originalOps = {ops[0], ops[1], ops[2]};

                inst.op          = MicroInstrOpcode::CmpRegImm;
                inst.numOperands = 3;
                ops[1].opBits    = originalOps[2].opBits;
                ops[2].valueU64  = immValue;
                if (MicroOptimization::violatesEncoderConformance(context, inst, ops))
                {
                    inst.op = originalOp;
                    for (uint32_t opIdx = 0; opIdx < originalOps.size(); ++opIdx)
                        ops[opIdx] = originalOps[opIdx];
                }
                else
                {
                    changed = true;
                }
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto itKnown = known.find(ops[0].reg.packed);
            if (itKnown != known.end())
            {
                uint64_t               foldedValue = 0;
                const Math::FoldStatus foldStatus  = MicroOptimization::foldBinaryImmediate(foldedValue, itKnown->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
                if (foldStatus == Math::FoldStatus::Ok)
                {
                    inst.op          = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands = 3;
                    ops[2].valueU64  = foldedValue;
                    changed          = true;
                }
                else if (Math::isSafetyError(foldStatus))
                {
                    return MicroOptimization::raiseFoldSafetyError(context, instRef, foldStatus);
                }
            }
        }

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        eraseKnownDefs(known, useDef.defs);
        eraseKnownAddressDefs(knownAddresses, useDef.defs);
        eraseKnownConstantPointerDefs(knownConstantPointers, useDef.defs);

        if (stackPointerReg.isValid() && definesRegister(useDef.defs, stackPointerReg))
        {
            knownStackSlots.clear();
            knownAddresses.clear();
        }

        if (useDef.isCall)
        {
            const bool hasStackAddressArg = callHasStackAddressArgument(knownAddresses, useDef.callConv);
            known.clear();
            if (hasStackAddressArg)
                knownStackSlots.clear();
            knownAddresses.clear();
            knownConstantPointers.clear();
            continue;
        }

        bool handledMemoryWrite = false;
        if (inst.op == MicroInstrOpcode::LoadMemImm)
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[2].valueU64))
            {
                setKnownStackSlot(knownStackSlots, stackOffset, ops[1].opBits, ops[3].valueU64);
                handledMemoryWrite = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::LoadMemReg)
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[3].valueU64))
            {
                const auto itKnownReg = known.find(ops[1].reg.packed);
                if (itKnownReg != known.end())
                {
                    setKnownStackSlot(knownStackSlots, stackOffset, ops[2].opBits, itKnownReg->second.value);
                }
                else
                {
                    bool handledConstantCopy = false;
                    if (it != storage.view().begin() &&
                        opBitsNumBytes(ops[2].opBits) &&
                        opBitsNumBytes(ops[2].opBits) <= 16)
                    {
                        auto              itPrev   = std::prev(it);
                        const MicroInstr& prevInst = *itPrev;
                        const auto*       prevOps  = prevInst.ops(operands);
                        if (prevOps &&
                            prevInst.op == MicroInstrOpcode::LoadRegMem &&
                            prevOps[0].reg == ops[1].reg &&
                            prevOps[2].opBits == ops[2].opBits &&
                            prevOps[1].reg.isInt())
                        {
                            const auto itConstPtr = knownConstantPointers.find(prevOps[1].reg.packed);
                            if (itConstPtr != knownConstantPointers.end())
                            {
                                const uint32_t numBytes       = opBitsNumBytes(ops[2].opBits);
                                const uint64_t constantOffset = itConstPtr->second.offset + prevOps[3].valueU64;

                                std::array<std::byte, 16> bytes{};
                                if (tryGetPointerBytesRange(bytes, numBytes, itConstPtr->second.pointer, constantOffset))
                                {
                                    eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[2].opBits);
                                    setKnownStackSlotsFromBytes(knownStackSlots, stackOffset, std::span<const std::byte>{bytes.data(), numBytes});
                                    handledConstantCopy = true;
                                }
                            }
                        }
                    }

                    if (!handledConstantCopy)
                        eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[2].opBits);
                }
                handledMemoryWrite = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::LoadAmcMemImm)
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetForAmc(stackOffset,
                                            knownAddresses,
                                            known,
                                            stackPointerReg,
                                            ops[0].reg,
                                            ops[1].reg,
                                            ops[5].valueU64,
                                            ops[6].valueU64))
            {
                setKnownStackSlot(knownStackSlots, stackOffset, ops[4].opBits, ops[7].valueU64);
                handledMemoryWrite = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::LoadAmcMemReg)
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetForAmc(stackOffset,
                                            knownAddresses,
                                            known,
                                            stackPointerReg,
                                            ops[0].reg,
                                            ops[1].reg,
                                            ops[5].valueU64,
                                            ops[6].valueU64))
            {
                const auto itKnownReg = known.find(ops[2].reg.packed);
                if (itKnownReg != known.end())
                    setKnownStackSlot(knownStackSlots, stackOffset, ops[4].opBits, itKnownReg->second.value);
                else
                    eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[4].opBits);

                handledMemoryWrite = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryMemImm)
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[3].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[1].opBits))
                {
                    uint64_t               foldedValue = 0;
                    const Math::FoldStatus foldStatus  = MicroOptimization::foldBinaryImmediate(foldedValue, knownValue, ops[4].valueU64, ops[2].microOp, ops[1].opBits);
                    if (foldStatus == Math::FoldStatus::Ok)
                        setKnownStackSlot(knownStackSlots, stackOffset, ops[1].opBits, foldedValue);
                    else if (Math::isSafetyError(foldStatus))
                        return MicroOptimization::raiseFoldSafetyError(context, instRef, foldStatus);
                    else
                        eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[1].opBits);
                }
                else
                {
                    eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[1].opBits);
                }

                handledMemoryWrite = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryMemReg)
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[4].valueU64))
            {
                uint64_t   knownValue = 0;
                const auto itKnownReg = known.find(ops[1].reg.packed);
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[2].opBits) && itKnownReg != known.end())
                {
                    uint64_t               foldedValue = 0;
                    const Math::FoldStatus foldStatus  = MicroOptimization::foldBinaryImmediate(foldedValue, knownValue, itKnownReg->second.value, ops[3].microOp, ops[2].opBits);
                    if (foldStatus == Math::FoldStatus::Ok)
                        setKnownStackSlot(knownStackSlots, stackOffset, ops[2].opBits, foldedValue);
                    else if (Math::isSafetyError(foldStatus))
                        return MicroOptimization::raiseFoldSafetyError(context, instRef, foldStatus);
                    else
                        eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[2].opBits);
                }
                else
                {
                    eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[2].opBits);
                }

                handledMemoryWrite = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::OpUnaryMem)
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[3].valueU64))
            {
                eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[1].opBits);
                handledMemoryWrite = true;
            }
        }

        if (writesMemory(inst) && !handledMemoryWrite)
            knownStackSlots.clear();

        if (inst.op == MicroInstrOpcode::LoadRegImm && ops[0].reg.isInt())
        {
            known[ops[0].reg.packed] = {
                .value = MicroOptimization::normalizeToOpBits(ops[2].valueU64, ops[1].opBits),
            };
        }
        else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end())
            {
                known[ops[0].reg.packed] = {
                    .value = MicroOptimization::normalizeToOpBits(itKnown->second.value, ops[2].opBits),
                };
            }
        }
        else if (inst.op == MicroInstrOpcode::ClearReg && ops[0].reg.isInt())
        {
            known[ops[0].reg.packed] = {
                .value = 0,
            };
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto itKnown = known.find(ops[0].reg.packed);
            if (itKnown != known.end())
            {
                uint64_t               foldedValue = 0;
                const Math::FoldStatus foldStatus  = MicroOptimization::foldBinaryImmediate(foldedValue, itKnown->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
                if (foldStatus == Math::FoldStatus::Ok)
                {
                    known[ops[0].reg.packed] = {
                        .value = foldedValue,
                    };
                }
                else if (Math::isSafetyError(foldStatus))
                {
                    return MicroOptimization::raiseFoldSafetyError(context, instRef, foldStatus);
                }
            }
        }

        if (inst.op == MicroInstrOpcode::LoadRegPtrImm && ops[0].reg.isInt() && ops[1].opBits == MicroOpBits::B64)
        {
            if (ops[2].valueU64)
            {
                knownConstantPointers[ops[0].reg.packed] = {
                    .pointer = ops[2].valueU64,
                    .offset  = 0,
                };
            }
            else
            {
                knownConstantPointers.erase(ops[0].reg.packed);
            }
        }
        else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isInt() && ops[1].reg.isInt() && ops[2].opBits == MicroOpBits::B64)
        {
            const auto itConstPtr = knownConstantPointers.find(ops[1].reg.packed);
            if (itConstPtr != knownConstantPointers.end())
            {
                knownConstantPointers[ops[0].reg.packed] = itConstPtr->second;
            }
            else
            {
                knownConstantPointers.erase(ops[0].reg.packed);
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt() && ops[1].opBits == MicroOpBits::B64)
        {
            const auto itConstPtr = knownConstantPointers.find(ops[0].reg.packed);
            if (itConstPtr != knownConstantPointers.end())
            {
                auto knownConstPtr = itConstPtr->second;
                bool validUpdate   = false;
                if (ops[2].microOp == MicroOp::Add)
                {
                    if (knownConstPtr.offset <= std::numeric_limits<uint64_t>::max() - ops[3].valueU64)
                    {
                        knownConstPtr.offset += ops[3].valueU64;
                        validUpdate = true;
                    }
                }
                else if (ops[2].microOp == MicroOp::Subtract)
                {
                    if (knownConstPtr.offset >= ops[3].valueU64)
                    {
                        knownConstPtr.offset -= ops[3].valueU64;
                        validUpdate = true;
                    }
                }

                if (validUpdate)
                    knownConstantPointers[ops[0].reg.packed] = knownConstPtr;
                else
                    knownConstantPointers.erase(ops[0].reg.packed);
            }
        }

        if (inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[0].reg.isInt())
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[1].reg, ops[3].valueU64))
                knownAddresses[ops[0].reg.packed] = stackOffset;
        }
        else if (inst.op == MicroInstrOpcode::LoadAddrAmcRegMem && ops[0].reg.isInt())
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetForAmc(stackOffset,
                                            knownAddresses,
                                            known,
                                            stackPointerReg,
                                            ops[1].reg,
                                            ops[2].reg,
                                            ops[5].valueU64,
                                            ops[6].valueU64))
            {
                knownAddresses[ops[0].reg.packed] = stackOffset;
            }
        }
        else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isInt() && ops[1].reg.isInt() && ops[2].opBits == MicroOpBits::B64)
        {
            if (ops[1].reg == stackPointerReg)
            {
                knownAddresses[ops[0].reg.packed] = 0;
            }
            else
            {
                const auto itAddress = knownAddresses.find(ops[1].reg.packed);
                if (itAddress != knownAddresses.end())
                    knownAddresses[ops[0].reg.packed] = itAddress->second;
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt() && ops[1].opBits == MicroOpBits::B64)
        {
            const auto itAddress = knownAddresses.find(ops[0].reg.packed);
            if (itAddress != knownAddresses.end())
            {
                if (ops[2].microOp == MicroOp::Add)
                    knownAddresses[ops[0].reg.packed] = itAddress->second + ops[3].valueU64;
                else if (ops[2].microOp == MicroOp::Subtract)
                    knownAddresses[ops[0].reg.packed] = itAddress->second - ops[3].valueU64;
            }
        }

        if (inst.op == MicroInstrOpcode::Label || MicroInstrInfo::isTerminatorInstruction(inst))
        {
            known.clear();
            knownStackSlots.clear();
            knownAddresses.clear();
            knownConstantPointers.clear();
        }
    }

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
