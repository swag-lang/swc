#pragma once

SWC_BEGIN_NAMESPACE()
class SymbolMap;

enum class ScopeFlagsE
{
    Zero     = 0,
    TopLevel = 1 << 0,
};
using ScopeFlags = EnumFlags<ScopeFlagsE>;

class Scope
{
    Scope*     parent_      = nullptr;
    ScopeFlags flags_       = ScopeFlagsE::Zero;
    SymbolMap* declContext_ = nullptr;

public:
    Scope() = default;

    Scope(ScopeFlags flags, Scope* parent) :
        parent_(parent),
        flags_(flags)
    {
    }

    Scope*           parent() const { return parent_; }
    ScopeFlags       flags() const { return flags_; }
    bool             has(ScopeFlags flag) const { return flags_.has(flag); }
    void             setDeclContext(SymbolMap& declContext) { declContext_ = &declContext; }
    SymbolMap&       declContext() { return *declContext_; }
    const SymbolMap& declContext() const { return *declContext_; }
};

SWC_END_NAMESPACE()
