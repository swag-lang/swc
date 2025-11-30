#pragma once
SWC_BEGIN_NAMESPACE()

enum class ScopeFlagsE
{
    Zero     = 0,
    TopLevel = 1 << 0,
};
using ScopeFlags = EnumFlags<ScopeFlagsE>;

class Scope
{
    Scope*     parent_ = nullptr;
    ScopeFlags flags_  = ScopeFlagsE::Zero;

public:
    Scope() = default;

    Scope(ScopeFlags flags, Scope* parent) :
        parent_(parent),
        flags_(flags)
    {
    }

    Scope*     parent() const { return parent_; }
    ScopeFlags flags() const { return flags_; }
};

SWC_END_NAMESPACE()
