#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

class SymbolModule : public SymbolMap
{
public:
    SymbolModule(std::string_view name, uint32_t hash) :
        SymbolMap(SymbolKind::Module, name, hash)
    {
    }
};

class SymbolNamespace : public SymbolMap
{
public:
    SymbolNamespace(std::string_view name, uint32_t hash) :
        SymbolMap(SymbolKind::Namespace, name, hash)
    {
    }
};

class SymbolConstant : public Symbol
{
public:
    explicit SymbolConstant(ConstantRef cstRef, std::string_view name, uint32_t hash) :
        Symbol(SymbolKind::Constant, name, hash),
        cstRef(cstRef)
    {
    }

    ConstantRef cstRef = ConstantRef::invalid();
};

SWC_END_NAMESPACE()
