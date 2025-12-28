#pragma once
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

class SymbolEnum;

struct SemaCompilerIf
{
    std::vector<Symbol*> symbols;
    SemaCompilerIf*      parent = nullptr;

    void addSymbol(Symbol* sym)
    {
        for (auto* it = this; it; it = it->parent)
            it->symbols.push_back(sym);
    }
};

class SemaFrame
{
    SymbolAccess                  defaultAccess_ = SymbolAccess::Private;
    std::optional<SymbolAccess>   currentAccess_;
    SmallVector<IdentifierRef, 8> nsPath_;
    SemaCompilerIf*               compilerIf_ = nullptr;

public:
    std::span<const IdentifierRef> nsPath() const { return nsPath_; }
    void                           pushNs(IdentifierRef id) { nsPath_.push_back(id); }
    void                           popNs() { nsPath_.pop_back(); }

    SymbolAccess    defaultAccess() const { return defaultAccess_; }
    void            setDefaultAccess(SymbolAccess access) { defaultAccess_ = access; }
    SymbolAccess    currentAccess() const { return currentAccess_.value_or(defaultAccess_); }
    void            setCurrentAccess(SymbolAccess access) { currentAccess_ = access; }
    SemaCompilerIf* compilerIf() const { return compilerIf_; }
    void            setCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }

    static SymbolAccess currentAccess(Sema& sema);
    static SymbolMap*   currentSymMap(Sema& sema);
};

SWC_END_NAMESPACE()
