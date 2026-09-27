#pragma once
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace SymbolOrder
{
    inline bool beforeToken(const Symbol* left, const Symbol* right)
    {
        SWC_ASSERT(left);
        SWC_ASSERT(right);
        return left->tokRef().get() < right->tokRef().get();
    }
}

SWC_END_NAMESPACE();
