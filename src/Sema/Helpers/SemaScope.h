#pragma once

SWC_BEGIN_NAMESPACE()
class SymbolMap;

enum class SemaScopeFlagsE
{
    Zero     = 0,
    TopLevel = 1 << 0,
};
using SemaScopeFlags = EnumFlags<SemaScopeFlagsE>;

class SemaScope
{
    SemaScope*     parent_ = nullptr;
    SemaScopeFlags flags_  = SemaScopeFlagsE::Zero;
    SymbolMap*     symMap_ = nullptr;

public:
    SemaScope() = default;

    SemaScope(SemaScopeFlags flags, SemaScope* parent) :
        parent_(parent),
        flags_(flags)
    {
    }

    SemaScope*       parent() const { return parent_; }
    SemaScopeFlags   flags() const { return flags_; }
    bool             has(SemaScopeFlags flag) const { return flags_.has(flag); }
    void             setSymMap(SymbolMap* symMap) { symMap_ = symMap; }
    SymbolMap*       symMap() { return symMap_; }
    const SymbolMap* symMap() const { return symMap_; }
};

SWC_END_NAMESPACE()
