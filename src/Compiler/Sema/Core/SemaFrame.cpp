#include "pch.h"
#include "Compiler/Sema/Core/SemaFrame.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SymbolMap* followNamespace(Sema& sema, SymbolMap* root, std::span<const IdentifierRef> nsPath)
    {
        constexpr SymbolFlags namespaceFlags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
        SymbolMap*            m              = root;
        for (const IdentifierRef idRef : nsPath)
        {
            TaskContext& ctx = sema.ctx();
            auto*        ns  = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), idRef, namespaceFlags);
            Symbol*      res = m->addSingleSymbol(ctx, ns);
            SWC_ASSERT(res->isNamespace());
            m = res->asSymMap();
        }

        return m;
    }
}

void SemaFrame::pushBindingType(TypeRef type)
{
    if (type.isValid())
        bindingTypes_.push_back(type);
}

void SemaFrame::popBindingType()
{
    if (!bindingTypes_.empty())
        bindingTypes_.pop_back();
}

void SemaFrame::pushBindingVar(SymbolVariable* sym)
{
    if (sym)
        bindingVars_.push_back(sym);
}

void SemaFrame::popBindingVar()
{
    if (!bindingVars_.empty())
        bindingVars_.pop_back();
}

void SemaFrame::hideLookupSymbol(const Symbol* sym)
{
    if (!sym)
        return;

    for (const Symbol* hidden : hiddenLookupSymbols_)
        if (hidden == sym)
            return;

    hiddenLookupSymbols_.push_back(sym);
}

bool SemaFrame::isLookupSymbolHidden(const Symbol* sym) const
{
    if (!sym)
        return false;

    for (const Symbol* hidden : hiddenLookupSymbols_)
        if (hidden == sym)
            return !sym->isSemaCompleted();

    return false;
}

void SemaFrame::addNarrowFact(std::span<const Symbol* const> path, SemaNarrowFactKind kind)
{
    if (path.empty())
        return;

    auto& fact = narrowFacts_.emplace_back();
    fact.path.assign(path.begin(), path.end());
    fact.kind  = kind;
    fact.holds = true;
}

void SemaFrame::addNarrowKill(std::span<const Symbol* const> path)
{
    if (path.empty())
        return;

    auto& fact = narrowFacts_.emplace_back();
    fact.path.assign(path.begin(), path.end());
    fact.holds = false;
}

void SemaFrame::killNarrowFactsByRootId(std::span<const IdentifierRef> rootIds)
{
    SmallVector2<SemaNarrowFact> kept;
    for (auto& fact : narrowFacts_)
    {
        const IdentifierRef rootId = fact.path.empty() ? IdentifierRef::invalid() : fact.path.front()->idRef();

        bool killed = false;
        for (const IdentifierRef id : rootIds)
        {
            if (id == rootId)
            {
                killed = true;
                break;
            }
        }

        if (!killed)
            kept.push_back(std::move(fact));
    }

    narrowFacts_ = std::move(kept);
}

bool SemaFrame::queryNarrowFact(std::span<const SemaNarrowFact> facts, std::span<const Symbol* const> path, SemaNarrowFactKind kind)
{
    if (path.empty())
        return false;

    // Newest fact wins: a kill pushed after a guard overrides it for the rest of its scope.
    for (size_t factIndex = facts.size(); factIndex > 0; --factIndex)
    {
        const SemaNarrowFact& fact = facts[factIndex - 1];
        if (fact.path.size() == path.size() && std::equal(fact.path.begin(), fact.path.end(), path.begin()))
        {
            // A kill drops every kind; a proof of another kind says nothing about this
            // one, so keep looking for an older proof of the requested kind.
            if (!fact.holds)
                return false;
            if (fact.kind == kind)
                return true;
            continue;
        }

        // A kill on a path also invalidates everything reached through it
        // (assigning `x` re-nullifies `x.y.z`).
        if (!fact.holds && fact.path.size() < path.size() && std::equal(fact.path.begin(), fact.path.end(), path.begin()))
            return false;
    }

    return false;
}

void SemaFrame::setCurrentBreakContent(AstNodeRef nodeRef, BreakContextKind kind)
{
    breakable_.nodeRef = nodeRef;
    breakable_.kind    = kind;

    if (kind == BreakContextKind::Loop || kind == BreakContextKind::None)
    {
        continuable_.nodeRef = nodeRef;
        continuable_.kind    = kind;
    }

    // A switch does not define a new loop index. Keep exposing the enclosing loop index inside it.
    if (kind != BreakContextKind::Switch)
    {
        currentLoopIndexTypeRef_  = TypeRef::invalid();
        currentLoopIndexOwnerRef_ = AstNodeRef::invalid();
    }
}

SymbolMap* SemaFrame::currentSymMap(Sema& sema)
{
    SymbolMap* symbolMap = sema.curSymMap();

    if (!sema.curScope().isTopLevel() || sema.curScope().isImpl())
        return symbolMap;

    // Explicit namespace scopes already carry the resolved namespace symbol map.
    // Re-rooting them through file/module access can create a sibling namespace
    // with the same id under another visibility root, which splits later member
    // declarations and qualified lookups across different namespace objects.
    if (symbolMap && !sema.frame().nsPath().empty())
        return symbolMap;

    const SymbolAccess access = sema.frame().currentAccess();

    SymbolMap* root = nullptr;
    if (access == SymbolAccess::Private)
        root = &sema.fileNamespace();
    else
    {
        root = &sema.moduleNamespace();

        // Imported-API files create their top-level symbols under the shared import-root namespace
        // (siblings of this module's namespace) so an imported module keeps its own namespace
        // hierarchy (e.g. `Pixel.Color`) exactly as if compiled directly, instead of being nested
        // under the importing module (`Importer.Pixel.Color`). Runtime files do the same: they are
        // compiled into every module, and rooting them under the module namespace would give the
        // same runtime type a different scoped name — and thus a different runtime identity
        // (descriptor fullname and crc) — in every module (`Importer.Swag.BaseError`). Lookup
        // still goes through the module namespace, so builtins (`Swag`) and sibling imports keep
        // resolving.
        const SourceFile* file = sema.file();
        if (file && (file->isImportedApi() || file->isRuntime()))
        {
            if (SymbolNamespace* importRoot = sema.compiler().importRootNamespace())
                root = importRoot;
        }
    }

    return followNamespace(sema, root, sema.frame().nsPath());
}

MemberAccessSpec SemaFrame::memberAccessFor(const SymbolMap* symMap) const
{
    if (symMap && symMap == memberAccessMap_)
        return memberAccess_;

    // An anonymous aggregate has no name to be reached by, and no declaration a modifier could be
    // written on: a returned tuple and an inline union are reached only through whatever holds
    // them, so that is what decides who reaches their members. Closing them again would leave them
    // unreachable with no syntax to open them.
    const auto* symStruct = symMap ? symMap->safeCast<SymbolStruct>() : nullptr;
    if (symStruct && symStruct->hasExtraFlag(SymbolStructFlagsE::Anonymous))
        return {MemberAccess::Public, false};

    return {};
}

SymbolFlags SemaFrame::flagsForCurrentAccess() const
{
    SymbolFlags flags = SymbolFlagsE::Zero;
    if (currentAccess() == SymbolAccess::Public)
        flags.add(SymbolFlagsE::Public);
    return flags;
}

SWC_END_NAMESPACE();
