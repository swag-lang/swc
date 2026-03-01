#include "pch.h"
#include "Backend/Micro/Passes/Pass.BranchFolding.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Backend/Micro/MicroPassContext.h"

// Folds branch decisions when compare inputs are compile-time constants.
// Example: cmp r1, 42; jz L1 -> jmp L1 (if r1 is known 42).
// Example: cmp r1, 42; jz L1 -> <remove jump> (if r1 is known != 42).
// This reduces control-flow overhead and unlocks later CFG cleanup.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct KnownConstant
    {
        uint64_t value = 0;
    };

    struct CompareState
    {
        bool        valid  = false;
        uint64_t    lhs    = 0;
        uint64_t    rhs    = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    int64_t toSigned(uint64_t value, MicroOpBits opBits)
    {
        const uint64_t normalized = MicroOptimization::normalizeToOpBits(value, opBits);
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
        const uint64_t lhsUnsigned = MicroOptimization::normalizeToOpBits(lhs, opBits);
        const uint64_t rhsUnsigned = MicroOptimization::normalizeToOpBits(rhs, opBits);
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

        outValue = MicroOptimization::normalizeToOpBits(static_cast<uint64_t>(resultSigned), opBits);
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

    bool                                        changed = false;
    std::unordered_map<uint32_t, KnownConstant> known;
    known.reserve(64);
    CompareState compareState{};

    MicroStorage&                     storage  = *context.instructions;
    MicroOperandStorage&              operands = *context.operands;
    std::unordered_set<MicroLabelRef> referencedLabels;
    referencedLabels.reserve(storage.count());
    for (const MicroInstr& scanInst : storage.view())
    {
        if ((scanInst.op == MicroInstrOpcode::JumpCond || scanInst.op == MicroInstrOpcode::JumpCondImm) && scanInst.numOperands >= 3)
        {
            const auto* scanOps = scanInst.ops(operands);
            if (scanOps)
                referencedLabels.insert(MicroLabelRef(static_cast<uint32_t>(scanOps[2].valueU64)));
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
            if (compareState.valid)
            {
                const std::optional<bool> jumpTaken = evaluateCondition(ops[0].cpuCond, compareState.lhs, compareState.rhs, compareState.opBits);
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
                        changed            = true;
                        compareState.valid = false;
                        continue;
                    }
                }
            }

            compareState.valid = false;
        }
        else if (inst.op == MicroInstrOpcode::CmpRegImm && ops[0].reg.isInt())
        {
            const auto knownIt = known.find(ops[0].reg.packed);
            if (knownIt != known.end())
            {
                compareState.valid  = true;
                compareState.lhs    = MicroOptimization::normalizeToOpBits(knownIt->second.value, ops[1].opBits);
                compareState.rhs    = MicroOptimization::normalizeToOpBits(ops[2].valueU64, ops[1].opBits);
                compareState.opBits = ops[1].opBits;
            }
            else
            {
                compareState.valid = false;
            }
        }
        else if (inst.op == MicroInstrOpcode::CmpRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto lhsIt = known.find(ops[0].reg.packed);
            const auto rhsIt = known.find(ops[1].reg.packed);
            if (lhsIt != known.end() && rhsIt != known.end())
            {
                compareState.valid  = true;
                compareState.lhs    = MicroOptimization::normalizeToOpBits(lhsIt->second.value, ops[2].opBits);
                compareState.rhs    = MicroOptimization::normalizeToOpBits(rhsIt->second.value, ops[2].opBits);
                compareState.opBits = ops[2].opBits;
            }
            else
            {
                compareState.valid = false;
            }
        }
        else
        {
            compareState.valid = false;
        }

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        for (const MicroReg defReg : useDef.defs)
            known.erase(defReg.packed);

        if (useDef.isCall)
        {
            known.clear();
            compareState.valid = false;
            continue;
        }

        if (inst.op == MicroInstrOpcode::LoadRegImm && ops[0].reg.isInt())
        {
            known[ops[0].reg.packed] = {
                .value = MicroOptimization::normalizeToOpBits(ops[2].valueU64, ops[1].opBits),
            };
        }
        else if (inst.op == MicroInstrOpcode::ClearReg && ops[0].reg.isInt())
        {
            known[ops[0].reg.packed] = {
                .value = 0,
            };
        }
        else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto sourceIt = known.find(ops[1].reg.packed);
            if (sourceIt != known.end())
            {
                known[ops[0].reg.packed] = {
                    .value = MicroOptimization::normalizeToOpBits(sourceIt->second.value, ops[2].opBits),
                };
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto valueIt = known.find(ops[0].reg.packed);
            if (valueIt != known.end())
            {
                uint64_t               folded     = 0;
                const Math::FoldStatus foldStatus = MicroOptimization::foldBinaryImmediate(folded, valueIt->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
                if (foldStatus == Math::FoldStatus::Ok)
                {
                    known[ops[0].reg.packed] = {
                        .value = folded,
                    };
                }
                else if (Math::isSafetyError(foldStatus))
                {
                    if (tryFoldAddSubSignedNoOverflow(folded, valueIt->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
                    {
                        known[ops[0].reg.packed] = {
                            .value = folded,
                        };
                    }
                    else if (!isAddOrSub(ops[2].microOp))
                    {
                        return MicroOptimization::raiseFoldSafetyError(context, instRef, foldStatus);
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
                clearForControlFlowBoundary = referencedLabels.contains(labelRef);
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
            known.clear();
            compareState.valid = false;
        }
    }

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
