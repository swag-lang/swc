#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Generic/GenericInstanceStorage.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaEscape.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"
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
            const SymbolFlags flags = completed ? SymbolFlagsE::SemaCompleted : SymbolFlagsE::Zero;
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
    GenericInstanceStorage         storage;
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
    TypeManager                                      manager;
    constexpr size_t                                 count = 256;
    std::array<std::array<TypeRef, count>, 3>          refs;
    std::array<std::unordered_set<uint32_t>, 3>       hashes;
    const std::array                                 fixedTypes = {TypeRef{1}, TypeRef{2}, TypeRef{3}, TypeRef{4}};
    const std::array                                 fixedNames = {IdentifierRef::invalid(), IdentifierRef{2}, IdentifierRef{3}, IdentifierRef{4}};

    // Keep long common prefixes and vary types independently from names. The second
    // pass checks that table growth and temporary input lifetimes preserve interning.
    for (size_t pass = 0; pass < 2; ++pass)
    {
        for (uint32_t index = 0; index < count; ++index)
        {
            auto types   = fixedTypes;
            auto names   = fixedNames;
            types.back() = TypeRef{index + 4};
            names.back() = IdentifierRef{index + 4};
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

    TypeInfo copy(manager.get(refs[1][count - 1]));
    const TypeInfo moved(std::move(copy));
    if (manager.addType(moved) != refs[1][count - 1])
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
    auto* outer   = fixture.addFunction();
    auto* middle  = fixture.addFunction();
    auto* leaf    = fixture.addFunction();
    auto* owned   = fixture.addFunction();
    auto* carried = fixture.addFunction();
    auto* pending = fixture.addFunction(false);
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
    auto* outer           = fixture.addFunction();
    auto* middle          = fixture.addFunction();
    auto* leaf            = fixture.addFunction();
    auto* aliasWrapper    = fixture.addFunction();
    auto* aliasLeaf       = fixture.addFunction();
    auto* payloadAlias    = fixture.addFunction();
    auto* borrowOnly      = fixture.addFunction();
    auto* incompleteAlias = fixture.addFunction();
    auto* unresolved      = fixture.addFunction(false);
    auto* payloadOwner    = fixture.addFunction();
    auto* nonAliasOwner   = fixture.addFunction();
    auto* unresolvedOwner = fixture.addFunction();
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

SWC_END_NAMESPACE();

#endif
