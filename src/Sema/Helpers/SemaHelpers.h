#pragma once
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE()

namespace SemaHelpers
{
    template<typename T>
    T* declareNamedSymbol(Sema& sema, const AstNode& node, TokenRef tokNameRef)
    {
        auto& ctx = sema.ctx();

        const IdentifierRef idRef     = sema.idMgr().addIdentifier(ctx, node.srcViewRef(), tokNameRef);
        const SymbolFlags   flags     = sema.frame().flagsForCurrentAccess();
        SymbolMap*          symbolMap = SemaFrame::currentSymMap(sema);

        T* sym = Symbol::make<T>(ctx, node.srcViewRef(), tokNameRef, idRef, flags);
        symbolMap->addSymbol(ctx, sym, true);
        sym->registerCompilerIf(sema);
        sema.setSymbol(sema.curNodeRef(), sym);

        return sym;
    }
};

SWC_END_NAMESPACE()
