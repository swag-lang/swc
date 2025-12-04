#pragma once

SWC_BEGIN_NAMESPACE()

class TaskContext;
class SymbolMap;

enum class SymbolKind : uint8_t
{
    Invalid,
    Namespace,
    Constant,
};

class Symbol
{
    IdentifierRef    idRef_;
    SymbolKind       kind_        = SymbolKind::Invalid;
    Symbol*          nextHomonym_ = nullptr;
    const SymbolMap* symMap_      = nullptr;

public:
    explicit Symbol(const TaskContext& ctx, SymbolKind kind, IdentifierRef idRef) :
        idRef_(idRef),
        kind_(kind)
    {
    }

    SymbolKind       kind() const { return kind_; }
    IdentifierRef    idRef() const { return idRef_; }
    const SymbolMap* symMap() const noexcept { return symMap_; }
    void             setSymMap(const SymbolMap* symMap) noexcept { symMap_ = symMap; }
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
