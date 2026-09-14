#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Generic/GenericInstanceStorage.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaEscape.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestHeap.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class CompletedFreesFixture
    {
    public:
        explicit CompletedFreesFixture(TaskContext& ctx) :
            ctx_(&ctx),
            savedEdges_(ctx.compiler().takeEscapeSummaryEdges())
        {
        }

        ~CompletedFreesFixture()
        {
            ctx_->compiler().takeEscapeSummaryEdges();
            for (const SemaEscapeSummaryEdge& edge : savedEdges_)
                ctx_->compiler().addEscapeSummaryEdge(edge);
        }

        SymbolFunction* addFunction(bool completed = true)
        {
            const SymbolFlags flags    = completed ? SymbolFlagsE::SemaCompleted : SymbolFlagsE::Zero;
            auto*             function = Symbol::make<SymbolFunction>(*ctx_, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), flags);
            if (completed)
                completed_.push_back(function);
            return function;
        }

        void addEdge(const SemaEscapeSummaryEdge& edge) { ctx_->compiler().addEscapeSummaryEdge(edge); }
        void propagate() const { SemaEscape::propagateCompletedFreesSummaries(*ctx_, completed_); }

    private:
        TaskContext*                       ctx_;
        std::vector<SemaEscapeSummaryEdge> savedEdges_;
        std::vector<SymbolFunction*>       completed_;
    };

    class SemaDecisionFixture
    {
    public:
        SemaDecisionFixture(TaskContext& ctx, const std::string_view testName)
        {
            SourceFile& sourceFile = Unittest::addTestSource(ctx, "Sema", testName, "");
            auto [rootRef, root]   = sourceFile.ast().makeNode<AstNodeId::File>(TokenRef::invalid());
            SWC_UNUSED(root);
            sourceFile.ast().setRoot(rootRef);

            constexpr SymbolFlags namespaceFlags  = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
            auto*                 module          = Symbol::make<SymbolModule>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
            const IdentifierRef   namespaceId     = ctx.idMgr().addIdentifierOwned(std::format("SemaDecision_{}", testName));
            auto*                 moduleNamespace = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), namespaceId, namespaceFlags);
            module->addSingleSymbol(ctx, moduleNamespace);
            sourceFile.setModuleNamespace(*moduleNamespace);
            sourceFile.setFileNamespace(*moduleNamespace);

            sema_ = std::make_unique<Sema>(ctx, sourceFile.nodePayloadContext(), false);
        }

        Sema& sema() const { return *sema_; }

    private:
        std::unique_ptr<Sema> sema_;
    };

    int comparisonSign(const int value)
    {
        if (value < 0)
            return -1;
        if (value > 0)
            return 1;
        return 0;
    }
}

SWC_TEST_BEGIN(Sema_OverloadRankingUsesOrderedConversionCriteria)
{
    SWC_UNUSED(ctx);

    using Rank = Match::FunctionConversionRank;

    struct TestCase
    {
        const char*       name;
        std::vector<Rank> leftRanks;
        std::vector<Rank> rightRanks;
        uint32_t          leftDefaults;
        uint32_t          rightDefaults;
        bool              leftGeneric;
        bool              rightGeneric;
        int               expected;
    };

    const std::array cases = {
        TestCase{"equal", {Rank::Exact}, {Rank::Exact}, 0, 0, false, false, 0},
        TestCase{"first differing argument", {Rank::Exact, Rank::Standard}, {Rank::Standard, Rank::Exact}, 0, 0, false, false, -1},
        TestCase{"later differing argument", {Rank::Exact, Rank::Exact}, {Rank::Exact, Rank::Standard}, 0, 0, false, false, -1},
        TestCase{"shorter conversion list", {Rank::Exact}, {Rank::Exact, Rank::Exact}, 0, 0, false, false, -1},
        TestCase{"fewer defaults", {Rank::Exact}, {Rank::Exact}, 0, 1, false, false, -1},
        TestCase{"non-generic overload", {Rank::Exact}, {Rank::Exact}, 0, 0, false, true, -1},
        TestCase{"conversion rank precedes later tie breakers", {Rank::Exact}, {Rank::Standard}, 2, 0, true, false, -1},
    };

    for (const TestCase& test : cases)
    {
        const Match::FunctionCandidateRanking left  = {test.leftRanks, test.leftDefaults, test.leftGeneric};
        const Match::FunctionCandidateRanking right = {test.rightRanks, test.rightDefaults, test.rightGeneric};
        if (comparisonSign(Match::compareFunctionCandidateRankings(left, right)) != test.expected)
            return Result::Error;
        if (comparisonSign(Match::compareFunctionCandidateRankings(right, left)) != -test.expected)
            return Result::Error;
    }

    constexpr std::array orderedRanks = {Rank::Exact, Rank::Standard, Rank::CopyToMove, Rank::MoveToValue, Rank::Ellipsis, Rank::Bad};
    for (size_t leftIndex = 0; leftIndex < orderedRanks.size(); ++leftIndex)
    {
        for (size_t rightIndex = leftIndex + 1; rightIndex < orderedRanks.size(); ++rightIndex)
        {
            const std::array leftRanks  = {orderedRanks[leftIndex]};
            const std::array rightRanks = {orderedRanks[rightIndex]};
            if (Match::compareFunctionCandidateRankings({leftRanks, 0, false}, {rightRanks, 0, false}) >= 0)
                return Result::Error;
        }
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_ConcurrentSymbolExtraFlagsPreserveIndependentUpdates)
{
    SWC_UNUSED(ctx);

    constexpr size_t NUM_WORKERS = 6;
    constexpr size_t NUM_ROUNDS  = 4096;
    constexpr auto   ALL_FLAGS   = static_cast<SymbolFunctionFlagsE>((1u << NUM_WORKERS) - 1);

    SymbolFunction                       function(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    bool                                 expectAll = true;
    bool                                 failed    = false;
    std::barrier                         rendezvous(NUM_WORKERS, [&]() noexcept {
        const auto expected = expectAll ? ALL_FLAGS : SymbolFunctionFlagsE::Zero;
        failed              = failed || function.semanticFlags() != SymbolFunctionFlags{expected};
        expectAll           = !expectAll;
    });
    std::array<std::thread, NUM_WORKERS> workers;
    for (size_t worker = 0; worker < NUM_WORKERS; ++worker)
    {
        workers[worker] = std::thread([&, worker] {
            const auto flag = static_cast<SymbolFunctionFlagsE>(1u << worker);
            for (size_t round = 0; round < NUM_ROUNDS; ++round)
            {
                // Each worker owns one bit, while the symbol is shared by all workers.
                function.addExtraFlag(flag);
                rendezvous.arrive_and_wait();
                function.removeExtraFlag(flag);
                rendezvous.arrive_and_wait();
            }
        });
    }
    for (auto& worker : workers)
        worker.join();
    if (failed)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_GlobalStoragePublicationSurvivesConcurrentFlags)
{
    SWC_UNUSED(ctx);

    constexpr size_t NUM_WORKERS = 6;
    constexpr size_t NUM_ROUNDS  = 4096;
    SymbolVariable   variable(nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    variable.setDeclaredGlobal(true);

    bool                                 expectPublished = true;
    bool                                 failed          = false;
    uint32_t                             expectedOffset  = 8;
    std::barrier                         rendezvous(NUM_WORKERS, [&]() noexcept {
        if (expectPublished)
        {
            failed = failed || !variable.hasGlobalStorage() || !variable.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
            failed = failed || variable.globalStorageKind() != DataSegmentKind::GlobalZero || variable.offset() != expectedOffset;
        }
        else
        {
            failed = failed || variable.hasGlobalStorage() || variable.hasExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
            expectedOffset += 8;
        }
        expectPublished = !expectPublished;
    });
    std::array<std::thread, NUM_WORKERS> workers;
    for (size_t worker = 0; worker < NUM_WORKERS; ++worker)
    {
        workers[worker] = std::thread([&, worker] {
            for (size_t round = 0; round < NUM_ROUNDS; ++round)
            {
                // Publishing storage must survive other users requesting an address
                // for the same symbol; losing GlobalStorage selects local codegen.
                if (worker == 0)
                    variable.setGlobalStorage(DataSegmentKind::GlobalZero, static_cast<uint32_t>((round + 1) * 8));
                else
                    variable.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
                rendezvous.arrive_and_wait();
                variable.removeExtraFlag(worker == 0 ? SymbolVariableFlagsE::GlobalStorage : SymbolVariableFlagsE::NeedsAddressableStorage);
                rendezvous.arrive_and_wait();
            }
        });
    }
    for (auto& worker : workers)
        worker.join();
    if (failed)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_GenericMethodSignaturePublishesLazyBody)
{
    SemaDecisionFixture fixture(ctx, "GenericMethodSignaturePublishesLazyBody");
    Sema&               sema = fixture.sema();
    auto [declRef, decl]     = sema.ast().makeNode<AstNodeId::FunctionDecl>(TokenRef::invalid());
    auto [paramsRef, params] = sema.ast().makeNode<AstNodeId::FunctionParamList>(TokenRef::invalid());
    auto [bodyRef, body]     = sema.ast().makeNode<AstNodeId::EmbeddedBlock>(TokenRef::invalid());
    SWC_UNUSED(params);
    SWC_UNUSED(body);
    decl->nodeParamsRef = paramsRef;
    decl->nodeBodyRef   = bodyRef;

    constexpr SymbolFlags ownerFlags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
    const IdentifierRef   ownerId    = ctx.idMgr().addIdentifierOwned("LazySignatureOwner");
    const IdentifierRef   methodId   = ctx.idMgr().addIdentifierOwned("lazySignatureMethod");
    auto*                 root       = Symbol::make<SymbolStruct>(ctx, nullptr, TokenRef::invalid(), ownerId, ownerFlags);
    auto*                 owner      = Symbol::make<SymbolStruct>(ctx, nullptr, TokenRef::invalid(), ownerId, ownerFlags);
    owner->setGenericInstance(root, {});

    auto* function = Symbol::make<SymbolFunction>(ctx, decl, TokenRef::invalid(), methodId, SymbolFlagsE::Declared);
    function->addExtraFlag(SymbolFunctionFlagsE::Method);
    function->setDeclNodeRef(declRef);
    function->setDeclNodePayloadContext(&sema.currentNodePayloadContext());
    owner->addSingleSymbol(ctx, function);
    sema.setSymbol(declRef, function);

    // Stop exactly where signature-only preparation publishes the callable symbol.
    // The declaring walk has not visited the body, so a caller must already know
    // that it needs to complete that body before using its borrow summary.
    Sema functionSema(ctx, sema, declRef);
    SWC_RESULT(decl->semaPostNodeChild(functionSema, paramsRef));
    if (!function->isTyped() || function->isSemaCompleted())
        return Result::Error;
    if (!function->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_DeclarationReplayPreservesPublishedAttributeStorage)
{
    SemaDecisionFixture fixture(ctx, "DeclarationReplayPreservesPublishedAttributeStorage");
    Sema&               sema = fixture.sema();
    auto [declRef, decl]     = sema.ast().makeNode<AstNodeId::FunctionDecl>(TokenRef::invalid());
    auto [paramsRef, params] = sema.ast().makeNode<AstNodeId::FunctionParamList>(TokenRef::invalid());
    auto [bodyRef, body]     = sema.ast().makeNode<AstNodeId::EmbeddedBlock>(TokenRef::invalid());
    SWC_UNUSED(params);
    SWC_UNUSED(body);
    decl->nodeParamsRef = paramsRef;
    decl->nodeBodyRef   = bodyRef;

    constexpr SymbolFlags ownerFlags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
    const IdentifierRef   ownerId    = ctx.idMgr().addIdentifierOwned("AttributeReplayOwner");
    const IdentifierRef   methodId   = ctx.idMgr().addIdentifierOwned("attributeReplayFunction");
    auto*                 owner      = Symbol::make<SymbolStruct>(ctx, nullptr, TokenRef::invalid(), ownerId, ownerFlags);
    auto*                 function   = Symbol::make<SymbolFunction>(ctx, decl, TokenRef::invalid(), methodId, SymbolFlagsE::Zero);
    function->setDeclNodeRef(declRef);
    function->setDeclNodePayloadContext(&sema.currentNodePayloadContext());
    owner->addSingleSymbol(ctx, function);
    sema.setSymbol(declRef, function);

    // More than four parameters give the attribute owned storage. Even assigning
    // an identical list destroys and rebuilds that storage through SmallVector.
    AttributeInstance attribute;
    attribute.params.resize(8);
    sema.frame().currentAttributes().attributes.push_back(std::move(attribute));
    sema.frame().currentAttributes().addRtFlag(RtAttributeFlagsE::Inline);
    SWC_RESULT(sema.prepareFunctionSignature(declRef));
    if (!function->isDeclared() || !function->isTyped())
        return Result::Error;

    Sema replay(ctx, sema, declRef);
    bool preserved = false;
    {
        // A later walk may reuse the declaration while another worker retains its
        // published attributes. Rebinding local scopes must not replace their data.
        Unittest::ScopedHeap heap;
        SemaHelpers::declareSymbol(replay, *decl);
        preserved             = heap.empty();
        const auto& published = function->attributes();
        preserved             = preserved && published.attributes.size() == 1 && published.attributes.front().params.size() == 8 && published.hasRtFlag(RtAttributeFlagsE::Inline);

        // Release any replacement buffer before its isolated heap is destroyed.
        function->ensureAttributes(ctx).attributes.clear();
    }
    if (!preserved)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_MatchCandidateCollectionPreservesUniqueDiscoveryOrder)
{
    constexpr MatchContext::Priority local{0, MatchContext::VisibilityTier::LocalScope};
    constexpr MatchContext::Priority outer{1, MatchContext::VisibilityTier::LocalScope};

    MatchContext               match;
    SmallVector<const Symbol*> collected;
    std::vector<const Symbol*> functions;

    for (uint32_t index = 0; index < 64; ++index)
    {
        const Symbol* function = Symbol::make<SymbolFunction>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        functions.push_back(function);
        match.addSymbol(function, outer);
        match.addSymbol(function, outer);
    }
    // Rediscovering the outer candidates at a better priority must not reorder them.
    for (auto it = functions.rbegin(); it != functions.rend(); ++it)
        match.addSymbol(*it, local);
    match.collectCallFallbackSymbols(collected);
    if (!std::ranges::equal(collected, functions))
        return Result::Error;
    match.collectCallableSymbols(collected);
    if (!std::ranges::equal(collected, functions))
        return Result::Error;

    const Symbol* namespaceSymbol = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    match.addSymbol(namespaceSymbol, local);
    match.collectCallFallbackSymbols(collected);
    if (!collected.empty())
        return Result::Error;
    match.collectCallableSymbols(collected);
    if (!std::ranges::equal(collected, functions))
        return Result::Error;

    match.replaceWithSingleSymbol(functions.back());
    match.collectCallFallbackSymbols(collected);
    if (collected.size() != 1 || collected.front() != functions.back())
        return Result::Error;
    match.clear();
    match.collectCallableSymbols(collected);
    if (!collected.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_GenericInstanceStoragePreservesIdentityAcrossGrowth)
{
    GenericInstanceStorage          storage;
    std::vector<Symbol*>            instances;
    SmallVector<GenericInstanceKey> args;
    SmallVector<GenericInstanceKey> recovered;

    // Alternate inline and allocated argument lists while forcing several rehashes.
    for (uint32_t index = 0; index < 512; ++index)
    {
        Symbol* instance = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        args.clear();
        const uint32_t count = index % 2 ? 20 : 2;
        for (uint32_t arg = 0; arg < count; ++arg)
            args.push_back({TypeRef(index), ConstantRef(arg)});

        if (storage.find(args.span()) || storage.add(args.span(), instance) != instance)
            return Result::Error;
        instances.push_back(instance);
    }

    for (uint32_t index = 0; index < instances.size(); ++index)
    {
        args.clear();
        const uint32_t count = index % 2 ? 20 : 2;
        for (uint32_t arg = 0; arg < count; ++arg)
            args.push_back({TypeRef(index), ConstantRef(arg)});

        if (storage.find(args.span()) != instances[index])
            return Result::Error;
        if (!storage.tryGetArgs(*instances[index], recovered) || !std::ranges::equal(args, recovered))
            return Result::Error;
        // An existing argument list wins even when the supplied symbol is already
        // associated with a different list. Reusing a symbol never adds an alias key.
        if (storage.add(args.span(), instances.front()) != instances[index])
            return Result::Error;
    }

    args = {{TypeRef(900), ConstantRef(1)}, {TypeRef(900), ConstantRef(0)}};
    if (storage.add(args.span(), instances.front()) != instances.front() || storage.find(args.span()))
        return Result::Error;
    args = {{TypeRef(0), ConstantRef(1)}, {TypeRef(0), ConstantRef(0)}};
    if (storage.find(args.span()))
        return Result::Error;

    Symbol* emptyInstance = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    if (storage.add({}, emptyInstance) != emptyInstance || storage.find({}) != emptyInstance)
        return Result::Error;
    if (!storage.tryGetArgs(*emptyInstance, recovered) || !recovered.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_AggregateTypeInterningUsesOrderedContents)
{
    // This manager needs only handle identity, so synthetic element and name refs suffice.
    TypeManager                                 manager;
    constexpr size_t                            count = 256;
    std::array<std::array<TypeRef, count>, 3>   refs;
    std::array<std::unordered_set<uint32_t>, 3> hashes;
    const std::array                            fixedTypes = {TypeRef{1}, TypeRef{2}, TypeRef{3}, TypeRef{4}};
    const std::array                            fixedNames = {IdentifierRef::invalid(), IdentifierRef{2}, IdentifierRef{3}, IdentifierRef{4}};

    // Keep long common prefixes and vary types independently from names. The second
    // pass checks that table growth and temporary input lifetimes preserve interning.
    for (size_t pass = 0; pass < 2; ++pass)
    {
        for (uint32_t index = 0; index < count; ++index)
        {
            auto types                  = fixedTypes;
            auto names                  = fixedNames;
            types.back()                = TypeRef{index + 4};
            names.back()                = IdentifierRef{index + 4};
            const std::array candidates = {TypeInfo::makeAggregateArray(types), TypeInfo::makeAggregateStruct(fixedNames, types), TypeInfo::makeAggregateStruct(names, fixedTypes)};
            for (size_t kind = 0; kind < candidates.size(); ++kind)
            {
                const TypeRef ref = manager.addType(candidates[kind]);
                if (!(manager.get(ref) == candidates[kind]))
                    return Result::Error;
                if (!pass)
                {
                    refs[kind][index] = ref;
                    hashes[kind].insert(candidates[kind].hash());
                }
                else if (refs[kind][index] != ref || manager.get(ref).hash() != candidates[kind].hash())
                    return Result::Error;
            }
        }
    }

    for (size_t kind = 0; kind < refs.size(); ++kind)
    {
        const std::unordered_set<TypeRef> uniqueRefs(refs[kind].begin(), refs[kind].end());
        // Allow hash collisions, while rejecting the old single bucket per arity.
        if (uniqueRefs.size() != count || hashes[kind].size() < count / 2)
            return Result::Error;
    }

    auto reversedTypes = fixedTypes;
    auto reversedNames = fixedNames;
    std::ranges::reverse(reversedTypes);
    std::ranges::reverse(reversedNames);
    if (manager.addType(TypeInfo::makeAggregateArray(reversedTypes)) == refs[0][0])
        return Result::Error;
    if (manager.addType(TypeInfo::makeAggregateStruct(fixedNames, reversedTypes)) == refs[1][0])
        return Result::Error;
    if (manager.addType(TypeInfo::makeAggregateStruct(reversedNames, fixedTypes)) == refs[2][0])
        return Result::Error;

    TypeInfo       copy(manager.get(refs[1][count - 1]));
    const TypeInfo moved(std::move(copy));
    if (manager.addType(moved) != refs[1][count - 1])
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_TypeManagerConcurrentInterningKeepsCanonicalStorage)
{
    constexpr size_t NUM_WORKERS = 2;
    // The three families exceed one default storage page per shard, even when evenly spread.
    constexpr size_t NUM_TYPES  = 1024;
    constexpr size_t NUM_FIELDS = 32;

    TypeManager                                                     manager;
    std::barrier                                                    rendezvous(NUM_WORKERS);
    std::array<std::thread, NUM_WORKERS>                            workers;
    std::array<std::array<TypeRef, NUM_TYPES>, NUM_WORKERS>         commonRefs;
    std::array<std::array<TypeRef, NUM_TYPES>, NUM_WORKERS>         uniqueRefs;
    std::array<std::array<const TypeInfo*, NUM_TYPES>, NUM_WORKERS> addresses;

    for (size_t worker = 0; worker < NUM_WORKERS; ++worker)
    {
        workers[worker] = std::thread([&, worker] {
            std::array<TypeRef, NUM_FIELDS> types;
            types.fill(TypeRef{1});
            for (uint32_t index = 0; index < NUM_TYPES; ++index)
            {
                // Race equal insertions, then grow other stripes while readers retain
                // pointers into earlier pages. Each source array is temporary input.
                types.back() = TypeRef{index + 1000};
                rendezvous.arrive_and_wait();
                commonRefs[worker][index] = manager.addType(TypeInfo::makeAggregateArray(types));
                addresses[worker][index]  = &manager.get(commonRefs[worker][index]);
                types.back()              = TypeRef{static_cast<uint32_t>(1000 + (worker + 1) * NUM_TYPES + index)};
                uniqueRefs[worker][index] = manager.addType(TypeInfo::makeAggregateArray(types));
            }
        });
    }
    for (auto& worker : workers)
        worker.join();

    std::unordered_set<TypeRef> allRefs;
    for (size_t index = 0; index < NUM_TYPES; ++index)
    {
        if (commonRefs[0][index] != commonRefs[1][index])
            return Result::Error;
        allRefs.insert(commonRefs[0][index]);
        for (size_t worker = 0; worker < NUM_WORKERS; ++worker)
        {
            const TypeRef   ref  = commonRefs[worker][index];
            const TypeInfo& type = manager.get(ref);
            if (&type != addresses[worker][index] || type.typeRef() != ref)
                return Result::Error;
            const auto& elements = type.payloadAggregate().types;
            if (elements.size() != NUM_FIELDS || elements.back() != TypeRef{static_cast<uint32_t>(index + 1000)})
                return Result::Error;
            for (size_t field = 0; field + 1 < elements.size(); ++field)
                if (elements[field] != TypeRef{1})
                    return Result::Error;

            const TypeRef duplicate = manager.addType(type);
            if (duplicate != ref)
                return Result::Error;
#if SWC_HAS_REF_DEBUG_INFO
            if (ref.dbgPtr != &type || type.typeRef().dbgPtr != &type || duplicate.dbgPtr != &type)
                return Result::Error;
#endif
            const TypeRef unique = uniqueRefs[worker][index];
            allRefs.insert(unique);
            if (manager.get(unique).payloadAggregate().types.back() != TypeRef{static_cast<uint32_t>(1000 + (worker + 1) * NUM_TYPES + index)})
                return Result::Error;
        }
    }
    if (allRefs.size() != NUM_TYPES * (NUM_WORKERS + 1))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_TypeManagerReleasesOwnedPayloads)
{
    // Observe only this thread's isolated allocations, including the vectors inside
    // arena objects. Releasing arena pages alone must not make this test pass.
    Unittest::ScopedHeap heap;
    if (!heap.empty())
        return Result::Error;
    {
        TypeManager      manager;
        const std::array names = {IdentifierRef{1}, IdentifierRef{2}, IdentifierRef{3}};
        for (uint32_t index = 0; index < 64; ++index)
        {
            const std::array types      = {TypeRef{1}, TypeRef{2}, TypeRef{index + 3}};
            const std::array dims       = {uint64_t{index + 1}, uint64_t{2}};
            const std::array indexTypes = {TypeRef{1}, TypeRef{2}};
            manager.addType(TypeInfo::makeAggregateStruct(names, types));
            manager.addType(TypeInfo::makeAggregateArray(types));
            manager.addType(TypeInfo::makeArray(dims, types.back(), TypeInfoFlagsE::Zero, indexTypes));
        }
    }
    if (!heap.empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_CastLegalityCoversScalarConversionKinds)
{
    SemaDecisionFixture fixture(ctx, "CastLegalityCoversScalarConversionKinds");
    Sema&               sema    = fixture.sema();
    TypeManager&        typeMgr = sema.typeMgr();

    struct TestCase
    {
        const char*  name;
        CastKind     kind;
        TypeRef      source;
        TypeRef      target;
        Result       expected;
        DiagnosticId expectedDiagnostic;
    };

    const std::array cases = {
        TestCase{"identity", CastKind::Implicit, typeMgr.typeS32(), typeMgr.typeS32(), Result::Continue, DiagnosticId::None},
        TestCase{"integer widening", CastKind::Implicit, typeMgr.typeS8(), typeMgr.typeS64(), Result::Continue, DiagnosticId::None},
        TestCase{"implicit integer narrowing", CastKind::Implicit, typeMgr.typeS64(), typeMgr.typeS8(), Result::Error, DiagnosticId::sema_err_cannot_cast},
        TestCase{"explicit integer narrowing", CastKind::Explicit, typeMgr.typeS64(), typeMgr.typeS8(), Result::Continue, DiagnosticId::None},
        TestCase{"implicit bool to integer", CastKind::Implicit, typeMgr.typeBool(), typeMgr.typeS32(), Result::Error, DiagnosticId::sema_err_cannot_cast},
        TestCase{"explicit bool to integer", CastKind::Explicit, typeMgr.typeBool(), typeMgr.typeS32(), Result::Continue, DiagnosticId::None},
        TestCase{"implicit 32-bit integer to float", CastKind::Implicit, typeMgr.typeS32(), typeMgr.typeF32(), Result::Continue, DiagnosticId::None},
        TestCase{"implicit 64-bit integer to f32", CastKind::Implicit, typeMgr.typeS64(), typeMgr.typeF32(), Result::Error, DiagnosticId::sema_err_cannot_cast},
        TestCase{"implicit float to integer", CastKind::Implicit, typeMgr.typeF32(), typeMgr.typeS32(), Result::Error, DiagnosticId::sema_err_cannot_cast},
        TestCase{"explicit float to integer", CastKind::Explicit, typeMgr.typeF32(), typeMgr.typeS32(), Result::Continue, DiagnosticId::None},
        TestCase{"float widening", CastKind::Implicit, typeMgr.typeF32(), typeMgr.typeF64(), Result::Continue, DiagnosticId::None},
        TestCase{"assignment float narrowing", CastKind::Assignment, typeMgr.typeF64(), typeMgr.typeF32(), Result::Error, DiagnosticId::sema_err_cannot_cast},
        TestCase{"parameter float narrowing", CastKind::Parameter, typeMgr.typeF64(), typeMgr.typeF32(), Result::Continue, DiagnosticId::None},
        TestCase{"condition to bool", CastKind::Condition, typeMgr.typeS32(), typeMgr.typeBool(), Result::Continue, DiagnosticId::None},
    };

    const AstNodeRef errorNodeRef = sema.ast().root();
    for (const TestCase& test : cases)
    {
        CastRequest request(test.kind);
        request.errorNodeRef = errorNodeRef;
        const Result result  = Cast::castAllowed(sema, request, test.source, test.target);
        if (result != test.expected || request.failure.diagId != test.expectedDiagnostic)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_GenericDeductionBindingHandlesConflictsAndDefaults)
{
    using Mode = SemaGeneric::Internal::GenericDeductionMode;

    SemaDecisionFixture fixture(ctx, "GenericDeductionBindingHandlesConflictsAndDefaults");
    Sema&               sema    = fixture.sema();
    TypeManager&        typeMgr = sema.typeMgr();
    const IdentifierRef typeId  = sema.idMgr().addIdentifierOwned("T");
    const IdentifierRef valueId = sema.idMgr().addIdentifierOwned("N");

    const SemaGeneric::GenericParamDesc typeParam = {
        .kind  = SemaGeneric::GenericParamKind::Type,
        .idRef = typeId,
    };

    struct TypeTestCase
    {
        const char*  name;
        TypeRef      initial;
        TypeRef      incoming;
        Mode         mode;
        bool         expectedResult;
        TypeRef      expectedType;
        DiagnosticId expectedDiagnostic;
    };

    const std::array typeCases = {
        TypeTestCase{"first deduction", TypeRef::invalid(), typeMgr.typeS32(), Mode::Normal, true, typeMgr.typeS32(), DiagnosticId::None},
        TypeTestCase{"identical deduction", typeMgr.typeS32(), typeMgr.typeS32(), Mode::Normal, true, typeMgr.typeS32(), DiagnosticId::None},
        TypeTestCase{"concretize unsized deduction", typeMgr.typeInt(), typeMgr.typeS32(), Mode::Normal, true, typeMgr.typeS32(), DiagnosticId::None},
        TypeTestCase{"keep concrete deduction", typeMgr.typeS32(), typeMgr.typeInt(), Mode::Normal, true, typeMgr.typeS32(), DiagnosticId::None},
        TypeTestCase{"accept compatible numeric deduction", typeMgr.typeS32(), typeMgr.typeS16(), Mode::Normal, true, typeMgr.typeS32(), DiagnosticId::None},
        TypeTestCase{"reject conflicting type deduction", typeMgr.typeBool(), typeMgr.typeString(), Mode::Normal, false, typeMgr.typeBool(), DiagnosticId::sema_err_generic_type_deduction_conflict},
        TypeTestCase{"default does not replace fixed deduction", typeMgr.typeBool(), typeMgr.typeString(), Mode::MissingOnly, true, typeMgr.typeBool(), DiagnosticId::None},
    };

    for (const TypeTestCase& test : typeCases)
    {
        std::array<SemaGeneric::GenericResolvedArg, 1> resolvedArgs{};
        if (test.initial.isValid())
        {
            resolvedArgs[0].present      = true;
            resolvedArgs[0].typeRef      = test.initial;
            resolvedArgs[0].callArgIndex = 1;
        }

        CastFailure failure;
        const bool  result = SemaGeneric::Internal::bindGenericTypeParam(sema, std::span{&typeParam, 1}, resolvedArgs, typeId, AstNodeRef::invalid(), 2, test.incoming, &failure, test.mode);
        if (result != test.expectedResult || resolvedArgs[0].typeRef != test.expectedType || failure.diagId != test.expectedDiagnostic)
            return Result::Error;
        if (!resolvedArgs[0].present)
            return Result::Error;
    }

    const SemaGeneric::GenericParamDesc valueParam = {
        .kind  = SemaGeneric::GenericParamKind::Value,
        .idRef = valueId,
    };
    const ConstantRef zero = sema.cstMgr().cstS32(0);
    const ConstantRef one  = sema.cstMgr().cstS32(1);

    struct ValueTestCase
    {
        const char*  name;
        ConstantRef  initial;
        ConstantRef  incoming;
        Mode         mode;
        bool         expectedResult;
        ConstantRef  expectedValue;
        DiagnosticId expectedDiagnostic;
    };

    const std::array valueCases = {
        ValueTestCase{"first value deduction", ConstantRef::invalid(), zero, Mode::Normal, true, zero, DiagnosticId::None},
        ValueTestCase{"identical value deduction", zero, zero, Mode::Normal, true, zero, DiagnosticId::None},
        ValueTestCase{"reject conflicting value deduction", zero, one, Mode::Normal, false, zero, DiagnosticId::sema_err_generic_value_deduction_conflict},
        ValueTestCase{"default does not replace fixed value", zero, one, Mode::MissingOnly, true, zero, DiagnosticId::None},
    };

    for (const ValueTestCase& test : valueCases)
    {
        std::array<SemaGeneric::GenericResolvedArg, 1> resolvedArgs{};
        if (test.initial.isValid())
        {
            resolvedArgs[0].present      = true;
            resolvedArgs[0].typeRef      = typeMgr.typeS32();
            resolvedArgs[0].cstRef       = test.initial;
            resolvedArgs[0].callArgIndex = 1;
        }

        CastFailure failure;
        const bool  result = SemaGeneric::Internal::bindGenericValueParam(sema, std::span{&valueParam, 1}, resolvedArgs, valueId, AstNodeRef::invalid(), 2, test.incoming, typeMgr.typeS32(), &failure, test.mode);
        if (result != test.expectedResult || resolvedArgs[0].cstRef != test.expectedValue || failure.diagId != test.expectedDiagnostic)
            return Result::Error;
        if (!resolvedArgs[0].present)
            return Result::Error;
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_CompletedFreesSummariesKeepDirectForwardingTransitive)
{
    CompletedFreesFixture fixture(ctx);
    auto*                 outer   = fixture.addFunction();
    auto*                 middle  = fixture.addFunction();
    auto*                 leaf    = fixture.addFunction();
    auto*                 owned   = fixture.addFunction();
    auto*                 carried = fixture.addFunction();
    auto*                 pending = fixture.addFunction(false);
    leaf->addFreesParam(2);

    // Reverse dependency order requires another frees iteration after middle grows.
    fixture.addEdge({.caller = outer, .callee = middle, .callerParamIndex = 0, .calleeParamIndex = 1, .kind = SemaEscapeSummaryEdgeKind::StoresToStores});
    fixture.addEdge({.caller = middle, .callee = leaf, .callerParamIndex = 1, .calleeParamIndex = 2, .kind = SemaEscapeSummaryEdgeKind::StoresToStores});
    fixture.addEdge({.caller = owned, .callee = leaf, .calleeParamIndex = 2, .kind = SemaEscapeSummaryEdgeKind::StoresToStores, .viaOwnedPayload = true});
    fixture.addEdge({.caller = carried, .callee = leaf, .calleeParamIndex = 2, .kind = SemaEscapeSummaryEdgeKind::StoresToStores, .viaStoredField = true});
    fixture.addEdge({.caller = pending, .callee = leaf, .calleeParamIndex = 2, .kind = SemaEscapeSummaryEdgeKind::StoresToStores});
    fixture.propagate();

    if (outer->freesParamsMask() != 1 || middle->freesParamsMask() != 2 || leaf->freesParamsMask() != 4)
        return Result::Error;
    if (owned->freesParamsMask() || carried->freesParamsMask() || pending->freesParamsMask())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_CompletedFreesSummariesResolveGuardedAliasRoutes)
{
    CompletedFreesFixture fixture(ctx);
    auto*                 outer           = fixture.addFunction();
    auto*                 middle          = fixture.addFunction();
    auto*                 leaf            = fixture.addFunction();
    auto*                 aliasWrapper    = fixture.addFunction();
    auto*                 aliasLeaf       = fixture.addFunction();
    auto*                 payloadAlias    = fixture.addFunction();
    auto*                 borrowOnly      = fixture.addFunction();
    auto*                 incompleteAlias = fixture.addFunction();
    auto*                 unresolved      = fixture.addFunction(false);
    auto*                 payloadOwner    = fixture.addFunction();
    auto*                 nonAliasOwner   = fixture.addFunction();
    auto*                 unresolvedOwner = fixture.addFunction();
    leaf->addFreesParam(2);
    aliasLeaf->addReturnBorrowsParam(2);
    aliasLeaf->addReturnsStorageParam(2);
    payloadAlias->addReturnBorrowsParam(0);
    payloadAlias->addReturnsStorageParam(0);
    payloadAlias->addReturnsPayloadParam(0);
    borrowOnly->addReturnBorrowsParam(0);
    incompleteAlias->addReturnBorrowsParam(0);
    incompleteAlias->addReturnsStorageParam(0);

    fixture.addEdge({.caller = outer, .callee = middle, .calleeParamIndex = 1, .kind = SemaEscapeSummaryEdgeKind::StoresToStores});
    fixture.addEdge({.caller = middle, .callee = leaf, .callerParamIndex = 1, .calleeParamIndex = 2, .kind = SemaEscapeSummaryEdgeKind::StoresToStores, .returnGuards = {{aliasWrapper, 1}}});
    fixture.addEdge({.caller = payloadOwner, .callee = leaf, .calleeParamIndex = 2, .kind = SemaEscapeSummaryEdgeKind::StoresToStores, .returnGuards = {{aliasWrapper, 1}, {payloadAlias, 0}}});
    fixture.addEdge({.caller = nonAliasOwner, .callee = leaf, .calleeParamIndex = 2, .kind = SemaEscapeSummaryEdgeKind::StoresToStores, .returnGuards = {{borrowOnly, 0}}});
    fixture.addEdge({.caller = unresolvedOwner, .callee = leaf, .calleeParamIndex = 2, .kind = SemaEscapeSummaryEdgeKind::StoresToStores, .returnGuards = {{incompleteAlias, 0}}});
    fixture.addEdge({.caller = aliasWrapper, .callee = aliasLeaf, .callerParamIndex = 1, .calleeParamIndex = 2});
    fixture.addEdge({.caller = incompleteAlias, .callee = unresolved});
    fixture.propagate();

    if (outer->freesParamsMask() != 1 || middle->freesParamsMask() != 2)
        return Result::Error;
    if (payloadOwner->freesParamsMask() || nonAliasOwner->freesParamsMask() || unresolvedOwner->freesParamsMask())
        return Result::Error;
    // Completed return masks belong to parallel readers and must remain untouched.
    if (aliasWrapper->returnBorrowsParamsMask() || aliasWrapper->returnsStorageParamsMask())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_NarrowRootKillsPreserveSurvivorOrder)
{
    SymbolVariable                     kept(nullptr, TokenRef::invalid(), IdentifierRef{1}, {});
    SymbolVariable                     killed(nullptr, TokenRef::invalid(), IdentifierRef{2}, {});
    SymbolVariable                     sameRootName(nullptr, TokenRef::invalid(), IdentifierRef{2}, {});
    SymbolVariable                     other(nullptr, TokenRef::invalid(), IdentifierRef{3}, {});
    SymbolVariable                     field(nullptr, TokenRef::invalid(), IdentifierRef{4}, {});
    const std::array<const Symbol*, 1> keptPath  = {&kept};
    const std::array<const Symbol*, 1> otherPath = {&other};
    const std::array<const Symbol*, 5> deepPath  = {&kept, &field, &field, &field, &field};
    SemaFrame                          frame;
    frame.addNarrowFact(keptPath, SemaNarrowFactKind::NonNull);
    frame.addNarrowFact(std::array<const Symbol*, 1>{&killed}, SemaNarrowFactKind::NonNull);
    frame.addNarrowKill(keptPath);
    frame.addNarrowFact(std::array<const Symbol*, 1>{&sameRootName}, SemaNarrowFactKind::NonZero);
    frame.addNarrowFact(keptPath, SemaNarrowFactKind::NonZero);
    frame.addNarrowFact(otherPath, SemaNarrowFactKind::NonNull);
    frame.addNarrowFact(deepPath, SemaNarrowFactKind::NonNull);
    const std::vector<SemaNarrowFact> original(frame.narrowFacts().begin(), frame.narrowFacts().end());

    const std::array absentRoot     = {IdentifierRef{99}};
    const std::array unchangedRoots = {std::span<const IdentifierRef>{}, std::span<const IdentifierRef>(absentRoot)};
    for (const auto roots : unchangedRoots)
    {
        frame.killNarrowFactsByRootId(roots);
        const auto facts = frame.narrowFacts();
        if (facts.size() != original.size())
            return Result::Error;
        for (size_t index = 0; index < facts.size(); ++index)
            if (facts[index].kind != original[index].kind || facts[index].holds != original[index].holds || !std::ranges::equal(facts[index].path, original[index].path))
                return Result::Error;
    }

    frame.killNarrowFactsByRootId(std::array{IdentifierRef{2}, IdentifierRef{2}});
    const std::array<size_t, 5> survivors = {0, 2, 4, 5, 6};
    const auto                  facts     = frame.narrowFacts();
    if (facts.size() != survivors.size())
        return Result::Error;
    for (size_t index = 0; index < facts.size(); ++index)
    {
        const SemaNarrowFact& expected = original[survivors[index]];
        if (facts[index].kind != expected.kind || facts[index].holds != expected.holds || !std::ranges::equal(facts[index].path, expected.path))
            return Result::Error;
    }
    if (frame.queryNarrowFact(keptPath, SemaNarrowFactKind::NonNull) || !frame.queryNarrowFact(keptPath, SemaNarrowFactKind::NonZero))
        return Result::Error;
    if (!frame.queryNarrowFact(otherPath, SemaNarrowFactKind::NonNull) || !frame.queryNarrowFact(deepPath, SemaNarrowFactKind::NonNull))
        return Result::Error;
    frame.killNarrowFactsByRootId(std::array{IdentifierRef{1}, IdentifierRef{3}});
    if (frame.hasNarrowFacts())
        return Result::Error;
    frame.killNarrowFactsByRootId(std::array{IdentifierRef{1}});
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_SanityOverrideSummaryPreservesOrderAndFrameInheritance)
{
    std::vector<RuntimeSafetyOverride> overrides  = {{0, true}, {0, false}, {UINT16_MAX, false}, {0x5555, true}, {0xAAAA, true}, {0x5555, false}, {UINT16_MAX, true}};
    std::array<uint16_t, 20>           buildMasks = {0, UINT16_MAX, 0x5555, 0xAAAA};
    for (uint32_t bit = 0; bit < 16; ++bit)
    {
        const auto mask     = static_cast<uint16_t>(1u << bit);
        buildMasks[bit + 4] = mask;
        overrides.push_back({mask, false});
        overrides.push_back({mask, true});
    }

    SemaFrame frame;
    if (!frame.currentAttributes().empty())
        return Result::Error;
    for (size_t index = 0; index < overrides.size(); ++index)
    {
        const auto& current = overrides[index];
        frame.currentAttributes().addSanityOverride(static_cast<Runtime::SafetyWhat>(current.whatMask), current.value);
        // Even a zero-mask declaration is an attribute, despite changing no guard bits.
        if (frame.currentAttributes().empty())
            return Result::Error;

        SemaFrame inherited = frame;
        for (const uint16_t buildMask : buildMasks)
        {
            uint16_t expected = buildMask;
            for (size_t applied = 0; applied <= index; ++applied)
            {
                const auto& entry = overrides[applied];
                if (entry.value)
                    expected |= entry.whatMask;
                else
                    expected &= ~entry.whatMask;
            }

            const auto buildCfgMask = static_cast<Runtime::SafetyWhat>(buildMask);
            if (frame.currentAttributes().effectiveSanityMask(buildCfgMask) != expected || inherited.currentAttributes().effectiveSanityMask(buildCfgMask) != expected)
                return Result::Error;
            if (!inherited.currentAttributes().hasSanity(buildCfgMask, Runtime::SafetyWhat::None) || inherited.currentAttributes().hasSanity(buildCfgMask, Runtime::SafetyWhat::All) != (expected == UINT16_MAX))
                return Result::Error;
        }

        inherited.currentAttributes().addSanityOverride(Runtime::SafetyWhat::All, false);
        inherited.currentAttributes().addSanityOverride(static_cast<Runtime::SafetyWhat>(0x8000), true);
        if (inherited.currentAttributes().effectiveSanityMask(Runtime::SafetyWhat::All) != 0x8000)
            return Result::Error;
        // Continuing the parent above must not inherit this nested scope's decisions.
    }

    frame.currentAttributes() = {};
    if (!frame.currentAttributes().empty() || frame.currentAttributes().effectiveSanityMask(Runtime::SafetyWhat::All) != UINT16_MAX)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Sema_RuntimeSafetySummaryPreservesHistoricalInlineDisables)
{
    const std::array<RuntimeSafetyOverride, 10> overrides  = {{{0, true}, {0, false}, {1, false}, {1, true}, {0xAAAA, false}, {0x5555, true}, {0x8000, false}, {UINT16_MAX, true}, {0x5555, false}, {0, false}}};
    const std::array<uint16_t, 5>               buildMasks = {0, UINT16_MAX, 0x5555, 0xAAAA, 0x8000};
    for (size_t callerCount = 0; callerCount <= overrides.size(); ++callerCount)
    {
        SemaFrame               caller;
        std::optional<uint16_t> callerDisables;
        for (size_t index = 0; index < callerCount; ++index)
        {
            const auto& entry = overrides[index];
            caller.currentAttributes().addRuntimeSafetyOverride(static_cast<Runtime::SafetyWhat>(entry.whatMask), entry.value);
            if (!entry.value)
                callerDisables = callerDisables.value_or(0) | entry.whatMask;
        }
        if (caller.currentAttributes().hasRuntimeSafetyOverrides() != (callerCount != 0) || caller.currentAttributes().empty() != (callerCount == 0) || caller.currentAttributes().runtimeSafetyDisables() != callerDisables)
            return Result::Error;

        for (size_t calleeCount = 0; calleeCount <= overrides.size(); ++calleeCount)
        {
            SemaFrame               callee;
            std::optional<uint16_t> combinedDisables = callerDisables;
            for (size_t index = 0; index < calleeCount; ++index)
            {
                const auto& entry = overrides[index];
                callee.currentAttributes().addRuntimeSafetyOverride(static_cast<Runtime::SafetyWhat>(entry.whatMask), entry.value);
                if (!entry.value)
                    combinedDisables = combinedDisables.value_or(0) | entry.whatMask;
            }

            SemaFrame  inlined          = caller;
            const auto disables         = inlined.currentAttributes().runtimeSafetyDisables();
            inlined.currentAttributes() = callee.currentAttributes();
            if (disables)
                inlined.currentAttributes().addRuntimeSafetyOverride(static_cast<Runtime::SafetyWhat>(*disables), false);
            if (inlined.currentAttributes().runtimeSafetyDisables() != combinedDisables || inlined.currentAttributes().empty() != (calleeCount == 0 && !callerDisables))
                return Result::Error;

            for (const uint16_t buildMask : buildMasks)
            {
                uint16_t expectedCaller = buildMask;
                uint16_t expectedCallee = buildMask;
                // Reference the original ordered history, including caller disables
                // whose bits a later caller enable switched back on.
                for (size_t index = 0; index < overrides.size(); ++index)
                {
                    const auto& entry = overrides[index];
                    if (index < callerCount)
                        expectedCaller = entry.value ? expectedCaller | entry.whatMask : expectedCaller & ~entry.whatMask;
                    if (index < calleeCount)
                        expectedCallee = entry.value ? expectedCallee | entry.whatMask : expectedCallee & ~entry.whatMask;
                }
                uint16_t expectedInline = expectedCallee;
                for (size_t index = 0; index < callerCount; ++index)
                    if (!overrides[index].value)
                        expectedInline &= ~overrides[index].whatMask;

                const auto buildCfgMask = static_cast<Runtime::SafetyWhat>(buildMask);
                if (caller.currentAttributes().effectiveRuntimeSafetyMask(buildCfgMask) != expectedCaller || callee.currentAttributes().effectiveRuntimeSafetyMask(buildCfgMask) != expectedCallee || inlined.currentAttributes().effectiveRuntimeSafetyMask(buildCfgMask) != expectedInline)
                    return Result::Error;
                if (!inlined.currentAttributes().hasRuntimeSafety(buildCfgMask, Runtime::SafetyWhat::None) || inlined.currentAttributes().hasRuntimeSafety(buildCfgMask, Runtime::SafetyWhat::All) != (expectedInline == UINT16_MAX))
                    return Result::Error;
            }
        }
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
