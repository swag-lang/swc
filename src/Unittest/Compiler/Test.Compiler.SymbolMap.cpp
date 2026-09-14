#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(SymbolMap_ConcurrentShardsPreserveCountAndTraversal)
{
    constexpr uint32_t NUM_WORKERS = 4;
    constexpr uint32_t NUM_ROUNDS  = 256;
    constexpr uint32_t NUM_SEEDS   = 65;
    constexpr uint32_t NUM_SYMBOLS = NUM_SEEDS + NUM_WORKERS * NUM_ROUNDS;

    SymbolMap                                    symbols(nullptr, TokenRef::invalid(), SymbolKind::Namespace, IdentifierRef{0}, {});
    std::vector<std::unique_ptr<SymbolVariable>> storage;
    storage.reserve(NUM_SYMBOLS);
    for (uint32_t index = 0; index < NUM_SYMBOLS; ++index)
    {
        // Each writer owns one shard after the initial insertions trigger the upgrade.
        const uint32_t id = index < NUM_SEEDS ? index + 1 : 128 + ((index - NUM_SEEDS) / NUM_WORKERS) * 8 + (index - NUM_SEEDS) % NUM_WORKERS;
        storage.push_back(std::make_unique<SymbolVariable>(nullptr, TokenRef{index}, IdentifierRef{id}, SymbolFlags{}));
    }
    for (uint32_t index = 0; index < NUM_SEEDS; ++index)
        symbols.addSymbol(ctx, storage[index].get(), false);

    std::barrier                        rendezvous(NUM_WORKERS + 1);
    std::array<std::thread, NUM_WORKERS> writers;
    for (uint32_t worker = 0; worker < NUM_WORKERS; ++worker)
    {
        writers[worker] = std::thread([&, worker] {
            TaskContext workerCtx(ctx);
            for (uint32_t round = 0; round < NUM_ROUNDS; ++round)
            {
                rendezvous.arrive_and_wait();
                symbols.addSymbol(workerCtx, storage[NUM_SEEDS + round * NUM_WORKERS + worker].get(), false);
                rendezvous.arrive_and_wait();
            }
        });
    }

    bool                       valid = true;
    std::vector<const Symbol*> snapshot;
    for (uint32_t round = 0; round < NUM_ROUNDS; ++round)
    {
        rendezvous.arrive_and_wait();
        symbols.getAllSymbols(snapshot);
        // A concurrent snapshot may precede some insertions, but never duplicates or loses
        // symbols from a completed round. Declaration order is independent of publication.
        if (snapshot.size() < NUM_SEEDS + round * NUM_WORKERS || snapshot.size() > NUM_SEEDS + (round + 1) * NUM_WORKERS)
            valid = false;
        for (size_t index = 1; index < snapshot.size(); ++index)
            if (snapshot[index - 1]->tokRef().get() >= snapshot[index]->tokRef().get())
                valid = false;
        rendezvous.arrive_and_wait();
        if (symbols.count() != NUM_SEEDS + (round + 1) * NUM_WORKERS)
            valid = false;
    }
    for (auto& writer : writers)
        writer.join();

    symbols.getAllSymbols(snapshot);
    if (!valid || snapshot.size() != NUM_SYMBOLS || symbols.count() != NUM_SYMBOLS)
        return Result::Error;

    SymbolVariable duplicate(nullptr, TokenRef::invalid(), storage.back()->idRef(), {});
    if (symbols.addSymbol(ctx, &duplicate, false) != storage.back().get() || symbols.count() != NUM_SYMBOLS)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
