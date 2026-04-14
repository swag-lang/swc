#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Store-to-load forwarding: when a LoadRegMem reads the same slot a recent
// LoadMemReg just wrote, and the store's source is still live/unchanged,
// rewrite the load as a plain LoadRegReg and skip the memory round-trip.
//
// Without alias information over spill/temp slots, we flush the cache on any
// memory-writing instruction we can't prove disjoint, on any call or branch,
// and whenever a cached base/src register gets redefined.

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

        bool forwardLoad(Context&                 ctx,
                         const Cache&             cache,
                         MicroInstrRef            loadRef,
                         const MicroInstrOperand* ops)
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

            if (inst.op == MicroInstrOpcode::LoadRegMem && inst.numOperands >= 4 && ops && !ctx.isClaimed(it.current))
            {
                forwardLoad(ctx, cache, it.current, ops);
                continue;
            }

            if (inst.op == MicroInstrOpcode::LoadMemReg && inst.numOperands >= 4 && ops)
            {
                // Any prior entry might alias this slot (no alias info), flush first.
                cache.clear();
                // A claimed store will be erased by another pattern; caching it
                // would let a later load forward to a register with no live def.
                if (ctx.isClaimed(it.current))
                    continue;
                CacheEntry entry;
                entry.base = ops[0].reg;
                entry.src  = ops[1].reg;
                entry.bits = ops[2].opBits;
                entry.off  = ops[3].valueU64;
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
