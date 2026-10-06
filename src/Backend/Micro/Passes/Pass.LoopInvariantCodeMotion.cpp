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
#include "Compiler/Sema/Symbol/Symbol.Function.h"
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
    constexpr uint32_t K_MAX_ROUNDS = 64;

    using NaturalLoop          = MicroPassHelpers::NaturalLoop;
    using RegDefinitionSummary = MicroPassHelpers::RegDefinitionSummary;

    // Value-producing opcodes that never write memory or call. A flag-writing
    // clear additionally needs dead flags at both sites. Hoisting relocates its single
    // destination register. The vector forms are the three-operand ones that
    // write a destination they do not read: a lane broadcast, a shuffle, a
    // packed operation on invariant inputs.
    bool isEligibleOpcode(MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::ClearReg:
            case MicroInstrOpcode::LoadRegPtrImm:
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::VecUnaryAmcRegMem:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadVecRegMem:
            case MicroInstrOpcode::VecUnaryRegMem:
            case MicroInstrOpcode::VecShuffleRegRegImm:
            case MicroInstrOpcode::VecUnaryRegReg:
            case MicroInstrOpcode::OpBinaryRegRegImm:
            case MicroInstrOpcode::OpBinaryRegRegReg:
                return true;
            default:
                return false;
        }
    }

    // A materialization that pays for its register even with a single reader:
    // nonzero scalar float literals become constant loads during legalization,
    // while vectors need lane moves, shuffles or packed operations to rebuild.
    // This is a candidate even when a reader can fold a memory operand: a
    // retained value can remove that memory read from every loop iteration.
    bool isCostlyMaterialization(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops || !ops[0].reg.isVirtualFloat())
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegImm:
                return (ops[1].opBits == MicroOpBits::B32 || ops[1].opBits == MicroOpBits::B64) && !ops[2].isImmediateZero();
            case MicroInstrOpcode::LoadRegReg:
                return ops[1].reg.isAnyInt();
            case MicroInstrOpcode::VecShuffleRegRegImm:
            case MicroInstrOpcode::VecUnaryRegReg:
            case MicroInstrOpcode::OpBinaryRegRegImm:
            case MicroInstrOpcode::OpBinaryRegRegReg:
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
            case MicroInstrOpcode::VecUnaryAmcRegMem:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadVecRegMem:
            case MicroInstrOpcode::VecUnaryRegMem:
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

    // The relocated instructions a hoist may clone: the relocation patches a
    // global or constant address into a load, so the clone reads the same
    // location wherever it sits. A relocated address materialization stays
    // where it is: it is one dependency-free immediate the allocator would
    // re-make in the loop anyway, and hoisting it only costs a spill slot
    // (measured on sha256's round-constant table, +2 instructions, +1 slot).
    bool isRelocatableHoist(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::LoadRegMem ||
               op == MicroInstrOpcode::LoadAddrRegMem ||
               op == MicroInstrOpcode::LoadSignedExtRegMem ||
               op == MicroInstrOpcode::LoadZeroExtRegMem ||
               op == MicroInstrOpcode::LoadVecRegMem;
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
            case MicroInstrOpcode::StoreVecMemReg:
                return true;
            default:
                return false;
        }
    }

    bool isStackOnlyWrite(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::Push || op == MicroInstrOpcode::Pop;
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

        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        if (cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
            return false;

        const uint32_t n = cfg.instructionCount();
        if (n == 0)
            return false;

        const auto instrRefs = cfg.instructionRefs();

        const uint32_t entry = MicroPassHelpers::findSingleCfgEntry(cfg);
        if (entry == MicroPassHelpers::MicroDomTree::K_INVALID_NODE)
            return false;

        const MicroPassHelpers::MicroDomTree      dom           = MicroPassHelpers::computeInstructionDominators(cfg, entry, context.ssaState);
        std::unordered_map<uint32_t, NaturalLoop> loopsByHeader = MicroPassHelpers::findNaturalLoops(cfg, dom);
        if (loopsByHeader.empty())
            return false;

        // Only a loop with a clean fall-through preheader can move code. Keep
        // the existing loop order, but reject the others before collecting
        // whole-function register effects, relocations, and frame privacy.
        thread_local std::vector<NaturalLoop*> loops;
        loops.clear();
        loops.reserve(loopsByHeader.size());
        for (auto& loop : loopsByHeader | std::views::values)
            loops.push_back(&loop);
        std::ranges::sort(loops, [](const NaturalLoop* a, const NaturalLoop* b) {
            return a->bodySize < b->bodySize;
        });
        std::erase_if(loops, [&](const NaturalLoop* loop) {
            const uint32_t header = loop->header;
            if (!header)
                return true;

            uint32_t externalPredCount = 0;
            for (const uint32_t p : cfg.predecessors(header))
                if (p < n && !loop->inBody[p])
                    ++externalPredCount;
            if (externalPredCount != 1)
                return true;

            const MicroInstrRef prevRef = storage.findPreviousInstructionRef(instrRefs[header]);
            if (prevRef.isInvalid() || instrRefs[header - 1] != prevRef || loop->inBody[header - 1])
                return true;
            const MicroInstr* prevInst = storage.ptr(prevRef);
            if (!prevInst)
                return true;
            const MicroInstrFlags prevFlags = MicroInstr::info(prevInst->op).flags;
            return (prevFlags.has(MicroInstrFlagsE::JumpInstruction) || prevFlags.has(MicroInstrFlagsE::TerminatorInstruction)) &&
                   !prevFlags.has(MicroInstrFlagsE::ConditionalJump);
        });
        if (loops.empty())
            return false;

        std::vector<uint32_t> innermostLoopSizes(n, n + 1);
        for (const auto& nested : loopsByHeader | std::views::values)
        {
            for (uint32_t i = 0; i < n; ++i)
            {
                if (nested.inBody[i])
                    innermostLoopSizes[i] = std::min(innermostLoopSizes[i], nested.bodySize);
            }
        }

        // Hoisting needs instruction-local effects, not SSA values or phis.
        // Collect these only after finding a natural loop worth analyzing.
        thread_local std::vector<MicroInstrUseDef>                      useDefs;
        thread_local std::unordered_map<MicroReg, RegDefinitionSummary> definitions;
        useDefs.resize(n); // every instruction effect is replaced below
        definitions.clear();
        for (uint32_t i = 0; i < n; ++i)
        {
            const MicroInstr* inst = storage.ptr(instrRefs[i]);
            if (!inst)
                return false;
            useDefs[i] = {};
            inst->collectUseDef(useDefs[i], operands, context.encoder);
            const MicroInstrUseDef* useDef = &useDefs[i];
            for (const MicroReg def : useDef->defs)
            {
                RegDefinitionSummary& summary = definitions[def];
                ++summary.count;
                summary.lastSlot = i;
            }
        }

        auto&                                             relocations   = context.builder->codeRelocations();
        const size_t                                      relocationEnd = relocations.size();
        thread_local std::unordered_map<uint32_t, size_t> firstRelocation;
        thread_local std::vector<size_t>                  nextRelocation;
        firstRelocation.clear();
        nextRelocation.assign(relocationEnd, relocationEnd);
        // One compact chain per instruction, preserving relocation order and
        // duplicates without allocating a separate vector for every key.
        for (size_t index = relocationEnd; index != 0;)
        {
            --index;
            const MicroInstrRef ref = relocations[index].instructionRef;
            if (ref.isInvalid())
                continue;
            const auto [it, inserted] = firstRelocation.try_emplace(ref.get(), index);
            if (!inserted)
            {
                nextRelocation[index] = it->second;
                it->second            = index;
            }
        }

        const auto callDoesNotWrite = [&](const MicroInstrRef ref, const MicroInstrOpcode op) {
            if (op != MicroInstrOpcode::CallLocal && op != MicroInstrOpcode::CallExtern)
                return false;
            const auto it = firstRelocation.find(ref.get());
            if (it == firstRelocation.end())
                return false;
            const Symbol* target = relocations[it->second].targetSymbol;
            return target && target->isFunction() && target->cast<SymbolFunction>().attributes().hasRtFlag(RtAttributeFlagsE::ReadOnly);
        };

        // A private global is reached only through its own direct accesses. Its address may sit in
        // a register that is defined once and only ever used as the base of a load or a store:
        // an access through it is still direct. Any other use lets the address flow somewhere a
        // pointer store could reach it from, and the global keeps the ordinary rules.
        const auto relocationKey = [](const MicroRelocation& relocation) {
            return (static_cast<uint64_t>(relocation.kind) << 56) ^ relocation.targetAddress;
        };
        thread_local std::unordered_set<uint64_t>           materializedPrivateGlobals;
        thread_local std::unordered_map<MicroReg, uint64_t> privateGlobalBases;
        materializedPrivateGlobals.clear();
        privateGlobalBases.clear();
        for (const MicroRelocation& relocation : relocations)
        {
            if (!relocation.privateGlobal || relocation.instructionRef.isInvalid())
                continue;
            const MicroInstr* inst = storage.ptr(relocation.instructionRef);
            if (!inst || inst->op != MicroInstrOpcode::LoadRegPtrReloc)
                continue;
            const MicroInstrOperand* instOps = inst->ops(operands);
            const MicroReg           reg     = instOps ? instOps[0].reg : MicroReg{};
            const auto               def     = reg.isVirtualInt() ? definitions.find(reg) : definitions.end();
            if (def == definitions.end() || def->second.count != 1)
                materializedPrivateGlobals.insert(relocationKey(relocation));
            else
                privateGlobalBases.emplace(reg, relocationKey(relocation));
        }
        if (!privateGlobalBases.empty())
        {
            for (uint32_t i = 0; i < n; ++i)
            {
                const MicroInstr* inst = storage.ptr(instrRefs[i]);
                if (!inst)
                    continue;
                uint8_t                  baseIndex = 0;
                const bool               hasBase   = MicroPassHelpers::dereferenceBaseOperandIndex(baseIndex, inst->op, MicroInstr::info(inst->op));
                const MicroInstrOperand* instOps   = inst->ops(operands);
                for (const MicroReg use : useDefs[i].uses)
                {
                    const auto it = privateGlobalBases.find(use);
                    if (it == privateGlobalBases.end())
                        continue;
                    // This loop already proves one use; only a sole base use with no definition stays private.
                    if (!hasBase || !instOps || instOps[baseIndex].reg != use ||
                        std::ranges::count(useDefs[i].uses, use) != 1 ||
                        std::ranges::find(useDefs[i].defs, use) != useDefs[i].defs.end())
                        materializedPrivateGlobals.insert(it->second);
                }
            }
        }

        const MicroReg stackPointer = CallConv::get(context.callConvKind).stackPointer;
        const auto     frame        = MicroPassHelpers::analyzeFramePrivacy(context, instrRefs, useDefs, definitions);

        // A value-handle parameter passed by reference is immutable to the
        // callee: no store and no call in a loop changes what a read through
        // its incoming address returns.
        thread_local std::unordered_set<MicroReg> immutableBases;
        MicroPassHelpers::collectImmutableStorageBases(immutableBases, context);

        thread_local std::unordered_set<uint32_t> claimed; // instruction slot ids planned this round
        thread_local std::vector<HoistPlan>       plans;
        thread_local std::vector<uint32_t>        bodyIndices;
        thread_local std::vector<MicroReg>        slotDefReg;
        thread_local std::vector<uint8_t>         slotIsFullDef;
        thread_local std::vector<uint8_t>         slotIsCompute;
        claimed.clear();
        plans.clear();

        for (const NaturalLoop* loop : loops)
        {
            const uint32_t      header    = loop->header;
            const auto&         inBody    = loop->inBody;
            const MicroInstrRef headerRef = instrRefs[header];
            // The prefilter proved this is the physical fall-through predecessor.
            const MicroInstrRef prevRef = instrRefs[header - 1];

            // Pure loads/copies never touch CPU flags, but a hoisted copy+compute
            // pair inserts a flag-writing instruction at the preheader insertion
            // point, which is only sound when no flags are live across it.
            const bool preheaderFlagsDead = MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, prevRef, context.builder);

            // Classify the loop's memory writers. A call or an opaque pointer
            // store may alias anything and blocks load hoisting; a store to a
            // private frame slot only aliases frame-derived loads.
            // Keep the body's listing order once; acceptance retries must not
            // rescan the rest of the function for each loop.
            bodyIndices.clear();
            bodyIndices.reserve(loop->bodySize);
            thread_local std::unordered_set<MicroReg> defsInLoop;
            thread_local std::unordered_set<MicroReg> dereferenceBasesInLoop;
            defsInLoop.clear();
            dereferenceBasesInLoop.clear();
            thread_local std::unordered_set<uint64_t> directStoreTargets;
            directStoreTargets.clear();
            bool loopHasCall         = false;
            bool loopHasReadOnlyCall = false;
            bool loopHasPointerStore = false;
            bool loopHasFrameStore   = false;
            bool loopHasNestedLoop   = false;
            for (uint32_t i = 0; i < n; ++i)
            {
                if (!inBody[i])
                    continue;
                bodyIndices.push_back(i);
                loopHasNestedLoop |= innermostLoopSizes[i] < loop->bodySize;
                const MicroInstr*       inst   = storage.ptr(instrRefs[i]);
                const MicroInstrUseDef* useDef = &useDefs[i];
                if (!inst)
                    continue;
                for (const MicroReg def : useDef->defs)
                    defsInLoop.insert(def);
                uint8_t                  baseOperandIndex = 0;
                const MicroInstrOperand* memoryOps        = MicroPassHelpers::dereferenceBaseOperandIndex(baseOperandIndex, inst->op, MicroInstr::info(inst->op)) ? inst->ops(operands) : nullptr;
                if (memoryOps)
                    dereferenceBasesInLoop.insert(memoryOps[baseOperandIndex].reg);
                if (useDef->isCall || MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::IsCallInstruction))
                {
                    if (callDoesNotWrite(instrRefs[i], inst->op))
                        loopHasReadOnlyCall = true;
                    else
                        loopHasCall = true;
                    continue;
                }
                if (!MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::WritesMemory))
                    continue;
                // A writer carrying a relocation addresses its target directly.
                if (const auto relocationIt = firstRelocation.find(instrRefs[i].get()); relocationIt != firstRelocation.end())
                {
                    for (size_t index = relocationIt->second; index < relocationEnd; index = nextRelocation[index])
                        directStoreTargets.insert(relocationKey(relocations[index]));
                }
                // So does one writing through a register that holds a private global's address.
                if (memoryOps)
                {
                    if (const auto privateBase = privateGlobalBases.find(memoryOps[baseOperandIndex].reg); privateBase != privateGlobalBases.end())
                        directStoreTargets.insert(privateBase->second);
                }
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

            // Reassociate a three-register memory address at the loop level
            // where exactly one component varies:
            //
            //     inner = &[fixed + induction]
            //       or: inner = fixed; inner += induction
            //     value = [base + inner]
            //   ->
            //     rooted = &[base + fixed]   // current loop preheader
            //     value  = [rooted + induction]
            //
            // x86 cannot encode the first form without the per-iteration LEA.
            // Doing this here, rather than in the instruction combiner, is
            // essential for nested loops: only this loop's definition set can
            // distinguish an outer induction value from the inner induction.
            //
            // A comparison of two indexed bytes reads its second operand
            // between the sum and the compare that consumes it. That one read
            // may sit there: it redefines neither part of the sum, so the
            // compare still sees the induction and the fixed part it was made of.
            for (const uint32_t i : bodyIndices)
            {
                const MicroInstrRef ref  = instrRefs[i];
                const MicroInstr*   inst = storage.ptr(ref);
                if (!inst || inst->op == MicroInstrOpcode::LoadAddrAmcRegMem)
                    continue;

                MicroPassHelpers::AmcLayout outerLayout;
                if (!MicroPassHelpers::amcLayoutFor(outerLayout, inst->op))
                    continue;
                const MicroInstrOperand* instOps = inst->ops(operands);
                if (!instOps || instOps[outerLayout.mulIdx].valueU64 != 1)
                    continue;

                const MicroReg nestedReg = instOps[outerLayout.indexIdx].reg;
                const MicroReg outerBase = instOps[outerLayout.baseIdx].reg;
                if (!nestedReg.isVirtualInt() || !outerBase.isVirtualInt() || defsInLoop.contains(outerBase))
                    continue;

                const auto definition = definitions.find(nestedReg);
                if (definition == definitions.end() || definition->second.lastSlot >= i)
                    continue;
                const uint32_t    lastSlot = definition->second.lastSlot;
                const MicroInstr* nested   = storage.ptr(instrRefs[lastSlot]);
                if (!nested)
                    continue;
                const MicroInstrOperand* nestedOps  = nested->ops(operands);
                MicroReg                 innerBase  = MicroReg::invalid();
                MicroReg                 innerIndex = MicroReg::invalid();
                int64_t                  innerAdd   = 0;
                bool                     copyAddSum = false;
                if (nested->op == MicroInstrOpcode::LoadAddrAmcRegMem && definition->second.count == 1)
                {
                    if (!nestedOps || nestedOps[0].reg != nestedReg || nestedOps[3].opBits != MicroOpBits::B64 ||
                        nestedOps[4].opBits != MicroOpBits::B64 || nestedOps[5].valueU64 != 1)
                        continue;
                    innerBase  = nestedOps[1].reg;
                    innerIndex = nestedOps[2].reg;
                    innerAdd   = static_cast<int64_t>(nestedOps[6].valueU64);
                }
                else if (nested->op == MicroInstrOpcode::OpBinaryRegReg && definition->second.count == 2 && lastSlot > 0 &&
                         inBody[lastSlot - 1] && nestedOps && nestedOps[0].reg == nestedReg &&
                         nestedOps[1].reg != nestedReg && nestedOps[2].opBits == MicroOpBits::B64 &&
                         nestedOps[3].microOp == MicroOp::Add &&
                         MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, instrRefs[lastSlot], context.builder))
                {
                    const MicroInstr*        copy    = storage.ptr(instrRefs[lastSlot - 1]);
                    const MicroInstrOperand* copyOps = copy ? copy->ops(operands) : nullptr;
                    if (!copy || copy->op != MicroInstrOpcode::LoadRegReg || !copyOps ||
                        copyOps[0].reg != nestedReg || copyOps[1].reg == nestedReg || copyOps[2].opBits != MicroOpBits::B64)
                        continue;
                    innerBase  = copyOps[1].reg;
                    innerIndex = nestedOps[1].reg;
                    copyAddSum = true;
                }
                else
                    continue;

                const bool baseVaries  = defsInLoop.contains(innerBase);
                const bool indexVaries = defsInLoop.contains(innerIndex);
                if (baseVaries == indexVaries)
                    continue;

                // Between the sum and its reader, only the read of the value the
                // reader compares against.
                if (copyAddSum && lastSlot + 1 != i)
                {
                    const MicroInstr* gap = lastSlot + 2 == i && inBody[lastSlot + 1] ? storage.ptr(instrRefs[lastSlot + 1]) : nullptr;
                    if (!gap || !opcodeReadsMemory(gap->op) || (inst->op != MicroInstrOpcode::CmpAmcReg && inst->op != MicroInstrOpcode::CmpRegAmc))
                        continue;
                    const MicroInstrUseDef& gapUseDef = useDefs[lastSlot + 1];
                    if (gapUseDef.defs.size() != 1 || gapUseDef.defs[0] == innerBase || gapUseDef.defs[0] == innerIndex ||
                        std::ranges::find(useDefs[i].uses, gapUseDef.defs[0]) == useDefs[i].uses.end())
                        continue;
                }

                const MicroReg induction = baseVaries ? innerBase : innerIndex;
                const MicroReg fixed     = baseVaries ? innerIndex : innerBase;
                if (!fixed.isVirtualInt())
                    continue;

                // A constant offset belongs in the displacement, which costs no
                // register: rooting it would keep one alive across the loop.
                if (const auto fixedDef = definitions.find(fixed); fixedDef != definitions.end() && fixedDef->second.count == 1)
                {
                    const MicroInstr* fixedInst = storage.ptr(instrRefs[fixedDef->second.lastSlot]);
                    if (fixedInst && (fixedInst->op == MicroInstrOpcode::LoadRegImm || fixedInst->op == MicroInstrOpcode::LoadRegPtrImm))
                        continue;
                }

                const int64_t add = static_cast<int64_t>(instOps[outerLayout.addIdx].valueU64) + innerAdd;
                if (add != static_cast<int64_t>(static_cast<int32_t>(add)))
                    continue;

                const uint32_t                    nextReg     = MicroPassHelpers::computeNextVirtualIntRegIndex(context);
                const MicroReg                    rooted      = MicroReg::virtualIntReg(nextReg);
                const MicroInstrOpcode            rewrittenOp = inst->op;
                SmallVector<MicroInstrOperand, 8> rewritten;
                rewritten.append(instOps, inst->numOperands);
                rewritten[outerLayout.baseIdx].reg     = rooted;
                rewritten[outerLayout.indexIdx].reg    = induction;
                rewritten[outerLayout.addIdx].valueU64 = 0;

                MicroInstrOperand rootedOps[8] = {};
                rootedOps[0].reg               = rooted;
                rootedOps[1].reg               = outerBase;
                rootedOps[2].reg               = fixed;
                rootedOps[3].opBits            = MicroOpBits::B64;
                rootedOps[4].opBits            = MicroOpBits::B64;
                rootedOps[5].valueU64          = 1;
                rootedOps[6].valueU64          = static_cast<uint64_t>(add);
                storage.insertDerivedBefore(operands, headerRef, MicroInstrOpcode::LoadAddrAmcRegMem, rootedOps);
                storage.insertDerivedBefore(operands, ref, rewrittenOp, {rewritten.data(), rewritten.size()});
                storage.erase(ref);

                if (context.ssaState)
                    context.ssaState->invalidate();
                context.builder->invalidateControlFlowGraph();
                return true;
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
            thread_local std::unordered_map<MicroReg, RegWeb> websByReg;
            websByReg.clear();
            slotDefReg.resize(n);
            slotIsFullDef.resize(n);
            slotIsCompute.resize(n);
            // Only body slots are read below; the other entries can keep their
            // values from an earlier loop or function.
            for (const uint32_t i : bodyIndices)
            {
                slotDefReg[i]    = MicroReg::invalid();
                slotIsFullDef[i] = 0;
                slotIsCompute[i] = 0;
                if (i == header)
                    continue;
                const MicroInstr*       inst   = storage.ptr(instrRefs[i]);
                const MicroInstrUseDef* useDef = &useDefs[i];
                if (!inst)
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
                const bool selfUse = std::ranges::find(useDef->uses, destReg) != useDef->uses.end();

                const bool fullDefEligible = isEligibleOpcode(inst->op);
                const bool eligible        = fullDefEligible || isEligiblePairedComputeOpcode(inst->op);
                if (!eligible)
                    web.chainOk = false;
                else if (selfUse)
                    slotIsCompute[i] = 1;
                else if (fullDefEligible)
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

            const auto eligibleWeb = [&](const MicroReg reg) -> const RegWeb* {
                const auto it = websByReg.find(reg);
                if (it == websByReg.end() || !it->second.chainOk)
                    return nullptr;
                if (it->second.defSlots.size() > K_MAX_WEB_DEFS)
                    return nullptr;
                const auto dc = definitions.find(reg);
                return dc != definitions.end() && dc->second.count == it->second.defSlots.size() ? &it->second : nullptr;
            };

            std::unordered_set<uint32_t>              hoistSet;
            thread_local std::unordered_set<MicroReg> banned;
            banned.clear();

            // The value a use reads at slot i is hoisted when every earlier def
            // of its register is: emission in listing order then reproduces it
            // in the preheader.
            const auto acceptedPrefix = [&](const RegWeb& web, const uint32_t slot) {
                for (const uint32_t defSlot : web.defSlots)
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
                    for (const uint32_t i : bodyIndices)
                    {
                        if (i == header || hoistSet.contains(i))
                            continue;

                        const MicroInstrRef ref = instrRefs[i];
                        if (claimed.contains(ref.get()))
                            continue;

                        const MicroInstr*       inst   = storage.ptr(ref);
                        const MicroInstrUseDef* useDef = &useDefs[i];
                        if (!inst)
                            continue;

                        const MicroReg destReg = slotDefReg[i];
                        if (!destReg.isValid() || banned.contains(destReg))
                            continue;
                        const RegWeb* destWeb = eligibleWeb(destReg);
                        if (!destWeb)
                            continue;
                        if (!slotIsFullDef[i] && !slotIsCompute[i])
                            continue;

                        // A relocation names the instruction it patches. The
                        // clone of a relocated load or address materialization
                        // takes the relocation over when it is emitted; any
                        // other relocated instruction stays where it is.
                        const auto relocationIt = firstRelocation.find(ref.get());
                        if (relocationIt != firstRelocation.end() && !isRelocatableHoist(inst->op))
                            continue;

                        if (slotIsCompute[i])
                        {
                            if (!acceptedPrefix(*destWeb, i))
                                continue;
                        }
                        // Both a full definition such as an integer clear and
                        // a continuation may write flags. Floating arithmetic
                        // and XMM clears preserve them despite sharing opcodes.
                        if (MicroInstr::info(inst->op).flags.has(MicroInstrFlagsE::DefinesCpuFlags) &&
                            MicroPassHelpers::instructionActuallyDefinesCpuFlags(*inst, inst->ops(operands)) &&
                            (!preheaderFlagsDead || !MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, ref, context.builder)))
                            continue;

                        // A multi-def web is only the value sequence its listing
                        // shows when every member runs on every iteration: a
                        // member inside one arm of a branch would make the
                        // register's final value path-dependent, which one
                        // preheader execution cannot reproduce. Every member
                        // must dominate every back-edge tail.
                        if (destWeb->defSlots.size() > 1)
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
                            const RegWeb* useWeb = banned.contains(use) ? nullptr : eligibleWeb(use);
                            if (!useWeb || !acceptedPrefix(*useWeb, i))
                            {
                                allInvariant = false;
                                break;
                            }
                        }
                        if (!allInvariant)
                            continue;

                        if (opcodeReadsMemory(inst->op))
                        {
                            // The vector conversion constants live in the read-only pool.
                            // Neither calls nor pointer stores can change their bytes.
                            const MicroInstrOperand* loadOps = inst->ops(operands);
                            if (!loadOps)
                                continue;
                            const bool constantPoolVector = inst->op == MicroInstrOpcode::LoadRegMem &&
                                                            loadOps[1].reg.isInstructionPointer() &&
                                                            loadOps[2].opBits == MicroOpBits::B128 &&
                                                            relocationIt != firstRelocation.end() &&
                                                            relocations[relocationIt->second].kind == MicroRelocation::Kind::ConstantAddress;

                            const bool immutableLoad = loadOps[1].reg.isVirtualInt() && immutableBases.contains(loadOps[1].reg);

                            // A private global read directly: no pointer store reaches it, only a
                            // direct store to the same global in this loop. Only an innermost loop
                            // keeps it: around a nested loop the value must outlive every inner
                            // value, and once the allocator spills it, the hoist trades a load of the
                            // global for a load of the stack slot plus the spill's own traffic.
                            bool privateGlobalLoad = false;
                            if (inst->op == MicroInstrOpcode::LoadRegMem && loadOps[1].reg.isInstructionPointer() && relocationIt != firstRelocation.end())
                            {
                                const MicroRelocation& relocation = relocations[relocationIt->second];
                                const uint64_t         key        = relocationKey(relocation);
                                privateGlobalLoad                 = relocation.privateGlobal && !loopHasNestedLoop && !materializedPrivateGlobals.contains(key);
                                if (privateGlobalLoad && directStoreTargets.contains(key))
                                    continue;
                            }

                            // A call may write an ordinary loaded location.
                            if (loopHasCall && !constantPoolVector && !immutableLoad)
                                continue;

                            // Indexed values and pointer-sized fields of an
                            // invariant structure can also cross a read-only
                            // call when the alias checks below exclude stores.
                            if (loopHasReadOnlyCall && !constantPoolVector && !immutableLoad)
                            {
                                bool directGlobal = false;
                                if (inst->op == MicroInstrOpcode::LoadRegMem && loadOps[1].reg.isInstructionPointer() &&
                                    loadOps[2].opBits == MicroOpBits::B64)
                                {
                                    if (relocationIt != firstRelocation.end())
                                    {
                                        const auto kind = relocations[relocationIt->second].kind;
                                        directGlobal    = kind == MicroRelocation::Kind::GlobalInitAddress ||
                                                       kind == MicroRelocation::Kind::GlobalZeroAddress;
                                    }
                                }
                                const bool structureField = inst->op == MicroInstrOpcode::LoadRegMem &&
                                                            loadOps[1].reg.isVirtualInt() && loadOps[2].opBits == MicroOpBits::B64 &&
                                                            dereferenceBasesInLoop.contains(loadOps[0].reg);
                                if (!directGlobal && !structureField && inst->op != MicroInstrOpcode::LoadAmcRegMem)
                                    continue;
                            }

                            const MicroReg base        = firstUseReg(*useDef);
                            const bool     baseIsFrame = base.isValid() && frame.isFrame(base, stackPointer);
                            if (immutableLoad)
                            {
                                // Nothing the loop does reaches the parameter's storage.
                            }
                            else if (baseIsFrame)
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
                                // address and no frame address escapes the function - or
                                // the address is instruction-pointer-relative, which
                                // names a global or a constant and never the frame.
                                if (loopHasPointerStore && !constantPoolVector && !privateGlobalLoad)
                                    continue;
                                const bool baseIsConstantAddress = !base.isValid() || base.isInstructionPointer();
                                if (loopHasFrameStore && !baseIsConstantAddress)
                                {
                                    const auto bc            = base.isValid() ? definitions.find(base) : definitions.end();
                                    const bool baseSingleDef = bc != definitions.end() && bc->second.count == 1;
                                    if (!frame.framePrivate || !baseSingleDef)
                                        continue;
                                }
                            }

                            // Speculation safety: the load must already run on every
                            // iteration (dominate every back-edge tail). A constant of the
                            // read-only pool is the exception: reading it can neither fault
                            // nor observe a store, so the preheader may read it for an arm
                            // that only some iterations take, as LLVM hoists a constant-pool
                            // load out of a conditional block.
                            bool dominatesAllTails = true;
                            for (const uint32_t t : loop->tails)
                            {
                                if (!dom.dominates(i, t))
                                {
                                    dominatesAllTails = false;
                                    break;
                                }
                            }
                            // A private global is equally safe to read early: its storage always
                            // exists, and no store the arm skips could have changed it.
                            if (!dominatesAllTails && !constantPoolVector && !privateGlobalLoad)
                                continue;
                        }

                        hoistSet.insert(i);
                        progress = true;
                    }
                }
            };

            // Loop exits, for the web-consistency rule below: a slot inside the
            // body with a successor outside it. Only multi-def webs need them.
            SmallVector<uint32_t> exitSlots;
            bool                  collectedExitSlots = false;

            // Accept optimistically, filter for profit, then enforce web
            // integrity on what remains: a register with any hoisted def needs
            // all of them hoisted (its in-loop value otherwise restarts from
            // the preheader copy every iteration), and a non-hoisted reader may
            // only see the FINAL value - reads before the first def see the
            // carried final of the previous iteration, which hoisting
            // preserves; reads between defs see an intermediate, which it does
            // not. A violating register is banned and the whole pipeline reruns
            // without it, cascading until stable.
            thread_local std::unordered_map<MicroReg, uint32_t> inLoopUse;
            std::unordered_set<MicroReg>                        nestedLoopUses;
            inLoopUse.clear();
            bool countedLoopUses = false;
            for (;;)
            {
                runAcceptance();

                // Profitability filter (do-no-harm). Hoisting a value keeps it
                // live across the whole loop, costing a register. That only
                // pays off for memory reads (a removed per-iteration load) or
                // values recomputed by several in-loop uses. A standalone
                // single-use address/copy would just add register pressure, so
                // keep only memory reads and multiply used values, plus the
                // hoisted webs that feed them. A zeroing clear in a loop that
                // calls does not pay by itself, however many readers it has:
                // the register renamer executes it for free, and hoisted it
                // must survive every call, which takes a callee-saved register
                // the prologue spills - one per clear once several pile up. It
                // then moves only with a kept value that reads it.
                if (!hoistSet.empty())
                {
                    // Acceptance changes only the hoist plan, not the IR or its uses.
                    if (!countedLoopUses)
                    {
                        for (const uint32_t i : bodyIndices)
                        {
                            for (const MicroReg use : useDefs[i].uses)
                            {
                                ++inLoopUse[use];
                                if (innermostLoopSizes[i] < loop->bodySize)
                                    nestedLoopUses.insert(use);
                            }
                        }
                        countedLoopUses = true;
                    }

                    std::unordered_set<uint32_t> keep;
                    std::vector<uint32_t>        worklist;
                    for (const uint32_t i : hoistSet)
                    {
                        const MicroInstr*       inst = storage.ptr(instrRefs[i]);
                        const MicroInstrUseDef* ud   = &useDefs[i];
                        if (!inst || ud->defs.size() != 1)
                            continue;
                        const auto               uc           = inLoopUse.find(ud->defs[0]);
                        const bool               multiplyUsed = uc != inLoopUse.end() && uc->second >= 2;
                        const MicroInstrOperand* instOps      = inst->ops(operands);

                        if (inst->op == MicroInstrOpcode::ClearReg && loopHasCall)
                            continue;

                        // A value computed only on some iterations, inside one
                        // arm of a branch, saves nothing on the others: however
                        // many readers that arm has, hoisting it trades at most
                        // one instruction on the arm for a register held across
                        // every iteration, the ones that never take the arm
                        // included. A refill or an error path computing a field
                        // address is the typical case. Such a value moves only
                        // when it is costly to rebuild. (A memory read other than a
                        // read-only pool constant already has to run on every
                        // iteration to be accepted.)
                        bool runsEveryIteration = true;
                        for (const uint32_t t : loop->tails)
                        {
                            if (!dom.dominates(i, t))
                            {
                                runsEveryIteration = false;
                                break;
                            }
                        }

                        // One textual reader in a nested loop can consume this
                        // address repeatedly. Moving an address computed on every
                        // iteration keeps the inner loop's live values unchanged;
                        // calls still make the longer lifetime too costly.
                        const bool nestedAddress = !loopHasCall && !loopHasReadOnlyCall &&
                                                   (inst->op == MicroInstrOpcode::LoadAddrRegMem || inst->op == MicroInstrOpcode::LoadAddrAmcRegMem) &&
                                                   nestedLoopUses.contains(ud->defs[0]);
                        if (opcodeReadsMemory(inst->op) || ((multiplyUsed || nestedAddress) && runsEveryIteration) || isCostlyMaterialization(*inst, instOps))
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
                        const MicroInstrUseDef* ud = &useDefs[i];

                        const auto pullWeb = [&](const MicroReg reg) {
                            const auto webIt = websByReg.find(reg);
                            if (webIt == websByReg.end())
                                return;
                            for (const uint32_t defSlot : webIt->second.defSlots)
                            {
                                if (hoistSet.contains(defSlot) && keep.insert(defSlot).second)
                                    worklist.push_back(defSlot);
                            }
                        };
                        if (ud->defs.size() == 1)
                            pullWeb(ud->defs[0]);
                        for (const MicroReg use : ud->uses)
                            pullWeb(use);
                    }

                    hoistSet = std::move(keep);
                }

                SmallVector<MicroReg>                  violations;
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
                    for (const uint32_t s : bodyIndices)
                    {
                        if (s > lastDef || violated)
                            break;
                        if (hoistSet.contains(s))
                            continue;
                        const MicroInstrUseDef* ud = &useDefs[s];
                        violated                   = std::ranges::find(ud->uses, reg) != ud->uses.end();
                    }

                    // An exit taken mid-web leaves the register holding an
                    // intermediate of the aborted iteration, which the hoisted
                    // final cannot reproduce. Every exit must either dominate
                    // the first def (the register then held the previous
                    // iteration's final, which hoisting preserves) or be
                    // dominated by the last def (the final of this iteration).
                    if (!violated && !collectedExitSlots)
                    {
                        for (const uint32_t i : bodyIndices)
                        {
                            for (const uint32_t succ : cfg.successors(i))
                            {
                                if (succ < n && !inBody[succ])
                                {
                                    exitSlots.push_back(i);
                                    break;
                                }
                            }
                        }
                        collectedExitSlots = true;
                    }
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
                        violated                        = spanInst->op == MicroInstrOpcode::Label ||
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
        {
            for (const Clone& clone : plan.clones)
            {
                const MicroInstrRef hoistedRef   = storage.insertDerivedBefore(operands, plan.headerRef, clone.op, clone.ops);
                const auto          relocationIt = firstRelocation.find(clone.original.get());
                if (relocationIt == firstRelocation.end())
                    continue;
                // Cloning only changes MicroStorage; the relocation array and
                // its index chains remain fixed until all retargeting is done.
                for (size_t index = relocationIt->second; index != relocationEnd; index = nextRelocation[index])
                    relocations[index].instructionRef = hoistedRef;
            }
        }
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
    // skip the dominator-tree construction and map allocations this
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
