#pragma once
SWC_BEGIN_NAMESPACE()

enum class SymbolKind
{
    Invalid = -1,
    Module,
    Namespace,
};

class Symbol
{
    SymbolKind kind_ = SymbolKind::Invalid;

public:
    explicit Symbol(SymbolKind kind) :
        kind_(kind)
    {
    }

    SymbolKind kind() const { return kind_; }
};

SWC_END_NAMESPACE()
