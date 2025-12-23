#pragma once
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

class SymbolModule : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Module;

    explicit SymbolModule(const TaskContext& ctx) :
        SymbolMap(ctx, nullptr, K, IdentifierRef::invalid(), SymbolFlagsE::Zero)
    {
    }
};

class SymbolNamespace : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Namespace;

    explicit SymbolNamespace(const TaskContext& ctx, const AstNode* decl, IdentifierRef idRef, SymbolFlags flags) :
        SymbolMap(ctx, decl, K, idRef, flags)
    {
    }
};

class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::Constant;

    explicit SymbolConstant(const TaskContext& ctx, const AstNode* decl, IdentifierRef idRef, SymbolFlags flags) :
        Symbol(ctx, decl, K, idRef, flags)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
    void        setCstRef(ConstantRef cstRef) { cstRef_ = cstRef; }
};

class SymbolVariable : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Variable;

    explicit SymbolVariable(const TaskContext& ctx, const AstNode* decl, IdentifierRef idRef, SymbolFlags flags) :
        Symbol(ctx, decl, K, idRef, flags)
    {
    }
};

class SymbolEnum : public SymbolMap
{
    TypeRef underlyingTypeRef_ = TypeRef::invalid();
    ApsInt  nextValue_;

public:
    static constexpr auto K = SymbolKind::Enum;

    explicit SymbolEnum(const TaskContext& ctx, const AstNode* decl, IdentifierRef idRef, SymbolFlags flags) :
        SymbolMap(ctx, decl, K, idRef, flags)
    {
    }

    TypeRef       underlyingTypeRef() const { return underlyingTypeRef_; }
    void          setUnderlyingTypeRef(TypeRef ref) { underlyingTypeRef_ = ref; }
    ApsInt&       nextValue() { return nextValue_; }
    const ApsInt& nextValue() const { return nextValue_; }
    void          setNextValue(const ApsInt& value) { nextValue_ = value; }
    bool          hasNextValue() const { return hasFlag(SymbolFlagsE::EnumHasNextValue); }
    void          setHasNextValue() { addFlag(SymbolFlagsE::EnumHasNextValue); }
};

class SymbolEnumValue : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::EnumValue;

    explicit SymbolEnumValue(const TaskContext& ctx, const AstNode* decl, IdentifierRef idRef, SymbolFlags flags) :
        Symbol(ctx, decl, K, idRef, flags)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
    void        setCstRef(ConstantRef cstRef) { cstRef_ = cstRef; }
};

SWC_END_NAMESPACE()
