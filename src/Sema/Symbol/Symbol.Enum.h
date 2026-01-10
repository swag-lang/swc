#pragma once
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

class SymbolImpl;

class SymbolEnum : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Enum;

    explicit SymbolEnum(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }

    TypeRef         underlyingTypeRef() const { return underlyingTypeRef_; }
    const TypeInfo& underlyingType(TaskContext& ctx) const { return ctx.typeMgr().get(underlyingTypeRef()); }
    void            setUnderlyingTypeRef(TypeRef ref) { underlyingTypeRef_ = ref; }

    ApsInt&       nextValue() { return nextValue_; }
    const ApsInt& nextValue() const { return nextValue_; }
    void          setNextValue(const ApsInt& value) { nextValue_ = value; }
    bool          hasNextValue() const { return hasFlag(SymbolFlagsE::EnumHasNextValue); }
    void          setHasNextValue() { addFlag(SymbolFlagsE::EnumHasNextValue); }
    bool          computeNextValue(Sema& sema, SourceViewRef srcViewRef, TokenRef tokRef);

    void                     addImpl(SymbolImpl& symImpl);
    std::vector<SymbolImpl*> impls() const;

    bool     isEnumFlags() const { return attributes().hasFlag(AttributeFlagsE::EnumFlags); }
    uint64_t sizeOf(TaskContext& ctx) const { return underlyingType(ctx).sizeOf(ctx); }

private:
    TypeRef underlyingTypeRef_ = TypeRef::invalid();
    ApsInt  nextValue_;

    mutable std::shared_mutex mutexImpls_;
    std::vector<SymbolImpl*>  impls_;
};

class SymbolEnumValue : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::EnumValue;

    explicit SymbolEnumValue(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(decl, tokRef, K, idRef, flags)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
    void        setCstRef(ConstantRef cstRef) { cstRef_ = cstRef; }
};

SWC_END_NAMESPACE();
