#pragma once
#include "Core/SmallVector.h"
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

class SymbolBigMap;

class SymbolMap : public Symbol
{
    struct Entry
    {
        Symbol*       head = nullptr;
        IdentifierRef key  = IdentifierRef::invalid();
    };

    std::atomic<SymbolBigMap*> big_ = nullptr;

    static constexpr uint32_t    SMALL_CAP = 8;
    std::array<Entry, SMALL_CAP> small_;
    mutable std::shared_mutex    mutex_;
    uint32_t                     smallSize_ = 0;

    Entry*        smallFind(IdentifierRef key);
    const Entry*  smallFind(IdentifierRef key) const;
    SymbolBigMap* buildBig(TaskContext& ctx) const;

public:
    explicit SymbolMap(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags);

    bool empty() const noexcept { return smallSize_ == 0 && big_ == nullptr; }

    Symbol* addSymbol(TaskContext& ctx, Symbol* symbol, bool acceptHomonyms);
    Symbol* addSingleSymbol(TaskContext& ctx, Symbol* symbol);
    Symbol* addSingleSymbolOrError(Sema& sema, Symbol* symbol);
    void    lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const;
};

SWC_END_NAMESPACE()
