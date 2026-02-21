#include "pch.h"
#include "Backend/Micro/Passes/Pass.BranchFolding.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"

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
}

bool MicroBranchFoldingPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                                        changed = false;
    std::unordered_map<uint32_t, KnownConstant> known;
    known.reserve(64);
    CompareState compareState{};

    MicroStorage&        storage  = *SWC_CHECK_NOT_NULL(context.instructions);
    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);
    for (auto it = storage.view().begin(); it != storage.view().end();)
    {
        const Ref   instRef = it.current;
        MicroInstr& inst    = *it;
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
        else if (inst.op == MicroInstrOpcode::CmpRegZero && ops[0].reg.isInt())
        {
            const auto knownIt = known.find(ops[0].reg.packed);
            if (knownIt != known.end())
            {
                compareState.valid  = true;
                compareState.lhs    = MicroOptimization::normalizeToOpBits(knownIt->second.value, ops[1].opBits);
                compareState.rhs    = 0;
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
        else if (inst.op != MicroInstrOpcode::Debug)
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
                uint64_t folded = 0;
                if (MicroOptimization::foldBinaryImmediate(folded, valueIt->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
                {
                    known[ops[0].reg.packed] = {
                        .value = folded,
                    };
                }
            }
        }

        if (inst.op == MicroInstrOpcode::Label || MicroInstrInfo::isTerminatorInstruction(inst))
        {
            known.clear();
            compareState.valid = false;
        }
    }

    return changed;
}

SWC_END_NAMESPACE();
