#pragma once
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

namespace SemaHelpers
{
    template<typename T>
    T& registerSymbol(Sema& sema, const AstNode& node, TokenRef tokNameRef)
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

    template<typename T>
    void declareSymbol(Sema& sema, const T& node)
    {
        if (!sema.curScope().isTopLevel())
        {
            SWC_ASSERT(!sema.hasSymbol(sema.curNodeRef()));
            node.semaPreDecl(sema);
        }

        Symbol& sym = sema.symbolOf(sema.curNodeRef());
        sym.registerAttributes(sema);
        sym.setDeclared(sema.ctx());
    }
}

SWC_END_NAMESPACE()
