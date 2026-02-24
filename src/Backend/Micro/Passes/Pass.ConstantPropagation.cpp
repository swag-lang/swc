#include "pch.h"
#include "Backend/Micro/Passes/Pass.ConstantPropagation.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroOptimization.h"

// Propagates known integer constants through register operations.
// Example: load r1, 5; add r2, r1  ->  add r2, 5.
// Example: load r1, 5; shl r1, 1    ->  load r1, 10.
// This removes dynamic work and creates simpler instruction forms.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct KnownConstant
    {
        uint64_t value = 0;
    };

    void eraseKnownDefs(std::unordered_map<uint32_t, KnownConstant>& known, std::span<const MicroReg> defs)
    {
        for (const MicroReg reg : defs)
        {
            known.erase(reg.packed);
        }
    }

    uint64_t signExtendToBits(uint64_t value, MicroOpBits srcBits, MicroOpBits dstBits)
    {
        const uint64_t normalizedSrc = MicroOptimization::normalizeToOpBits(value, srcBits);

        switch (srcBits)
        {
            case MicroOpBits::B8:
                return MicroOptimization::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int8_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B16:
                return MicroOptimization::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int16_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B32:
                return MicroOptimization::normalizeToOpBits(static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(normalizedSrc))), dstBits);
            case MicroOpBits::B64:
                return MicroOptimization::normalizeToOpBits(normalizedSrc, dstBits);
            default:
                return MicroOptimization::normalizeToOpBits(normalizedSrc, dstBits);
        }
    }
}

bool MicroConstantPropagationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                                        changed = false;
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
                inst.op         = MicroInstrOpcode::LoadRegImm;
                ops[1].opBits   = ops[2].opBits;
                ops[2].valueU64 = MicroOptimization::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                changed         = true;
            }
        }
        else if ((inst.op == MicroInstrOpcode::LoadSignedExtRegReg || inst.op == MicroInstrOpcode::LoadZeroExtRegReg) && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end())
            {
                uint64_t immValue = 0;
                if (inst.op == MicroInstrOpcode::LoadSignedExtRegReg)
                    immValue = signExtendToBits(itKnown->second.value, ops[3].opBits, ops[2].opBits);
                else
                    immValue = MicroOptimization::normalizeToOpBits(itKnown->second.value, ops[2].opBits);

                inst.op          = MicroInstrOpcode::LoadRegImm;
                inst.numOperands = 3;
                ops[1].opBits    = ops[2].opBits;
                ops[2].valueU64  = immValue;
                changed          = true;
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnownSrc = known.find(ops[1].reg.packed);
            if (itKnownSrc != known.end())
            {
                const uint64_t immValue   = MicroOptimization::normalizeToOpBits(itKnownSrc->second.value, ops[2].opBits);
                const auto     itKnownDst = known.find(ops[0].reg.packed);

                if (itKnownDst != known.end())
                {
                    uint64_t foldedValue = 0;
                    if (MicroOptimization::foldBinaryImmediate(foldedValue, itKnownDst->second.value, immValue, ops[3].microOp, ops[2].opBits))
                    {
                        inst.op          = MicroInstrOpcode::LoadRegImm;
                        inst.numOperands = 3;
                        ops[1].opBits    = ops[2].opBits;
                        ops[2].valueU64  = foldedValue;
                        changed          = true;
                    }
                }
                else
                {
                    const MicroInstrOpcode originalOp  = inst.op;
                    const std::array       originalOps = {ops[0], ops[1], ops[2], ops[3]};

                    inst.op          = MicroInstrOpcode::OpBinaryRegImm;
                    inst.numOperands = 4;
                    ops[1].opBits    = originalOps[2].opBits;
                    ops[2].microOp   = originalOps[3].microOp;
                    ops[3].valueU64  = immValue;
                    if (MicroOptimization::violatesEncoderConformance(context, inst, ops))
                    {
                        inst.op = originalOp;
                        for (uint32_t opIdx = 0; opIdx < originalOps.size(); ++opIdx)
                            ops[opIdx] = originalOps[opIdx];
                    }
                    else
                    {
                        changed = true;
                    }
                }
            }
        }
        else if (inst.op == MicroInstrOpcode::CmpRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end())
            {
                const uint64_t         immValue    = MicroOptimization::normalizeToOpBits(itKnown->second.value, ops[2].opBits);
                const MicroInstrOpcode originalOp  = inst.op;
                const std::array       originalOps = {ops[0], ops[1], ops[2]};

                inst.op          = MicroInstrOpcode::CmpRegImm;
                inst.numOperands = 3;
                ops[1].opBits    = originalOps[2].opBits;
                ops[2].valueU64  = immValue;
                if (MicroOptimization::violatesEncoderConformance(context, inst, ops))
                {
                    inst.op = originalOp;
                    for (uint32_t opIdx = 0; opIdx < originalOps.size(); ++opIdx)
                        ops[opIdx] = originalOps[opIdx];
                }
                else
                {
                    changed = true;
                }
            }
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto itKnown = known.find(ops[0].reg.packed);
            if (itKnown != known.end())
            {
                uint64_t foldedValue = 0;
                if (MicroOptimization::foldBinaryImmediate(foldedValue, itKnown->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
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
                .value = MicroOptimization::normalizeToOpBits(ops[2].valueU64, ops[1].opBits),
            };
        }
        else if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg.isInt() && ops[1].reg.isInt())
        {
            const auto itKnown = known.find(ops[1].reg.packed);
            if (itKnown != known.end())
            {
                known[ops[0].reg.packed] = {
                    .value = MicroOptimization::normalizeToOpBits(itKnown->second.value, ops[2].opBits),
                };
            }
        }
        else if (inst.op == MicroInstrOpcode::ClearReg && ops[0].reg.isInt())
        {
            known[ops[0].reg.packed] = {
                .value = 0,
            };
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg.isInt())
        {
            const auto itKnown = known.find(ops[0].reg.packed);
            if (itKnown != known.end())
            {
                uint64_t foldedValue = 0;
                if (MicroOptimization::foldBinaryImmediate(foldedValue, itKnown->second.value, ops[3].valueU64, ops[2].microOp, ops[1].opBits))
                {
                    known[ops[0].reg.packed] = {
                        .value = foldedValue,
                    };
                }
            }
        }

        if (inst.op == MicroInstrOpcode::Label || MicroInstrInfo::isTerminatorInstruction(inst))
            known.clear();
    }

    return changed;
}

SWC_END_NAMESPACE();
