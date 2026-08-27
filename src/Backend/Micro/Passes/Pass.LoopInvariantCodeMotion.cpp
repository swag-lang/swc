#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoopInvariantCodeMotion.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

// Loop-invariant code motion. See the header for the high-level contract.
//
// Operates on the per-instruction CFG exposed by the builder. A single run()
// hoists invariants out of every natural loop in the function, peeling one
// nesting level per internal round until a fixed point is reached, so the
// transform converges on its own rather than relying on the enclosing pre-RA
// optimization loop to re-run it (a large switch full of sibling loops would
// otherwise blow the pre-RA iteration cap).

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_INVALID    = std::numeric_limits<uint32_t>::max();
    constexpr uint32_t K_MAX_ROUNDS = 64;

    using NaturalLoop = MicroPassHelpers::NaturalLoop;

    // Value-producing opcodes that never touch CPU flags, never write memory,
    // and never call. Hoisting one only relocates the computation of its single
    // destination register.
    bool isEligibleOpcode(MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::LoadRegPtrImm:
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
                return true;
            default:
                return false;
        }
    }

    // Two-address compute opcodes (the destination is read-modify-write). They
    // never qualify alone: the incoming destination value is a use that changes
    // every iteration through the re-copy. They hoist only as the second half of
    // an adjacent copy+compute pair whose copy is hoisted with them, and since
    // they define CPU flags they additionally need flags to be dead both after
    // the compute and at the preheader insertion point.
    bool isEligiblePairedComputeOpcode(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::OpBinaryRegImm || op == MicroInstrOpcode::OpBinaryRegReg;
    }

    // The subset of eligible opcodes that dereference memory. Hoisting these
    // requires the extra alias + speculation guards.
    bool opcodeReadsMemory(MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                return true;
            default:
                return false;
        }
    }

    // For every eligible memory-reading load and for every store opcode handled
    // below, the addressing base register is the first use operand.
    MicroReg firstUseReg(const MicroInstrUseDef& useDef)
    {
        return useDef.uses.empty() ? MicroReg::invalid() : useDef.uses[0];
    }

    // A `mov`/`lea` that merely re-points an address. Returns the source whose
    // address it propagates (first use), else invalid().
    bool isAddressPropagation(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::LoadRegReg ||
               op == MicroInstrOpcode::LoadAddrRegMem ||
               op == MicroInstrOpcode::LoadAddrAmcRegMem;
    }

    // Stores whose base register is the first use operand. Push/Pop write only
    // the stack; any other memory writer is treated as an opaque pointer store.
    bool isFirstUseBaseStore(MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::LoadMemImm:
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
            case MicroInstrOpcode::OpUnaryMem:
                return true;
            default:
                return false;
        }
    }

    bool isStackOnlyWrite(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::Push || op == MicroInstrOpcode::Pop;
    }

    // Sound frame-privacy analysis.
    //
    // `frameDerived` is the set of single-def virtual registers that provably
    // hold an address into the current stack frame (the stack pointer, plus any
    // `mov`/`lea` chain rooted at it). `framePrivate` is true when no such
    // address ever escapes — i.e. every appearance of a frame-derived register
    // is either the base of a load/store or the propagation of another tracked
    // frame address. When private, a store to a frame slot cannot alias a load
    // through a register that is not frame-derived (no outside pointer can name
    // a private frame slot), which is what lets LICM hoist invariant loads past
    // the loop-carried accumulator spill.
    struct FramePrivacy
    {
        std::unordered_set<MicroReg> frameDerived;
        bool                         framePrivate = true;

        bool isFrame(MicroReg reg, MicroReg stackPointer) const
        {
            return reg == stackPointer || frameDerived.contains(reg);
        }
    };

    FramePrivacy analyzeFramePrivacy(MicroStorage&                                 storage,
                                     MicroOperandStorage&                          operands,
                                     std::span<const MicroInstrRef>                instrRefs,
                                     const MicroSsaState&                          ssaState,
                                     MicroReg                                      stackPointer,
                                     const std::unordered_map<MicroReg, uint32_t>& defCount,
                                     const Encoder*                                encoder)
    {
        FramePrivacy   fp;
        const uint32_t n = static_cast<uint32_t>(instrRefs.size());
        if (!stackPointer.isValid())
        {
            fp.framePrivate = false;
            return fp;
        }

        auto singleDefVirtual = [&](MicroReg reg) {
            if (!reg.isVirtualInt())
                return false;
            const auto it = defCount.find(reg);
            return it != defCount.end() && it->second == 1;
        };

        // Closure: propagate frame-derivedness through single-def mov/lea chains.
        bool changed = true;
        while (changed)
        {
            changed = false;
            for (uint32_t i = 0; i < n; ++i)
            {
                const MicroInstr* inst = storage.ptr(instrRefs[i]);
                if (!inst || !isAddressPropagation(inst->op))
                    continue;
                const MicroInstrUseDef* ud = ssaState.instrUseDef(instrRefs[i]);
                if (!ud || ud->defs.size() != 1 || ud->uses.empty())
                    continue;
                const MicroReg dst = ud->defs[0];
                const MicroReg src = ud->uses[0];
                if (!singleDefVirtual(dst) || fp.frameDerived.contains(dst))
                    continue;
                if (fp.isFrame(src, stackPointer))
                {
                    fp.frameDerived.insert(dst);
                    changed = true;
                }
            }
        }

        // Escape scan: any frame-derived register that appears as something other
        // than an explained base / propagation marks the frame as non-private.
        for (uint32_t i = 0; i < n && fp.framePrivate; ++i)
        {
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            if (!inst)
                continue;
            const MicroInstrUseDef* ud = ssaState.instrUseDef(instrRefs[i]);
            if (!ud)
                continue;

            MicroReg explainedBase = MicroReg::invalid();
            MicroReg explainedSrc  = MicroReg::invalid();
            MicroReg explainedDst  = MicroReg::invalid();

            if (isAddressPropagation(inst->op) && ud->defs.size() == 1 && fp.frameDerived.contains(ud->defs[0]))
            {
                explainedSrc = ud->uses.empty() ? MicroReg::invalid() : ud->uses[0];
                explainedDst = ud->defs[0];
            }
            else if (opcodeReadsMemory(inst->op) || isFirstUseBaseStore(inst->op))
            {
                explainedBase = firstUseReg(*ud);
            }

            const MicroInstr*                    mutInst = storage.ptr(instrRefs[i]);
            SmallVector<MicroInstrRegOperandRef> regRefs;
            mutInst->collectRegOperands(operands, regRefs, encoder);
            for (const auto& rref : regRefs)
            {
                if (!rref.reg)
                    continue;
                const MicroReg reg = *rref.reg;
                if (reg == stackPointer || !fp.frameDerived.contains(reg))
                    continue;
                if (reg == explainedBase || reg == explainedSrc || reg == explainedDst)
                    continue;
                fp.framePrivate = false;
                break;
            }
        }

        return fp;
    }

    // One instruction scheduled to move to a preheader, with its operands
    // snapshotted so applying the move never reads freed storage.
    struct Clone
    {
        MicroInstrOpcode               op;
        std::vector<MicroInstrOperand> ops;
        MicroInstrRef                  original;
    };

    struct HoistPlan
    {
        MicroInstrRef      headerRef = MicroInstrRef::invalid();
        std::vector<Clone> clones; // in preheader emission order
    };

    // Performs one round: hoists invariants out of every natural loop (innermost
    // first; an instruction claimed by an inner loop is left for the next round
    // to lift out of the enclosing one). Returns true if it changed the IR.
    bool licmHoistRound(MicroPassContext& context)
    {
        MicroStorage&        storage  = *context.instructions;
        MicroOperandStorage& operands = *context.operands;

        MicroSsaState        localSsaState;
        const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
        if (!ssaState || !ssaState->isValid())
            return false;

        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        if (cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;

        const uint32_t n = cfg.instructionCount();
        if (n == 0)
            return false;

        const auto instrRefs = cfg.instructionRefs();

        std::unordered_map<uint32_t, uint32_t> refToIndex;
        refToIndex.reserve(n);
        for (uint32_t i = 0; i < n; ++i)
            refToIndex[instrRefs[i].get()] = i;

        uint32_t entry      = K_INVALID;
        bool     multiEntry = false;
        for (uint32_t i = 0; i < n; ++i)
        {
            if (cfg.predecessors(i).empty())
            {
                if (entry == K_INVALID)
                    entry = i;
                else
                    multiEntry = true;
            }
        }
        if (entry == K_INVALID || multiEntry)
            return false;

        const MicroPassHelpers::MicroDomTree      dom           = MicroPassHelpers::computeInstructionDominators(cfg, entry);
        std::unordered_map<uint32_t, NaturalLoop> loopsByHeader = MicroPassHelpers::findNaturalLoops(cfg, dom);
        if (loopsByHeader.empty())
            return false;

        // Whole-function virtual-register def counts.
        std::unordered_map<MicroReg, uint32_t> defCount;
        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
            if (!useDef)
                continue;
            for (const MicroReg def : useDef->defs)
                ++defCount[def];
        }

        std::unordered_set<uint32_t> relocRefs;
        for (const MicroRelocation& reloc : context.builder->codeRelocations())
        {
            if (reloc.instructionRef.isValid())
                relocRefs.insert(reloc.instructionRef.get());
        }

        const MicroReg     stackPointer = CallConv::get(context.callConvKind).stackPointer;
        const FramePrivacy frame        = analyzeFramePrivacy(storage, operands, instrRefs, *ssaState, stackPointer, defCount, context.encoder);

        std::vector<NaturalLoop*> loops;
        loops.reserve(loopsByHeader.size());
        for (auto& loop : loopsByHeader | std::views::values)
            loops.push_back(&loop);
        std::ranges::sort(loops, [](const NaturalLoop* a, const NaturalLoop* b) {
            return a->bodySize < b->bodySize;
        });

        std::unordered_set<uint32_t> claimed; // instruction slot ids planned this round
        std::vector<HoistPlan>       plans;

        for (const NaturalLoop* loop : loops)
        {
            const uint32_t      header    = loop->header;
            const auto&         inBody    = loop->inBody;
            const MicroInstrRef headerRef = instrRefs[header];

            // Validate a clean preheader: exactly one predecessor outside the
            // loop, that predecessor is the immediate linear predecessor, and it
            // falls through into the header.
            uint32_t externalPredCount = 0;
            for (const uint32_t p : cfg.predecessors(header))
                if (p < n && !inBody[p])
                    ++externalPredCount;
            if (externalPredCount != 1)
            {
                continue;
            }

            const MicroInstrRef prevRef = storage.findPreviousInstructionRef(headerRef);
            if (!prevRef.isValid())
                continue;
            const auto prevIdxIt = refToIndex.find(prevRef.get());
            if (prevIdxIt == refToIndex.end() || inBody[prevIdxIt->second])
                continue;
            const MicroInstr* prevInst = storage.ptr(prevRef);
            if (!prevInst)
                continue;
            const MicroInstrFlags prevFlags = MicroInstr::info(prevInst->op).flags;
            const bool            prevIsUncondJump =
                prevFlags.has(MicroInstrFlagsE::JumpInstruction) && !prevFlags.has(MicroInstrFlagsE::ConditionalJump);
            const bool prevIsUncondTerm =
                prevFlags.has(MicroInstrFlagsE::TerminatorInstruction) && !prevFlags.has(MicroInstrFlagsE::ConditionalJump);
            if (prevIsUncondJump || prevIsUncondTerm)
            {
                continue;
            }

            // Pure loads/copies never touch CPU flags, but a hoisted copy+compute
            // pair inserts a flag-writing instruction at the preheader insertion
            // point, which is only sound when no flags are live across it.
            const bool preheaderFlagsDead = MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, prevRef);

            // Classify the loop's memory writers. A call or an opaque pointer
            // store may alias anything and blocks load hoisting; a store to a
            // private frame slot only aliases frame-derived loads.
            bool loopHasCall         = false;
            bool loopHasPointerStore = false;
            bool loopHasFrameStore   = false;
            for (uint32_t i = 0; i < n; ++i)
            {
                if (!inBody[i])
                    continue;
                const MicroInstr*       inst   = storage.ptr(instrRefs[i]);
                const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
                if (!inst || !useDef)
                    continue;
                if (useDef->isCall || MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                {
                    loopHasCall = true;
                    continue;
                }
                if (!MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::WritesMemory))
                    continue;
                if (isStackOnlyWrite(inst->op))
                {
                    loopHasFrameStore = true;
                    continue;
                }
                if (!isFirstUseBaseStore(inst->op))
                {
                    loopHasPointerStore = true; // unclassified writer: assume aliasing
                    continue;
                }
                const MicroReg base = firstUseReg(*useDef);
                if (base.isValid() && frame.isFrame(base, stackPointer))
                    loopHasFrameStore = true;
                else
                    loopHasPointerStore = true;
            }

            std::unordered_set<MicroReg> defsInLoop;
            for (uint32_t i = 0; i < n; ++i)
            {
                if (!inBody[i])
                    continue;
                const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
                if (!useDef)
                    continue;
                for (const MicroReg def : useDef->defs)
                    defsInLoop.insert(def);
            }

            // Webs: the unit LLVM's MachineLICM gets for free from SSA. The
            // lowering reuses one virtual register through two-address chains,
            // so a register may carry several values in sequence; each full
            // definition (an eligible value-producing opcode) starts a web and
            // every two-address compute continues the web of the previous
            // definition. LLVM never sees the multi-def shape because the
            // TwoAddress copies are only inserted after its loop passes run;
            // here the web is reconstructed and hoisted whole instead - all of
            // a register's defs move or none do - and the preheader emits the
            // members in listing order, which reproduces the def-use texture
            // exactly, mid-web reads between hoisted members included.
            struct RegWeb
            {
                std::vector<uint32_t> defSlots; // ascending
                bool                  chainOk = true;
            };
            std::unordered_map<MicroReg, RegWeb> websByReg;
            std::vector<MicroReg>                slotDefReg(n, MicroReg::invalid());
            std::vector<uint8_t>                 slotIsFullDef(n, 0);
            std::vector<uint8_t>                 slotIsCompute(n, 0);
            for (uint32_t i = 0; i < n; ++i)
            {
                if (!inBody[i] || i == header)
                    continue;
                const MicroInstr*       inst   = storage.ptr(instrRefs[i]);
                const MicroInstrUseDef* useDef = ssaState->instrUseDef(instrRefs[i]);
                if (!inst || !useDef)
                    continue;

                if (useDef->defs.size() != 1 || !useDef->defs[0].isVirtual() || useDef->isCall)
                {
                    for (const MicroReg def : useDef->defs)
                        if (def.isVirtual())
                            websByReg[def].chainOk = false;
                    continue;
                }

                const MicroReg destReg = useDef->defs[0];
                RegWeb&        web     = websByReg[destReg];

                // A definition that reads its own destination continues the
                // web whatever its opcode: a two-address arithmetic op, or an
                // address computation the multiply-to-lea rewrite produced,
                // `%r = &[%r + %r*2]`. A definition that does not is a full
                // def and starts a fresh value.
                bool selfUse = false;
                for (const MicroReg use : useDef->uses)
                    selfUse = selfUse || use == destReg;

                const bool eligible = isEligibleOpcode(inst->op) || isEligiblePairedComputeOpcode(inst->op);
                if (!eligible)
                    web.chainOk = false;
                else if (selfUse)
                    slotIsCompute[i] = 1;
                else if (isEligibleOpcode(inst->op))
                    slotIsFullDef[i] = 1;
                else
                    web.chainOk = false; // a paired-compute opcode with no self-read defines from a carried value

                // A compute with no prior definition in the body reads a
                // loop-carried value.
                if (slotIsCompute[i] && web.defSlots.empty())
                    web.chainOk = false;

                web.defSlots.push_back(i);
                slotDefReg[i] = destReg;
            }

            constexpr size_t K_MAX_WEB_DEFS = 32;

            const auto webEligible = [&](const MicroReg reg) {
                const auto it = websByReg.find(reg);
                if (it == websByReg.end() || !it->second.chainOk)
                    return false;
                if (it->second.defSlots.size() > K_MAX_WEB_DEFS)
                    return false;
                const auto dc = defCount.find(reg);
                return dc != defCount.end() && dc->second == it->second.defSlots.size();
            };

            std::unordered_set<uint32_t> hoistSet;
            std::unordered_set<MicroReg>           banned;

            // The value a use reads at slot i is hoisted when every earlier def
            // of its register is: emission in listing order then reproduces it
            // in the preheader.
            const auto acceptedPrefix = [&](const MicroReg reg, const uint32_t slot) {
                const auto it = websByReg.find(reg);
                if (it == websByReg.end())
                    return false;
                for (const uint32_t defSlot : it->second.defSlots)
                {
                    if (defSlot >= slot)
                        break;
                    if (!hoistSet.contains(defSlot))
                        return false;
                }
                return true;
            };

            const auto runAcceptance = [&]() {
                hoistSet.clear();
                bool progress = true;
                while (progress)
                {
                    progress = false;
                    for (uint32_t i = 0; i < n; ++i)
                    {
                        if (!inBody[i] || i == header || hoistSet.contains(i))
                            continue;

                        const MicroInstrRef ref = instrRefs[i];
                        if (claimed.contains(ref.get()) || relocRefs.contains(ref.get()))
                            continue;

                        const MicroReg destReg = slotDefReg[i];
                        if (!destReg.isValid() || banned.contains(destReg) || !webEligible(destReg))
                            continue;
                        if (!slotIsFullDef[i] && !slotIsCompute[i])
                            continue;

                        const MicroInstr*       inst   = storage.ptr(ref);
                        const MicroInstrUseDef* useDef = ssaState->instrUseDef(ref);
                        if (!inst || !useDef)
                            continue;

                        if (slotIsCompute[i])
                        {
                            if (!acceptedPrefix(destReg, i))
                                continue;
                            // A flag-writing continuation writes flags at the
                            // preheader insertion point and stops producing
                            // them here; an address computation writes none.
                            if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::DefinesCpuFlags) &&
                                (!preheaderFlagsDead ||
                                 !MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, ref)))
                                continue;
                        }

                        // A multi-def web is only the value sequence its listing
                        // shows when every member runs on every iteration: a
                        // member inside one arm of a branch would make the
                        // register's final value path-dependent, which one
                        // preheader execution cannot reproduce. Every member
                        // must dominate every back-edge tail.
                        const auto webIt = websByReg.find(destReg);
                        if (webIt != websByReg.end() && webIt->second.defSlots.size() > 1)
                        {
                            bool dominatesTails = true;
                            for (const uint32_t t : loop->tails)
                            {
                                if (!dom.dominates(i, t))
                                {
                                    dominatesTails = false;
                                    break;
                                }
                            }
                            if (!dominatesTails)
                            {
                                continue;
                            }
                        }

                        bool allInvariant = true;
                        for (const MicroReg use : useDef->uses)
                        {
                            if (use == destReg && slotIsCompute[i])
                                continue; // the web's own previous value
                            if (!defsInLoop.contains(use))
                                continue;
                            if (banned.contains(use) || !webEligible(use) || !acceptedPrefix(use, i))
                            {
                                allInvariant = false;
                                break;
                            }
                        }
                        if (!allInvariant)
                            continue;

                        if (opcodeReadsMemory(inst->op))
                        {
                            // A call may write the loaded location; never hoist past one.
                            if (loopHasCall)
                                continue;

                            const MicroReg base        = firstUseReg(*useDef);
                            const bool     baseIsFrame = base.isValid() && frame.isFrame(base, stackPointer);
                            if (baseIsFrame)
                            {
                                // Reading a frame slot: any store in the loop may hit it.
                                if (loopHasFrameStore || loopHasPointerStore)
                                    continue;
                            }
                            else
                            {
                                // Reading through a pointer. An opaque pointer store may
                                // alias it. A frame store cannot, provided the load's base
                                // is a single-def register that is definitely not a frame
                                // address and no frame address escapes the function.
                                if (loopHasPointerStore)
                                    continue;
                                if (loopHasFrameStore)
                                {
                                    const auto bc            = base.isValid() ? defCount.find(base) : defCount.end();
                                    const bool baseSingleDef = bc != defCount.end() && bc->second == 1;
                                    if (!frame.framePrivate || !baseSingleDef)
                                        continue;
                                }
                            }

                            // Speculation safety: the load must already run on every
                            // iteration (dominate every back-edge tail).
                            bool dominatesAllTails = true;
                            for (const uint32_t t : loop->tails)
                            {
                                if (!dom.dominates(i, t))
                                {
                                    dominatesAllTails = false;
                                    break;
                                }
                            }
                            if (!dominatesAllTails)
                                continue;
                        }

                        hoistSet.insert(i);
                        progress = true;
                    }
                }
            };

            // Loop exits, for the web-consistency rule below: a slot inside the
            // body with a successor outside it.
            SmallVector<uint32_t> exitSlots;
            for (uint32_t i = 0; i < n; ++i)
            {
                if (!inBody[i])
                    continue;
                for (const uint32_t succ : cfg.successors(i))
                {
                    if (succ < n && !inBody[succ])
                    {
                        exitSlots.push_back(i);
                        break;
                    }
                }
            }

            // Accept optimistically, filter for profit, then enforce web
            // integrity on what remains: a register with any hoisted def needs
            // all of them hoisted (its in-loop value otherwise restarts from
            // the preheader copy every iteration), and a non-hoisted reader may
            // only see the FINAL value - reads before the first def see the
            // carried final of the previous iteration, which hoisting
            // preserves; reads between defs see an intermediate, which it does
            // not. A violating register is banned and the whole pipeline reruns
            // without it, cascading until stable.
            for (;;)
            {
                runAcceptance();

                // Profitability filter (do-no-harm). Hoisting a value keeps it
                // live across the whole loop, costing a register. That only
                // pays off for memory reads (a removed per-iteration load) or
                // values recomputed by several in-loop uses. A standalone
                // single-use address/copy would just add register pressure, so
                // keep only memory reads and multiply used values, plus the
                // hoisted webs that feed them.
                if (!hoistSet.empty())
                {
                    std::unordered_map<MicroReg, uint32_t> inLoopUse;
                    for (uint32_t i = 0; i < n; ++i)
                    {
                        if (!inBody[i])
                            continue;
                        const MicroInstrUseDef* ud = ssaState->instrUseDef(instrRefs[i]);
                        if (!ud)
                            continue;
                        for (const MicroReg use : ud->uses)
                            ++inLoopUse[use];
                    }

                    std::unordered_set<uint32_t> keep;
                    std::vector<uint32_t>        worklist;
                    for (const uint32_t i : hoistSet)
                    {
                        const MicroInstr*       inst = storage.ptr(instrRefs[i]);
                        const MicroInstrUseDef* ud   = ssaState->instrUseDef(instrRefs[i]);
                        if (!inst || !ud || ud->defs.size() != 1)
                            continue;
                        const auto uc           = inLoopUse.find(ud->defs[0]);
                        const bool multiplyUsed = uc != inLoopUse.end() && uc->second >= 2;
                        if (opcodeReadsMemory(inst->op) || multiplyUsed)
                        {
                            if (keep.insert(i).second)
                                worklist.push_back(i);
                        }
                    }
                    while (!worklist.empty())
                    {
                        const uint32_t i = worklist.back();
                        worklist.pop_back();

                        // A web moves or stays as a unit, and a member's
                        // operands pull the producing webs whole: keeping a
                        // compute without the defs before it would compound the
                        // two-address update across iterations.
                        const MicroInstrUseDef* ud = ssaState->instrUseDef(instrRefs[i]);
                        if (!ud)
                            continue;

                        SmallVector<MicroReg> pullRegs;
                        if (ud->defs.size() == 1)
                            pullRegs.push_back(ud->defs[0]);
                        for (const MicroReg use : ud->uses)
                            pullRegs.push_back(use);

                        for (const MicroReg reg : pullRegs)
                        {
                            const auto webIt = websByReg.find(reg);
                            if (webIt == websByReg.end())
                                continue;
                            for (const uint32_t defSlot : webIt->second.defSlots)
                            {
                                if (hoistSet.contains(defSlot) && keep.insert(defSlot).second)
                                    worklist.push_back(defSlot);
                            }
                        }
                    }

                    hoistSet = std::move(keep);
                }

                SmallVector<MicroReg> violations;
                std::unordered_map<MicroReg, uint32_t> keptDefsOf;
                for (const uint32_t i : hoistSet)
                    ++keptDefsOf[slotDefReg[i]];
                for (const auto& [reg, count] : keptDefsOf)
                {
                    const auto webIt = websByReg.find(reg);
                    if (webIt == websByReg.end() || count != webIt->second.defSlots.size())
                    {
                        violations.push_back(reg);
                        continue;
                    }

                    // Only a read of the FINAL value survives hoisting: a read
                    // between defs would see an intermediate, and a read before
                    // the first def saw the previous iteration's value on entry
                    // paths this transform cannot audit. Both kinds ban the web.
                    const auto& defSlots = webIt->second.defSlots;
                    if (defSlots.size() <= 1)
                        continue;
                    const uint32_t firstDef = defSlots.front();
                    const uint32_t lastDef  = defSlots.back();
                    bool           violated = false;
                    for (uint32_t s = 0; s <= lastDef && !violated; ++s)
                    {
                        if (!inBody[s] || hoistSet.contains(s))
                            continue;
                        const MicroInstrUseDef* ud = ssaState->instrUseDef(instrRefs[s]);
                        if (!ud)
                            continue;
                        for (const MicroReg use : ud->uses)
                            violated = violated || use == reg;
                    }

                    // An exit taken mid-web leaves the register holding an
                    // intermediate of the aborted iteration, which the hoisted
                    // final cannot reproduce. Every exit must either dominate
                    // the first def (the register then held the previous
                    // iteration's final, which hoisting preserves) or be
                    // dominated by the last def (the final of this iteration).
                    for (const uint32_t e : exitSlots)
                    {
                        if (violated)
                            break;
                        violated = !dom.dominates(e, firstDef) && !dom.dominates(lastDef, e);
                    }

                    // A multi-def web is only atomic when its span is straight
                    // line: a label or jump between its defs would let control
                    // enter or leave mid-sequence, and the register's value
                    // would again depend on the path. The single preheader
                    // execution reproduces exactly the uninterrupted sequence.
                    for (uint32_t s = firstDef; s <= lastDef && !violated; ++s)
                    {
                        const MicroInstr* spanInst = storage.ptr(instrRefs[s]);
                        if (!spanInst)
                        {
                            violated = true;
                            break;
                        }
                        const MicroInstrFlags spanFlags = MicroInstr::info(spanInst->op).flags;
                        violated = spanInst->op == MicroInstrOpcode::Label ||
                                   spanFlags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                                   spanFlags.has(MicroInstrFlagsE::JumpInstruction) ||
                                   spanFlags.has(MicroInstrFlagsE::IsCallInstruction);
                    }

                    if (violated)
                        violations.push_back(reg);
                }

                if (violations.empty())
                    break;
                for (const MicroReg reg : violations)
                    banned.insert(reg);
            }

            if (hoistSet.empty())
                continue;

            // Listing order is the dependency order: every hoisted member sits
            // in one loop body, and its operands are produced above it there.
            std::vector<uint32_t> order(hoistSet.begin(), hoistSet.end());
            std::ranges::sort(order);

            HoistPlan plan;
            plan.headerRef = headerRef;
            plan.clones.reserve(order.size());
            for (const uint32_t i : order)
            {
                const MicroInstrRef ref  = instrRefs[i];
                MicroInstr*         inst = storage.ptr(ref);
                if (!inst)
                    continue;
                const MicroInstrOperand* ops = inst->ops(operands);
                Clone                    clone;
                clone.op       = inst->op;
                clone.original = ref;
                if (ops && inst->numOperands)
                    clone.ops.assign(ops, ops + inst->numOperands);
                plan.clones.push_back(std::move(clone));
                claimed.insert(ref.get());
            }
            plans.push_back(std::move(plan));
        }

        if (plans.empty())
            return false;

        for (const HoistPlan& plan : plans)
            for (const Clone& clone : plan.clones)
                storage.insertDerivedBefore(operands, plan.headerRef, clone.op, clone.ops);
        for (const HoistPlan& plan : plans)
            for (const Clone& clone : plan.clones)
                storage.erase(clone.original);

        if (context.ssaState)
            context.ssaState->invalidate();
        context.builder->invalidateControlFlowGraph();
        return true;
    }
}

Result MicroLoopInvariantCodeMotionPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    if (!context.builder)
        return Result::Continue;

    // Loop-invariant code motion is meaningless without loops. A cheap back-edge
    // test on the (cached) CFG lets the overwhelmingly common loop-free functions
    // skip the SSA build, dominator-tree construction and map allocations this
    // pass would otherwise perform every time it runs.
    if (!context.builder->controlFlowGraph().hasLoop())
        return Result::Continue;

    bool changedAny = false;
    for (uint32_t round = 0; round < K_MAX_ROUNDS; ++round)
    {
        if (!licmHoistRound(context))
            break;
        changedAny = true;
    }

    if (changedAny)
        context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
