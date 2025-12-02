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
    SourceViewRef srcViewRef_;
    TokenRef      tokRef_;
    SymbolKind    kind_ = SymbolKind::Invalid;

public:
    explicit Symbol(SymbolKind kind) :
        kind_(kind)
    {
    }

    explicit Symbol(const TaskContext& ctx, SymbolKind kind, SourceViewRef srcViewRef, TokenRef tokRef) :
        srcViewRef_(srcViewRef),
        tokRef_(tokRef),
        kind_(kind)
    {
    }

    SymbolKind       kind() const { return kind_; }
    std::string_view name(const TaskContext& ctx) const;
    uint32_t         crc(const TaskContext& ctx) const;
};

SWC_END_NAMESPACE()
