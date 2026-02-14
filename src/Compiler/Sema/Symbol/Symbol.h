#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Core/AttributeList.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class SymbolMap;

enum class SymbolAccess : uint8_t
{
    Invalid,
    Public,   // Visible in the module and from outside the module
    Private,  // Visible only inside the module (across files)
    Internal, // Visible only in the file it is declared
};

enum class SymbolKind : uint8_t
{
    Invalid,
    Module,
    Namespace,
    Constant,
    Variable,
    Enum,
    EnumValue,
    Attribute,
    Struct,
    Interface,
    Alias,
    Function,
    Impl,
};

enum class SymbolFlagsE : uint8_t
{
    Zero             = 0,
    Public           = 1 << 0,
    Declared         = 1 << 1,
    SemaCompleted    = 1 << 2,
    Ignored          = 1 << 3,
    Typed            = 1 << 4,
    CodeGenCompleted = 1 << 5,
};

using SymbolFlags = AtomicEnumFlags<SymbolFlagsE>;

class Symbol
{
public:
    explicit Symbol(const AstNode* decl, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags) :
        decl_(decl),
        idRef_(idRef),
        tokRef_(tokRef),
        kind_(kind),
        flags_(flags)
    {
    }

    SymbolKind      kind() const noexcept { return kind_; }
    IdentifierRef   idRef() const noexcept { return idRef_; }
    void            setIdRef(IdentifierRef idRef) noexcept { idRef_ = idRef; }
    TypeRef         typeRef() const noexcept { return typeRef_; }
    void            setTypeRef(TypeRef typeRef) noexcept { typeRef_ = typeRef; }
    const TypeInfo& type(TaskContext& ctx) const { return ctx.typeMgr().get(typeRef_); }
    const AstNode*  decl() const noexcept { return decl_; }
    SourceCodeRef   codeRef() const noexcept { return SourceCodeRef{decl_->srcViewRef(), tokRef_}; }
    SourceCodeRange codeRange(TaskContext& ctx) const noexcept;
    SourceViewRef   srcViewRef() const noexcept { return decl_->srcViewRef(); }
    TokenRef        tokRef() const noexcept { return tokRef_; }
    Utf8            toFamily() const;

    SymbolFlags flags() const noexcept { return flags_; }
    bool        hasFlag(SymbolFlagsE flag) const noexcept { return flags_.has(flag); }
    void        addFlag(SymbolFlagsE fl) { flags_.add(fl); }
    bool        isPublic() const noexcept { return flags_.has(SymbolFlagsE::Public); }

    bool isTyped() const noexcept { return flags_.has(SymbolFlagsE::Typed); }
    void setTyped(TaskContext& ctx);
    bool isSemaCompleted() const noexcept { return flags_.has(SymbolFlagsE::SemaCompleted); }
    void setSemaCompleted(TaskContext& ctx);
    bool isCodeGenCompleted() const noexcept { return flags_.has(SymbolFlagsE::CodeGenCompleted); }
    void setCodeGenCompleted(TaskContext& ctx);
    bool isDeclared() const noexcept { return flags_.has(SymbolFlagsE::Declared); }
    void setDeclared(TaskContext& ctx);
    bool isIgnored() const noexcept { return flags_.has(SymbolFlagsE::Ignored); }
    void setIgnored(TaskContext& ctx) noexcept;

    uint8_t extraFlags() const noexcept { return extraFlags_; }

    const AttributeList& attributes() const { return attributes_; }
    AttributeList&       attributes() { return attributes_; }
    void                 setAttributes(const AttributeList& attrs) { attributes_ = attrs; }

    void registerCompilerIf(Sema& sema);
    void registerAttributes(Sema& sema);

    SymbolMap*       ownerSymMap() noexcept { return ownerSymMap_; }
    const SymbolMap* ownerSymMap() const noexcept { return ownerSymMap_; }
    void             setOwnerSymMap(SymbolMap* symMap) noexcept { ownerSymMap_ = symMap; }

    bool is(SymbolKind kind) const noexcept { return kind_ == kind; }
    bool isNamespace() const noexcept { return kind_ == SymbolKind::Namespace; }
    bool isVariable() const noexcept { return kind_ == SymbolKind::Variable; }
    bool isConstant() const noexcept { return kind_ == SymbolKind::Constant; }
    bool isEnum() const noexcept { return kind_ == SymbolKind::Enum; }
    bool isEnumValue() const noexcept { return kind_ == SymbolKind::EnumValue; }
    bool isStruct() const noexcept { return kind_ == SymbolKind::Struct; }
    bool isInterface() const noexcept { return kind_ == SymbolKind::Interface; }
    bool isAttribute() const noexcept { return kind_ == SymbolKind::Attribute; }
    bool isModule() const noexcept { return kind_ == SymbolKind::Module; }
    bool isAlias() const noexcept { return kind_ == SymbolKind::Alias; }
    bool isFunction() const noexcept { return kind_ == SymbolKind::Function; }
    bool isImpl() const noexcept { return kind_ == SymbolKind::Impl; }

    bool isSymMap() const noexcept { return isNamespace() || isModule() || isEnum() || isStruct() || isInterface() || isImpl(); }
    bool isType() const;
    bool isValueExpr() const noexcept { return isVariable() || isConstant() || isEnumValue(); }
    bool inSwagNamespace(const TaskContext& ctx) const noexcept;
    bool acceptOverloads() const noexcept { return isFunction() || isAttribute(); }
    bool deepCompare(const Symbol* other) const noexcept;

    Symbol* nextHomonym() const noexcept { return nextHomonym_; }
    void    setNextHomonym(Symbol* next) noexcept { nextHomonym_ = next; }

    std::string_view name(const TaskContext& ctx) const;
    Utf8             getFullScopedName(const TaskContext& ctx) const;
    void             appendFullScopedName(const TaskContext& ctx, Utf8& out) const;
    const TypeInfo&  typeInfo(const TaskContext& ctx) const;

    template<typename T>
    T* safeCast()
    {
        return kind_ == T::K ? static_cast<T*>(this) : nullptr;
    }

    template<typename T>
    const T* safeCast() const
    {
        return kind_ == T::K ? static_cast<const T*>(this) : nullptr;
    }

    template<typename T>
    T& cast()
    {
        SWC_ASSERT(kind_ == T::K);
        return *static_cast<T*>(this);
    }

    template<typename T>
    const T& cast() const
    {
        SWC_ASSERT(kind_ == T::K);
        return *static_cast<const T*>(this);
    }

    SymbolMap* asSymMap()
    {
        SWC_ASSERT(isSymMap());
        return reinterpret_cast<SymbolMap*>(this);
    }

    const SymbolMap* asSymMap() const
    {
        SWC_ASSERT(isSymMap());
        return reinterpret_cast<const SymbolMap*>(this);
    }

    template<typename T>
    static T* make(TaskContext& ctx, const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, SymbolFlags flags)
    {
#if SWC_HAS_STATS
        Stats::get().numSymbols.fetch_add(1);
        Stats::get().memSymbols.fetch_add(sizeof(T), std::memory_order_relaxed);
#endif

        return ctx.compiler().allocate<T>(decl, tokRef, idRef, flags);
    }

protected:
    Symbol*              nextHomonym_ = nullptr;
    SymbolMap*           ownerSymMap_ = nullptr;
    const AstNode*       decl_        = nullptr;
    AttributeList        attributes_;
    IdentifierRef        idRef_      = IdentifierRef::invalid();
    TypeRef              typeRef_    = TypeRef::invalid();
    TokenRef             tokRef_     = TokenRef::invalid();
    SymbolKind           kind_       = SymbolKind::Invalid;
    SymbolFlags          flags_      = SymbolFlagsE::Zero;
    std::atomic<uint8_t> extraFlags_ = 0;
};

template<typename BASE, SymbolKind K, typename E = void>
struct SymbolExtraFlagsT : BASE
{
    using FlagsE    = E;
    using FlagsType = std::conditional_t<std::is_void_v<E>, uint8_t, EnumFlags<E>>;

    static_assert(sizeof(FlagsType) == sizeof(uint8_t), "Extra flags storage expects one-byte flag wrappers");

    explicit SymbolExtraFlagsT(const AstNode* decl, TokenRef tokRef, IdentifierRef idRef, const SymbolFlags& flags) :
        BASE(decl, tokRef, K, idRef, flags)
    {
    }

    FlagsType& extraFlags()
    {
        if constexpr (!std::is_void_v<E>)
            return *reinterpret_cast<FlagsType*>(&this->extraFlags_);
        else
            return this->extraFlags_;
    }

    const FlagsType& extraFlags() const
    {
        if constexpr (!std::is_void_v<E>)
            return *reinterpret_cast<const FlagsType*>(&this->extraFlags_);
        else
            return this->extraFlags_;
    }

    template<typename T = E>
    bool hasExtraFlag(T flag) const
    {
        if constexpr (!std::is_void_v<E>)
            return extraFlags().has(flag);
        return false;
    }

    template<typename T = E>
    void addExtraFlag(T flag)
    {
        if constexpr (!std::is_void_v<E>)
            extraFlags().add(flag);
    }

    template<typename T = E>
    void removeExtraFlag(T flag)
    {
        if constexpr (!std::is_void_v<E>)
            extraFlags().remove(flag);
    }
};

template<SymbolKind K, typename E = void>
struct SymbolT : SymbolExtraFlagsT<Symbol, K, E>
{
    using SymbolExtraFlagsT<Symbol, K, E>::SymbolExtraFlagsT;
};

SWC_END_NAMESPACE();
