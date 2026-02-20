#include "pch.h"
#include "Backend/Micro/Passes/MicroBranchFoldingPass.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct KnownConstant
    {
        uint64_t    value  = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    struct CompareState
    {
        bool       valid  = false;
        uint64_t   lhs    = 0;
        uint64_t   rhs    = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    uint64_t normalizeToOpBits(uint64_t value, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B64)
            return value;
        return value & getOpBitsMask(opBits);
    }

    bool foldBinaryImmediate(uint64_t& outValue, uint64_t inValue, uint64_t immediate, MicroOp microOp, MicroOpBits opBits)
    {
        const uint64_t value = normalizeToOpBits(inValue, opBits);
        const uint64_t imm   = normalizeToOpBits(immediate, opBits);

        switch (microOp)
        {
            case MicroOp::Add:
                outValue = normalizeToOpBits(value + imm, opBits);
                return true;
            case MicroOp::Subtract:
                outValue = normalizeToOpBits(value - imm, opBits);
                return true;
            case MicroOp::And:
                outValue = normalizeToOpBits(value & imm, opBits);
                return true;
            case MicroOp::Or:
                outValue = normalizeToOpBits(value | imm, opBits);
                return true;
            case MicroOp::Xor:
                outValue = normalizeToOpBits(value ^ imm, opBits);
                return true;
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
            {
                const uint32_t numBits = getNumBits(opBits);
                if (!numBits)
                    return false;

                const uint64_t shiftAmount = std::min<uint64_t>(imm, numBits - 1);
                if (microOp == MicroOp::ShiftLeft)
                    outValue = normalizeToOpBits(value << shiftAmount, opBits);
                else if (microOp == MicroOp::ShiftRight)
                    outValue = normalizeToOpBits(value >> shiftAmount, opBits);
                else if (opBits == MicroOpBits::B8)
                    outValue = static_cast<uint8_t>(static_cast<int8_t>(value) >> shiftAmount);
                else if (opBits == MicroOpBits::B16)
                    outValue = static_cast<uint16_t>(static_cast<int16_t>(value) >> shiftAmount);
                else if (opBits == MicroOpBits::B32)
                    outValue = static_cast<uint32_t>(static_cast<int32_t>(value) >> shiftAmount);
                else if (opBits == MicroOpBits::B64)
                    outValue = static_cast<uint64_t>(static_cast<int64_t>(value) >> shiftAmount);
                else
                    return false;

                outValue = normalizeToOpBits(outValue, opBits);
                return true;
            }
            default:
                return false;
        }
    }

    bool isTerminator(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::JumpTable:
            case MicroInstrOpcode::Ret:
                return true;
            default:
                return false;
        }
    }

    int64_t toSigned(uint64_t value, MicroOpBits opBits)
    {
        const uint64_t normalized = normalizeToOpBits(value, opBits);
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
        const uint64_t lhsUnsigned = normalizeToOpBits(lhs, opBits);
        const uint64_t rhsUnsigned = normalizeToOpBits(rhs, opBits);
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

    bool                                         changed = false;
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
                        changed = true;
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
                compareState.lhs    = normalizeToOpBits(knownIt->second.value, ops[1].opBits);
                compareState.rhs    = normalizeToOpBits(ops[2].valueU64, ops[1].opBits);
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
                compareState.lhs    = normalizeToOpBits(knownIt->second.value, ops[1].opBits);
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
                compareState.lhs    = normalizeToOpBits(lhsIt->second.value, ops[2].opBits);
                compareState.rhs    = normalizeToOpBits(rhsIt->second.value, ops[2].opBits);
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
                .value  = normalizeToOpBits(ops[2].valueU64, ops[1].opBits),
                .opBits = ops[1].opBits,
            };
        }
        else if (inst.op == MicroInstrOpcode::ClearReg && ops[0].reg.isInt())
        {
            known[ops[0].reg.packed] = {
                .value  = 0,
                .opBits = ops[1].opBits,
            };
        }
        else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto sourceIt = known.find(ops[1].reg.packed);
            if (sourceIt != known.end())
            {
                known[ops[0].reg.packed] = {
                    .value  = normalizeToOpBits(sourceIt->second.value, ops[2].opBits),
                    .opBits = ops[2].opBits,
                };
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto valueIt = known.find(ops[0].reg.packed);
            if (valueIt != known.end())
            {
                uint64_t folded = 0;
                if (foldBinaryImmediate(folded, valueIt->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
                {
                    known[ops[0].reg.packed] = {
                        .value  = folded,
                        .opBits = ops[1].opBits,
                    };
                }
            }
        }

        if (inst.op == MicroInstrOpcode::Label || isTerminator(inst))
        {
            known.clear();
            compareState.valid = false;
        }
    }

    return changed;
}

SWC_END_NAMESPACE();
