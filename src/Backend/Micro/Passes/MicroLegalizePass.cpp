#include "pch.h"
#include "Backend/Micro/Passes/MicroLegalizePass.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroOptimization.h"
#include "Support/Math/Helpers.h"

// Rewrites non-encodable instruction forms into legal encoder forms.
// Example: unsupported mem+imm pattern -> sequence using a temporary register.
// Example: oversized immediate form -> split/rewrite to legal width.
// This pass preserves semantics while enforcing backend encoding constraints.

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t U32_MASK             = 0xFFFFFFFFu;
    constexpr uint64_t FLOAT_STACK_SCRATCH  = 8;
    constexpr uint64_t REG_STACK_SLOT_SIZE  = 8;
    constexpr uint64_t LEGALIZE_STACK_ALIGN = 16;

    bool hasOperand(const MicroInstr& inst, const MicroInstrOperand* ops, uint8_t operandIndex)
    {
        return ops && operandIndex < inst.numOperands;
    }

    bool containsReg(std::span<const MicroReg> regs, MicroReg reg)
    {
        for (const MicroReg value : regs)
        {
            if (value == reg)
                return true;
        }

        return false;
    }

    bool mustPreserveRegAfterInstruction(const MicroPassContext& context, Ref instRef, MicroReg reg)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (!reg.isValid())
            return false;

        const MicroStorage::View view = context.instructions->view();
        auto                     it   = view.begin();
        while (it != view.end() && it.current != instRef)
            ++it;
        if (it == view.end())
            return true;

        ++it;
        for (; it != view.end(); ++it)
        {
            const MicroInstr&      scanInst = *it;
            const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
            if (MicroOptimization::isLocalDataflowBarrier(scanInst, useDef))
                return true;

            if (containsReg(useDef.uses, reg))
                return true;
            if (containsReg(useDef.defs, reg))
                return false;
        }

        return false;
    }

    uint64_t requiredScratchForIssue(const MicroPassContext& context, Ref instRef, const MicroInstrOperand* ops, const MicroConformanceIssue& issue)
    {
        if (!ops)
            return 0;

        switch (issue.kind)
        {
            case MicroConformanceIssueKind::RewriteLoadFloatRegImm:
                return FLOAT_STACK_SCRATCH;

            case MicroConformanceIssueKind::RewriteRegRegOperandAwayFromFixedReg:
                return mustPreserveRegAfterInstruction(context, instRef, issue.scratchReg) ? REG_STACK_SLOT_SIZE : 0;

            case MicroConformanceIssueKind::RewriteRegRegOperandToFixedReg:
            {
                SWC_ASSERT(issue.operandIndex <= 1);
                const bool operandIsDst = issue.operandIndex == 0;
                const bool conflict     = operandIsDst ? ops[1].reg == issue.requiredReg : ops[0].reg == issue.requiredReg;
                uint64_t   required     = 0;
                if (mustPreserveRegAfterInstruction(context, instRef, issue.requiredReg))
                    required += REG_STACK_SLOT_SIZE;
                if (conflict)
                    required += REG_STACK_SLOT_SIZE;
                return required;
            }

            default:
                return 0;
        }
    }

    void insertScratchFrame(const MicroPassContext& context, const Encoder& encoder, uint64_t frameSize)
    {
        if (!frameSize)
            return;

        const auto beginIt = context.instructions->view().begin();
        if (beginIt == context.instructions->view().end())
            return;

        const MicroReg stackPointerReg = encoder.stackPointerReg();
        const Ref      firstRef        = beginIt.current;

        std::array<MicroInstrOperand, 4> subOps;
        subOps[0].reg      = stackPointerReg;
        subOps[1].opBits   = MicroOpBits::B64;
        subOps[2].microOp  = MicroOp::Subtract;
        subOps[3].valueU64 = frameSize;
        context.instructions->insertBefore(*context.operands, firstRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

        std::vector<Ref> retRefs;
        for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
        {
            if (it->op == MicroInstrOpcode::Ret)
                retRefs.push_back(it.current);
        }

        for (const Ref retRef : retRefs)
        {
            std::array<MicroInstrOperand, 4> addOps;
            addOps[0].reg      = stackPointerReg;
            addOps[1].opBits   = MicroOpBits::B64;
            addOps[2].microOp  = MicroOp::Add;
            addOps[3].valueU64 = frameSize;
            context.instructions->insertBefore(*context.operands, retRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
        }
    }

    void removeInstruction(const MicroPassContext& context, Ref instRef)
    {
        // Remove instruction after replacements have been inserted before its position.
        const bool erased = SWC_CHECK_NOT_NULL(context.instructions)->erase(instRef);
        SWC_ASSERT(erased);
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

    void applySplitLoadMemImm64(const MicroPassContext& context, Ref instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::LoadMemImm);
        SWC_ASSERT(inst.numOperands >= 4);

        const MicroReg memReg    = ops[0].reg;
        const uint64_t memOffset = ops[2].valueU64;
        const uint64_t value     = ops[3].valueU64;
        const uint32_t lowU32    = static_cast<uint32_t>(value & U32_MASK);
        const uint32_t highU32   = static_cast<uint32_t>((value >> 32) & U32_MASK);

        // Some encoders cannot store a 64-bit immediate to memory directly.
        // Rewrite as two 32-bit stores at [offset] and [offset + 4].
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
        removeInstruction(context, instRef);
    }

    void applySplitLoadAmcMemImm64(const MicroPassContext& context, Ref instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
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

        // Same split strategy for address-mode-combined memory stores.
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
        removeInstruction(context, instRef);
    }

    void applyRewriteLoadFloatRegImm(const MicroPassContext& context, const Encoder& encoder, Ref instRef, const MicroInstr& inst, const MicroInstrOperand* ops, uint64_t stackScratchBaseOffset)
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

        std::array<MicroInstrOperand, 4> storeOps;
        storeOps[0].reg      = rspReg;
        storeOps[1].opBits   = opBits;
        storeOps[2].valueU64 = stackScratchBaseOffset;
        storeOps[3].valueU64 = immValue;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadMemImm, storeOps);

        std::array<MicroInstrOperand, 4> loadOps;
        loadOps[0].reg      = dstReg;
        loadOps[1].reg      = rspReg;
        loadOps[2].opBits   = opBits;
        loadOps[3].valueU64 = stackScratchBaseOffset;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadRegMem, loadOps);
        removeInstruction(context, instRef);
    }

    void insertStoreRegToStack(const MicroPassContext& context, Ref instRef, MicroReg stackPointerReg, uint64_t offset, MicroReg reg)
    {
        std::array<MicroInstrOperand, 4> ops;
        ops[0].reg      = stackPointerReg;
        ops[1].reg      = reg;
        ops[2].opBits   = MicroOpBits::B64;
        ops[3].valueU64 = offset;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadMemReg, ops);
    }

    void insertLoadRegFromStack(const MicroPassContext& context, Ref instRef, MicroReg reg, MicroReg stackPointerReg, uint64_t offset)
    {
        std::array<MicroInstrOperand, 4> ops;
        ops[0].reg      = reg;
        ops[1].reg      = stackPointerReg;
        ops[2].opBits   = MicroOpBits::B64;
        ops[3].valueU64 = offset;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadRegMem, ops);
    }

    void insertMoveRegReg(const MicroPassContext& context, Ref instRef, MicroReg dstReg, MicroReg srcReg, MicroOpBits opBits)
    {
        std::array<MicroInstrOperand, 3> ops;
        ops[0].reg    = dstReg;
        ops[1].reg    = srcReg;
        ops[2].opBits = opBits;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadRegReg, ops);
    }

    void insertBinaryRegReg(const MicroPassContext& context, Ref instRef, MicroReg dstReg, MicroReg srcReg, MicroOp op, MicroOpBits opBits)
    {
        std::array<MicroInstrOperand, 4> ops;
        ops[0].reg     = dstReg;
        ops[1].reg     = srcReg;
        ops[2].opBits  = opBits;
        ops[3].microOp = op;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::OpBinaryRegReg, ops);
    }

    void applyRewriteRegRegOperandToFixedReg(const MicroPassContext& context, const Encoder& encoder, Ref instRef, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroConformanceIssue& issue, uint64_t stackScratchBaseOffset)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::OpBinaryRegReg);
        SWC_ASSERT(issue.operandIndex <= 1);

        const MicroReg    originalDstReg = ops[0].reg;
        const MicroReg    originalSrcReg = ops[1].reg;
        const MicroOpBits opBits         = ops[2].opBits;
        const MicroOp     op             = ops[3].microOp;
        const MicroReg    requiredReg    = issue.requiredReg;
        const MicroReg    helperReg      = issue.helperReg;
        SWC_ASSERT(requiredReg.isValid());

        const MicroReg stackPointerReg = encoder.stackPointerReg();
        const bool     operandIsDst    = issue.operandIndex == 0;
        const bool     conflict        = operandIsDst ? originalSrcReg == requiredReg : originalDstReg == requiredReg;
        if (conflict)
            SWC_ASSERT(helperReg.isValid());

        const bool mustPreserveRequiredReg = mustPreserveRegAfterInstruction(context, instRef, requiredReg);
        uint64_t   helperStackOffset       = stackScratchBaseOffset;
        if (mustPreserveRequiredReg)
        {
            insertStoreRegToStack(context, instRef, stackPointerReg, stackScratchBaseOffset, requiredReg);
            helperStackOffset += REG_STACK_SLOT_SIZE;
        }

        if (conflict)
        {
            insertStoreRegToStack(context, instRef, stackPointerReg, helperStackOffset, helperReg);
            insertMoveRegReg(context, instRef, helperReg, requiredReg, MicroOpBits::B64);
        }

        if (operandIsDst)
            insertMoveRegReg(context, instRef, requiredReg, originalDstReg, MicroOpBits::B64);
        else
            insertMoveRegReg(context, instRef, requiredReg, originalSrcReg, MicroOpBits::B64);

        MicroReg rewrittenDstReg = originalDstReg;
        MicroReg rewrittenSrcReg = originalSrcReg;
        if (operandIsDst)
            rewrittenDstReg = requiredReg;
        else
            rewrittenSrcReg = requiredReg;

        if (conflict)
        {
            if (operandIsDst)
                rewrittenSrcReg = helperReg;
            else
                rewrittenDstReg = helperReg;
        }

        insertBinaryRegReg(context, instRef, rewrittenDstReg, rewrittenSrcReg, op, opBits);
        if (rewrittenDstReg != originalDstReg)
            insertMoveRegReg(context, instRef, originalDstReg, rewrittenDstReg, opBits);

        if (mustPreserveRequiredReg && requiredReg != originalDstReg)
            insertLoadRegFromStack(context, instRef, requiredReg, stackPointerReg, stackScratchBaseOffset);
        if (conflict && helperReg != originalDstReg)
            insertLoadRegFromStack(context, instRef, helperReg, stackPointerReg, helperStackOffset);
        removeInstruction(context, instRef);
    }

    void applyRewriteRegRegOperandAwayFromFixedReg(const MicroPassContext& context, const Encoder& encoder, Ref instRef, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroConformanceIssue& issue, uint64_t stackScratchBaseOffset)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::OpBinaryRegReg);
        SWC_ASSERT(issue.operandIndex <= 1);

        const MicroReg    originalDstReg = ops[0].reg;
        const MicroReg    originalSrcReg = ops[1].reg;
        const MicroOpBits opBits         = ops[2].opBits;
        const MicroOp     op             = ops[3].microOp;
        const MicroReg    forbiddenReg   = issue.forbiddenReg;
        const MicroReg    scratchReg     = issue.scratchReg;
        SWC_ASSERT(forbiddenReg.isValid());
        SWC_ASSERT(scratchReg.isValid());

        const MicroReg stackPointerReg        = encoder.stackPointerReg();
        const bool     mustPreserveScratchReg = mustPreserveRegAfterInstruction(context, instRef, scratchReg);

        if (mustPreserveScratchReg)
            insertStoreRegToStack(context, instRef, stackPointerReg, stackScratchBaseOffset, scratchReg);
        if (issue.operandIndex == 0)
            insertMoveRegReg(context, instRef, scratchReg, originalDstReg, MicroOpBits::B64);
        else
            insertMoveRegReg(context, instRef, scratchReg, originalSrcReg, MicroOpBits::B64);

        MicroReg rewrittenDstReg = originalDstReg;
        MicroReg rewrittenSrcReg = originalSrcReg;
        if (issue.operandIndex == 0)
            rewrittenDstReg = scratchReg;
        else
            rewrittenSrcReg = scratchReg;

        SWC_ASSERT((issue.operandIndex == 0 ? rewrittenDstReg : rewrittenSrcReg) != forbiddenReg);
        insertBinaryRegReg(context, instRef, rewrittenDstReg, rewrittenSrcReg, op, opBits);
        if (rewrittenDstReg != originalDstReg)
            insertMoveRegReg(context, instRef, originalDstReg, rewrittenDstReg, opBits);

        if (mustPreserveScratchReg && scratchReg != originalDstReg)
            insertLoadRegFromStack(context, instRef, scratchReg, stackPointerReg, stackScratchBaseOffset);
        removeInstruction(context, instRef);
    }

    void applyLegalizeIssue(const MicroPassContext& context, const Encoder& encoder, Ref instRef, MicroInstr& inst, MicroInstrOperand* ops, const MicroConformanceIssue& issue, uint64_t stackScratchBaseOffset)
    {
        // Encoder reports one issue at a time; apply one targeted rewrite/fix.
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
                applyRewriteLoadFloatRegImm(context, encoder, instRef, inst, ops, stackScratchBaseOffset);
                return;
            case MicroConformanceIssueKind::RewriteRegRegOperandToFixedReg:
                applyRewriteRegRegOperandToFixedReg(context, encoder, instRef, inst, ops, issue, stackScratchBaseOffset);
                return;
            case MicroConformanceIssueKind::RewriteRegRegOperandAwayFromFixedReg:
                applyRewriteRegRegOperandAwayFromFixedReg(context, encoder, instRef, inst, ops, issue, stackScratchBaseOffset);
                return;
            default:
                SWC_ASSERT(false);
        }
    }
}

bool MicroLegalizePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    const auto& encoder               = *SWC_CHECK_NOT_NULL(context.encoder);
    uint64_t    stackScratchFrameSize = 0;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        const Ref                instRef = it.current;
        const MicroInstr&        inst    = *it;
        const MicroInstrOperand* ops     = inst.ops(*SWC_CHECK_NOT_NULL(context.operands));

        MicroConformanceIssue issue;
        if (!encoder.queryConformanceIssue(issue, inst, ops))
            continue;

        stackScratchFrameSize = std::max(stackScratchFrameSize, requiredScratchForIssue(context, instRef, ops, issue));
    }

    if (stackScratchFrameSize)
        stackScratchFrameSize = Math::alignUpU64(stackScratchFrameSize, LEGALIZE_STACK_ALIGN);

    if (stackScratchFrameSize)
        insertScratchFrame(context, encoder, stackScratchFrameSize);

    bool changed = false;

    // Iterate once over instructions, but keep fixing a given instruction
    // until the encoder reports it conformant.
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end();)
    {
        const Ref instRef = it.current;
        ++it;

        MicroInstr* const instPtr = context.instructions->ptr(instRef);
        if (!instPtr)
            continue;
        MicroInstr&              inst = *instPtr;
        MicroInstrOperand* const ops  = inst.ops(*context.operands);

        MicroConformanceIssue issue;
        if (!encoder.queryConformanceIssue(issue, inst, ops))
            continue;

        for (;;)
        {
            changed = true;
            applyLegalizeIssue(context, encoder, instRef, inst, ops, issue, 0);

            const MicroInstr* const currentInst = context.instructions->ptr(instRef);
            if (!currentInst)
                break;

            const MicroInstrOperand* const currentOps = currentInst->ops(*context.operands);
            if (!encoder.queryConformanceIssue(issue, *currentInst, currentOps))
                break;
        }
    }

    return changed;
}

SWC_END_NAMESPACE();
