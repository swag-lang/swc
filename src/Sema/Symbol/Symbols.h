#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

class SymbolModule : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Module;

    explicit SymbolModule(const TaskContext& ctx) :
        SymbolMap(ctx, SymbolKind::Module, IdentifierRef::invalid())
    {
    }
};

class SymbolNamespace : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Namespace;

    explicit SymbolNamespace(const TaskContext& ctx, IdentifierRef idRef) :
        SymbolMap(ctx, SymbolKind::Namespace, idRef)
    {
    }
};

class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::Constant;

    explicit SymbolConstant(const TaskContext& ctx, IdentifierRef idRef, ConstantRef cstRef) :
        Symbol(ctx, SymbolKind::Constant, idRef),
        cstRef_(cstRef)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
};

SWC_END_NAMESPACE()
