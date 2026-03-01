#include "pch.h"
#include "Backend/Micro/Passes/Pass.BranchFolding.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"

// Folds branch decisions when compare inputs are compile-time constants.
// Example: cmp r1, 42; jz L1 -> jmp L1 (if r1 is known 42).
// Example: cmp r1, 42; jz L1 -> <remove jump> (if r1 is known != 42).
// This reduces control-flow overhead and unlocks later CFG cleanup.

SWC_BEGIN_NAMESPACE();

namespace
{
}

Result MicroBranchFoldingPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    knownValues_.clear();
    knownValues_.reserve(64);
    referencedLabels_.clear();
    compareValid_  = false;
    compareLhs_    = 0;
    compareRhs_    = 0;
    compareOpBits_ = MicroOpBits::B64;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;
    referencedLabels_.reserve(storage.count());
    MicroPassHelpers::collectReferencedLabels(storage, operands, referencedLabels_, true);

    for (auto it = storage.view().begin(); it != storage.view().end();)
    {
        const MicroInstrRef instRef = it.current;
        const MicroInstr&   inst    = *it;
        ++it;

        MicroInstrOperand* ops = inst.ops(operands);
        if (inst.op == MicroInstrOpcode::JumpCond || inst.op == MicroInstrOpcode::JumpCondImm)
        {
            if (compareValid_)
            {
                const std::optional<bool> jumpTaken = MicroPassHelpers::evaluateCondition(ops[0].cpuCond, compareLhs_, compareRhs_, compareOpBits_);
                if (jumpTaken.has_value())
                {
                    if (*jumpTaken)
                    {
                        if (ops[0].cpuCond != MicroCond::Unconditional)
                        {
                            ops[0].cpuCond = MicroCond::Unconditional;
                            context.passChanged = true;
                        }
                    }
                    else
                    {
                        storage.erase(instRef);
                        context.passChanged = true;
                        compareValid_ = false;
                        continue;
                    }
                }
            }

            compareValid_ = false;
        }
        else if (inst.op == MicroInstrOpcode::CmpRegImm && ops[0].reg.isInt())
        {
            const auto knownIt = knownValues_.find(ops[0].reg.packed);
            if (knownIt != knownValues_.end())
            {
                compareValid_  = true;
                compareLhs_    = MicroPassHelpers::normalizeToOpBits(knownIt->second, ops[1].opBits);
                compareRhs_    = MicroPassHelpers::normalizeToOpBits(ops[2].valueU64, ops[1].opBits);
                compareOpBits_ = ops[1].opBits;
            }
            else
            {
                compareValid_ = false;
            }
        }
        else if (inst.op == MicroInstrOpcode::CmpRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto lhsIt = knownValues_.find(ops[0].reg.packed);
            const auto rhsIt = knownValues_.find(ops[1].reg.packed);
            if (lhsIt != knownValues_.end() && rhsIt != knownValues_.end())
            {
                compareValid_  = true;
                compareLhs_    = MicroPassHelpers::normalizeToOpBits(lhsIt->second, ops[2].opBits);
                compareRhs_    = MicroPassHelpers::normalizeToOpBits(rhsIt->second, ops[2].opBits);
                compareOpBits_ = ops[2].opBits;
            }
            else
            {
                compareValid_ = false;
            }
        }
        else
        {
            compareValid_ = false;
        }

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        for (const MicroReg defReg : useDef.defs)
            knownValues_.erase(defReg.packed);

        if (useDef.isCall)
        {
            knownValues_.clear();
            compareValid_ = false;
            continue;
        }

        if (inst.op == MicroInstrOpcode::LoadRegImm && ops[0].reg.isInt())
        {
            knownValues_[ops[0].reg.packed] = MicroPassHelpers::normalizeToOpBits(ops[2].valueU64, ops[1].opBits);
        }
        else if (inst.op == MicroInstrOpcode::ClearReg && ops[0].reg.isInt())
        {
            knownValues_[ops[0].reg.packed] = 0;
        }
        else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto sourceIt = knownValues_.find(ops[1].reg.packed);
            if (sourceIt != knownValues_.end())
            {
                knownValues_[ops[0].reg.packed] = MicroPassHelpers::normalizeToOpBits(sourceIt->second, ops[2].opBits);
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto valueIt = knownValues_.find(ops[0].reg.packed);
            if (valueIt != knownValues_.end())
            {
                uint64_t               folded     = 0;
                const Math::FoldStatus foldStatus = MicroPassHelpers::foldBinaryImmediate(folded, valueIt->second, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
                if (foldStatus == Math::FoldStatus::Ok)
                {
                    knownValues_[ops[0].reg.packed] = folded;
                }
                else if (Math::isSafetyError(foldStatus))
                {
                    if (MicroPassHelpers::tryFoldAddSubSignedNoOverflow(folded, valueIt->second, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
                    {
                        knownValues_[ops[0].reg.packed] = folded;
                    }
                    else if (!MicroPassHelpers::isAddOrSubMicroOp(ops[2].microOp))
                    {
                        return MicroPassHelpers::raiseFoldSafetyError(context, instRef, foldStatus);
                    }
                }
            }
        }

        if (MicroPassHelpers::shouldClearDataflowStateOnControlFlowBoundary(inst, ops, referencedLabels_))
        {
            knownValues_.clear();
            compareValid_ = false;
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
