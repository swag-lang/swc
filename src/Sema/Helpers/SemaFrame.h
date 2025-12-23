#pragma once
#include "Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE()

class SymbolEnum;

class SemaFrame
{
    SymbolAccess                  defaultAccess_ = SymbolAccess::Private;
    std::optional<SymbolAccess>   currentAccess_;
    SmallVector<IdentifierRef, 8> nsPath_;

public:
    std::span<const IdentifierRef> nsPath() const { return nsPath_; }
    void                           pushNs(IdentifierRef id) { nsPath_.push_back(id); }
    void                           popNs() { nsPath_.pop_back(); }

    SymbolAccess defaultAccess() const { return defaultAccess_; }
    void         setDefaultAccess(SymbolAccess access) { defaultAccess_ = access; }
    SymbolAccess currentAccess() const { return currentAccess_.value_or(defaultAccess_); }
    void         setCurrentAccess(SymbolAccess access) { currentAccess_ = access; }

    static SymbolAccess currentAccess(Sema& sema);
    static SymbolMap*   currentSymMap(Sema& sema);
};

SWC_END_NAMESPACE()
