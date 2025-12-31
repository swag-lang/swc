#pragma once
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

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
class SymbolAttribute : public Symbol
{
    AttributeFlags attributes_ = AttributeFlagsE::Zero;

public:
    static constexpr auto K = SymbolKind::Attribute;

    explicit SymbolAttribute(SourceViewRef srcViewRef, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(srcViewRef, tokRef, K, idRef, flags)
    {
    }

    AttributeFlags attributeFlags() const { return attributes_; }
    void           setAttributeFlags(AttributeFlags attr) { attributes_ = attr; }
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

    TypeRef underlyingTypeRef() const { return underlyingTypeRef_; }
    void    setUnderlyingTypeRef(TypeRef ref) { underlyingTypeRef_ = ref; }

    ApsInt&       nextValue() { return nextValue_; }
    const ApsInt& nextValue() const { return nextValue_; }
    void          setNextValue(const ApsInt& value) { nextValue_ = value; }
    bool          hasNextValue() const { return hasFlag(SymbolFlagsE::EnumHasNextValue); }
    void          setHasNextValue() { addFlag(SymbolFlagsE::EnumHasNextValue); }

    bool isEnumFlags() const { return attributes().hasFlag(AttributeFlagsE::EnumFlags); }
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

// -----------------------------------------------------------------------------
class SymbolStruct : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Struct;

    explicit SymbolStruct(SourceViewRef srcViewRef, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(srcViewRef, tokRef, K, idRef, flags)
    {
    }
};

// -----------------------------------------------------------------------------
class SymbolInterface : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Interface;

    explicit SymbolInterface(SourceViewRef srcViewRef, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(srcViewRef, tokRef, K, idRef, flags)
    {
    }
};

SWC_END_NAMESPACE()
