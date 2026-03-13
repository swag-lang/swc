#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

void MicroConstantPropagationPass::eraseOverlappingStackSlots(uint64_t offset, MicroOpBits opBits)
{
    const uint32_t slotSize = getNumBytes(opBits);
    if (!slotSize)
    {
        knownStackSlots_.clear();
        return;
    }

    for (auto it = knownStackSlots_.begin(); it != knownStackSlots_.end();)
    {
        const uint32_t knownSize = getNumBytes(it->first.opBits);
        if (MicroPassHelpers::rangesOverlap(offset, slotSize, it->first.offset, knownSize))
            it = knownStackSlots_.erase(it);
        else
            ++it;
    }
}

void MicroConstantPropagationPass::setKnownStackSlot(uint64_t offset, MicroOpBits opBits, uint64_t value)
{
    eraseOverlappingStackSlots(offset, opBits);
    knownStackSlots_[{.offset = offset, .opBits = opBits}] = {
        .value = MicroPassHelpers::normalizeToOpBits(value, opBits),
    };
}

void MicroConstantPropagationPass::eraseOverlappingStackAddresses(uint64_t offset, MicroOpBits opBits)
{
    const uint32_t slotSize = getNumBytes(opBits);
    if (!slotSize)
    {
        knownStackAddresses_.clear();
        return;
    }

    for (auto it = knownStackAddresses_.begin(); it != knownStackAddresses_.end();)
    {
        if (MicroPassHelpers::rangesOverlap(offset, slotSize, it->first, sizeof(uint64_t)))
            it = knownStackAddresses_.erase(it);
        else
            ++it;
    }
}

void MicroConstantPropagationPass::setKnownStackAddress(uint64_t stackSlotOffset, uint64_t stackAddressOffset)
{
    eraseOverlappingStackAddresses(stackSlotOffset, MicroOpBits::B64);
    knownStackAddresses_[stackSlotOffset] = stackAddressOffset;
}

bool MicroConstantPropagationPass::tryGetKnownStackAddress(uint64_t& outStackAddressOffset, uint64_t stackSlotOffset, MicroOpBits opBits) const
{
    if (opBits != MicroOpBits::B64)
        return false;

    const auto it = knownStackAddresses_.find(stackSlotOffset);
    if (it == knownStackAddresses_.end())
        return false;

    outStackAddressOffset = it->second;
    return true;
}

bool MicroConstantPropagationPass::tryGetKnownStackSlotValue(uint64_t& outValue, uint64_t offset, MicroOpBits opBits) const
{
    const auto it = knownStackSlots_.find({.offset = offset, .opBits = opBits});
    if (it != knownStackSlots_.end())
    {
        outValue = it->second.value;
        return true;
    }

    const uint32_t wantedSize = getNumBytes(opBits);
    if (!wantedSize || wantedSize > sizeof(uint64_t))
        return false;

    for (const auto& [knownKey, knownValue] : knownStackSlots_)
    {
        const uint32_t knownSize = getNumBytes(knownKey.opBits);
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

bool MicroConstantPropagationPass::tryResolveStackOffset(uint64_t& outOffset, MicroReg baseReg, uint64_t baseOffset) const
{
    if (baseReg == stackPointerReg_)
    {
        outOffset = baseOffset;
        return true;
    }

    const auto itAddress = knownAddresses_.find(baseReg);
    if (itAddress == knownAddresses_.end())
        return false;

    outOffset = itAddress->second + baseOffset;
    return true;
}

bool MicroConstantPropagationPass::tryResolveStackOffsetForAmc(uint64_t& outOffset, MicroReg baseReg, MicroReg mulReg, uint64_t mulValue, uint64_t addValue) const
{
    uint64_t baseOffset = 0;
    if (!tryResolveStackOffset(baseOffset, baseReg, 0))
        return false;

    const auto itKnownMul = known_.find(mulReg);
    if (itKnownMul == known_.end())
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

bool MicroConstantPropagationPass::callHasStackAddressArgument(CallConvKind callConvKind) const
{
    const CallConv& callConv = CallConv::get(callConvKind);
    for (const MicroReg argReg : callConv.intArgRegs)
    {
        if (knownAddresses_.contains(argReg))
            return true;
    }

    return false;
}

void MicroConstantPropagationPass::eraseKnownDefs(MicroRegSpan defs)
{
    for (const MicroReg reg : defs)
        known_.erase(reg);
}

void MicroConstantPropagationPass::eraseKnownAddressDefs(MicroRegSpan defs)
{
    for (const MicroReg reg : defs)
        knownAddresses_.erase(reg);
}

void MicroConstantPropagationPass::eraseKnownConstantPointerDefs(MicroRegSpan defs)
{
    for (const MicroReg reg : defs)
        knownConstantPointers_.erase(reg);
}

bool MicroConstantPropagationPass::tryGetPointerBytesRange(std::array<std::byte, 16>& outBytes, uint32_t numBytes, uint64_t pointer, uint64_t offset)
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

bool MicroConstantPropagationPass::constantPointerRangeHasRelocation(const KnownConstantPointer& constantPointer, const uint32_t numBytes) const
{
    if (!context_ || !context_->taskContext)
        return true;
    if (constantPointer.constantRef.isInvalid())
        return true;
    if (!numBytes)
        return false;

    uint32_t  shardIndex = 0;
    const Ref baseOffset = context_->taskContext->cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(constantPointer.pointer));
    if (baseOffset == INVALID_REF)
        return true;

    const DataSegment& segment    = context_->taskContext->cstMgr().shardDataSegment(shardIndex);
    const uint64_t     rangeBegin = static_cast<uint64_t>(baseOffset) + constantPointer.offset;
    const uint64_t     rangeEnd   = rangeBegin + numBytes;
    constexpr uint64_t relocSize  = sizeof(uint64_t);
    DataSegmentAllocation allocation;
    if (!segment.findAllocation(allocation, static_cast<uint32_t>(rangeBegin)))
        return true;

    const uint64_t allocBegin = allocation.offset;
    const uint64_t allocEnd   = allocBegin + allocation.size;
    if (rangeBegin < allocBegin || rangeEnd > allocEnd)
        return true;

    for (const auto& relocation : segment.relocations())
    {
        const uint64_t relocBegin = relocation.offset;
        if (relocBegin < allocBegin || relocBegin >= allocEnd)
            continue;
        if (MicroPassHelpers::rangesOverlap(rangeBegin, numBytes, relocBegin, relocSize))
            return true;
    }

    return false;
}

void MicroConstantPropagationPass::setKnownStackSlotsFromBytes(uint64_t baseOffset, std::span<const std::byte> bytes)
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
        setKnownStackSlot(baseOffset + byteOffset, chunkBits, chunkValue);
        byteOffset += chunkSize;
    }
}

uint64_t MicroConstantPropagationPass::signExtendToBits(uint64_t value, MicroOpBits srcBits, MicroOpBits dstBits)
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

bool MicroConstantPropagationPass::foldFloatBinaryToBits(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits)
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

bool MicroConstantPropagationPass::foldConvertFloatToIntToBits(uint64_t& outValue, uint64_t srcBits, MicroOpBits opBits)
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

MicroConstantPropagationPass::BinaryFoldResult MicroConstantPropagationPass::tryFoldBinaryImmediateForPropagation(uint64_t&         outValue,
                                                                                                                  uint64_t          lhs,
                                                                                                                  uint64_t          rhs,
                                                                                                                  MicroOp           op,
                                                                                                                  MicroOpBits       opBits,
                                                                                                                  Math::FoldStatus* outSafetyStatus)
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

bool MicroConstantPropagationPass::tryApplyUnsignedAddSubOffset(uint64_t& outValue, uint64_t inValue, uint64_t delta, MicroOp op)
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

void MicroConstantPropagationPass::captureInstrRewriteSnapshot(InstrRewriteSnapshot& outSnapshot, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    SWC_ASSERT(ops != nullptr);
    SWC_ASSERT(inst.numOperands <= InstrRewriteSnapshot::K_MAX_OPERANDS);

    outSnapshot.op          = inst.op;
    outSnapshot.numOperands = inst.numOperands;
    for (uint32_t idx = 0; idx < outSnapshot.numOperands; ++idx)
        outSnapshot.operands[idx] = ops[idx];
}

void MicroConstantPropagationPass::restoreInstrRewriteSnapshot(const InstrRewriteSnapshot& snapshot, MicroInstr& inst, MicroInstrOperand* ops)
{
    SWC_ASSERT(ops != nullptr);

    inst.op          = snapshot.op;
    inst.numOperands = snapshot.numOperands;
    for (uint32_t idx = 0; idx < snapshot.numOperands; ++idx)
        ops[idx] = snapshot.operands[idx];
}

bool MicroConstantPropagationPass::commitOrRestoreInstrRewrite(const InstrRewriteSnapshot& snapshot, MicroInstr& inst, MicroInstrOperand* ops) const
{
    SWC_ASSERT(context_ != nullptr);
    if (!MicroPassHelpers::violatesEncoderConformance(*context_, inst, ops))
        return true;

    restoreInstrRewriteSnapshot(snapshot, inst, ops);
    return false;
}

Math::FoldStatus MicroConstantPropagationPass::foldUnaryImmediateToBits(uint64_t& outValue, uint64_t inValue, MicroOp microOp, MicroOpBits opBits)
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

SWC_END_NAMESPACE();
