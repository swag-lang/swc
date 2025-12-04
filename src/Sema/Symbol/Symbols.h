#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

class SymbolNamespace : public SymbolMap
{
public:
    SymbolNamespace(const TaskContext& ctx, IdentifierRef idRef) :
        SymbolMap(ctx, SymbolKind::Namespace, idRef)
    {
    }
};

class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    explicit SymbolConstant(const TaskContext& ctx, IdentifierRef idRef, ConstantRef cstRef) :
        Symbol(ctx, SymbolKind::Constant, idRef),
        cstRef_(cstRef)
    {
    }
};

SWC_END_NAMESPACE()
