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

        const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, node.srcViewRef(), tokNameRef);
        const SymbolFlags   flags = sema.frame().flagsForCurrentAccess();

        T*         sym       = Symbol::make<T>(ctx, &node, tokNameRef, idRef, flags);
        SymbolMap* symbolMap = SemaFrame::currentSymMap(sema);

        if (sema.curScope().isLocal())
            sema.curScope().addSymbol(sym);
        else
            symbolMap->addSymbol(ctx, sym, true);

        handleSymbolRegistration(sema, symbolMap, sym);
        sym->registerCompilerIf(sema);
        sema.setSymbol(sema.curNodeRef(), sym);

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
        auto&               ctx         = sema.ctx();
        const Utf8          privateName = Utf8("__") + Utf8(name);
        const IdentifierRef idRef       = getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();

        T* sym = Symbol::make<T>(ctx, &node, node.tokRef(), idRef, flags);

        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(sym);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            symMap->addSymbol(ctx, sym, true);
        }

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

    ConstantRef makeConstantLocation(Sema& sema, const AstNode& node);
    Result      extractConstantStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef);
}

SWC_END_NAMESPACE();
