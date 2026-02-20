#include "pch.h"
#include "Backend/Micro/Passes/MicroConstantPropagationPass.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct KnownConstant
    {
        uint64_t    value  = 0;
        MicroOpBits opBits = MicroOpBits::B64;
    };

    uint64_t normalizeToOpBits(uint64_t value, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B64)
            return value;

        const uint64_t mask = getOpBitsMask(opBits);
        return value & mask;
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
                else
                {
                    if (opBits == MicroOpBits::B8)
                        outValue = static_cast<uint8_t>(value);
                    else if (opBits == MicroOpBits::B16)
                        outValue = static_cast<uint16_t>(value);
                    else if (opBits == MicroOpBits::B32)
                        outValue = static_cast<uint32_t>(value);
                    else if (opBits == MicroOpBits::B64)
                        outValue = static_cast<uint64_t>(static_cast<int64_t>(value) >> shiftAmount);
                    else
                        return false;
                }

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

    void eraseKnownDefs(std::unordered_map<uint32_t, KnownConstant>& known, std::span<const MicroReg> defs)
    {
        for (const MicroReg reg : defs)
        {
            known.erase(reg.packed);
        }
    }
}

bool MicroConstantPropagationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                                         changed = false;
    std::unordered_map<uint32_t, KnownConstant> known;
    known.reserve(64);

    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);
    for (MicroInstr& inst : context.instructions->view())
    {
        MicroInstrOperand* ops = inst.ops(operands);
        if (inst.op == MicroInstrOpcode::LoadRegReg)
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end() && ops[0].reg.isInt())
            {
                inst.op          = MicroInstrOpcode::LoadRegImm;
                ops[1].opBits    = ops[2].opBits;
                ops[2].valueU64  = normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                changed          = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto itKnown = known.find(ops[0].reg.packed);
            if (itKnown != known.end())
            {
                uint64_t foldedValue = 0;
                if (foldBinaryImmediate(foldedValue, itKnown->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
                {
                    inst.op          = MicroInstrOpcode::LoadRegImm;
                    inst.numOperands = 3;
                    ops[2].valueU64  = foldedValue;
                    changed          = true;
                }
            }
        }

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        eraseKnownDefs(known, useDef.defs);

        if (useDef.isCall)
        {
            known.clear();
            continue;
        }

        if (inst.op == MicroInstrOpcode::LoadRegImm && ops[0].reg.isInt())
        {
            known[ops[0].reg.packed] = {
                .value  = normalizeToOpBits(ops[2].valueU64, ops[1].opBits),
                .opBits = ops[1].opBits,
            };
        }
        else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end())
            {
                known[ops[0].reg.packed] = {
                    .value  = normalizeToOpBits(itKnown->second.value, ops[2].opBits),
                    .opBits = ops[2].opBits,
                };
            }
        }
        else if (inst.op == MicroInstrOpcode::ClearReg && ops[0].reg.isInt())
        {
            known[ops[0].reg.packed] = {
                .value  = 0,
                .opBits = ops[1].opBits,
            };
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto itKnown = known.find(ops[0].reg.packed);
            if (itKnown != known.end())
            {
                uint64_t foldedValue = 0;
                if (foldBinaryImmediate(foldedValue, itKnown->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
                {
                    known[ops[0].reg.packed] = {
                        .value  = foldedValue,
                        .opBits = ops[1].opBits,
                    };
                }
            }
        }

        if (inst.op == MicroInstrOpcode::Label || isTerminator(inst))
            known.clear();
    }

    return changed;
}

SWC_END_NAMESPACE();
