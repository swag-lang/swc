#include "pch.h"
#include "Backend/Micro/Passes/Pass.PrologEpilog.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
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
    using MicroPhysLiveness = MicroPassHelpers::MicroPhysLiveness;

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

    void collectUsedConcreteRegs(const MicroPassContext& context, const CallConv& conv, std::unordered_set<MicroReg>& outUsedRegs, uint64_t& outDefinedBeforeUse)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        outUsedRegs.clear();
        outDefinedBeforeUse  = 0;
        uint64_t pendingRegs = 0;
        for (const MicroReg reg : conv.intPersistentRegs)
        {
            const uint32_t bit = MicroPhysLiveness::bitOf(reg);
            if (reg != conv.framePointer && bit < MicroPhysLiveness::K_INVALID_BIT)
                pendingRegs |= 1ull << bit;
        }

        auto& operands = *context.operands;
        for (const auto& inst : context.instructions->view())
        {
            SmallVector<MicroInstrRegOperandRef> refs;
            inst.collectRegOperands(operands, refs, context.encoder);
            uint64_t usedRegs    = 0;
            uint64_t definedRegs = 0;
            for (const MicroInstrRegOperandRef& microInstrRef : refs)
            {
                if (!microInstrRef.reg)
                    continue;

                const MicroReg reg = *(microInstrRef.reg);
                if (!reg.isValid() || reg.isVirtual())
                    continue;

                outUsedRegs.insert(reg);
                if (!pendingRegs)
                    continue;
                const uint32_t bit = MicroPhysLiveness::bitOf(reg);
                if (bit >= MicroPhysLiveness::K_INVALID_BIT)
                    continue;
                const uint64_t mask = (1ull << bit) & pendingRegs;
                if (microInstrRef.use)
                    usedRegs |= mask;
                if (microInstrRef.def)
                    definedRegs |= mask;
            }
            // Aggregate the entire instruction before resolving first touches:
            // a read wins over a definition even when its operand appears later.
            outDefinedBeforeUse |= pendingRegs & definedRegs & ~usedRegs;
            pendingRegs &= ~(usedRegs | definedRegs);
        }
    }

    bool isFramePointerLocallyInitializedFromStackPointer(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (!conv.framePointer.isValid() || !conv.stackPointer.isValid())
            return false;

        auto& operands = *context.operands;
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

            if (framePointerUsed)
                return false;
            if (!framePointerDef)
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

            return true;
        }

        return false;
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

    bool tryPickUnusedTransientIntReg(const CallConv& conv, const std::unordered_set<MicroReg>& usedRegs, MicroReg& outReg)
    {
        for (const MicroReg reg : conv.intTransientRegs)
        {
            if (!reg.isValid())
                continue;
            if (!isSafeTransientReplacementIntReg(conv, reg))
                continue;
            if (usedRegs.contains(reg))
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

    // The run of stack-pointer adds that releases the frame in front of a
    // return, walked backwards from it. Register allocation puts its own
    // release beside the one lowering emitted, so this is a run and not a
    // single instruction. Returns their total and, through `outFirst`, the
    // earliest of them - which is where anything reading the frame still has
    // to sit.
    uint64_t sumEpilogueAdds(const MicroPassContext& context, MicroReg stackPointer, MicroInstrRef retRef, MicroInstrRef& outFirst)
    {
        auto&    instructions = *context.instructions;
        uint64_t total        = 0;
        outFirst              = MicroInstrRef::invalid();
        for (MicroInstrRef cur = instructions.findPreviousInstructionRef(retRef); cur.isValid();
             cur              = instructions.findPreviousInstructionRef(cur))
        {
            const MicroInstr* inst = instructions.ptr(cur);
            if (!inst)
                break;
            if (inst->op == MicroInstrOpcode::Nop)
                continue;
            const MicroInstrOperand* ops = inst->ops(*context.operands);
            if (!isStackPointerAdjust(*inst, ops, stackPointer, MicroOp::Add) || ops[3].hasWideImmediateValue())
                break;
            total += ops[3].valueU64;
            outFirst = cur;
        }

        return total;
    }

    // The body's own allocation, when its whole stack shape is one subtract at
    // entry and one run of adds before every return releasing exactly it.
    // Returns zero for anything else, so the fold below can trust the shape it
    // is about to rewrite.
    uint64_t findBodyEntryAllocation(const MicroPassContext& context, const CallConv& conv)
    {
        const MicroReg stackPointer = conv.stackPointer;
        if (!stackPointer.isValid())
            return 0;

        // Lowering and register allocation each contribute a subtract, so the
        // entry allocation is a run too.
        uint64_t   allocation = 0;
        const auto view       = context.instructions->view();
        for (auto it = view.begin(); it != view.end(); ++it)
        {
            const MicroInstrOperand* ops = it->ops(*context.operands);
            if (isStackPointerAdjust(*it, ops, stackPointer, MicroOp::Subtract))
            {
                if (ops[3].hasWideImmediateValue() || !ops[3].valueU64)
                    return 0;
                allocation += ops[3].valueU64;
                continue;
            }
            if (isStackPointerAdjust(*it, ops, stackPointer, MicroOp::Add))
                continue;
            if (definesStackPointer(context, *it, stackPointer) || it->op == MicroInstrOpcode::Push ||
                it->op == MicroInstrOpcode::Pop)
                return 0;
        }

        if (!allocation)
            return 0;

        // Every return must release exactly that allocation, or the epilogue
        // this fold rewrites is not the one it matched.
        for (auto it = view.begin(); it != view.end(); ++it)
        {
            if (it->op != MicroInstrOpcode::Ret)
                continue;
            MicroInstrRef  first = MicroInstrRef::invalid();
            const uint64_t total = sumEpilogueAdds(context, stackPointer, it.current, first);
            if (!first.isValid() || total != allocation)
                return 0;
        }

        return allocation;
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
                // This entire add/Nop run is validated. Resume at the Ret so
                // its entry-run effect is still handled by the main walk.
                it = nextIt;
                --it;
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
        uint64_t                     definedBeforeUse = 0;
        collectUsedConcreteRegs(context, conv, usedRegs, definedBeforeUse);
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
            const uint32_t bit        = MicroPhysLiveness::bitOf(persistentReg);
            const bool     firstIsDef = bit < MicroPhysLiveness::K_INVALID_BIT ? (definedBeforeUse & (1ull << bit)) != 0 : isRegDefinedBeforeAnyUse(context, persistentReg);
            if (!firstIsDef)
                continue;

            remapCandidates.push_back(persistentReg);
        }

        if (remapCandidates.empty())
            return false;

        std::unordered_map<MicroReg, MicroReg> remap;
        remap.reserve(remapCandidates.size() * 2 + 1);

        for (const MicroReg persistentReg : remapCandidates)
        {
            MicroReg replacementReg;
            if (!tryPickUnusedTransientIntReg(conv, usedRegs, replacementReg))
                continue;

            remap[persistentReg] = replacementReg;
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

    // A leaf whose only frame-pointer references are incoming stack arguments
    // can address them from the unchanged entry stack pointer. The offsets
    // produced by lowering assume `push fp; mov fp, sp`, so removing that push
    // moves every incoming slot down by one pointer. Reject any other frame or
    // stack use: saved registers, local allocations and calls all change the
    // stack-pointer value seen by the body.
    bool rewriteLeafIncomingArgsToStackPointer(MicroPassContext& context, const CallConv& conv)
    {
        if (!conv.framePointer.isValid() || !conv.stackPointer.isValid() || hasCallInstruction(context))
            return false;

        const uint64_t firstIncomingArgOffset = ABICall::incomingArgFrameOffset(conv, conv.numArgRegisterSlots());
        SmallVector<MicroInstrRef> accesses;
        auto&                      operands = *context.operands;
        for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
        {
            MicroInstr*              inst = context.instructions->ptr(it.current);
            MicroInstrOperand*       ops  = inst ? inst->ops(operands) : nullptr;
            const MicroInstrDef&     info = MicroInstr::info(inst->op);
            SmallVector<MicroInstrRegOperandRef> regOperands;
            inst->collectRegOperands(operands, regOperands, context.encoder);

            if (inst->op == MicroInstrOpcode::Push || inst->op == MicroInstrOpcode::Pop ||
                definesStackPointer(context, *inst, conv.stackPointer))
                return false;

            bool namesFramePointer = false;
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (!regOperand.reg || *regOperand.reg != conv.framePointer)
                    continue;
                namesFramePointer = true;
                if (!ops || regOperand.def || !info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) ||
                    regOperand.reg != &ops[info.memBaseOperandIndex].reg)
                    return false;
            }

            if (!namesFramePointer)
                continue;
            if (ops[info.memBaseOperandIndex].reg != conv.framePointer ||
                ops[info.memOffsetOperandIndex].valueU64 < firstIncomingArgOffset)
                return false;
            accesses.push_back(it.current);
        }

        if (accesses.empty())
            return false;

        for (const MicroInstrRef ref : accesses)
        {
            MicroInstr*          inst = context.instructions->ptr(ref);
            MicroInstrOperand*   ops  = inst->ops(operands);
            const MicroInstrDef& info = MicroInstr::info(inst->op);
            ops[info.memBaseOperandIndex].reg = conv.stackPointer;
            ops[info.memOffsetOperandIndex].valueU64 -= sizeof(void*);
        }
        return true;
    }
}

Result MicroPrologEpilogPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);

    // Caller can disable this when generated code does not need ABI-preserved registers.
    if (!context.preservePersistentRegs)
    {
        pushedRegs_.clear();
        savedRegSlots_.clear();
        savedRegsStackSubSize_ = 0;
        useFramePointer_       = false;
        return Result::Continue;
    }

    const CallConv& conv                              = CallConv::get(context.callConvKind);
    const bool      remappedPersistentRegsToTransient = remapPersistentIntRegsToUnusedTransient(context, conv);
    buildSavedRegsPlan(context, conv);
    bool rewroteIncomingArgs = false;
    if (useFramePointer_ && pushedRegs_.empty() && savedRegSlots_.empty())
    {
        rewroteIncomingArgs = rewriteLeafIncomingArgsToStackPointer(context, conv);
        if (rewroteIncomingArgs)
            buildSavedRegsPlan(context, conv);
    }
    if (pushedRegs_.empty() && !savedRegsStackSubSize_ && !useFramePointer_)
    {
        context.passChanged = remappedPersistentRegsToTransient || rewroteIncomingArgs;
        return Result::Continue;
    }

    const auto beginIt = context.instructions->view().begin();
    if (beginIt != context.instructions->view().end())
    {
        insertSavedRegsPrologue(context, conv, beginIt.current);
        // Insertions before a Ret preserve its successor. Walk from the
        // original first instruction to skip the newly inserted prologue.
        for (auto it = beginIt; it != context.instructions->view().end(); ++it)
        {
            if (it->op == MicroInstrOpcode::Ret)
                insertSavedRegsEpilogue(context, conv, it.current);
        }
    }

    context.passChanged = beginIt.current.isValid() || remappedPersistentRegsToTransient || rewroteIncomingArgs;
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
    savedRegsStackSubSize_     = 0;
    useFramePointer_           = context.forceFramePointer;
    bool     framePointerNamed = false;
    uint64_t classifiedRegs    = 0;

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

            // Merely naming the frame pointer requests its setup. Every
            // other register matters only at its first definition.
            if (reg.isInt() && reg == conv.framePointer)
            {
                if (conv.isIntPersistentReg(reg))
                {
                    useFramePointer_  = true;
                    framePointerNamed = true;
                }
                continue;
            }
            if (!microInstrRef.def)
                continue;

            const uint32_t bit = MicroPhysLiveness::bitOf(reg);
            if (bit < MicroPhysLiveness::K_INVALID_BIT)
            {
                const uint64_t mask = 1ull << bit;
                if (classifiedRegs & mask)
                    continue;
                classifiedRegs |= mask;
            }

            if (reg.isInt())
            {
                if (!conv.isIntPersistentReg(reg))
                    continue;

                if (!containsPushedReg(reg))
                    pushedRegs_.push_back(reg);
            }
            else if (reg.isFloat())
            {
                if (!conv.isFloatPersistentReg(reg))
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
    // where the unwind codes cannot describe it: the description holds the nonvolatile pushes,
    // ONE allocation, and the float saves that follow it. A body whose whole stack shape is one
    // subtract at entry and one add before each return fits, because the saved-register area is
    // folded into that subtract below instead of taking a second allocation of its own. Anything
    // else - a body that keeps moving the stack pointer - still needs the frame register to cover
    // the difference, and it costs a push, a move and a pop on every call.
    //
    // The request is cleared, not just ignored: the sanitize pass synthesizes a setup for any
    // function that still asks for one, so both passes have to read the same answer.
    const bool     bodyStackIsOneAllocation = !bodyMovesStackPointerAfterPrologue(context, conv);
    const uint64_t bodyAllocation           = bodyStackIsOneAllocation ? findBodyEntryAllocation(context, conv) : 0;
    const bool     canMerge                 = bodyStackIsOneAllocation && bodyAllocation != 0;

    if (useFramePointer_ && !framePointerNamed && bodyStackIsOneAllocation && (savedRegSlots_.empty() || canMerge))
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

    // Fold that area into the body's allocation instead of emitting a second
    // one. The slots go to the top of the merged frame, so every `[sp + k]` the
    // body already computed still addresses the same byte, and the saves land
    // after the one allocation at final-rsp-relative offsets - which is what
    // UWOP_SAVE_XMM128 is defined against.
    mergedIntoBodyAllocation_ = false;
    bodyAllocationSize_       = 0;
    if (savedRegsStackSubSize_ && canMerge &&
        bodyAllocation <= std::numeric_limits<uint32_t>::max() - savedRegsStackSubSize_)
    {
        mergedIntoBodyAllocation_ = true;
        bodyAllocationSize_       = bodyAllocation;
        for (auto& slot : savedRegSlots_)
            slot.offset += bodyAllocation;
    }
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
    // Merged: the body's own subtract at entry grows to cover the saved area,
    // and the saves follow it. Otherwise the area takes its own allocation here.
    MicroInstrRef saveInsertBeforeRef = insertBeforeRef;
    if (mergedIntoBodyAllocation_)
    {
        // The entry allocation is a run of subtracts. The first one grows to
        // carry the saved area, and the saves go after the last, where the
        // stack pointer has reached its final value.
        MicroInstr*        bodyAlloc = instructions.ptr(insertBeforeRef);
        MicroInstrOperand* allocOps  = bodyAlloc ? bodyAlloc->ops(operands) : nullptr;
        SWC_ASSERT(allocOps && allocOps[0].reg == conv.stackPointer && allocOps[2].microOp == MicroOp::Subtract);
        allocOps[3].valueU64 += savedRegsStackSubSize_;

        MicroInstrRef lastSub = insertBeforeRef;
        for (MicroInstrRef cur = instructions.findNextInstructionRef(insertBeforeRef); cur.isValid();
             cur              = instructions.findNextInstructionRef(cur))
        {
            const MicroInstr* inst = instructions.ptr(cur);
            if (!inst)
                break;
            if (inst->op == MicroInstrOpcode::Nop)
                continue;
            if (!isStackPointerAdjust(*inst, inst->ops(operands), conv.stackPointer, MicroOp::Subtract))
                break;
            lastSub = cur;
        }
        saveInsertBeforeRef = instructions.findNextInstructionRef(lastSub);
    }
    else if (savedRegsStackSubSize_)
    {
        insertStackAdjust(context, insertBeforeRef, conv.stackPointer, MicroOp::Subtract, savedRegsStackSubSize_);
    }

    // Float persistent regs use explicit stack slots because there is no
    // push/pop form.
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        MicroInstrOperand storeOps[4];
        storeOps[0].reg      = conv.stackPointer;
        storeOps[1].reg      = slot.reg;
        storeOps[2].opBits   = slot.slotBits;
        storeOps[3].valueU64 = slot.offset;
        instructions.insertSyntheticBefore(operands, saveInsertBeforeRef, MicroInstrOpcode::LoadMemReg, storeOps);
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
    // Merged: the reloads must read the slots before the body's add releases
    // them, and that add grows to release the saved area too. The run of adds
    // in front of a return is what the plan matched, so the first of them is
    // where the reloads go.
    MicroInstrRef reloadBeforeRef = insertBeforeRef;
    if (mergedIntoBodyAllocation_)
    {
        MicroInstrRef  firstAdd = MicroInstrRef::invalid();
        const uint64_t released = sumEpilogueAdds(context, conv.stackPointer, insertBeforeRef, firstAdd);
        SWC_ASSERT(firstAdd.isValid() && released == bodyAllocationSize_);

        MicroInstr*        addInst = instructions.ptr(firstAdd);
        MicroInstrOperand* addOps  = addInst->ops(operands);
        addOps[3].valueU64 += savedRegsStackSubSize_;
        reloadBeforeRef = firstAdd;
    }

    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        MicroInstrOperand loadOps[4];
        loadOps[0].reg      = slot.reg;
        loadOps[1].reg      = conv.stackPointer;
        loadOps[2].opBits   = slot.slotBits;
        loadOps[3].valueU64 = slot.offset;
        instructions.insertSyntheticBefore(operands, reloadBeforeRef, MicroInstrOpcode::LoadRegMem, loadOps);
    }

    if (savedRegsStackSubSize_ && !mergedIntoBodyAllocation_)
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
