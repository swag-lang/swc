#pragma once

SWC_BEGIN_NAMESPACE()

class TaskContext;

enum class SymbolKind : uint8_t
{
    Invalid,
    Namespace,
    Constant,
};

class Symbol
{
    IdentifierRef idRef_;
    SymbolKind    kind_        = SymbolKind::Invalid;
    Symbol*       nextHomonym_ = nullptr;

public:
    explicit Symbol(const TaskContext& ctx, SymbolKind kind, IdentifierRef idRef) :
        idRef_(idRef),
        kind_(kind)
    {
    }

    SymbolKind    kind() const { return kind_; }
    IdentifierRef idRef() const { return idRef_; }
    Symbol*       nextHomonym() const noexcept { return nextHomonym_; }
    void          setNextHomonym(Symbol* next) noexcept { nextHomonym_ = next; }

    std::string_view name(const TaskContext& ctx) const;
};

SWC_END_NAMESPACE()
