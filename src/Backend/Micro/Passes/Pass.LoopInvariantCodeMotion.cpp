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
#include "Support/Memory/MemoryProfile.h"
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

    // Order a loop's hoist set so a producer precedes every consumer. For a
    // copy+compute pair both instructions define the same register: consumers
    // must depend on the compute (the final value), while the compute itself
    // depends on its copy through the explicit pair edge.
    bool topoOrderHoistSet(const MicroSsaState&                          ssaState,
                           std::span<const MicroInstrRef>                instrRefs,
                           const std::unordered_set<uint32_t>&           hoistSet,
                           const std::unordered_map<uint32_t, uint32_t>& pairedCopyOf,
                           const std::unordered_map<uint32_t, uint32_t>& pairedComputeOf,
                           std::vector<uint32_t>&                        outOrder)
    {
        std::unordered_map<MicroReg, uint32_t> regToNode;
        for (const uint32_t i : hoistSet)
        {
            if (pairedComputeOf.contains(i))
                continue;
            const MicroInstrUseDef* useDef = ssaState.instrUseDef(instrRefs[i]);
            if (useDef && useDef->defs.size() == 1)
                regToNode[useDef->defs[0]] = i;
        }

        std::unordered_map<uint32_t, uint32_t>              indegree;
        std::unordered_map<uint32_t, std::vector<uint32_t>> dependents;
        for (const uint32_t i : hoistSet)
            indegree[i] = 0;
        for (const uint32_t i : hoistSet)
        {
            const MicroInstrUseDef* useDef = ssaState.instrUseDef(instrRefs[i]);
            if (!useDef)
                continue;
            for (const MicroReg use : useDef->uses)
            {
                const auto producer = regToNode.find(use);
                if (producer != regToNode.end() && producer->second != i)
                {
                    dependents[producer->second].push_back(i);
                    ++indegree[i];
                }
            }
        }
        for (const auto& [compute, copy] : pairedCopyOf)
        {
            if (!hoistSet.contains(compute) || !hoistSet.contains(copy))
                continue;
            dependents[copy].push_back(compute);
            ++indegree[compute];
        }

        std::vector<uint32_t> ready;
        for (const uint32_t i : hoistSet)
            if (indegree[i] == 0)
                ready.push_back(i);
        std::ranges::sort(ready);

        outOrder.clear();
        outOrder.reserve(hoistSet.size());
        while (!ready.empty())
        {
            const uint32_t i = ready.front();
            ready.erase(ready.begin());
            outOrder.push_back(i);
            const auto depIt = dependents.find(i);
            if (depIt == dependents.end())
                continue;
            for (const uint32_t d : depIt->second)
            {
                if (--indegree[d] == 0)
                {
                    ready.push_back(d);
                    std::ranges::sort(ready);
                }
            }
        }
        return outOrder.size() == hoistSet.size();
    }

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

        const MicroPassHelpers::MicroDomTree dom           = MicroPassHelpers::computeInstructionDominators(cfg, entry);
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
                continue;

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
                continue;

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

            std::unordered_set<uint32_t>           hoistSet;
            std::unordered_set<MicroReg>           hoistedRegs;
            std::unordered_map<uint32_t, uint32_t> pairedCopyOf;    // compute slot -> its copy slot
            std::unordered_map<uint32_t, uint32_t> pairedComputeOf; // copy slot -> its compute slot

            // A copy whose destination has exactly two defs qualifies when the
            // second def is the immediately adjacent two-address compute over the
            // same register: both then move together, so every use still reads the
            // same (invariant) final value. Returns the compute's slot, K_INVALID
            // when the shape or one of its guards does not hold.
            const auto findAdjacentPairCompute = [&](MicroInstrRef copyRef, MicroReg destReg) -> uint32_t {
                if (!preheaderFlagsDead)
                    return K_INVALID;

                const MicroInstrRef computeRef = storage.findNextInstructionRef(copyRef);
                if (!computeRef.isValid() || relocRefs.contains(computeRef.get()) || claimed.contains(computeRef.get()))
                    return K_INVALID;
                const auto computeIdxIt = refToIndex.find(computeRef.get());
                if (computeIdxIt == refToIndex.end())
                    return K_INVALID;
                const uint32_t computeIdx = computeIdxIt->second;
                if (!inBody[computeIdx] || computeIdx == header || hoistSet.contains(computeIdx))
                    return K_INVALID;

                const MicroInstr* computeInst = storage.ptr(computeRef);
                if (!computeInst || !isEligiblePairedComputeOpcode(computeInst->op))
                    return K_INVALID;

                const MicroInstrUseDef* computeUseDef = ssaState->instrUseDef(computeRef);
                if (!computeUseDef || computeUseDef->isCall || computeUseDef->defs.size() != 1 || computeUseDef->defs[0] != destReg)
                    return K_INVALID;

                for (const MicroReg use : computeUseDef->uses)
                {
                    if (use == destReg)
                        continue;
                    if (defsInLoop.contains(use) && !hoistedRegs.contains(use))
                        return K_INVALID;
                }

                if (!MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, computeRef))
                    return K_INVALID;

                return computeIdx;
            };

            bool progress = true;
            while (progress)
            {
                progress = false;
                for (uint32_t i = 0; i < n; ++i)
                {
                    if (!inBody[i] || i == header || hoistSet.contains(i))
                        continue;

                    const MicroInstrRef ref = instrRefs[i];
                    if (claimed.contains(ref.get()))
                        continue; // already moving to an inner loop's preheader

                    const MicroInstr* inst = storage.ptr(ref);
                    if (!inst || !isEligibleOpcode(inst->op) || relocRefs.contains(ref.get()))
                        continue;

                    const MicroInstrUseDef* useDef = ssaState->instrUseDef(ref);
                    if (!useDef || useDef->isCall || useDef->defs.size() != 1)
                        continue;

                    const MicroReg destReg = useDef->defs[0];
                    if (!destReg.isVirtual())
                        continue;
                    const auto dc = defCount.find(destReg);
                    if (dc == defCount.end())
                        continue;

                    uint32_t pairComputeIndex = K_INVALID;
                    if (dc->second == 2)
                    {
                        pairComputeIndex = findAdjacentPairCompute(ref, destReg);
                        if (pairComputeIndex == K_INVALID)
                            continue;
                    }
                    else if (dc->second != 1)
                        continue;

                    bool allInvariant = true;
                    for (const MicroReg use : useDef->uses)
                    {
                        if (defsInLoop.contains(use) && !hoistedRegs.contains(use))
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
                    if (pairComputeIndex != K_INVALID)
                    {
                        hoistSet.insert(pairComputeIndex);
                        pairedCopyOf[pairComputeIndex] = i;
                        pairedComputeOf[i]             = pairComputeIndex;
                    }
                    hoistedRegs.insert(destReg);
                    progress = true;
                }
            }

            if (hoistSet.empty())
                continue;

            // Profitability filter (do-no-harm). Hoisting a value keeps it live
            // across the whole loop, costing a register. That only pays off for
            // memory reads (a removed per-iteration load) or values recomputed by
            // several in-loop uses. A standalone single-use address/copy would
            // just add register pressure, so keep only memory reads and multiply
            // used values, plus the hoisted operand chains that feed them.
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

                std::unordered_map<MicroReg, uint32_t> hoistedDef;
                for (const uint32_t i : hoistSet)
                {
                    // For a pair, consumers must pull the compute (the final value),
                    // never the copy; the copy is reached through the pair link.
                    if (pairedComputeOf.contains(i))
                        continue;
                    const MicroInstrUseDef* ud = ssaState->instrUseDef(instrRefs[i]);
                    if (ud && ud->defs.size() == 1)
                        hoistedDef[ud->defs[0]] = i;
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

                    // A pair moves or stays as a unit: a hoisted copy without its
                    // compute (or the reverse) would compound the two-address
                    // update across iterations.
                    const auto pairCopy = pairedCopyOf.find(i);
                    if (pairCopy != pairedCopyOf.end() && keep.insert(pairCopy->second).second)
                        worklist.push_back(pairCopy->second);
                    const auto pairCompute = pairedComputeOf.find(i);
                    if (pairCompute != pairedComputeOf.end() && keep.insert(pairCompute->second).second)
                        worklist.push_back(pairCompute->second);

                    const MicroInstrUseDef* ud = ssaState->instrUseDef(instrRefs[i]);
                    if (!ud)
                        continue;
                    for (const MicroReg use : ud->uses)
                    {
                        const auto producer = hoistedDef.find(use);
                        if (producer != hoistedDef.end() && keep.insert(producer->second).second)
                            worklist.push_back(producer->second);
                    }
                }

                hoistSet = std::move(keep);
            }
            if (hoistSet.empty())
                continue;

            std::vector<uint32_t> order;
            if (!topoOrderHoistSet(*ssaState, instrRefs, hoistSet, pairedCopyOf, pairedComputeOf, order))
                continue; // dependency cycle (should not happen) — skip defensively.

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
    SWC_MEM_SCOPE("Backend/MicroLower/LICM");
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
