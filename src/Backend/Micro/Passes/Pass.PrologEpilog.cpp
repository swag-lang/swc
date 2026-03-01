#include "pch.h"
#include "Backend/Micro/Passes/Pass.PrologEpilog.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Support/Math/Helpers.h"

// Inserts ABI-mandated save/restore code around the function body.
// Example: if callee-saved rbx is used, emit push rbx in prolog and pop rbx in epilog.
// Example: reserve stack slots for preserved state when required by calling convention.
// This pass enforces ABI correctness, not optimization.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool tryMergeStackAdjustInstruction(const MicroPassContext& context, MicroInstrRef targetRef, MicroReg stackPointerReg, MicroOp expectedOp, uint64_t additionalValue)
    {
        if (targetRef.isInvalid() || !additionalValue)
            return false;

        const MicroInstr* inst = SWC_NOT_NULL(context.instructions)->ptr(targetRef);
        if (!inst || inst->op != MicroInstrOpcode::OpBinaryRegImm)
            return false;

        MicroInstrOperand* ops = inst->ops(*context.operands);
        if (!ops)
            return false;
        if (ops[0].reg != stackPointerReg || ops[1].opBits != MicroOpBits::B64 || ops[2].microOp != expectedOp)
            return false;
        if (ops[3].valueU64 > std::numeric_limits<uint64_t>::max() - additionalValue)
            return false;

        ops[3].valueU64 += additionalValue;
        return true;
    }

    bool hasCallInstruction(const MicroPassContext& context)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        const auto& operands = *context.operands;
        for (const auto& inst : context.instructions->view())
        {
            const auto useDef = inst.collectUseDef(operands, context.encoder);
            if (useDef.isCall)
                return true;
        }

        return false;
    }

    void collectUsedConcreteRegs(const MicroPassContext& context, std::unordered_set<MicroReg>& outUsedRegs)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        outUsedRegs.clear();
        auto& operands = *context.operands;
        for (const auto& inst : context.instructions->view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(operands, refs, context.encoder);
            for (const MicroInstrRegOperandRef& microInstrRef : refs)
            {
                if (!microInstrRef.reg)
                    continue;

                const MicroReg reg = *SWC_NOT_NULL(microInstrRef.reg);
                if (!reg.isValid() || reg.isVirtual())
                    continue;

                outUsedRegs.insert(reg);
            }
        }
    }

    bool isFramePointerLocallyInitializedFromStackPointer(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (!conv.framePointer.isValid() || !conv.stackPointer.isValid())
            return false;

        bool  foundInit = false;
        auto& operands  = *context.operands;
        for (const auto& inst : context.instructions->view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(operands, refs, context.encoder);

            bool framePointerUsed = false;
            bool framePointerDef  = false;
            for (const MicroInstrRegOperandRef& microInstrRef : refs)
            {
                if (!microInstrRef.reg)
                    continue;

                const MicroReg reg = *SWC_NOT_NULL(microInstrRef.reg);
                if (!reg.isValid() || reg.isVirtual() || reg != conv.framePointer)
                    continue;

                if (microInstrRef.use)
                    framePointerUsed = true;
                if (microInstrRef.def)
                    framePointerDef = true;
            }

            if (framePointerUsed && !foundInit)
                return false;
            if (!framePointerDef || foundInit)
                continue;

            if (inst.op != MicroInstrOpcode::LoadRegReg)
                return false;

            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                return false;
            if (ops[0].reg != conv.framePointer)
                return false;
            if (ops[1].reg != conv.stackPointer)
                return false;
            if (ops[2].opBits != MicroOpBits::B64)
                return false;

            foundInit = true;
        }

        return foundInit;
    }

    bool isRegDefinedBeforeAnyUse(const MicroPassContext& context, MicroReg reg)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (!reg.isValid())
            return false;

        auto& operands = *context.operands;
        for (const auto& inst : context.instructions->view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(operands, refs, context.encoder);

            bool hasUse = false;
            bool hasDef = false;
            for (const MicroInstrRegOperandRef& microInstrRef : refs)
            {
                if (!microInstrRef.reg)
                    continue;

                const MicroReg refReg = *SWC_NOT_NULL(microInstrRef.reg);
                if (refReg != reg)
                    continue;

                if (microInstrRef.use)
                    hasUse = true;
                if (microInstrRef.def)
                    hasDef = true;
            }

            if (!hasUse && !hasDef)
                continue;
            if (hasUse)
                return false;

            return hasDef;
        }

        return false;
    }

    bool isSafeTransientReplacementIntReg(const CallConv& conv, MicroReg reg)
    {
        if (!reg.isValid() || !reg.isInt())
            return false;
        if (reg == conv.stackPointer || reg == conv.framePointer || reg == conv.intReturn)
            return false;
        if (conv.isIntArgReg(reg))
            return false;
        return true;
    }

    bool tryPickUnusedTransientIntReg(const CallConv& conv, const std::unordered_set<MicroReg>& usedRegs, const std::unordered_set<MicroReg>& pickedTransientRegs, MicroReg& outReg)
    {
        for (const MicroReg reg : conv.intTransientRegs)
        {
            if (!reg.isValid())
                continue;
            if (!isSafeTransientReplacementIntReg(conv, reg))
                continue;
            if (usedRegs.contains(reg))
                continue;
            if (pickedTransientRegs.contains(reg))
                continue;

            outReg = reg;
            return true;
        }

        return false;
    }

    bool remapPersistentIntRegsToUnusedTransient(const MicroPassContext& context, const CallConv& conv)
    {
        if (hasCallInstruction(context))
            return false;

        std::unordered_set<MicroReg> usedRegs;
        collectUsedConcreteRegs(context, usedRegs);
        if (usedRegs.empty())
            return false;

        SmallVector<MicroReg> remapCandidates;
        remapCandidates.reserve(conv.intPersistentRegs.size());

        if (conv.framePointer.isValid() &&
            conv.isIntPersistentReg(conv.framePointer) &&
            usedRegs.contains(conv.framePointer) &&
            isFramePointerLocallyInitializedFromStackPointer(context, conv))
        {
            remapCandidates.push_back(conv.framePointer);
        }

        for (const MicroReg persistentReg : conv.intPersistentRegs)
        {
            if (!persistentReg.isValid())
                continue;
            if (persistentReg == conv.framePointer)
                continue;
            if (!usedRegs.contains(persistentReg))
                continue;
            if (!isRegDefinedBeforeAnyUse(context, persistentReg))
                continue;

            remapCandidates.push_back(persistentReg);
        }

        if (remapCandidates.empty())
            return false;

        std::unordered_set<MicroReg>           pickedTransientRegs;
        std::unordered_map<MicroReg, MicroReg> remap;
        pickedTransientRegs.reserve(remapCandidates.size() * 2 + 1);
        remap.reserve(remapCandidates.size() * 2 + 1);

        for (const MicroReg persistentReg : remapCandidates)
        {
            MicroReg replacementReg;
            if (!tryPickUnusedTransientIntReg(conv, usedRegs, pickedTransientRegs, replacementReg))
                continue;

            remap[persistentReg] = replacementReg;
            pickedTransientRegs.insert(replacementReg);
            usedRegs.insert(replacementReg);
        }

        if (remap.empty())
            return false;

        bool  remapped = false;
        auto& operands = *context.operands;
        for (const auto& inst : context.instructions->view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(operands, refs, context.encoder);
            for (const MicroInstrRegOperandRef& microInstrRef : refs)
            {
                if (!microInstrRef.reg)
                    continue;

                const MicroReg reg = *SWC_NOT_NULL(microInstrRef.reg);
                if (!reg.isValid() || reg.isVirtual())
                    continue;

                const auto mapIt = remap.find(reg);
                if (mapIt == remap.end())
                    continue;

                *SWC_NOT_NULL(microInstrRef.reg) = mapIt->second;
                remapped                         = true;
            }
        }

        return remapped;
    }
}

Result MicroPrologEpilogPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);

    // Caller can disable this when generated code does not need ABI-preserved registers.
    if (!context.preservePersistentRegs)
    {
        pushedRegs_.clear();
        retRefs_.clear();
        savedRegSlots_.clear();
        savedRegsStackSubSize_ = 0;
        useFramePointer_       = false;
        return Result::Continue;
    }

    const CallConv& conv                              = CallConv::get(context.callConvKind);
    const bool      remappedPersistentRegsToTransient = remapPersistentIntRegsToUnusedTransient(context, conv);
    buildSavedRegsPlan(context, conv);
    if (pushedRegs_.empty() && !savedRegsStackSubSize_ && !useFramePointer_)
    {
        context.passChanged = remappedPersistentRegsToTransient;
        return Result::Continue;
    }

    MicroInstrRef firstRef = MicroInstrRef::invalid();
    retRefs_.clear();
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        if (firstRef.isInvalid())
            firstRef = it.current;
        if (it->op == MicroInstrOpcode::Ret)
            retRefs_.push_back(it.current);
    }

    if (firstRef.isValid())
        insertSavedRegsPrologue(context, conv, firstRef);
    for (const MicroInstrRef retRef : retRefs_)
        insertSavedRegsEpilogue(context, conv, retRef);

    context.passChanged = firstRef.isValid() || remappedPersistentRegsToTransient;
    return Result::Continue;
}

bool MicroPrologEpilogPass::containsSavedSlot(MicroReg reg) const
{
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        if (slot.reg == reg)
            return true;
    }

    return false;
}

bool MicroPrologEpilogPass::containsPushedReg(MicroReg reg) const
{
    for (const MicroReg pushedReg : pushedRegs_)
    {
        if (pushedReg == reg)
            return true;
    }

    return false;
}

void MicroPrologEpilogPass::buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv)
{
    SWC_ASSERT(context.instructions);

    pushedRegs_.clear();
    savedRegSlots_.clear();
    savedRegsStackSubSize_ = 0;
    useFramePointer_       = false;

    // Scan concrete register operands and collect only ABI-persistent regs that are used.
    auto& storeOps = *context.operands;
    for (const auto& inst : context.instructions->view())
    {
        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(storeOps, refs, context.encoder);
        for (const MicroInstrRegOperandRef& microInstrRef : refs)
        {
            if (!microInstrRef.reg)
                continue;

            const MicroReg reg = *SWC_NOT_NULL(microInstrRef.reg);
            if (!reg.isValid() || reg.isVirtual())
                continue;

            if (reg.isInt())
            {
                if (!conv.isIntPersistentReg(reg))
                    continue;

                if (reg == conv.framePointer)
                {
                    useFramePointer_ = true;
                    continue;
                }

                if (!containsPushedReg(reg))
                    pushedRegs_.push_back(reg);
            }
            else if (reg.isFloat())
            {
                if (!conv.isFloatPersistentReg(reg))
                    continue;

                if (!containsSavedSlot(reg))
                    savedRegSlots_.push_back({.reg = reg, .offset = 0, .slotBits = MicroOpBits::B128});
            }
        }
    }

    if (pushedRegs_.empty() && savedRegSlots_.empty() && !useFramePointer_)
        return;

    uint64_t frameOffset = 0;
    for (auto& slot : savedRegSlots_)
    {
        const uint64_t slotSize = slot.slotBits == MicroOpBits::B128 ? 16 : 8;
        frameOffset             = Math::alignUpU64(frameOffset, slotSize);
        slot.offset             = frameOffset;
        frameOffset += slotSize;
    }

    // Final frame size includes push area + spill slots, rounded to ABI stack alignment.
    uint64_t pushedRegsCount = pushedRegs_.size();
    if (useFramePointer_)
        ++pushedRegsCount;

    const uint64_t pushedRegsSize = pushedRegsCount * sizeof(uint64_t);
    const uint64_t stackAlignment = conv.stackAlignment ? conv.stackAlignment : 16;
    const uint64_t totalFrameSize = Math::alignUpU64(pushedRegsSize + frameOffset, stackAlignment);
    savedRegsStackSubSize_        = totalFrameSize > pushedRegsSize ? totalFrameSize - pushedRegsSize : 0;
}

void MicroPrologEpilogPass::insertSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv, MicroInstrRef insertBeforeRef) const
{
    if (pushedRegs_.empty() && !savedRegsStackSubSize_ && !useFramePointer_)
        return;

    auto& instructions = *context.instructions;
    auto& operands     = *context.operands;

    if (useFramePointer_)
    {
        MicroInstrOperand pushFrameOps[1];
        pushFrameOps[0].reg = conv.framePointer;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::Push, pushFrameOps);

        MicroInstrOperand setFrameOps[3];
        setFrameOps[0].reg    = conv.framePointer;
        setFrameOps[1].reg    = conv.stackPointer;
        setFrameOps[2].opBits = MicroOpBits::B64;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadRegReg, setFrameOps);
    }

    // Integer persistent regs are saved with push/pop.
    for (const MicroReg pushedReg : pushedRegs_)
    {
        MicroInstrOperand pushOps[1];
        pushOps[0].reg = pushedReg;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::Push, pushOps);
    }

    bool mergedStackSub = false;
    if (savedRegsStackSubSize_ && savedRegSlots_.empty())
    {
        mergedStackSub = tryMergeStackAdjustInstruction(context, insertBeforeRef, conv.stackPointer, MicroOp::Subtract, savedRegsStackSubSize_);
    }

    if (savedRegsStackSubSize_ && !mergedStackSub)
    {
        MicroInstrOperand subOps[4];
        subOps[0].reg      = conv.stackPointer;
        subOps[1].opBits   = MicroOpBits::B64;
        subOps[2].microOp  = MicroOp::Subtract;
        subOps[3].valueU64 = savedRegsStackSubSize_;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, subOps);
    }

    // Float persistent regs use explicit stack slots because there is no push/pop form.
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        MicroInstrOperand storeOps[4];
        storeOps[0].reg      = conv.stackPointer;
        storeOps[1].reg      = slot.reg;
        storeOps[2].opBits   = slot.slotBits;
        storeOps[3].valueU64 = slot.offset;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadMemReg, storeOps);
    }
}

void MicroPrologEpilogPass::insertSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, MicroInstrRef insertBeforeRef) const
{
    if (pushedRegs_.empty() && !savedRegsStackSubSize_ && !useFramePointer_)
        return;

    auto& instructions = *context.instructions;
    auto& operands     = *context.operands;

    // Restore in reverse: load slot-backed regs, undo stack allocation, then pop integer regs.
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        MicroInstrOperand loadOps[4];
        loadOps[0].reg      = slot.reg;
        loadOps[1].reg      = conv.stackPointer;
        loadOps[2].opBits   = slot.slotBits;
        loadOps[3].valueU64 = slot.offset;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadRegMem, loadOps);
    }

    bool mergedStackAdd = false;
    if (savedRegsStackSubSize_ && savedRegSlots_.empty())
    {
        const MicroInstrRef previousBodyRef = instructions.findPreviousInstructionRef(insertBeforeRef);
        mergedStackAdd                      = tryMergeStackAdjustInstruction(context, previousBodyRef, conv.stackPointer, MicroOp::Add, savedRegsStackSubSize_);
    }

    if (savedRegsStackSubSize_ && !mergedStackAdd)
    {
        MicroInstrOperand addOps[4];
        addOps[0].reg      = conv.stackPointer;
        addOps[1].opBits   = MicroOpBits::B64;
        addOps[2].microOp  = MicroOp::Add;
        addOps[3].valueU64 = savedRegsStackSubSize_;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
    }

    for (const MicroReg pushedReg : std::ranges::reverse_view(pushedRegs_))
    {
        MicroInstrOperand popOps[1];
        popOps[0].reg = pushedReg;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::Pop, popOps);
    }

    if (useFramePointer_)
    {
        MicroInstrOperand popFrameOps[1];
        popFrameOps[0].reg = conv.framePointer;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::Pop, popFrameOps);
    }
}

SWC_END_NAMESPACE();
