#pragma once

SWC_BEGIN_NAMESPACE()
class SymbolMap;

enum class SemaScopeFlagsE
{
    Zero     = 0,
    TopLevel = 1 << 0,
    Type     = 1 << 1,
};
using SemaScopeFlags = EnumFlags<SemaScopeFlagsE>;

class SemaScope
{
public:
    SemaScope() = default;

    SemaScope(SemaScopeFlags flags, SemaScope* parent) :
        parent_(parent),
        flags_(flags)
    {
    }

    SemaScope*     parent() const { return parent_; }
    SemaScopeFlags flags() const { return flags_; }
    bool           hasFlag(SemaScopeFlags flag) const { return flags_.has(flag); }
    bool           isTopLevel() const { return hasFlag(SemaScopeFlagsE::TopLevel); }

    void             setSymMap(SymbolMap* symMap) { symMap_ = symMap; }
    SymbolMap*       symMap() { return symMap_; }
    const SymbolMap* symMap() const { return symMap_; }

    void addUsingSymMap(SymbolMap* symMap) { usingSymMaps_.push_back(symMap); }
    const SmallVector<SymbolMap*>& usingSymMaps() const { return usingSymMaps_; }

private:
    SemaScope*              parent_ = nullptr;
    SemaScopeFlags          flags_  = SemaScopeFlagsE::Zero;
    SymbolMap*              symMap_ = nullptr;
    SmallVector<SymbolMap*> usingSymMaps_;
};

SWC_END_NAMESPACE()
