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
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Core/PointerSet.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // A generic function or struct root: the overload checks skip it instead of waiting for its type.
    bool isGenericFunctionOrStructRoot(const Symbol& symbol)
    {
        if (symbol.isFunction())
            return symbol.cast<SymbolFunction>().isGenericRoot();

        return symbol.isStruct() && symbol.cast<SymbolStruct>().isGenericRoot();
    }

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
            symMap->cast<SymbolStruct>().forEachImpl([&](const SymbolImpl* impl) {
                if (impl && !impl->isIgnored())
                    addSymMap(lookUpCxt, impl, priority);
            });
        }
        else if (symMap->isEnum())
        {
            symMap->cast<SymbolEnum>().forEachImpl([&](const SymbolImpl* impl) { addSymMap(lookUpCxt, impl, priority); });
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

    // True when 'symMap' is 'owner' or lives somewhere below it.
    bool isOwnedBySymMap(const SymbolMap* symMap, const SymbolMap* owner)
    {
        for (const SymbolMap* current = symMap; current; current = current->ownerSymMap())
        {
            if (current == owner)
                return true;
        }

        return false;
    }

    // Prefer this module's namespaces over same-named dependency namespaces. Otherwise
    // using Lib could hide the module's own Testing behind Lib.Testing, which remains
    // accessible by qualification. Other symbol kinds retain normal scope priority.
    void preferOwnModuleNamespace(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef)
    {
        // A hinted lookup already selects an exact map; preserve that namespace.
        if (lookUpCxt.symMapHint || lookUpCxt.empty())
            return;

        const SymbolMap& moduleNs = sema.moduleNamespace();
        for (const Symbol* symbol : lookUpCxt.symbols())
        {
            if (!symbol->isNamespace() || isOwnedBySymMap(symbol->ownerSymMap(), &moduleNs))
                return;
        }

        const Symbol* own = moduleNs.findFirstSymbol(idRef);
        if (!own || !own->isNamespace())
            return;

        lookUpCxt.replaceWithSingleSymbol(own);
    }

    void addPersistedUsingSymMaps(Sema& sema, MatchContext& lookUpCxt, const SymbolMap* symMap, const MatchPriority& priority)
    {
        if (!symMap)
            return;

        SmallVector<const SymbolMap*> usingSymMaps;
        symMap->copyUsingSymMaps(usingSymMaps, &sema.compiler());

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

        // Namespace homonyms retain chain order within one map and priority.
        // Follow the first one, as lookup would.
        const SymbolMap* current = root;
        for (const IdentifierRef idRef : nsPath)
        {
            const Symbol* nextNamespace = current->findFirstNamespace(idRef);
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
        addPersistedUsingSymMaps(sema, lookUpCxt, symMap, priority);
    }

    const SymbolMap* importedApiModuleRoot(Sema& sema, const SymbolMap* importRoot)
    {
        const SourceFile* file = sema.file();
        if (!file || !file->isImportedApi() || !importRoot)
            return nullptr;

        const auto nsPath = sema.frame().nsPath();
        if (nsPath.empty())
            return nullptr;

        return followNamespacePath(importRoot, nsPath.first(1));
    }

    // Most structs have no using field. Avoid walking fields or filling the visited set
    // until there is a using target to follow.
    Result addUsingMemberSymMaps(Sema& sema, MatchContext& lookUpCxt, const SymbolStruct& symStruct, PointerSet<const SymbolStruct>& visited)
    {
        if (!symStruct.mayHaveUsingField())
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

            if (visited.empty())
                visited.insert(&symStruct);

            if (visited.insert(target))
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

    // Copy only matching local symbols into the context, so unrelated identifiers
    // need no visibility checks.
    Result collect(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef)
    {
        lookUpCxt.symMaps.clear();
        lookUpCxt.symMapPriorities.clear();

        // A hinted map defines a precise lookup at the highest priority.
        if (lookUpCxt.symMapHint)
        {
            constexpr MatchPriority priority{.scopeDepth = 0, .visibility = VisibilityTier::LocalScope};

            // Inside impl Interface for Struct, a struct hint must also search that impl's
            // scope. Keep this rule shared by all member lookup paths.
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
            addPersistedUsingSymMaps(sema, lookUpCxt, lookUpCxt.symMapHint, priority);

            // Struct member lookup must also see members of `using` fields.
            if (lookUpCxt.symMapHint->isStruct() && !lookUpCxt.skipUsingFieldMembers)
            {
                const auto& structSym = lookUpCxt.symMapHint->cast<SymbolStruct>();

                PointerSet<const SymbolStruct> visited;
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
                    addPersistedUsingSymMaps(sema, lookUpCxt, symMap, priority);
                }
            }

            if (scope->mayHaveSymbolNamed(idRef))
            {
                for (const Symbol* symbol : scope->symbols())
                {
                    if (symbol->idRef() != idRef || sema.frame().isLookupSymbolHidden(symbol))
                        continue;

                    const MatchPriority priority{.scopeDepth = scopeDepth, .visibility = VisibilityTier::LocalScope};
                    lookUpCxt.localSymbols.push_back({.symbol = symbol, .priority = priority});
                }
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

        // Injected caller code can retain its original source view while being resolved
        // in the macro's AST. Its file-private symbols belong to that source file.
        const SymbolMap* fileNamespace = &sema.fileNamespace();
        if (lookUpCxt.codeRef.isValid() && lookUpCxt.codeRef.srcViewRef != sema.ast().srcView().ref())
        {
            if (const SourceFile* sourceFile = sema.ownerSourceFile(lookUpCxt.codeRef.srcViewRef))
            {
                if (sourceFile->fileNamespace())
                    fileNamespace = sourceFile->fileNamespace();
            }
        }

        // Outside any namespace the path of a root is the root itself: adding it again at the
        // root priority, with its `using` directives, would only find every map already there.
        const bool atNamespaceRoot = sema.frame().nsPath().empty();

        const MatchPriority filePathPriority{.scopeDepth = scopeDepth, .visibility = VisibilityTier::FileNamespace};
        addNamespacePathSymMap(sema, lookUpCxt, fileNamespace, filePathPriority);

        if (!atNamespaceRoot)
        {
            const MatchPriority fileRootPriority{.scopeDepth = static_cast<uint16_t>(scopeDepth + 1), .visibility = VisibilityTier::FileNamespace};
            addSymMap(lookUpCxt, fileNamespace, fileRootPriority);
            addPersistedUsingSymMaps(sema, lookUpCxt, fileNamespace, fileRootPriority);
        }

        // Imported modules keep their namespace hierarchy under the import root.
        // Imported API files resolve relative names there too, so walk their current
        // namespace path from that root (for example, Lib.Math.Point in lib.swg).
        const SymbolNamespace* importRoot = sema.compiler().importRootNamespace();
        if (importRoot == &sema.moduleNamespace())
            importRoot = nullptr;

        const MatchPriority modulePathPriority{.scopeDepth = static_cast<uint16_t>(scopeDepth + 1), .visibility = VisibilityTier::ModuleNamespace};
        addNamespacePathSymMap(sema, lookUpCxt, &sema.moduleNamespace(), modulePathPriority);
        if (importRoot)
            addNamespacePathSymMap(sema, lookUpCxt, importRoot, modulePathPriority);

        uint16_t moduleRootDepth = static_cast<uint16_t>(scopeDepth + 2);
        if (const SymbolMap* importedModuleRoot = importedApiModuleRoot(sema, importRoot))
        {
            const MatchPriority importedModuleRootPriority{.scopeDepth = moduleRootDepth++, .visibility = VisibilityTier::ModuleNamespace};
            addSymMap(lookUpCxt, importedModuleRoot, importedModuleRootPriority);
            addPersistedUsingSymMaps(sema, lookUpCxt, importedModuleRoot, importedModuleRootPriority);
        }

        if (!atNamespaceRoot)
        {
            const MatchPriority moduleRootPriority{.scopeDepth = moduleRootDepth, .visibility = VisibilityTier::ModuleNamespace};
            addSymMap(lookUpCxt, &sema.moduleNamespace(), moduleRootPriority);
            addPersistedUsingSymMaps(sema, lookUpCxt, &sema.moduleNamespace(), moduleRootPriority);

            // Expose imported module namespaces as siblings without importRoot's persisted usings.
            // Those combine all imported files and could shadow names with unrelated symbols.
            if (importRoot)
                addSymMap(lookUpCxt, importRoot, moduleRootPriority);
        }

        addCurrentModuleNamespaceSymbol(sema, lookUpCxt, static_cast<uint16_t>(moduleRootDepth + 1));

        return Result::Continue;
    }

    void lookup(MatchContext& lookUpCxt, IdentifierRef idRef)
    {
        lookUpCxt.resetCandidates();

        const auto count = lookUpCxt.symMaps.size();
        for (size_t i = 0; i < count; ++i)
        {
            const SymbolMap* symMap   = lookUpCxt.symMaps[i];
            const auto&      priority = lookUpCxt.symMapPriorities[i];

            lookUpCxt.beginSymMapLookup(priority);
            symMap->lookupAppend(idRef, lookUpCxt);
        }

        for (const auto& local : lookUpCxt.localSymbols)
        {
            if (local.symbol->idRef() == idRef)
            {
                if (local.symbol->isIgnored())
                {
                    if (!local.symbol->isExcludedByCondition())
                        lookUpCxt.addIgnoredSymbol(local.priority);
                }
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

// Collect visible names for suggestions after an unqualified lookup finds no match.
void Match::collectVisibleNames(Sema& sema, const SourceCodeRef& codeRef, std::vector<Utf8>& out)
{
    MatchContext lookUpCxt;
    lookUpCxt.codeRef = codeRef;
    if (collect(sema, lookUpCxt, IdentifierRef::invalid()) != Result::Continue)
        return;

    const auto append = [&](const Symbol& symbol) {
        const std::string_view name = symbol.name(sema.ctx());
        if (!name.empty() && !name.starts_with("__"))
            out.emplace_back(name);
    };

    for (const SemaScope* scope = sema.lookupScope(); scope; scope = scope->lookupParent())
    {
        for (const Symbol* symbol : scope->symbols())
            append(*symbol);
    }

    std::vector<const Symbol*> symbols;
    for (const SymbolMap* symMap : lookUpCxt.symMaps)
    {
        symMap->getAllSymbols(symbols);

        for (const Symbol* symbol : symbols)
            append(*symbol);
    }
}

Result Match::match(Sema& sema, MatchContext& lookUpCxt, IdentifierRef idRef)
{
    SWC_RESULT(collect(sema, lookUpCxt, idRef));

    while (true)
    {
        lookup(lookUpCxt, idRef);
        preferOwnModuleNamespace(sema, lookUpCxt, idRef);
        if (lookUpCxt.blockedByIgnored())
            return Result::Error;

        if (lookUpCxt.empty())
        {
            if (lookUpCxt.noWaitOnEmpty)
                return Result::Continue;

            const Result result = lookUpCxt.symMapHint ? sema.waitScopedMember(idRef, lookUpCxt.codeRef) : sema.waitIdentifier(idRef, lookUpCxt.codeRef);
            if (result == Result::Pause)
                sema.ctx().state().memberScope = lookUpCxt.symMapHint;

            return result;
        }

        SWC_RESULT(reportUsingCurrentModuleNamespace(sema, lookUpCxt));

        bool retryLookup = false;
        for (const Symbol* other : lookUpCxt.symbols())
        {
            if (other->isFunction() && other->cast<SymbolFunction>().isGenericRoot())
            {
                if (!other->isDeclared() && lookUpCxt.noWaitOnPendingSymbols)
                    return Result::Continue;

                const Result ready = declareGenericRootFunctionCandidate(sema, other->cast<SymbolFunction>(), lookUpCxt.codeRef);
                if (other->isExcludedByCondition())
                {
                    retryLookup = true;
                    break;
                }

                SWC_RESULT(ready);
                continue;
            }

            if (!other->isDeclared())
            {
                if (lookUpCxt.noWaitOnPendingSymbols)
                    return Result::Continue;

                const Result ready = sema.waitDeclared(other, lookUpCxt.codeRef);
                if (other->isExcludedByCondition())
                {
                    retryLookup = true;
                    break;
                }

                SWC_RESULT(ready);
            }

            if (other->isStruct() && other->cast<SymbolStruct>().isGenericRoot())
                continue;

            if (!other->isTyped())
            {
                if (lookUpCxt.noWaitOnPendingSymbols)
                    return Result::Continue;

                const Result ready = sema.waitTyped(other, lookUpCxt.codeRef);
                if (other->isExcludedByCondition())
                {
                    retryLookup = true;
                    break;
                }

                SWC_RESULT(ready);
            }
        }

        // Another worker can discard a compiler-if candidate between lookup and its
        // readiness check. Resolve the name again instead of reporting a failed job.
        if (!retryLookup)
            return Result::Continue;
    }
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

    SWC_RESULT(collect(sema, lookUpCxt, idRef));
    lookup(lookUpCxt, idRef);
    if (lookUpCxt.empty())
        return Result::Continue;

    SmallVector<const Symbol*> fallbackSymbols;
    lookUpCxt.appendCallFallbackSymbols(fallbackSymbols);
    if (fallbackSymbols.size() <= lookUpCxt.count())
        return Result::Continue;

    for (const Symbol* other : fallbackSymbols)
    {
        SWC_RESULT(sema.waitDeclared(other, lookUpCxt.codeRef));
        if (isGenericFunctionOrStructRoot(*other))
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

    collect(sema, lookUpCxt, sym.idRef());
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

        // Local symbols have no owner map; two null owners therefore denote the same scope.
        if (other->ownerSymMap() != symMapOfSym)
            continue;

        if (sym.acceptOverloads() && other->acceptOverloads())
        {
            SWC_ASSERT(sym.isTyped());
            if (isGenericFunctionOrStructRoot(*other))
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
            if (isGenericFunctionOrStructRoot(*other))
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
