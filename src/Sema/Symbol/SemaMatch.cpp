#include "pch.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/LookUpContext.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void collect(Sema& sema, LookUpContext& lookUpCxt)
    {
        lookUpCxt.symMaps.clear();
        lookUpCxt.symMapPriorities.clear();

        // If we have a symMapHint, treat it as a "precise" lookup
        // and give it top priority.
        if (lookUpCxt.symMapHint)
        {
            LookUpContext::Priority priority;
            priority.scopeDepth  = 0;
            priority.visibility  = LookUpContext::VisibilityTier::LocalScope;
            priority.searchOrder = 0;
            lookUpCxt.symMaps.push_back(lookUpCxt.symMapHint);
            lookUpCxt.symMapPriorities.push_back(priority);
            return;
        }

        uint16_t scopeDepth  = 0;
        uint16_t searchOrder = 0;

        // Walk lexical scopes from innermost to outermost.
        const SemaScope* scope = &sema.curScope();
        while (scope)
        {
            if (const auto* symMap = scope->symMap())
            {
                LookUpContext::Priority priority;
                priority.scopeDepth  = scopeDepth;
                priority.visibility  = LookUpContext::VisibilityTier::LocalScope;
                priority.searchOrder = searchOrder++;
                lookUpCxt.symMaps.push_back(symMap);
                lookUpCxt.symMapPriorities.push_back(priority);
            }

            // Namespaces imported via "using" in this scope:
            for (const auto* usingSymMap : scope->usingSymMaps())
            {
                LookUpContext::Priority priority;
                priority.scopeDepth  = scopeDepth;
                priority.visibility  = LookUpContext::VisibilityTier::UsingDirective;
                priority.searchOrder = searchOrder++;
                lookUpCxt.symMaps.push_back(usingSymMap);
                lookUpCxt.symMapPriorities.push_back(priority);
            }

            scope = scope->parent();
            ++scopeDepth;
        }

        // File-level namespace: conceptually outer than lexical scopes.
        {
            LookUpContext::Priority priority;
            priority.scopeDepth  = scopeDepth;
            priority.visibility  = LookUpContext::VisibilityTier::FileNamespace;
            priority.searchOrder = searchOrder++;
            lookUpCxt.symMaps.push_back(&sema.semaInfo().fileNamespace());
            lookUpCxt.symMapPriorities.push_back(priority);
        }

        // Module-level namespace: outer than file-level.
        {
            LookUpContext::Priority priority;
            priority.scopeDepth  = static_cast<uint16_t>(scopeDepth + 1);
            priority.visibility  = LookUpContext::VisibilityTier::ModuleNamespace;
            priority.searchOrder = searchOrder++;
            lookUpCxt.symMaps.push_back(&sema.semaInfo().moduleNamespace());
            lookUpCxt.symMapPriorities.push_back(priority);
        }
    }

    void lookup(LookUpContext& lookUpCxt, IdentifierRef idRef)
    {
        // Reset candidates & priority state.
        lookUpCxt.resetCandidates();

        const auto count = lookUpCxt.symMaps.size();
        for (size_t i = 0; i < count; ++i)
        {
            const auto* symMap   = lookUpCxt.symMaps[i];
            const auto& priority = lookUpCxt.symMapPriorities[i];

            // Tell the context: "we're now scanning this layer with this priority".
            lookUpCxt.beginSymMapLookup(priority);

            // SymbolMap::lookupAppend must call lookUpCxt.addSymbol(...)
            // for each matching symbol it finds.
            symMap->lookupAppend(idRef, lookUpCxt);
        }
    }
}

Result SemaMatch::match(Sema& sema, LookUpContext& lookUpCxt, IdentifierRef idRef)
{
    collect(sema, lookUpCxt);
    lookup(lookUpCxt, idRef);
    if (lookUpCxt.empty())
        return sema.waitIdentifier(idRef, lookUpCxt.srcViewRef, lookUpCxt.tokRef);

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (!other->isDeclared())
            return sema.waitDeclared(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
        if (!other->isTyped())
            return sema.waitTyped(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
    }

    if (lookUpCxt.count() > 1)
        return SemaError::raiseAmbiguousSymbol(sema, lookUpCxt.srcViewRef, lookUpCxt.tokRef, lookUpCxt.symbols());

    return Result::Continue;
}

Result SemaMatch::ghosting(Sema& sema, const Symbol& sym)
{
    LookUpContext lookUpCxt;
    lookUpCxt.srcViewRef = sym.srcViewRef();
    lookUpCxt.tokRef     = sym.tokRef();

    collect(sema, lookUpCxt);
    lookup(lookUpCxt, sym.idRef());
    if (lookUpCxt.empty())
        return sema.waitIdentifier(sym.idRef(), sym.srcViewRef(), sym.tokRef());

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (!other->isDeclared())
            return sema.waitDeclared(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
    }

    if (lookUpCxt.count() == 1)
        return Result::Continue;

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;
        if (other->symMap() != sym.symMap())
            continue;
        return SemaError::raiseAlreadyDefined(sema, &sym, other);
    }

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;
        return SemaError::raiseGhosting(sema, &sym, other);
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
