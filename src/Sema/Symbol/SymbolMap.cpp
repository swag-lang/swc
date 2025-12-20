#include "pch.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Sema/Symbol/BigMap.h"

SWC_BEGIN_NAMESPACE()

SymbolMap::SymbolMap(const TaskContext& ctx, const AstNode* decl, SymbolKind kind, IdentifierRef idRef, SymbolFlags flags) :
    Symbol(ctx, decl, kind, idRef, flags)
{
}

SymbolMap::Entry* SymbolMap::smallFind(IdentifierRef key)
{
    for (uint32_t i = 0; i < smallSize_; ++i)
        if (small_[i].key == key)
            return &small_[i];
    return nullptr;
}

const SymbolMap::Entry* SymbolMap::smallFind(IdentifierRef key) const
{
    for (uint32_t i = 0; i < smallSize_; ++i)
        if (small_[i].key == key)
            return &small_[i];
    return nullptr;
}

BigMap* SymbolMap::buildBig(TaskContext& ctx) const
{
    SWC_ASSERT(big_.load(std::memory_order_relaxed) == nullptr);

    BigMap* newBig = ctx.compiler().allocate<BigMap>();
#if SWC_HAS_STATS
    Stats::get().memSymbols.fetch_add(sizeof(BigMap), std::memory_order_relaxed);
#endif

    for (uint32_t i = 0; i < smallSize_; ++i)
    {
        Symbol* cur = small_[i].head;
        while (cur)
        {
            Symbol* next = cur->nextHomonym();
            newBig->addSymbol(ctx, cur, false);
            cur = next;
        }
    }

    return newBig;
}

void SymbolMap::lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const
{
    if (const BigMap* big = big_.load(std::memory_order_acquire))
    {
        big->lookup(idRef, out);
        return;
    }

    std::shared_lock lk(mutex_);

    if (const BigMap* big = big_.load(std::memory_order_acquire))
    {
        lk.unlock();
        big->lookup(idRef, out);
        return;
    }

    out.clear();

    Symbol* head = nullptr;
    if (const Entry* e = smallFind(idRef))
        head = e->head;
    for (Symbol* cur = head; cur; cur = cur->nextHomonym())
        out.push_back(cur);
}

void SymbolMap::addSymbol(TaskContext& ctx, Symbol* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    symbol->setSymMap(this);

    if (BigMap* big = big_.load(std::memory_order_acquire))
    {
        big->addSymbol(ctx, symbol);
        return;
    }

    BigMap* big = nullptr;

    {
        std::unique_lock lk(mutex_);

        big = big_.load(std::memory_order_acquire);
        if (!big)
        {
            const IdentifierRef idRef = symbol->idRef();

            if (Entry* e = smallFind(idRef))
            {
                symbol->setNextHomonym(e->head);
                e->head = symbol;
                ctx.compiler().notifySymbolAdded();
                return;
            }

            if (smallSize_ < SMALL_CAP)
            {
                symbol->setNextHomonym(nullptr);
                small_[smallSize_++] = Entry{.head = symbol, .key = idRef};
                ctx.compiler().notifySymbolAdded();
                return;
            }

            BigMap* newBig = buildBig(ctx);
            big_.store(newBig, std::memory_order_release);
            big = newBig;
        }
    }

    big->addSymbol(ctx, symbol);
}

SWC_END_NAMESPACE()
