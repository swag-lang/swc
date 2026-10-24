#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MachineCodeCache.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SymbolFunction* makeCacheFunction(TaskContext& ctx, const std::string_view name, const TypeRef parameter = TypeRef::invalid(), const AstNode* declaration = nullptr)
    {
        auto* function = Symbol::make<SymbolFunction>(ctx, declaration, TokenRef::invalid(), ctx.idMgr().addIdentifier(name), SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted);
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

SWC_FILESYSTEM_TEST_BEGIN(MachineCodeCache_ReusesModuleSourceWithRelocations)
{
    CommandLine command;
    command.command  = CommandKind::Build;
    command.numCores = 6;
    CommandLineParser::refreshBuildCfg(command);
    CompilerInstance compiler(ctx.global(), command);
    TaskContext      localCtx(compiler);
    SWC_RESULT(compiler.setupSema(localCtx));
    SourceFile& source            = Unittest::addTestSource(localCtx, "Micro", "MachineCacheModule", "", FileFlagsE::ModuleSrc);
    const auto [ref, declaration] = source.ast().makeNode<AstNodeId::FunctionDecl>(TokenRef::invalid());
    auto*               caller    = makeCacheFunction(localCtx, "cacheModuleCaller", TypeRef::invalid(), declaration);
    auto*               target    = makeCacheFunction(localCtx, "cacheModuleTarget");
    MicroBuilder        builder(localCtx);
    const SourceCodeRef originalSource{source.ast().srcView().ref(), TokenRef{10}};
    builder.setCurrentDebugSourceCodeRef(originalSource);
    builder.emitLoadRegPtrReloc(MicroReg::virtualIntReg(0), 0, ConstantRef::invalid(), target);

    MachineCode expected;
    expected.bytes.resize(8, std::byte{0});
    expected.codeAlignment                 = 16;
    expected.codeRelocations               = builder.codeRelocations();
    expected.codeRelocations[0].codeOffset = 0;
    expected.debugSourceRanges.push_back({.codeStartOffset = 0, .codeEndOffset = 8, .debugSourceInfo = {.sourceCodeRef = originalSource}});
    MachineCodeCache cache(localCtx, *caller, builder);
    cache.write(expected);
    MachineCode restored;
    if (!cache.read(restored) || restored.bytes.size() != 8 || restored.codeRelocations.size() != 1 || restored.codeRelocations[0].targetSymbol != target)
        return Result::Error;

    auto*               relocatedTarget = makeCacheFunction(localCtx, "cacheModuleTarget");
    MicroBuilder        relocated(localCtx);
    const SourceCodeRef relocatedSource{source.ast().srcView().ref(), TokenRef{20}};
    relocated.setCurrentDebugSourceCodeRef(relocatedSource);
    relocated.emitLoadRegPtrReloc(MicroReg::virtualIntReg(0), 0, ConstantRef::invalid(), relocatedTarget);
    MachineCodeCache rebound(localCtx, *caller, relocated);
    if (!rebound.read(restored) || restored.codeRelocations[0].targetSymbol != relocatedTarget || restored.debugSourceRanges.size() != 1 || restored.debugSourceRanges[0].debugSourceInfo.sourceCodeRef != relocatedSource)
        return Result::Error;

    auto*        changedTarget = makeCacheFunction(localCtx, "cacheChangedModuleTarget");
    MicroBuilder changed(localCtx);
    changed.setCurrentDebugSourceCodeRef(relocatedSource);
    changed.emitLoadRegPtrReloc(MicroReg::virtualIntReg(0), 0, ConstantRef::invalid(), changedTarget);
    MachineCodeCache invalidated(localCtx, *caller, changed);
    if (invalidated.read(restored))
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(MachineCodeCache_RebindsSourceLocationsWithoutChangingCodeIdentity)
{
    SourceFile&  first  = Unittest::addTestSource(ctx, "Micro", "CacheSourceOriginal", "");
    SourceFile&  moved  = Unittest::addTestSource(ctx, "Micro", "CacheSourceMoved", "");
    auto*        caller = makeCacheFunction(ctx, "cacheSourceCaller");
    MicroBuilder original(ctx), translated(ctx), split(ctx);
    original.setCurrentDebugSourceCodeRef({first.ast().srcView().ref(), TokenRef{10}});
    original.emitNop();
    original.emitRet();
    translated.setCurrentDebugSourceCodeRef({moved.ast().srcView().ref(), TokenRef{20}});
    translated.emitNop();
    translated.emitRet();
    split.setCurrentDebugSourceCodeRef({moved.ast().srcView().ref(), TokenRef{20}});
    split.emitNop();
    split.setCurrentDebugSourceCodeRef({moved.ast().srcView().ref(), TokenRef{21}});
    split.emitRet();

    const Utf8 key = cacheKey(ctx, *caller, original);
    if (key.empty() || key != cacheKey(ctx, *caller, translated) || key == cacheKey(ctx, *caller, split))
        return Result::Error;
}
SWC_TEST_END()

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

// A caller's code depends on what its callees were proved to clobber.
SWC_TEST_BEGIN(MachineCodeCache_TracksCallClobbers)
{
    auto*        caller = makeCacheFunction(ctx, "cacheClobbersCaller");
    auto*        target = makeCacheFunction(ctx, "cacheClobbersTarget");
    MicroBuilder builder(ctx);
    builder.emitCallLocal(target, CallConvKind::Swag);
    const Utf8        whole = cacheKey(ctx, *caller, builder);
    const MicroInstr& call  = *builder.instructions().ptr(builder.instructions().lastInstructionRef());
    call.setCallClobbers(builder.operands(), 1);
    const Utf8 narrowed = cacheKey(ctx, *caller, builder);
    if (whole.empty() || narrowed.empty() || whole == narrowed)
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

SWC_TEST_BEGIN(MachineCodeCache_TracksCalleeReleaseSummaries)
{
    auto*        caller = makeCacheFunction(ctx, "cacheReleaseCaller");
    auto*        target = makeCacheFunction(ctx, "cacheReleaseTarget", ctx.typeMgr().typeS32());
    MicroBuilder builder(ctx);
    builder.emitCallLocal(target, CallConvKind::Swag);
    const Utf8 before = cacheKey(ctx, *caller, builder);
    target->addFreesParam(0);
    const Utf8 direct = cacheKey(ctx, *caller, builder);
    target->addFreesParam(0, true);
    const Utf8 indirect = cacheKey(ctx, *caller, builder);
    if (before.empty() || direct.empty() || indirect.empty() || before == direct || direct == indirect)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
