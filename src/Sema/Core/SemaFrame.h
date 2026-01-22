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

    SemaCompilerIf*  compilerIf() const { return compilerIf_; }
    void             setCompilerIf(SemaCompilerIf* ifc) { compilerIf_ = ifc; }
    SymbolImpl*      impl() const { return impl_; }
    void             setImpl(SymbolImpl* impl) { impl_ = impl; }
    SymbolInterface* interface() const { return interface_; }
    void             setInterface(SymbolInterface* itf) { interface_ = itf; }
    SymbolFunction*  function() const { return function_; }
    void             setFunction(SymbolFunction* func) { function_ = func; }
    TypeRef          typeHint() const { return typeHint_; }
    void             setTypeHint(TypeRef type) { typeHint_ = type; }

    static SymbolMap* currentSymMap(Sema& sema);
    SymbolFlags       flagsForCurrentAccess() const;

private:
    SymbolAccess                  access_ = SymbolAccess::Private;
    AttributeList                 attributes_;
    SmallVector<IdentifierRef, 8> nsPath_;
    SemaCompilerIf*               compilerIf_ = nullptr;
    SymbolImpl*                   impl_       = nullptr;
    SymbolInterface*              interface_  = nullptr;
    SymbolFunction*               function_   = nullptr;
    TypeRef                       typeHint_   = TypeRef::invalid();
};

SWC_END_NAMESPACE();
