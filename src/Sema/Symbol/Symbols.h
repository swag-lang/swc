#pragma once
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

class SymbolModule : public SymbolMap
{
public:
    SymbolModule(std::string_view name, uint32_t hash) :
        SymbolMap(SymbolKind::Module)
    {
    }
};

class SymbolNamespace : public SymbolMap
{
public:
    SymbolNamespace(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef, ConstantRef cstRef) :
        SymbolMap(ctx, SymbolKind::Namespace, srcViewRef, tokRef)
    {
    }
};

class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    explicit SymbolConstant(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef, ConstantRef cstRef) :
        Symbol(ctx, SymbolKind::Constant, srcViewRef, tokRef),
        cstRef_(cstRef)
    {
    }
};

SWC_END_NAMESPACE()
