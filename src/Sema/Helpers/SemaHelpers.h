#pragma once
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

namespace SemaHelpers
{
    template<typename T>
    T& declareNamedSymbol(Sema& sema, const AstNode& node, TokenRef tokNameRef)
    {
        auto& ctx = sema.ctx();

        const IdentifierRef idRef     = sema.idMgr().addIdentifier(ctx, node.srcViewRef(), tokNameRef);
        const SymbolFlags   flags     = sema.frame().flagsForCurrentAccess();
        SymbolMap*          symbolMap = SemaFrame::currentSymMap(sema);

        T* sym = Symbol::make<T>(ctx, &node, tokNameRef, idRef, flags);
        symbolMap->addSymbol(ctx, sym, true);
        sym->registerCompilerIf(sema);
        sema.setSymbol(sema.curNodeRef(), sym);

        // Special case when adding a variable inside a struct
        if (const auto symStruct = symbolMap->safeCast<SymbolStruct>())
        {
            if (sym->isVariable())
                symStruct->fields().push_back(sym);
        }

        return *sym;
    }
};

SWC_END_NAMESPACE()
