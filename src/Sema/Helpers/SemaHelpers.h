#pragma once
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/Symbol.Variable.h"
#include "Sema/Symbol/SymbolMap.h"

SWC_BEGIN_NAMESPACE();

namespace SemaHelpers
{
    void handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym);

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

        handleSymbolRegistration(sema, symbolMap, sym);
        return *sym;
    }

    inline IdentifierRef getUniqueIdentifier(Sema& sema, const std::string_view& name)
    {
        const uint32_t id = sema.ctx().compiler().atomicId().fetch_add(1);
        return sema.idMgr().addIdentifier(std::format("{}_{}", name, id));
    }

    template<typename T>
    T& registerUniqueSymbol(Sema& sema, const AstNode& node, const std::string_view& name)
    {
        auto&               ctx    = sema.ctx();
        const IdentifierRef idRef  = getUniqueIdentifier(sema, name);
        const SymbolFlags   flags  = sema.frame().flagsForCurrentAccess();
        SymbolMap*          symMap = SemaFrame::currentSymMap(sema);

        T* sym = Symbol::make<T>(ctx, &node, node.tokRef(), idRef, flags);
        symMap->addSymbol(ctx, sym, true);
        sema.setSymbol(sema.curNodeRef(), sym);

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

SWC_END_NAMESPACE();
