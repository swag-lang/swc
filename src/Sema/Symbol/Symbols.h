#pragma once
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

class SymbolModule : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Module;

    explicit SymbolModule(const TaskContext& ctx) :
        SymbolMap(ctx, SymbolKind::Module, IdentifierRef::invalid(), TypeRef::invalid(), SymbolFlagsE::Zero)
    {
    }
};

class SymbolNamespace : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Namespace;

    explicit SymbolNamespace(const TaskContext& ctx, IdentifierRef idRef, SymbolFlags flags) :
        SymbolMap(ctx, SymbolKind::Namespace, idRef, TypeRef::invalid(), flags)
    {
    }
};

class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::Constant;

    explicit SymbolConstant(const TaskContext& ctx, IdentifierRef idRef, ConstantRef cstRef, SymbolFlags flags) :
        Symbol(ctx, SymbolKind::Constant, idRef, ctx.cstMgr().get(cstRef).typeRef(), flags),
        cstRef_(cstRef)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
};

class SymbolVariable : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Variable;

    explicit SymbolVariable(const TaskContext& ctx, IdentifierRef idRef, TypeRef typeRef, SymbolFlags flags) :
        Symbol(ctx, SymbolKind::Variable, idRef, typeRef, flags)
    {
    }
};

class SymbolEnum : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Variable;

    explicit SymbolEnum(const TaskContext& ctx, IdentifierRef idRef, TypeRef typeRef, SymbolFlags flags) :
        Symbol(ctx, SymbolKind::Enum, idRef, typeRef, flags)
    {
    }
};

SWC_END_NAMESPACE()
