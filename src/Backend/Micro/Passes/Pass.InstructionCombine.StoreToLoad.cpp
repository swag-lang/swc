#include "pch.h"
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
        };

        using Cache = SmallVector<CacheEntry, 8>;

        void dropEntriesReferencing(Cache& cache, MicroReg reg)
        {
            for (uint32_t i = 0; i < cache.size();)
            {
                if (cache[i].base == reg || cache[i].src == reg)
                    cache.erase(cache.begin() + i);
                else
                    ++i;
            }
        }

        // Byte-range overlap test. Only meaningful when the two accesses
        // share the same base register — different bases are handled by
        // the caller as "may alias" since we have no pointer-provenance
        // information.
        bool rangesOverlap(uint64_t offA, MicroOpBits bitsA, uint64_t offB, MicroOpBits bitsB)
        {
            const uint64_t endA = offA + getNumBytes(bitsA);
            const uint64_t endB = offB + getNumBytes(bitsB);
            return !(endA <= offB || endB <= offA);
        }

        // A newly-emitted store kills cache entries that might refer to the
        // same bytes. Same-base + non-overlapping ranges are proven disjoint
        // and survive; everything else we can't disprove gets evicted.
        void invalidateAliasedEntries(Cache& cache, MicroReg base, uint64_t off, MicroOpBits bits)
        {
            for (uint32_t i = 0; i < cache.size();)
            {
                const CacheEntry& e        = cache[i];
                const bool        sameBase = e.base == base;
                const bool        disjoint = sameBase && !rangesOverlap(e.off, e.bits, off, bits);
                if (!sameBase || !disjoint)
                    cache.erase(cache.begin() + i);
                else
                    ++i;
            }
        }

        bool forwardLoad(Context& ctx, const Cache& cache, MicroInstrRef loadRef, const MicroInstrOperand* ops)
        {
            const MicroReg    dst  = ops[0].reg;
            const MicroReg    base = ops[1].reg;
            const MicroOpBits bits = ops[2].opBits;
            const uint64_t    off  = ops[3].valueU64;

            for (const CacheEntry& e : cache)
            {
                if (e.base == base && e.off == off && e.bits == bits && e.src.isValid() && e.src != dst)
                {
                    if (!ctx.claimAll({loadRef}))
                        return false;
                    MicroInstrOperand moveOps[3];
                    moveOps[0].reg    = dst;
                    moveOps[1].reg    = e.src;
                    moveOps[2].opBits = bits;
                    ctx.emitRewrite(loadRef, MicroInstrOpcode::LoadRegReg, moveOps);
                    return true;
                }
            }
            return false;
        }
    }

    void runStoreToLoadForwarding(Context& ctx)
    {
        if (!ctx.ssa)
            return;

        Cache cache;

        const auto view  = ctx.storage->view();
        const auto endIt = view.end();
        for (auto it = view.begin(); it != endIt; ++it)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(*ctx.operands);

            if (inst.op == MicroInstrOpcode::LoadRegMem && ops)
            {
                bool forwarded = false;
                if (!ctx.isClaimed(it.current))
                    forwarded = forwardLoad(ctx, cache, it.current, ops);
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
                if (!forwarded && !ctx.isClaimed(it.current) && ops[1].reg.isValid() && ops[1].reg != ops[0].reg)
                {
                    CacheEntry entry;
                    entry.base = ops[1].reg;
                    entry.src  = ops[0].reg;
                    entry.bits = ops[2].opBits;
                    entry.off  = ops[3].valueU64;
                    cache.push_back(entry);
                }
                continue;
            }

            if (inst.op == MicroInstrOpcode::LoadMemReg && ops)
            {
                const MicroReg    base = ops[0].reg;
                const MicroOpBits bits = ops[2].opBits;
                const uint64_t    off  = ops[3].valueU64;

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
}

SWC_END_NAMESPACE();
