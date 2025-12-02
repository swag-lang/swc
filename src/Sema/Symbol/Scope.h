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
    Scope*     parent_ = nullptr;
    ScopeFlags flags_  = ScopeFlagsE::Zero;
    SymbolMap* symMap_ = nullptr;

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
    void             setSymMap(SymbolMap& symMap) { symMap_ = &symMap; }
    SymbolMap&       symMap() { return *symMap_; }
    const SymbolMap& symMap() const { return *symMap_; }
};

SWC_END_NAMESPACE()
