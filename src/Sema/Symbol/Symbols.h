#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

class SymbolModule : public SymbolMap
{
public:
    SymbolModule() :
        SymbolMap(SymbolKind::Module)
    {
    }
};

class SymbolNamespace : public SymbolMap
{
public:
    SymbolNamespace() :
        SymbolMap(SymbolKind::Namespace)
    {
    }
};

SWC_END_NAMESPACE()
