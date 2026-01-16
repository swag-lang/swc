#include "pch.h"
#include "Sema/Symbol/Match.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/MatchContext.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void addSymMap(MatchContext& lookUpCxt, const SymbolMap* symMap, const MatchContext::Priority& priority)
    {
        for (const auto* existing : lookUpCxt.symMaps)
        {
            if (existing == symMap)
                return;
        }

        lookUpCxt.symMaps.push_back(symMap);
        lookUpCxt.symMapPriorities.push_back(priority);

        if (const auto* structSym = symMap->safeCast<SymbolStruct>())
        {
            for (const auto* impl : structSym->impls())
                addSymMap(lookUpCxt, impl, priority);
        }
        else if (const auto* enumSym = symMap->safeCast<SymbolEnum>())
        {
            for (const auto* impl : enumSym->impls())
                addSymMap(lookUpCxt, impl, priority);
        }
        else if (const auto* implSym = symMap->safeCast<SymbolImpl>())
        {
            if (implSym->ownerKind() == SymbolImplOwnerKind::Struct)
                addSymMap(lookUpCxt, implSym->symStruct(), priority);
            else
                addSymMap(lookUpCxt, implSym->symEnum(), priority);
        }
    }

    void collect(Sema& sema, MatchContext& lookUpCxt)
    {
        lookUpCxt.symMaps.clear();
        lookUpCxt.symMapPriorities.clear();

        // If we have a symMapHint, treat it as a "precise" lookup
        // and give it top priority.
        if (lookUpCxt.symMapHint)
        {
            MatchContext::Priority priority;
            priority.scopeDepth  = 0;
            priority.visibility  = MatchContext::VisibilityTier::LocalScope;
            priority.searchOrder = 0;
            addSymMap(lookUpCxt, lookUpCxt.symMapHint, priority);
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
                MatchContext::Priority priority;
                priority.scopeDepth  = scopeDepth;
                priority.visibility  = MatchContext::VisibilityTier::LocalScope;
                priority.searchOrder = searchOrder++;
                addSymMap(lookUpCxt, symMap, priority);
            }

            // Namespaces imported via "using" in this scope:
            for (const auto* usingSymMap : scope->usingSymMaps())
            {
                MatchContext::Priority priority;
                priority.scopeDepth  = scopeDepth;
                priority.visibility  = MatchContext::VisibilityTier::UsingDirective;
                priority.searchOrder = searchOrder++;
                addSymMap(lookUpCxt, usingSymMap, priority);
            }

            scope = scope->parent();
            ++scopeDepth;
        }

        // File-level namespace: conceptually outer than lexical scopes.
        {
            MatchContext::Priority priority;
            priority.scopeDepth  = scopeDepth;
            priority.visibility  = MatchContext::VisibilityTier::FileNamespace;
            priority.searchOrder = searchOrder++;
            addSymMap(lookUpCxt, &sema.semaInfo().fileNamespace(), priority);
        }

        // Module-level namespace: outer than file-level.
        {
            MatchContext::Priority priority;
            priority.scopeDepth  = static_cast<uint16_t>(scopeDepth + 1);
            priority.visibility  = MatchContext::VisibilityTier::ModuleNamespace;
            priority.searchOrder = searchOrder;
            addSymMap(lookUpCxt, &sema.semaInfo().moduleNamespace(), priority);
        }
    }

    void lookup(MatchContext& lookUpCxt, IdentifierRef idRef)
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

Result Match::match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef)
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

    return Result::Continue;
}

Result Match::ghosting(Sema& sema, const Symbol& sym)
{
    MatchContext lookUpCxt;
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

        if (sym.acceptOverloads() && other->acceptOverloads())
        {
            SWC_ASSERT(sym.isTyped());
            if (!other->isTyped())
                return sema.waitTyped(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
            if (!sym.deepCompare(other))
                continue;
        }

        return SemaError::raiseAlreadyDefined(sema, &sym, other);
    }

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;

        if (sym.acceptOverloads() && other->acceptOverloads())
        {
            SWC_ASSERT(sym.isTyped());
            if (!other->isTyped())
                return sema.waitTyped(other, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
            if (!sym.deepCompare(other))
                continue;
        }

        return SemaError::raiseGhosting(sema, &sym, other);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
