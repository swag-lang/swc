#include "pch.h"
#include "Backend/CodeGen/Micro/Passes/MicroLegalizePass.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t U32_MASK            = 0xFFFFFFFFu;
    constexpr uint64_t FLOAT_STACK_SCRATCH = 8;

    bool hasOperand(const MicroInstr& inst, const MicroInstrOperand* ops, uint8_t operandIndex)
    {
        return ops && operandIndex < inst.numOperands;
    }

    void invalidateInstruction(MicroInstr& inst)
    {
        inst.op          = MicroInstrOpcode::Ignore;
        inst.opsRef      = INVALID_REF;
        inst.numOperands = 0;
    }

    void applyClampImmediate(const MicroInstr& inst, MicroInstrOperand* ops, const MicroConformanceIssue& issue)
    {
        SWC_ASSERT(hasOperand(inst, ops, issue.operandIndex));
        ops[issue.operandIndex].valueU64 = std::min(ops[issue.operandIndex].valueU64, issue.valueLimitU64);
    }

    void applyNormalizeOpBits(const MicroInstr& inst, MicroInstrOperand* ops, const MicroConformanceIssue& issue)
    {
        SWC_ASSERT(hasOperand(inst, ops, issue.operandIndex));
        ops[issue.operandIndex].opBits = issue.normalizedOpBits;
    }

    void applySplitLoadMemImm64(const MicroPassContext& context, Ref instRef, MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::LoadMemImm);
        SWC_ASSERT(inst.numOperands >= 4);

        const MicroReg memReg    = ops[0].reg;
        const uint64_t memOffset = ops[2].valueU64;
        const uint64_t value     = ops[3].valueU64;
        const uint32_t lowU32    = static_cast<uint32_t>(value & U32_MASK);
        const uint32_t highU32   = static_cast<uint32_t>((value >> 32) & U32_MASK);

        invalidateInstruction(inst);

        std::array<MicroInstrOperand, 4> lowOps;
        lowOps[0].reg      = memReg;
        lowOps[1].opBits   = MicroOpBits::B32;
        lowOps[2].valueU64 = memOffset;
        lowOps[3].valueU64 = lowU32;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadMemImm, lowOps);

        std::array<MicroInstrOperand, 4> highOps;
        highOps[0].reg      = memReg;
        highOps[1].opBits   = MicroOpBits::B32;
        highOps[2].valueU64 = memOffset + 4;
        highOps[3].valueU64 = highU32;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadMemImm, highOps);
    }

    void applySplitLoadAmcMemImm64(const MicroPassContext& context, Ref instRef, MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::LoadAmcMemImm);
        SWC_ASSERT(inst.numOperands >= 8);

        const MicroReg    regBase       = ops[0].reg;
        const MicroReg    regMul        = ops[1].reg;
        const MicroOpBits opBitsBaseMul = ops[3].opBits;
        const uint64_t    mulValue      = ops[5].valueU64;
        const uint64_t    addValue      = ops[6].valueU64;
        const uint64_t    value         = ops[7].valueU64;
        const uint32_t    lowU32        = static_cast<uint32_t>(value & U32_MASK);
        const uint32_t    highU32       = static_cast<uint32_t>((value >> 32) & U32_MASK);

        invalidateInstruction(inst);

        std::array<MicroInstrOperand, 8> lowOps;
        lowOps[0].reg      = regBase;
        lowOps[1].reg      = regMul;
        lowOps[3].opBits   = opBitsBaseMul;
        lowOps[4].opBits   = MicroOpBits::B32;
        lowOps[5].valueU64 = mulValue;
        lowOps[6].valueU64 = addValue;
        lowOps[7].valueU64 = lowU32;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadAmcMemImm, lowOps);

        std::array<MicroInstrOperand, 8> highOps;
        highOps[0].reg      = regBase;
        highOps[1].reg      = regMul;
        highOps[3].opBits   = opBitsBaseMul;
        highOps[4].opBits   = MicroOpBits::B32;
        highOps[5].valueU64 = mulValue;
        highOps[6].valueU64 = addValue + 4;
        highOps[7].valueU64 = highU32;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadAmcMemImm, highOps);
    }

    void applyRewriteLoadFloatRegImm(const MicroPassContext& context, const Encoder& encoder, Ref instRef, MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::LoadRegImm || inst.op == MicroInstrOpcode::LoadRegPtrImm);
        SWC_ASSERT(inst.numOperands >= 3);

        const MicroReg dstReg   = ops[0].reg;
        MicroOpBits    opBits   = ops[1].opBits;
        const uint64_t immValue = ops[2].valueU64;
        const MicroReg rspReg   = encoder.stackPointerReg();
        if (opBits != MicroOpBits::B32 && opBits != MicroOpBits::B64)
            opBits = MicroOpBits::B64;

        invalidateInstruction(inst);

        std::array<MicroInstrOperand, 4> subOps;
        subOps[0].reg      = rspReg;
        subOps[1].opBits   = MicroOpBits::B64;
        subOps[2].microOp  = MicroOp::Subtract;
        subOps[3].valueU64 = FLOAT_STACK_SCRATCH;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

        std::array<MicroInstrOperand, 4> storeOps;
        storeOps[0].reg      = rspReg;
        storeOps[1].opBits   = opBits;
        storeOps[2].valueU64 = 0;
        storeOps[3].valueU64 = immValue;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadMemImm, storeOps);

        std::array<MicroInstrOperand, 4> loadOps;
        loadOps[0].reg      = dstReg;
        loadOps[1].reg      = rspReg;
        loadOps[2].opBits   = opBits;
        loadOps[3].valueU64 = 0;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadRegMem, loadOps);

        std::array<MicroInstrOperand, 4> addOps;
        addOps[0].reg      = rspReg;
        addOps[1].opBits   = MicroOpBits::B64;
        addOps[2].microOp  = MicroOp::Add;
        addOps[3].valueU64 = FLOAT_STACK_SCRATCH;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
    }

    void applyLegalizeIssue(const MicroPassContext& context, const Encoder& encoder, Ref instRef, MicroInstr& inst, MicroInstrOperand* ops, const MicroConformanceIssue& issue)
    {
        switch (issue.kind)
        {
            case MicroConformanceIssueKind::ClampImmediate:
                applyClampImmediate(inst, ops, issue);
                return;
            case MicroConformanceIssueKind::NormalizeOpBits:
                applyNormalizeOpBits(inst, ops, issue);
                return;
            case MicroConformanceIssueKind::SplitLoadMemImm64:
                applySplitLoadMemImm64(context, instRef, inst, ops);
                return;
            case MicroConformanceIssueKind::SplitLoadAmcMemImm64:
                applySplitLoadAmcMemImm64(context, instRef, inst, ops);
                return;
            case MicroConformanceIssueKind::RewriteLoadFloatRegImm:
                applyRewriteLoadFloatRegImm(context, encoder, instRef, inst, ops);
                return;
            default:
                SWC_ASSERT(false);
        }
    }
}

void MicroLegalizePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    const auto& encoder = *SWC_CHECK_NOT_NULL(context.encoder);

    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        auto&       inst = *it;
        MicroInstrOperand* const ops  = inst.ops(*context.operands);

        MicroConformanceIssue issue;
        if (!encoder.queryConformanceIssue(issue, inst, ops))
            continue;

        for (;;)
        {
            applyLegalizeIssue(context, encoder, it.current, inst, ops, issue);
            if (inst.op == MicroInstrOpcode::Ignore)
                break;

            if (!encoder.queryConformanceIssue(issue, inst, ops))
                break;
        }
    }
}

SWC_END_NAMESPACE();
