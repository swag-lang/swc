#pragma once
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

// -----------------------------------------------------------------------------
class SymbolModule : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Module;

    explicit SymbolModule(const AstNode*, TokenRef, IdentifierRef, const SymbolFlags&) :
        SymbolMap(nullptr, TokenRef::invalid(), K, IdentifierRef::invalid(), SymbolFlagsE::Zero)
    {
    }
};

// -----------------------------------------------------------------------------
class SymbolNamespace : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Namespace;

    explicit SymbolNamespace(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }
};

// -----------------------------------------------------------------------------
class SymbolConstant : public Symbol
{
    ConstantRef cstRef_ = ConstantRef::invalid();

public:
    static constexpr auto K = SymbolKind::Constant;

    explicit SymbolConstant(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(decl, tokRef, K, idRef, flags)
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

    explicit SymbolAttribute(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(decl, tokRef, K, idRef, flags)
    {
    }

    AttributeFlags attributeFlags() const { return attributes_; }
    void           setAttributeFlags(AttributeFlags attr) { attributes_ = attr; }
};

// -----------------------------------------------------------------------------
class SymbolAlias : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Alias;

    explicit SymbolAlias(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(decl, tokRef, K, idRef, flags)
    {
    }
};

// -----------------------------------------------------------------------------
class SymbolVariable : public Symbol
{
public:
    static constexpr auto K = SymbolKind::Variable;

    explicit SymbolVariable(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        Symbol(decl, tokRef, K, idRef, flags)
    {
    }

    uint32_t offset() const { return offset_; }
    void     setOffset(uint32_t offset) { offset_ = offset; }

private:
    uint32_t offset_ = 0;
};

// -----------------------------------------------------------------------------
class SymbolEnum : public SymbolMap
{
    TypeRef underlyingTypeRef_ = TypeRef::invalid();
    ApsInt  nextValue_;

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

    bool     isEnumFlags() const { return attributes().hasFlag(AttributeFlagsE::EnumFlags); }
    uint64_t sizeOf(TaskContext& ctx) const { return underlyingType(ctx).sizeOf(ctx); }
};

// -----------------------------------------------------------------------------
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

// -----------------------------------------------------------------------------
class SymbolStruct : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Struct;

    explicit SymbolStruct(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }

    uint64_t                    sizeOf() const { return sizeInBytes_; }
    uint32_t                    alignment() const { return alignment_; }
    std::vector<Symbol*>&       fields() { return fields_; }
    const std::vector<Symbol*>& fields() const { return fields_; }
    Result                      canBeCompleted(Sema& sema) const;
    void                        computeLayout(Sema& sema);

private:
    std::vector<Symbol*> fields_;
    uint64_t             sizeInBytes_ = 0;
    uint32_t             alignment_   = 0;
};

// -----------------------------------------------------------------------------
class SymbolInterface : public SymbolMap
{
public:
    static constexpr auto K = SymbolKind::Interface;

    explicit SymbolInterface(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        SymbolMap(decl, tokRef, K, idRef, flags)
    {
    }
};

SWC_END_NAMESPACE()
