#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Backend/Micro/MachineCode.h"
#include "Backend/Micro/MachineCodeCache.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
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

    uint32_t reserveGlobal(TaskContext& ctx, const uint32_t size)
    {
        return ctx.compiler().globalZeroSegment().reserveBytes(size, 8, true).first;
    }

    // A load of the constant bytes stored at `offset` in constant shard `shard`.
    void emitConstantLoad(TaskContext& ctx, MicroBuilder& builder, const uint32_t reg, const uint32_t shard, const uint32_t offset)
    {
        const std::byte* bytes = ctx.cstMgr().shardDataSegment(shard).ptr<std::byte>(offset);
        builder.emitLoadRegPtrReloc(MicroReg::virtualIntReg(reg), reinterpret_cast<uint64_t>(bytes), ctx.cstMgr().addS32(ctx, 1));
        MicroRelocation& relocation = builder.codeRelocations().back();
        relocation.targetAddress    = reinterpret_cast<uint64_t>(bytes);
        relocation.constantShard    = shard;
        relocation.constantOffset   = offset;
    }

    struct ModuleCacheFixture
    {
        CommandLine                       command;
        std::unique_ptr<CompilerInstance> compiler;
        std::unique_ptr<TaskContext>      context;
        SourceFile*                       source   = nullptr;
        SymbolFunction*                   function = nullptr;

        ModuleCacheFixture(const Global& global, const std::string_view name)
        {
            command.command  = CommandKind::Build;
            command.numCores = 6;
            CommandLineParser::refreshBuildCfg(command);
            compiler = std::make_unique<CompilerInstance>(global, command);
            context  = std::make_unique<TaskContext>(*compiler);
            SWC_ASSERT(compiler->setupSema(*context) == Result::Continue);
            source                        = &Unittest::addTestSource(*context, "Micro", name, "", FileFlagsE::ModuleSrc);
            const auto [ref, declaration] = source->ast().makeNode<AstNodeId::FunctionDecl>(TokenRef::invalid());
            function                      = makeCacheFunction(*context, name, TypeRef::invalid(), declaration);
        }
    };
}

SWC_FILESYSTEM_TEST_BEGIN(MachineCodeCache_ReusesModuleSourceWithRelocations)
{
    ModuleCacheFixture  fixture(ctx.global(), "cacheModuleCaller");
    TaskContext&        localCtx = *fixture.context;
    SourceFile&         source   = *fixture.source;
    auto*               caller   = fixture.function;
    auto*               target   = makeCacheFunction(localCtx, "cacheModuleTarget");
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

SWC_FILESYSTEM_TEST_BEGIN(MachineCodeCache_RecreatesOptimizerConstantsInTheConsumer)
{
    ModuleCacheFixture producer(ctx.global(), "cacheGeneratedConstantCaller");
    TaskContext&       producerCtx = *producer.context;
    MicroBuilder       input(producerCtx);
    input.emitRet();

    const std::array<char, 16> payload = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
    DataSegmentRef             source;
    const auto                 stored = producerCtx.cstMgr().addPayloadBuffer({payload.data(), payload.size()}, &source, 16);
    MachineCode                expected;
    expected.bytes.resize(8, std::byte{0});
    expected.codeAlignment = 16;
    MicroRelocation relocation;
    relocation.kind              = MicroRelocation::Kind::ConstantAddress;
    relocation.form              = MicroRelocation::Form::Relative32;
    relocation.targetAddress     = reinterpret_cast<uint64_t>(stored.data());
    relocation.constantShard     = source.shardIndex;
    relocation.constantOffset    = source.offset;
    relocation.relativeEndOffset = 4;
    relocation.constantCopySize  = 16;
    expected.codeRelocations.push_back(relocation);
    relocation.codeOffset        = 4;
    relocation.relativeEndOffset = 8;
    relocation.targetAddress += 4;
    relocation.constantOffset += 4;
    relocation.constantCopySize = 8;
    expected.codeRelocations.push_back(relocation);
    MachineCodeCache writeCache(producerCtx, *producer.function, input);
    writeCache.write(expected);

    ModuleCacheFixture consumer(ctx.global(), "cacheGeneratedConstantCaller");
    TaskContext&       consumerCtx = *consumer.context;
    MicroBuilder       currentInput(consumerCtx);
    currentInput.emitRet();
    MachineCodeCache readCache(consumerCtx, *consumer.function, currentInput);
    MachineCode      restored;
    if (!readCache.read(restored) || restored.codeRelocations.size() != 2)
        return Result::Error;
    const auto& first  = restored.codeRelocations[0];
    const auto& second = restored.codeRelocations[1];
    if (first.targetAddress == reinterpret_cast<uint64_t>(stored.data()) || first.constantShard != second.constantShard || second.constantOffset - first.constantOffset != 4 || second.targetAddress - first.targetAddress != 4)
        return Result::Error;
    if (std::memcmp(reinterpret_cast<const void*>(first.targetAddress), payload.data(), payload.size()) != 0 || first.targetAddress % 16)
        return Result::Error;
    DataSegmentAllocation allocation;
    if (!consumerCtx.cstMgr().shardDataSegment(first.constantShard).findAllocation(allocation, first.constantOffset) || allocation.size != payload.size())
        return Result::Error;
}
SWC_TEST_END()

SWC_FILESYSTEM_TEST_BEGIN(MachineCodeCache_RejectsGeneratedConstantsWithPointerEdges)
{
    ModuleCacheFixture fixture(ctx.global(), "cacheGeneratedPointerCaller");
    TaskContext&       localCtx = *fixture.context;
    MicroBuilder       input(localCtx);
    input.emitRet();
    const std::array<char, 8> payload{};
    DataSegmentRef            source;
    const auto                stored = localCtx.cstMgr().addPayloadBuffer({payload.data(), payload.size()}, &source, 8);
    auto*                     target = makeCacheFunction(localCtx, "cacheGeneratedPointerTarget");
    localCtx.cstMgr().shardDataSegment(source.shardIndex).addFunctionRelocation(source.offset, target);

    MachineCode code;
    code.bytes.resize(4, std::byte{0});
    MicroRelocation relocation;
    relocation.kind              = MicroRelocation::Kind::ConstantAddress;
    relocation.form              = MicroRelocation::Form::Relative32;
    relocation.targetAddress     = reinterpret_cast<uint64_t>(stored.data());
    relocation.constantShard     = source.shardIndex;
    relocation.constantOffset    = source.offset;
    relocation.relativeEndOffset = 4;
    code.codeRelocations.push_back(relocation);
    MachineCodeCache cache(localCtx, *fixture.function, input);
    cache.write(code);
    MachineCode restored;
    if (cache.read(restored))
        return Result::Error;
}
SWC_TEST_END()

// Reused code reaches each global through the current input's own allocation, at the
// offset it used inside it. A global the input never named cannot be rebound.
SWC_FILESYSTEM_TEST_BEGIN(MachineCodeCache_RebindsGlobalsToTheirOwnAllocation)
{
    ModuleCacheFixture fixture(ctx.global(), "cacheGlobalRebindCaller");
    TaskContext&       localCtx = *fixture.context;
    const uint32_t     first    = reserveGlobal(localCtx, 16);
    const uint32_t     second   = reserveGlobal(localCtx, 16);
    const uint32_t     stranger = reserveGlobal(localCtx, 16);
    MicroBuilder       input(localCtx);
    input.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, first);
    input.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, second);

    MachineCode expected;
    expected.bytes.resize(8, std::byte{0});
    expected.codeAlignment = 16;
    MicroRelocation relocation;
    relocation.kind              = MicroRelocation::Kind::GlobalZeroAddress;
    relocation.form              = MicroRelocation::Form::Relative32;
    relocation.targetAddress     = first + 8;
    relocation.relativeEndOffset = 4;
    expected.codeRelocations.push_back(relocation);
    relocation.targetAddress     = second;
    relocation.codeOffset        = 4;
    relocation.relativeEndOffset = 8;
    expected.codeRelocations.push_back(relocation);
    MachineCodeCache(localCtx, *fixture.function, input).write(expected);

    const uint32_t movedSecond = reserveGlobal(localCtx, 16);
    const uint32_t movedFirst  = reserveGlobal(localCtx, 16);
    MicroBuilder   moved(localCtx);
    moved.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, movedFirst);
    moved.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, movedSecond);
    MachineCode restored;
    if (!MachineCodeCache(localCtx, *fixture.function, moved).read(restored) || restored.codeRelocations.size() != 2)
        return Result::Error;
    if (restored.codeRelocations[0].targetAddress != movedFirst + 8 || restored.codeRelocations[1].targetAddress != movedSecond)
        return Result::Error;

    MicroBuilder escaping(localCtx);
    escaping.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, first);
    escaping.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, first + 8);
    expected.codeRelocations[1].targetAddress = stranger;
    MachineCodeCache(localCtx, *fixture.function, escaping).write(expected);
    if (MachineCodeCache(localCtx, *fixture.function, escaping).read(restored))
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

// Workers allocate globals in the order they reach them, so the key names a global
// by its allocation and the offset inside it, never by where the allocation sits.
SWC_TEST_BEGIN(MachineCodeCache_IdentifiesGlobalsByAllocation)
{
    auto*          caller = makeCacheFunction(ctx, "cacheGlobalCaller");
    const uint32_t first  = reserveGlobal(ctx, 16);
    const uint32_t second = reserveGlobal(ctx, 16);
    const uint32_t third  = reserveGlobal(ctx, 16);
    const uint32_t fourth = reserveGlobal(ctx, 16);
    const uint32_t wide   = reserveGlobal(ctx, 32);
    MicroBuilder   original(ctx), placed(ctx), interior(ctx), shared(ctx), resized(ctx);
    original.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, first);
    original.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, second);
    placed.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, fourth);
    placed.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, third);
    interior.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, first);
    interior.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, second + 8);
    shared.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, first);
    shared.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, first);
    resized.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(0), DataSegmentKind::GlobalZero, first);
    resized.emitLoadRegDataSegmentReloc(MicroReg::virtualIntReg(1), DataSegmentKind::GlobalZero, wide);
    const Utf8 key = cacheKey(ctx, *caller, original);
    if (key.empty() || key != cacheKey(ctx, *caller, placed))
        return Result::Error;
    if (key == cacheKey(ctx, *caller, interior) || key == cacheKey(ctx, *caller, shared) || key == cacheKey(ctx, *caller, resized))
        return Result::Error;
}
SWC_TEST_END()

// Constant shards intern their own copy of a string: which copy a load names is not
// part of the input, but the bytes are.
SWC_TEST_BEGIN(MachineCodeCache_IdentifiesPointerFreeConstantsByContent)
{
    auto*          caller = makeCacheFunction(ctx, "cacheLeafCaller");
    const uint32_t copyA  = ctx.cstMgr().shardDataSegment(0).addString("cache leaf").second;
    const uint32_t copyB  = ctx.cstMgr().shardDataSegment(1).addString("cache leaf").second;
    const uint32_t other  = ctx.cstMgr().shardDataSegment(1).addString("cache leaves").second;
    MicroBuilder   sameCopy(ctx), twoCopies(ctx), changed(ctx);
    emitConstantLoad(ctx, sameCopy, 0, 0, copyA);
    emitConstantLoad(ctx, sameCopy, 1, 0, copyA);
    emitConstantLoad(ctx, twoCopies, 0, 0, copyA);
    emitConstantLoad(ctx, twoCopies, 1, 1, copyB);
    emitConstantLoad(ctx, changed, 0, 0, copyA);
    emitConstantLoad(ctx, changed, 1, 1, other);
    const Utf8 key = cacheKey(ctx, *caller, sameCopy);
    if (key.empty() || key != cacheKey(ctx, *caller, twoCopies) || key == cacheKey(ctx, *caller, changed))
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
