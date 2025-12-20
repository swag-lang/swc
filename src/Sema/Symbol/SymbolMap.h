#pragma once
#include "Core/SmallVector.h"
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

class BigMap;

class SymbolMap : public Symbol
{
    struct Entry
    {
        Symbol*       head = nullptr;
        IdentifierRef key  = IdentifierRef::invalid();
    };

    std::atomic<BigMap*> big_{nullptr};

    static constexpr uint32_t    SMALL_CAP = 8;
    std::array<Entry, SMALL_CAP> small_;
    mutable std::shared_mutex    mutex_;
    uint32_t                     smallSize_ = 0;

    Entry*       smallFind(IdentifierRef key);
    const Entry* smallFind(IdentifierRef key) const;
    BigMap*      buildBig(TaskContext& ctx) const;

public:
    explicit SymbolMap(const TaskContext& ctx, const AstNode* decl, SymbolKind kind, IdentifierRef idRef, SymbolFlags flags);

    void addSymbol(TaskContext& ctx, Symbol* symbol);
    void lookup(IdentifierRef idRef, SmallVector<Symbol*>& out) const;
};

SWC_END_NAMESPACE()
