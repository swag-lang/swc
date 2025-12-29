#pragma once
#include "AttributeList.h"
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
    SymbolAccess                  access_ = SymbolAccess::Private;
    AttributeList                 attributes_;
    SmallVector<IdentifierRef, 8> nsPath_;
    SemaCompilerIf*               compilerIf_ = nullptr;

public:
    std::span<const IdentifierRef> nsPath() const { return nsPath_; }
    void                           pushNs(IdentifierRef id) { nsPath_.push_back(id); }
    void                           popNs() { nsPath_.pop_back(); }

    SymbolAccess access() const { return access_; }
    void         setAccess(SymbolAccess access) { access_ = access; }

    AttributeList&       attributes() { return attributes_; }
    const AttributeList& attributes() const { return attributes_; }

    SemaCompilerIf* compilerIf() const { return compilerIf_; }
    void            setCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }

    static SymbolMap*   currentSymMap(Sema& sema);
};

SWC_END_NAMESPACE()
