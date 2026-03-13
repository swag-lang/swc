#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isIndirectTrackedStackWrite(const MicroPassContext& context, const MicroReg baseReg)
    {
        return baseReg.isValid() && !MicroPassHelpers::isStackBaseRegister(context, baseReg);
    }
}

void MicroConstantPropagationPass::invalidateStateForDefinitions(const MicroInstrUseDef& useDef)
{
    eraseKnownDefs(useDef.defs);
    eraseKnownAddressDefs(useDef.defs);
    eraseKnownConstantPointerDefs(useDef.defs);

    if (stackPointerReg_.isValid() && microRegSpanContains(useDef.defs, stackPointerReg_))
    {
        knownStackSlots_.clear();
        knownAddresses_.clear();
        knownStackAddresses_.clear();
    }
}

// Update stack-slot facts after memory writes. Kept separate from rewrite
// logic to make dataflow effects explicit.
Result MicroConstantPropagationPass::trackKnownMemoryWrite(MicroInstrRef instRef, const MicroInstr* prevInst, const MicroInstrOperand* prevOps, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    SWC_ASSERT(context_ != nullptr);
    bool handledMemoryWrite = false;

    switch (inst.op)
    {
        case MicroInstrOpcode::LoadMemImm:
        case MicroInstrOpcode::LoadMemReg:
        case MicroInstrOpcode::LoadAmcMemImm:
        case MicroInstrOpcode::LoadAmcMemReg:
            SWC_RESULT(trackStackStoreInstruction(prevInst, prevOps, inst, ops, handledMemoryWrite));
            break;

        case MicroInstrOpcode::OpBinaryMemImm:
        case MicroInstrOpcode::OpBinaryMemReg:
        case MicroInstrOpcode::OpUnaryMem:
            SWC_RESULT(trackStackMutationInstruction(instRef, inst, ops, handledMemoryWrite));
            break;

        default:
            break;
    }

    if (MicroInstrInfo::isMemoryWriteInstruction(inst) && !handledMemoryWrite)
    {
        knownStackSlots_.clear();
        knownStackAddresses_.clear();
    }

    return Result::Continue;
}

Result MicroConstantPropagationPass::trackStackStoreInstruction(const MicroInstr* prevInst, const MicroInstrOperand* prevOps, const MicroInstr& inst, const MicroInstrOperand* ops, bool& handledMemoryWrite)
{
    switch (inst.op)
    {
        case MicroInstrOpcode::LoadMemImm:
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, ops[0].reg, ops[2].valueU64))
            {
                setKnownStackSlot(stackOffset, ops[1].opBits, ops[3].valueU64);
                eraseOverlappingStackAddresses(stackOffset, ops[1].opBits);
                handledMemoryWrite = true;
                if (isIndirectTrackedStackWrite(*context_, ops[0].reg))
                {
                    knownStackSlots_.clear();
                    knownStackAddresses_.clear();
                }
            }
            break;
        }

        case MicroInstrOpcode::LoadMemReg:
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, ops[0].reg, ops[3].valueU64))
            {
                const auto itKnownReg = known_.find(ops[1].reg);
                if (itKnownReg != known_.end())
                    setKnownStackSlot(stackOffset, ops[2].opBits, itKnownReg->second.value);
                else if (!tryTrackConstantPointerStackCopy(stackOffset, ops[2].opBits, ops[1].reg, prevInst, prevOps))
                    eraseOverlappingStackSlots(stackOffset, ops[2].opBits);

                if (ops[2].opBits == MicroOpBits::B64)
                {
                    const auto itKnownAddress = knownAddresses_.find(ops[1].reg);
                    if (itKnownAddress != knownAddresses_.end())
                        setKnownStackAddress(stackOffset, itKnownAddress->second);
                    else
                        eraseOverlappingStackAddresses(stackOffset, ops[2].opBits);
                }
                else
                    eraseOverlappingStackAddresses(stackOffset, ops[2].opBits);

                handledMemoryWrite = true;
                if (isIndirectTrackedStackWrite(*context_, ops[0].reg))
                {
                    knownStackSlots_.clear();
                    knownStackAddresses_.clear();
                }
            }
            break;
        }

        case MicroInstrOpcode::LoadAmcMemImm:
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetForAmc(stackOffset, ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64))
            {
                setKnownStackSlot(stackOffset, ops[4].opBits, ops[7].valueU64);
                eraseOverlappingStackAddresses(stackOffset, ops[4].opBits);
                handledMemoryWrite = true;
                if (isIndirectTrackedStackWrite(*context_, ops[0].reg))
                {
                    knownStackSlots_.clear();
                    knownStackAddresses_.clear();
                }
            }
            break;
        }

        case MicroInstrOpcode::LoadAmcMemReg:
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetForAmc(stackOffset, ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64))
            {
                const auto itKnownReg = known_.find(ops[2].reg);
                if (itKnownReg != known_.end())
                    setKnownStackSlot(stackOffset, ops[4].opBits, itKnownReg->second.value);
                else
                    eraseOverlappingStackSlots(stackOffset, ops[4].opBits);

                if (ops[4].opBits == MicroOpBits::B64)
                {
                    const auto itKnownAddress = knownAddresses_.find(ops[2].reg);
                    if (itKnownAddress != knownAddresses_.end())
                        setKnownStackAddress(stackOffset, itKnownAddress->second);
                    else
                        eraseOverlappingStackAddresses(stackOffset, ops[4].opBits);
                }
                else
                    eraseOverlappingStackAddresses(stackOffset, ops[4].opBits);

                handledMemoryWrite = true;
                if (isIndirectTrackedStackWrite(*context_, ops[0].reg))
                {
                    knownStackSlots_.clear();
                    knownStackAddresses_.clear();
                }
            }
            break;
        }

        default:
            break;
    }

    return Result::Continue;
}

Result MicroConstantPropagationPass::trackStackMutationInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops, bool& handledMemoryWrite)
{
    SWC_ASSERT(context_ != nullptr);
    switch (inst.op)
    {
        case MicroInstrOpcode::OpBinaryMemImm:
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, ops[0].reg, ops[3].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, stackOffset, ops[1].opBits))
                {
                    uint64_t foldedValue = 0;
                    if (tryFoldBinaryImmediateForPropagation(foldedValue, knownValue, ops[4].valueU64, ops[2].microOp, ops[1].opBits) == BinaryFoldResult::Folded)
                        setKnownStackSlot(stackOffset, ops[1].opBits, foldedValue);
                    else
                        eraseOverlappingStackSlots(stackOffset, ops[1].opBits);
                }
                else
                    eraseOverlappingStackSlots(stackOffset, ops[1].opBits);

                eraseOverlappingStackAddresses(stackOffset, ops[1].opBits);
                handledMemoryWrite = true;
                if (isIndirectTrackedStackWrite(*context_, ops[0].reg))
                {
                    knownStackSlots_.clear();
                    knownStackAddresses_.clear();
                }
            }
            break;
        }

        case MicroInstrOpcode::OpBinaryMemReg:
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, ops[0].reg, ops[4].valueU64))
            {
                uint64_t   knownValue = 0;
                const auto itKnownReg = known_.find(ops[1].reg);
                if (tryGetKnownStackSlotValue(knownValue, stackOffset, ops[2].opBits) && itKnownReg != known_.end())
                {
                    uint64_t foldedValue = 0;
                    if (tryFoldBinaryImmediateForPropagation(foldedValue, knownValue, itKnownReg->second.value, ops[3].microOp, ops[2].opBits) == BinaryFoldResult::Folded)
                        setKnownStackSlot(stackOffset, ops[2].opBits, foldedValue);
                    else
                        eraseOverlappingStackSlots(stackOffset, ops[2].opBits);
                }
                else
                    eraseOverlappingStackSlots(stackOffset, ops[2].opBits);

                eraseOverlappingStackAddresses(stackOffset, ops[2].opBits);
                handledMemoryWrite = true;
                if (isIndirectTrackedStackWrite(*context_, ops[0].reg))
                {
                    knownStackSlots_.clear();
                    knownStackAddresses_.clear();
                }
            }
            break;
        }

        case MicroInstrOpcode::OpUnaryMem:
        {
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, ops[0].reg, ops[3].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, stackOffset, ops[1].opBits))
                {
                    uint64_t               foldedValue = 0;
                    const Math::FoldStatus foldStatus  = foldUnaryImmediateToBits(foldedValue, knownValue, ops[2].microOp, ops[1].opBits);
                    if (foldStatus == Math::FoldStatus::Ok)
                        setKnownStackSlot(stackOffset, ops[1].opBits, foldedValue);
                    else if (Math::isSafetyError(foldStatus))
                        return MicroPassHelpers::raiseFoldSafetyError(*context_, instRef, foldStatus);
                    else
                        eraseOverlappingStackSlots(stackOffset, ops[1].opBits);
                }
                else
                    eraseOverlappingStackSlots(stackOffset, ops[1].opBits);

                eraseOverlappingStackAddresses(stackOffset, ops[1].opBits);
                handledMemoryWrite = true;
                if (isIndirectTrackedStackWrite(*context_, ops[0].reg))
                {
                    knownStackSlots_.clear();
                    knownStackAddresses_.clear();
                }
            }
            break;
        }

        default:
            break;
    }

    return Result::Continue;
}

bool MicroConstantPropagationPass::tryTrackConstantPointerStackCopy(uint64_t stackOffset, MicroOpBits slotOpBits, MicroReg sourceReg, const MicroInstr* prevInst, const MicroInstrOperand* prevOps)
{
    if (!prevInst || !prevOps)
        return false;

    const uint32_t slotNumBytes = getNumBytes(slotOpBits);
    if (!slotNumBytes || slotNumBytes > 16)
        return false;

    if (prevInst->op != MicroInstrOpcode::LoadRegMem)
        return false;

    if (prevOps[0].reg != sourceReg || prevOps[2].opBits != slotOpBits || !prevOps[1].reg.isInt())
        return false;

    const auto itConstPtr = knownConstantPointers_.find(prevOps[1].reg);
    if (itConstPtr == knownConstantPointers_.end())
        return false;
    if (constantPointerRangeHasRelocation(itConstPtr->second, slotNumBytes))
        return false;

    const uint64_t            constantOffset = itConstPtr->second.offset + prevOps[3].valueU64;
    std::array<std::byte, 16> bytes{};
    if (!tryGetPointerBytesRange(bytes, slotNumBytes, itConstPtr->second.pointer, constantOffset))
        return false;

    eraseOverlappingStackSlots(stackOffset, slotOpBits);
    setKnownStackSlotsFromBytes(stackOffset, std::span<const std::byte>{bytes.data(), slotNumBytes});
    return true;
}

Result MicroConstantPropagationPass::updateKnownRegistersForInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    SWC_ASSERT(context_ != nullptr);
    switch (inst.op)
    {
        case MicroInstrOpcode::LoadRegImm:
            known_[ops[0].reg] = {
                .value = MicroPassHelpers::normalizeToOpBits(ops[2].valueU64, ops[1].opBits),
            };
            break;

        case MicroInstrOpcode::LoadRegReg:
        {
            const auto itKnown = known_.find(ops[1].reg);
            if (itKnown != known_.end())
            {
                known_[ops[0].reg] = {
                    .value = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits),
                };
            }
            break;
        }

        case MicroInstrOpcode::ClearReg:
            known_[ops[0].reg] = {
                .value = 0,
            };
            break;

        case MicroInstrOpcode::OpBinaryRegImm:
        {
            if (!ops[0].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[0].reg);
            if (itKnown != known_.end())
            {
                uint64_t               foldedValue  = 0;
                auto                   safetyStatus = Math::FoldStatus::Ok;
                const BinaryFoldResult foldResult   = tryFoldBinaryImmediateForPropagation(foldedValue, itKnown->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits, &safetyStatus);
                if (foldResult == BinaryFoldResult::Folded)
                {
                    known_[ops[0].reg] = {
                        .value = foldedValue,
                    };
                }
                else if (foldResult == BinaryFoldResult::SafetyError)
                {
                    if (!MicroPassHelpers::isAddOrSubMicroOp(ops[2].microOp))
                        return MicroPassHelpers::raiseFoldSafetyError(*context_, instRef, safetyStatus);
                }
            }
            break;
        }

        default:
            break;
    }

    return Result::Continue;
}

void MicroConstantPropagationPass::applyDeferredKnownDefinition(const DeferredDef& deferredKnownDef)
{
    if (deferredKnownDef.has_value())
    {
        known_[deferredKnownDef->first] = {
            .value = deferredKnownDef->second,
        };
    }
}

void MicroConstantPropagationPass::updateKnownConstantPointersForInstruction(MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
{
    switch (inst.op)
    {
        case MicroInstrOpcode::LoadRegPtrReloc:
        {
            if (!ops[0].reg.isInt() || ops[1].opBits != MicroOpBits::B64)
                break;

            bool       canTrackConstantPointer = false;
            const auto itRelocation            = relocationByInstructionRef_.find(instRef);
            if (itRelocation != relocationByInstructionRef_.end())
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
                knownConstantPointers_[ops[0].reg] = {
                    .pointer     = ops[2].valueU64,
                    .offset      = 0,
                    .constantRef = itRelocation->second->constantRef,
                };
            }
            else
            {
                knownConstantPointers_.erase(ops[0].reg);
            }
            break;
        }

        case MicroInstrOpcode::LoadRegReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt() || ops[2].opBits != MicroOpBits::B64)
                break;

            const auto itConstPtr = knownConstantPointers_.find(ops[1].reg);
            if (itConstPtr != knownConstantPointers_.end())
            {
                knownConstantPointers_[ops[0].reg] = itConstPtr->second;
            }
            else
            {
                knownConstantPointers_.erase(ops[0].reg);
            }
            break;
        }

        case MicroInstrOpcode::OpBinaryRegImm:
        {
            if (!ops[0].reg.isInt() || ops[1].opBits != MicroOpBits::B64)
                break;

            const auto itConstPtr = knownConstantPointers_.find(ops[0].reg);
            if (itConstPtr != knownConstantPointers_.end())
            {
                auto     knownConstPtr = itConstPtr->second;
                uint64_t updatedOffset = 0;
                if (tryApplyUnsignedAddSubOffset(updatedOffset, knownConstPtr.offset, ops[3].valueU64, ops[2].microOp))
                {
                    knownConstPtr.offset               = updatedOffset;
                    knownConstantPointers_[ops[0].reg] = knownConstPtr;
                }
                else
                {
                    knownConstantPointers_.erase(ops[0].reg);
                }
            }
            break;
        }

        default:
            break;
    }
}

void MicroConstantPropagationPass::updateKnownAddressesForInstruction(const MicroInstr& inst, const MicroInstrOperand* ops)
{
    switch (inst.op)
    {
        case MicroInstrOpcode::LoadAddrRegMem:
        {
            if (!ops[0].reg.isInt())
                break;
            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, ops[1].reg, ops[3].valueU64))
                knownAddresses_[ops[0].reg] = stackOffset;
            break;
        }
        case MicroInstrOpcode::LoadAddrAmcRegMem:
        {
            if (!ops[0].reg.isInt())
                break;
            uint64_t stackOffset = 0;
            if (tryResolveStackOffsetForAmc(stackOffset, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64))
            {
                knownAddresses_[ops[0].reg] = stackOffset;
            }
            break;
        }
        case MicroInstrOpcode::LoadRegReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt() || ops[2].opBits != MicroOpBits::B64)
                break;
            if (ops[1].reg == stackPointerReg_)
            {
                knownAddresses_[ops[0].reg] = 0;
            }
            else
            {
                const auto itAddress = knownAddresses_.find(ops[1].reg);
                if (itAddress != knownAddresses_.end())
                    knownAddresses_[ops[0].reg] = itAddress->second;
            }
            break;
        }
        case MicroInstrOpcode::OpBinaryRegImm:
        {
            if (!ops[0].reg.isInt() || ops[1].opBits != MicroOpBits::B64)
                break;
            const auto itAddress = knownAddresses_.find(ops[0].reg);
            if (itAddress != knownAddresses_.end())
            {
                uint64_t updatedOffset = 0;
                if (tryApplyUnsignedAddSubOffset(updatedOffset, itAddress->second, ops[3].valueU64, ops[2].microOp))
                    knownAddresses_[ops[0].reg] = updatedOffset;
            }
            break;
        }
        default:
            break;
    }
}

void MicroConstantPropagationPass::applyDeferredAddressDefinition(const DeferredDef& deferredAddressDef)
{
    if (deferredAddressDef.has_value())
        knownAddresses_[deferredAddressDef->first] = deferredAddressDef->second;
}

SWC_END_NAMESPACE();
