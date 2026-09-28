#pragma once
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"

SWC_BEGIN_NAMESPACE();

namespace SemaGenericRootAlias
{
    inline SymbolStruct* resolve(Symbol* symbol)
    {
        // Only non-strict aliases preserve the generic root's specialization semantics.
        Symbol* current = symbol;
        while (current && current->isAlias())
        {
            auto& alias = current->cast<SymbolAlias>();
            if (alias.isStrict())
                return nullptr;

            const auto* next = alias.aliasedSymbol();
            if (!next || next == current)
                return nullptr;

            current = const_cast<Symbol*>(next);
        }

        if (!current || !current->isStruct())
            return nullptr;

        auto& st = current->cast<SymbolStruct>();
        return st.isGenericRoot() ? &st : nullptr;
    }
}

SWC_END_NAMESPACE();
