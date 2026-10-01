#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Main/CompilerInstance.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class PartitionedSymbolMap final : public SymbolMap
    {
    public:
        using SymbolMap::SymbolMap;

        uint32_t usedShards() const
        {
            const Shard* shards = shards_.load(std::memory_order_acquire);
            if (!shards)
                return 0;

            uint32_t result = 0;
            for (uint32_t i = 0; i < SHARD_COUNT; ++i)
            {
                const ShardTable* table = shards[i].table.load(std::memory_order_acquire);
                if (table && table->size)
                    ++result;
            }
            return result;
        }
    };
}

SWC_TEST_BEGIN(SymbolMap_InternedIdentifiersUseEveryShard)
{
    PartitionedSymbolMap                         symbols(nullptr, TokenRef::invalid(), SymbolKind::Namespace, IdentifierRef::invalid(), {});
    std::vector<std::unique_ptr<SymbolVariable>> storage;
    for (uint32_t index = 0; index < 512; ++index)
    {
        // Real references encode aligned storage offsets, unlike consecutive test integers.
        const IdentifierRef id = ctx.idMgr().addIdentifierOwned(std::format("partitioned_symbol_{}", index));
        storage.push_back(std::make_unique<SymbolVariable>(nullptr, TokenRef{index}, id, SymbolFlags{}));
        symbols.addSymbol(ctx, storage.back().get(), false);
    }

    if (symbols.usedShards() != 8)
        return Result::Error;
    for (const auto& symbol : storage)
        if (symbols.findFirstSymbol(symbol->idRef()) != symbol.get())
            return Result::Error;
}
SWC_TEST_END()

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
        const IdentifierRef id = ctx.idMgr().addIdentifierOwned(std::format("concurrent_symbol_{}", index));
        storage.push_back(std::make_unique<SymbolVariable>(nullptr, TokenRef{index}, id, SymbolFlags{}));
    }
    for (uint32_t index = 0; index < NUM_SEEDS; ++index)
        symbols.addSymbol(ctx, storage[index].get(), false);

    std::barrier                         rendezvous(NUM_WORKERS + 1);
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

SWC_TEST_BEGIN(SymbolMap_LockFreeLookupsSeeEveryPublishedSymbol)
{
    // Readers probe the shard tables without a lock while writers grow them and link homonyms
    // in front of and behind existing ones. A symbol published before a lookup starts must be
    // found, whatever table generation the reader lands on.
    constexpr uint32_t NUM_WRITERS = 2;
    constexpr uint32_t NUM_READERS = 2;
    constexpr uint32_t NUM_NAMES   = 2048;
    constexpr uint32_t NUM_SEEDS   = 65;

    SymbolMap                                    symbols(nullptr, TokenRef::invalid(), SymbolKind::Namespace, IdentifierRef::invalid(), {});
    std::vector<IdentifierRef>                   ids;
    std::vector<std::unique_ptr<SymbolVariable>> firsts;
    std::vector<std::unique_ptr<SymbolVariable>> earlier;
    for (uint32_t index = 0; index < NUM_NAMES; ++index)
    {
        ids.push_back(ctx.idMgr().addIdentifierOwned(std::format("lock_free_symbol_{}", index)));
        // Token order decides homonym order: 'earlier' is linked in front of 'first'.
        firsts.push_back(std::make_unique<SymbolVariable>(nullptr, TokenRef{2 * NUM_NAMES + index}, ids.back(), SymbolFlags{}));
        earlier.push_back(std::make_unique<SymbolVariable>(nullptr, TokenRef{index}, ids.back(), SymbolFlags{}));
    }
    for (uint32_t index = 0; index < NUM_SEEDS; ++index)
        symbols.addSymbol(ctx, firsts[index].get(), true);

    std::array<std::atomic<uint32_t>, NUM_WRITERS> published{};
    std::atomic<uint32_t>                          finished{0};
    std::atomic<bool>                              valid{true};
    std::vector<std::thread>                       threads;
    for (uint32_t writer = 0; writer < NUM_WRITERS; ++writer)
    {
        threads.emplace_back([&, writer] {
            TaskContext workerCtx(ctx);
            uint32_t    count = 0;
            for (uint32_t index = NUM_SEEDS + writer; index < NUM_NAMES; index += NUM_WRITERS)
            {
                symbols.addSymbol(workerCtx, firsts[index].get(), true);
                symbols.addSymbol(workerCtx, earlier[index].get(), true);
                published[writer].store(++count, std::memory_order_release);
            }
            finished.fetch_add(1, std::memory_order_release);
        });
    }

    for (uint32_t reader = 0; reader < NUM_READERS; ++reader)
    {
        threads.emplace_back([&, reader] {
            uint32_t probe = reader;
            while (finished.load(std::memory_order_acquire) != NUM_WRITERS)
            {
                for (uint32_t writer = 0; writer < NUM_WRITERS; ++writer)
                {
                    const uint32_t count = published[writer].load(std::memory_order_acquire);
                    if (!count)
                        continue;
                    const uint32_t index = NUM_SEEDS + writer + NUM_WRITERS * (probe++ % count);
                    if (symbols.findFirstSymbol(ids[index]) != earlier[index].get())
                        valid.store(false, std::memory_order_relaxed);
                    const Symbol* second = earlier[index]->nextHomonym();
                    if (second != firsts[index].get() || second->nextHomonym())
                        valid.store(false, std::memory_order_relaxed);
                }
                for (uint32_t index = 0; index < NUM_SEEDS; ++index)
                    if (symbols.findFirstSymbol(ids[index]) != firsts[index].get())
                        valid.store(false, std::memory_order_relaxed);
            }
        });
    }

    for (auto& thread : threads)
        thread.join();

    if (!valid.load() || symbols.count() != 2 * NUM_NAMES - NUM_SEEDS)
        return Result::Error;
    for (uint32_t index = NUM_SEEDS; index < NUM_NAMES; ++index)
        if (symbols.findFirstSymbol(ids[index]) != earlier[index].get())
            return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(SymbolMap_ConcurrentUsingPublicationPreservesSnapshots)
{
    constexpr uint32_t NUM_IMPORTS = 128;
    SymbolMap          symbols(nullptr, TokenRef::invalid(), SymbolKind::Namespace, IdentifierRef::invalid(), {});
    std::vector<std::unique_ptr<SymbolMap>> imports;
    for (uint32_t i = 0; i < NUM_IMPORTS; ++i)
        imports.push_back(std::make_unique<SymbolMap>(nullptr, TokenRef::invalid(), SymbolKind::Namespace, IdentifierRef::invalid(), SymbolFlags{}));

    SmallVector<const SymbolMap*> empty;
    empty.push_back(&symbols);
    symbols.copyUsingSymMaps(empty);
    if (empty.size() != 1 || empty.front() != &symbols)
        return Result::Error;

    std::barrier          start(3);
    std::atomic<uint32_t> finished{0};
    std::thread           writers[2];
    for (uint32_t writer = 0; writer < 2; ++writer)
    {
        writers[writer] = std::thread([&, writer] {
            TaskContext workerCtx(ctx);
            start.arrive_and_wait();
            for (uint32_t i = writer; i < NUM_IMPORTS; i += 2)
            {
                symbols.addUsingSymMap(workerCtx, imports[i].get());
                symbols.addUsingSymMap(workerCtx, imports[i].get());
            }
            finished.fetch_add(1, std::memory_order_release);
        });
    }

    bool                         valid = true;
    SmallVector<const SymbolMap*> previous;
    previous.push_back(&symbols);
    start.arrive_and_wait();
    do
    {
        SmallVector<const SymbolMap*> snapshot;
        snapshot.push_back(&symbols);
        symbols.copyUsingSymMaps(snapshot);
        // Every read is an insertion-ordered prefix, including while writers publish.
        if (snapshot.size() < previous.size() || !std::equal(previous.begin(), previous.end(), snapshot.begin()))
            valid = false;
        previous = std::move(snapshot);
        std::this_thread::yield();
    } while (finished.load(std::memory_order_acquire) != 2);
    for (auto& writer : writers)
        writer.join();

    SmallVector<const SymbolMap*> all;
    all.push_back(&symbols);
    symbols.copyUsingSymMaps(all);
    const std::unordered_set<const SymbolMap*> unique(all.begin(), all.end());
    if (!valid || all.size() != NUM_IMPORTS + 1 || unique.size() != all.size() || all.front() != &symbols)
        return Result::Error;
    for (const auto& imported : imports)
        if (!unique.contains(imported.get()))
            return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
