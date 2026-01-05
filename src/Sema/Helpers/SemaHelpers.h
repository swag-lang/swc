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

        if (const auto symStruct = symbolMap->safeCast<SymbolStruct>())
        {
            if (sym->isVariable())
                symStruct->addField(reinterpret_cast<SymbolVariable*>(sym));
        }

        if (const auto symAttr = symbolMap->safeCast<SymbolAttribute>())
        {
            if (sym->isVariable())
                symAttr->addParameter(reinterpret_cast<SymbolVariable*>(sym));
        }

        return *sym;
    }

    template<typename T>
    void declareSymbol(Sema& sema, const T& node)
    {
        const AstNodeRef curNodeRef = sema.curNodeRef();
        if (!sema.hasSymbol(curNodeRef))
            node.semaPreDecl(sema);
        Symbol& sym = sema.symbolOf(curNodeRef);
        sym.registerAttributes(sema);
        sym.setDeclared(sema.ctx());
    }
}

SWC_END_NAMESPACE()
