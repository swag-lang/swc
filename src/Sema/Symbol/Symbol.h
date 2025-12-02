#pragma once

SWC_BEGIN_NAMESPACE()

class TaskContext;

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
    explicit Symbol(SymbolKind kind) :
        kind_(kind)
    {
    }

    explicit Symbol(const TaskContext& ctx, SymbolKind kind, SourceViewRef srcViewRef, TokenRef tokRef);

    SymbolKind       kind() const { return kind_; }
    std::string_view name() const { return name_; }
};

SWC_END_NAMESPACE()
