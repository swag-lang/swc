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
        while (current->nextHomonym() && !symbolDeclaredBefore(*symbol, *current->nextHomonym()))
            current = current->nextHomonym();

        symbol->setNextHomonym(current->nextHomonym());
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

uint32_t SymbolMap::shardIndex(IdentifierRef idRef) noexcept
{
    // References contain aligned byte offsets: masking their low bits routes every
    // real identifier to shard zero. Mix the whole reference before choosing a lock.
    return Math::hash(idRef.get()) & (SHARD_COUNT - 1);
}

void SymbolMap::addUsingSymMap(TaskContext& ctx, SymbolMap* symMap)
{
    SWC_ASSERT(symMap != nullptr);
    const std::unique_lock lk(mutex_);
    const UsingSymMap* head = usingSymMaps_.load(std::memory_order_relaxed);
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
    if (isSharded())
        return false;
    const std::shared_lock lk(mutex_);
    return smallSize_.load(std::memory_order_relaxed) == 0 && (!bigMap_ || bigMap_->empty());
}

SymbolMap::Entry* SymbolMap::smallFind(IdentifierRef key)
{
    const uint32_t smallSize = smallSize_.load(std::memory_order_relaxed);
    for (uint32_t i = 0; i < smallSize; ++i)
        if (small_[i].key == key)
            return &small_[i];
    return nullptr;
}

const SymbolMap::Entry* SymbolMap::smallFind(IdentifierRef key) const
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

void SymbolMap::maybeUpgradeToSharded(TaskContext& ctx)
{
    // Fast path: already sharded.
    if (isSharded())
        return;

    // Not enough keys yet - stay unsharded.
    if (!bigMap_ || bigMap_->size() < SHARD_AFTER_KEYS)
        return;

    // Large symbol maps are read by many sema jobs. Publish immutable shard storage
    // with release/acquire semantics so readers can switch from the monolithic map
    // without holding the original mutex forever.
    auto* newShards = ctx.compiler().allocateArray<Shard>(SHARD_COUNT);

    const auto totalKeys = static_cast<uint32_t>(bigMap_->size());
    const auto perShard  = (totalKeys / SHARD_COUNT) + 1;
    for (uint32_t i = 0; i < SHARD_COUNT; ++i)
        shardReserve(ctx, newShards[i], perShard * 2);

    for (const auto& [id, head] : *bigMap_)
    {
        ShardTable& table = *newShards[shardIndex(id)].table.load(std::memory_order_relaxed);
        shardPlace(table, shardKey(id), head);
    }

    bigMap_.reset();
    shards_.store(newShards, std::memory_order_release);
}

void SymbolMap::notifyInserted(TaskContext& ctx, IdentifierRef idRef)
{
    ctx.compiler().notifyAlive();
    ctx.global().jobMgr().wake(WaitKey::name(idRef, TaskStateKind::SemaWaitIdentifier));
}

uint32_t SymbolMap::shardSlot(const ShardTable& table, uint64_t key) noexcept
{
    const uint32_t mask = table.capacity - 1;
    uint32_t       i    = (Math::hash(static_cast<uint32_t>(key - 1)) >> SHARD_BITS) & mask;
    while (true)
    {
        const uint64_t slotKey = table.keys[i].load(std::memory_order_acquire);
        if (slotKey == key || !slotKey)
            return i;
        i = (i + 1) & mask;
    }
}

Symbol* SymbolMap::shardFindHead(const Shard& shard, IdentifierRef idRef) noexcept
{
    const ShardTable* table = shard.table.load(std::memory_order_acquire);
    if (!table)
        return nullptr;

    const uint32_t slot = shardSlot(*table, shardKey(idRef));
    if (!table->keys[slot].load(std::memory_order_acquire))
        return nullptr;
    return table->heads[slot].load(std::memory_order_acquire);
}

void SymbolMap::shardPlace(ShardTable& table, uint64_t key, Symbol* head) noexcept
{
    const uint32_t slot = shardSlot(table, key);
    SWC_ASSERT(!table.keys[slot].load(std::memory_order_relaxed));

    // The head goes first: a reader that sees the key must find a complete entry.
    table.heads[slot].store(head, std::memory_order_relaxed);
    table.keys[slot].store(key, std::memory_order_release);
    table.size++;
}

void SymbolMap::shardReserve(TaskContext& ctx, Shard& shard, uint32_t minSize)
{
    // Keeping the load at or below one half bounds every probe and guarantees an empty slot.
    const ShardTable* old = shard.table.load(std::memory_order_relaxed);
    if (old && minSize * 2 <= old->capacity)
        return;

    uint32_t capacity = old ? old->capacity * 2 : 16;
    while (capacity < minSize * 2)
        capacity *= 2;

    auto* table     = ctx.compiler().allocateArray<ShardTable>(1);
    table->keys     = ctx.compiler().allocateArray<std::atomic<uint64_t>>(capacity);
    table->heads    = ctx.compiler().allocateArray<std::atomic<Symbol*>>(capacity);
    table->capacity = capacity;

    if (old)
    {
        for (uint32_t i = 0; i < old->capacity; ++i)
        {
            if (const uint64_t key = old->keys[i].load(std::memory_order_relaxed))
                shardPlace(*table, key, old->heads[i].load(std::memory_order_relaxed));
        }
    }

    shard.table.store(table, std::memory_order_release);
}

Symbol* SymbolMap::insertIntoShard(Shard* shards, IdentifierRef idRef, Symbol* symbol, TaskContext& ctx, bool acceptHomonyms, bool notify)
{
    SWC_ASSERT(shards != nullptr);

    Shard&                 shard = shards[shardIndex(idRef)];
    const std::unique_lock lock(shard.mutex);

    Symbol* head = shardFindHead(shard, idRef);
    if (head && !acceptHomonyms)
        return head;

    // Readers walk the published chain without the lock, so the symbol is complete, owner
    // included, before any link to it is stored.
    symbol->setOwnerSymMap(this);
    if (!head)
    {
        symbol->setNextHomonym(nullptr);
        const ShardTable* table = shard.table.load(std::memory_order_relaxed);
        shardReserve(ctx, shard, (table ? table->size : 0) + 1);
        shardPlace(*shard.table.load(std::memory_order_relaxed), shardKey(idRef), symbol);
        if (notify)
            notifyInserted(ctx, idRef);
        return symbol;
    }

    Symbol* const insertedHead = insertSymbolOrdered(head, symbol);
    if (insertedHead == symbol)
    {
        ShardTable& table = *shard.table.load(std::memory_order_relaxed);
        table.heads[shardSlot(table, shardKey(idRef))].store(insertedHead, std::memory_order_release);
    }

    if (notify)
        notifyInserted(ctx, idRef);
    return insertedHead;
}

void SymbolMap::lookupAppend(IdentifierRef idRef, MatchContext& lookUpCxt) const
{
    // Once sharded, a lookup takes no lock: homonym chains remain ordered and the
    // old big map is no longer the lookup source.
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        appendHomonyms(lookUpCxt, shardFindHead(shards[shardIndex(idRef)], idRef));
        return;
    }

    const uint32_t smallSize = smallSize_.load(std::memory_order_acquire);
    if (smallSize <= SMALL_CAP)
    {
        appendHomonyms(lookUpCxt, smallFindHead(idRef, smallSize));
        return;
    }

    std::shared_lock lk(mutex_);

    // Check sharded again after locking: another writer may have upgraded between
    // the optimistic atomic load and this shared lock.
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        appendHomonyms(lookUpCxt, shardFindHead(shards[shardIndex(idRef)], idRef));
        return;
    }

    const Symbol* head = nullptr;
    if (bigMap_)
    {
        const auto it = bigMap_->find(idRef);
        if (it != bigMap_->end())
            head = it->second;
    }

    appendHomonyms(lookUpCxt, head);
}

const Symbol* SymbolMap::findFirstSymbol(IdentifierRef idRef, bool includeIgnored) const
{
    if (const Shard* shards = shards_.load(std::memory_order_acquire))
        return firstVisibleSymbol(shardFindHead(shards[shardIndex(idRef)], idRef), includeIgnored);

    const uint32_t smallSize = smallSize_.load(std::memory_order_acquire);
    if (smallSize <= SMALL_CAP)
        return firstVisibleSymbol(smallFindHead(idRef, smallSize), includeIgnored);

    std::shared_lock lk(mutex_);

    if (const Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        return firstVisibleSymbol(shardFindHead(shards[shardIndex(idRef)], idRef), includeIgnored);
    }

    const Symbol* head = nullptr;
    if (bigMap_)
    {
        const auto it = bigMap_->find(idRef);
        if (it != bigMap_->end())
            head = it->second;
    }

    return firstVisibleSymbol(head, includeIgnored);
}

void SymbolMap::getAllSymbols(std::vector<Symbol*>& out, bool includeIgnored) const
{
    std::vector<const Symbol*> symbols;
    getAllSymbols(symbols, includeIgnored);

    out.clear();
    out.reserve(symbols.size());
    for (const Symbol* symbol : symbols)
        out.push_back(const_cast<Symbol*>(symbol));
}

template<typename F>
void SymbolMap::forEachShardHead(const Shard* shards, const F& fn)
{
    for (uint32_t s = 0; s < SHARD_COUNT; ++s)
    {
        const ShardTable* table = shards[s].table.load(std::memory_order_acquire);
        if (!table)
            continue;

        for (uint32_t i = 0; i < table->capacity; ++i)
        {
            if (table->keys[i].load(std::memory_order_acquire))
                fn(table->heads[i].load(std::memory_order_acquire));
        }
    }
}

void SymbolMap::getAllSymbols(std::vector<const Symbol*>& out, bool includeIgnored) const
{
    out.clear();
    std::vector<SymbolSortEntry> ordered;
    ordered.reserve(count());

    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        forEachShardHead(shards, [&](Symbol* head) { appendSymbolsForSort(ordered, head, includeIgnored); });

        sortSymbolsByDeclaration(out, ordered);
        return;
    }

    std::shared_lock lk(mutex_);

    // Check sharded again after lock
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        forEachShardHead(shards, [&](Symbol* head) { appendSymbolsForSort(ordered, head, includeIgnored); });

        sortSymbolsByDeclaration(out, ordered);
        return;
    }

    if (isBig())
    {
        if (bigMap_)
            for (const auto& val : *bigMap_ | std::views::values)
            appendSymbolsForSort(ordered, val, includeIgnored);
    }
    else
    {
        const uint32_t smallSize = smallSize_.load(std::memory_order_relaxed);
        for (uint32_t i = 0; i < smallSize; ++i)
            appendSymbolsForSort(ordered, small_[i].head.load(std::memory_order_relaxed), includeIgnored);
    }

    sortSymbolsByDeclaration(out, ordered);
}

Symbol* SymbolMap::addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms)
{
    SWC_ASSERT(symbol != nullptr);

    const IdentifierRef idRef = symbol->idRef();

    // Sharded fast path.
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        const bool hadOwner    = symbol->ownerSymMap() == this;
        Symbol*    insertedSym = insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms, true);
        if (!hadOwner && symbol->ownerSymMap() == this)
        {
            count_.fetch_add(1, std::memory_order_relaxed);
        }

        return insertedSym;
    }

    std::unique_lock lk(mutex_);

    // If upgraded to sharded while waiting for lock
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        const bool hadOwner    = symbol->ownerSymMap() == this;
        Symbol*    insertedSym = insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms, true);
        if (!hadOwner && symbol->ownerSymMap() == this)
        {
            count_.fetch_add(1, std::memory_order_relaxed);
        }

        return insertedSym;
    }

    if (!isBig())
    {
        if (Entry* e = smallFind(idRef))
        {
            Symbol* head = e->head.load(std::memory_order_relaxed);
            if (!acceptHomonyms)
                return head;
            count_.fetch_add(1, std::memory_order_relaxed);
            symbol->setOwnerSymMap(this);
            Symbol* insertedHead = insertSymbolOrdered(head, symbol);
            e->head.store(insertedHead, std::memory_order_release);
            notifyInserted(ctx, idRef);
            return insertedHead;
        }

        const uint32_t smallSize = smallSize_.load(std::memory_order_relaxed);
        if (smallSize < SMALL_CAP)
        {
            count_.fetch_add(1, std::memory_order_relaxed);
            symbol->setOwnerSymMap(this);
            symbol->setNextHomonym(nullptr);
            small_[smallSize].key = idRef;
            small_[smallSize].head.store(symbol, std::memory_order_relaxed);
            smallSize_.store(smallSize + 1, std::memory_order_release);
            notifyInserted(ctx, idRef);
            return symbol;
        }

        // Transition to big. The small entries stay intact for readers still scanning them.
        bigMap_.emplace();
        bigMap_->reserve(SMALL_CAP * 2ull);
        for (uint32_t i = 0; i < smallSize; ++i)
            bigMap_->emplace(small_[i].key, small_[i].head.load(std::memory_order_relaxed));
        smallSize_.store(SMALL_CAP + 1, std::memory_order_release); // Mark as big
    }

    maybeUpgradeToSharded(ctx);

    // If upgraded to sharded during, maybeUpgradeToSharded
    if (Shard* shards = shards_.load(std::memory_order_acquire))
    {
        lk.unlock();
        const bool hadOwner    = symbol->ownerSymMap() == this;
        Symbol*    insertedSym = insertIntoShard(shards, idRef, symbol, ctx, acceptHomonyms, true);
        if (!hadOwner && symbol->ownerSymMap() == this)
        {
            count_.fetch_add(1, std::memory_order_relaxed);
        }

        return insertedSym;
    }

    // Still unsharded big map.
    const auto [it, inserted] = bigMap_->try_emplace(idRef, nullptr);
    if (!acceptHomonyms && !inserted)
        return it->second;

    Symbol*& head         = it->second;
    Symbol*  insertedHead = insertSymbolOrdered(head, symbol);
    count_.fetch_add(1, std::memory_order_relaxed);
    symbol->setOwnerSymMap(this);
    notifyInserted(ctx, idRef);
    return insertedHead;
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
