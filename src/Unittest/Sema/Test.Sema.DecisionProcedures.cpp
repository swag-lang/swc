#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Module.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Support/Report/Diagnostic.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

SWC_END_NAMESPACE();

#endif
