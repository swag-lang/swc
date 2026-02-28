#include "pch.h"
#include "Backend/Micro/Passes/Pass.Legalize.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroInstrInfo.h"
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

    bool mustPreserveRegAfterInstruction(const MicroPassContext& context, MicroInstrRef instRef, MicroReg reg)
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
            const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_NOT_NULL(context.operands), context.encoder);
            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return true;

            if (containsReg(useDef.uses, reg))
                return true;
            if (containsReg(useDef.defs, reg))
                return false;
        }

        return false;
    }

    uint64_t requiredScratchForIssue(const MicroConformanceIssue& issue)
    {
        return issue.kind == MicroConformanceIssueKind::RewriteLoadFloatRegImm ? FLOAT_STACK_SCRATCH : 0;
    }

    bool isConcreteAllocatableReg(MicroReg reg)
    {
        return reg.isInt() || reg.isFloat();
    }

    void addVirtualForbiddenReg(const MicroPassContext& context, MicroReg virtualReg, MicroReg concreteReg)
    {
        SWC_ASSERT(context.builder);
        SWC_ASSERT(virtualReg.isVirtual());
        if (!isConcreteAllocatableReg(concreteReg))
            return;

        SWC_NOT_NULL(context.builder)->addVirtualRegForbiddenPhysReg(virtualReg, concreteReg);
    }

    uint32_t computeNextVirtualIntRegIndex(const MicroPassContext& context)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        uint32_t nextIndex = 1;
        if (context.builder)
            nextIndex = std::max(nextIndex, SWC_NOT_NULL(context.builder)->nextVirtualIntRegIndexHint());

        for (const MicroInstr& inst : context.instructions->view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(*SWC_NOT_NULL(context.operands), refs, context.encoder);
            for (const auto& ref : refs)
            {
                if (!ref.reg)
                    continue;

                const MicroReg reg = *ref.reg;
                if (!reg.isVirtualInt())
                    continue;

                if (reg.index() < MicroReg::K_MAX_INDEX)
                    nextIndex = std::max(nextIndex, reg.index() + 1);
                else
                    nextIndex = MicroReg::K_MAX_INDEX;
            }
        }

        return nextIndex;
    }

    MicroReg allocateVirtualIntReg(const MicroPassContext& context, uint32_t& nextVirtualIntRegIndex)
    {
        SWC_ASSERT(nextVirtualIntRegIndex <= MicroReg::K_MAX_INDEX);
        SWC_ASSERT(nextVirtualIntRegIndex < MicroReg::K_MAX_INDEX);
        const MicroReg result = MicroReg::virtualIntReg(nextVirtualIntRegIndex);
        ++nextVirtualIntRegIndex;
        SWC_UNUSED(context);
        return result;
    }

    uint64_t immediateValueU64(const MicroInstrOperand& operand)
    {
        if (!operand.hasWideImmediateValue())
            return operand.valueU64;

        const ApInt& value = operand.wideImmediateValue();
        if (!value.fit64())
            return 0;
        return value.as64();
    }

    uint64_t computeStackScratchBaseOffset(const MicroPassContext& context, const Encoder& encoder, MicroInstrRef instRef, uint64_t stackScratchFrameSize)
    {
        if (!stackScratchFrameSize)
            return 0;

        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        const MicroReg stackPointerReg = encoder.stackPointerReg();
        int64_t        stackDelta      = 0;

        const MicroStorage::View view = context.instructions->view();
        for (auto it = view.begin(); it != view.end() && it.current != instRef; ++it)
        {
            const MicroInstr&        scanInst = *it;
            const MicroInstrOperand* scanOps  = scanInst.ops(*SWC_NOT_NULL(context.operands));
            if (!scanOps)
                continue;

            if (scanInst.op == MicroInstrOpcode::Push)
            {
                stackDelta += static_cast<int64_t>(REG_STACK_SLOT_SIZE);
                continue;
            }

            if (scanInst.op == MicroInstrOpcode::Pop)
            {
                stackDelta -= static_cast<int64_t>(REG_STACK_SLOT_SIZE);
                continue;
            }

            if (scanInst.op != MicroInstrOpcode::OpBinaryRegImm || scanInst.numOperands < 4)
                continue;
            if (scanOps[0].reg != stackPointerReg || scanOps[1].opBits != MicroOpBits::B64)
                continue;

            const uint64_t immValue = immediateValueU64(scanOps[3]);
            if (scanOps[2].microOp == MicroOp::Subtract)
                stackDelta += static_cast<int64_t>(immValue);
            else if (scanOps[2].microOp == MicroOp::Add)
                stackDelta -= static_cast<int64_t>(immValue);
        }

        if (std::cmp_less_equal(stackDelta, stackScratchFrameSize))
            return 0;
        return static_cast<uint64_t>(stackDelta - static_cast<int64_t>(stackScratchFrameSize));
    }

    void insertScratchFrame(const MicroPassContext& context, const Encoder& encoder, uint64_t frameSize)
    {
        if (!frameSize)
            return;

        const auto beginIt = context.instructions->view().begin();
        if (beginIt == context.instructions->view().end())
            return;

        const MicroReg      stackPointerReg = encoder.stackPointerReg();
        const MicroInstrRef firstRef        = beginIt.current;

        std::array<MicroInstrOperand, 4> subOps;
        subOps[0].reg      = stackPointerReg;
        subOps[1].opBits   = MicroOpBits::B64;
        subOps[2].microOp  = MicroOp::Subtract;
        subOps[3].valueU64 = frameSize;
        context.instructions->insertBefore(*context.operands, firstRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

        std::vector<MicroInstrRef> retRefs;
        for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
        {
            if (it->op == MicroInstrOpcode::Ret)
                retRefs.push_back(it.current);
        }

        for (const MicroInstrRef retRef : retRefs)
        {
            std::array<MicroInstrOperand, 4> addOps;
            addOps[0].reg      = stackPointerReg;
            addOps[1].opBits   = MicroOpBits::B64;
            addOps[2].microOp  = MicroOp::Add;
            addOps[3].valueU64 = frameSize;
            context.instructions->insertBefore(*context.operands, retRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
        }
    }

    void removeInstruction(const MicroPassContext& context, MicroInstrRef instRef)
    {
        // Remove instruction after replacements have been inserted before its position.
        const bool erased = SWC_NOT_NULL(context.instructions)->erase(instRef);
        SWC_ASSERT(erased);
    }

    void applyClampImmediate(const MicroInstr& inst, MicroInstrOperand* ops, const MicroConformanceIssue& issue)
    {
        SWC_ASSERT(hasOperand(inst, ops, issue.operandIndex));
        const uint64_t clampedValue = std::min(ops[issue.operandIndex].valueU64, issue.valueLimitU64);
        ops[issue.operandIndex].setImmediateValue(ApInt(clampedValue, 64));
    }

    void applyNormalizeOpBits(const MicroInstr& inst, MicroInstrOperand* ops, const MicroConformanceIssue& issue)
    {
        SWC_ASSERT(hasOperand(inst, ops, issue.operandIndex));
        ops[issue.operandIndex].opBits = issue.normalizedOpBits;
    }

    void applySplitLoadMemImm64(const MicroPassContext& context, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::LoadMemImm);
        SWC_ASSERT(inst.numOperands >= 4);

        const MicroReg memReg    = ops[0].reg;
        const uint64_t memOffset = ops[2].valueU64;
        const uint64_t value     = ops[3].valueU64;
        const auto     lowU32    = static_cast<uint32_t>(value & U32_MASK);
        const auto     highU32   = static_cast<uint32_t>((value >> 32) & U32_MASK);

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

    void applySplitLoadAmcMemImm64(const MicroPassContext& context, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
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
        const auto        lowU32        = static_cast<uint32_t>(value & U32_MASK);
        const auto        highU32       = static_cast<uint32_t>((value >> 32) & U32_MASK);

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

    void applyRewriteLoadFloatRegImm(const MicroPassContext& context, const Encoder& encoder, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops, uint64_t stackScratchBaseOffset)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::LoadRegImm || inst.op == MicroInstrOpcode::LoadRegPtrImm || inst.op == MicroInstrOpcode::LoadRegPtrReloc);
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

    void applyRewriteLoadAddrAmcScale(const MicroPassContext& context, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::LoadAddrAmcRegMem);
        SWC_ASSERT(inst.numOperands >= 8);

        const MicroReg dstReg   = ops[0].reg;
        const MicroReg baseReg  = ops[1].reg;
        const MicroReg indexReg = ops[2].reg;
        const uint64_t mulValue = ops[5].valueU64;
        const uint64_t addValue = ops[6].valueU64;

        SWC_ASSERT(dstReg != baseReg);
        SWC_ASSERT(dstReg != indexReg);

        std::array<MicroInstrOperand, 3> moveOps;
        moveOps[0].reg    = dstReg;
        moveOps[1].reg    = indexReg;
        moveOps[2].opBits = MicroOpBits::B64;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadRegReg, moveOps);

        if (mulValue != 1)
        {
            std::array<MicroInstrOperand, 4> mulOps;
            mulOps[0].reg      = dstReg;
            mulOps[1].opBits   = MicroOpBits::B64;
            mulOps[2].microOp  = MicroOp::MultiplySigned;
            mulOps[3].valueU64 = mulValue;
            context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::OpBinaryRegImm, mulOps);
        }

        std::array<MicroInstrOperand, 4> addBaseOps;
        addBaseOps[0].reg     = dstReg;
        addBaseOps[1].reg     = baseReg;
        addBaseOps[2].opBits  = MicroOpBits::B64;
        addBaseOps[3].microOp = MicroOp::Add;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::OpBinaryRegReg, addBaseOps);

        if (addValue)
        {
            std::array<MicroInstrOperand, 4> addImmOps;
            addImmOps[0].reg      = dstReg;
            addImmOps[1].opBits   = MicroOpBits::B64;
            addImmOps[2].microOp  = MicroOp::Add;
            addImmOps[3].valueU64 = addValue;
            context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::OpBinaryRegImm, addImmOps);
        }

        removeInstruction(context, instRef);
    }

    void insertMoveRegReg(const MicroPassContext& context, MicroInstrRef instRef, MicroReg dstReg, MicroReg srcReg, MicroOpBits opBits)
    {
        std::array<MicroInstrOperand, 3> ops;
        ops[0].reg    = dstReg;
        ops[1].reg    = srcReg;
        ops[2].opBits = opBits;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadRegReg, ops);
    }

    void insertBinaryRegReg(const MicroPassContext& context, MicroInstrRef instRef, MicroReg dstReg, MicroReg srcReg, MicroOp op, MicroOpBits opBits)
    {
        std::array<MicroInstrOperand, 4> ops;
        ops[0].reg     = dstReg;
        ops[1].reg     = srcReg;
        ops[2].opBits  = opBits;
        ops[3].microOp = op;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::OpBinaryRegReg, ops);
    }

    void insertBinaryMemReg(const MicroPassContext& context, MicroInstrRef instRef, MicroReg memReg, uint64_t memOffset, MicroReg srcReg, MicroOp op, MicroOpBits opBits)
    {
        std::array<MicroInstrOperand, 5> ops;
        ops[0].reg      = memReg;
        ops[1].reg      = srcReg;
        ops[2].opBits   = opBits;
        ops[3].microOp  = op;
        ops[4].valueU64 = memOffset;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::OpBinaryMemReg, ops);
    }

    void insertCmpRegReg(const MicroPassContext& context, MicroInstrRef instRef, MicroReg lhsReg, MicroReg rhsReg, MicroOpBits opBits)
    {
        std::array<MicroInstrOperand, 3> ops;
        ops[0].reg    = lhsReg;
        ops[1].reg    = rhsReg;
        ops[2].opBits = opBits;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::CmpRegReg, ops);
    }

    void insertCmpMemReg(const MicroPassContext& context, MicroInstrRef instRef, MicroReg memReg, uint64_t memOffset, MicroReg rhsReg, MicroOpBits opBits)
    {
        std::array<MicroInstrOperand, 4> ops;
        ops[0].reg      = memReg;
        ops[1].reg      = rhsReg;
        ops[2].opBits   = opBits;
        ops[3].valueU64 = memOffset;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::CmpMemReg, ops);
    }

    void insertLoadRegImm(const MicroPassContext& context, MicroInstrRef instRef, MicroReg dstReg, MicroOpBits opBits, const MicroInstrOperand& immOperand)
    {
        std::array<MicroInstrOperand, 3> ops;
        ops[0].reg    = dstReg;
        ops[1].opBits = opBits;
        ops[2]        = immOperand;
        context.instructions->insertBefore(*context.operands, instRef, MicroInstrOpcode::LoadRegImm, ops);
    }

    void applyRewriteRegImmToRegReg(const MicroPassContext& context, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroConformanceIssue& issue, uint32_t& nextVirtualIntRegIndex)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::OpBinaryRegImm || inst.op == MicroInstrOpcode::OpBinaryMemImm || inst.op == MicroInstrOpcode::CmpRegImm || inst.op == MicroInstrOpcode::CmpMemImm);

        const MicroOpBits opBits = ops[1].opBits;
        MicroInstrOperand immOperand;
        if (inst.op == MicroInstrOpcode::OpBinaryRegImm)
            immOperand = ops[3];
        else if (inst.op == MicroInstrOpcode::OpBinaryMemImm)
            immOperand = ops[4];
        else if (inst.op == MicroInstrOpcode::CmpRegImm)
            immOperand = ops[2];
        else
            immOperand = ops[3];

        const MicroReg scratchReg = allocateVirtualIntReg(context, nextVirtualIntRegIndex);
        SWC_ASSERT(scratchReg.isValid());
        addVirtualForbiddenReg(context, scratchReg, ops[0].reg);
        addVirtualForbiddenReg(context, scratchReg, issue.requiredReg);
        addVirtualForbiddenReg(context, scratchReg, issue.forbiddenReg);

        insertLoadRegImm(context, instRef, scratchReg, opBits, immOperand);

        if (inst.op == MicroInstrOpcode::OpBinaryRegImm)
        {
            insertBinaryRegReg(context, instRef, ops[0].reg, scratchReg, ops[2].microOp, opBits);
        }
        else if (inst.op == MicroInstrOpcode::OpBinaryMemImm)
        {
            insertBinaryMemReg(context, instRef, ops[0].reg, ops[3].valueU64, scratchReg, ops[2].microOp, opBits);
        }
        else if (inst.op == MicroInstrOpcode::CmpRegImm)
        {
            insertCmpRegReg(context, instRef, ops[0].reg, scratchReg, opBits);
        }
        else
        {
            insertCmpMemReg(context, instRef, ops[0].reg, ops[2].valueU64, scratchReg, opBits);
        }

        removeInstruction(context, instRef);
    }

    void applyRewriteRegRegOperandToFixedReg(const MicroPassContext& context, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroConformanceIssue& issue, uint32_t& nextVirtualIntRegIndex)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::OpBinaryRegReg);
        SWC_ASSERT(issue.operandIndex <= 1);

        const MicroReg    originalDstReg = ops[0].reg;
        const MicroReg    originalSrcReg = ops[1].reg;
        const MicroOpBits opBits         = ops[2].opBits;
        const MicroOp     op             = ops[3].microOp;
        const MicroReg    requiredReg    = issue.requiredReg;
        SWC_ASSERT(requiredReg.isValid());

        const bool operandIsDst              = issue.operandIndex == 0;
        const bool conflict                  = operandIsDst ? originalSrcReg == requiredReg : originalDstReg == requiredReg;
        const bool mustPreserveRequiredReg   = mustPreserveRegAfterInstruction(context, instRef, requiredReg);
        const bool shouldPreserveRequiredReg = mustPreserveRequiredReg && requiredReg != originalDstReg;
        MicroReg   savedRequiredReg          = MicroReg::invalid();
        if (shouldPreserveRequiredReg)
        {
            savedRequiredReg = allocateVirtualIntReg(context, nextVirtualIntRegIndex);
            addVirtualForbiddenReg(context, savedRequiredReg, requiredReg);
            addVirtualForbiddenReg(context, savedRequiredReg, originalDstReg);
            addVirtualForbiddenReg(context, savedRequiredReg, originalSrcReg);
            insertMoveRegReg(context, instRef, savedRequiredReg, requiredReg, MicroOpBits::B64);
        }

        MicroReg helperReg = MicroReg::invalid();
        if (conflict)
        {
            helperReg = allocateVirtualIntReg(context, nextVirtualIntRegIndex);
            addVirtualForbiddenReg(context, helperReg, requiredReg);
            addVirtualForbiddenReg(context, helperReg, originalDstReg);
            addVirtualForbiddenReg(context, helperReg, originalSrcReg);
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

        if (savedRequiredReg.isValid())
            insertMoveRegReg(context, instRef, requiredReg, savedRequiredReg, MicroOpBits::B64);
        removeInstruction(context, instRef);
    }

    void applyRewriteMemRegOperandToFixedReg(const MicroPassContext& context, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroConformanceIssue& issue, uint32_t& nextVirtualIntRegIndex)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::OpBinaryMemReg);
        SWC_ASSERT(issue.operandIndex == 1);

        const MicroReg    originalMemReg = ops[0].reg;
        const MicroReg    originalSrcReg = ops[1].reg;
        const MicroOpBits opBits         = ops[2].opBits;
        const MicroOp     op             = ops[3].microOp;
        const uint64_t    memOffset      = ops[4].valueU64;
        const MicroReg    requiredReg    = issue.requiredReg;
        SWC_ASSERT(requiredReg.isValid());

        const bool mustPreserveRequiredReg = mustPreserveRegAfterInstruction(context, instRef, requiredReg);
        MicroReg   savedRequiredReg        = MicroReg::invalid();
        if (mustPreserveRequiredReg)
        {
            savedRequiredReg = allocateVirtualIntReg(context, nextVirtualIntRegIndex);
            addVirtualForbiddenReg(context, savedRequiredReg, requiredReg);
            addVirtualForbiddenReg(context, savedRequiredReg, originalMemReg);
            addVirtualForbiddenReg(context, savedRequiredReg, originalSrcReg);
            insertMoveRegReg(context, instRef, savedRequiredReg, requiredReg, MicroOpBits::B64);
        }

        MicroReg rewrittenMemReg = originalMemReg;
        if (originalMemReg == requiredReg)
        {
            rewrittenMemReg = allocateVirtualIntReg(context, nextVirtualIntRegIndex);
            addVirtualForbiddenReg(context, rewrittenMemReg, requiredReg);
            addVirtualForbiddenReg(context, rewrittenMemReg, originalMemReg);
            addVirtualForbiddenReg(context, rewrittenMemReg, originalSrcReg);
            insertMoveRegReg(context, instRef, rewrittenMemReg, requiredReg, MicroOpBits::B64);
        }

        insertMoveRegReg(context, instRef, requiredReg, originalSrcReg, MicroOpBits::B64);
        insertBinaryMemReg(context, instRef, rewrittenMemReg, memOffset, requiredReg, op, opBits);

        if (savedRequiredReg.isValid())
            insertMoveRegReg(context, instRef, requiredReg, savedRequiredReg, MicroOpBits::B64);
        removeInstruction(context, instRef);
    }

    void applyRewriteRegRegOperandAwayFromFixedReg(const MicroPassContext& context, MicroInstrRef instRef, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroConformanceIssue& issue, uint32_t& nextVirtualIntRegIndex)
    {
        SWC_ASSERT(ops);
        SWC_ASSERT(inst.op == MicroInstrOpcode::OpBinaryRegReg);
        SWC_ASSERT(issue.operandIndex <= 1);

        const MicroReg    originalDstReg = ops[0].reg;
        const MicroReg    originalSrcReg = ops[1].reg;
        const MicroOpBits opBits         = ops[2].opBits;
        const MicroOp     op             = ops[3].microOp;
        const MicroReg    forbiddenReg   = issue.forbiddenReg;
        const MicroReg    scratchReg     = allocateVirtualIntReg(context, nextVirtualIntRegIndex);
        SWC_ASSERT(forbiddenReg.isValid());
        SWC_ASSERT(scratchReg.isValid());
        addVirtualForbiddenReg(context, scratchReg, forbiddenReg);
        addVirtualForbiddenReg(context, scratchReg, originalDstReg);
        addVirtualForbiddenReg(context, scratchReg, originalSrcReg);

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

        removeInstruction(context, instRef);
    }

    void applyLegalizeIssue(const MicroPassContext& context, const Encoder& encoder, MicroInstrRef instRef, const MicroInstr& inst, MicroInstrOperand* ops, const MicroConformanceIssue& issue, uint64_t stackScratchBaseOffset, uint32_t& nextVirtualIntRegIndex)
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
            case MicroConformanceIssueKind::RewriteLoadAddrAmcScale:
                applyRewriteLoadAddrAmcScale(context, instRef, inst, ops);
                return;
            case MicroConformanceIssueKind::RewriteLoadFloatRegImm:
                applyRewriteLoadFloatRegImm(context, encoder, instRef, inst, ops, stackScratchBaseOffset);
                return;
            case MicroConformanceIssueKind::RewriteRegImmToRegReg:
                applyRewriteRegImmToRegReg(context, instRef, inst, ops, issue, nextVirtualIntRegIndex);
                return;
            case MicroConformanceIssueKind::RewriteRegRegOperandToFixedReg:
                if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
                    applyRewriteRegRegOperandToFixedReg(context, instRef, inst, ops, issue, nextVirtualIntRegIndex);
                else if (inst.op == MicroInstrOpcode::OpBinaryMemReg)
                    applyRewriteMemRegOperandToFixedReg(context, instRef, inst, ops, issue, nextVirtualIntRegIndex);
                else
                    SWC_ASSERT(false);
                return;
            case MicroConformanceIssueKind::RewriteRegRegOperandAwayFromFixedReg:
                applyRewriteRegRegOperandAwayFromFixedReg(context, instRef, inst, ops, issue, nextVirtualIntRegIndex);
                return;
            default:
                SWC_ASSERT(false);
        }
    }
}

Result MicroLegalizePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.builder);
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    const auto& encoder                = *SWC_NOT_NULL(context.encoder);
    uint64_t    stackScratchFrameSize  = 0;
    uint32_t    nextVirtualIntRegIndex = computeNextVirtualIntRegIndex(context);
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(*SWC_NOT_NULL(context.operands));

        MicroConformanceIssue issue;
        if (!encoder.queryConformanceIssue(issue, inst, ops))
            continue;

        stackScratchFrameSize = std::max(stackScratchFrameSize, requiredScratchForIssue(issue));
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
        const MicroInstrRef instRef = it.current;
        ++it;

        const MicroInstr* instPtr = context.instructions->ptr(instRef);
        if (!instPtr)
            continue;
        const MicroInstr&        inst = *instPtr;
        MicroInstrOperand* const ops  = inst.ops(*context.operands);

        MicroConformanceIssue issue;
        if (!encoder.queryConformanceIssue(issue, inst, ops))
            continue;

        for (;;)
        {
            changed                               = true;
            const uint64_t stackScratchBaseOffset = computeStackScratchBaseOffset(context, encoder, instRef, stackScratchFrameSize);
            applyLegalizeIssue(context, encoder, instRef, inst, ops, issue, stackScratchBaseOffset, nextVirtualIntRegIndex);

            const MicroInstr* const currentInst = context.instructions->ptr(instRef);
            if (!currentInst)
                break;

            const MicroInstrOperand* const currentOps = currentInst->ops(*context.operands);
            if (!encoder.queryConformanceIssue(issue, *currentInst, currentOps))
                break;
        }
    }

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
