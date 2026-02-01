#include "pch.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"

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
            if (implSym->isForStruct())
                addSymMap(lookUpCxt, implSym->symStruct(), priority);
            else
                addSymMap(lookUpCxt, implSym->symEnum(), priority);
        }
    }

    bool isUsingMemberDecl(const AstNode* decl)
    {
        if (!decl)
            return false;
        if (const auto* var = decl->safeCast<AstVarDecl>())
            return var->hasFlag(AstVarDeclFlagsE::Using);
        if (const auto* varList = decl->safeCast<AstVarDeclNameList>())
            return varList->hasFlag(AstVarDeclFlagsE::Using);
        return false;
    }

    const SymbolStruct* usingTargetStruct(Sema& sema, const SymbolVariable& symVar)
    {
        const auto& ctx     = sema.ctx();
        const auto& typeMgr = sema.typeMgr();

        // Resolve aliases so that `using v: AliasToStruct` works.
        const TypeRef   ultimateTypeRef = typeMgr.get(symVar.typeRef()).unwrap(ctx, symVar.typeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
        const TypeInfo& ultimateType    = typeMgr.get(ultimateTypeRef);

        if (ultimateType.isStruct())
            return &ultimateType.payloadSymStruct();

        if (ultimateType.isAnyPointer())
        {
            const TypeRef   pointeeUltimateRef = typeMgr.get(ultimateType.payloadTypeRef()).unwrap(ctx, ultimateType.payloadTypeRef(), TypeExpandE::Alias | TypeExpandE::Enum);
            const TypeInfo& pointeeUltimate    = typeMgr.get(pointeeUltimateRef);
            if (pointeeUltimate.isStruct())
                return &pointeeUltimate.payloadSymStruct();
        }

        return nullptr;
    }

    void addUsingMemberSymMaps(Sema& sema, MatchContext& lookUpCxt, const SymbolStruct& symStruct, uint16_t& searchOrder, SmallVector<const SymbolStruct*>& visited)
    {
        for (const auto* s : visited)
        {
            if (s == &symStruct)
                return;
        }

        visited.push_back(&symStruct);

        for (const auto* field : symStruct.fields())
        {
            if (!field || field->isIgnored())
                continue;

            const auto& symVar = field->cast<SymbolVariable>();
            if (!isUsingMemberDecl(symVar.decl()))
                continue;

            const SymbolStruct* target = usingTargetStruct(sema, symVar);
            if (!target)
                continue;

            MatchContext::Priority priority;
            priority.scopeDepth = 0;
            priority.visibility = MatchContext::VisibilityTier::UsingDirective;

            addSymMap(lookUpCxt, target, priority);
            addUsingMemberSymMaps(sema, lookUpCxt, *target, searchOrder, visited);
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
            uint16_t searchOrder = 0;

            MatchContext::Priority priority;
            priority.scopeDepth = 0;
            priority.visibility = MatchContext::VisibilityTier::LocalScope;

            // If the caller hints a struct scope, but we're currently inside an `impl Interface for Struct`
            // block for that same struct, member lookup must also consider the current impl scope.
            // This keeps the rule centralized (all lookups benefit), instead of having ad-hoc fixes
            // in member-access/auto-member-access.
            if (const auto* structSym = lookUpCxt.symMapHint->safeCast<SymbolStruct>())
            {
                if (const SymbolImpl* symImpl = sema.frame().currentImpl())
                {
                    if (symImpl->isForStruct() && symImpl->symStruct() == structSym && symImpl->idRef() != structSym->idRef())
                        addSymMap(lookUpCxt, symImpl->asSymMap(), priority);
                }
            }

            addSymMap(lookUpCxt, lookUpCxt.symMapHint, priority);

            // Struct member lookup must also see members of `using` fields.
            if (const auto* structSym = lookUpCxt.symMapHint->safeCast<SymbolStruct>())
            {
                SmallVector<const SymbolStruct*> visited;
                addUsingMemberSymMaps(sema, lookUpCxt, *structSym, searchOrder, visited);
            }

            return;
        }

        uint16_t scopeDepth = 0;

        // Walk lexical scopes from innermost to outermost.
        const SemaScope* scope = &sema.curScope();
        while (scope)
        {
            if (const auto* symMap = scope->symMap())
            {
                MatchContext::Priority priority;
                priority.scopeDepth = scopeDepth;
                priority.visibility = MatchContext::VisibilityTier::LocalScope;
                addSymMap(lookUpCxt, symMap, priority);
            }

            for (const auto* symbol : scope->symbols())
            {
                MatchContext::Priority priority;
                priority.scopeDepth = scopeDepth;
                priority.visibility = MatchContext::VisibilityTier::LocalScope;
                lookUpCxt.localSymbols.push_back({.symbol = symbol, .priority = priority});
            }

            // Namespaces imported via "using" in this scope:
            for (const auto* usingSymMap : scope->usingSymMaps())
            {
                MatchContext::Priority priority;
                priority.scopeDepth = scopeDepth;
                priority.visibility = MatchContext::VisibilityTier::UsingDirective;
                addSymMap(lookUpCxt, usingSymMap, priority);
            }

            scope = scope->parent();
            ++scopeDepth;
        }

        // File-level namespace: conceptually outer than lexical scopes.
        {
            MatchContext::Priority priority;
            priority.scopeDepth = scopeDepth;
            priority.visibility = MatchContext::VisibilityTier::FileNamespace;
            addSymMap(lookUpCxt, &sema.semaInfo().fileNamespace(), priority);
        }

        // Module-level namespace: outer than file-level.
        {
            MatchContext::Priority priority;
            priority.scopeDepth = static_cast<uint16_t>(scopeDepth + 1);
            priority.visibility = MatchContext::VisibilityTier::ModuleNamespace;
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

        for (const auto& local : lookUpCxt.localSymbols)
        {
            if (local.symbol->idRef() == idRef)
                lookUpCxt.addSymbol(local.symbol, local.priority);
        }
    }
}

Result Match::match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef)
{
    collect(sema, lookUpCxt);
    lookup(lookUpCxt, idRef);
    if (lookUpCxt.empty())
    {
        if (lookUpCxt.noWaitOnEmpty)
            return Result::Continue;
        return sema.waitIdentifier(idRef, lookUpCxt.srcViewRef, lookUpCxt.tokRef);
    }

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

    const auto* symMapOfSym = sym.ownerSymMap();

    for (const auto* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;

        // If it's a "local" symbol in SemaScope::symbols_, it doesn't have a symMap (it's null).
        // So if BOTH are null, they are in the same scope.
        if (other->ownerSymMap() != symMapOfSym)
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
