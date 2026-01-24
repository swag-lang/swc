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

    std::span<const TypeRef> typeHints() const { return typeHints_.span(); }
    TypeRef                  topTypeHint() const { return typeHints_.empty() ? TypeRef::invalid() : typeHints_.back(); }
    void                     pushTypeHint(TypeRef type)
    {
        if (type.isValid())
            typeHints_.push_back(type);
    }
    void popTypeHint()
    {
        if (!typeHints_.empty())
            typeHints_.pop_back();
    }

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
    SmallVector<TypeRef, 2>       typeHints_;
};

SWC_END_NAMESPACE();
