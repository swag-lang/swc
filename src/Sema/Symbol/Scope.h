#pragma once
SWC_BEGIN_NAMESPACE()

enum class ScopeKind
{
    Unknown = 0,
    Global,
    Module,
    Function,
    Block,
};

class Scope
{
    Scope*    parent_ = nullptr;
    ScopeKind kind_   = ScopeKind::Unknown;

public:
    Scope() = default;

    Scope(ScopeKind kind, Scope* parent) :
        parent_(parent),
        kind_(kind)
    {
    }

    Scope*    parent() const { return parent_; }
    ScopeKind kind() const { return kind_; }
};

SWC_END_NAMESPACE()
