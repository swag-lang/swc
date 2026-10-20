#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MachineCodeCache.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/CompilerInstance.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SymbolFunction* makeCacheFunction(TaskContext& ctx, const std::string_view name, const TypeRef parameter = TypeRef::invalid())
    {
        auto* function = Symbol::make<SymbolFunction>(ctx, nullptr, TokenRef::invalid(), ctx.idMgr().addIdentifier(name), SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted);
        function->setReturnTypeRef(ctx.typeMgr().typeVoid());
        if (parameter.isValid())
        {
            auto* variable = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), ctx.idMgr().addIdentifier("value"), SymbolFlagsE::Typed);
            variable->setTypeRef(parameter);
            function->parameters().push_back(variable);
        }
        function->setTypeRef(ctx.typeMgr().addType(TypeInfo::makeFunction(function)));
        return function;
    }

    Utf8 cacheKey(TaskContext& ctx, const SymbolFunction& function, const MicroBuilder& builder)
    {
        std::vector<DebugSourceInfo> sources;
        return MachineCodeCache::inputKey(ctx, sources, function, builder, "unit-test-compiler");
    }
}

SWC_TEST_BEGIN(MachineCodeCache_PreservesFunctionReferenceSharing)
{
    auto*        caller = makeCacheFunction(ctx, "cacheCaller");
    auto*        first  = makeCacheFunction(ctx, "cacheTarget");
    auto*        second = makeCacheFunction(ctx, "cacheTarget");
    auto*        third  = makeCacheFunction(ctx, "cacheTarget");
    auto*        fourth = makeCacheFunction(ctx, "cacheTarget");
    MicroBuilder aliased(ctx), distinct(ctx), relocated(ctx);
    aliased.emitLoadRegPtrReloc(MicroReg::virtualIntReg(0), 0, ConstantRef::invalid(), first);
    aliased.emitLoadRegPtrReloc(MicroReg::virtualIntReg(1), 0, ConstantRef::invalid(), first);
    distinct.emitLoadRegPtrReloc(MicroReg::virtualIntReg(0), 0, ConstantRef::invalid(), first);
    distinct.emitLoadRegPtrReloc(MicroReg::virtualIntReg(1), 0, ConstantRef::invalid(), second);
    relocated.emitLoadRegPtrReloc(MicroReg::virtualIntReg(0), 0, ConstantRef::invalid(), third);
    relocated.emitLoadRegPtrReloc(MicroReg::virtualIntReg(1), 0, ConstantRef::invalid(), fourth);
    const Utf8 sameKey     = cacheKey(ctx, *caller, aliased);
    const Utf8 distinctKey = cacheKey(ctx, *caller, distinct);
    if (sameKey.empty() || distinctKey.empty() || sameKey == distinctKey || distinctKey != cacheKey(ctx, *caller, relocated))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MachineCodeCache_RejectsUntypedEvaluators)
{
    auto* evaluator = makeCacheFunction(ctx, "cacheEvaluator");
    evaluator->setTypeRef(TypeRef::invalid());
    MicroBuilder builder(ctx);
    builder.emitRet();
    if (!cacheKey(ctx, *evaluator, builder).empty())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MachineCodeCache_TracksCalleeEffectsAndNullability)
{
    auto*        caller = makeCacheFunction(ctx, "cacheEffectsCaller");
    auto*        target = makeCacheFunction(ctx, "cacheEffectsTarget");
    MicroBuilder builder(ctx);
    builder.emitCallLocal(target, CallConvKind::Swag);
    const Utf8    before = cacheKey(ctx, *caller, builder);
    AttributeList attributes;
    attributes.addRtFlag(RtAttributeFlagsE::ReadOnly);
    target->setAttributes(ctx, attributes);
    const Utf8 readOnly = cacheKey(ctx, *caller, builder);
    if (before.empty() || readOnly.empty() || before == readOnly)
        return Result::Error;

    const TypeRef pointer          = ctx.typeMgr().addType(TypeInfo::makeValuePointer(ctx.typeMgr().typeS32()));
    const TypeRef nullable         = ctx.typeMgr().addType(TypeInfo::makeValuePointer(ctx.typeMgr().typeS32(), TypeInfoFlagsE::Nullable));
    auto*         nonNullFunction  = makeCacheFunction(ctx, "cachePointerTarget", pointer);
    auto*         nullableFunction = makeCacheFunction(ctx, "cachePointerTarget", nullable);
    MicroBuilder  nonNullInput(ctx), nullableInput(ctx);
    nonNullInput.emitCallLocal(nonNullFunction, CallConvKind::Swag);
    nullableInput.emitCallLocal(nullableFunction, CallConvKind::Swag);
    const Utf8 nonNullKey  = cacheKey(ctx, *caller, nonNullInput);
    const Utf8 nullableKey = cacheKey(ctx, *caller, nullableInput);
    if (nonNullKey.empty() || nullableKey.empty() || nonNullKey == nullableKey)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MachineCodeCache_PreservesGlobalAddressDistances)
{
    auto*        caller = makeCacheFunction(ctx, "cacheGlobalCaller");
    MicroBuilder original(ctx), translated(ctx), changed(ctx);
    original.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, 32);
    original.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, 48);
    translated.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, 96);
    translated.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, 112);
    changed.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, 96);
    changed.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, 120);
    const Utf8 key = cacheKey(ctx, *caller, original);
    if (key.empty() || key != cacheKey(ctx, *caller, translated) || key == cacheKey(ctx, *caller, changed))
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
