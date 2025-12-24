#include "pch.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/SymbolBigMap.h"

SWC_BEGIN_NAMESPACE()

SymbolMap::SymbolMap(SourceViewRef srcViewRef, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags) :
    Symbol(srcViewRef, tokRef, kind, idRef, flags)
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

SymbolBigMap* SymbolMap::buildBig(TaskContext& ctx) const
{
    SWC_ASSERT(big_.load(std::memory_order_relaxed) == nullptr);

    SymbolBigMap* newBig = ctx.compiler().allocate<SymbolBigMap>();
#if SWC_HAS_STATS
    Stats::get().memSymbols.fetch_add(sizeof(SymbolBigMap), std::memory_order_relaxed);
#endif

    for (uint32_t i = 0; i < smallSize_; ++i)
    {
        Symbol* cur = small_[i].head;
        while (cur)
        {
            Symbol* next = cur->nextHomonym();
            newBig->addSymbol(ctx, cur, true, false);
            cur = next;
        }
    }

    return newBig;
}

void SymbolMap::lookup(IdentifierRef idRef, SmallVector<const Symbol*>& out) const
{
    if (const SymbolBigMap* big = big_.load(std::memory_order_acquire))
    {
        big->lookup(idRef, out);
        return;
    }

    std::shared_lock lk(mutex_);

    if (const SymbolBigMap* big = big_.load(std::memory_order_acquire))
    {
        lk.unlock();
        big->lookup(idRef, out);
        return;
    }

    out.clear();

    const Symbol* head = nullptr;
    if (const Entry* e = smallFind(idRef))
        head = e->head;
    for (const Symbol* cur = head; cur; cur = cur->nextHomonym())
        out.push_back(cur);
}

Symbol* SymbolMap::addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms)
{
    SWC_ASSERT(symbol != nullptr);

    if (SymbolBigMap* big = big_.load(std::memory_order_acquire))
    {
        Symbol* insertedSym = big->addSymbol(ctx, symbol, acceptHomonyms, true);
        if (insertedSym == symbol)
            symbol->setSymMap(this);
        return insertedSym;
    }

    SymbolBigMap* big = nullptr;

    {
        std::unique_lock lk(mutex_);

        big = big_.load(std::memory_order_acquire);
        if (!big)
        {
            const IdentifierRef idRef = symbol->idRef();

            if (Entry* e = smallFind(idRef))
            {
                if (!acceptHomonyms)
                    return e->head;
                symbol->setSymMap(this);
                symbol->setNextHomonym(e->head);
                e->head = symbol;
                ctx.compiler().notifySymbolAdded();
                return symbol;
            }

            if (smallSize_ < SMALL_CAP)
            {
                symbol->setSymMap(this);
                symbol->setNextHomonym(nullptr);
                small_[smallSize_++] = Entry{.head = symbol, .key = idRef};
                ctx.compiler().notifySymbolAdded();
                return symbol;
            }

            SymbolBigMap* newBig = buildBig(ctx);
            big_.store(newBig, std::memory_order_release);
            big = newBig;
        }
    }

    Symbol* insertedSym = big->addSymbol(ctx, symbol, acceptHomonyms, true);
    if (insertedSym == symbol)
        symbol->setSymMap(this);
    return insertedSym;
}

Symbol* SymbolMap::addSingleSymbolOrError(Sema& sema, Symbol* symbol)
{
    auto&   ctx         = sema.ctx();
    Symbol* insertedSym = addSymbol(ctx, symbol, true);
    if (symbol->nextHomonym())
        SemaError::raiseSymbolAlreadyDefined(sema, symbol, symbol->nextHomonym());
    return insertedSym;
}

Symbol* SymbolMap::addSingleSymbol(TaskContext& ctx, Symbol* symbol)
{
    return addSymbol(ctx, symbol, false);
}

SWC_END_NAMESPACE()
