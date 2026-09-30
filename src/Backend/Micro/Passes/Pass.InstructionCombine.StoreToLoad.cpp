#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Store-to-load forwarding: when a LoadRegMem reads the same slot a recent
// LoadMemReg just wrote, and the store's source is still live/unchanged,
// rewrite the load as a plain LoadRegReg and skip the memory round-trip.
//
// Alias model: two memory accesses are disjoint when their base registers
// are the *same* MicroReg and their byte ranges don't overlap. Different
// bases are treated as possibly-aliasing. `dropEntriesReferencing` already
// evicts cache entries whose base reg was redefined, so "same base" also
// implies "same pointer value at the point of the later access."
// Calls, branches, labels, and unclassified memory writers still flush the
// whole cache.
//
// A load into the very register the cache names is not a copy to make: the
// register already holds those bytes, and the load goes away.
//
// The same alias model removes a dead store: one that a later store to the
// same base overwrites completely, with nothing in between that may read the
// bytes it wrote.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        struct CacheEntry
        {
            MicroReg    base;
            MicroReg    src;
            MicroOpBits bits = MicroOpBits::Zero;
            uint64_t    off  = 0;
            // For RIP-relative loads the true address lives in the
            // relocation, not in (base, off): entries carry the relocation's
            // identity instead, and only equal identities match.
            const MicroRelocation* relocation = nullptr;
            // The register was filled by a load of this slot, and so holds
            // exactly what another load of it would produce.
            bool fromLoad = false;
        };

        enum class Forward : uint8_t
        {
            None,
            Copied,
            Erased,
        };

        using Cache = SmallVector<CacheEntry, 8>;

        void dropEntriesReferencing(Cache& cache, MicroReg reg)
        {
            const auto end = std::remove_if(cache.begin(), cache.end(), [reg](const CacheEntry& entry) {
                return entry.base == reg || entry.src == reg;
            });
            cache.resize(static_cast<size_t>(end - cache.begin()));
        }

        // Byte-range overlap test. Only meaningful when the two accesses
        // share the same base register — different bases are handled by
        // the caller as "may alias" since we have no pointer-provenance
        // information.
        // A displacement is signed. An access that ends at the base, such as
        // the eight bytes at `[b - 8]`, would wrap its unsigned end to zero and
        // read as disjoint from everything, itself included.
        bool rangesOverlap(uint64_t offA, MicroOpBits bitsA, uint64_t offB, MicroOpBits bitsB)
        {
            const int64_t startA = static_cast<int64_t>(offA);
            const int64_t startB = static_cast<int64_t>(offB);
            const int64_t endA   = startA + static_cast<int64_t>(getNumBytes(bitsA));
            const int64_t endB   = startB + static_cast<int64_t>(getNumBytes(bitsB));
            return !(endA <= startB || endB <= startA);
        }

        // Whether the first access holds every byte of the second.
        bool rangeCovers(uint64_t offA, MicroOpBits bitsA, uint64_t offB, MicroOpBits bitsB)
        {
            const int64_t startA = static_cast<int64_t>(offA);
            const int64_t startB = static_cast<int64_t>(offB);
            return startA <= startB && startB + static_cast<int64_t>(getNumBytes(bitsB)) <= startA + static_cast<int64_t>(getNumBytes(bitsA));
        }

        // A newly-emitted store kills cache entries that might refer to the
        // same bytes. Same-base + non-overlapping ranges are proven disjoint
        // and survive; everything else we can't disprove gets evicted.
        void invalidateAliasedEntries(Cache& cache, MicroReg base, uint64_t off, MicroOpBits bits)
        {
            const auto end = std::remove_if(cache.begin(), cache.end(), [base, off, bits](const CacheEntry& entry) {
                const bool sameBase = entry.base == base;
                const bool disjoint = sameBase && !rangesOverlap(entry.off, entry.bits, off, bits);
                return !sameBase || !disjoint;
            });
            cache.resize(static_cast<size_t>(end - cache.begin()));
        }

        Forward forwardLoad(Context& ctx, const Cache& cache, MicroInstrRef loadRef, const MicroInstrOperand* ops, const MicroRelocation* relocation = nullptr)
        {
            const MicroReg    dst  = ops[0].reg;
            const MicroReg    base = ops[1].reg;
            const MicroOpBits bits = ops[2].opBits;
            const uint64_t    off  = ops[3].valueU64;

            for (const CacheEntry& e : cache)
            {
                if (e.base != base || e.off != off || e.bits != bits || !e.src.isValid())
                    continue;
                const bool sameTarget = e.relocation && relocation ? e.relocation->hasSameTarget(*relocation) : e.relocation == relocation;
                if (!sameTarget)
                    continue;

                // A 32-bit integer load also clears the upper half of its
                // register. A register the slot was only stored from may
                // carry other bits there, so that reload stays.
                const bool sameRegister = e.src == dst;
                if (sameRegister && !e.fromLoad && dst.isAnyInt() && bits == MicroOpBits::B32)
                    return Forward::None;
                if (!ctx.claimAll({loadRef}, relocation != nullptr))
                    return Forward::None;
                // A forwarded RIP-relative load leaves its relocation
                // behind on what becomes a plain register move; detach it
                // now so the emitter never tries to bind it.
                if (relocation && ctx.builder)
                    ctx.builder->invalidateRelocationForInstruction(loadRef);
                if (sameRegister)
                {
                    ctx.emitErase(loadRef);
                    return Forward::Erased;
                }

                MicroInstrOperand moveOps[3];
                moveOps[0].reg    = dst;
                moveOps[1].reg    = e.src;
                moveOps[2].opBits = bits;
                ctx.emitRewrite(loadRef, MicroInstrOpcode::LoadRegReg, moveOps);
                return Forward::Copied;
            }
            return Forward::None;
        }

        // Opcodes that neither read nor write memory, so a pending store
        // stays unread across them. Anything absent from the list ends the
        // search: an indexed or vector read, a read-modify-write, a call.
        bool leavesMemoryAlone(const MicroInstrOpcode op)
        {
            switch (op)
            {
                case MicroInstrOpcode::Nop:
                case MicroInstrOpcode::LoadRegReg:
                case MicroInstrOpcode::LoadRegImm:
                case MicroInstrOpcode::LoadRegPtrImm:
                case MicroInstrOpcode::LoadRegPtrReloc:
                case MicroInstrOpcode::LoadSignedExtRegReg:
                case MicroInstrOpcode::LoadZeroExtRegReg:
                case MicroInstrOpcode::LoadAddrRegMem:
                case MicroInstrOpcode::LoadAddrAmcRegMem:
                case MicroInstrOpcode::TestRegReg:
                case MicroInstrOpcode::TestRegImm:
                case MicroInstrOpcode::CmpRegReg:
                case MicroInstrOpcode::CmpRegImm:
                case MicroInstrOpcode::SetCondReg:
                case MicroInstrOpcode::ClearReg:
                case MicroInstrOpcode::OpUnaryReg:
                case MicroInstrOpcode::LoadCondRegReg:
                case MicroInstrOpcode::OpBinaryRegReg:
                case MicroInstrOpcode::OpBinaryRegRegReg:
                case MicroInstrOpcode::OpBinaryRegImm:
                case MicroInstrOpcode::OpBinaryRegRegImm:
                case MicroInstrOpcode::OpTernaryRegRegReg:
                case MicroInstrOpcode::OpTernaryRegRegRegImm:
                case MicroInstrOpcode::VecShuffleRegRegImm:
                case MicroInstrOpcode::VecUnaryRegReg:
                    return true;
                default:
                    return false;
            }
        }
    }

    void runStoreToLoadForwarding(Context& ctx)
    {
        if (!ctx.ssa)
            return;

        // Relocation identity per instruction, so RIP-relative loads of the
        // same target can forward to each other: their (base, off) pair is
        // always ([ip], 0) and only the relocation tells two targets apart.
        std::unordered_map<uint32_t, const MicroRelocation*> relocationByRef;
        bool                                                 relocationsReady       = false;
        const auto                                           ensureRelocationsReady = [&]() {
            if (relocationsReady)
                return;
            if (ctx.builder)
            {
                for (const MicroRelocation& reloc : ctx.builder->codeRelocations())
                {
                    if (reloc.instructionRef.isValid())
                        relocationByRef[reloc.instructionRef.get()] = &reloc;
                }
            }
            relocationsReady = true;
        };

        Cache cache;

        const auto view  = ctx.storage->view();
        const auto endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(*ctx.operands);

            if (inst.op == MicroInstrOpcode::LoadRegMem && ops)
            {
                // A RIP-relative load participates through its relocation
                // identity; one whose relocation cannot be found stays
                // opaque (never matches, never cached).
                const MicroRelocation* relocation = nullptr;
                if (ops[1].reg.isInstructionPointer())
                {
                    // Forwarding only invalidates an existing relocation; the
                    // first RIP access sees the original snapshot.
                    ensureRelocationsReady();
                    const auto relocIt = relocationByRef.find(it.current.get());
                    if (relocIt == relocationByRef.end() || relocIt->second->form != MicroRelocation::Form::Relative32)
                    {
                        dropEntriesReferencing(cache, ops[0].reg);
                        continue;
                    }
                    relocation = relocIt->second;
                }

                const bool claimed = ctx.isClaimed(it.current);
                Forward    forward = Forward::None;
                if (!claimed)
                    forward = forwardLoad(ctx, cache, it.current, ops, relocation);
                // An erased reload leaves its register, and every entry that
                // names it, exactly as they were.
                if (forward == Forward::Erased)
                    continue;
                const bool forwarded = forward == Forward::Copied;
                // The load redefines its destination register; any cache entry
                // whose `src` refers to it is now stale and must be dropped
                // before a later load could reach for it.
                dropEntriesReferencing(cache, ops[0].reg);

                // Load-to-load forwarding: record this load's result so a later
                // load of the same slot reuses the register instead of re-reading
                // memory. Safe under the same alias model used for stores — entries
                // are evicted on aliasing writes, calls, control flow, and base/dst
                // redefinition. Skip when base and destination are the same register
                // (e.g. `r = [r + off]`), since the base no longer points at the slot.
                // A claimed load will be erased or rewritten by another pattern
                // (e.g. folded into a following ALU op), so its destination may hold
                // no live value; caching it would forward a later load to a dead reg.
                // A failed forward leaves claims untouched; a successful one
                // is excluded here regardless of the claim it just added.
                if (!forwarded && !claimed && ops[1].reg.isValid() && ops[1].reg != ops[0].reg)
                {
                    CacheEntry entry;
                    entry.base       = ops[1].reg;
                    entry.src        = ops[0].reg;
                    entry.bits       = ops[2].opBits;
                    entry.off        = ops[3].valueU64;
                    entry.relocation = relocation;
                    entry.fromLoad   = true;
                    cache.push_back(entry);
                }
                continue;
            }

            if (inst.op == MicroInstrOpcode::LoadMemReg && ops)
            {
                const MicroReg    base = ops[0].reg;
                const MicroOpBits bits = ops[2].opBits;
                const uint64_t    off  = ops[3].valueU64;

                // A RIP-relative store may alias earlier cached locations, so
                // flush them. Its own relocated global target is exact and can
                // answer a following load until another writer or barrier.
                if (base.isInstructionPointer())
                {
                    cache.clear();
                    if (ctx.isClaimed(it.current))
                        continue;
                    ensureRelocationsReady();
                    const auto relocIt = relocationByRef.find(it.current.get());
                    if (relocIt == relocationByRef.end() || relocIt->second->form != MicroRelocation::Form::Relative32)
                        continue;
                    const MicroRelocation::Kind kind = relocIt->second->kind;
                    if (kind != MicroRelocation::Kind::GlobalInitAddress && kind != MicroRelocation::Kind::GlobalZeroAddress)
                        continue;
                    cache.push_back({.base = base, .src = ops[1].reg, .bits = bits, .off = off, .relocation = relocIt->second});
                    continue;
                }

                // Only evict entries that could alias this store's byte range.
                invalidateAliasedEntries(cache, base, off, bits);

                // A claimed store will be erased by another pattern; caching it
                // would let a later load forward to a register with no live def.
                if (ctx.isClaimed(it.current))
                    continue;

                CacheEntry entry;
                entry.base = base;
                entry.src  = ops[1].reg;
                entry.bits = bits;
                entry.off  = off;
                cache.push_back(entry);
                continue;
            }

            if (cache.empty())
                continue;

            if (isControlOrCall(inst) || writesMemory(inst))
            {
                cache.clear();
                continue;
            }

            const auto* useDef = ctx.ssa->instrUseDef(it.current);
            if (useDef)
            {
                for (const MicroReg def : useDef->defs)
                    dropEntriesReferencing(cache, def);
            }
        }
    }

    void runDeadStoreElimination(Context& ctx)
    {
        if (!ctx.ssa)
            return;

        struct PendingStore
        {
            MicroInstrRef ref;
            MicroReg      base;
            uint64_t      off  = 0;
            MicroOpBits   bits = MicroOpBits::Zero;
        };
        SmallVector<PendingStore, 8> pending;
        const auto                   dropWhere = [&](const auto& predicate) {
            const auto end = std::remove_if(pending.begin(), pending.end(), predicate);
            pending.resize(static_cast<size_t>(end - pending.begin()));
        };

        const auto view  = ctx.storage->view();
        const auto endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(*ctx.operands);

            // A register and an immediate store alike: they differ only in
            // where the width and the offset sit.
            if ((inst.op == MicroInstrOpcode::LoadMemReg || inst.op == MicroInstrOpcode::LoadMemImm) && ops)
            {
                const bool        fromReg = inst.op == MicroInstrOpcode::LoadMemReg;
                const MicroReg    base    = ops[0].reg;
                const MicroOpBits bits    = ops[fromReg ? 2 : 1].opBits;
                const uint64_t    off     = ops[fromReg ? 3 : 2].valueU64;
                // A store another rule of this sweep has taken may become
                // anything, a read-modify-write included: it proves nothing.
                if (!base.isVirtualInt() || ctx.isClaimed(it.current) || ctx.isRelocated(it.current))
                {
                    pending.clear();
                    continue;
                }

                // Whatever this store covers whole was written for nothing.
                // A store through another base reads no memory, so the
                // stores still pending stay pending behind it.
                dropWhere([&](const PendingStore& earlier) {
                    if (earlier.base != base || !rangeCovers(off, bits, earlier.off, earlier.bits))
                        return false;
                    if (ctx.claimAll({earlier.ref}))
                        ctx.emitErase(earlier.ref);
                    return true;
                });

                pending.push_back({.ref = it.current, .base = base, .off = off, .bits = bits});
                continue;
            }

            if (pending.empty())
                continue;

            if (inst.op == MicroInstrOpcode::LoadRegMem && ops)
            {
                // A read keeps only the stores it provably misses: the same
                // base, and bytes that do not overlap. It also redefines its
                // destination, which may be the base of a pending store.
                const MicroReg    dst  = ops[0].reg;
                const MicroReg    base = ops[1].reg;
                const MicroOpBits bits = ops[2].opBits;
                const uint64_t    off  = ops[3].valueU64;
                dropWhere([&](const PendingStore& earlier) {
                    return earlier.base == dst || earlier.base != base || rangesOverlap(earlier.off, earlier.bits, off, bits);
                });
                continue;
            }

            if (!leavesMemoryAlone(inst.op))
            {
                pending.clear();
                continue;
            }

            // A redefined base no longer names the address the store wrote.
            if (const auto* useDef = ctx.ssa->instrUseDef(it.current))
            {
                for (const MicroReg def : useDef->defs)
                    dropWhere([&](const PendingStore& earlier) { return earlier.base == def; });
            }
        }
    }

    // A store of the value just loaded from the same place, at the same width:
    //
    //     LoadRegMem  v, [b + o], w
    //     ...                           (no memory write, call or control flow)
    //     LoadMemReg  [b + o], v, w  -> erased
    //
    // writes back the bytes memory already holds. The front end emits the pair
    // when a value built in a temporary is copied into the variable sharing its
    // slot; left in place, the whole-width load waits on the narrower stores
    // that built the value. Erasing the store leaves the load to dead-code
    // elimination when nothing else reads it. The base must hold the same value
    // at both ends and nothing between may write memory, so no other store can
    // have changed those bytes in between; a volatile load has its own opcode.
    bool tryEraseStoreOfLoadedValue(Context& ctx, const MicroInstrRef storeRef, const MicroInstr& storeInst)
    {
        if (ctx.isClaimed(storeRef) || ctx.isRelocated(storeRef) || !ctx.ssa)
            return false;
        const MicroInstrOperand* storeOps = storeInst.ops(*ctx.operands);
        if (!storeOps)
            return false;
        const MicroReg base  = storeOps[0].reg;
        const MicroReg value = storeOps[1].reg;
        if (!base.isVirtualInt() || !value.isVirtual() || base == value)
            return false;

        const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(value, storeRef);
        if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::LoadRegMem || ctx.isRelocated(def.instRef))
            return false;
        const MicroInstrOperand* loadOps = def.inst->ops(*ctx.operands);
        if (!loadOps || loadOps[0].reg != value || loadOps[1].reg != base || loadOps[2].opBits != storeOps[2].opBits ||
            loadOps[3].valueU64 != storeOps[3].valueU64)
            return false;
        const MicroSsaState::ReachingDef baseAtLoad  = ctx.ssa->reachingDef(base, def.instRef);
        const MicroSsaState::ReachingDef baseAtStore = ctx.ssa->reachingDef(base, storeRef);
        if (!baseAtLoad.valid() || !baseAtStore.valid() || baseAtLoad.valueId != baseAtStore.valueId)
            return false;

        constexpr uint32_t K_MAX_WINDOW = 32;
        MicroInstrRef      ref          = ctx.storage->findPreviousInstructionRef(storeRef);
        for (uint32_t step = 0; ref != def.instRef; ++step, ref = ctx.storage->findPreviousInstructionRef(ref))
        {
            const MicroInstr* inst = ref.isValid() ? ctx.storage->ptr(ref) : nullptr;
            if (!inst || step >= K_MAX_WINDOW || isControlOrCall(*inst) || writesMemory(*inst))
                return false;
        }

        if (!ctx.claimAll({storeRef}))
            return false;
        ctx.emitErase(storeRef);
        return true;
    }
}

SWC_END_NAMESPACE();
