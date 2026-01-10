#pragma once
#include "Sema/Core/AttributeList.h"
#include "Sema/Symbol/Symbol.Struct.h"
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

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
public:
    std::span<const IdentifierRef> nsPath() const { return nsPath_; }
    void                           pushNs(IdentifierRef id) { nsPath_.push_back(id); }
    void                           popNs() { nsPath_.pop_back(); }

    SymbolAccess         access() const { return access_; }
    void                 setAccess(SymbolAccess access) { access_ = access; }
    AttributeList&       attributes() { return attributes_; }
    const AttributeList& attributes() const { return attributes_; }
    SemaCompilerIf*      compilerIf() const { return compilerIf_; }
    void                 setCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }
    SymbolImpl*          impl() const { return impl_; }
    void                 setImpl(SymbolImpl* impl) { impl_ = impl; }

    static SymbolMap* currentSymMap(Sema& sema);
    SymbolFlags       flagsForCurrentAccess() const;

private:
    SymbolAccess                  access_ = SymbolAccess::Private;
    AttributeList                 attributes_;
    SmallVector<IdentifierRef, 8> nsPath_;
    SemaCompilerIf*               compilerIf_ = nullptr;
    SymbolImpl*                   impl_       = nullptr;
};

SWC_END_NAMESPACE();
