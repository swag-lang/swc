#include "pch.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using MatchPriority  = MatchContext::Priority;
    using VisibilityTier = MatchContext::VisibilityTier;

    bool scopeUsesRedirectedLookupChain(const SemaScope* scope)
    {
        for (const SemaScope* it = scope; it; it = it->parent())
        {
            if (it->lookupParent() != it->parent())
                return true;
        }

        return false;
    }

    bool symbolDeclaredBefore(const Symbol& lhs, const Symbol& rhs)
    {
        if (lhs.srcViewRef() != rhs.srcViewRef())
            return lhs.srcViewRef() < rhs.srcViewRef();
        if (lhs.tokRef() != rhs.tokRef())
            return lhs.tokRef() < rhs.tokRef();
        return lhs.kind() < rhs.kind();
    }

    void addCurrentModuleNamespaceSymbol(Sema& sema, MatchContext& lookUpCxt, uint16_t scopeDepth)
    {
        if (!sema.moduleNamespace().idRef().isValid())
            return;

        const MatchPriority priority{.scopeDepth = scopeDepth, .visibility = VisibilityTier::ModuleNamespace};
        lookUpCxt.localSymbols.push_back({.symbol = &sema.moduleNamespace(), .priority = priority});
    }

    Result reportUsingCurrentModuleNamespace(Sema& sema, const MatchContext& lookUpCxt)
    {
        if (lookUpCxt.count() != 1)
            return Result::Continue;
        if (lookUpCxt.first() != &sema.moduleNamespace())
            return Result::Continue;
        if (sema.curNode().isNot(AstNodeId::Identifier))
            return Result::Continue;

        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (!parentRef.isValid() || sema.node(parentRef).isNot(AstNodeId::UsingDecl))
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_using_module_namespace, lookUpCxt.codeRef);
        SemaError::setReportArguments(sema, diag, lookUpCxt.first());
        diag.report(sema.ctx());
        return Result::Error;
    }

    void addSymMap(MatchContext& lookUpCxt, const SymbolMap* symMap, const MatchPriority& priority)
    {
        SWC_ASSERT(symMap != nullptr);
        for (const SymbolMap* existing : lookUpCxt.symMaps)
        {
            if (existing == symMap)
                return;
        }

        lookUpCxt.symMaps.push_back(symMap);
        lookUpCxt.symMapPriorities.push_back(priority);

        if (symMap->isStruct())
        {
            const auto& structSym = symMap->cast<SymbolStruct>();
            for (const SymbolImpl* impl : structSym.impls())
            {
                if (!impl || impl->isIgnored())
                    continue;
                addSymMap(lookUpCxt, impl, priority);
            }
        }
        else if (symMap->isEnum())
        {
            const auto& enumSym = symMap->cast<SymbolEnum>();
            for (const SymbolImpl* impl : enumSym.impls())
                addSymMap(lookUpCxt, impl, priority);
        }
        else if (symMap->isImpl())
        {
            const auto& implSym = symMap->cast<SymbolImpl>();
            if (implSym.isForStruct())
                addSymMap(lookUpCxt, implSym.symStruct(), priority);
            else
                addSymMap(lookUpCxt, implSym.symEnum(), priority);
        }
    }

    void addPersistedUsingSymMaps(MatchContext& lookUpCxt, const SymbolMap* symMap, const MatchPriority& priority)
    {
        if (!symMap)
            return;

        SmallVector<const SymbolMap*> usingSymMaps;
        symMap->copyUsingSymMaps(usingSymMaps);
        for (const SymbolMap* usingSymMap : usingSymMaps)
        {
            const MatchPriority usingPriority{.scopeDepth = priority.scopeDepth, .visibility = VisibilityTier::UsingDirective};
            addSymMap(lookUpCxt, usingSymMap, usingPriority);
        }
    }

    const SymbolMap* followNamespacePath(const SymbolMap* root, std::span<const IdentifierRef> nsPath)
    {
        if (!root)
            return nullptr;

        const SymbolMap* current = root;
        for (const IdentifierRef idRef : nsPath)
        {
            MatchContext            matchCxt;
            constexpr MatchPriority priority{.scopeDepth = 0, .visibility = VisibilityTier::LocalScope};
            matchCxt.beginSymMapLookup(priority);
            current->lookupAppend(idRef, matchCxt);

            const Symbol* nextNamespace = nullptr;
            for (const Symbol* symbol : matchCxt.symbols())
            {
                if (symbol && symbol->isNamespace())
                {
                    nextNamespace = symbol;
                    break;
                }
            }

            if (!nextNamespace)
                return nullptr;

            current = nextNamespace->asSymMap();
        }

        return current;
    }

    void addNamespacePathSymMap(Sema& sema, MatchContext& lookUpCxt, const SymbolMap* root, const MatchPriority& priority)
    {
        const SymbolMap* symMap = followNamespacePath(root, sema.frame().nsPath());
        if (!symMap)
            return;

        addSymMap(lookUpCxt, symMap, priority);
        addPersistedUsingSymMaps(lookUpCxt, symMap, priority);
    }

    Result addUsingMemberSymMaps(Sema& sema, MatchContext& lookUpCxt, const SymbolStruct& symStruct, std::unordered_set<const SymbolStruct*>& visited)
    {
        if (!visited.insert(&symStruct).second)
            return Result::Continue;

        for (const Symbol* field : symStruct.fields())
        {
            const auto& symVar = field->cast<SymbolVariable>();
            if (!symVar.isUsingField())
                continue;

            const SymbolStruct* target = symVar.usingTargetStruct(sema.ctx());
            if (!target)
                continue;

            SWC_RESULT(sema.waitSemaCompleted(target, lookUpCxt.codeRef));

            constexpr MatchPriority priority{.scopeDepth = 0, .visibility = VisibilityTier::UsingDirective};

            addSymMap(lookUpCxt, target, priority);
            SWC_RESULT(addUsingMemberSymMaps(sema, lookUpCxt, *target, visited));
        }

        return Result::Continue;
    }

    void addBindingTypeSymMaps(Sema& sema, MatchContext& lookUpCxt, uint16_t& scopeDepth)
    {
        for (const TypeRef typeRef : std::ranges::reverse_view(sema.frame().bindingTypes()))
        {
            if (!typeRef.isValid())
                continue;

            const TypeRef enumTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), typeRef);
            if (!enumTypeRef.isValid())
                continue;

            const TypeInfo& typeInfo = sema.typeMgr().get(enumTypeRef);
            if (!typeInfo.isEnum())
                continue;

            const MatchPriority priority{.scopeDepth = scopeDepth++, .visibility = VisibilityTier::LocalScope};
            addSymMap(lookUpCxt, &typeInfo.payloadSymEnum(), priority);
        }
    }

    Result collect(Sema& sema, MatchContext& lookUpCxt)
    {
        lookUpCxt.symMaps.clear();
        lookUpCxt.symMapPriorities.clear();

        // If we have a symMapHint, treat it as a "precise" lookup
        // and give it top priority.
        if (lookUpCxt.symMapHint)
        {
            constexpr MatchPriority priority{.scopeDepth = 0, .visibility = VisibilityTier::LocalScope};

            // If the caller hints a struct scope, but we're currently inside an `impl Interface for Struct`
            // block for that same struct, member lookup must also consider the current impl scope.
            // This keeps the rule centralized (all lookups benefit), instead of having ad-hoc fixes
            // in member-access/auto-member-access.
            if (lookUpCxt.symMapHint->isStruct())
            {
                const auto& structSym = lookUpCxt.symMapHint->cast<SymbolStruct>();
                if (const SymbolImpl* symImpl = sema.frame().currentImpl())
                {
                    if (symImpl->isForStruct() && symImpl->symStruct() == &structSym && symImpl->idRef() != structSym.idRef())
                        addSymMap(lookUpCxt, symImpl->asSymMap(), priority);
                }
            }

            addSymMap(lookUpCxt, lookUpCxt.symMapHint, priority);
            addPersistedUsingSymMaps(lookUpCxt, lookUpCxt.symMapHint, priority);

            // Struct member lookup must also see members of `using` fields.
            if (lookUpCxt.symMapHint->isStruct())
            {
                const auto&                             structSym = lookUpCxt.symMapHint->cast<SymbolStruct>();
                std::unordered_set<const SymbolStruct*> visited;
                SWC_RESULT(addUsingMemberSymMaps(sema, lookUpCxt, structSym, visited));
            }

            return Result::Continue;
        }

        uint16_t scopeDepth = 0;

        // Walk lexical scopes from innermost to outermost.
        const SemaScope* scope = sema.lookupScope();
        while (scope)
        {
            const bool skipRedirectedSymMap = sema.frame().ignoreRedirectedLookupSymMaps() && scopeUsesRedirectedLookupChain(scope);
            if (!skipRedirectedSymMap)
            {
                if (const SymbolMap* symMap = scope->symMap())
                {
                    const MatchPriority priority{.scopeDepth = scopeDepth, .visibility = VisibilityTier::LocalScope};
                    addSymMap(lookUpCxt, symMap, priority);
                    addPersistedUsingSymMaps(lookUpCxt, symMap, priority);
                }
            }

            for (const Symbol* symbol : scope->symbols())
            {
                if (sema.frame().isLookupSymbolHidden(symbol))
                    continue;

                const MatchPriority priority{.scopeDepth = scopeDepth, .visibility = VisibilityTier::LocalScope};
                lookUpCxt.localSymbols.push_back({.symbol = symbol, .priority = priority});
            }

            // Namespaces imported via "using" in this scope:
            for (const SymbolMap* usingSymMap : scope->usingSymMaps())
            {
                const MatchPriority priority{.scopeDepth = scopeDepth, .visibility = VisibilityTier::UsingDirective};
                addSymMap(lookUpCxt, usingSymMap, priority);
            }

            scope = scope->lookupParent();
            ++scopeDepth;
        }

        addBindingTypeSymMaps(sema, lookUpCxt, scopeDepth);

        const MatchPriority filePathPriority{.scopeDepth = scopeDepth, .visibility = VisibilityTier::FileNamespace};
        addNamespacePathSymMap(sema, lookUpCxt, &sema.fileNamespace(), filePathPriority);

        const MatchPriority fileRootPriority{.scopeDepth = static_cast<uint16_t>(scopeDepth + 1), .visibility = VisibilityTier::FileNamespace};
        addSymMap(lookUpCxt, &sema.fileNamespace(), fileRootPriority);
        addPersistedUsingSymMaps(lookUpCxt, &sema.fileNamespace(), fileRootPriority);

        // Symbols imported from other modules live under the empty-named import-root namespace
        // (as siblings of this module's namespace) so they keep their own hierarchy (e.g. `Pixel`,
        // `Core`). An imported-API file's own relative names resolve against that root, so the
        // current namespace path must be walked from there too (e.g. `Core.Math.Point` inside the
        // generated `core.swg`).
        const SymbolNamespace* importRoot = sema.compiler().importRootNamespace();
        if (importRoot == &sema.moduleNamespace())
            importRoot = nullptr;

        const MatchPriority modulePathPriority{.scopeDepth = static_cast<uint16_t>(scopeDepth + 1), .visibility = VisibilityTier::ModuleNamespace};
        addNamespacePathSymMap(sema, lookUpCxt, &sema.moduleNamespace(), modulePathPriority);
        if (importRoot)
            addNamespacePathSymMap(sema, lookUpCxt, importRoot, modulePathPriority);

        const MatchPriority moduleRootPriority{.scopeDepth = static_cast<uint16_t>(scopeDepth + 2), .visibility = VisibilityTier::ModuleNamespace};
        addSymMap(lookUpCxt, &sema.moduleNamespace(), moduleRootPriority);
        addPersistedUsingSymMaps(lookUpCxt, &sema.moduleNamespace(), moduleRootPriority);

        // Expose the imported module namespaces (Core, Pixel, ...) as siblings. Do NOT pull in
        // importRoot's persisted `using` directives: those accumulate every imported file's usings
        // (e.g. `using Win32`) and would flood unqualified lookups with unrelated symbols
        // (e.g. `Gdi32.Rectangle` shadowing `Core.Math.Rectangle`).
        if (importRoot)
            addSymMap(lookUpCxt, importRoot, moduleRootPriority);

        addCurrentModuleNamespaceSymbol(sema, lookUpCxt, static_cast<uint16_t>(scopeDepth + 3));
        return Result::Continue;
    }

    void lookup(MatchContext& lookUpCxt, IdentifierRef idRef)
    {
        // Reset candidates & priority state.
        lookUpCxt.resetCandidates();

        const auto count = lookUpCxt.symMaps.size();
        for (size_t i = 0; i < count; ++i)
        {
            const SymbolMap* symMap   = lookUpCxt.symMaps[i];
            const auto&      priority = lookUpCxt.symMapPriorities[i];

            // Tell the context: "we're now scanning this layer with this priority".
            lookUpCxt.beginSymMapLookup(priority);

            // SymbolMap::lookupAppend must call lookUpCxt.addSymbol(...)
            // for each matching symbol it finds.
            symMap->lookupAppend(idRef, lookUpCxt);
        }

        for (const auto& local : lookUpCxt.localSymbols)
        {
            if (local.symbol->idRef() == idRef)
            {
                if (local.symbol->isIgnored())
                    lookUpCxt.addIgnoredSymbol(local.priority);
                else
                    lookUpCxt.addSymbol(local.symbol, local.priority);
            }
        }
    }

    Result declareGenericRootFunctionCandidate(Sema& sema, const SymbolFunction& sym, const SourceCodeRef& codeRef)
    {
        if (!sym.isGenericRoot() || sym.isDeclared())
            return Result::Continue;

        const auto* ownerImpl   = sym.ownerSymMap() ? sym.ownerSymMap()->safeCast<SymbolImpl>() : nullptr;
        const auto* ownerStruct = ownerImpl ? ownerImpl->symStruct() : nullptr;
        if (!ownerStruct || !ownerStruct->isGenericRoot() || ownerStruct->isGenericInstance())
            return sema.waitDeclared(&sym, codeRef);

        if (!sym.decl())
            return sema.waitDeclared(&sym, codeRef);

        std::unique_ptr<Sema> declSemaHolder;
        Sema*                 declSema = sema.tryCreateDeclSema(declSemaHolder, sym.srcViewRef(), sym.decl(), sym.declNodeRef());
        if (!declSema)
            declSema = &sema;

        const AstNodeRef declRef = declSema->ownerDeclNodeRef(sym.srcViewRef(), sym.decl(), sym.declNodeRef());
        if (declRef.isInvalid())
            return sema.waitDeclared(&sym, codeRef);

        SWC_RESULT(declSema->prepareFunctionSignature(declRef));
        if (!sym.isDeclared())
            return sema.waitDeclared(&sym, codeRef);
        return Result::Continue;
    }
}

Result Match::match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef)
{
    SWC_RESULT(collect(sema, lookUpCxt));
    lookup(lookUpCxt, idRef);
    if (lookUpCxt.empty())
    {
        if (lookUpCxt.blockedByIgnored())
            return Result::Error;
        if (lookUpCxt.noWaitOnEmpty)
            return Result::Continue;
        return sema.waitIdentifier(idRef, lookUpCxt.codeRef);
    }

    SWC_RESULT(reportUsingCurrentModuleNamespace(sema, lookUpCxt));

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (other->isFunction() && other->cast<SymbolFunction>().isGenericRoot())
        {
            if (!other->isDeclared() && lookUpCxt.noWaitOnPendingSymbols)
                return Result::Continue;
            SWC_RESULT(declareGenericRootFunctionCandidate(sema, other->cast<SymbolFunction>(), lookUpCxt.codeRef));
            continue;
        }
        if (!other->isDeclared())
        {
            if (lookUpCxt.noWaitOnPendingSymbols)
                return Result::Continue;
            SWC_RESULT(sema.waitDeclared(other, lookUpCxt.codeRef));
        }
        if (other->isStruct() && other->cast<SymbolStruct>().isGenericRoot())
            continue;
        if (!other->isTyped())
        {
            if (lookUpCxt.noWaitOnPendingSymbols)
                return Result::Continue;
            SWC_RESULT(sema.waitTyped(other, lookUpCxt.codeRef));
        }
    }

    return Result::Continue;
}

Result Match::matchCallFallbackSymbols(Sema& sema, const SemaNodeView& nodeCallee, SmallVector<Symbol*>& outSymbols)
{
    outSymbols.clear();

    const AstNode* calleeNode = nodeCallee.node();
    if (!calleeNode || calleeNode->isNot(AstNodeId::Identifier))
        return Result::Continue;

    const AstIdentifier& callee = calleeNode->cast<AstIdentifier>();
    const IdentifierRef  idRef  = SemaHelpers::resolveIdentifier(sema, callee.codeRef());

    MatchContext lookUpCxt;
    lookUpCxt.codeRef       = callee.codeRef();
    lookUpCxt.noWaitOnEmpty = true;

    SWC_RESULT(collect(sema, lookUpCxt));
    lookup(lookUpCxt, idRef);
    if (lookUpCxt.empty())
        return Result::Continue;

    SmallVector<const Symbol*> fallbackSymbols;
    lookUpCxt.collectCallFallbackSymbols(fallbackSymbols);
    if (fallbackSymbols.size() <= lookUpCxt.count())
        return Result::Continue;

    for (const Symbol* other : fallbackSymbols)
    {
        SWC_RESULT(sema.waitDeclared(other, lookUpCxt.codeRef));
        if (other->isFunction() && other->cast<SymbolFunction>().isGenericRoot())
            continue;
        if (other->isStruct() && other->cast<SymbolStruct>().isGenericRoot())
            continue;
        SWC_RESULT(sema.waitTyped(other, lookUpCxt.codeRef));
    }

    outSymbols.reserve(fallbackSymbols.size());
    for (const Symbol* symbol : fallbackSymbols)
        outSymbols.push_back(const_cast<Symbol*>(symbol));

    return Result::Continue;
}

Result Match::ghosting(Sema& sema, const Symbol& sym)
{
    if (sym.isIgnored())
        return Result::Continue;

    MatchContext lookUpCxt;
    lookUpCxt.codeRef = sym.codeRef();
    if (sym.isFunction() && sym.ownerSymMap())
        lookUpCxt.symMapHint = sym.ownerSymMap();

    collect(sema, lookUpCxt);
    lookup(lookUpCxt, sym.idRef());
    if (lookUpCxt.empty())
        return sema.waitIdentifier(sym.idRef(), sym.codeRef());

    for (const Symbol* other : lookUpCxt.symbols())
    {
        SWC_RESULT(sema.waitDeclared(other, lookUpCxt.codeRef));
    }

    if (lookUpCxt.count() == 1)
        return Result::Continue;

    const SymbolMap* symMapOfSym            = sym.ownerSymMap();
    bool             reportedLaterDuplicate = false;

    for (const Symbol* other : lookUpCxt.symbols())
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
            if (other->isFunction() && other->cast<SymbolFunction>().isGenericRoot())
                continue;
            if (other->isStruct() && other->cast<SymbolStruct>().isGenericRoot())
                continue;
            SWC_RESULT(sema.waitTyped(other, lookUpCxt.codeRef));
            if (!sym.deepCompare(other))
                continue;
        }

        if (symbolDeclaredBefore(sym, *other))
        {
            auto* duplicateSymbol = const_cast<Symbol*>(other);
            duplicateSymbol->setIgnored(sema.ctx());
            SemaError::raiseAlreadyDefined(sema, duplicateSymbol, &sym);
            reportedLaterDuplicate = true;
            continue;
        }

        const_cast<Symbol&>(sym).setIgnored(sema.ctx());
        return SemaError::raiseAlreadyDefined(sema, &sym, other);
    }

    if (reportedLaterDuplicate)
        return Result::Continue;

    for (const Symbol* other : lookUpCxt.symbols())
    {
        if (other == &sym)
            continue;
        if (other->isIgnored())
            continue;
        if (sym.isFunction() && sym.ownerSymMap() && other->ownerSymMap() != symMapOfSym)
            continue;

        if (sym.acceptOverloads() && other->acceptOverloads())
        {
            SWC_ASSERT(sym.isTyped());
            if (other->isFunction() && other->cast<SymbolFunction>().isGenericRoot())
                continue;
            if (other->isStruct() && other->cast<SymbolStruct>().isGenericRoot())
                continue;
            SWC_RESULT(sema.waitTyped(other, lookUpCxt.codeRef));
            if (!sym.deepCompare(other))
                continue;
        }

        return SemaError::raiseGhosting(sema, &sym, other);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
