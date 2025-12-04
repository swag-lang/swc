#pragma once
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE()

class Symbol;

class LookupResult
{
    SmallVector<Symbol*> symbols_;

public:
    void clear()
    {
        symbols_.clear();
    }

    SmallVector<Symbol*>& symbols() { return symbols_; }
    bool                  empty() const { return symbols_.empty(); }
};

SWC_END_NAMESPACE()
