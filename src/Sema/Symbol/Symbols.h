#pragma once
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

class SymbolModule : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Module;

    explicit SymbolModule(const TaskContext& ctx) :
        SymbolMap(ctx, nullptr, SymbolKind::Module, IdentifierRef::invalid(), TypeRef::invalid(), SymbolFlagsE::Zero)
    {
    }
};

class SymbolNamespace : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Namespace;

    explicit SymbolNamespace(const TaskContext& ctx, const AstNode* decl, IdentifierRef idRef, SymbolFlags flags) :
        SymbolMap(ctx, decl, SymbolKind::Namespace, idRef, TypeRef::invalid(), flags)
    {
    }
};

class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::Constant;

    explicit SymbolConstant(const TaskContext& ctx, const AstNode* decl, IdentifierRef idRef, ConstantRef cstRef, SymbolFlags flags) :
        Symbol(ctx, decl, SymbolKind::Constant, idRef, ctx.cstMgr().get(cstRef).typeRef(), flags),
        cstRef_(cstRef)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
};

class SymbolVariable : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Variable;

    explicit SymbolVariable(const TaskContext& ctx, const AstNode* decl, IdentifierRef idRef, TypeRef typeRef, SymbolFlags flags) :
        Symbol(ctx, decl, SymbolKind::Variable, idRef, typeRef, flags)
    {
    }
};

class SymbolEnum : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Variable;

    explicit SymbolEnum(const TaskContext& ctx, AstNode* decl, IdentifierRef idRef, TypeRef typeRef, SymbolFlags flags) :
        SymbolMap(ctx, decl, SymbolKind::Enum, idRef, typeRef, flags)
    {
    }
};

SWC_END_NAMESPACE()
