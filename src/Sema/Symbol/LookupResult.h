#pragma once
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE()

class Symbol;

class LookupResult
{
    SmallVector<Symbol*> symbols_;

public:
    void                  clear() { symbols_.clear(); }
    SmallVector<Symbol*>& symbols() { return symbols_; }
    bool                  empty() const { return symbols_.empty(); }
    size_t                count() const { return symbols_.size(); }
    Symbol*               first() const { return symbols_.front(); }

    bool isFullComplete() const
    {
        for (const auto sym : symbols_)
        {
            if (!sym->isFullComplete())
                return false;
        }

        return true;
    }
};

SWC_END_NAMESPACE()
