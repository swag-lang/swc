#pragma once

// -----------------------------------------------------------------------------
class SymbolModule : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Module;

    explicit SymbolModule(SourceViewRef, TokenRef, IdentifierRef, const SymbolFlags&) :
        SymbolMap(SourceViewRef::invalid(), TokenRef::invalid(), K, IdentifierRef::invalid(), SymbolFlagsE::Zero)
    {
    }
};

// -----------------------------------------------------------------------------
class SymbolNamespace : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Namespace;

    explicit SymbolNamespace(SourceViewRef srcViewRef, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(srcViewRef, tokRef, K, idRef, flags)
    {
    }
};

// -----------------------------------------------------------------------------
class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::Constant;

    explicit SymbolConstant(SourceViewRef srcViewRef, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(srcViewRef, tokRef, K, idRef, flags)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
    void        setCstRef(ConstantRef cstRef) { cstRef_ = cstRef; }
};

// -----------------------------------------------------------------------------
class SymbolVariable : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Variable;

    explicit SymbolVariable(SourceViewRef srcViewRef, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(srcViewRef, tokRef, K, idRef, flags)
    {
    }
};

// -----------------------------------------------------------------------------
class SymbolEnum : public SymbolMap
{
    TypeRef underlyingTypeRef_ = TypeRef::invalid();
    ApsInt  nextValue_;

public:
    static constexpr auto K = SymbolKind::Enum;

    explicit SymbolEnum(SourceViewRef srcViewRef, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(srcViewRef, tokRef, K, idRef, flags)
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

// -----------------------------------------------------------------------------
class SymbolEnumValue : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::EnumValue;

    explicit SymbolEnumValue(SourceViewRef srcViewRef, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(srcViewRef, tokRef, K, idRef, flags)
    {
    }

    ConstantRef cstRef() const { return cstRef_; }
    void        setCstRef(ConstantRef cstRef) { cstRef_ = cstRef; }
};
