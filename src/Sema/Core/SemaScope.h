#pragma once

SWC_BEGIN_NAMESPACE();
class SymbolMap;

enum class SemaScopeFlagsE
{
    Zero       = 0,
    TopLevel   = 1 << 0,
    Type       = 1 << 1,
    Parameters = 1 << 2,
    Local      = 1 << 3,
    Impl       = 1 << 4,
    Interface  = 1 << 5,
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
    void           setParent(SemaScope* parent) { parent_ = parent; }
    SemaScopeFlags flags() const { return flags_; }
    bool           hasFlag(SemaScopeFlags flag) const { return flags_.has(flag); }
    bool           isTopLevel() const { return hasFlag(SemaScopeFlagsE::TopLevel); }
    bool           isLocal() const { return hasFlag(SemaScopeFlagsE::Local); }
    bool           isImpl() const { return hasFlag(SemaScopeFlagsE::Impl); }
    bool           isInterface() const { return hasFlag(SemaScopeFlagsE::Interface); }
    bool           isType() const { return hasFlag(SemaScopeFlagsE::Type); }
    bool           isParameters() const { return hasFlag(SemaScopeFlagsE::Parameters); }

    void             setSymMap(SymbolMap* symMap) { symMap_ = symMap; }
    SymbolMap*       symMap() { return symMap_; }
    const SymbolMap* symMap() const { return symMap_; }

    void                           addUsingSymMap(SymbolMap* symMap) { usingSymMaps_.push_back(symMap); }
    const SmallVector<SymbolMap*>& usingSymMaps() const { return usingSymMaps_; }

private:
    SemaScope*              parent_ = nullptr;
    SemaScopeFlags          flags_  = SemaScopeFlagsE::Zero;
    SymbolMap*              symMap_ = nullptr;
    SmallVector<SymbolMap*> usingSymMaps_;
};

SWC_END_NAMESPACE();
