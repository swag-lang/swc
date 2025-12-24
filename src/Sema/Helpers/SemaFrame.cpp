#include "pch.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    SymbolMap* followNamespace(Sema& sema, SymbolMap* root, std::span<const IdentifierRef> nsPath)
    {
        SymbolMap* m = root;
        for (const IdentifierRef idRef : nsPath)
        {
            auto&   ctx = sema.ctx();
            auto*   ns  = Symbol::make<SymbolNamespace>(ctx, SourceViewRef::invalid(), TokenRef::invalid(), idRef, SymbolFlagsE::Zero);
            Symbol* res = m->addSingleSymbol(ctx, ns);
            SWC_ASSERT(res->isNamespace());
            m = res->asSymMap();
        }

        return m;
    }
}

SymbolAccess SemaFrame::currentAccess(Sema& sema)
{
    return sema.frame().currentAccess();
}

SymbolMap* SemaFrame::currentSymMap(Sema& sema)
{
    SymbolMap* symbolMap = sema.curSymMap();

    if (!sema.curScope().isTopLevel())
        return symbolMap;

    const SymbolAccess access = currentAccess(sema);

    SymbolMap* root = nullptr;
    if (access == SymbolAccess::Internal)
        root = &sema.semaInfo().fileNamespace();
    else
        root = &sema.semaInfo().moduleNamespace();

    return followNamespace(sema, root, sema.frame().nsPath());
}

SWC_END_NAMESPACE()
