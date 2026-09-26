#include "pch.h"
#include "Backend/Micro/Passes/Pass.PrologEpilogSanitize.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroStorage.h"
#include "Main/Command/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Report/Assert.h"

// Tidies up the prologue / epilogue produced by lowering before final emission.
//
//   sanitizePrologueFramePointerSetups
//       Promotes a stray `mov fp, sp` / `lea fp, [sp]` redundantly emitted by
//       earlier stages to a single canonical setup placed right after the
//       frame-pointer push. When --force-frame-pointer is on but no setup was
//       produced, one is synthesized.
//
//   sanitizePrologueStackAdjustments
//       Coalesces consecutive `sub sp, c1` / `sub sp, c2` pairs into a single
//       subtract. Encoder conformance is re-checked so we do not produce an
//       immediate the target cannot encode.
//
//   eraseUnusedStackFrame
//       Drops the local-stack subtract and its releases when the body calls
//       nothing and no longer addresses the stack.
//
//   compactUnusedStackPrefix
//       Trims a fixed call frame with no surviving stack access, or rebases
//       allocator-owned spills above its unused prefix without moving ABI
//       argument slots.
//
//   reserveBodyCallShadow
//       Keeps one ABI call area below a local frame's saved stack base, then
//       restores the original stack address before the final argument frame.
//
//   hoistLoopCallFrame
//       Moves a balanced call frame around one call to the enclosing loop's
//       entry and exit when no other operation in that loop observes rsp.
//
//   expandLargePrologueStackAdjustments
//       Windows requires touching every guard page when growing the stack by
//       more than one page, so a function that subtracts more than 4 KiB needs
//       explicit probe loads. The expansion inserts one dummy load per page
//       between the subtract and the body so the guard pages fault in order.
//
//   sanitizeEpilogueStackAdjustments
//       Same coalescing as the prologue version but applied backwards from
//       each Ret over the run of epilogue instructions.

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint64_t K_WINDOWS_STACK_PROBE_PAGE_SIZE = 4096;

    bool isFramePointerSetupInstruction(const CallConv& conv, const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg stackPointer)
    {
        if (!ops || !conv.framePointer.isValid())
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
                return ops[0].reg == conv.framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;

            case MicroInstrOpcode::LoadAddrRegMem:
                return ops[0].reg == conv.framePointer && ops[1].reg == stackPointer && ops[2].opBits == MicroOpBits::B64;

            default:
                return false;
        }
    }

    bool isStackAdjustWithOp(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer, MicroOp expectedOp, uint64_t& outImmediate)
    {
        outImmediate = 0;
        if (!ops || inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        if (ops[0].reg != stackPointer || ops[1].opBits != MicroOpBits::B64)
            return false;
        if (ops[2].microOp != expectedOp)
            return false;

        const ApInt immediate = ops[3].immediateValue(64);
        if (!immediate.fit64())
            return false;

        outImmediate = immediate.as64();
        return true;
    }

    bool isPrologueInstruction(const CallConv& conv, const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::Push:
                return true;

            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
                return isFramePointerSetupInstruction(conv, inst, ops, stackPointer);

            case MicroInstrOpcode::LoadMemReg:
                return ops[0].reg == stackPointer;

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                uint64_t immediate = 0;
                return isStackAdjustWithOp(inst, ops, stackPointer, MicroOp::Subtract, immediate);
            }

            default:
                return false;
        }
    }

    bool isEpilogueInstruction(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg stackPointer)
    {
        if (!ops)
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::Pop:
                return true;

            case MicroInstrOpcode::LoadRegMem:
                return ops[1].reg == stackPointer;

            case MicroInstrOpcode::OpBinaryRegImm:
            {
                uint64_t immediate = 0;
                return isStackAdjustWithOp(inst, ops, stackPointer, MicroOp::Add, immediate);
            }

            default:
                return false;
        }
    }

    bool tryMergeAdjacentStackAdjust(const MicroPassContext& context, MicroInstrRef firstRef, MicroInstrRef secondRef, MicroReg stackPointer, MicroOp expectedOp)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (firstRef.isInvalid() || secondRef.isInvalid())
            return false;
        if (context.instructions->findPreviousInstructionRef(secondRef) != firstRef)
            return false;

        const MicroInstr* firstInst  = context.instructions->ptr(firstRef);
        const MicroInstr* secondInst = context.instructions->ptr(secondRef);
        if (!firstInst || !secondInst)
            return false;

        MicroInstrOperand*       firstOps  = firstInst->ops(*context.operands);
        const MicroInstrOperand* secondOps = secondInst->ops(*context.operands);
        if (!firstOps || !secondOps)
            return false;

        uint64_t firstImmediate  = 0;
        uint64_t secondImmediate = 0;
        if (!isStackAdjustWithOp(*firstInst, firstOps, stackPointer, expectedOp, firstImmediate))
            return false;
        if (!isStackAdjustWithOp(*secondInst, secondOps, stackPointer, expectedOp, secondImmediate))
            return false;
        if (firstImmediate > std::numeric_limits<uint64_t>::max() - secondImmediate)
            return false;

        const ApInt    originalImmediate = firstOps[3].immediateValue(64);
        const uint64_t mergedImmediate   = firstImmediate + secondImmediate;
        firstOps[3].setImmediateValue(ApInt(mergedImmediate, 64));

        if (MicroPassHelpers::violatesEncoderConformance(context, *firstInst, firstOps))
        {
            firstOps[3].setImmediateValue(originalImmediate);
            return false;
        }

        context.instructions->erase(secondRef);
        return true;
    }

    bool sanitizePrologueFramePointerSetups(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (!conv.framePointer.isValid())
            return false;

        // Establish the frame pointer only AFTER the stack frame is fully shaped (all nonvolatile pushes
        // and the stack subtract), as `mov fp, sp`, so the frame register equals the final post-prologue
        // stack pointer. UWOP_SET_FPREG then encodes FrameOffset 0 -- a relation (`fp == final_sp`) that
        // actually holds, for ANY frame size (no <= 240 / 16-multiple constraint) -- so the function is
        // walkable by strict unwinders (Visual Studio, lldb) as well as by the OS unwinder used for
        // compile-time `#run`/`#test` execution. The legacy form placed `mov fp, sp` at the top, before
        // the pushes/subtract, leaving fp at `entry_sp - sizeof(void*)` while UWOP_SET_FPREG still claimed
        // FrameOffset 0: the OS unwinder tolerated the lie, but Visual Studio and lldb rejected the frame
        // (callers shown as external code / the call stack failed to walk). Anchoring fp at the final
        // stack pointer is also what makes functions that lower their argument area with a dynamic
        // `sub sp` in the body unwindable at all: the unwinder recovers `sp = fp` independently of the
        // current, dynamically lowered stack pointer (a frame register is required; FPO cannot describe
        // those frames).
        //
        // The body was generated assuming fp sits at the saved-fp slot (entry_sp - sizeof(void*)), i.e.
        // `frameDelta` bytes ABOVE the final stack pointer, and addresses stack arguments as `[fp + disp]`
        // under that assumption. Since fp is now `frameDelta` lower, each frame-pointer-relative access is
        // re-anchored by adding frameDelta to its displacement so it still reaches the same address.
        std::vector<MicroInstrRef> framePointerSetupRefs;
        MicroInstrRef              framePointerPushRef = MicroInstrRef::invalid();
        MicroInstrRef              afterStackShapeRef  = MicroInstrRef::invalid();
        uint64_t                   frameDelta          = 0;
        bool                       seenPrologueStore   = false;

        for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
        {
            const MicroInstrOperand* ops = it->ops(*context.operands);
            if (!isPrologueInstruction(conv, *it, ops, conv.stackPointer))
                break;

            if (it->op == MicroInstrOpcode::Push)
            {
                auto nextIt = it;
                ++nextIt;

                if (ops && ops[0].reg == conv.framePointer && framePointerPushRef.isInvalid())
                    framePointerPushRef = it.current;
                else
                    frameDelta += sizeof(uint64_t);

                afterStackShapeRef = nextIt.current;
                continue;
            }

            if (it->op == MicroInstrOpcode::LoadMemReg)
            {
                seenPrologueStore = true;
                continue;
            }

            uint64_t subtractImmediate = 0;
            if (isStackAdjustWithOp(*it, ops, conv.stackPointer, MicroOp::Subtract, subtractImmediate))
            {
                // A subtract after the saved-register stores is the body's own
                // (its frame, its spill area, a call adjust) — the prologue's
                // stack shape ended with the stores. The frame pointer must
                // anchor above such subtracts: the unwinder recovers the stack
                // pointer from it, which is what keeps a frame walkable no
                // matter how the body moves the stack pointer afterwards, and
                // the unwind scanner can only describe the setup while it is
                // still inside the tracked prologue.
                if (seenPrologueStore)
                    break;

                frameDelta += subtractImmediate;

                auto nextIt = it;
                ++nextIt;
                afterStackShapeRef = nextIt.current;
                continue;
            }

            if (isFramePointerSetupInstruction(conv, *it, ops, conv.stackPointer))
                framePointerSetupRefs.push_back(it.current);
        }

        const bool hasFramePointerSetup = !framePointerSetupRefs.empty();
        if (!hasFramePointerSetup && !context.forceFramePointer)
            return false;

        const MicroInstrRef insertBeforeRef = afterStackShapeRef;
        if (!insertBeforeRef.isValid())
            return false;

        // Re-anchor every frame-pointer-relative memory access from the old fp (saved-fp slot) to the new
        // fp (final stack pointer), which is frameDelta lower: `[fp + disp]` -> `[fp + disp + frameDelta]`.
        if (frameDelta != 0)
        {
            for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
            {
                const MicroInstrDef& def = MicroInstr::info(it->op);
                if (!def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
                    continue;
                MicroInstrOperand* ops = it->ops(*context.operands);
                if (!ops || ops[def.memBaseOperandIndex].reg != conv.framePointer)
                    continue;
                ops[def.memOffsetOperandIndex].valueU64 += frameDelta;
            }
        }

        constexpr auto setupOpcode = MicroInstrOpcode::LoadRegReg;

        MicroInstrOperand setFrameOps[3];
        setFrameOps[0].reg    = conv.framePointer;
        setFrameOps[1].reg    = conv.stackPointer;
        setFrameOps[2].opBits = MicroOpBits::B64;

        context.instructions->insertSyntheticBefore(*context.operands, insertBeforeRef, setupOpcode, setFrameOps);

        bool changed = true;
        for (const MicroInstrRef ref : framePointerSetupRefs)
            changed |= context.instructions->erase(ref);

        return changed;
    }

    bool sanitizePrologueStackAdjustments(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        bool changedAny = false;
        bool retry      = true;
        while (retry)
        {
            retry     = false;
            auto view = context.instructions->view();
            for (auto it = view.begin(); it != view.end(); ++it)
            {
                const MicroInstrOperand* ops = it->ops(*context.operands);
                if (!isPrologueInstruction(conv, *it, ops, conv.stackPointer))
                    return changedAny;

                auto nextIt = it;
                ++nextIt;
                if (nextIt == view.end())
                    return changedAny;

                const MicroInstrOperand* nextOps = nextIt->ops(*context.operands);
                if (!isPrologueInstruction(conv, *nextIt, nextOps, conv.stackPointer))
                    return changedAny;

                if (tryMergeAdjacentStackAdjust(context, it.current, nextIt.current, conv.stackPointer, MicroOp::Subtract))
                {
                    changedAny = true;
                    retry      = true;
                    break;
                }
            }
        }

        return changedAny;
    }

    // The release run in front of a Ret: stack adds, then the pops of the saved
    // registers. True when `addRef` starts such a run.
    bool isFrameRelease(const MicroPassContext& context, const MicroInstrRef addRef)
    {
        for (MicroInstrRef ref = context.instructions->findNextInstructionRef(addRef); ref.isValid(); ref = context.instructions->findNextInstructionRef(ref))
        {
            const MicroInstr* inst = context.instructions->ptr(ref);
            if (!inst)
                return false;
            if (inst->op == MicroInstrOpcode::Ret)
                return true;
            if (inst->op == MicroInstrOpcode::Pop || inst->op == MicroInstrOpcode::Nop)
                continue;
            return false;
        }

        return false;
    }

    // Allocation decides which nonvolatile registers the prologue saves, and the
    // post-allocation peephole can still forward every use of one away: an
    // argument copied into rsi whose readers now read rcx. LLVM computes the
    // callee-saved set from the final code (determineCalleeSaves runs after
    // every rewrite of the function body), so a save the body no longer needs is
    // dropped here. The subtract grows by the freed slot: the final stack
    // pointer, every stack-relative offset, the frame-pointer anchor and the call
    // alignment all stay exactly as they were.
    bool eraseUnusedRegisterSaves(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        const MicroReg stackPointer = conv.stackPointer;

        struct Save
        {
            MicroInstrRef              pushRef = MicroInstrRef::invalid();
            MicroReg                   reg;
            bool                       used = false;
            SmallVector<MicroInstrRef> popRefs;
        };

        SmallVector<Save>                    saves;
        MicroInstrRef                        frameRef   = MicroInstrRef::invalid();
        uint64_t                             frameSize  = 0;
        bool                                 inEntryRun = true;
        SmallVector<MicroInstrRef>           rets;
        const auto                           markUsed = [&saves](const MicroReg reg) {
            for (Save& save : saves)
            {
                if (save.reg == reg)
                    save.used = true;
            }
        };

        for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
        {
            const MicroInstr& inst = *it;
            if (inst.op == MicroInstrOpcode::Nop || inst.op == MicroInstrOpcode::Label)
                continue;
            const MicroInstrOperand* ops = inst.ops(*context.operands);

            uint64_t immediate = 0;
            if (inEntryRun)
            {
                if (inst.op == MicroInstrOpcode::Push && ops && frameRef.isInvalid())
                {
                    // The frame-pointer save anchors the frame; it is never dropped.
                    if (ops[0].reg != conv.framePointer)
                        saves.push_back({.pushRef = it.current, .reg = ops[0].reg});
                    continue;
                }

                if (frameRef.isInvalid() && isStackAdjustWithOp(inst, ops, stackPointer, MicroOp::Subtract, immediate))
                {
                    frameRef  = it.current;
                    frameSize = immediate;
                    continue;
                }

                if (saves.empty() || frameRef.isInvalid())
                    return false;
                inEntryRun = false;
            }

            if (inst.op == MicroInstrOpcode::Ret)
            {
                rets.push_back(it.current);
                continue;
            }

            // A pop restores a save only inside the release run of a Ret.
            if (inst.op == MicroInstrOpcode::Pop && ops)
            {
                bool matched = false;
                for (Save& save : saves)
                {
                    if (save.reg == ops[0].reg && isFrameRelease(context, it.current))
                    {
                        save.popRefs.push_back(it.current);
                        matched = true;
                    }
                }

                if (!matched)
                    markUsed(ops[0].reg);
                continue;
            }

            const MicroInstrFlags flags = MicroInstr::info(inst.op).flags;
            if (flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                (context.encoder && flags.has(MicroInstrFlagsE::EncoderRegUseDef)))
            {
                const MicroInstrUseDef useDef = inst.collectUseDef(*context.operands, context.encoder);
                for (const MicroReg reg : useDef.uses)
                    markUsed(reg);
                for (const MicroReg reg : useDef.defs)
                    markUsed(reg);
            }
            else if (ops)
            {
                const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
                for (size_t i = 0; i < modes.size(); ++i)
                {
                    if (modes[i] != MicroInstrRegMode::None)
                        markUsed(ops[i].reg);
                }
            }
        }

        if (inEntryRun || rets.empty())
            return false;

        // Each Ret is released by `add sp, frame` followed by the pops.
        SmallVector<MicroInstrRef> releaseRefs;
        for (const MicroInstrRef retRef : rets)
        {
            MicroInstrRef ref = context.instructions->findPreviousInstructionRef(retRef);
            while (ref.isValid())
            {
                const MicroInstr* inst = context.instructions->ptr(ref);
                if (!inst || (inst->op != MicroInstrOpcode::Pop && inst->op != MicroInstrOpcode::Nop))
                    break;
                ref = context.instructions->findPreviousInstructionRef(ref);
            }

            const MicroInstr* release   = ref.isValid() ? context.instructions->ptr(ref) : nullptr;
            uint64_t          immediate = 0;
            if (!release || !isStackAdjustWithOp(*release, release->ops(*context.operands), stackPointer, MicroOp::Add, immediate) || immediate != frameSize)
                return false;
            releaseRefs.push_back(ref);
        }

        uint64_t freed = 0;
        for (const Save& save : saves)
        {
            if (!save.used && save.popRefs.size() == rets.size())
                freed += sizeof(uint64_t);
        }

        if (!freed)
            return false;

        // Grow the subtract and every release first: an immediate the encoder
        // refuses leaves the function untouched.
        const auto growAdjust = [&context](const MicroInstrRef ref, const uint64_t newSize) {
            const MicroInstr*  inst = context.instructions->ptr(ref);
            MicroInstrOperand* ops  = inst->ops(*context.operands);
            const ApInt        old  = ops[3].immediateValue(64);
            ops[3].setImmediateValue(ApInt(newSize, 64));
            if (!MicroPassHelpers::violatesEncoderConformance(context, *inst, ops))
                return true;
            ops[3].setImmediateValue(old);
            return false;
        };

        if (!growAdjust(frameRef, frameSize + freed))
            return false;
        for (const MicroInstrRef ref : releaseRefs)
            SWC_INTERNAL_CHECK(growAdjust(ref, frameSize + freed));

        for (const Save& save : saves)
        {
            if (save.used || save.popRefs.size() != rets.size())
                continue;
            context.instructions->erase(save.pushRef);
            for (const MicroInstrRef ref : save.popRefs)
                context.instructions->erase(ref);
        }

        return true;
    }

    // Lowering reserves the local stack before the body is optimized. Once every
    // local lives in a register and the body calls nothing, that subtract and its
    // releases only move the stack pointer down and back up. LLVM sizes the frame
    // from the objects that survive (X86FrameLowering::emitPrologue emits no
    // allocation for a leaf without stack objects), so a frame nothing addresses
    // is dropped here: no call, no stack-pointer operand other than the entry
    // subtract and the release in front of each Ret. A leaf does not need the
    // call alignment the subtract may also have carried.
    bool eraseUnusedStackFrame(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (context.forceFramePointer)
            return false;

        const MicroReg                       stackPointer = conv.stackPointer;
        MicroInstrRef                        frameRef     = MicroInstrRef::invalid();
        uint64_t                             frameSize    = 0;
        uint32_t                             numRets      = 0;
        bool                                 inEntryRun   = true;
        SmallVector<MicroInstrRef>           releaseRefs;
        for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
        {
            const MicroInstr& inst = *it;
            if (inst.op == MicroInstrOpcode::Nop || inst.op == MicroInstrOpcode::Label)
                continue;
            const MicroInstrOperand* ops = inst.ops(*context.operands);

            uint64_t immediate = 0;
            if (inEntryRun)
            {
                if (inst.op == MicroInstrOpcode::Push)
                    continue;
                if (frameRef.isInvalid() && isStackAdjustWithOp(inst, ops, stackPointer, MicroOp::Subtract, immediate))
                {
                    frameRef  = it.current;
                    frameSize = immediate;
                    continue;
                }

                if (frameRef.isInvalid())
                    return false;
                inEntryRun = false;
            }

            if (inst.op == MicroInstrOpcode::Ret)
            {
                ++numRets;
                continue;
            }

            if (inst.op == MicroInstrOpcode::Pop)
                continue;

            if (isStackAdjustWithOp(inst, ops, stackPointer, MicroOp::Add, immediate))
            {
                if (immediate != frameSize || !isFrameRelease(context, it.current))
                    return false;
                releaseRefs.push_back(it.current);
                continue;
            }

            if (inst.op == MicroInstrOpcode::Push || MicroInstr::info(inst.op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;

            if (!ops)
                continue;
            const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] != MicroInstrRegMode::None && ops[i].reg == stackPointer)
                    return false;
            }
        }

        // A pop outside a release run would read a slot the pushes did not
        // write; isFrameRelease only admits pops between a release and its Ret.
        if (frameRef.isInvalid() || numRets == 0 || releaseRefs.size() != numRets)
            return false;

        context.instructions->erase(frameRef);
        for (const MicroInstrRef ref : releaseRefs)
            context.instructions->erase(ref);
        return true;
    }

    // Register allocation can leave a frame with no surviving stack access,
    // or with only spill slots far above the outgoing call area. Keep the ABI
    // shadow and call alignment; move only allocator-owned slots when present.
    // Outgoing argument slots have fixed offsets from rsp and must not move.
    // An address of the frame or a dynamic stack adjustment needs a fuller
    // layout analysis, so neither participates in this conservative rewrite.
    bool compactUnusedStackPrefix(const MicroPassContext& context, const CallConv& conv)
    {
        if (context.forceFramePointer || context.debugStackBasePhysReg.isValid() ||
            !conv.stackShadowSpace || !conv.stackAlignment)
            return false;

        enum class Phase : uint8_t { Entry, Body, Exit, Done };
        Phase phase = Phase::Entry;
        MicroInstrRef frameRef = MicroInstrRef::invalid();
        MicroInstrRef releaseRef = MicroInstrRef::invalid();
        uint64_t frameSize = 0;
        uint64_t firstOffset = UINT64_MAX;
        bool hasCall = false;
        struct StackAccess { MicroInstrRef ref; uint8_t offsetIndex; };
        SmallVector<StackAccess> accesses;
        MicroInstrRegOperandRefs regOperands;

        for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
        {
            const MicroInstr& inst = *it;
            if (inst.op == MicroInstrOpcode::Nop || inst.op == MicroInstrOpcode::Label)
                continue;
            MicroInstrOperand* ops = inst.ops(*context.operands);
            uint64_t adjust = 0;

            if (phase == Phase::Entry)
            {
                if (inst.op == MicroInstrOpcode::Push)
                    continue;
                if (!isStackAdjustWithOp(inst, ops, conv.stackPointer, MicroOp::Subtract, adjust) ||
                    adjust < conv.stackShadowSpace + conv.stackAlignment)
                    return false;
                frameRef = it.current;
                frameSize = adjust;
                phase = Phase::Body;
                continue;
            }
            if (phase == Phase::Body && isStackAdjustWithOp(inst, ops, conv.stackPointer, MicroOp::Add, adjust))
            {
                if (adjust != frameSize)
                    return false;
                releaseRef = it.current;
                phase = Phase::Exit;
                continue;
            }
            if (phase == Phase::Exit)
            {
                if (inst.op == MicroInstrOpcode::Pop)
                    continue;
                if (inst.op != MicroInstrOpcode::Ret)
                    return false;
                phase = Phase::Done;
                continue;
            }
            if (phase != Phase::Body || inst.op == MicroInstrOpcode::Push || inst.op == MicroInstrOpcode::Pop || inst.op == MicroInstrOpcode::Ret)
                return false;

            const MicroInstrDef& def = MicroInstr::info(inst.op);
            hasCall |= def.flags.has(MicroInstrFlagsE::IsCallInstruction);
            const bool directAccess = ops && def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
                                      ops[def.memBaseOperandIndex].reg == conv.stackPointer;
            if (directAccess)
            {
                if (inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem ||
                    ops[def.memOffsetOperandIndex].valueU64 > INT32_MAX)
                    return false;
                if (inst.op != MicroInstrOpcode::LoadMemReg && inst.op != MicroInstrOpcode::LoadRegMem)
                    return false;
                const uint64_t offset = ops[def.memOffsetOperandIndex].valueU64;
                const uint64_t width  = getNumBytes(ops[2].opBits);
                if (context.spillAreaLo >= context.spillAreaHi ||
                    offset < context.spillAreaLo || offset > context.spillAreaHi || width > context.spillAreaHi - offset)
                    return false;
                firstOffset = std::min(firstOffset, ops[def.memOffsetOperandIndex].valueU64);
                accesses.push_back({it.current, def.memOffsetOperandIndex});
            }

            regOperands.clear();
            inst.collectRegOperands(*context.operands, regOperands, context.encoder);
            for (const MicroInstrRegOperandRef& operand : regOperands)
            {
                if (operand.reg && *operand.reg == conv.stackPointer &&
                    (!directAccess || operand.reg != &ops[def.memBaseOperandIndex].reg))
                    return false;
            }
        }

        if (phase != Phase::Done || frameRef.isInvalid() || releaseRef.isInvalid())
            return false;

        uint64_t delta = 0;
        if (accesses.empty())
        {
            if (!hasCall || frameSize < conv.stackShadowSpace)
                return false;
            delta = ((frameSize - conv.stackShadowSpace) / conv.stackAlignment) * conv.stackAlignment;
        }
        else
        {
            if (firstOffset < conv.stackShadowSpace + conv.stackAlignment)
                return false;
            delta = ((firstOffset - conv.stackShadowSpace) / conv.stackAlignment) * conv.stackAlignment;
        }
        if (!delta || delta >= frameSize)
            return false;

        for (const StackAccess access : accesses)
            context.instructions->ptr(access.ref)->ops(*context.operands)[access.offsetIndex].valueU64 -= delta;
        context.instructions->ptr(frameRef)->ops(*context.operands)[3].setImmediateValue(ApInt(frameSize - delta, 64));
        context.instructions->ptr(releaseRef)->ops(*context.operands)[3].setImmediateValue(ApInt(frameSize - delta, 64));
        return true;
    }

    // A local frame based on a saved copy of rsp can keep the ABI shadow
    // permanently below that copy. Calls in the body then need no per-call
    // sub/add pair. A later argument frame gives the reserve back before its
    // own contents are addressed, so its rsp and the epilogue stay unchanged.
    bool reserveBodyCallShadow(const MicroPassContext& context, const CallConv& conv)
    {
        if (!context.encoder || conv.stackShadowSpace != 32 || conv.stackAlignment != 16 ||
            !conv.framePointer.isValid())
            return false;

        constexpr uint64_t K_RESERVE = 40;
        SmallVector<MicroInstrRef> order;
        for (auto it = context.instructions->view().begin(), end = context.instructions->view().end(); it != end; ++it)
            order.push_back(it.current);
        if (order.size() < 12)
            return false;

        const auto get = [&](size_t index) -> const MicroInstr* {
            return index < order.size() ? context.instructions->ptr(order[index]) : nullptr;
        };
        const auto opsAt = [&](size_t index) -> const MicroInstrOperand* {
            const MicroInstr* inst = get(index);
            return inst ? inst->ops(*context.operands) : nullptr;
        };

        // The frame-pointer setup must precede the body allocation. The local
        // base copy keeps pointing at the old local frame when rsp moves down.
        size_t bodyBase = order.size();
        uint64_t frameSize = 0;
        bool sawFramePointer = false;
        for (size_t i = 0; i + 1 < order.size() && i < 32; ++i)
        {
            const MicroInstr* inst = get(i);
            const MicroInstrOperand* ops = opsAt(i);
            if (inst && isFramePointerSetupInstruction(conv, *inst, ops, conv.stackPointer))
            {
                sawFramePointer = true;
                continue;
            }
            uint64_t adjust = 0;
            const MicroInstr* next = get(i + 1);
            const MicroInstrOperand* nextOps = opsAt(i + 1);
            if (sawFramePointer && inst && isStackAdjustWithOp(*inst, ops, conv.stackPointer, MicroOp::Subtract, adjust) &&
                adjust >= K_RESERVE && adjust <= INT32_MAX - K_RESERVE && adjust % conv.stackAlignment == 0 &&
                next && next->op == MicroInstrOpcode::LoadRegReg &&
                nextOps && nextOps[1].reg == conv.stackPointer && nextOps[0].reg != conv.framePointer &&
                nextOps[0].reg.isInt() && nextOps[2].opBits == MicroOpBits::B64)
            {
                bodyBase = i + 1;
                frameSize = adjust;
                break;
            }
        }
        if (bodyBase == order.size() || bodyBase + 1 >= order.size())
            return false;

        struct Access { MicroInstrRef ref; uint8_t offsetIndex; uint64_t newOffset; };
        SmallVector<Access> accesses;
        SmallVector<MicroInstrRef> callAdjusts;
        MicroInstrRegOperandRefs regs;
        size_t tailStart = order.size();
        size_t finalAdd = order.size();
        uint64_t tailSubtract = 0;
        uint32_t retCount = 0;
        uint32_t foldedCalls = 0;
        for (size_t i = bodyBase + 1; i < order.size(); ++i)
        {
            const MicroInstr* inst = get(i);
            const MicroInstrOperand* ops = opsAt(i);
            if (!inst)
                return false;
            if (inst->op == MicroInstrOpcode::Ret)
            {
                if (finalAdd == order.size())
                    return false;
                ++retCount;
                continue;
            }
            if (finalAdd != order.size())
            {
                if (inst->op != MicroInstrOpcode::Nop &&
                    !isEpilogueInstruction(*inst, ops, conv.stackPointer))
                    return false;
                continue;
            }

            uint64_t adjust = 0;
            if (isStackAdjustWithOp(*inst, ops, conv.stackPointer, MicroOp::Subtract, adjust))
            {
                if (tailStart != order.size())
                {
                    if (finalAdd != order.size() || adjust > UINT64_MAX - tailSubtract)
                        return false;
                    tailSubtract += adjust;
                    continue;
                }
                if (adjust != K_RESERVE)
                {
                    if (adjust <= K_RESERVE)
                        return false;
                    tailStart = i;
                    tailSubtract = adjust;
                    continue;
                }

                // The simple call frame may contain register argument setup,
                // but no stack access, label or second call before its release.
                bool sawCall = false;
                size_t release = i + 1;
                for (; release < order.size(); ++release)
                {
                    const MicroInstr* step = get(release);
                    const MicroInstrOperand* stepOps = opsAt(release);
                    uint64_t releaseAmount = 0;
                    if (step && isStackAdjustWithOp(*step, stepOps, conv.stackPointer, MicroOp::Add, releaseAmount))
                    {
                        if (releaseAmount == K_RESERVE && sawCall)
                            break;
                        return false;
                    }
                    if (!step || step->op == MicroInstrOpcode::Label || step->op == MicroInstrOpcode::JumpCond ||
                        step->op == MicroInstrOpcode::Ret || step->op == MicroInstrOpcode::Push || step->op == MicroInstrOpcode::Pop ||
                        isStackAdjustWithOp(*step, stepOps, conv.stackPointer, MicroOp::Subtract, releaseAmount))
                        return false;
                    if (MicroInstr::info(step->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                    {
                        if (sawCall)
                            return false;
                        sawCall = true;
                        continue;
                    }
                    regs.clear();
                    step->collectRegOperands(*context.operands, regs, context.encoder);
                    for (const MicroInstrRegOperandRef& operand : regs)
                        if (operand.reg && *operand.reg == conv.stackPointer)
                            return false;
                }
                if (release >= order.size())
                    return false;
                callAdjusts.push_back(order[i]);
                callAdjusts.push_back(order[release]);
                ++foldedCalls;
                i = release;
                continue;
            }

            if (isStackAdjustWithOp(*inst, ops, conv.stackPointer, MicroOp::Add, adjust))
            {
                if (tailStart == order.size() || finalAdd != order.size() ||
                    frameSize > UINT64_MAX - tailSubtract || adjust != frameSize + tailSubtract)
                    return false;
                finalAdd = i;
                continue;
            }

            if (tailStart != order.size())
            {
                if (finalAdd == order.size() && (inst->op == MicroInstrOpcode::Label || inst->op == MicroInstrOpcode::JumpCond))
                    return false;
                continue;
            }

            if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                inst->op == MicroInstrOpcode::Push || inst->op == MicroInstrOpcode::Pop)
                return false;
            const MicroInstrDef& def = MicroInstr::info(inst->op);
            const bool direct = ops && def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
                                ops[def.memBaseOperandIndex].reg == conv.stackPointer;
            if (direct)
            {
                if ((inst->op != MicroInstrOpcode::LoadRegMem && inst->op != MicroInstrOpcode::LoadMemReg) ||
                    inst->numOperands != 4 || ops[def.memOffsetOperandIndex].valueU64 > frameSize ||
                    getNumBytes(ops[2].opBits) > frameSize - ops[def.memOffsetOperandIndex].valueU64)
                    return false;
                MicroInstrOperand candidate[4];
                std::copy_n(ops, 4, candidate);
                candidate[def.memOffsetOperandIndex].valueU64 += K_RESERVE;
                if (MicroPassHelpers::violatesEncoderConformance(context, *inst, candidate))
                    return false;
                accesses.push_back({order[i], def.memOffsetOperandIndex, candidate[def.memOffsetOperandIndex].valueU64});
            }
            regs.clear();
            inst->collectRegOperands(*context.operands, regs, context.encoder);
            for (const MicroInstrRegOperandRef& operand : regs)
                if (operand.reg && *operand.reg == conv.stackPointer &&
                    (!direct || operand.reg != &ops[def.memBaseOperandIndex].reg))
                    return false;
        }

        if (!foldedCalls || tailStart == order.size() || finalAdd == order.size() || retCount != 1 ||
            finalAdd <= tailStart || finalAdd + 1 >= order.size())
            return false;
        const MicroInstr* tail = get(tailStart);
        const MicroInstrOperand* tailOps = opsAt(tailStart);
        MicroInstrOperand tailCandidate[4];
        std::copy_n(tailOps, 4, tailCandidate);
        tailCandidate[3].setImmediateValue(ApInt(tailOps[3].valueU64 - K_RESERVE, 64));
        if (MicroPassHelpers::violatesEncoderConformance(context, *tail, tailCandidate))
            return false;

        for (const Access& access : accesses)
            context.instructions->ptr(access.ref)->ops(*context.operands)[access.offsetIndex].valueU64 = access.newOffset;
        context.instructions->ptr(order[tailStart])->ops(*context.operands)[3] = tailCandidate[3];
        for (const MicroInstrRef ref : callAdjusts)
            context.instructions->erase(ref);

        MicroInstrOperand reserveOps[4];
        reserveOps[0].reg = conv.stackPointer;
        reserveOps[1].opBits = MicroOpBits::B64;
        reserveOps[2].microOp = MicroOp::Subtract;
        reserveOps[3].setImmediateValue(ApInt(K_RESERVE, 64));
        context.instructions->insertSyntheticBefore(*context.operands, order[bodyBase + 1], MicroInstrOpcode::OpBinaryRegImm, reserveOps);
        return true;
    }

    bool hoistLoopCallFrame(const MicroPassContext& context, const CallConv& conv)
    {
        if (!context.builder || !context.encoder)
            return false;
        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        if (!cfg.hasLoop() || cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;
        const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
        if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
            return false;
        const auto dom   = MicroPassHelpers::computeInstructionDominators(cfg, entry);
        auto       loops = MicroPassHelpers::findNaturalLoops(cfg, dom);
        if (loops.empty())
            return false;

        const auto refs = cfg.instructionRefs();
        const auto n    = cfg.instructionCount();
        std::vector<const MicroPassHelpers::NaturalLoop*> candidates;
        for (const auto& loop : loops | std::views::values)
            candidates.push_back(&loop);
        std::ranges::sort(candidates, [](const auto* lhs, const auto* rhs) { return lhs->bodySize > rhs->bodySize; });

        const auto flagsDeadUntilRedefined = [&](const uint32_t begin, const uint32_t end) {
            for (uint32_t i = begin; i < end; ++i)
            {
                const MicroInstr* inst = context.instructions->ptr(refs[i]);
                if (!inst)
                    return false;
                const auto* ops = inst->ops(*context.operands);
                if (MicroPassHelpers::instructionActuallyUsesCpuFlags(*inst, ops))
                    return false;
                if (MicroPassHelpers::instructionActuallyDefinesCpuFlags(*inst, ops))
                    return true;
                if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::JumpInstruction))
                    return false;
            }
            return true;
        };

        for (const auto* loop : candidates)
        {
            if (!loop->header || loop->tails.size() != 1)
                continue;
            const uint32_t header = loop->header;
            const uint32_t tail   = loop->tails[0];
            if (tail + 1 >= n || tail <= header || !loop->inBody[tail] || loop->bodySize != tail - header + 1)
                continue;
            const auto* tailInst = context.instructions->ptr(refs[tail]);
            if (!tailInst || !MicroInstr::info(tailInst->op).flags.has(MicroInstrFlagsE::ConditionalJump))
                continue;
            if (cfg.predecessors(header).size() != 2 || cfg.predecessors(tail + 1).size() != 1 ||
                cfg.predecessors(tail + 1)[0] != tail)
                continue;
            bool hasPreheader = false;
            bool hasBackEdge  = false;
            for (const uint32_t pred : cfg.predecessors(header))
            {
                hasPreheader |= pred == header - 1;
                hasBackEdge |= pred == tail;
            }
            if (!hasPreheader || !hasBackEdge)
                continue;

            bool enclosed = true;
            for (uint32_t i = header; i <= tail && enclosed; ++i)
            {
                if (!loop->inBody[i])
                {
                    enclosed = false;
                    break;
                }
                for (const uint32_t succ : cfg.successors(i))
                    if (succ >= n || (!loop->inBody[succ] && !(i == tail && succ == tail + 1)))
                        enclosed = false;
            }
            if (!enclosed)
                continue;

            uint32_t subIndex  = n;
            uint32_t addIndex  = n;
            uint32_t callCount = 0;
            uint64_t amount    = 0;
            bool inside        = false;
            MicroInstrRegOperandRefs regOperands;
            for (uint32_t i = header; i <= tail && enclosed; ++i)
            {
                const MicroInstr* inst = context.instructions->ptr(refs[i]);
                const auto* ops = inst ? inst->ops(*context.operands) : nullptr;
                if (!inst)
                {
                    enclosed = false;
                    break;
                }
                uint64_t adjust = 0;
                if (isStackAdjustWithOp(*inst, ops, conv.stackPointer, MicroOp::Subtract, adjust))
                {
                    if (inside || subIndex != n || !adjust || adjust > INT32_MAX)
                        enclosed = false;
                    else
                    {
                        subIndex = i;
                        amount   = adjust;
                        inside   = true;
                    }
                    continue;
                }
                if (isStackAdjustWithOp(*inst, ops, conv.stackPointer, MicroOp::Add, adjust))
                {
                    if (!inside || adjust != amount || callCount != 1)
                        enclosed = false;
                    else
                    {
                        addIndex = i;
                        inside   = false;
                    }
                    continue;
                }
                if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                {
                    if (!inside || ++callCount != 1)
                        enclosed = false;
                    continue;
                }
                if (inst->op == MicroInstrOpcode::Push || inst->op == MicroInstrOpcode::Pop)
                {
                    enclosed = false;
                    break;
                }
                regOperands.clear();
                inst->collectRegOperands(*context.operands, regOperands, context.encoder);
                for (const MicroInstrRegOperandRef& operand : regOperands)
                {
                    if (!operand.reg || *operand.reg != conv.stackPointer)
                        continue;
                    const MicroInstrDef& def = MicroInstr::info(inst->op);
                    const bool direct = ops && def.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
                                        operand.reg == &ops[def.memBaseOperandIndex].reg;
                    if (!inside || !direct)
                        enclosed = false;
                }
            }
            if (!enclosed || inside || subIndex == n || addIndex == n || callCount != 1 ||
                !flagsDeadUntilRedefined(header, subIndex) ||
                !flagsDeadUntilRedefined(subIndex + 1, addIndex) ||
                !flagsDeadUntilRedefined(addIndex + 1, tail + 1) ||
                !flagsDeadUntilRedefined(tail + 1, n))
                continue;

            MicroInstrOperand subtract[4];
            MicroInstrOperand release[4];
            std::copy_n(context.instructions->ptr(refs[subIndex])->ops(*context.operands), 4, subtract);
            std::copy_n(context.instructions->ptr(refs[addIndex])->ops(*context.operands), 4, release);
            context.instructions->erase(refs[subIndex]);
            context.instructions->erase(refs[addIndex]);
            context.instructions->insertSyntheticBefore(*context.operands, refs[header], MicroInstrOpcode::OpBinaryRegImm, subtract);
            context.instructions->insertSyntheticBefore(*context.operands, refs[tail + 1], MicroInstrOpcode::OpBinaryRegImm, release);
            return true;
        }
        return false;
    }

    bool needsWindowsStackProbe(const MicroPassContext& context, const uint64_t stackAdjust)
    {
        if (stackAdjust <= K_WINDOWS_STACK_PROBE_PAGE_SIZE)
            return false;
        if (!context.taskContext)
            return false;
        return context.taskContext->cmdLine().targetOs == Runtime::TargetOs::Windows;
    }

    bool expandLargePrologueStackAdjustments(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        if (!conv.intReturn.isValid() || !conv.intReturn.isInt())
            return false;

        for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
        {
            const MicroInstrOperand* ops = it->ops(*context.operands);
            if (!isPrologueInstruction(conv, *it, ops, conv.stackPointer))
                break;

            uint64_t stackAdjust = 0;
            if (!isStackAdjustWithOp(*it, ops, conv.stackPointer, MicroOp::Subtract, stackAdjust))
                continue;
            if (!needsWindowsStackProbe(context, stackAdjust))
                continue;

            auto nextIt = it;
            ++nextIt;
            if (nextIt == endIt)
                return false;

            while (nextIt != endIt)
            {
                const MicroInstrOperand* nextOps = nextIt->ops(*context.operands);
                if (!isFramePointerSetupInstruction(conv, *nextIt, nextOps, conv.stackPointer))
                    break;
                ++nextIt;
            }

            if (nextIt == endIt)
                return false;

            const MicroInstrRef insertBeforeRef = nextIt.current;
            uint64_t            remaining       = stackAdjust;

            MicroInstrOperand probeOps[4];
            probeOps[0].reg    = conv.intReturn;
            probeOps[1].reg    = conv.stackPointer;
            probeOps[2].opBits = MicroOpBits::B64;

            while (remaining > K_WINDOWS_STACK_PROBE_PAGE_SIZE)
            {
                remaining -= K_WINDOWS_STACK_PROBE_PAGE_SIZE;
                probeOps[3].valueU64 = remaining;
                context.instructions->insertSyntheticBefore(*context.operands, insertBeforeRef, MicroInstrOpcode::LoadRegMem, probeOps);
            }

            probeOps[3].valueU64 = 0;
            context.instructions->insertSyntheticBefore(*context.operands, insertBeforeRef, MicroInstrOpcode::LoadRegMem, probeOps);
            return true;
        }

        return false;
    }

    bool sanitizeEpilogueStackAdjustments(const MicroPassContext& context, const CallConv& conv)
    {
        SWC_ASSERT(context.instructions);
        SWC_ASSERT(context.operands);

        bool changedAny = false;
        for (auto it = context.instructions->view().begin(), endIt = context.instructions->view().end(); it != endIt; ++it)
        {
            if (it->op != MicroInstrOpcode::Ret)
                continue;

            // Merges erase only predecessors of this Ret, so its iterator and
            // successor remain valid throughout the suffix rewrite.
            const MicroInstrRef retRef   = it.current;
            MicroInstrRef       firstRef = retRef;
            for (MicroInstrRef ref = context.instructions->findPreviousInstructionRef(retRef); ref.isValid(); ref = context.instructions->findPreviousInstructionRef(ref))
            {
                const MicroInstr* inst = context.instructions->ptr(ref);
                if (!inst)
                    break;

                const MicroInstrOperand* ops = inst->ops(*context.operands);
                if (!isEpilogueInstruction(*inst, ops, conv.stackPointer))
                    break;
                firstRef = ref;
            }

            // The first suffix instruction cannot be the erased second member
            // of a pair. Survivors keep their opcode and remain in this suffix.
            for (MicroInstrRef ref = firstRef; ref != retRef;)
            {
                const MicroInstrRef nextRef = context.instructions->findNextInstructionRef(ref);
                if (nextRef == retRef)
                    break;

                if (tryMergeAdjacentStackAdjust(context, ref, nextRef, conv.stackPointer, MicroOp::Add))
                {
                    changedAny = true;
                    // Preserve retries of earlier rejected pairs after a
                    // neighboring immediate changes, including conformance.
                    ref = firstRef;
                }
                else
                    ref = nextRef;
            }
        }

        return changedAny;
    }
}

Result MicroPrologEpilogSanitizePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    const CallConv& conv                      = CallConv::get(context.callConvKind);
    const bool      changedFramePointerProlog = sanitizePrologueFramePointerSetups(context, conv);
    const bool      changedStackProlog        = sanitizePrologueStackAdjustments(context, conv);
    const bool      changedStackEpilogue      = sanitizeEpilogueStackAdjustments(context, conv);
    const bool      changedUnusedSaves        = eraseUnusedRegisterSaves(context, conv);
    const bool      changedUnusedFrame        = eraseUnusedStackFrame(context, conv);
    const bool      changedCompactFrame       = compactUnusedStackPrefix(context, conv);
    const bool      changedReservedCallShadow = reserveBodyCallShadow(context, conv);
    const bool      changedLoopCallFrame       = hoistLoopCallFrame(context, conv);
    const bool      changedStackProbeProlog   = expandLargePrologueStackAdjustments(context, conv);
    const bool      changed                   = changedFramePointerProlog || changedStackProlog || changedStackProbeProlog || changedStackEpilogue || changedUnusedSaves || changedUnusedFrame || changedCompactFrame || changedReservedCallShadow || changedLoopCallFrame;
    context.passChanged                       = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
