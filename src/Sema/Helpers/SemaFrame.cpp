#include "pch.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Core/Sema.h"
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

SymbolMap* SemaFrame::currentSymMap(Sema& sema)
{
    SymbolMap* symbolMap = sema.curSymMap();

    if (!sema.curScope().isTopLevel())
        return symbolMap;

    const SymbolAccess access = sema.frame().access();

    SymbolMap* root = nullptr;
    if (access == SymbolAccess::Internal)
        root = &sema.semaInfo().fileNamespace();
    else
        root = &sema.semaInfo().moduleNamespace();

    return followNamespace(sema, root, sema.frame().nsPath());
}

SymbolFlags SemaFrame::flagsForCurrentAccess() const
{
    SymbolFlags flags = SymbolFlagsE::Zero;
    if (access() == SymbolAccess::Public)
        flags.add(SymbolFlagsE::Public);
    return flags;
}

SWC_END_NAMESPACE()
