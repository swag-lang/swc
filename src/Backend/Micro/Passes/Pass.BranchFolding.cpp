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
    int64_t toSigned(uint64_t value, MicroOpBits opBits)
    {
        const uint64_t normalized = MicroPassHelpers::normalizeToOpBits(value, opBits);
        switch (opBits)
        {
            case MicroOpBits::B8:
                return static_cast<int8_t>(normalized);
            case MicroOpBits::B16:
                return static_cast<int16_t>(normalized);
            case MicroOpBits::B32:
                return static_cast<int32_t>(normalized);
            case MicroOpBits::B64:
                return static_cast<int64_t>(normalized);
            default:
                return static_cast<int64_t>(normalized);
        }
    }

    std::optional<bool> evaluateCondition(MicroCond condition, uint64_t lhs, uint64_t rhs, MicroOpBits opBits)
    {
        const uint64_t lhsUnsigned = MicroPassHelpers::normalizeToOpBits(lhs, opBits);
        const uint64_t rhsUnsigned = MicroPassHelpers::normalizeToOpBits(rhs, opBits);
        const int64_t  lhsSigned   = toSigned(lhs, opBits);
        const int64_t  rhsSigned   = toSigned(rhs, opBits);

        switch (condition)
        {
            case MicroCond::Unconditional:
                return true;
            case MicroCond::Equal:
            case MicroCond::Zero:
                return lhsUnsigned == rhsUnsigned;
            case MicroCond::NotEqual:
            case MicroCond::NotZero:
                return lhsUnsigned != rhsUnsigned;
            case MicroCond::Above:
                return lhsUnsigned > rhsUnsigned;
            case MicroCond::AboveOrEqual:
                return lhsUnsigned >= rhsUnsigned;
            case MicroCond::Below:
                return lhsUnsigned < rhsUnsigned;
            case MicroCond::BelowOrEqual:
            case MicroCond::NotAbove:
                return lhsUnsigned <= rhsUnsigned;
            case MicroCond::Greater:
                return lhsSigned > rhsSigned;
            case MicroCond::GreaterOrEqual:
                return lhsSigned >= rhsSigned;
            case MicroCond::Less:
                return lhsSigned < rhsSigned;
            case MicroCond::LessOrEqual:
                return lhsSigned <= rhsSigned;
            default:
                return std::nullopt;
        }
    }

    bool tryFoldAddSubSignedNoOverflow(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits)
    {
        if (op != MicroOp::Add && op != MicroOp::Subtract)
            return false;

        const int64_t lhsSigned = toSigned(lhs, opBits);
        const int64_t rhsSigned = toSigned(rhs, opBits);
        int64_t       minValue  = std::numeric_limits<int64_t>::min();
        int64_t       maxValue  = std::numeric_limits<int64_t>::max();
        switch (opBits)
        {
            case MicroOpBits::B8:
                minValue = std::numeric_limits<int8_t>::min();
                maxValue = std::numeric_limits<int8_t>::max();
                break;
            case MicroOpBits::B16:
                minValue = std::numeric_limits<int16_t>::min();
                maxValue = std::numeric_limits<int16_t>::max();
                break;
            case MicroOpBits::B32:
                minValue = std::numeric_limits<int32_t>::min();
                maxValue = std::numeric_limits<int32_t>::max();
                break;
            case MicroOpBits::B64:
                minValue = std::numeric_limits<int64_t>::min();
                maxValue = std::numeric_limits<int64_t>::max();
                break;
            default:
                return false;
        }

        int64_t resultSigned = 0;
        if (op == MicroOp::Add)
        {
            if ((rhsSigned > 0 && lhsSigned > maxValue - rhsSigned) ||
                (rhsSigned < 0 && lhsSigned < minValue - rhsSigned))
            {
                return false;
            }

            resultSigned = lhsSigned + rhsSigned;
        }
        else
        {
            if ((rhsSigned < 0 && lhsSigned > maxValue + rhsSigned) ||
                (rhsSigned > 0 && lhsSigned < minValue + rhsSigned))
            {
                return false;
            }

            resultSigned = lhsSigned - rhsSigned;
        }

        outValue = MicroPassHelpers::normalizeToOpBits(static_cast<uint64_t>(resultSigned), opBits);
        return true;
    }

    bool isAddOrSub(MicroOp op)
    {
        return op == MicroOp::Add || op == MicroOp::Subtract;
    }
}

Result MicroBranchFoldingPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool changed = false;
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
    for (const MicroInstr& scanInst : storage.view())
    {
        if ((scanInst.op == MicroInstrOpcode::JumpCond || scanInst.op == MicroInstrOpcode::JumpCondImm) && scanInst.numOperands >= 3)
        {
            const auto* scanOps = scanInst.ops(operands);
            if (scanOps)
                referencedLabels_.insert(MicroLabelRef(static_cast<uint32_t>(scanOps[2].valueU64)));
        }
    }

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
                const std::optional<bool> jumpTaken = evaluateCondition(ops[0].cpuCond, compareLhs_, compareRhs_, compareOpBits_);
                if (jumpTaken.has_value())
                {
                    if (*jumpTaken)
                    {
                        if (ops[0].cpuCond != MicroCond::Unconditional)
                        {
                            ops[0].cpuCond = MicroCond::Unconditional;
                            changed        = true;
                        }
                    }
                    else
                    {
                        storage.erase(instRef);
                        changed       = true;
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
                    if (tryFoldAddSubSignedNoOverflow(folded, valueIt->second, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
                    {
                        knownValues_[ops[0].reg.packed] = folded;
                    }
                    else if (!isAddOrSub(ops[2].microOp))
                    {
                        return MicroPassHelpers::raiseFoldSafetyError(context, instRef, foldStatus);
                    }
                }
            }
        }

        bool clearForControlFlowBoundary = false;
        if (inst.op == MicroInstrOpcode::Label)
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
        }
        else if (MicroInstrInfo::isTerminatorInstruction(inst))
        {
            clearForControlFlowBoundary = true;
        }

        if (clearForControlFlowBoundary)
        {
            knownValues_.clear();
            compareValid_ = false;
        }
    }

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
