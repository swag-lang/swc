#pragma once
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Parser/AstNode.h"
#include "Sema/Core/AttributeList.h"
#include "Sema/Type/TypeInfo.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

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
};

enum class SymbolFlagsE : uint8_t
{
    Zero              = 0,
    Public            = 1 << 0,
    Declared          = 1 << 1,
    Completed         = 1 << 2,
    Ignored           = 1 << 3,
    Typed             = 1 << 4,
    ExplicitUndefined = 1 << 5,

    // Specific per symbol kind
    EnumHasNextValue = 1 << 7,
};

using SymbolFlags = AtomicEnumFlags<SymbolFlagsE>;

class Symbol
{
public:
    explicit Symbol(const AstNode* decl, TokenRef tokRef, SymbolKind kind, IdentifierRef idRef, const SymbolFlags& flags) :
        idRef_(idRef),
        decl_(decl),
        tokRef_(tokRef),
        kind_(kind),
        flags_(flags)
    {
    }

    SymbolKind         kind() const noexcept { return kind_; }
    IdentifierRef      idRef() const noexcept { return idRef_; }
    TypeRef            typeRef() const noexcept { return typeRef_; }
    void               setTypeRef(TypeRef typeRef) noexcept { typeRef_ = typeRef; }
    const TypeInfo&    type(TaskContext& ctx) const { return ctx.typeMgr().get(typeRef_); }
    const AstNode*     decl() const noexcept { return decl_; }
    SourceViewRef      srcViewRef() const noexcept { return decl_->srcViewRef(); }
    TokenRef           tokRef() const noexcept { return tokRef_; }
    SourceCodeLocation loc(TaskContext& ctx) const noexcept;
    Utf8               toFamily() const;

    SymbolFlags flags() const noexcept { return flags_; }
    bool        hasFlag(SymbolFlagsE flag) const noexcept { return flags_.has(flag); }
    void        addFlag(SymbolFlagsE fl) { flags_.add(fl); }
    bool        isPublic() const noexcept { return flags_.has(SymbolFlagsE::Public); }

    bool isTyped() const noexcept { return flags_.has(SymbolFlagsE::Typed); }
    void setTyped(TaskContext& ctx);
    bool isCompleted() const noexcept { return flags_.has(SymbolFlagsE::Completed); }
    void setCompleted(TaskContext& ctx);
    bool isDeclared() const noexcept { return flags_.has(SymbolFlagsE::Declared); }
    void setDeclared(TaskContext& ctx);
    bool isIgnored() const noexcept { return flags_.has(SymbolFlagsE::Ignored); }
    void setIgnored(TaskContext& ctx) noexcept;

    const AttributeList& attributes() const { return attributes_; }
    AttributeList&       attributes() { return attributes_; }
    void                 setAttributes(const AttributeList& attrs) { attributes_ = attrs; }

    void registerCompilerIf(Sema& sema);
    void registerAttributes(Sema& sema);

    SymbolMap*       symMap() noexcept { return ownerSymMap_; }
    const SymbolMap* symMap() const noexcept { return ownerSymMap_; }
    void             setSymMap(SymbolMap* symMap) noexcept { ownerSymMap_ = symMap; }
    bool             isTopLevel() const noexcept { return ownerSymMap_ == nullptr; }

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

    bool isSymMap() const noexcept { return isNamespace() || isModule() || isEnum() || isStruct() || isInterface(); }
    bool isType() const;
    bool isValueExpr() const noexcept { return isVariable() || isConstant() || isEnumValue(); }
    bool isSwagNamespace(const TaskContext& ctx) const noexcept;

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

private:
    IdentifierRef  idRef_       = IdentifierRef::invalid();
    TypeRef        typeRef_     = TypeRef::invalid();
    Symbol*        nextHomonym_ = nullptr;
    SymbolMap*     ownerSymMap_ = nullptr;
    const AstNode* decl_        = nullptr;
    TokenRef       tokRef_      = TokenRef::invalid();
    SymbolKind     kind_        = SymbolKind::Invalid;
    SymbolFlags    flags_       = SymbolFlagsE::Zero;
    AttributeList  attributes_;
};

SWC_END_NAMESPACE()
