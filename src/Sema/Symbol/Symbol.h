#pragma once
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Type/TypeInfo.h"

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
};

enum class SymbolFlagsE : uint8_t
{
    Zero = 0,
    Public,
    FullComplete,
};
using SymbolFlags = EnumFlags<SymbolFlagsE>;

class Symbol
{
    IdentifierRef idRef_       = IdentifierRef::invalid();
    TypeRef       typeRef_     = TypeRef::invalid();
    Symbol*       nextHomonym_ = nullptr;
    SymbolMap*    symMap_      = nullptr;
    SymbolKind    kind_        = SymbolKind::Invalid;
    SymbolFlags   flags_       = SymbolFlagsE::Zero;

public:
    explicit Symbol(const TaskContext& ctx, SymbolKind kind, IdentifierRef idRef, TypeRef typeRef, SymbolFlags flags) :
        idRef_(idRef),
        typeRef_(typeRef),
        kind_(kind)
    {
    }

    SymbolKind       kind() const { return kind_; }
    IdentifierRef    idRef() const { return idRef_; }
    TypeRef          typeRef() const { return typeRef_; }
    SymbolMap*       symMap() noexcept { return symMap_; }
    const SymbolMap* symMap() const noexcept { return symMap_; }
    void             setSymMap(SymbolMap* symMap) noexcept { symMap_ = symMap; }
    bool             is(SymbolKind kind) const noexcept { return kind_ == kind; }

    Symbol* nextHomonym() const noexcept { return nextHomonym_; }
    void    setNextHomonym(Symbol* next) noexcept { nextHomonym_ = next; }

    std::string_view name(const TaskContext& ctx) const;

    template<typename T>
    const T* safeCast() const
    {
        return kind_ == T::K ? static_cast<const T*>(this) : nullptr;
    }
};

SWC_END_NAMESPACE()
