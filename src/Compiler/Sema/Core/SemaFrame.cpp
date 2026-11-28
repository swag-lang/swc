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

void SemaFrame::pushScopeBindingType(TypeRef type)
{
    if (!type.isValid())
        return;

    bindingTypes_.push_back(type);
    std::rotate(bindingTypes_.begin() + scopeBindingCount_, bindingTypes_.end() - 1, bindingTypes_.end());
    ++scopeBindingCount_;
}

void SemaFrame::popBindingType()
{
    if (bindingTypes_.empty())
        return;

    bindingTypes_.pop_back();
    if (scopeBindingCount_ > bindingTypes_.size())
        scopeBindingCount_ = static_cast<uint32_t>(bindingTypes_.size());
}

void SemaFrame::clearBindingTypes()
{
    if (bindingTypes_.size() > scopeBindingCount_)
        bindingTypes_.resize(scopeBindingCount_);
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

void SemaFrame::addNarrowCaseFact(std::span<const Symbol* const> path, std::span<const ConstantRef> cases)
{
    if (path.empty())
        return;

    auto& fact = narrowFacts_.emplace_back();
    fact.path.assign(path.begin(), path.end());
    fact.cases = cases;
    fact.kind  = SemaNarrowFactKind::Case;
    fact.holds = true;
}

const SemaNarrowFact* SemaFrame::findNarrowCases(std::span<const SemaNarrowFact> facts, std::span<const Symbol* const> path)
{
    if (path.empty())
        return nullptr;

    for (size_t factIndex = facts.size(); factIndex > 0; --factIndex)
    {
        const SemaNarrowFact& fact = facts[factIndex - 1];
        if (fact.holds && fact.kind != SemaNarrowFactKind::Case)
            continue;

        if (fact.path.size() == path.size() && std::equal(fact.path.begin(), fact.path.end(), path.begin()))
            return fact.holds ? &fact : nullptr;

        if (!fact.holds && fact.path.size() < path.size() && std::equal(fact.path.begin(), fact.path.end(), path.begin()))
            return nullptr;
    }

    return nullptr;
}

bool SemaFrame::queryNarrowCases(std::span<const Symbol* const> path, std::span<const ConstantRef> allowed) const
{
    const SemaNarrowFact* fact = findNarrowCases(narrowFacts_.span(), path);
    if (!fact)
        return false;

    // Every case the path may hold must make the requested member active.
    return std::ranges::all_of(fact->cases, [&](ConstantRef value) { return std::ranges::find(allowed, value) != allowed.end(); });
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
    if (rootIds.empty() || narrowFacts_.empty())
        return;

    const auto keptEnd = std::remove_if(narrowFacts_.begin(), narrowFacts_.end(), [&](const SemaNarrowFact& fact) {
        const IdentifierRef rootId = fact.path.empty() ? IdentifierRef::invalid() : fact.path.front()->idRef();
        return std::ranges::find(rootIds, rootId) != rootIds.end();
    });

    // Keep survivor order: the most recent matching proof or kill still wins.
    narrowFacts_.resize(static_cast<size_t>(keptEnd - narrowFacts_.begin()));
}

bool SemaFrame::queryNarrowFact(std::span<const SemaNarrowFact> facts, std::span<const Symbol* const> path, SemaNarrowFactKind kind)
{
    if (path.empty())
        return false;

    // Newest fact wins: a kill pushed after a guard overrides it for the rest of its scope.
    for (size_t factIndex = facts.size(); factIndex > 0; --factIndex)
    {
        const SemaNarrowFact& fact = facts[factIndex - 1];

        // Proofs of another kind cannot answer this query, even when their paths match.
        if (fact.holds && fact.kind != kind)
            continue;

        if (fact.path.size() == path.size() && std::equal(fact.path.begin(), fact.path.end(), path.begin()))
            return fact.holds;

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
}

SymbolMap* SemaFrame::currentSymMap(Sema& sema)
{
    SymbolMap* symbolMap = sema.curSymMap();

    if (!sema.curScope().isTopLevel() || sema.curScope().isImpl())
        return symbolMap;

    // Explicit namespace scopes already have the resolved map. Re-rooting through
    // file/module visibility would create sibling namespaces with the same id,
    // splitting member declarations from qualified lookups.
    if (symbolMap && !sema.frame().nsPath().empty())
        return symbolMap;

    const SymbolAccess access = sema.frame().currentAccess();

    SymbolMap* root = nullptr;
    if (access == SymbolAccess::Private)
        root = &sema.fileNamespace();
    else
    {
        root = &sema.moduleNamespace();

        // Imported APIs and runtime files share the import-root namespace. Nesting
        // them under the importer would rename Lib.Color to Importer.Lib.Color and
        // give runtime types module-dependent full names and CRC identities.
        // Lookup still uses the module namespace to resolve Swag and sibling imports.
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

    // Anonymous aggregates cannot carry access modifiers. Their holders control
    // visibility; closing members would leave no syntax to make them accessible.
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
    else if (currentAccess() == SymbolAccess::Private)
        flags.add(SymbolFlagsE::Private);

    return flags;
}

SWC_END_NAMESPACE();
