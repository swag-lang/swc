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
