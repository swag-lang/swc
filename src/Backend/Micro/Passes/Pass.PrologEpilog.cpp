#include "pch.h"
#include "Backend/Micro/Passes/Pass.PrologEpilog.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"

// Inserts ABI-mandated save/restore code around the function body.
//
// Pipeline (run after register allocation, when every register is concrete):
//
//   1. remapPersistentIntRegsToUnusedTransient
//        Optimization: for leaf functions (no calls), if RA picked a callee-
//        saved integer register but a free caller-saved one is also available,
//        swap them. The save/restore that would otherwise be required is then
//        unnecessary. Eligible candidates must be defined before any use (so
//        the original ABI value never matters) and be remappable end-to-end.
//
//   2. buildSavedRegsPlan
//        Walks the body and classifies every concrete register touched:
//          - integer persistent regs   -> push/pop in prologue/epilogue
//          - float   persistent regs   -> explicit stack slot (no push form)
//          - frame   pointer           -> push + `mov fp, sp` setup
//        Computes the spill-area size needed to hold the float slots and
//        rounds the prologue stack subtract up to the ABI alignment so the
//        body sees a properly aligned SP.
//
//   3. insertSavedRegsPrologue / insertSavedRegsEpilogue
//        Materializes the planned push/pop, frame setup, stack adjust, and
//        slot stores/loads. The saved area is a self-contained allocation in
//        front of the body: the frame pointer anchored right after it (see
//        the sanitize pass) is what keeps the frame walkable, so the body's
//        own stack motion stays out of the unwind description.

SWC_BEGIN_NAMESPACE();

namespace
{
    void insertStackAdjust(const MicroPassContext& context, MicroInstrRef insertBeforeRef, MicroReg stackPointerReg, MicroOp op, uint64_t value)
    {
        MicroInstrOperand ops[4];
        ops[0].reg      = stackPointerReg;
        ops[1].opBits   = MicroOpBits::B64;
        ops[2].microOp  = op;
        ops[3].valueU64 = value;
        context.instructions->insertSyntheticBefore(*context.operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, ops);
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

                const MicroReg reg = *(microInstrRef.reg);
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

                const MicroReg reg = *(microInstrRef.reg);
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

                const MicroReg refReg = *(microInstrRef.reg);
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

    bool isStackPointerAdjust(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer, MicroOp expectedOp)
    {
        if (!ops || inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        if (ops[0].reg != stackPointer || ops[1].opBits != MicroOpBits::B64)
            return false;
        return ops[2].microOp == expectedOp;
    }

    bool definesStackPointer(const MicroPassContext& context, const MicroInstr& inst, MicroReg stackPointer)
    {
        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(*context.operands, refs, context.encoder);
        for (const MicroInstrRegOperandRef& regRef : refs)
        {
            if (regRef.reg && regRef.def && *regRef.reg == stackPointer)
                return true;
        }

        return false;
    }

    // Windows unwind data describes the prologue it can see: the nonvolatile pushes and the
    // one stack allocation that follows them. A body that moves the stack pointer afterwards
    // leaves that description short, and recovering the stack pointer from a frame register is
    // what covers the difference. A function whose whole stack shape is one subtract at entry
    // and one add before each return needs no such cover: it can keep the frame register as an
    // ordinary callee-saved one and skip three instructions on every call.
    bool bodyMovesStackPointerAfterPrologue(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        const MicroReg stackPointer = conv.stackPointer;
        if (!stackPointer.isValid())
            return true;

        bool       inEntryRun = true;
        const auto view       = context.instructions->view();
        const auto endIt      = view.end();
        for (auto it = view.begin(); it != endIt; ++it)
        {
            const MicroInstrOperand* ops = it->ops(*context.operands);

            if (it->op == MicroInstrOpcode::Push || it->op == MicroInstrOpcode::Pop)
                return true;

            if (isStackPointerAdjust(*it, ops, stackPointer, MicroOp::Subtract))
            {
                if (!inEntryRun)
                    return true;
                continue;
            }

            if (isStackPointerAdjust(*it, ops, stackPointer, MicroOp::Add))
            {
                // Register allocation adds its own release beside the one lowering already
                // emitted, so an epilogue is a run of adds, not a single one.
                auto nextIt = it;
                ++nextIt;
                while (nextIt != endIt &&
                       (nextIt->op == MicroInstrOpcode::Nop ||
                        isStackPointerAdjust(*nextIt, nextIt->ops(*context.operands), stackPointer, MicroOp::Add)))
                    ++nextIt;
                if (nextIt == endIt || nextIt->op != MicroInstrOpcode::Ret)
                    return true;
                continue;
            }

            if (definesStackPointer(context, *it, stackPointer))
                return true;

            if (it->op != MicroInstrOpcode::Nop && it->op != MicroInstrOpcode::Label)
                inEntryRun = false;
        }

        return false;
    }

    bool remapPersistentIntRegsToUnusedTransient(MicroPassContext& context, const CallConv& conv)
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

        // Keep the debug local-stack base in sync: if its physical home is one of the persistent
        // registers being renamed, the debug records must name the replacement or locals would
        // resolve against the wrong register.
        if (context.debugStackBasePhysReg.isValid())
        {
            const auto baseIt = remap.find(context.debugStackBasePhysReg);
            if (baseIt != remap.end())
                context.debugStackBasePhysReg = baseIt->second;
        }

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

                const MicroReg reg = *(microInstrRef.reg);
                if (!reg.isValid() || reg.isVirtual())
                    continue;

                const auto mapIt = remap.find(reg);
                if (mapIt == remap.end())
                    continue;

                *(microInstrRef.reg) = mapIt->second;
                remapped             = true;
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

void MicroPrologEpilogPass::buildSavedRegsPlan(MicroPassContext& context, const CallConv& conv)
{
    SWC_ASSERT(context.instructions);

    pushedRegs_.clear();
    savedRegSlots_.clear();
    savedRegsStackSubSize_ = 0;
    useFramePointer_       = context.forceFramePointer;
    bool framePointerNamed = false;

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

            const MicroReg reg = *(microInstrRef.reg);
            if (!reg.isValid() || reg.isVirtual())
                continue;

            if (reg.isInt())
            {
                if (!conv.isIntPersistentReg(reg))
                    continue;

                if (reg == conv.framePointer)
                {
                    useFramePointer_  = true;
                    framePointerNamed = true;
                    continue;
                }

                if (!microInstrRef.def)
                    continue;

                if (!containsPushedReg(reg))
                    pushedRegs_.push_back(reg);
            }
            else if (reg.isFloat())
            {
                if (!conv.isFloatPersistentReg(reg))
                    continue;
                if (!microInstrRef.def)
                    continue;

                if (!containsSavedSlot(reg))
                {
                    SavedRegSlot savedSlot;
                    savedSlot.reg      = reg;
                    savedSlot.slotBits = MicroOpBits::B128;
                    savedRegSlots_.push_back(savedSlot);
                }
            }
        }
    }

    // The frame register is only owed to the unwinder by a function whose stack pointer moves
    // where the unwind codes cannot describe it. Two shapes qualify: a body that adjusts the
    // stack pointer after the prologue, and a float save area, whose stores sit between this
    // pass's allocation and the body's own and keep the sanitize pass from coalescing the two
    // into the single allocation the unwind description can hold. Everything else is described
    // in full by the pushes and one allocation, so the frame register buys nothing and costs a
    // push, a move and a pop on every call.
    //
    // The request is cleared, not just ignored: the sanitize pass synthesizes a setup for any
    // function that still asks for one, so both passes have to read the same answer.
    if (useFramePointer_ && !framePointerNamed && savedRegSlots_.empty() && !bodyMovesStackPointerAfterPrologue(context, conv))
    {
        useFramePointer_          = false;
        context.forceFramePointer = false;
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
        instructions.insertSyntheticBefore(operands, insertBeforeRef, MicroInstrOpcode::Push, pushFrameOps);

        MicroInstrOperand setFrameOps[3];
        setFrameOps[0].reg    = conv.framePointer;
        setFrameOps[1].reg    = conv.stackPointer;
        setFrameOps[2].opBits = MicroOpBits::B64;
        instructions.insertSyntheticBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadRegReg, setFrameOps);
    }

    // Integer persistent regs are saved with push/pop.
    for (const MicroReg pushedReg : pushedRegs_)
    {
        MicroInstrOperand pushOps[1];
        pushOps[0].reg = pushedReg;
        instructions.insertSyntheticBefore(operands, insertBeforeRef, MicroInstrOpcode::Push, pushOps);
    }

    // The saved area gets its own allocation, in front of everything the body
    // does with the stack pointer. The slots sit at [sp+0..], each 16-aligned
    // so UWOP_SAVE_XMM128 can describe the stores, and the frame pointer is
    // anchored right after them (see the sanitize pass): the unwinder then
    // recovers the stack pointer from the frame register, so the body's own
    // later allocations — its frame, its spill area, its call adjusts — never
    // need to appear in the unwind description at all.
    if (savedRegsStackSubSize_)
        insertStackAdjust(context, insertBeforeRef, conv.stackPointer, MicroOp::Subtract, savedRegsStackSubSize_);

    // Float persistent regs use explicit stack slots because there is no
    // push/pop form.
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        MicroInstrOperand storeOps[4];
        storeOps[0].reg      = conv.stackPointer;
        storeOps[1].reg      = slot.reg;
        storeOps[2].opBits   = slot.slotBits;
        storeOps[3].valueU64 = slot.offset;
        instructions.insertSyntheticBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadMemReg, storeOps);
    }
}

void MicroPrologEpilogPass::insertSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, MicroInstrRef insertBeforeRef) const
{
    if (pushedRegs_.empty() && !savedRegsStackSubSize_ && !useFramePointer_)
        return;

    auto& instructions = *context.instructions;
    auto& operands     = *context.operands;

    // Restore in reverse: load slot-backed regs, undo the saved-area
    // allocation, then pop integer regs. At every return the body has undone
    // its own stack motion, so the stack pointer addresses the saved area
    // directly, at the same [sp+0..] offsets the prologue stored to.
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        MicroInstrOperand loadOps[4];
        loadOps[0].reg      = slot.reg;
        loadOps[1].reg      = conv.stackPointer;
        loadOps[2].opBits   = slot.slotBits;
        loadOps[3].valueU64 = slot.offset;
        instructions.insertSyntheticBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadRegMem, loadOps);
    }

    if (savedRegsStackSubSize_)
        insertStackAdjust(context, insertBeforeRef, conv.stackPointer, MicroOp::Add, savedRegsStackSubSize_);

    for (const MicroReg pushedReg : std::ranges::reverse_view(pushedRegs_))
    {
        MicroInstrOperand popOps[1];
        popOps[0].reg = pushedReg;
        instructions.insertSyntheticBefore(operands, insertBeforeRef, MicroInstrOpcode::Pop, popOps);
    }

    if (useFramePointer_)
    {
        MicroInstrOperand popFrameOps[1];
        popFrameOps[0].reg = conv.framePointer;
        instructions.insertSyntheticBefore(operands, insertBeforeRef, MicroInstrOpcode::Pop, popFrameOps);
    }
}

SWC_END_NAMESPACE();
