#include "pch.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Assert.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SourceViewRef safeSymbolSrcViewRef(const Symbol& symbol)
    {
        if (const AstNode* decl = symbol.decl())
            return decl->srcViewRef();
        return SourceViewRef::invalid();
    }

    struct SymbolSortEntry
    {
        Symbol*       symbol     = nullptr;
        SourceViewRef srcViewRef = SourceViewRef::invalid();
        TokenRef      tokRef     = TokenRef::invalid();
        SymbolKind    kind       = SymbolKind::Invalid;
        IdentifierRef idRef      = IdentifierRef::invalid();
    };

    bool symbolDeclaredBefore(const Symbol& lhs, const Symbol& rhs)
    {
        const auto lhsSrcViewRef = safeSymbolSrcViewRef(lhs);
        const auto rhsSrcViewRef = safeSymbolSrcViewRef(rhs);
        if (lhsSrcViewRef != rhsSrcViewRef)
            return lhsSrcViewRef < rhsSrcViewRef;
        if (lhs.tokRef() != rhs.tokRef())
            return lhs.tokRef() < rhs.tokRef();
        return lhs.kind() < rhs.kind();
    }

    bool symbolDeclaredBefore(const SymbolSortEntry& lhs, const SymbolSortEntry& rhs)
    {
        if (lhs.srcViewRef != rhs.srcViewRef)
            return lhs.srcViewRef < rhs.srcViewRef;
        if (lhs.tokRef != rhs.tokRef)
            return lhs.tokRef < rhs.tokRef;
        if (lhs.kind != rhs.kind)
            return lhs.kind < rhs.kind;
        return lhs.idRef < rhs.idRef;
    }

    Symbol* insertSymbolOrdered(Symbol*& head, Symbol* symbol)
    {
        // Homonyms are kept in declaration order. Lookup can then report overloads
        // and duplicate diagnostics deterministically without sorting on every query.
        if (!head || symbolDeclaredBefore(*symbol, *head))
        {
            symbol->setNextHomonym(head);
            head = symbol;
            return head;
        }

        Symbol* current = head;
        Symbol* next    = current->nextHomonym();
        while (next && !symbolDeclaredBefore(*symbol, *next))
        {
            current = next;
            next    = current->nextHomonym();
        }

        symbol->setNextHomonym(next);
        current->setNextHomonym(symbol);
        return head;
    }

    void appendSymbolsForSort(std::vector<SymbolSortEntry>& out, Symbol* head, bool includeIgnored)
    {
        for (Symbol* cur = head; cur; cur = cur->nextHomonym())
        {
            if (!includeIgnored && cur->isIgnored())
                continue;

            SymbolSortEntry entry;
            entry.symbol     = cur;
            entry.srcViewRef = safeSymbolSrcViewRef(*cur);
            entry.tokRef     = cur->tokRef();
            entry.kind       = cur->kind();
            entry.idRef      = cur->idRef();
            out.push_back(entry);
        }
    }

    template<typename T>
    void sortSymbolsByDeclaration(std::vector<T*>& symbols, std::vector<SymbolSortEntry>& entries)
    {
        if (entries.size() < 2)
        {
            symbols.clear();
            symbols.reserve(entries.size());
            for (const auto& entry : entries)
                symbols.push_back(entry.symbol);
            return;
        }

        std::ranges::stable_sort(entries, [](const SymbolSortEntry& lhs, const SymbolSortEntry& rhs) {
            return symbolDeclaredBefore(lhs, rhs);
        });

        symbols.clear();
        symbols.reserve(entries.size());
        for (const auto& entry : entries)
            symbols.push_back(entry.symbol);
    }

    void appendHomonyms(MatchContext& lookUpCxt, const Symbol* head)
    {
        for (const Symbol* cur = head; cur; cur = cur->nextHomonym())
        {
            if (cur->isIgnored())
            {
                if (!cur->isExcludedByCondition())
                    lookUpCxt.addIgnoredSymbol();
            }
            else
                lookUpCxt.addSymbol(cur);
        }
    }

    uint64_t shardKey(IdentifierRef idRef) noexcept
    {
        return static_cast<uint64_t>(idRef.get()) + 1;
    }

    const Symbol* firstVisibleSymbol(const Symbol* head, bool includeIgnored)
    {
        for (const Symbol* cur = head; cur; cur = cur->nextHomonym())
        {
            if (includeIgnored || !cur->isIgnored())
                return cur;
        }

        return nullptr;
    }

}

SymbolMap::SymbolMap(const AstNode* decl, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags) :
    Symbol(decl, tokRef, kind, idRef, flags)
{
}

void SymbolMap::addUsingSymMap(TaskContext& ctx, SymbolMap* symMap)
{
    SWC_ASSERT(symMap != nullptr);
    const std::unique_lock lk(mutex_);
    const UsingSymMap*     head = usingSymMaps_.load(std::memory_order_relaxed);
    for (const UsingSymMap* existing = head; existing; existing = existing->previous)
    {
        if (existing->symbol == symMap)
            return;
    }

    auto* entry     = ctx.allocate<UsingSymMap>();
    entry->symbol   = symMap;
    entry->previous = head;
    usingSymMaps_.store(entry, std::memory_order_release);
}

void SymbolMap::copyUsingSymMaps(SmallVector<const SymbolMap*>& out) const
{
    const size_t start = out.size();
    for (const UsingSymMap* entry = usingSymMaps_.load(std::memory_order_acquire); entry; entry = entry->previous)
        out.push_back(entry->symbol);

    // The published chain points backwards; lookup still sees insertion order and
    // keeps any entries the caller had already collected at the front.
    std::reverse(out.begin() + start, out.end());
}

bool SymbolMap::empty() const noexcept
{
    return count() == 0;
}

SymbolMap::Entry* SymbolMap::smallFind(IdentifierRef key)
{
    const uint32_t smallSize = smallSize_.load(std::memory_order_relaxed);
    for (uint32_t i = 0; i < smallSize; ++i)
        if (small_[i].key == key)
            return &small_[i];
    return nullptr;
}

Symbol* SymbolMap::smallFindHead(IdentifierRef key, uint32_t smallSize) const noexcept
{
    // Turning big copies the entries and leaves them in place, so a reader that saw a small
    // size still scans a consistent snapshot; it simply misses insertions made after it.
    for (uint32_t i = 0; i < smallSize; ++i)
        if (small_[i].key == key)
            return small_[i].head.load(std::memory_order_acquire);
    return nullptr;
}

template<typename F>
void SymbolMap::forEachHead(const HeadTable* table, const F& fn)
{
    if (!table)
        return;

    for (uint32_t i = 0; i < table->capacity; ++i)
    {
        if (const uint64_t key = table->keys[i].load(std::memory_order_acquire))
            fn(key, table->heads[i].load(std::memory_order_acquire));
    }
}

void SymbolMap::upgradeToSharded(TaskContext& ctx)
{
    // Large symbol maps are read by many sema jobs and written by many declarations. Shards
    // spread the writers; readers keep probing without a lock, on whichever table they loaded.
    const HeadTable& big       = *bigTable_.load(std::memory_order_relaxed);
    auto*            newShards = ctx.compiler().allocateArray<Shard>(SHARD_COUNT);

    const auto perShard = (big.size / SHARD_COUNT) + 1;
    for (uint32_t i = 0; i < SHARD_COUNT; ++i)
        tableReserve(ctx, newShards[i].table, perShard * 2);

    forEachHead(&big, [&](uint64_t key, Symbol* head) {
        const uint32_t hash  = Math::hash(static_cast<uint32_t>(key - 1));
        HeadTable&     table = *newShards[hash & (SHARD_COUNT - 1)].table.load(std::memory_order_relaxed);
        tablePlace(table, tableSlot(table, key, hash), key, head);
    });

    shards_.store(newShards, std::memory_order_release);
}

void SymbolMap::notifyInserted(TaskContext& ctx, IdentifierRef idRef)
{
    ctx.compiler().notifyAlive();
    ctx.global().jobMgr().wake(WaitKey::name(idRef, TaskStateKind::SemaWaitIdentifier));
}

uint32_t SymbolMap::tableSlot(const HeadTable& table, uint64_t key, uint32_t hash) noexcept
{
    const uint32_t mask = table.capacity - 1;
    uint32_t       i    = (hash >> SHARD_BITS) & mask;
    while (true)
    {
        const uint64_t slotKey = table.keys[i].load(std::memory_order_acquire);
        if (slotKey == key || !slotKey)
            return i;
        i = (i + 1) & mask;
    }
}

Symbol* SymbolMap::tableFindHead(const HeadTable* table, IdentifierRef idRef, uint32_t hash) noexcept
{
    if (!table)
        return nullptr;

    const uint64_t key  = shardKey(idRef);
    const uint32_t mask = table->capacity - 1;
    uint32_t       slot = (hash >> SHARD_BITS) & mask;
    while (true)
    {
        // Decide from this observation: an empty slot can acquire a different key before
        // another load. Once our key is published, its head can only change to a homonym.
        const uint64_t slotKey = table->keys[slot].load(std::memory_order_acquire);
        if (slotKey == key)
            return table->heads[slot].load(std::memory_order_acquire);
        if (!slotKey)
            return nullptr;
        slot = (slot + 1) & mask;
    }
}

void SymbolMap::tablePlace(HeadTable& table, uint32_t slot, uint64_t key, Symbol* head) noexcept
{
    SWC_ASSERT(!table.keys[slot].load(std::memory_order_relaxed));

    // The head goes first: a reader that sees the key must find a complete entry.
    table.heads[slot].store(head, std::memory_order_relaxed);
    table.keys[slot].store(key, std::memory_order_release);
    table.size++;
}

void SymbolMap::tableReserve(TaskContext& ctx, std::atomic<HeadTable*>& published, uint32_t minSize)
{
    // Keeping the load at or below one half bounds every probe and guarantees an empty slot.
    const HeadTable* old = published.load(std::memory_order_relaxed);
    if (old && minSize * 2 <= old->capacity)
        return;

    uint32_t capacity = old ? old->capacity * 2 : 8;
    while (capacity < minSize * 2)
        capacity *= 2;

    auto* table     = ctx.compiler().allocateArray<HeadTable>(1);
    table->keys     = ctx.compiler().allocateArray<std::atomic<uint64_t>>(capacity);
    table->heads    = ctx.compiler().allocateArray<std::atomic<Symbol*>>(capacity);
    table->capacity = capacity;
    forEachHead(old, [&](uint64_t key, Symbol* head) {
        const uint32_t hash = Math::hash(static_cast<uint32_t>(key - 1));
        tablePlace(*table, tableSlot(*table, key, hash), key, head);
    });

    // A reader still probing the old table sees a consistent snapshot: tables live in the arena.
    published.store(table, std::memory_order_release);
}

Symbol* SymbolMap::tableInsert(TaskContext& ctx, std::atomic<HeadTable*>& published, IdentifierRef idRef, uint32_t hash, Symbol* symbol, bool acceptHomonyms)
{
    HeadTable*     table = published.load(std::memory_order_relaxed);
    const uint64_t key   = shardKey(idRef);
    uint32_t       slot  = table ? tableSlot(*table, key, hash) : 0;
    Symbol*        head  = table && table->keys[slot].load(std::memory_order_acquire) ? table->heads[slot].load(std::memory_order_acquire) : nullptr;
    if (head && !acceptHomonyms)
        return head;

    // Readers walk the published chain without the lock, so the symbol is complete, owner
    // included, before any link to it is stored.
    if (symbol->ownerSymMap() != this)
        count_.fetch_add(1, std::memory_order_relaxed);
    symbol->setOwnerSymMap(this);
    if (!head)
    {
        symbol->setNextHomonym(nullptr);
        tableReserve(ctx, published, (table ? table->size : 0) + 1);
        // The writer holds the map or shard lock, so only growth can change this slot.
        HeadTable* const resized = published.load(std::memory_order_relaxed);
        if (table != resized)
        {
            table = resized;
            slot  = tableSlot(*table, key, hash);
        }
        tablePlace(*table, slot, key, symbol);
        return symbol;
    }

    Symbol* const insertedHead = insertSymbolOrdered(head, symbol);
    if (insertedHead == symbol)
        table->heads[slot].store(insertedHead, std::memory_order_release);

    return insertedHead;
}

Symbol* SymbolMap::insertIntoShard(Shard* shards, IdentifierRef idRef, Symbol* symbol, TaskContext& ctx, bool acceptHomonyms)
{
    // References contain aligned byte offsets: masking their low bits routes every
    // real identifier to shard zero. Mix the whole reference before choosing a lock.
    const uint32_t         hash  = Math::hash(idRef.get());
    Shard&                 shard = shards[hash & (SHARD_COUNT - 1)];
    const std::unique_lock lock(shard.mutex);
    return tableInsert(ctx, shard.table, idRef, hash, symbol, acceptHomonyms);
}

Symbol* SymbolMap::findHead(IdentifierRef idRef) const noexcept
{
    // No lookup takes a lock. The representation only grows: small entries, then one table,
    // then shards. Each step is published before the next one is announced, so a reader that
    // sees a later step also sees its storage, and a stale step stays a consistent snapshot.
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        const uint32_t hash = Math::hash(idRef.get());
        return tableFindHead(shards[hash & (SHARD_COUNT - 1)].table.load(std::memory_order_acquire), idRef, hash);
    }

    const uint32_t smallSize = smallSize_.load(std::memory_order_acquire);
    if (smallSize <= SMALL_CAP)
        return smallFindHead(idRef, smallSize);

    return tableFindHead(bigTable_.load(std::memory_order_acquire), idRef, Math::hash(idRef.get()));
}

void SymbolMap::lookupAppend(IdentifierRef idRef, MatchContext& lookUpCxt) const
{
    appendHomonyms(lookUpCxt, findHead(idRef));
}

const Symbol* SymbolMap::findFirstSymbol(IdentifierRef idRef, bool includeIgnored) const
{
    return firstVisibleSymbol(findHead(idRef), includeIgnored);
}

template<typename F>
void SymbolMap::forEachPublishedHead(const F& fn) const
{
    const auto append = [&](uint64_t, Symbol* head) {
        fn(head);
    };
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        for (uint32_t i = 0; i < SHARD_COUNT; ++i)
            forEachHead(shards[i].table.load(std::memory_order_acquire), append);
    }
    else
    {
        const uint32_t smallSize = smallSize_.load(std::memory_order_acquire);
        if (smallSize <= SMALL_CAP)
        {
            for (uint32_t i = 0; i < smallSize; ++i)
                fn(small_[i].head.load(std::memory_order_acquire));
        }
        else
            forEachHead(bigTable_.load(std::memory_order_acquire), append);
    }
}

void SymbolMap::getAllSymbols(std::vector<const Symbol*>& out, bool includeIgnored) const
{
    out.clear();
    std::vector<SymbolSortEntry> ordered;
    ordered.reserve(count());
    forEachPublishedHead([&](Symbol* head) { appendSymbolsForSort(ordered, head, includeIgnored); });
    sortSymbolsByDeclaration(out, ordered);
}

uint64_t SymbolMap::countSymbols(SymbolKind kind) const
{
    // Counting visible symbols needs neither declaration metadata nor a sorted snapshot.
    uint64_t result = 0;
    forEachPublishedHead([&](const Symbol* head) {
        for (const Symbol* symbol = head; symbol; symbol = symbol->nextHomonym())
        {
            if (!symbol->isIgnored() && symbol->kind() == kind)
                ++result;
        }
    });
    return result;
}

Symbol* SymbolMap::addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms)
{
    SWC_ASSERT(symbol != nullptr);

    const IdentifierRef idRef = symbol->idRef();
    Symbol*             result;

    if (Shard* shards = shards_.load(std::memory_order_acquire))
        result = insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms);
    else
    {
        std::unique_lock lk(mutex_);

        // Another writer may have upgraded the representation while this one waited.
        if (Shard* upgraded = shards_.load(std::memory_order_acquire))
        {
            lk.unlock();
            result = insertIntoShard(upgraded, idRef, symbol, ctx, acceptHomonyms);
        }
        else if (!isBig())
        {
            const uint32_t smallSize = smallSize_.load(std::memory_order_relaxed);
            if (Entry* e = smallFind(idRef))
            {
                Symbol* head = e->head.load(std::memory_order_relaxed);
                if (!acceptHomonyms)
                    return head;
                count_.fetch_add(1, std::memory_order_relaxed);
                symbol->setOwnerSymMap(this);
                result = insertSymbolOrdered(head, symbol);
                e->head.store(result, std::memory_order_release);
            }
            else if (smallSize < SMALL_CAP)
            {
                count_.fetch_add(1, std::memory_order_relaxed);
                symbol->setOwnerSymMap(this);
                symbol->setNextHomonym(nullptr);
                small_[smallSize].key = idRef;
                small_[smallSize].head.store(symbol, std::memory_order_relaxed);
                smallSize_.store(smallSize + 1, std::memory_order_release);
                result = symbol;
            }
            else
            {
                // Turn big: the table is published before the size announces it, and the small
                // entries stay intact for readers still scanning them.
                tableReserve(ctx, bigTable_, SMALL_CAP + 1);
                HeadTable& table = *bigTable_.load(std::memory_order_relaxed);
                for (uint32_t i = 0; i < SMALL_CAP; ++i)
                {
                    const uint64_t key  = shardKey(small_[i].key);
                    const uint32_t hash = Math::hash(small_[i].key.get());
                    tablePlace(table, tableSlot(table, key, hash), key, small_[i].head.load(std::memory_order_relaxed));
                }
                smallSize_.store(SMALL_CAP + 1, std::memory_order_release);
                result = tableInsert(ctx, bigTable_, idRef, Math::hash(idRef.get()), symbol, acceptHomonyms);
            }
        }
        else if (bigTable_.load(std::memory_order_relaxed)->size < SHARD_AFTER_KEYS)
            result = tableInsert(ctx, bigTable_, idRef, Math::hash(idRef.get()), symbol, acceptHomonyms);
        else
        {
            upgradeToSharded(ctx);
            lk.unlock();
            result = insertIntoShard(shards_.load(std::memory_order_relaxed), idRef, symbol, ctx, acceptHomonyms);
        }
    }

    if (result == symbol || symbol->ownerSymMap() == this)
        notifyInserted(ctx, idRef);
    return result;
}

Symbol* SymbolMap::addSingleSymbolOrError(Sema& sema, Symbol* symbol)
{
    TaskContext& ctx         = sema.ctx();
    Symbol*      insertedSym = addSymbol(ctx, symbol, true);
    if (!insertedSym)
        return nullptr;

    if (insertedSym != symbol)
    {
        symbol->setIgnored(ctx);
        SemaError::raiseAlreadyDefined(sema, symbol, insertedSym);
    }
    else if (symbol->nextHomonym())
    {
        Symbol* duplicateSymbol = symbol->nextHomonym();
        duplicateSymbol->setIgnored(ctx);
        SemaError::raiseAlreadyDefined(sema, duplicateSymbol, symbol);
    }

    return insertedSym;
}

Symbol* SymbolMap::addSingleSymbol(TaskContext& ctx, Symbol* symbol)
{
    return addSymbol(ctx, symbol, false);
}

SWC_END_NAMESPACE();
