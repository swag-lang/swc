#pragma once
#include "Core/SmallVector.h"

SWC_BEGIN_NAMESPACE()

class Symbol;

class LookupResult
{
    SmallVector<const Symbol*> symbols_;

public:
    void                        clear() { symbols_.clear(); }
    SmallVector<const Symbol*>& symbols() { return symbols_; }
    bool                        empty() const { return symbols_.empty(); }
    size_t                      count() const { return symbols_.size(); }
    const Symbol*               first() const { return symbols_.front(); }

    bool isComplete() const
    {
        for (const auto sym : symbols_)
        {
            if (!sym->isComplete())
                return false;
        }

        return true;
    }
};

SWC_END_NAMESPACE()
