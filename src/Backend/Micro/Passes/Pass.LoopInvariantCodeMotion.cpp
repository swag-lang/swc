#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoopInvariantCodeMotion.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Memory/MemoryProfile.h"

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

    //===-- Dominators (Cooper-Harvey-Kennedy) on the per-instruction CFG --===//

    struct DomTree
    {
        std::vector<uint32_t> idom;   // idom[entry] == entry; K_INVALID if unreachable
        std::vector<uint32_t> rpoPos; // position in reverse-postorder; K_INVALID if unreachable

        bool reachable(uint32_t node) const { return node < idom.size() && idom[node] != K_INVALID; }

        bool dominates(uint32_t a, uint32_t b) const
        {
            if (!reachable(a) || !reachable(b))
                return false;
            uint32_t x = b;
            while (x != a && x != idom[x])
                x = idom[x];
            return x == a;
        }
    };

    DomTree computeDominators(const MicroControlFlowGraph& cfg, uint32_t entry)
    {
        const uint32_t n = cfg.instructionCount();
        DomTree        dom;
        dom.idom.assign(n, K_INVALID);
        dom.rpoPos.assign(n, K_INVALID);
        if (entry >= n)
            return dom;

        std::vector<uint32_t> postorder;
        postorder.reserve(n);
        std::vector<uint8_t>  visited(n, 0);
        std::vector<uint32_t> childCursor(n, 0);
        std::vector<uint32_t> stack;
        stack.push_back(entry);
        visited[entry] = 1;
        while (!stack.empty())
        {
            const uint32_t u    = stack.back();
            const auto&    succ = cfg.successors(u);
            if (childCursor[u] < succ.size())
            {
                const uint32_t v = succ[childCursor[u]++];
                if (v < n && !visited[v])
                {
                    visited[v] = 1;
                    stack.push_back(v);
                }
            }
            else
            {
                postorder.push_back(u);
                stack.pop_back();
            }
        }

        const uint32_t        count = static_cast<uint32_t>(postorder.size());
        std::vector<uint32_t> rpo;
        rpo.reserve(count);
        for (uint32_t i = count; i-- > 0;)
        {
            const uint32_t node = postorder[i];
            dom.rpoPos[node]    = static_cast<uint32_t>(rpo.size());
            rpo.push_back(node);
        }

        auto intersect = [&](uint32_t a, uint32_t b) {
            while (a != b)
            {
                while (dom.rpoPos[a] > dom.rpoPos[b])
                    a = dom.idom[a];
                while (dom.rpoPos[b] > dom.rpoPos[a])
                    b = dom.idom[b];
            }
            return a;
        };

        dom.idom[entry] = entry;
        bool changed    = true;
        while (changed)
        {
            changed = false;
            for (const uint32_t node : rpo)
            {
                if (node == entry)
                    continue;
                uint32_t newIdom = K_INVALID;
                for (const uint32_t pred : cfg.predecessors(node))
                {
                    if (pred >= n || dom.idom[pred] == K_INVALID)
                        continue;
                    newIdom = (newIdom == K_INVALID) ? pred : intersect(pred, newIdom);
                }
                if (newIdom != K_INVALID && newIdom != dom.idom[node])
                {
                    dom.idom[node] = newIdom;
                    changed        = true;
                }
            }
        }

        return dom;
    }

    struct NaturalLoop
    {
        uint32_t              header = K_INVALID;
        SmallVector<uint32_t> tails;
        std::vector<uint8_t>  inBody;
        uint32_t              bodySize = 0;
    };

    void collectLoopBody(const MicroControlFlowGraph& cfg, NaturalLoop& loop)
    {
        const uint32_t n = cfg.instructionCount();
        loop.inBody.assign(n, 0);
        loop.inBody[loop.header] = 1;
        std::vector<uint32_t> stack;
        for (const uint32_t t : loop.tails)
        {
            if (t < n && !loop.inBody[t])
            {
                loop.inBody[t] = 1;
                stack.push_back(t);
            }
        }
        while (!stack.empty())
        {
            const uint32_t x = stack.back();
            stack.pop_back();
            for (const uint32_t p : cfg.predecessors(x))
            {
                if (p < n && !loop.inBody[p])
                {
                    loop.inBody[p] = 1;
                    stack.push_back(p);
                }
            }
        }
        uint32_t size = 0;
        for (const uint8_t b : loop.inBody)
            size += b;
        loop.bodySize = size;
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

    // Order a loop's hoist set so a producer precedes every consumer.
    bool topoOrderHoistSet(const MicroSsaState&                ssaState,
                           std::span<const MicroInstrRef>      instrRefs,
                           const std::unordered_set<uint32_t>& hoistSet,
                           std::vector<uint32_t>&              outOrder)
    {
        std::unordered_map<MicroReg, uint32_t> regToNode;
        for (const uint32_t i : hoistSet)
        {
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

        const DomTree dom = computeDominators(cfg, entry);

        std::unordered_map<uint32_t, NaturalLoop> loopsByHeader;
        for (uint32_t u = 0; u < n; ++u)
        {
            if (!dom.reachable(u))
                continue;
            for (const uint32_t v : cfg.successors(u))
            {
                if (v < n && dom.dominates(v, u))
                {
                    NaturalLoop& loop = loopsByHeader[v];
                    loop.header       = v;
                    loop.tails.push_back(u);
                }
            }
        }
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
        {
            collectLoopBody(cfg, loop);
            loops.push_back(&loop);
        }
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

            std::unordered_set<uint32_t> hoistSet;
            std::unordered_set<MicroReg> hoistedRegs;
            bool                         progress = true;
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
                    if (dc == defCount.end() || dc->second != 1)
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
            if (!topoOrderHoistSet(*ssaState, instrRefs, hoistSet, order))
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
