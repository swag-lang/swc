#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRALoopHoist.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Report/Assert.h"

// Post-RA loop-invariant reload hoisting. See the header for why this exists.

SWC_BEGIN_NAMESPACE();

namespace
{
    using MicroPassHelpers::MicroPhysLiveness;
    using MicroPassHelpers::NaturalLoop;

    // How many times the pass lifts a load one loop level. A load hoisted out of
    // an inner loop lands in the enclosing loop's body and may be invariant
    // there too; three levels covers every loop nest in the standard library
    // and bounds the cost on a pathological one.
    constexpr uint32_t K_MAX_LEVELS = 3;

    struct FrameRef
    {
        MicroReg base;
        uint64_t lo = 0;
        uint64_t hi = 0;
    };

    bool isFrameBaseRegister(const MicroReg reg, const CallConv& conv)
    {
        return reg.isValid() && (reg == conv.stackPointer || reg == conv.framePointer);
    }

    // A constant-offset frame write, whose range the slot analysis can compare
    // against the one being hoisted. An indexed write reaches an offset this pass
    // cannot bound and still makes the body opaque; a write through a program
    // pointer is answered by the frame-reachability test below instead.
    bool frameWriteRange(FrameRef& out, const MicroInstr& inst, const MicroInstrOperand* ops, const CallConv& conv, const MicroReg localBaseReg)
    {
        if (!ops)
            return false;

        auto     bits   = MicroOpBits::Zero;
        uint64_t offset = 0;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::StoreVecMemReg:
                bits   = ops[2].opBits;
                offset = ops[3].valueU64;
                break;
            case MicroInstrOpcode::LoadMemImm:
                bits   = ops[1].opBits;
                offset = ops[2].valueU64;
                break;
            case MicroInstrOpcode::OpBinaryMemReg:
                bits   = ops[2].opBits;
                offset = ops[4].valueU64;
                break;
            case MicroInstrOpcode::OpBinaryMemImm:
                bits   = ops[1].opBits;
                offset = ops[3].valueU64;
                break;
            case MicroInstrOpcode::OpUnaryMem:
                bits   = ops[1].opBits;
                offset = ops[3].valueU64;
                break;
            default:
                return false;
        }

        if (!isFrameBaseRegister(ops[0].reg, conv) && !(localBaseReg.isValid() && ops[0].reg == localBaseReg))
            return false;

        out.base = ops[0].reg;
        out.lo   = offset;
        out.hi   = offset + getNumBytes(bits);
        return true;
    }

    bool isFrameLoad(FrameRef& out, const MicroInstr& inst, const MicroInstrOperand* ops, const CallConv& conv, const MicroReg localBaseReg)
    {
        if (inst.op != MicroInstrOpcode::LoadRegMem || !ops)
            return false;
        if (!isFrameBaseRegister(ops[1].reg, conv) && !(localBaseReg.isValid() && ops[1].reg == localBaseReg))
            return false;

        out.base = ops[1].reg;
        out.lo   = ops[3].valueU64;
        out.hi   = out.lo + getNumBytes(ops[2].opBits);
        return true;
    }

    // What a program pointer can reach in this function's frame.
    //
    // The frame is the compiler's: nothing outside reaches it unless the function
    // hands out an address into it. When it never does, a store through a program
    // pointer cannot land on a frame slot however opaque that pointer is - which is
    // what lets a loop that writes pixels keep hoisting the strides and counts it
    // reloads on every iteration.
    //
    // A function with local variables addresses them through one register that
    // copies the resting stack pointer once in the prologue. Handing out
    // `&local` is then an address computed from that register, and it reaches
    // the one object it points into, nothing else - a pointer into one object
    // cannot roam the rest of the frame, which is the same per-object rule
    // mem2reg already relies on. So the escapes are classified per source
    // object, from the extents the function's symbols carry, and a slot no
    // escaped object contains stays private even when the frame as a whole
    // does not. Any appearance of a frame base this cannot account for - the
    // base handed out as a value, an address whose object extents are unknown -
    // falls back to the old answer: everything is reachable.
    struct FrameObject
    {
        int64_t  start   = 0;
        uint64_t size    = 0;
        bool     escaped = false;
    };

    // The two address spaces escape independently. A value use of the stack
    // pointer - call-argument staging, a parameter home handed out - reaches
    // sp-addressed slots, never the locals behind the base register: nothing
    // lands in local space without naming the base register, and the base
    // register's own leaks are classified per object. The allocator's spill
    // area stays unreachable under either: it holds no source object, so no
    // pointer can be made to land in it.
    struct FrameReachability
    {
        bool                     computed          = false;
        bool                     wholeFramePrivate = false;
        bool                     spSpaceEscapes    = false;
        bool                     localSpaceEscapes = false;
        MicroReg                 localBaseReg;
        bool                     extentsKnown = false;
        std::vector<FrameObject> objects;
    };

    // The single prologue copy of the resting stack pointer that all locals are
    // addressed against. Only a register defined exactly once, by that copy,
    // qualifies: a register the allocator later reuses means the same name
    // addresses two different things.
    MicroReg findLocalBaseRegister(MicroStorage& storage, MicroOperandStorage& operands, const CallConv& conv, const Encoder* encoder)
    {
        MicroReg candidate;
        for (const MicroInstr& inst : storage.view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops || ops[1].reg != conv.stackPointer)
                continue;
            if (isFrameBaseRegister(ops[0].reg, conv))
                continue;
            if (candidate.isValid() && candidate != ops[0].reg)
                return MicroReg::invalid();
            candidate = ops[0].reg;
        }
        if (!candidate.isValid())
            return MicroReg::invalid();

        uint32_t defCount = 0;
        for (const MicroInstr& inst : storage.view())
        {
            const MicroInstrDef& info = MicroInstr::info(inst.op);
            if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                (encoder && info.flags.has(MicroInstrFlagsE::EncoderRegUseDef)))
            {
                const MicroInstrUseDef useDef = inst.collectUseDef(operands, encoder);
                for (const MicroReg def : useDef.defs)
                    defCount += def == candidate ? 1 : 0;
            }
            else if (const MicroInstrOperand* ops = inst.ops(operands))
            {
                const auto modes = info.resolvedRegModes(ops);
                for (size_t i = 0; i < modes.size(); ++i)
                {
                    if ((modes[i] == MicroInstrRegMode::Def || modes[i] == MicroInstrRegMode::UseDef) && ops[i].reg == candidate)
                        ++defCount;
                }
            }
            if (defCount > 1)
                return MicroReg::invalid();
        }

        return defCount == 1 ? candidate : MicroReg::invalid();
    }

    void markEscapedObject(FrameReachability& out, const int64_t offset)
    {
        for (FrameObject& object : out.objects)
        {
            if (offset >= object.start && offset < object.start + static_cast<int64_t>(object.size))
            {
                object.escaped = true;
                return;
            }
        }

        // An address into no known object: the extents cannot vouch for what it
        // reaches.
        out.localSpaceEscapes = true;
    }

    void analyzeFrameReachability(FrameReachability& out, const MicroPassContext& context, MicroStorage& storage, MicroOperandStorage& operands, const CallConv& conv)
    {
        out.computed = true;

        if (context.sanitizerFunction)
        {
            out.extentsKnown = true;
            for (const SymbolVariable* symVar : context.sanitizerFunction->localVariables())
            {
                if (symVar && symVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack) && symVar->codeGenLocalSize())
                    out.objects.push_back({.start = static_cast<int64_t>(symVar->offset()), .size = symVar->codeGenLocalSize()});
            }
            for (const SymbolVariable* symVar : context.sanitizerFunction->parameters())
            {
                if (symVar && symVar->debugStackSlotSize())
                    out.objects.push_back({.start = static_cast<int64_t>(symVar->debugStackSlotOffset()), .size = symVar->debugStackSlotSize()});
            }
        }

        for (const MicroInstr& inst : storage.view())
        {
            const MicroInstrOperand* ops  = inst.ops(operands);
            const MicroInstrDef&     info = MicroInstr::info(inst.op);

            const auto isTrackedBase = [&](const MicroReg reg) {
                return isFrameBaseRegister(reg, conv) || (out.localBaseReg.isValid() && reg == out.localBaseReg);
            };

            if (inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
            {
                if (ops && isFrameBaseRegister(ops[1].reg, conv))
                {
                    // An address into the stack-pointer space: call-area
                    // staging and other shapes the extents cannot describe.
                    out.spSpaceEscapes = true;
                }
                else if (ops && out.localBaseReg.isValid() && ops[1].reg == out.localBaseReg)
                {
                    if (!out.extentsKnown)
                        out.localSpaceEscapes = true;
                    else if (inst.op == MicroInstrOpcode::LoadAddrRegMem)
                        markEscapedObject(out, static_cast<int64_t>(ops[3].valueU64));
                    else
                        markEscapedObject(out, static_cast<int64_t>(ops[6].valueU64));
                }
            }

            if (!ops)
                continue;
            const auto modes = info.resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] == MicroInstrRegMode::None || !isTrackedBase(ops[i].reg))
                    continue;
                if (inst.op == MicroInstrOpcode::Push || inst.op == MicroInstrOpcode::Pop)
                    continue;
                if (modes[i] == MicroInstrRegMode::Def || modes[i] == MicroInstrRegMode::UseDef)
                    continue;
                // The prologue copy that defines the local base is the one
                // legitimate value use of the stack pointer.
                if (inst.op == MicroInstrOpcode::LoadRegReg && ops &&
                    (isFrameBaseRegister(ops[0].reg, conv) || (out.localBaseReg.isValid() && ops[0].reg == out.localBaseReg)))
                    continue;
                if (info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) && i == info.memBaseOperandIndex)
                    continue;
                if (inst.op == MicroInstrOpcode::LoadAddrRegMem || inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
                    continue; // classified above, per object
                if (isFrameBaseRegister(ops[i].reg, conv))
                    out.spSpaceEscapes = true;
                else
                    out.localSpaceEscapes = true;
            }
        }

        out.wholeFramePrivate = !out.spSpaceEscapes && !out.localSpaceEscapes &&
                                std::ranges::none_of(out.objects, &FrameObject::escaped);
    }

    // The extent of the source object containing `offset`, as a write range
    // over the local-base space. An indexed access through the local base
    // stays inside the object its displacement names, so widening it to that
    // object is what makes it placeable.
    bool findContainingObject(FrameRef& out, const FrameReachability& reach, const MicroReg base, const int64_t offset)
    {
        if (!reach.extentsKnown)
            return false;

        for (const FrameObject& object : reach.objects)
        {
            if (offset >= object.start && offset < object.start + static_cast<int64_t>(object.size))
            {
                out.base = base;
                out.lo   = static_cast<uint64_t>(object.start);
                out.hi   = static_cast<uint64_t>(object.start) + object.size;
                return true;
            }
        }

        return false;
    }

    // Whether no program pointer can land on this slot: the whole frame is
    // private, the slot is the allocator's own (no source object overlaps the
    // spill area and no pointer can be made to reach it), or every escaped
    // object lies elsewhere and the slot sits wholly inside a known one.
    bool slotIsUnreachable(const FrameReachability& reach, const MicroPassContext& context, const FrameRef& slot, const CallConv& conv)
    {
        if (reach.wholeFramePrivate)
            return true;

        if (isFrameBaseRegister(slot.base, conv))
        {
            if (!reach.spSpaceEscapes)
                return true;
            return context.spillAreaLo < context.spillAreaHi && slot.lo >= context.spillAreaLo && slot.hi <= context.spillAreaHi;
        }

        if (reach.localSpaceEscapes || !reach.extentsKnown)
            return false;

        for (const FrameObject& object : reach.objects)
        {
            const auto start = static_cast<uint64_t>(object.start);
            if (slot.lo >= start && slot.hi <= start + object.size)
                return !object.escaped;
        }

        return false;
    }
    bool overlaps(const FrameRef& a, const FrameRef& b)
    {
        return a.base == b.base && a.lo < b.hi && b.lo < a.hi;
    }

    struct Hoist
    {
        MicroInstrRef ref;
        MicroInstrRef beforeRef;
    };

    // One loop-carried slot promoted out of memory: its load and store inside
    // the body go away, the register is seeded before the loop and written back
    // once after it.
    struct Carried
    {
        MicroInstrRef loadRef;
        MicroInstrRef storeRef;
        MicroInstrRef seedBeforeRef;   // insert the seeding load before this, or invalid if not needed
        MicroInstrRef writeBackBefore; // insert the write-back before this
        MicroReg      reg;
        MicroReg      base;
        uint64_t      offset = 0;
        MicroOpBits   bits   = MicroOpBits::Zero;
    };

    struct SunkStore
    {
        MicroInstrRef storeRef;
        MicroInstrRef writeBackBefore;
        MicroReg      source;
        MicroReg      base;
        uint64_t      offset = 0;
        MicroOpBits   bits   = MicroOpBits::Zero;
    };

    // A redundant reload whose destination is reused right afterwards for
    // something else: rather than leaving a register copy behind, point its
    // readers at the register the slot was hoisted into and report that the
    // load itself can go.
    //
    // The scan is linear and stops at anything that could bring in a different
    // value for the destination: a label (a join arrives with its own), a call,
    // an unconditional jump, or the end of the body. A conditional exit is
    // allowed through only when the destination is dead on the way out, so
    // nothing outside the loop can observe the register we stopped writing.
    // Success means a redefinition was reached, which is what makes the load
    // dead rather than merely redundant.
    bool redirectUsesToHoistedRegister(MicroStorage& storage, MicroOperandStorage& operands, const MicroControlFlowGraph& cfg, const MicroPhysLiveness& liveness, const std::vector<uint8_t>& inBody, const uint32_t loadIndex, const MicroReg hoisted, const Encoder* encoder)
    {
        const auto     instrRefs = cfg.instructionRefs();
        const uint32_t n         = cfg.instructionCount();

        const MicroInstr*        loadInst = storage.ptr(instrRefs[loadIndex]);
        const MicroInstrOperand* loadOps  = loadInst ? loadInst->ops(operands) : nullptr;
        if (!loadOps)
            return false;
        const MicroReg dead = loadOps[0].reg;

        // Pass one decides; nothing is rewritten until the whole stretch is known
        // to be safe.
        SmallVector<uint32_t> useSites;
        bool                  redefined = false;
        for (uint32_t k = loadIndex + 1; k < n && !redefined; ++k)
        {
            if (!inBody[k])
                return false;
            const MicroInstr* inst = storage.ptr(instrRefs[k]);
            if (!inst)
                return false;
            if (inst->op == MicroInstrOpcode::Label)
                return false;

            const MicroInstrDef&    info   = MicroInstr::info(inst->op);
            const MicroInstrUseDef& useDef = liveness.useDefs[k];
            if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) || useDef.isCall)
                return false;

            const bool usesDead = std::ranges::find(useDef.uses, dead) != useDef.uses.end();
            const bool defsDead = std::ranges::find(useDef.defs, dead) != useDef.defs.end();

            // A read-modify-write of the destination is both, and rewriting only
            // its read half would change what it writes.
            if (defsDead && usesDead)
                return false;
            if (defsDead)
            {
                redefined = true;
                break;
            }
            if (usesDead)
                useSites.push_back(k);

            if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
            {
                if (!info.flags.has(MicroInstrFlagsE::ConditionalJump))
                    return false;
                const uint32_t deadBit = MicroPhysLiveness::bitOf(dead);
                if (deadBit >= MicroPhysLiveness::K_INVALID_BIT)
                    return false;
                for (const uint32_t succ : cfg.successors(k))
                {
                    if (succ < n && !inBody[succ] && (liveness.liveIn[succ] & (1ull << deadBit)) != 0)
                        return false;
                }
            }
        }

        if (!redefined)
            return false;

        // Every rewritten instruction has to remain encodable with the hoisted
        // register in place of the dead one.
        for (const uint32_t k : useSites)
        {
            const MicroInstr*        inst = storage.ptr(instrRefs[k]);
            const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!ops)
                return false;

            MicroInstrOperand probe[8] = {};
            if (inst->numOperands > 8)
                return false;
            for (uint8_t o = 0; o < inst->numOperands; ++o)
            {
                probe[o] = ops[o];
                if (probe[o].reg == dead)
                    probe[o].reg = hoisted;
            }

            if (encoder)
            {
                MicroInstr probeInst;
                probeInst.op          = inst->op;
                probeInst.numOperands = inst->numOperands;

                MicroConformanceIssue issue;
                if (encoder->queryConformanceIssue(issue, probeInst, probe))
                    return false;
            }
        }

        for (const uint32_t k : useSites)
        {
            const MicroInstr*  inst = storage.ptr(instrRefs[k]);
            MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
            if (!ops)
                continue;
            const auto modes = MicroInstr::info(inst->op).resolvedRegModes(ops);
            for (size_t operandIndex = 0; operandIndex < modes.size(); ++operandIndex)
            {
                const MicroInstrRegMode mode = modes[operandIndex];
                if (mode != MicroInstrRegMode::Use && mode != MicroInstrRegMode::UseDef)
                    continue;
                MicroReg& reg = ops[operandIndex].reg;
                if (reg.isValid() && !reg.isNoBase() && reg == dead)
                    reg = hoisted;
            }
        }

        return true;
    }

    // The register allocator hands every non-pinned loop-carried value a stable
    // memory home and writes it back at each control-flow boundary, so an
    // accumulator is loaded and stored on every iteration even when one register
    // could have carried it. This finds that shape and keeps the value in the
    // register the allocator already chose.
    //
    // What has to hold, and all of it is checked on the emitted code:
    //   - the body touches the slot exactly twice, one load then one store, at
    //     the same width and through the same register;
    //   - that register carries nothing else across the iteration: every
    //     definition of it in the body lies between the load and the store, and
    //     it is neither read before the load nor read after the store;
    //   - every way out of the loop lands on one instruction that nothing
    //     outside the loop jumps to, so a single write-back covers them all;
    //   - the register is dead where the seeding load and the write-back land.
    void promoteCarriedSlots(MicroStorage&                storage,
                             MicroOperandStorage&         operands,
                             const MicroControlFlowGraph& cfg,
                             const MicroPhysLiveness&     liveness,
                             const NaturalLoop&           loop,
                             const MicroInstrRef          headerRef,
                             const uint32_t               preheaderIndex,
                             const CallConv&              conv,
                             const FrameReachability&     reach,
                             const bool                   restrictToUnreachable,
                             const MicroPassContext&      context,
                             std::vector<Carried>&        out,
                             std::vector<SunkStore>&      sunkStores)
    {
        const auto     instrRefs = cfg.instructionRefs();
        const uint32_t n         = cfg.instructionCount();
        const auto&    inBody    = loop.inBody;

        // Every way out of the loop must converge on one instruction that only
        // the loop reaches.
        uint32_t exitTarget = std::numeric_limits<uint32_t>::max();
        for (uint32_t i = 0; i < n; ++i)
        {
            if (!inBody[i])
                continue;
            for (const uint32_t succ : cfg.successors(i))
            {
                if (succ < n && inBody[succ])
                    continue;
                if (exitTarget != std::numeric_limits<uint32_t>::max() && exitTarget != succ)
                    return;
                exitTarget = succ;
            }
        }
        if (exitTarget >= n)
            return;
        for (const uint32_t pred : cfg.predecessors(exitTarget))
        {
            if (pred < n && !inBody[pred])
                return;
        }

        // The write-back belongs at the start of the exit block. When the loop leaves through a
        // label, that start is after the label, since every edge into the block passes it. When
        // it leaves by falling through onto an ordinary instruction the block starts at that
        // instruction, and placing the store after it puts the store past whatever that
        // instruction is - past an unconditional jump, nothing ever runs it, and the loop's
        // result is silently left in the register it was promoted into.
        const MicroInstr* exitInst = storage.ptr(instrRefs[exitTarget]);
        if (!exitInst)
            return;

        MicroInstrRef writeBackBefore = instrRefs[exitTarget];
        if (exitInst->op == MicroInstrOpcode::Label)
        {
            writeBackBefore = storage.findNextInstructionRef(writeBackBefore);
            if (!writeBackBefore.isValid())
                return;
        }

        // Index every constant-offset frame access of the body by (base, slot).
        struct SlotUse
        {
            uint32_t    loadIndex  = std::numeric_limits<uint32_t>::max();
            uint32_t    storeIndex = std::numeric_limits<uint32_t>::max();
            uint32_t    accesses   = 0;
            MicroReg    reg;
            MicroReg    base;
            uint64_t    offset = 0;
            MicroOpBits bits   = MicroOpBits::Zero;
        };
        const auto slotKey = [](const MicroReg base, const uint64_t offset) {
            return (static_cast<uint64_t>(base.hash()) << 32) ^ offset;
        };
        thread_local std::unordered_map<uint64_t, SlotUse> slots;
        thread_local std::vector<FrameRef>                 blockedRanges;
        slots.clear();
        blockedRanges.clear();

        for (uint32_t i = 0; i < n; ++i)
        {
            if (!inBody[i])
                continue;
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            if (!inst)
                return;
            const MicroInstrOperand* ops = inst->ops(operands);

            FrameRef ref;
            if (isFrameLoad(ref, *inst, ops, conv, reach.localBaseReg))
            {
                SlotUse& use = slots[slotKey(ref.base, ref.lo)];
                ++use.accesses;
                use.base   = ref.base;
                use.offset = ref.lo;
                if (use.loadIndex != std::numeric_limits<uint32_t>::max())
                    use.accesses = 99; // a second load: not the shape
                use.loadIndex = i;
                use.reg       = ops[0].reg;
                use.bits      = ops[2].opBits;
                continue;
            }

            if (inst->op == MicroInstrOpcode::LoadMemReg && ops &&
                (isFrameBaseRegister(ops[0].reg, conv) || (reach.localBaseReg.isValid() && ops[0].reg == reach.localBaseReg)))
            {
                SlotUse& use = slots[slotKey(ops[0].reg, ops[3].valueU64)];
                ++use.accesses;
                use.base   = ops[0].reg;
                use.offset = ops[3].valueU64;
                if (use.storeIndex != std::numeric_limits<uint32_t>::max())
                    use.accesses = 99;
                use.storeIndex = i;
                continue;
            }

            // Any other frame access at all disqualifies the slot it touches. A write the
            // caller could not place is either refused there or proven unable to reach the
            // frame at all, so nothing else needs accounting for here.
            FrameRef written;
            if (frameWriteRange(written, *inst, ops, conv, reach.localBaseReg))
            {
                slots[slotKey(written.base, written.lo)].accesses = 99;
                continue;
            }

            // Any other addressed touch of the frame - an indexed access, a
            // vector load, a compare against memory - disqualifies whatever it
            // can land on: its whole object through the local base, a
            // conservative window otherwise. Removing a slot's store while
            // something else still reads the home would hand that reader a
            // stale value.
            const MicroInstrDef& accessInfo = MicroInstr::info(inst->op);
            if (ops && accessInfo.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands))
            {
                const MicroReg accessBase = ops[accessInfo.memBaseOperandIndex].reg;
                const bool     tracked    = isFrameBaseRegister(accessBase, conv) ||
                                     (reach.localBaseReg.isValid() && accessBase == reach.localBaseReg);
                if (tracked)
                {
                    const auto accessOffset = static_cast<int64_t>(ops[accessInfo.memOffsetOperandIndex].valueU64);
                    FrameRef   touchedRange;
                    if (!findContainingObject(touchedRange, reach, accessBase, accessOffset))
                    {
                        touchedRange.base = accessBase;
                        touchedRange.lo   = static_cast<uint64_t>(accessOffset);
                        touchedRange.hi   = touchedRange.lo + 16;
                    }
                    blockedRanges.push_back(touchedRange);
                }
            }
        }

        for (auto& [key, use] : slots)
        {
            const uint64_t offset = use.offset;
            if (use.accesses == 1 && use.loadIndex == std::numeric_limits<uint32_t>::max() &&
                use.storeIndex != std::numeric_limits<uint32_t>::max())
            {
                const MicroInstr*        storeInst = storage.ptr(instrRefs[use.storeIndex]);
                const MicroInstrOperand* storeOps  = storeInst ? storeInst->ops(operands) : nullptr;
                if (!storeOps || use.storeIndex == 0)
                    continue;
                if (std::ranges::any_of(sunkStores, [&](const SunkStore& sunk) { return sunk.storeRef == instrRefs[use.storeIndex]; }))
                    continue;

                const MicroReg    source = storeOps[1].reg;
                const MicroOpBits bits   = storeOps[2].opBits;
                if (!source.isInt() || bits != MicroOpBits::B64 || source == use.base)
                    continue;

                const FrameRef slotRef{use.base, offset, offset + getNumBytes(bits)};
                bool           blocked = std::ranges::any_of(blockedRanges, [&](const FrameRef& range) { return overlaps(slotRef, range); });
                if (blocked || !slotIsUnreachable(reach, context, slotRef, conv))
                    continue;

                // A different frame access, including a partially overlapping one, must
                // not observe the old home while its write is delayed.
                for (uint32_t k = 0; k < n && !blocked; ++k)
                {
                    if (!inBody[k] || k == use.storeIndex)
                        continue;
                    const MicroInstr*        other    = storage.ptr(instrRefs[k]);
                    const MicroInstrOperand* otherOps = other ? other->ops(operands) : nullptr;
                    FrameRef                 otherRef;
                    if (other && (isFrameLoad(otherRef, *other, otherOps, conv, reach.localBaseReg) ||
                                  frameWriteRange(otherRef, *other, otherOps, conv, reach.localBaseReg)))
                        blocked = overlaps(slotRef, otherRef);
                }
                if (blocked)
                    continue;

                // The update and the store are adjacent. The source register has no
                // other definition in the body, so an early exit still sees its
                // previous value and an exit after the update sees the new one.
                const MicroInstr*        update    = storage.ptr(instrRefs[use.storeIndex - 1]);
                const MicroInstrOperand* updateOps = update ? update->ops(operands) : nullptr;
                if (!inBody[use.storeIndex - 1] || !update || update->op != MicroInstrOpcode::OpBinaryRegImm ||
                    !updateOps || updateOps[0].reg != source || updateOps[1].opBits != bits ||
                    updateOps[2].microOp != MicroOp::Add)
                    continue;
                bool otherDefinition = false;
                for (uint32_t k = 0; k < n && !otherDefinition; ++k)
                {
                    if (!inBody[k] || k == use.storeIndex - 1)
                        continue;
                    const auto& defs = liveness.useDefs[k].defs;
                    otherDefinition  = std::ranges::find(defs, source) != defs.end();
                }
                if (otherDefinition)
                    continue;

                // The loop may exit before its first update. Its preheader must
                // initialize both the frame home and the source to one value.
                const MicroInstr*        initialStore = storage.ptr(instrRefs[preheaderIndex]);
                const MicroInstrOperand* initialOps   = initialStore ? initialStore->ops(operands) : nullptr;
                if (!initialStore || initialStore->op != MicroInstrOpcode::LoadMemReg || !initialOps ||
                    initialOps[0].reg != use.base || initialOps[3].valueU64 != offset || initialOps[2].opBits != bits)
                    continue;
                if (initialOps[1].reg != source)
                {
                    if (!preheaderIndex)
                        continue;
                    const MicroInstr*        copy    = storage.ptr(instrRefs[preheaderIndex - 1]);
                    const MicroInstrOperand* copyOps = copy ? copy->ops(operands) : nullptr;
                    if (!copy || copy->op != MicroInstrOpcode::LoadRegReg || !copyOps ||
                        copyOps[0].reg != source || copyOps[1].reg != initialOps[1].reg || copyOps[2].opBits != bits)
                        continue;
                }

                sunkStores.push_back({instrRefs[use.storeIndex], writeBackBefore, source, use.base, offset, bits});
                continue;
            }
            if (use.accesses != 2)
                continue;

            FrameRef slotRef;
            slotRef.base = use.base;
            slotRef.lo   = offset;
            slotRef.hi   = offset + getNumBytes(use.bits);

            const bool blocked = std::ranges::any_of(blockedRanges, [&](const FrameRef& range) { return overlaps(slotRef, range); });
            if (blocked)
                continue;

            if (restrictToUnreachable && !slotIsUnreachable(reach, context, slotRef, conv))
                continue;
            if (use.loadIndex == std::numeric_limits<uint32_t>::max() ||
                use.storeIndex == std::numeric_limits<uint32_t>::max())
                continue;
            if (use.loadIndex > use.storeIndex)
                continue;

            const MicroInstr*        loadInst  = storage.ptr(instrRefs[use.loadIndex]);
            const MicroInstr*        storeInst = storage.ptr(instrRefs[use.storeIndex]);
            const MicroInstrOperand* storeOps  = storeInst ? storeInst->ops(operands) : nullptr;
            if (!loadInst || !storeOps)
                continue;
            if (storeOps[1].reg != use.reg || storeOps[2].opBits != use.bits)
                continue;
            if (!use.reg.isInt() && !use.reg.isFloat())
                continue;
            if (isFrameBaseRegister(use.reg, conv) || (reach.localBaseReg.isValid() && use.reg == reach.localBaseReg))
                continue;

            // The register must carry nothing else around the iteration.
            bool usable = true;
            for (uint32_t k = 0; k < n && usable; ++k)
            {
                // All touches from the load through the store belong to this
                // accumulator. The next iteration checks the first index after it.
                if (k == use.loadIndex)
                {
                    k = use.storeIndex;
                    continue;
                }
                if (!inBody[k])
                    continue;
                const MicroInstrUseDef& useDef = liveness.useDefs[k];
                usable                         = std::ranges::find(useDef.defs, use.reg) == useDef.defs.end() &&
                         std::ranges::find(useDef.uses, use.reg) == useDef.uses.end();
            }
            if (!usable)
                continue;

            // Nothing outside may read the register we now leave holding the
            // accumulator, and nothing may be holding a live value where the
            // seeding load lands.
            if (liveness.isLiveOut(exitTarget, use.reg))
                continue;
            if (liveness.isLiveOut(preheaderIndex, use.reg))
                continue;

            // The preheader usually stores the initial value into the slot
            // already, in which case the register still holds it and no seeding
            // load is needed.
            MicroInstrRef     seedBefore = headerRef;
            const MicroInstr* prev       = storage.ptr(instrRefs[preheaderIndex]);
            if (prev && prev->op == MicroInstrOpcode::LoadMemReg)
            {
                const MicroInstrOperand* prevOps = prev->ops(operands);
                if (prevOps && prevOps[0].reg == use.base && prevOps[3].valueU64 == offset &&
                    prevOps[1].reg == use.reg && prevOps[2].opBits == use.bits)
                    seedBefore = MicroInstrRef::invalid();
            }

            out.push_back({.loadRef         = instrRefs[use.loadIndex],
                           .storeRef        = instrRefs[use.storeIndex],
                           .seedBeforeRef   = seedBefore,
                           .writeBackBefore = writeBackBefore,
                           .reg             = use.reg,
                           .base            = use.base,
                           .offset          = offset,
                           .bits            = use.bits});
        }
    }

    // Integer spill homes can use an otherwise unused caller-saved SIMD register
    // even when the GP register changes roles between accesses. Keeping every
    // read and write coherent also handles branch arms and distinct loop exits.
    bool cachePrivateSpills(MicroPassContext& context, const MicroControlFlowGraph& cfg, const MicroPhysLiveness& liveness, const NaturalLoop& loop)
    {
        if (context.spillAreaLo >= context.spillAreaHi)
            return false;
        const CallConv& conv     = CallConv::get(context.callConvKind);
        auto&           storage  = *context.instructions;
        auto&           operands = *context.operands;
        const auto      refs     = cfg.instructionRefs();

        SmallVector<uint32_t, 4>      entries;
        SmallVector<MicroInstrRef, 4> seeds;
        for (const uint32_t predecessor : cfg.predecessors(loop.header))
        {
            if (predecessor >= refs.size())
                return false;
            if (loop.inBody[predecessor])
                continue;
            const MicroInstr* inst = storage.ptr(refs[predecessor]);
            if (!inst)
                return false;
            if (inst->op == MicroInstrOpcode::JumpCond)
                seeds.push_back(refs[predecessor]);
            else if (predecessor + 1 == loop.header)
                seeds.push_back(refs[loop.header]);
            else
                return false;
            entries.push_back(predecessor);
        }
        if (entries.empty())
            return false;

        SmallVector<uint32_t, 4> calls;
        uint64_t                 unavailable = 0;
        for (uint32_t index = 0; index < refs.size(); ++index)
        {
            if (!loop.inBody[index])
                continue;
            const auto& useDef = liveness.useDefs[index];
            for (const MicroReg reg : useDef.uses)
                if (reg.isFloat())
                    unavailable |= 1ull << MicroPhysLiveness::bitOf(reg);
            for (const MicroReg reg : useDef.defs)
                if (reg.isFloat() && (!useDef.isCall || liveness.isLiveOut(index, reg)))
                    unavailable |= 1ull << MicroPhysLiveness::bitOf(reg);
            if (useDef.isCall)
                calls.push_back(index);
        }
        SmallVector<MicroReg, 6> available;
        for (const MicroReg reg : conv.floatTransientRegs)
            if (!(unavailable & (1ull << MicroPhysLiveness::bitOf(reg))) &&
                std::ranges::none_of(entries, [&](const uint32_t entry) { return liveness.isLiveOut(entry, reg); }))
                available.push_back(reg);
        if (available.empty())
            return false;

        // Only a loop with a call-free route back to its header can avoid a
        // reload on some trips. Calls on every trip would merely move the load.
        if (!calls.empty())
        {
            std::vector<uint8_t>  visited(refs.size(), 0);
            SmallVector<uint32_t> pending;
            pending.push_back(loop.header);
            bool callFreeTrip = false;
            while (!pending.empty() && !callFreeTrip)
            {
                const uint32_t index = pending.back();
                pending.pop_back();
                if (visited[index] || liveness.useDefs[index].isCall)
                    continue;
                visited[index] = 1;
                for (const uint32_t successor : cfg.successors(index))
                {
                    if (successor == loop.header)
                        callFreeTrip = true;
                    else if (successor < refs.size() && loop.inBody[successor] && !visited[successor])
                        pending.push_back(successor);
                }
            }
            if (!callFreeTrip)
                return false;
        }

        struct Slot
        {
            FrameRef                      range;
            SmallVector<MicroInstrRef, 4> accesses;
            uint32_t                      writes   = 0;
            bool                          eligible = true;
        };
        SmallVector<Slot, 16>    slots;
        SmallVector<uint32_t, 4> exits;
        for (uint32_t index = 0; index < refs.size(); ++index)
        {
            if (!loop.inBody[index])
                continue;
            const auto& useDef = liveness.useDefs[index];
            if (std::ranges::find(useDef.defs, conv.stackPointer) != useDef.defs.end())
                return false;
            const MicroInstr* inst = storage.ptr(refs[index]);
            const auto*       ops  = inst ? inst->ops(operands) : nullptr;
            if (!inst)
                return false;
            for (const uint32_t successor : cfg.successors(index))
            {
                if (successor >= refs.size())
                    return false;
                if (!loop.inBody[successor] && std::ranges::find(exits, successor) == exits.end())
                    exits.push_back(successor);
            }

            // A derived stack address or indexed stack access needs a wider
            // alias proof. Other fixed accesses only block overlapping slots.
            if (std::ranges::find(useDef.uses, conv.stackPointer) == useDef.uses.end())
                continue;
            const bool                  load  = inst->op == MicroInstrOpcode::LoadRegMem;
            const bool                  store = inst->op == MicroInstrOpcode::LoadMemReg;
            const auto&                 info  = MicroInstr::info(inst->op);
            MicroPassHelpers::AmcLayout layout;
            if (!ops || !info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) ||
                ops[info.memBaseOperandIndex].reg != conv.stackPointer ||
                inst->op == MicroInstrOpcode::LoadAddrRegMem || MicroPassHelpers::amcLayoutFor(layout, inst->op))
                return false;
            const uint64_t offset = ops[info.memOffsetOperandIndex].valueU64;
            uint64_t       width  = info.flags.has(MicroInstrFlagsE::Fixed128BitOperands) ? 16 : 0;
            for (uint32_t operand = 0; operand < inst->numOperands; ++operand)
                if (info.opBitsMask & (1u << operand))
                    width = std::max<uint64_t>(width, getNumBytes(ops[operand].opBits));
            if (!width)
                return false;
            if (offset + width < offset)
                return false;
            auto found = std::ranges::find_if(slots, [&](const Slot& slot) { return slot.range.lo == offset; });
            if (found == slots.end())
            {
                slots.push_back({.range = {conv.stackPointer, offset, offset + width}});
                found = slots.end() - 1;
            }
            found->eligible &= (load || store) && width == 8 && found->range.hi == offset + width && ops[load ? 0 : 1].reg.isInt();
            found->range.hi = std::max(found->range.hi, offset + width);
            found->accesses.push_back(refs[index]);
            found->writes += store;
        }
        if (exits.empty())
            return false;
        SmallVector<MicroInstrRef, 4> writeBacks;
        bool                          exclusiveExits = true;
        for (const uint32_t exit : exits)
        {
            for (const uint32_t predecessor : cfg.predecessors(exit))
                if (predecessor >= refs.size() || !loop.inBody[predecessor])
                    exclusiveExits = false;
            MicroInstrRef     before = refs[exit];
            const MicroInstr* inst   = storage.ptr(before);
            if (!inst)
                return false;
            if (inst->op == MicroInstrOpcode::Label)
                before = storage.findNextInstructionRef(before);
            if (!before.isValid())
                return false;
            writeBacks.push_back(before);
        }

        // Prefer the slots with the most traffic. Retain collection order for
        // ties so register assignment does not depend on a hash table's order.
        std::stable_sort(slots.begin(), slots.end(), [](const Slot& a, const Slot& b) { return a.accesses.size() > b.accesses.size(); });
        uint32_t selected = 0;
        for (const Slot& slot : slots)
        {
            if (selected == available.size())
                break;
            // A write-only home is observable after the loop, so it benefits
            // too: the last bank transfer replaces repeated spill stores.
            if (!slot.eligible ||
                slot.range.lo < context.spillAreaLo || slot.range.hi > context.spillAreaHi || slot.range.hi < slot.range.lo)
                continue;
            bool overlap = false;
            for (const Slot& other : slots)
                if (&slot != &other && overlaps(slot.range, other.range))
                    overlap = true;
            if (overlap)
                continue;

            // Keep writes coherent when calls or shared exits prevent deferred
            // write-back. Existing stores also cover paths that skip the loop.
            const bool writeThrough   = slot.writes && (!calls.empty() || !exclusiveExits);
            const bool needsWriteBack = slot.writes && !writeThrough;

            const MicroReg cached       = available[selected];
            const auto     needsRestore = [&](const uint32_t call) {
                return call + 1 < refs.size() && loop.inBody[call + 1] &&
                       std::ranges::find(liveness.useDefs[call].defs, cached) != liveness.useDefs[call].defs.end();
            };
            // A called loop must reuse the home enough to repay its explicit
            // entry/restore reads. Otherwise the cold arms grow memory traffic.
            const auto restores     = std::ranges::count_if(calls, needsRestore);
            const auto readsRemoved = slot.accesses.size() - (writeThrough ? slot.writes : 0);
            if ((writeThrough && !readsRemoved) || (!calls.empty() && readsRemoved <= seeds.size() + restores))
                continue;
            ++selected;
            MicroInstrOperand seed[4] = {};
            seed[0].reg               = cached;
            seed[1].reg               = conv.stackPointer;
            seed[2].opBits            = MicroOpBits::B64;
            seed[3].valueU64          = slot.range.lo;
            for (const MicroInstrRef before : seeds)
                storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadRegMem, seed);
            // Private spill homes cannot be changed by a callee. Restore
            // only clobbered caches, on the call's fallthrough edge inside the loop.
            for (const uint32_t call : calls)
            {
                if (needsRestore(call))
                    storage.insertDerivedBefore(operands, refs[call + 1], MicroInstrOpcode::LoadRegMem, seed);
            }
            MicroInstrOperand write[4] = {};
            write[0].reg               = conv.stackPointer;
            write[1].reg               = cached;
            write[2].opBits            = MicroOpBits::B64;
            write[3].valueU64          = slot.range.lo;
            if (needsWriteBack)
                for (const MicroInstrRef before : writeBacks)
                    storage.insertDerivedBefore(operands, before, MicroInstrOpcode::LoadMemReg, write);
            for (const MicroInstrRef ref : slot.accesses)
            {
                MicroInstr* inst = storage.ptr(ref);
                auto*       ops  = inst->ops(operands);
                if (writeThrough && inst->op == MicroInstrOpcode::LoadMemReg)
                {
                    MicroInstrOperand copy[3] = {};
                    copy[0].reg               = cached;
                    copy[1].reg               = ops[1].reg;
                    copy[2].opBits            = MicroOpBits::B64;
                    storage.insertDerivedBefore(operands, ref, MicroInstrOpcode::LoadRegReg, copy);
                    continue;
                }
                if (inst->op == MicroInstrOpcode::LoadRegMem)
                    ops[1].reg = cached;
                else
                    ops[0].reg = cached;
                inst->op          = MicroInstrOpcode::LoadRegReg;
                inst->numOperands = 3;
            }
        }
        if (!selected)
            return false;
        context.builder->invalidateControlFlowGraph();
        return true;
    }

    bool hoistRound(MicroPassContext& context, const CallConv& conv, FrameReachability& framePrivacy)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        if (!cfg.hasLoop() || cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;

        const uint32_t n = cfg.instructionCount();
        if (!n)
            return false;

        const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
        if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
            return false;

        const auto instrRefs = cfg.instructionRefs();

        // Only base-register detection is needed to find a frame reload.
        // Classify escaped objects after one has been found.
        if (!framePrivacy.computed)
            framePrivacy.localBaseReg = findLocalBaseRegister(storage, operands, conv, context.encoder);

        bool anyFrameLoad = false;
        for (uint32_t i = 0; i < n && !anyFrameLoad; ++i)
        {
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            FrameRef          slot;
            if (inst && isFrameLoad(slot, *inst, inst->ops(operands), conv, framePrivacy.localBaseReg))
                anyFrameLoad = true;
        }
        if (!anyFrameLoad)
            return false;

        const auto dom           = MicroPassHelpers::computeInstructionDominators(cfg, entry);
        auto       loopsByHeader = MicroPassHelpers::findNaturalLoops(cfg, dom);
        if (loopsByHeader.empty())
            return false;

        // Physical liveness is only useful for a loop with a clean
        // fall-through preheader. The instruction stream stays unchanged
        // until all candidate loops have been analyzed.
        SmallVector<const NaturalLoop*, 4> loops;
        loops.reserve(loopsByHeader.size());
        for (const auto& loop : loopsByHeader | std::views::values)
        {
            const uint32_t      header            = loop.header;
            const auto&         inBody            = loop.inBody;
            const MicroInstrRef headerRef         = instrRefs[header];
            uint32_t            externalPredCount = 0;
            for (const uint32_t p : cfg.predecessors(header))
            {
                if (p < n && !inBody[p])
                    ++externalPredCount;
            }
            if (externalPredCount != 1)
                continue;

            const MicroInstrRef prevRef = storage.findPreviousInstructionRef(headerRef);
            if (!prevRef.isValid() || !header || instrRefs[header - 1] != prevRef || inBody[header - 1])
                continue;
            const MicroInstr* prevInst = storage.ptr(prevRef);
            if (!prevInst)
                continue;
            const MicroInstrFlags prevFlags = MicroInstr::info(prevInst->op).flags;
            if (prevFlags.has(MicroInstrFlagsE::TerminatorInstruction) &&
                !prevFlags.has(MicroInstrFlagsE::ConditionalJump))
                continue;
            if (prevFlags.has(MicroInstrFlagsE::JumpInstruction) &&
                !prevFlags.has(MicroInstrFlagsE::ConditionalJump))
                continue;
            // A conditional jump directly to the following header can skip
            // instructions inserted before that label on its taken edge.
            if (prevFlags.has(MicroInstrFlagsE::JumpInstruction) && cfg.successors(header - 1).size() == 1)
                continue;
            loops.push_back(&loop);
        }
        if (loops.empty() && context.spillAreaLo >= context.spillAreaHi)
            return false;
        if (!framePrivacy.computed)
            analyzeFrameReachability(framePrivacy, context, storage, operands, conv);
        const FrameReachability& reach        = framePrivacy;
        const bool               framePrivate = reach.wholeFramePrivate;

        // Hoist rounds run sequentially on a worker. The analysis overwrites
        // the live entries each round, so retain its storage between rounds.
        thread_local MicroPhysLiveness liveness;
        MicroPassHelpers::computePhysicalLiveness(liveness, context);
        if (!liveness.valid)
            return false;

        // Innermost first, so a load leaves the loop it costs most in before the
        // enclosing one is considered.
        std::ranges::sort(loops, [](const NaturalLoop* a, const NaturalLoop* b) { return a->bodySize < b->bodySize; });

        struct Rewrite
        {
            MicroInstrRef ref;
            MicroReg      source;
        };

        struct CachedReload
        {
            MicroInstrRef beforeRef;
            MicroReg      reg;
            MicroReg      base;
            MicroOpBits   bits;
            uint64_t      offset;
        };
        uint64_t unavailableCacheRegs = 0;
        bool     cacheRegsComputed    = false;

        thread_local std::vector<CachedReload>    cachedReloads;
        thread_local std::vector<Hoist>           hoists;
        thread_local std::vector<MicroInstrRef>   erasures;
        thread_local std::vector<Rewrite>         rewrites;
        thread_local std::vector<Carried>         carried;
        thread_local std::vector<SunkStore>       sunkStores;
        thread_local std::unordered_set<uint32_t> claimed;
        cachedReloads.clear();
        hoists.clear();
        erasures.clear();
        rewrites.clear();
        carried.clear();
        sunkStores.clear();
        claimed.clear();
        std::vector<FrameRef> writes;

        for (const NaturalLoop* loop : loops)
        {
            const uint32_t      header    = loop->header;
            const auto&         inBody    = loop->inBody;
            const MicroInstrRef headerRef = instrRefs[header];

            const uint32_t preheaderIndex = header - 1;

            // Classify the body once: every frame slot it writes, and whether it
            // does anything the slot analysis cannot account for. Count definitions by
            // instruction in two masks, so reload candidates need no body scan.
            bool     bodyOpaque          = false;
            bool     hasUnplaceableWrite = false;
            uint64_t definedRegs         = 0;
            uint64_t multiplyDefinedRegs = 0;
            writes.clear();
            for (uint32_t i = 0; i < n && !bodyOpaque; ++i)
            {
                if (!inBody[i])
                    continue;
                const MicroInstr* inst = storage.ptr(instrRefs[i]);
                if (!inst)
                {
                    bodyOpaque = true;
                    break;
                }
                const MicroInstrDef& info = MicroInstr::info(inst->op);
                if (info.flags.has(MicroInstrFlagsE::IsCallInstruction) || liveness.useDefs[i].isCall)
                {
                    bodyOpaque = true;
                    break;
                }
                if (inst->op == MicroInstrOpcode::Push || inst->op == MicroInstrOpcode::Pop)
                {
                    bodyOpaque = true;
                    break;
                }
                // The frame base must mean the same thing on every iteration.
                uint64_t instructionDefs = 0;
                for (const MicroReg def : liveness.useDefs[i].defs)
                {
                    const uint32_t bit = MicroPhysLiveness::bitOf(def);
                    if (bit < MicroPhysLiveness::K_INVALID_BIT)
                        instructionDefs |= 1ull << bit;
                    if (isFrameBaseRegister(def, conv) || (reach.localBaseReg.isValid() && def == reach.localBaseReg))
                        bodyOpaque = true;
                }
                multiplyDefinedRegs |= definedRegs & instructionDefs;
                definedRegs |= instructionDefs;
                if (bodyOpaque)
                    break;
                if (!info.flags.has(MicroInstrFlagsE::WritesMemory))
                    continue;

                // An indexed write through the local base lands somewhere in
                // the object its displacement names; widen it to that whole
                // object rather than treating it as reaching anywhere.
                if (inst->op == MicroInstrOpcode::LoadAmcMemReg || inst->op == MicroInstrOpcode::LoadAmcMemImm)
                {
                    const MicroInstrOperand* writeOps = inst->ops(operands);
                    FrameRef                 objectRange;
                    if (writeOps && reach.localBaseReg.isValid() && writeOps[0].reg == reach.localBaseReg &&
                        findContainingObject(objectRange, reach, writeOps[0].reg, static_cast<int64_t>(writeOps[6].valueU64)))
                    {
                        writes.push_back(objectRange);
                        continue;
                    }
                }

                FrameRef written;
                if (!frameWriteRange(written, *inst, inst->ops(operands), conv, reach.localBaseReg))
                {
                    // A write this pass cannot place. It reaches nothing in the frame when no
                    // pointer into the frame exists, and only what escaped otherwise: not the
                    // allocator's own spill area - that area holds no source object, so no
                    // pointer can be made to land in it - and not a source object whose
                    // address the function never handed out.
                    hasUnplaceableWrite = true;
                    continue;
                }
                writes.push_back(written);
            }
            if (bodyOpaque)
                continue;

            const bool restrictToUnreachable = hasUnplaceableWrite && !framePrivate;

            for (uint32_t i = 0; i < n; ++i)
            {
                if (!inBody[i])
                    continue;
                if (claimed.contains(i))
                    continue;

                const MicroInstr* inst = storage.ptr(instrRefs[i]);
                if (!inst)
                    continue;
                const MicroInstrOperand* ops = inst->ops(operands);
                FrameRef                 slot;
                if (!isFrameLoad(slot, *inst, ops, conv, reach.localBaseReg))
                    continue;

                const MicroReg dst = ops[0].reg;
                if (!dst.isInt() && !dst.isFloat())
                    continue;
                if (isFrameBaseRegister(dst, conv) || (reach.localBaseReg.isValid() && dst == reach.localBaseReg))
                    continue;
                if (restrictToUnreachable && !slotIsUnreachable(reach, context, slot, conv))
                    continue;

                bool aliased = false;
                for (const FrameRef& written : writes)
                {
                    if (overlaps(slot, written))
                    {
                        aliased = true;
                        break;
                    }
                }
                if (aliased)
                    continue;

                // Reuse the assigned destination only when it survives the whole
                // loop and is free at the preheader. Otherwise use a separate cache.
                const uint32_t dstBit = MicroPhysLiveness::bitOf(dst);
                SWC_ASSERT(dstBit < MicroPhysLiveness::K_INVALID_BIT);
                MicroReg   cachedReg  = dst;
                const bool needsCache = liveness.isLiveOut(preheaderIndex, dst) || (multiplyDefinedRegs & (1ull << dstBit));
                if (needsCache)
                {
                    // Integer pressure need not repeat an invariant frame read when
                    // the function leaves a caller-saved SIMD register unused. A
                    // scalar bank transfer replaces the reload; no ABI save is added.
                    // Existing float operands reserve their registers globally so
                    // separately planned hoists cannot overlap a newly chosen cache.
                    if (!dst.isInt() || (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64))
                        continue;
                    if (!cacheRegsComputed)
                    {
                        for (const auto& useDef : liveness.useDefs)
                        {
                            if (useDef.isCall)
                                continue;
                            for (const MicroReg reg : useDef.uses)
                            {
                                if (reg.isFloat())
                                    unavailableCacheRegs |= 1ull << MicroPhysLiveness::bitOf(reg);
                            }
                            for (const MicroReg reg : useDef.defs)
                            {
                                if (reg.isFloat())
                                    unavailableCacheRegs |= 1ull << MicroPhysLiveness::bitOf(reg);
                            }
                        }
                        cacheRegsComputed = true;
                    }
                    cachedReg = MicroReg::invalid();
                    for (const MicroReg reg : conv.floatTransientRegs)
                    {
                        const uint64_t bit = 1ull << MicroPhysLiveness::bitOf(reg);
                        if ((unavailableCacheRegs & bit) || liveness.isLiveOut(preheaderIndex, reg))
                            continue;
                        cachedReg = reg;
                        unavailableCacheRegs |= bit;
                        break;
                    }
                    if (!cachedReg.isValid())
                        continue;
                    cachedReloads.push_back({headerRef, cachedReg, ops[1].reg, ops[2].opBits, ops[3].valueU64});
                    rewrites.push_back({instrRefs[i], cachedReg});
                }

                // The hoisted register now holds this slot for the whole body:
                // nothing in the body writes the slot, and nothing writes the
                // register. So every other load of the same slot in the body is
                // reading a value already in a register — redundant when it
                // targets that same register, and a register copy rather than a
                // memory access when it targets another one.
                if (!needsCache)
                    hoists.push_back({instrRefs[i], headerRef});
                claimed.insert(i);
                for (uint32_t k = 0; k < n; ++k)
                {
                    if (!inBody[k] || k == i || claimed.contains(k))
                        continue;
                    const MicroInstr* other = storage.ptr(instrRefs[k]);
                    if (!other)
                        continue;
                    const MicroInstrOperand* otherOps = other->ops(operands);
                    FrameRef                 otherSlot;
                    if (!isFrameLoad(otherSlot, *other, otherOps, conv, reach.localBaseReg))
                        continue;
                    if (otherSlot.base != slot.base || otherSlot.lo != slot.lo || otherSlot.hi != slot.hi)
                        continue;
                    if (otherOps[0].reg == cachedReg)
                    {
                        erasures.push_back(instrRefs[k]);
                    }
                    else
                    {
                        // A copy only replaces the load when both ends live in
                        // the same register class; across classes the move is a
                        // different instruction entirely.
                        if (otherOps[0].reg.isAnyFloat() != dst.isAnyFloat())
                            continue;
                        // Better than a copy: point the readers at the hoisted
                        // register and let the load go. Only worth attempting
                        // when the register is reused right after for something
                        // else, which is the shape that makes the copy pure
                        // overhead — and freeing it is what lets a later pass
                        // keep a loop-carried value there.
                        if (needsCache || !redirectUsesToHoistedRegister(storage, operands, cfg, liveness, inBody, k, cachedReg, context.encoder))
                            rewrites.push_back({instrRefs[k], cachedReg});
                        else
                            erasures.push_back(instrRefs[k]);
                    }
                    claimed.insert(k);
                }
            }

            // Second phase for this loop: a slot the body both reads and writes
            // once, through one register that carries nothing else across the
            // iteration. The allocator gives every non-pinned loop-carried value
            // a memory home and writes it back at each boundary, so an
            // accumulator round-trips through the frame on every iteration; this
            // keeps it in its register for the whole loop and writes it back once
            // on the way out.
            promoteCarriedSlots(storage, operands, cfg, liveness, *loop, headerRef, preheaderIndex, conv, reach, restrictToUnreachable, context, carried, sunkStores);
        }

        if (hoists.empty() && carried.empty() && sunkStores.empty() && cachedReloads.empty())
        {
            // Use the remaining register bank only after ordinary promotion has
            // exhausted its opportunities. Mutate one loop, then refresh liveness.
            SmallVector<const NaturalLoop*, 4> cacheLoops;
            for (const auto& loop : loopsByHeader | std::views::values)
                cacheLoops.push_back(&loop);
            std::stable_sort(cacheLoops.begin(), cacheLoops.end(), [](const NaturalLoop* a, const NaturalLoop* b) {
                return a->bodySize != b->bodySize ? a->bodySize < b->bodySize : a->header < b->header;
            });
            for (const NaturalLoop* loop : cacheLoops)
                if (cachePrivateSpills(context, cfg, liveness, *loop))
                    return true;
            return false;
        }

        for (const CachedReload& reload : cachedReloads)
        {
            MicroInstrOperand ops[4] = {};
            ops[0].reg               = reload.reg;
            ops[1].reg               = reload.base;
            ops[2].opBits            = reload.bits;
            ops[3].valueU64          = reload.offset;
            storage.insertDerivedBefore(operands, reload.beforeRef, MicroInstrOpcode::LoadRegMem, ops);
        }

        for (const MicroInstrRef ref : erasures)
            storage.erase(ref);

        for (const Rewrite& rewrite : rewrites)
        {
            MicroInstr* inst = storage.ptr(rewrite.ref);
            if (!inst)
                continue;
            MicroInstrOperand* ops = inst->ops(operands);
            if (!ops)
                continue;

            // `mov D, [slot]` becomes `mov D, R`, the register the slot was
            // hoisted into. LoadRegMem is (dst, base, bits, offset) and
            // LoadRegReg is (dst, src, bits), so the base becomes the source
            // and the offset is dropped.
            ops[1].reg        = rewrite.source;
            inst->op          = MicroInstrOpcode::LoadRegReg;
            inst->numOperands = 3;
        }

        for (const Carried& promo : carried)
        {
            // Seed the register before the loop when the preheader has not
            // already left the value in it.
            if (promo.seedBeforeRef.isValid())
            {
                MicroInstrOperand seedOps[4] = {};
                seedOps[0].reg               = promo.reg;
                seedOps[1].reg               = promo.base;
                seedOps[2].opBits            = promo.bits;
                seedOps[3].valueU64          = promo.offset;
                storage.insertDerivedBefore(operands, promo.seedBeforeRef, MicroInstrOpcode::LoadRegMem, std::span(seedOps, 4));
            }

            // Write it back once, at the start of the block every exit reaches.

            MicroInstrOperand backOps[4] = {};
            backOps[0].reg               = promo.base;
            backOps[1].reg               = promo.reg;
            backOps[2].opBits            = promo.bits;
            backOps[3].valueU64          = promo.offset;
            storage.insertDerivedBefore(operands, promo.writeBackBefore, MicroInstrOpcode::LoadMemReg, std::span(backOps, 4));

            storage.erase(promo.loadRef);
            storage.erase(promo.storeRef);
        }

        for (const SunkStore& store : sunkStores)
        {
            MicroInstrOperand ops[4] = {};
            ops[0].reg               = store.base;
            ops[1].reg               = store.source;
            ops[2].opBits            = store.bits;
            ops[3].valueU64          = store.offset;
            storage.insertDerivedBefore(operands, store.writeBackBefore, MicroInstrOpcode::LoadMemReg, std::span(ops, 4));
            storage.erase(store.storeRef);
        }

        for (const Hoist& hoist : hoists)
        {
            const MicroInstr* inst = storage.ptr(hoist.ref);
            if (!inst)
                continue;
            const MicroInstrOperand* ops = inst->ops(operands);
            if (!ops)
                continue;

            MicroInstrOperand copied[4] = {};
            const uint8_t     numOps    = inst->numOperands;
            SWC_ASSERT(numOps <= 4);
            for (uint8_t k = 0; k < numOps; ++k)
                copied[k] = ops[k];

            storage.insertDerivedBefore(operands, hoist.beforeRef, MicroInstrOpcode::LoadRegMem, std::span(copied, numOps));
            storage.erase(hoist.ref);
        }

        context.builder->invalidateControlFlowGraph();
        return true;
    }

    // A folded memory operand can keep an invariant scalar in memory even
    // when a saved persistent register is idle throughout the loop. Reuse
    // that register at an identical entry read, replacing rather than adding
    // the entry memory access. The loop may call a read-only function, but no
    // instruction in it may write memory or redefine the address base.
    bool hoistFoldedBitwiseOperand(MicroPassContext& context, const CallConv& conv)
    {
        MicroStorage&        storage                 = *context.instructions;
        MicroOperandStorage& operands                = *context.operands;
        bool                 hasFoldedBitwiseOperand = false;
        for (const MicroInstr& inst : storage.view())
        {
            if (inst.op != MicroInstrOpcode::OpBinaryRegMem)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (ops && (ops[3].microOp == MicroOp::And || ops[3].microOp == MicroOp::Or || ops[3].microOp == MicroOp::Xor) &&
                (ops[2].opBits == MicroOpBits::B32 || ops[2].opBits == MicroOpBits::B64) && ops[1].reg.isInt())
            {
                hasFoldedBitwiseOperand = true;
                break;
            }
        }
        if (!hasFoldedBitwiseOperand)
            return false;

        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        if (!cfg.hasLoop() || cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;
        const uint32_t n     = cfg.instructionCount();
        const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
        if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
            return false;
        const auto dom           = MicroPassHelpers::computeInstructionDominators(cfg, entry);
        const auto loopsByHeader = MicroPassHelpers::findNaturalLoops(cfg, dom);
        if (loopsByHeader.empty())
            return false;

        MicroPhysLiveness liveness;
        MicroPassHelpers::computePhysicalLiveness(liveness, context);
        if (!liveness.valid)
            return false;
        const auto refs = cfg.instructionRefs();

        SmallVector<MicroReg, 8> savedRegs;
        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstr* inst = storage.ptr(refs[i]);
            if (!inst)
                return false;
            const MicroInstrFlags flags = MicroInstr::info(inst->op).flags;
            if (inst->op == MicroInstrOpcode::Label || flags.has(MicroInstrFlagsE::JumpInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                break;
            if (inst->op == MicroInstrOpcode::Push)
            {
                const MicroInstrOperand* ops = inst->ops(operands);
                if (ops && conv.isIntPersistentReg(ops[0].reg))
                    savedRegs.push_back(ops[0].reg);
            }
        }
        if (savedRegs.empty())
            return false;

        const auto                   readOnlyCallRefs = MicroPassHelpers::collectReadOnlyCallRefs(*context.builder);
        std::unordered_set<uint32_t> relocatedRefs;
        for (const MicroRelocation& relocation : context.builder->codeRelocations())
        {
            if (relocation.instructionRef.isValid())
                relocatedRefs.insert(relocation.instructionRef.get());
        }

        for (const auto& loop : loopsByHeader | std::views::values)
        {
            const uint32_t header = loop.header;
            if (!header || loop.inBody[header - 1])
                continue;
            uint32_t externalPredCount    = 0;
            bool     hasOtherExternalPred = false;
            for (const uint32_t pred : cfg.predecessors(header))
            {
                if (pred < n && !loop.inBody[pred])
                {
                    ++externalPredCount;
                    if (pred != header - 1)
                        hasOtherExternalPred = true;
                }
            }
            if (externalPredCount != 1 || hasOtherExternalPred)
                continue;

            for (uint32_t i = header; i < n; ++i)
            {
                if (!loop.inBody[i])
                    continue;
                const MicroInstr*        inst = storage.ptr(refs[i]);
                const MicroInstrOperand* ops  = inst ? inst->ops(operands) : nullptr;
                if (!ops || inst->op != MicroInstrOpcode::OpBinaryRegMem ||
                    relocatedRefs.contains(refs[i].get()) ||
                    (ops[3].microOp != MicroOp::And && ops[3].microOp != MicroOp::Or && ops[3].microOp != MicroOp::Xor) ||
                    (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
                    !ops[1].reg.isInt())
                    continue;

                const MicroReg base           = ops[1].reg;
                const uint64_t offset         = ops[4].valueU64;
                uint32_t       entryReadIndex = n;
                for (uint32_t j = header; j > 0 && header - j < 16;)
                {
                    --j;
                    const MicroInstr* prior = storage.ptr(refs[j]);
                    if (!prior)
                        break;
                    const MicroInstrFlags flags = MicroInstr::info(prior->op).flags;
                    if (prior->op == MicroInstrOpcode::Label || flags.has(MicroInstrFlagsE::JumpInstruction) ||
                        flags.has(MicroInstrFlagsE::TerminatorInstruction) || flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                        flags.has(MicroInstrFlagsE::WritesMemory))
                        break;
                    if (std::ranges::find(liveness.useDefs[j].defs, base) != liveness.useDefs[j].defs.end())
                        break;
                    const MicroInstrOperand* priorOps = prior->ops(operands);
                    if (prior->op == MicroInstrOpcode::OpBinaryRegMem && priorOps && !relocatedRefs.contains(refs[j].get()) && priorOps[1].reg == base &&
                        priorOps[2].opBits == ops[2].opBits && priorOps[4].valueU64 == offset &&
                        (priorOps[3].microOp == MicroOp::And || priorOps[3].microOp == MicroOp::Or || priorOps[3].microOp == MicroOp::Xor))
                    {
                        entryReadIndex = j;
                        break;
                    }
                }
                if (!entryReadIndex || entryReadIndex == n)
                    continue;

                bool stable = true;
                for (uint32_t j = 0; j < n && stable; ++j)
                {
                    if (!loop.inBody[j])
                        continue;
                    const MicroInstr* bodyInst = storage.ptr(refs[j]);
                    if (!bodyInst)
                    {
                        stable = false;
                        break;
                    }
                    const MicroInstrFlags flags = MicroInstr::info(bodyInst->op).flags;
                    if (flags.has(MicroInstrFlagsE::IsCallInstruction))
                    {
                        if ((bodyInst->op != MicroInstrOpcode::CallLocal && bodyInst->op != MicroInstrOpcode::CallExtern) ||
                            !readOnlyCallRefs.contains(refs[j].get()))
                            stable = false;
                    }
                    else if (flags.has(MicroInstrFlagsE::WritesMemory) || bodyInst->op == MicroInstrOpcode::Push || bodyInst->op == MicroInstrOpcode::Pop)
                        stable = false;
                    if (std::ranges::find(liveness.useDefs[j].defs, base) != liveness.useDefs[j].defs.end())
                        stable = false;
                }
                if (!stable)
                    continue;

                for (auto it = savedRegs.rbegin(); it != savedRegs.rend(); ++it)
                {
                    const MicroReg scratch = *it;
                    if (scratch == base || scratch == ops[0].reg || liveness.isLiveOut(entryReadIndex - 1, scratch))
                        continue;
                    bool unused = true;
                    for (uint32_t j = entryReadIndex; j < header && unused; ++j)
                    {
                        const auto& useDef = liveness.useDefs[j];
                        unused             = std::ranges::find(useDef.uses, scratch) == useDef.uses.end() &&
                                 std::ranges::find(useDef.defs, scratch) == useDef.defs.end();
                    }
                    for (uint32_t j = 0; j < n && unused; ++j)
                    {
                        if (!loop.inBody[j])
                            continue;
                        const auto& useDef = liveness.useDefs[j];
                        unused             = std::ranges::find(useDef.uses, scratch) == useDef.uses.end() &&
                                 std::ranges::find(useDef.defs, scratch) == useDef.defs.end();
                    }
                    if (!unused)
                        continue;

                    SmallVector<MicroInstrRef, 4> foldedRefs;
                    bool                          hasRelocatedUse = false;
                    for (uint32_t j = 0; j < n; ++j)
                    {
                        if (!loop.inBody[j])
                            continue;
                        const MicroInstr*        other    = storage.ptr(refs[j]);
                        const MicroInstrOperand* otherOps = other ? other->ops(operands) : nullptr;
                        if (otherOps && other->op == MicroInstrOpcode::OpBinaryRegMem && otherOps[1].reg == base &&
                            otherOps[2].opBits == ops[2].opBits && otherOps[4].valueU64 == offset &&
                            (otherOps[3].microOp == MicroOp::And || otherOps[3].microOp == MicroOp::Or || otherOps[3].microOp == MicroOp::Xor))
                        {
                            if (relocatedRefs.contains(refs[j].get()))
                            {
                                hasRelocatedUse = true;
                                break;
                            }
                            foldedRefs.push_back(refs[j]);
                        }
                    }
                    if (hasRelocatedUse)
                        continue;

                    MicroInstrOperand loadOps[4] = {};
                    loadOps[0].reg               = scratch;
                    loadOps[1].reg               = base;
                    loadOps[2].opBits            = ops[2].opBits;
                    loadOps[3].valueU64          = offset;
                    storage.insertDerivedBefore(operands, refs[entryReadIndex], MicroInstrOpcode::LoadRegMem, loadOps);
                    foldedRefs.push_back(refs[entryReadIndex]);
                    for (const MicroInstrRef foldedRef : foldedRefs)
                    {
                        MicroInstr*        folded    = storage.ptr(foldedRef);
                        MicroInstrOperand* foldedOps = folded->ops(operands);
                        foldedOps[1].reg             = scratch;
                        folded->op                   = MicroInstrOpcode::OpBinaryRegReg;
                        folded->numOperands          = 4;
                    }
                    context.builder->invalidateControlFlowGraph();
                    return true;
                }
            }
        }
        return false;
    }
}

Result MicroPostRaLoopHoistPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    SWC_ASSERT(context.builder != nullptr);

    // Only the first post-RA sweep: what this hoists is the shape register
    // allocation just produced, and a later sweep would pay for the dominator,
    // loop and liveness analyses to find nothing.
    if (!context.isFirstOptimizationSweep)
        return Result::Continue;

    const CallConv& conv = CallConv::get(context.callConvKind);

    // The frame-reachability answer is a property of the function, so the rounds below share one.
    FrameReachability framePrivacy;
    for (uint32_t level = 0; level < K_MAX_LEVELS; ++level)
    {
        if (!hoistRound(context, conv, framePrivacy))
            break;
        context.passChanged = true;
    }

    while (hoistFoldedBitwiseOperand(context, conv))
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
