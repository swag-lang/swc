#pragma once
SWC_BEGIN_NAMESPACE()

enum class SymbolKind : uint8_t
{
    Invalid,
    Module,
    Namespace,
    Constant,
};

class Symbol
{
    std::string_view name_;
    uint32_t         hash_ = 0;
    SymbolKind       kind_ = SymbolKind::Invalid;

public:
    explicit Symbol(SymbolKind kind, std::string_view name, uint32_t hash) :
        name_(name),
        hash_(hash),
        kind_(kind)
    {
    }

    SymbolKind       kind() const { return kind_; }
    std::string_view name() const { return name_; }
};

SWC_END_NAMESPACE()
