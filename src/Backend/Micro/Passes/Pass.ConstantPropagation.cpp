#include "pch.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"

// Propagates known constants through register operations.
// Example: load r1, 5; add r2, r1  ->  add r2, 5.
// Example: load r1, 5; shl r1, 1    ->  load r1, 10.
// This removes dynamic work and creates simpler instruction forms.

SWC_BEGIN_NAMESPACE();

namespace
{
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
        const uint32_t slotSize = microOpBitsNumBytes(opBits);
        if (!slotSize)
        {
            knownSlots.clear();
            return;
        }

        for (auto it = knownSlots.begin(); it != knownSlots.end();)
        {
            const uint32_t knownSize = microOpBitsNumBytes(it->first.opBits);
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
            .value = MicroPassHelpers::normalizeToOpBits(value, opBits),
        };
    }

    void eraseOverlappingStackAddresses(KnownStackAddressMap& knownStackAddresses, uint64_t offset, MicroOpBits opBits)
    {
        const uint32_t slotSize = microOpBitsNumBytes(opBits);
        if (!slotSize)
        {
            knownStackAddresses.clear();
            return;
        }

        for (auto it = knownStackAddresses.begin(); it != knownStackAddresses.end();)
        {
            if (rangesOverlap(offset, slotSize, it->first, sizeof(uint64_t)))
                it = knownStackAddresses.erase(it);
            else
                ++it;
        }
    }

    void setKnownStackAddress(KnownStackAddressMap& knownStackAddresses, uint64_t stackSlotOffset, uint64_t stackAddressOffset)
    {
        eraseOverlappingStackAddresses(knownStackAddresses, stackSlotOffset, MicroOpBits::B64);
        knownStackAddresses[stackSlotOffset] = stackAddressOffset;
    }

    bool tryGetKnownStackAddress(uint64_t& outStackAddressOffset, const KnownStackAddressMap& knownStackAddresses, uint64_t stackSlotOffset, MicroOpBits opBits)
    {
        if (opBits != MicroOpBits::B64)
            return false;

        const auto it = knownStackAddresses.find(stackSlotOffset);
        if (it == knownStackAddresses.end())
            return false;

        outStackAddressOffset = it->second;
        return true;
    }

    bool tryGetKnownStackSlotValue(uint64_t& outValue, const KnownStackSlotMap& knownSlots, uint64_t offset, MicroOpBits opBits)
    {
        const auto it = knownSlots.find({.offset = offset, .opBits = opBits});
        if (it != knownSlots.end())
        {
            outValue = it->second.value;
            return true;
        }

        const uint32_t wantedSize = microOpBitsNumBytes(opBits);
        if (!wantedSize || wantedSize > sizeof(uint64_t))
            return false;

        for (const auto& [knownKey, knownValue] : knownSlots)
        {
            const uint32_t knownSize = microOpBitsNumBytes(knownKey.opBits);
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
            outValue                  = MicroPassHelpers::normalizeToOpBits(shifted, opBits);
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
        if (MicroPassHelpers::violatesEncoderConformance(context, inst, ops))
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
        const uint64_t normalizedSrc = MicroPassHelpers::normalizeToOpBits(value, srcBits);

        switch (srcBits)
        {
            case MicroOpBits::B8:
                return MicroPassHelpers::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int8_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B16:
                return MicroPassHelpers::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int16_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B32:
                return MicroPassHelpers::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B64:
                return MicroPassHelpers::normalizeToOpBits(normalizedSrc, dstBits);
            default:
                return MicroPassHelpers::normalizeToOpBits(normalizedSrc, dstBits);
        }
    }

    bool foldFloatBinaryToBits(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B32)
        {
            const uint32_t lhsBits = static_cast<uint32_t>(lhs);
            const uint32_t rhsBits = static_cast<uint32_t>(rhs);
            float          lhsVal  = 0;
            float          rhsVal  = 0;
            std::memcpy(&lhsVal, &lhsBits, sizeof(lhsVal));
            std::memcpy(&rhsVal, &rhsBits, sizeof(rhsVal));

            float result = 0;
            switch (op)
            {
                case MicroOp::FloatAdd:
                    result = lhsVal + rhsVal;
                    break;
                case MicroOp::FloatSubtract:
                    result = lhsVal - rhsVal;
                    break;
                case MicroOp::FloatMultiply:
                    result = lhsVal * rhsVal;
                    break;
                case MicroOp::FloatDivide:
                    result = lhsVal / rhsVal;
                    break;
                default:
                    return false;
            }

            uint32_t resultBits = 0;
            std::memcpy(&resultBits, &result, sizeof(resultBits));
            outValue = MicroPassHelpers::normalizeToOpBits(resultBits, MicroOpBits::B32);
            return true;
        }

        if (opBits == MicroOpBits::B64)
        {
            double lhsVal = 0;
            double rhsVal = 0;
            std::memcpy(&lhsVal, &lhs, sizeof(lhsVal));
            std::memcpy(&rhsVal, &rhs, sizeof(rhsVal));

            double result = 0;
            switch (op)
            {
                case MicroOp::FloatAdd:
                    result = lhsVal + rhsVal;
                    break;
                case MicroOp::FloatSubtract:
                    result = lhsVal - rhsVal;
                    break;
                case MicroOp::FloatMultiply:
                    result = lhsVal * rhsVal;
                    break;
                case MicroOp::FloatDivide:
                    result = lhsVal / rhsVal;
                    break;
                default:
                    return false;
            }

            std::memcpy(&outValue, &result, sizeof(outValue));
            return true;
        }

        return false;
    }

    bool foldConvertFloatToIntToBits(uint64_t& outValue, uint64_t srcBits, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B32)
        {
            float          value = 0;
            const uint32_t bits  = static_cast<uint32_t>(srcBits);
            std::memcpy(&value, &bits, sizeof(value));
            if (!std::isfinite(value))
                return false;
            if (value < static_cast<float>(std::numeric_limits<int32_t>::min()) ||
                value > static_cast<float>(std::numeric_limits<int32_t>::max()))
            {
                return false;
            }

            outValue = MicroPassHelpers::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(value))), MicroOpBits::B32);
            return true;
        }

        if (opBits == MicroOpBits::B64)
        {
            double value = 0;
            std::memcpy(&value, &srcBits, sizeof(value));
            if (!std::isfinite(value))
                return false;
            if (value < static_cast<double>(std::numeric_limits<int64_t>::min()) ||
                value > static_cast<double>(std::numeric_limits<int64_t>::max()))
            {
                return false;
            }

            outValue = static_cast<uint64_t>(static_cast<int64_t>(value));
            return true;
        }

        return false;
    }

    enum class BinaryFoldResult : uint8_t
    {
        NotFolded,
        Folded,
        SafetyError,
    };

    BinaryFoldResult tryFoldBinaryImmediateForPropagation(uint64_t&         outValue,
                                                          uint64_t          lhs,
                                                          uint64_t          rhs,
                                                          MicroOp           op,
                                                          MicroOpBits       opBits,
                                                          Math::FoldStatus* outSafetyStatus = nullptr)
    {
        const Math::FoldStatus foldStatus = MicroPassHelpers::foldBinaryImmediate(outValue, lhs, rhs, op, opBits);
        if (foldStatus == Math::FoldStatus::Ok)
            return BinaryFoldResult::Folded;

        if (!Math::isSafetyError(foldStatus))
            return BinaryFoldResult::NotFolded;

        if (MicroPassHelpers::tryFoldAddSubSignedNoOverflow(outValue, lhs, rhs, op, opBits))
            return BinaryFoldResult::Folded;

        if (outSafetyStatus)
            *outSafetyStatus = foldStatus;

        return BinaryFoldResult::SafetyError;
    }

    bool tryApplyUnsignedAddSubOffset(uint64_t& outValue, uint64_t inValue, uint64_t delta, MicroOp op)
    {
        if (op == MicroOp::Add)
        {
            if (inValue > std::numeric_limits<uint64_t>::max() - delta)
                return false;
            outValue = inValue + delta;
            return true;
        }

        if (op == MicroOp::Subtract)
        {
            if (inValue < delta)
                return false;
            outValue = inValue - delta;
            return true;
        }

        return false;
    }

    struct InstrRewriteSnapshot
    {
        static constexpr uint32_t K_MAX_OPERANDS = 8;

        MicroInstrOpcode                              op          = MicroInstrOpcode::Nop;
        uint8_t                                       numOperands = 0;
        std::array<MicroInstrOperand, K_MAX_OPERANDS> operands{};
    };

    void captureInstrRewriteSnapshot(InstrRewriteSnapshot& outSnapshot, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_ASSERT(ops != nullptr);
        SWC_ASSERT(inst.numOperands <= InstrRewriteSnapshot::K_MAX_OPERANDS);

        outSnapshot.op          = inst.op;
        outSnapshot.numOperands = inst.numOperands;
        for (uint32_t idx = 0; idx < outSnapshot.numOperands; ++idx)
            outSnapshot.operands[idx] = ops[idx];
    }

    void restoreInstrRewriteSnapshot(const InstrRewriteSnapshot& snapshot, MicroInstr& inst, MicroInstrOperand* ops)
    {
        SWC_ASSERT(ops != nullptr);

        inst.op          = snapshot.op;
        inst.numOperands = snapshot.numOperands;
        for (uint32_t idx = 0; idx < snapshot.numOperands; ++idx)
            ops[idx] = snapshot.operands[idx];
    }

    bool commitOrRestoreInstrRewrite(const MicroPassContext& context, const InstrRewriteSnapshot& snapshot, MicroInstr& inst, MicroInstrOperand* ops)
    {
        if (!MicroPassHelpers::violatesEncoderConformance(context, inst, ops))
            return true;

        restoreInstrRewriteSnapshot(snapshot, inst, ops);
        return false;
    }

    Math::FoldStatus foldUnaryImmediateToBits(uint64_t& outValue, uint64_t inValue, MicroOp microOp, MicroOpBits opBits)
    {
        const uint32_t bitWidth = getNumBits(opBits);
        if (!bitWidth)
            return Math::FoldStatus::Unsupported;

        auto unaryOp = Math::FoldUnaryOp::Plus;
        bool isSignedInput;
        switch (microOp)
        {
            case MicroOp::Negate:
                unaryOp       = Math::FoldUnaryOp::Minus;
                isSignedInput = true;
                break;

            case MicroOp::BitwiseNot:
                unaryOp       = Math::FoldUnaryOp::BitwiseNot;
                isSignedInput = false;
                break;

            default:
                return Math::FoldStatus::Unsupported;
        }

        const uint64_t normalized = MicroPassHelpers::normalizeToOpBits(inValue, opBits);
        const ApsInt   input(&normalized, bitWidth, !isSignedInput);

        ApsInt                 folded;
        const Math::FoldStatus foldStatus = Math::foldUnaryInt(folded, input, unaryOp);
        if (foldStatus != Math::FoldStatus::Ok)
            return foldStatus;

        outValue = MicroPassHelpers::normalizeToOpBits(folded.as64(), opBits);
        return Math::FoldStatus::Ok;
    }
}

Result MicroConstantPropagationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool changed = false;
    initRunState(context);

    KnownRegMap&             known                      = known_;
    KnownStackSlotMap&       knownStackSlots            = knownStackSlots_;
    KnownAddressMap&         knownAddresses             = knownAddresses_;
    KnownStackAddressMap&    knownStackAddresses        = knownStackAddresses_;
    KnownConstantPointerMap& knownConstantPointers      = knownConstantPointers_;
    auto&                    relocationByInstructionRef = relocationByInstructionRef_;
    const MicroReg           stackPointerReg            = stackPointerReg_;
    MicroStorage&            storage                    = *storage_;
    MicroOperandStorage&     operands                   = *operands_;

    for (auto it = storage_->view().begin(); it != storage_->view().end(); ++it)
    {
        const MicroInstrRef                          instRef = it.current;
        MicroInstr&                                  inst    = *it;
        MicroInstrOperand*                           ops     = inst.ops(*operands_);
        std::optional<std::pair<uint32_t, uint64_t>> deferredKnownDef;
        std::optional<std::pair<uint32_t, uint64_t>> deferredAddressDef;

        if (rewriteMemoryBaseToKnownStack(inst, ops))
            changed = true;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            {
                if (!stackPointerReg.isValid() || !ops[0].reg.isInt() || !ops[1].reg.isInt() || !ops[2].reg.isInt())
                    break;

                uint64_t stackOffset = 0;
                if (!tryResolveStackOffsetForAmc(stackOffset, knownAddresses, known, stackPointerReg, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64))
                    break;

                InstrRewriteSnapshot rewriteSnapshot;
                captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);
                bool rewritten = false;

                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[4].opBits))
                {
                    inst.op          = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands = 3;
                    ops[1].opBits    = ops[3].opBits;
                    ops[2].valueU64  = MicroPassHelpers::normalizeToOpBits(knownValue, ops[3].opBits);
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
                    if (commitOrRestoreInstrRewrite(context, rewriteSnapshot, inst, ops))
                        changed = true;
                }

                uint64_t knownStackAddressOffset = 0;
                if (tryGetKnownStackAddress(knownStackAddressOffset, knownStackAddresses, stackOffset, ops[3].opBits))
                    deferredAddressDef = std::pair{ops[0].reg.packed, knownStackAddressOffset};
                break;
            }
            case MicroInstrOpcode::LoadRegMem:
            {
                uint64_t stackOffset = 0;
                if (!tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[1].reg, ops[3].valueU64))
                    break;

                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[2].opBits))
                {
                    const uint64_t normalizedValue = MicroPassHelpers::normalizeToOpBits(knownValue, ops[2].opBits);
                    if (ops[0].reg.isInt())
                    {
                        inst.op          = MicroInstrOpcode::LoadRegImm;
                        inst.numOperands = 3;
                        ops[1].opBits    = ops[2].opBits;
                        ops[2].valueU64  = normalizedValue;
                        changed          = true;
                    }
                    else
                    {
                        deferredKnownDef = std::pair{ops[0].reg.packed, normalizedValue};
                    }
                }

                if (!ops[0].reg.isInt())
                    break;

                uint64_t knownStackAddressOffset = 0;
                if (tryGetKnownStackAddress(knownStackAddressOffset, knownStackAddresses, stackOffset, ops[2].opBits))
                    deferredAddressDef = std::pair{ops[0].reg.packed, knownStackAddressOffset};
                break;
            }
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            {
                if (!ops[0].reg.isInt())
                    break;

                uint64_t stackOffset = 0;
                if (!tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[1].reg, ops[4].valueU64))
                    break;

                uint64_t knownValue = 0;
                if (!tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[3].opBits))
                    break;

                uint64_t immValue = 0;
                switch (inst.op)
                {
                    case MicroInstrOpcode::LoadSignedExtRegMem:
                        immValue = signExtendToBits(knownValue, ops[3].opBits, ops[2].opBits);
                        break;
                    case MicroInstrOpcode::LoadZeroExtRegMem:
                        immValue = MicroPassHelpers::normalizeToOpBits(knownValue, ops[2].opBits);
                        break;
                    default:
                        break;
                }

                inst.op          = MicroInstrOpcode::LoadRegImm;
                inst.numOperands = 3;
                ops[1].opBits    = ops[2].opBits;
                ops[2].valueU64  = immValue;
                changed          = true;
                break;
            }
            case MicroInstrOpcode::LoadAddrRegMem:
            {
                if (!ops[0].reg.isInt() || !ops[1].reg.isInt() || ops[1].reg.isInstructionPointer())
                    break;

                const MicroReg baseReg    = ops[1].reg;
                const uint64_t baseOffset = ops[3].valueU64;
                const auto     itKnown    = known.find(ops[1].reg.packed);
                if (itKnown == known.end())
                    break;

                inst.op          = MicroInstrOpcode::LoadRegImm;
                inst.numOperands = 3;
                ops[1].opBits    = ops[2].opBits;
                ops[2].valueU64  = MicroPassHelpers::normalizeToOpBits(itKnown->second.value + baseOffset, ops[2].opBits);
                changed          = true;

                if (ops[2].opBits != MicroOpBits::B64)
                    break;

                const auto itAddress = knownAddresses.find(baseReg.packed);
                if (itAddress != knownAddresses.end() && itAddress->second <= std::numeric_limits<uint64_t>::max() - baseOffset)
                    deferredAddressDef = std::pair{ops[0].reg.packed, itAddress->second + baseOffset};
                break;
            }
            default:
                break;
        }

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            {
                const MicroReg sourceReg = ops[1].reg;
                const auto     itKnown   = known.find(ops[1].reg.packed);
                if (itKnown != known.end() && ops[0].reg.isInt())
                {
                    inst.op         = MicroInstrOpcode::LoadRegImm;
                    ops[1].opBits   = ops[2].opBits;
                    ops[2].valueU64 = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                    changed         = true;

                    if (ops[2].opBits == MicroOpBits::B64)
                    {
                        const auto itAddress = knownAddresses.find(sourceReg.packed);
                        if (itAddress != knownAddresses.end())
                            deferredAddressDef = std::pair{ops[0].reg.packed, itAddress->second};
                    }
                }
                break;
            }
            case MicroInstrOpcode::LoadSignedExtRegReg:
            {
                if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[1].reg.packed);
                if (itKnown != known.end())
                {
                    inst.op          = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands = 3;
                    ops[1].opBits    = ops[2].opBits;
                    ops[2].valueU64  = signExtendToBits(itKnown->second.value, ops[3].opBits, ops[2].opBits);
                    changed          = true;
                }
                break;
            }
            case MicroInstrOpcode::LoadZeroExtRegReg:
            {
                if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[1].reg.packed);
                if (itKnown != known.end())
                {
                    inst.op          = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands = 3;
                    ops[1].opBits    = ops[2].opBits;
                    ops[2].valueU64  = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                    changed          = true;
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryRegMem:
            {
                if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                    break;

                uint64_t stackOffset = 0;
                if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[1].reg, ops[4].valueU64))
                {
                    uint64_t knownValue = 0;
                    if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[2].opBits))
                    {
                        const uint64_t immValue   = MicroPassHelpers::normalizeToOpBits(knownValue, ops[2].opBits);
                        const auto     itKnownDst = known.find(ops[0].reg.packed);

                        if (itKnownDst != known.end())
                        {
                            uint64_t foldedValue  = 0;
                            auto     safetyStatus = Math::FoldStatus::Ok;
                            switch (tryFoldBinaryImmediateForPropagation(foldedValue, itKnownDst->second.value, immValue, ops[3].microOp, ops[2].opBits, &safetyStatus))
                            {
                                case BinaryFoldResult::Folded:
                                    inst.op          = MicroInstrOpcode::LoadRegImm;
                                    inst.numOperands = 3;
                                    ops[1].opBits    = ops[2].opBits;
                                    ops[2].valueU64  = foldedValue;
                                    changed          = true;
                                    break;
                                case BinaryFoldResult::SafetyError:
                                    if (!MicroPassHelpers::isAddOrSubMicroOp(ops[3].microOp))
                                        return MicroPassHelpers::raiseFoldSafetyError(context, instRef, safetyStatus);
                                    break;
                                case BinaryFoldResult::NotFolded:
                                    break;
                            }
                        }
                        else
                        {
                            InstrRewriteSnapshot rewriteSnapshot;
                            captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                            inst.op          = MicroInstrOpcode::OpBinaryRegImm;
                            inst.numOperands = 4;
                            ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                            ops[2].microOp   = rewriteSnapshot.operands[3].microOp;
                            ops[3].valueU64  = immValue;
                            if (commitOrRestoreInstrRewrite(context, rewriteSnapshot, inst, ops))
                                changed = true;
                        }
                    }
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryRegReg:
            {
                if (ops[0].reg.isInt() && ops[1].reg.isInt())
                {
                    const auto itKnownSrc = known.find(ops[1].reg.packed);
                    if (itKnownSrc != known.end())
                    {
                        const uint64_t immValue   = MicroPassHelpers::normalizeToOpBits(itKnownSrc->second.value, ops[2].opBits);
                        const auto     itKnownDst = known.find(ops[0].reg.packed);

                        if (itKnownDst != known.end())
                        {
                            uint64_t foldedValue  = 0;
                            auto     safetyStatus = Math::FoldStatus::Ok;
                            switch (tryFoldBinaryImmediateForPropagation(foldedValue, itKnownDst->second.value, immValue, ops[3].microOp, ops[2].opBits, &safetyStatus))
                            {
                                case BinaryFoldResult::Folded:
                                    inst.op          = MicroInstrOpcode::LoadRegImm;
                                    inst.numOperands = 3;
                                    ops[1].opBits    = ops[2].opBits;
                                    ops[2].valueU64  = foldedValue;
                                    changed          = true;
                                    break;
                                case BinaryFoldResult::SafetyError:
                                    if (!MicroPassHelpers::isAddOrSubMicroOp(ops[3].microOp))
                                        return MicroPassHelpers::raiseFoldSafetyError(context, instRef, safetyStatus);
                                    break;
                                case BinaryFoldResult::NotFolded:
                                    break;
                            }
                        }
                        else
                        {
                            InstrRewriteSnapshot rewriteSnapshot;
                            captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                            inst.op          = MicroInstrOpcode::OpBinaryRegImm;
                            inst.numOperands = 4;
                            ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                            ops[2].microOp   = rewriteSnapshot.operands[3].microOp;
                            ops[3].valueU64  = immValue;
                            if (commitOrRestoreInstrRewrite(context, rewriteSnapshot, inst, ops))
                                changed = true;
                        }
                    }
                }
                else if (ops[3].microOp == MicroOp::ConvertFloatToInt && ops[0].reg.isInt())
                {
                    const auto itKnownSrc = known.find(ops[1].reg.packed);
                    if (itKnownSrc != known.end())
                    {
                        uint64_t immValue = 0;
                        if (foldConvertFloatToIntToBits(immValue, itKnownSrc->second.value, ops[2].opBits))
                        {
                            inst.op          = MicroInstrOpcode::LoadRegImm;
                            inst.numOperands = 3;
                            ops[1].opBits    = ops[2].opBits;
                            ops[2].valueU64  = immValue;
                            changed          = true;
                        }
                    }
                }
                else if (ops[3].microOp == MicroOp::FloatAdd ||
                         ops[3].microOp == MicroOp::FloatSubtract ||
                         ops[3].microOp == MicroOp::FloatMultiply ||
                         ops[3].microOp == MicroOp::FloatDivide)
                {
                    const auto itKnownDst = known.find(ops[0].reg.packed);
                    const auto itKnownSrc = known.find(ops[1].reg.packed);
                    if (itKnownDst != known.end() && itKnownSrc != known.end())
                    {
                        uint64_t foldedValue = 0;
                        if (foldFloatBinaryToBits(foldedValue, itKnownDst->second.value, itKnownSrc->second.value, ops[3].microOp, ops[2].opBits))
                            deferredKnownDef = std::pair{ops[0].reg.packed, foldedValue};
                    }
                }
                break;
            }
            case MicroInstrOpcode::CmpRegReg:
            {
                if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[1].reg.packed);
                if (itKnown != known.end())
                {
                    const uint64_t       immValue = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                    InstrRewriteSnapshot rewriteSnapshot;
                    captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                    inst.op          = MicroInstrOpcode::CmpRegImm;
                    inst.numOperands = 3;
                    ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                    ops[2].valueU64  = immValue;
                    if (commitOrRestoreInstrRewrite(context, rewriteSnapshot, inst, ops))
                    {
                        changed = true;
                    }
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (!ops[0].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[0].reg.packed);
                if (itKnown != known.end())
                {
                    const MicroOp          binaryOp     = ops[2].microOp;
                    const uint64_t         immValue     = ops[3].valueU64;
                    const MicroOpBits      opBits       = ops[1].opBits;
                    uint64_t               foldedValue  = 0;
                    auto                   safetyStatus = Math::FoldStatus::Ok;
                    const BinaryFoldResult foldResult   = tryFoldBinaryImmediateForPropagation(foldedValue, itKnown->second.value, immValue, binaryOp, opBits, &safetyStatus);
                    if (foldResult == BinaryFoldResult::Folded)
                    {
                        inst.op          = MicroInstrOpcode::LoadRegImm;
                        inst.numOperands = 3;
                        ops[1].opBits    = opBits;
                        ops[2].valueU64  = foldedValue;
                        changed          = true;

                        if (opBits == MicroOpBits::B64)
                        {
                            const auto itAddress = knownAddresses.find(ops[0].reg.packed);
                            if (itAddress != knownAddresses.end())
                            {
                                uint64_t updatedOffset = 0;
                                if (tryApplyUnsignedAddSubOffset(updatedOffset, itAddress->second, immValue, binaryOp))
                                    deferredAddressDef = std::pair{ops[0].reg.packed, updatedOffset};
                            }
                        }
                    }
                    else if (foldResult == BinaryFoldResult::SafetyError)
                    {
                        if (!MicroPassHelpers::isAddOrSubMicroOp(binaryOp))
                            return MicroPassHelpers::raiseFoldSafetyError(context, instRef, safetyStatus);
                    }
                }
                break;
            }
            case MicroInstrOpcode::OpUnaryReg:
            {
                if (!ops[0].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[0].reg.packed);
                if (itKnown != known.end())
                {
                    uint64_t               foldedValue = 0;
                    const Math::FoldStatus foldStatus  = foldUnaryImmediateToBits(foldedValue, itKnown->second.value, ops[2].microOp, ops[1].opBits);
                    if (foldStatus == Math::FoldStatus::Ok)
                    {
                        inst.op          = MicroInstrOpcode::LoadRegImm;
                        inst.numOperands = 3;
                        ops[2].valueU64  = foldedValue;
                        changed          = true;
                    }
                    else if (Math::isSafetyError(foldStatus))
                    {
                        return MicroPassHelpers::raiseFoldSafetyError(context, instRef, foldStatus);
                    }
                }
                break;
            }
            default:
                break;
        }

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
            {
                if (!ops[1].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[1].reg.packed);
                if (itKnown != known.end())
                {
                    const uint64_t       immValue = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                    InstrRewriteSnapshot rewriteSnapshot;
                    captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                    inst.op          = MicroInstrOpcode::LoadMemImm;
                    inst.numOperands = 4;
                    ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                    ops[2].valueU64  = rewriteSnapshot.operands[3].valueU64;
                    ops[3].valueU64  = immValue;
                    if (commitOrRestoreInstrRewrite(context, rewriteSnapshot, inst, ops))
                    {
                        changed = true;
                    }
                }
                break;
            }
            case MicroInstrOpcode::LoadAmcMemReg:
            {
                if (!ops[2].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[2].reg.packed);
                if (itKnown != known.end())
                {
                    const uint64_t       immValue = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[4].opBits);
                    InstrRewriteSnapshot rewriteSnapshot;
                    captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                    inst.op          = MicroInstrOpcode::LoadAmcMemImm;
                    inst.numOperands = 8;
                    ops[3].opBits    = rewriteSnapshot.operands[3].opBits;
                    ops[4].opBits    = rewriteSnapshot.operands[4].opBits;
                    ops[5].valueU64  = rewriteSnapshot.operands[5].valueU64;
                    ops[6].valueU64  = rewriteSnapshot.operands[6].valueU64;
                    ops[7].valueU64  = immValue;
                    if (commitOrRestoreInstrRewrite(context, rewriteSnapshot, inst, ops))
                    {
                        changed = true;
                    }
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryMemReg:
            {
                if (!ops[1].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[1].reg.packed);
                if (itKnown != known.end())
                {
                    const uint64_t       immValue = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                    InstrRewriteSnapshot rewriteSnapshot;
                    captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                    inst.op          = MicroInstrOpcode::OpBinaryMemImm;
                    inst.numOperands = 5;
                    ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                    ops[2].microOp   = rewriteSnapshot.operands[3].microOp;
                    ops[3].valueU64  = rewriteSnapshot.operands[4].valueU64;
                    ops[4].valueU64  = immValue;
                    if (commitOrRestoreInstrRewrite(context, rewriteSnapshot, inst, ops))
                    {
                        changed = true;
                    }
                }
                break;
            }
            case MicroInstrOpcode::CmpMemReg:
            {
                if (!ops[1].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[1].reg.packed);
                if (itKnown != known.end())
                {
                    const uint64_t       immValue = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                    InstrRewriteSnapshot rewriteSnapshot;
                    captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                    inst.op          = MicroInstrOpcode::CmpMemImm;
                    inst.numOperands = 4;
                    ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                    ops[2].valueU64  = rewriteSnapshot.operands[3].valueU64;
                    ops[3].valueU64  = immValue;
                    if (commitOrRestoreInstrRewrite(context, rewriteSnapshot, inst, ops))
                    {
                        changed = true;
                    }
                }
                break;
            }
            default:
                break;
        }

        updateCompareStateForInstruction(inst, ops, deferredKnownDef);

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        eraseKnownDefs(known, useDef.defs);
        eraseKnownAddressDefs(knownAddresses, useDef.defs);
        eraseKnownConstantPointerDefs(knownConstantPointers, useDef.defs);

        if (stackPointerReg.isValid() && definesRegisterInSet(useDef.defs, stackPointerReg))
        {
            knownStackSlots.clear();
            knownAddresses.clear();
            knownStackAddresses.clear();
        }

        if (useDef.isCall)
        {
            clearForCallBoundary(useDef.callConv);
            continue;
        }

        bool handledMemoryWrite = false;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemImm:
            {
                uint64_t stackOffset = 0;
                if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[2].valueU64))
                {
                    setKnownStackSlot(knownStackSlots, stackOffset, ops[1].opBits, ops[3].valueU64);
                    eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[1].opBits);
                    handledMemoryWrite = true;
                }
                break;
            }
            case MicroInstrOpcode::LoadMemReg:
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
                        bool           handledConstantCopy = false;
                        const uint32_t slotNumBytes        = microOpBitsNumBytes(ops[2].opBits);
                        if (it != storage.view().begin() &&
                            slotNumBytes &&
                            slotNumBytes <= 16)
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
                                    const uint64_t constantOffset = itConstPtr->second.offset + prevOps[3].valueU64;

                                    std::array<std::byte, 16> bytes{};
                                    if (tryGetPointerBytesRange(bytes, slotNumBytes, itConstPtr->second.pointer, constantOffset))
                                    {
                                        eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[2].opBits);
                                        setKnownStackSlotsFromBytes(knownStackSlots, stackOffset, std::span<const std::byte>{bytes.data(), slotNumBytes});
                                        handledConstantCopy = true;
                                    }
                                }
                            }
                        }

                        if (!handledConstantCopy)
                            eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[2].opBits);
                    }

                    if (ops[2].opBits == MicroOpBits::B64)
                    {
                        const auto itKnownAddress = knownAddresses.find(ops[1].reg.packed);
                        if (itKnownAddress != knownAddresses.end())
                            setKnownStackAddress(knownStackAddresses, stackOffset, itKnownAddress->second);
                        else
                            eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[2].opBits);
                    }
                    else
                    {
                        eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[2].opBits);
                    }

                    handledMemoryWrite = true;
                }
                break;
            }
            case MicroInstrOpcode::LoadAmcMemImm:
            {
                uint64_t stackOffset = 0;
                if (tryResolveStackOffsetForAmc(stackOffset, knownAddresses, known, stackPointerReg, ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64))
                {
                    setKnownStackSlot(knownStackSlots, stackOffset, ops[4].opBits, ops[7].valueU64);
                    eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[4].opBits);
                    handledMemoryWrite = true;
                }
                break;
            }
            case MicroInstrOpcode::LoadAmcMemReg:
            {
                uint64_t stackOffset = 0;
                if (tryResolveStackOffsetForAmc(stackOffset, knownAddresses, known, stackPointerReg, ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64))
                {
                    const auto itKnownReg = known.find(ops[2].reg.packed);
                    if (itKnownReg != known.end())
                        setKnownStackSlot(knownStackSlots, stackOffset, ops[4].opBits, itKnownReg->second.value);
                    else
                        eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[4].opBits);

                    if (ops[4].opBits == MicroOpBits::B64)
                    {
                        const auto itKnownAddress = knownAddresses.find(ops[2].reg.packed);
                        if (itKnownAddress != knownAddresses.end())
                            setKnownStackAddress(knownStackAddresses, stackOffset, itKnownAddress->second);
                        else
                            eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[4].opBits);
                    }
                    else
                    {
                        eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[4].opBits);
                    }

                    handledMemoryWrite = true;
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryMemImm:
            {
                uint64_t stackOffset = 0;
                if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[3].valueU64))
                {
                    uint64_t knownValue = 0;
                    if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[1].opBits))
                    {
                        uint64_t foldedValue = 0;
                        if (tryFoldBinaryImmediateForPropagation(foldedValue, knownValue, ops[4].valueU64, ops[2].microOp, ops[1].opBits) == BinaryFoldResult::Folded)
                            setKnownStackSlot(knownStackSlots, stackOffset, ops[1].opBits, foldedValue);
                        else
                            eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[1].opBits);
                    }
                    else
                    {
                        eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[1].opBits);
                    }

                    eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[1].opBits);
                    handledMemoryWrite = true;
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryMemReg:
            {
                uint64_t stackOffset = 0;
                if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[4].valueU64))
                {
                    uint64_t   knownValue = 0;
                    const auto itKnownReg = known.find(ops[1].reg.packed);
                    if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[2].opBits) && itKnownReg != known.end())
                    {
                        uint64_t foldedValue = 0;
                        if (tryFoldBinaryImmediateForPropagation(foldedValue, knownValue, itKnownReg->second.value, ops[3].microOp, ops[2].opBits) == BinaryFoldResult::Folded)
                            setKnownStackSlot(knownStackSlots, stackOffset, ops[2].opBits, foldedValue);
                        else
                            eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[2].opBits);
                    }
                    else
                    {
                        eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[2].opBits);
                    }

                    eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[2].opBits);
                    handledMemoryWrite = true;
                }
                break;
            }
            case MicroInstrOpcode::OpUnaryMem:
            {
                uint64_t stackOffset = 0;
                if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[0].reg, ops[3].valueU64))
                {
                    uint64_t knownValue = 0;
                    if (tryGetKnownStackSlotValue(knownValue, knownStackSlots, stackOffset, ops[1].opBits))
                    {
                        uint64_t               foldedValue = 0;
                        const Math::FoldStatus foldStatus  = foldUnaryImmediateToBits(foldedValue, knownValue, ops[2].microOp, ops[1].opBits);
                        if (foldStatus == Math::FoldStatus::Ok)
                            setKnownStackSlot(knownStackSlots, stackOffset, ops[1].opBits, foldedValue);
                        else if (Math::isSafetyError(foldStatus))
                            return MicroPassHelpers::raiseFoldSafetyError(context, instRef, foldStatus);
                        else
                            eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[1].opBits);
                    }
                    else
                    {
                        eraseOverlappingStackSlots(knownStackSlots, stackOffset, ops[1].opBits);
                    }

                    eraseOverlappingStackAddresses(knownStackAddresses, stackOffset, ops[1].opBits);
                    handledMemoryWrite = true;
                }
                break;
            }
            default:
                break;
        }

        if (MicroInstrInfo::isMemoryWriteInstruction(inst) && !handledMemoryWrite)
        {
            knownStackSlots.clear();
            knownStackAddresses.clear();
        }

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegImm:
                known[ops[0].reg.packed] = {
                    .value = MicroPassHelpers::normalizeToOpBits(ops[2].valueU64, ops[1].opBits),
                };
                break;
            case MicroInstrOpcode::LoadRegReg:
            {
                const auto itKnown = known.find(ops[1].reg.packed);
                if (itKnown != known.end())
                {
                    known[ops[0].reg.packed] = {
                        .value = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits),
                    };
                }
                break;
            }
            case MicroInstrOpcode::ClearReg:
                known[ops[0].reg.packed] = {
                    .value = 0,
                };
                break;
            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (!ops[0].reg.isInt())
                    break;

                const auto itKnown = known.find(ops[0].reg.packed);
                if (itKnown != known.end())
                {
                    uint64_t               foldedValue  = 0;
                    auto                   safetyStatus = Math::FoldStatus::Ok;
                    const BinaryFoldResult foldResult   = tryFoldBinaryImmediateForPropagation(foldedValue, itKnown->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits, &safetyStatus);
                    if (foldResult == BinaryFoldResult::Folded)
                    {
                        known[ops[0].reg.packed] = {
                            .value = foldedValue,
                        };
                    }
                    else if (foldResult == BinaryFoldResult::SafetyError)
                    {
                        if (!MicroPassHelpers::isAddOrSubMicroOp(ops[2].microOp))
                            return MicroPassHelpers::raiseFoldSafetyError(context, instRef, safetyStatus);
                    }
                }
                break;
            }
            default:
                break;
        }

        if (deferredKnownDef.has_value())
        {
            known[deferredKnownDef->first] = {
                .value = deferredKnownDef->second,
            };
        }

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegPtrReloc:
            {
                if (!ops[0].reg.isInt() || ops[1].opBits != MicroOpBits::B64)
                    break;

                bool       canTrackConstantPointer = false;
                const auto itRelocation            = relocationByInstructionRef.find(instRef);
                if (itRelocation != relocationByInstructionRef.end())
                {
                    const auto* relocation = itRelocation->second;
                    if (relocation &&
                        relocation->kind == MicroRelocation::Kind::ConstantAddress &&
                        relocation->constantRef.isValid())
                    {
                        canTrackConstantPointer = true;
                    }
                }

                if (canTrackConstantPointer && ops[2].valueU64)
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
                break;
            }
            case MicroInstrOpcode::LoadRegReg:
            {
                if (!ops[0].reg.isInt() || !ops[1].reg.isInt() || ops[2].opBits != MicroOpBits::B64)
                    break;

                const auto itConstPtr = knownConstantPointers.find(ops[1].reg.packed);
                if (itConstPtr != knownConstantPointers.end())
                {
                    knownConstantPointers[ops[0].reg.packed] = itConstPtr->second;
                }
                else
                {
                    knownConstantPointers.erase(ops[0].reg.packed);
                }
                break;
            }
            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (!ops[0].reg.isInt() || ops[1].opBits != MicroOpBits::B64)
                    break;

                const auto itConstPtr = knownConstantPointers.find(ops[0].reg.packed);
                if (itConstPtr != knownConstantPointers.end())
                {
                    auto     knownConstPtr = itConstPtr->second;
                    uint64_t updatedOffset = 0;
                    if (tryApplyUnsignedAddSubOffset(updatedOffset, knownConstPtr.offset, ops[3].valueU64, ops[2].microOp))
                    {
                        knownConstPtr.offset                     = updatedOffset;
                        knownConstantPointers[ops[0].reg.packed] = knownConstPtr;
                    }
                    else
                    {
                        knownConstantPointers.erase(ops[0].reg.packed);
                    }
                }
                break;
            }
            default:
                break;
        }

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAddrRegMem:
            {
                if (!ops[0].reg.isInt())
                    break;
                uint64_t stackOffset = 0;
                if (tryResolveStackOffset(stackOffset, knownAddresses, stackPointerReg, ops[1].reg, ops[3].valueU64))
                    knownAddresses[ops[0].reg.packed] = stackOffset;
                break;
            }
            case MicroInstrOpcode::LoadAddrAmcRegMem:
            {
                if (!ops[0].reg.isInt())
                    break;
                uint64_t stackOffset = 0;
                if (tryResolveStackOffsetForAmc(stackOffset, knownAddresses, known, stackPointerReg, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64))
                {
                    knownAddresses[ops[0].reg.packed] = stackOffset;
                }
                break;
            }
            case MicroInstrOpcode::LoadRegReg:
            {
                if (!ops[0].reg.isInt() || !ops[1].reg.isInt() || ops[2].opBits != MicroOpBits::B64)
                    break;
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
                break;
            }
            case MicroInstrOpcode::OpBinaryRegImm:
            {
                if (!ops[0].reg.isInt() || ops[1].opBits != MicroOpBits::B64)
                    break;
                const auto itAddress = knownAddresses.find(ops[0].reg.packed);
                if (itAddress != knownAddresses.end())
                {
                    uint64_t updatedOffset = 0;
                    if (tryApplyUnsignedAddSubOffset(updatedOffset, itAddress->second, ops[3].valueU64, ops[2].microOp))
                        knownAddresses[ops[0].reg.packed] = updatedOffset;
                }
                break;
            }
            default:
                break;
        }

        if (deferredAddressDef.has_value())
            knownAddresses[deferredAddressDef->first] = deferredAddressDef->second;

        clearControlFlowBoundaryForInstruction(inst, ops);
    }

    context.passChanged = changed;
    return Result::Continue;
}

void MicroConstantPropagationPass::clearRunContext()
{
    context_         = nullptr;
    storage_         = nullptr;
    operands_        = nullptr;
    stackPointerReg_ = {};
}

void MicroConstantPropagationPass::clearState()
{
    known_.clear();
    knownStackSlots_.clear();
    knownAddresses_.clear();
    knownStackAddresses_.clear();
    knownConstantPointers_.clear();
    compareState_ = {};
    relocationByInstructionRef_.clear();
    referencedLabels_.clear();
    clearRunContext();
}

void MicroConstantPropagationPass::initRunState(MicroPassContext& context)
{
    clearState();

    context_  = &context;
    storage_  = context.instructions;
    operands_ = context.operands;

    known_.reserve(64);
    knownStackSlots_.reserve(64);
    knownAddresses_.reserve(32);
    knownStackAddresses_.reserve(32);
    knownConstantPointers_.reserve(32);

    stackPointerReg_ = CallConv::get(context.callConvKind).stackPointer;
    if (context.encoder)
        stackPointerReg_ = context.encoder->stackPointerReg();

    if (context.builder)
    {
        const auto& relocations = context.builder->codeRelocations();
        relocationByInstructionRef_.reserve(relocations.size());
        for (const auto& relocation : relocations)
            relocationByInstructionRef_[relocation.instructionRef] = &relocation;
    }

    collectReferencedLabels();
}

void MicroConstantPropagationPass::collectReferencedLabels()
{
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    referencedLabels_.reserve(storage_->count());
    for (const MicroInstr& scanInst : storage_->view())
    {
        switch (scanInst.op)
        {
            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            {
                if (scanInst.numOperands < 3)
                    break;

                const auto* scanOps = scanInst.ops(*operands_);
                if (scanOps)
                    referencedLabels_.insert(MicroLabelRef(static_cast<uint32_t>(scanOps[2].valueU64)));
                break;
            }
            default:
                break;
        }
    }
}

void MicroConstantPropagationPass::updateCompareStateForInstruction(const MicroInstr& inst, MicroInstrOperand* ops, std::optional<std::pair<uint32_t, uint64_t>>& deferredKnownDef)
{
    switch (inst.op)
    {
        case MicroInstrOpcode::CmpRegImm:
        {
            if (!ops[0].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[0].reg.packed);
            if (itKnown != known_.end())
            {
                compareState_.valid  = true;
                compareState_.lhs    = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[1].opBits);
                compareState_.rhs    = MicroPassHelpers::normalizeToOpBits(ops[2].valueU64, ops[1].opBits);
                compareState_.opBits = ops[1].opBits;
            }
            else
            {
                compareState_.valid = false;
            }
            break;
        }
        case MicroInstrOpcode::CmpRegReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                break;

            const auto itKnownLhs = known_.find(ops[0].reg.packed);
            const auto itKnownRhs = known_.find(ops[1].reg.packed);
            if (itKnownLhs != known_.end() && itKnownRhs != known_.end())
            {
                compareState_.valid  = true;
                compareState_.lhs    = MicroPassHelpers::normalizeToOpBits(itKnownLhs->second.value, ops[2].opBits);
                compareState_.rhs    = MicroPassHelpers::normalizeToOpBits(itKnownRhs->second.value, ops[2].opBits);
                compareState_.opBits = ops[2].opBits;
            }
            else
            {
                compareState_.valid = false;
            }
            break;
        }
        case MicroInstrOpcode::CmpMemImm:
        {
            if (!ops[0].reg.isInt())
                break;

            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses_, stackPointerReg_, ops[0].reg, ops[2].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots_, stackOffset, ops[1].opBits))
                {
                    compareState_.valid  = true;
                    compareState_.lhs    = MicroPassHelpers::normalizeToOpBits(knownValue, ops[1].opBits);
                    compareState_.rhs    = MicroPassHelpers::normalizeToOpBits(ops[3].valueU64, ops[1].opBits);
                    compareState_.opBits = ops[1].opBits;
                }
                else
                {
                    compareState_.valid = false;
                }
            }
            else
            {
                compareState_.valid = false;
            }
            break;
        }
        case MicroInstrOpcode::CmpMemReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                break;

            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses_, stackPointerReg_, ops[0].reg, ops[3].valueU64))
            {
                uint64_t   knownValue = 0;
                const auto itKnownRhs = known_.find(ops[1].reg.packed);
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots_, stackOffset, ops[2].opBits) && itKnownRhs != known_.end())
                {
                    compareState_.valid  = true;
                    compareState_.lhs    = MicroPassHelpers::normalizeToOpBits(knownValue, ops[2].opBits);
                    compareState_.rhs    = MicroPassHelpers::normalizeToOpBits(itKnownRhs->second.value, ops[2].opBits);
                    compareState_.opBits = ops[2].opBits;
                }
                else
                {
                    compareState_.valid = false;
                }
            }
            else
            {
                compareState_.valid = false;
            }
            break;
        }
        case MicroInstrOpcode::SetCondReg:
        {
            if (!ops[0].reg.isInt() || !compareState_.valid)
                break;

            const std::optional<bool> condValue = MicroPassHelpers::evaluateCondition(ops[1].cpuCond, compareState_.lhs, compareState_.rhs, compareState_.opBits);
            if (condValue.has_value())
                deferredKnownDef = std::pair{ops[0].reg.packed, static_cast<uint64_t>(*condValue ? 1 : 0)};
            break;
        }
        default:
            if (MicroInstrInfo::definesCpuFlags(inst))
                compareState_.valid = false;
            break;
    }
}

void MicroConstantPropagationPass::clearControlFlowBoundaryForInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    bool clearForControlFlowBoundary = false;
    switch (inst.op)
    {
        case MicroInstrOpcode::Label:
        {
            if (ops && inst.numOperands >= 1)
            {
                const MicroLabelRef labelRef(static_cast<uint32_t>(ops[0].valueU64));
                clearForControlFlowBoundary = referencedLabels_.contains(labelRef);
            }
            else
            {
                clearForControlFlowBoundary = true;
            }
            break;
        }
        default:
            if (MicroInstrInfo::isTerminatorInstruction(inst))
                clearForControlFlowBoundary = true;
            break;
    }

    if (clearForControlFlowBoundary)
    {
        known_.clear();
        knownStackSlots_.clear();
        knownAddresses_.clear();
        knownStackAddresses_.clear();
        knownConstantPointers_.clear();
        compareState_.valid = false;
    }
}

void MicroConstantPropagationPass::clearForCallBoundary(CallConvKind callConvKind)
{
    const bool hasStackAddressArg = callHasStackAddressArgument(knownAddresses_, callConvKind);
    known_.clear();
    if (hasStackAddressArg)
        knownStackSlots_.clear();
    knownAddresses_.clear();
    knownStackAddresses_.clear();
    knownConstantPointers_.clear();
    compareState_.valid = false;
}

bool MicroConstantPropagationPass::tryResolveStackOffsetFromState(uint64_t& outOffset, MicroReg baseReg, uint64_t baseOffset) const
{
    return tryResolveStackOffset(outOffset, knownAddresses_, stackPointerReg_, baseReg, baseOffset);
}

bool MicroConstantPropagationPass::tryResolveStackOffsetForAmcFromState(uint64_t& outOffset, MicroReg baseReg, MicroReg mulReg, uint64_t mulValue, uint64_t addValue) const
{
    return tryResolveStackOffsetForAmc(outOffset, knownAddresses_, known_, stackPointerReg_, baseReg, mulReg, mulValue, addValue);
}

bool MicroConstantPropagationPass::rewriteMemoryBaseToKnownStack(const MicroInstr& inst, MicroInstrOperand* ops) const
{
    SWC_ASSERT(context_ != nullptr);
    return tryRewriteMemoryBaseToStack(*context_, inst, ops, stackPointerReg_, knownAddresses_);
}

bool MicroConstantPropagationPass::definesRegisterInSet(std::span<const MicroReg> defs, MicroReg reg)
{
    return definesRegister(defs, reg);
}

SWC_END_NAMESPACE();
