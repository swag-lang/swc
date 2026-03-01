#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.Private.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"

SWC_BEGIN_NAMESPACE();

Result MicroConstantPropagationPass::rewriteInstructionFromKnownValues(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef)
{
    SWC_ASSERT(context_ != nullptr);

    switch (inst.op)
    {
        case MicroInstrOpcode::LoadAmcRegMem:
        case MicroInstrOpcode::LoadRegMem:
        case MicroInstrOpcode::LoadSignedExtRegMem:
        case MicroInstrOpcode::LoadZeroExtRegMem:
            return rewriteLoadFromMemoryInstructions(inst, ops, deferredKnownDef, deferredAddressDef);

        case MicroInstrOpcode::LoadAddrRegMem:
        case MicroInstrOpcode::LoadRegReg:
        case MicroInstrOpcode::LoadSignedExtRegReg:
        case MicroInstrOpcode::LoadZeroExtRegReg:
            return rewriteLoadAndMoveInstructions(inst, ops, deferredAddressDef);

        case MicroInstrOpcode::OpBinaryRegMem:
        case MicroInstrOpcode::OpBinaryRegReg:
        case MicroInstrOpcode::CmpRegReg:
        case MicroInstrOpcode::OpBinaryRegImm:
        case MicroInstrOpcode::OpUnaryReg:
            return rewriteRegisterOperationInstructions(instRef, inst, ops, deferredKnownDef, deferredAddressDef);

        case MicroInstrOpcode::LoadMemReg:
        case MicroInstrOpcode::LoadAmcMemReg:
        case MicroInstrOpcode::OpBinaryMemReg:
        case MicroInstrOpcode::CmpMemReg:
            return rewriteMemoryOperandInstructions(inst, ops);

        default:
            break;
    }

    return Result::Continue;
}

Result MicroConstantPropagationPass::rewriteLoadFromMemoryInstructions(MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef) const
{
    SWC_ASSERT(context_ != nullptr);

    switch (inst.op)
    {
        case MicroInstrOpcode::LoadAmcRegMem:
        {
            if (!stackPointerReg_.isValid() || !ops[0].reg.isInt() || !ops[1].reg.isInt() || !ops[2].reg.isInt())
                break;

            uint64_t stackOffset = 0;
            if (!tryResolveStackOffsetForAmc(stackOffset, knownAddresses_, known_, stackPointerReg_, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64))
                break;

            InstrRewriteSnapshot rewriteSnapshot;
            captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);
            bool rewritten = false;

            uint64_t knownValue = 0;
            if (tryGetKnownStackSlotValue(knownValue, knownStackSlots_, stackOffset, ops[4].opBits))
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
                ops[1].reg       = stackPointerReg_;
                ops[2].opBits    = ops[4].opBits;
                ops[3].valueU64  = stackOffset;
                rewritten        = true;
            }

            if (rewritten)
            {
                if (commitOrRestoreInstrRewrite(*context_, rewriteSnapshot, inst, ops))
                    context_->passChanged = true;
            }

            uint64_t knownStackAddressOffset = 0;
            if (tryGetKnownStackAddress(knownStackAddressOffset, knownStackAddresses_, stackOffset, ops[3].opBits))
                deferredAddressDef = std::pair{ops[0].reg, knownStackAddressOffset};
            break;
        }

        case MicroInstrOpcode::LoadRegMem:
        {
            uint64_t stackOffset = 0;
            if (!tryResolveStackOffset(stackOffset, knownAddresses_, stackPointerReg_, ops[1].reg, ops[3].valueU64))
                break;

            uint64_t knownValue = 0;
            if (tryGetKnownStackSlotValue(knownValue, knownStackSlots_, stackOffset, ops[2].opBits))
            {
                const uint64_t normalizedValue = MicroPassHelpers::normalizeToOpBits(knownValue, ops[2].opBits);
                if (ops[0].reg.isInt())
                {
                    inst.op               = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands      = 3;
                    ops[1].opBits         = ops[2].opBits;
                    ops[2].valueU64       = normalizedValue;
                    context_->passChanged = true;
                }
                else
                {
                    deferredKnownDef = std::pair{ops[0].reg, normalizedValue};
                }
            }

            if (!ops[0].reg.isInt())
                break;

            uint64_t knownStackAddressOffset = 0;
            if (tryGetKnownStackAddress(knownStackAddressOffset, knownStackAddresses_, stackOffset, ops[2].opBits))
                deferredAddressDef = std::pair{ops[0].reg, knownStackAddressOffset};
            break;
        }

        case MicroInstrOpcode::LoadSignedExtRegMem:
        case MicroInstrOpcode::LoadZeroExtRegMem:
        {
            if (!ops[0].reg.isInt())
                break;

            uint64_t stackOffset = 0;
            if (!tryResolveStackOffset(stackOffset, knownAddresses_, stackPointerReg_, ops[1].reg, ops[4].valueU64))
                break;

            uint64_t knownValue = 0;
            if (!tryGetKnownStackSlotValue(knownValue, knownStackSlots_, stackOffset, ops[3].opBits))
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

            inst.op               = MicroInstrOpcode::LoadRegImm;
            inst.numOperands      = 3;
            ops[1].opBits         = ops[2].opBits;
            ops[2].valueU64       = immValue;
            context_->passChanged = true;
            break;
        }

        default:
            break;
    }

    return Result::Continue;
}

Result MicroConstantPropagationPass::rewriteLoadAndMoveInstructions(MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredAddressDef)
{
    SWC_ASSERT(context_ != nullptr);

    switch (inst.op)
    {
        case MicroInstrOpcode::LoadAddrRegMem:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt() || ops[1].reg.isInstructionPointer())
                break;

            const MicroReg baseReg    = ops[1].reg;
            const uint64_t baseOffset = ops[3].valueU64;
            const auto     itKnown    = known_.find(ops[1].reg);
            if (itKnown == known_.end())
                break;

            inst.op               = MicroInstrOpcode::LoadRegImm;
            inst.numOperands      = 3;
            ops[1].opBits         = ops[2].opBits;
            ops[2].valueU64       = MicroPassHelpers::normalizeToOpBits(itKnown->second.value + baseOffset, ops[2].opBits);
            context_->passChanged = true;

            if (ops[2].opBits != MicroOpBits::B64)
                break;

            const auto itAddress = knownAddresses_.find(baseReg);
            if (itAddress != knownAddresses_.end() && itAddress->second <= std::numeric_limits<uint64_t>::max() - baseOffset)
                deferredAddressDef = std::pair{ops[0].reg, itAddress->second + baseOffset};
            break;
        }

        case MicroInstrOpcode::LoadRegReg:
        {
            const MicroReg sourceReg = ops[1].reg;
            const auto     itKnown   = known_.find(ops[1].reg);
            if (itKnown != known_.end() && ops[0].reg.isInt())
            {
                inst.op               = MicroInstrOpcode::LoadRegImm;
                ops[1].opBits         = ops[2].opBits;
                ops[2].valueU64       = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                context_->passChanged = true;

                if (ops[2].opBits == MicroOpBits::B64)
                {
                    const auto itAddress = knownAddresses_.find(sourceReg);
                    if (itAddress != knownAddresses_.end())
                        deferredAddressDef = std::pair{ops[0].reg, itAddress->second};
                }
            }
            break;
        }

        case MicroInstrOpcode::LoadSignedExtRegReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[1].reg);
            if (itKnown != known_.end())
            {
                inst.op               = MicroInstrOpcode::LoadRegImm;
                inst.numOperands      = 3;
                ops[1].opBits         = ops[2].opBits;
                ops[2].valueU64       = signExtendToBits(itKnown->second.value, ops[3].opBits, ops[2].opBits);
                context_->passChanged = true;
            }
            break;
        }

        case MicroInstrOpcode::LoadZeroExtRegReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[1].reg);
            if (itKnown != known_.end())
            {
                inst.op               = MicroInstrOpcode::LoadRegImm;
                inst.numOperands      = 3;
                ops[1].opBits         = ops[2].opBits;
                ops[2].valueU64       = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                context_->passChanged = true;
            }
            break;
        }

        default:
            break;
    }

    return Result::Continue;
}

Result MicroConstantPropagationPass::rewriteRegisterOperationInstructions(MicroInstrRef instRef, MicroInstr& inst, MicroInstrOperand* ops, DeferredDef& deferredKnownDef, DeferredDef& deferredAddressDef)
{
    SWC_ASSERT(context_ != nullptr);

    switch (inst.op)
    {
        case MicroInstrOpcode::OpBinaryRegMem:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                break;

            uint64_t stackOffset = 0;
            if (tryResolveStackOffset(stackOffset, knownAddresses_, stackPointerReg_, ops[1].reg, ops[4].valueU64))
            {
                uint64_t knownValue = 0;
                if (tryGetKnownStackSlotValue(knownValue, knownStackSlots_, stackOffset, ops[2].opBits))
                {
                    const uint64_t immValue   = MicroPassHelpers::normalizeToOpBits(knownValue, ops[2].opBits);
                    const auto     itKnownDst = known_.find(ops[0].reg);

                    if (itKnownDst != known_.end())
                    {
                        uint64_t foldedValue  = 0;
                        auto     safetyStatus = Math::FoldStatus::Ok;
                        switch (tryFoldBinaryImmediateForPropagation(foldedValue, itKnownDst->second.value, immValue, ops[3].microOp, ops[2].opBits, &safetyStatus))
                        {
                            case BinaryFoldResult::Folded:
                                inst.op               = MicroInstrOpcode::LoadRegImm;
                                inst.numOperands      = 3;
                                ops[1].opBits         = ops[2].opBits;
                                ops[2].valueU64       = foldedValue;
                                context_->passChanged = true;
                                break;
                            case BinaryFoldResult::SafetyError:
                                if (!MicroPassHelpers::isAddOrSubMicroOp(ops[3].microOp))
                                    return MicroPassHelpers::raiseFoldSafetyError(*context_, instRef, safetyStatus);
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
                        if (commitOrRestoreInstrRewrite(*context_, rewriteSnapshot, inst, ops))
                            context_->passChanged = true;
                    }
                }
            }
            break;
        }

        case MicroInstrOpcode::OpBinaryRegReg:
        {
            if (ops[0].reg.isInt() && ops[1].reg.isInt())
            {
                const auto itKnownSrc = known_.find(ops[1].reg);
                if (itKnownSrc != known_.end())
                {
                    const uint64_t immValue   = MicroPassHelpers::normalizeToOpBits(itKnownSrc->second.value, ops[2].opBits);
                    const auto     itKnownDst = known_.find(ops[0].reg);

                    if (itKnownDst != known_.end())
                    {
                        uint64_t foldedValue  = 0;
                        auto     safetyStatus = Math::FoldStatus::Ok;
                        switch (tryFoldBinaryImmediateForPropagation(foldedValue, itKnownDst->second.value, immValue, ops[3].microOp, ops[2].opBits, &safetyStatus))
                        {
                            case BinaryFoldResult::Folded:
                                inst.op               = MicroInstrOpcode::LoadRegImm;
                                inst.numOperands      = 3;
                                ops[1].opBits         = ops[2].opBits;
                                ops[2].valueU64       = foldedValue;
                                context_->passChanged = true;
                                break;
                            case BinaryFoldResult::SafetyError:
                                if (!MicroPassHelpers::isAddOrSubMicroOp(ops[3].microOp))
                                    return MicroPassHelpers::raiseFoldSafetyError(*context_, instRef, safetyStatus);
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
                        if (commitOrRestoreInstrRewrite(*context_, rewriteSnapshot, inst, ops))
                            context_->passChanged = true;
                    }
                }
            }
            else if (ops[3].microOp == MicroOp::ConvertFloatToInt && ops[0].reg.isInt())
            {
                const auto itKnownSrc = known_.find(ops[1].reg);
                if (itKnownSrc != known_.end())
                {
                    uint64_t immValue = 0;
                    if (foldConvertFloatToIntToBits(immValue, itKnownSrc->second.value, ops[2].opBits))
                    {
                        inst.op               = MicroInstrOpcode::LoadRegImm;
                        inst.numOperands      = 3;
                        ops[1].opBits         = ops[2].opBits;
                        ops[2].valueU64       = immValue;
                        context_->passChanged = true;
                    }
                }
            }
            else if (ops[3].microOp == MicroOp::FloatAdd ||
                     ops[3].microOp == MicroOp::FloatSubtract ||
                     ops[3].microOp == MicroOp::FloatMultiply ||
                     ops[3].microOp == MicroOp::FloatDivide)
            {
                const auto itKnownDst = known_.find(ops[0].reg);
                const auto itKnownSrc = known_.find(ops[1].reg);
                if (itKnownDst != known_.end() && itKnownSrc != known_.end())
                {
                    uint64_t foldedValue = 0;
                    if (foldFloatBinaryToBits(foldedValue, itKnownDst->second.value, itKnownSrc->second.value, ops[3].microOp, ops[2].opBits))
                        deferredKnownDef = std::pair{ops[0].reg, foldedValue};
                }
            }
            break;
        }

        case MicroInstrOpcode::CmpRegReg:
        {
            if (!ops[0].reg.isInt() || !ops[1].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[1].reg);
            if (itKnown != known_.end())
            {
                const uint64_t       immValue = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                InstrRewriteSnapshot rewriteSnapshot;
                captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                inst.op          = MicroInstrOpcode::CmpRegImm;
                inst.numOperands = 3;
                ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                ops[2].valueU64  = immValue;
                if (commitOrRestoreInstrRewrite(*context_, rewriteSnapshot, inst, ops))
                    context_->passChanged = true;
            }
            break;
        }

        case MicroInstrOpcode::OpBinaryRegImm:
        {
            if (!ops[0].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[0].reg);
            if (itKnown != known_.end())
            {
                const MicroOp          binaryOp     = ops[2].microOp;
                const uint64_t         immValue     = ops[3].valueU64;
                const MicroOpBits      opBits       = ops[1].opBits;
                uint64_t               foldedValue  = 0;
                auto                   safetyStatus = Math::FoldStatus::Ok;
                const BinaryFoldResult foldResult   = tryFoldBinaryImmediateForPropagation(foldedValue, itKnown->second.value, immValue, binaryOp, opBits, &safetyStatus);
                if (foldResult == BinaryFoldResult::Folded)
                {
                    inst.op               = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands      = 3;
                    ops[1].opBits         = opBits;
                    ops[2].valueU64       = foldedValue;
                    context_->passChanged = true;

                    if (opBits == MicroOpBits::B64)
                    {
                        const auto itAddress = knownAddresses_.find(ops[0].reg);
                        if (itAddress != knownAddresses_.end())
                        {
                            uint64_t updatedOffset = 0;
                            if (tryApplyUnsignedAddSubOffset(updatedOffset, itAddress->second, immValue, binaryOp))
                                deferredAddressDef = std::pair{ops[0].reg, updatedOffset};
                        }
                    }
                }
                else if (foldResult == BinaryFoldResult::SafetyError)
                {
                    if (!MicroPassHelpers::isAddOrSubMicroOp(binaryOp))
                        return MicroPassHelpers::raiseFoldSafetyError(*context_, instRef, safetyStatus);
                }
            }
            break;
        }

        case MicroInstrOpcode::OpUnaryReg:
        {
            if (!ops[0].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[0].reg);
            if (itKnown != known_.end())
            {
                uint64_t               foldedValue = 0;
                const Math::FoldStatus foldStatus  = foldUnaryImmediateToBits(foldedValue, itKnown->second.value, ops[2].microOp, ops[1].opBits);
                if (foldStatus == Math::FoldStatus::Ok)
                {
                    inst.op               = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands      = 3;
                    ops[2].valueU64       = foldedValue;
                    context_->passChanged = true;
                }
                else if (Math::isSafetyError(foldStatus))
                {
                    return MicroPassHelpers::raiseFoldSafetyError(*context_, instRef, foldStatus);
                }
            }
            break;
        }

        default:
            break;
    }

    return Result::Continue;
}

Result MicroConstantPropagationPass::rewriteMemoryOperandInstructions(MicroInstr& inst, MicroInstrOperand* ops)
{
    SWC_ASSERT(context_ != nullptr);

    switch (inst.op)
    {
        case MicroInstrOpcode::LoadMemReg:
        {
            if (!ops[1].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[1].reg);
            if (itKnown != known_.end())
            {
                const uint64_t       immValue = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                InstrRewriteSnapshot rewriteSnapshot;
                captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                inst.op          = MicroInstrOpcode::LoadMemImm;
                inst.numOperands = 4;
                ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                ops[2].valueU64  = rewriteSnapshot.operands[3].valueU64;
                ops[3].valueU64  = immValue;
                if (commitOrRestoreInstrRewrite(*context_, rewriteSnapshot, inst, ops))
                    context_->passChanged = true;
            }
            break;
        }

        case MicroInstrOpcode::LoadAmcMemReg:
        {
            if (!ops[2].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[2].reg);
            if (itKnown != known_.end())
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
                if (commitOrRestoreInstrRewrite(*context_, rewriteSnapshot, inst, ops))
                    context_->passChanged = true;
            }
            break;
        }

        case MicroInstrOpcode::OpBinaryMemReg:
        {
            if (!ops[1].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[1].reg);
            if (itKnown != known_.end())
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
                if (commitOrRestoreInstrRewrite(*context_, rewriteSnapshot, inst, ops))
                    context_->passChanged = true;
            }
            break;
        }

        case MicroInstrOpcode::CmpMemReg:
        {
            if (!ops[1].reg.isInt())
                break;

            const auto itKnown = known_.find(ops[1].reg);
            if (itKnown != known_.end())
            {
                const uint64_t       immValue = MicroPassHelpers::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                InstrRewriteSnapshot rewriteSnapshot;
                captureInstrRewriteSnapshot(rewriteSnapshot, inst, ops);

                inst.op          = MicroInstrOpcode::CmpMemImm;
                inst.numOperands = 4;
                ops[1].opBits    = rewriteSnapshot.operands[2].opBits;
                ops[2].valueU64  = rewriteSnapshot.operands[3].valueU64;
                ops[3].valueU64  = immValue;
                if (commitOrRestoreInstrRewrite(*context_, rewriteSnapshot, inst, ops))
                    context_->passChanged = true;
            }
            break;
        }

        default:
            break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
