#pragma once
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE()

class Symbol;

class MatchResult
{
    SmallVector<const Symbol*> symbols_;

public:
    void                        clear() { symbols_.clear(); }
    SmallVector<const Symbol*>& symbols() { return symbols_; }
    bool                        empty() const { return symbols_.empty(); }
    size_t                      count() const { return symbols_.size(); }
    const Symbol*               first() const { return symbols_.front(); }
};

SWC_END_NAMESPACE()
