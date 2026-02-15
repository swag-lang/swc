#include "pch.h"
#include "Backend/CodeGen/Micro/Passes/MicroConformancePass.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool applyConformanceIssue(const MicroPassContext& context, Ref instRef, MicroInstr& inst, MicroInstrOperand* ops, const MicroConformanceIssue& issue)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        ///////////////////////////////////////////
        if (issue.kind == MicroConformanceIssueKind::ClampImmediate)
        {
            if (!ops || issue.operandIndex >= inst.numOperands)
                return false;
            ops[issue.operandIndex].valueU64 = std::min(ops[issue.operandIndex].valueU64, issue.valueLimitU64);
            return true;
        }

        ///////////////////////////////////////////
        if (issue.kind == MicroConformanceIssueKind::NormalizeOpBits)
        {
            if (!ops || issue.operandIndex >= inst.numOperands)
                return false;
            ops[issue.operandIndex].opBits = issue.normalizedOpBits;
            return true;
        }

        ///////////////////////////////////////////
        if (issue.kind == MicroConformanceIssueKind::SplitLoadMemImm64)
        {
            if (!ops || inst.op != MicroInstrOpcode::LoadMemImm || inst.numOperands < 4)
                return false;

            const auto memReg    = ops[0].reg;
            const auto memOffset = ops[2].valueU64;
            const auto value     = ops[3].valueU64;
            const auto lowU32    = static_cast<uint32_t>(value & 0xFFFFFFFFu);
            const auto highU32   = static_cast<uint32_t>((value >> 32) & 0xFFFFFFFFu);

            std::array<MicroInstrOperand, 4> lowOps;
            lowOps[0].reg      = memReg;
            lowOps[1].opBits   = MicroOpBits::B32;
            lowOps[2].valueU64 = memOffset;
            lowOps[3].valueU64 = lowU32;
            context.instructions->insertInstructionBefore(*context.operands, instRef, MicroInstrOpcode::LoadMemImm, inst.emitFlags, lowOps);

            std::array<MicroInstrOperand, 4> highOps;
            highOps[0].reg      = memReg;
            highOps[1].opBits   = MicroOpBits::B32;
            highOps[2].valueU64 = memOffset + 4;
            highOps[3].valueU64 = highU32;
            context.instructions->insertInstructionBefore(*context.operands, instRef, MicroInstrOpcode::LoadMemImm, inst.emitFlags, highOps);

            inst.op          = MicroInstrOpcode::Ignore;
            inst.opsRef      = INVALID_REF;
            inst.numOperands = 0;
            return true;
        }

        ///////////////////////////////////////////
        if (issue.kind == MicroConformanceIssueKind::SplitLoadAmcMemImm64)
        {
            if (!ops || inst.op != MicroInstrOpcode::LoadAmcMemImm || inst.numOperands < 8)
                return false;

            const auto regBase        = ops[0].reg;
            const auto regMul         = ops[1].reg;
            const auto opBitsBaseMul  = ops[3].opBits;
            const auto mulValue       = ops[5].valueU64;
            const auto addValue       = ops[6].valueU64;
            const auto value          = ops[7].valueU64;
            const auto lowU32         = static_cast<uint32_t>(value & 0xFFFFFFFFu);
            const auto highU32        = static_cast<uint32_t>((value >> 32) & 0xFFFFFFFFu);

            std::array<MicroInstrOperand, 8> lowOps;
            lowOps[0].reg      = regBase;
            lowOps[1].reg      = regMul;
            lowOps[3].opBits   = opBitsBaseMul;
            lowOps[4].opBits   = MicroOpBits::B32;
            lowOps[5].valueU64 = mulValue;
            lowOps[6].valueU64 = addValue;
            lowOps[7].valueU64 = lowU32;
            context.instructions->insertInstructionBefore(*context.operands, instRef, MicroInstrOpcode::LoadAmcMemImm, inst.emitFlags, lowOps);

            std::array<MicroInstrOperand, 8> highOps;
            highOps[0].reg      = regBase;
            highOps[1].reg      = regMul;
            highOps[3].opBits   = opBitsBaseMul;
            highOps[4].opBits   = MicroOpBits::B32;
            highOps[5].valueU64 = mulValue;
            highOps[6].valueU64 = addValue + 4;
            highOps[7].valueU64 = highU32;
            context.instructions->insertInstructionBefore(*context.operands, instRef, MicroInstrOpcode::LoadAmcMemImm, inst.emitFlags, highOps);

            inst.op          = MicroInstrOpcode::Ignore;
            inst.opsRef      = INVALID_REF;
            inst.numOperands = 0;
            return true;
        }

        return false;
    }
}

void MicroConformancePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    const auto& encoder = *SWC_CHECK_NOT_NULL(context.encoder);

    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        auto& inst = *it;
        for (;;)
        {
            auto* const ops = inst.ops(*context.operands);
            MicroConformanceIssue issue;
            if (!encoder.queryConformanceIssue(issue, inst, ops))
                break;

            if (!applyConformanceIssue(context, it.current, inst, ops, issue))
                SWC_INTERNAL_ERROR();
        }
    }
}

SWC_END_NAMESPACE();
