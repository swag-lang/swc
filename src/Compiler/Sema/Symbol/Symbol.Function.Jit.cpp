#include "pch.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITPatchJob.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Assert.h"
#if SWC_HAS_STATS
#include "Main/Stats.h"
#include "Support/Core/Timer.h"
#endif

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class DepVisitState : uint8_t
    {
        Visiting,
        Done,
    };

    struct DepStackEntry
    {
        SymbolFunction* function = nullptr;
        bool            expanded = false;
    };

    void appendDepOrder(SmallVector<SymbolFunction*>& outJitOrder, SymbolFunction& root)
    {
        std::unordered_map<SymbolFunction*, DepVisitState> visitStates;
        SmallVector<DepStackEntry>                         stack;
        stack.push_back({.function = &root, .expanded = false});

        while (!stack.empty())
        {
            const auto current = stack.back();
            stack.pop_back();
            SymbolFunction* function = current.function;
            if (!function)
                continue;

            const auto foundState = visitStates.find(function);
            if (current.expanded)
            {
                if (foundState != visitStates.end() && foundState->second == DepVisitState::Done)
                    continue;

                visitStates[function] = DepVisitState::Done;
                outJitOrder.push_back(function);
                continue;
            }

            if (foundState != visitStates.end())
            {
                if (foundState->second == DepVisitState::Done)
                    continue;
                continue;
            }

            if (function->isIgnored())
            {
                visitStates[function] = DepVisitState::Done;
                outJitOrder.push_back(function);
                continue;
            }

            visitStates[function] = DepVisitState::Visiting;
            stack.push_back({.function = function, .expanded = true});

            SmallVector<SymbolFunction*> dependencies;
            function->appendCallDependencies(dependencies);
            for (auto* dependency : std::ranges::reverse_view(dependencies))
            {
                if (!dependency || dependency == function)
                    continue;
                stack.push_back({.function = dependency, .expanded = false});
            }
        }
    }

    SourceCodeRef safeCodeRef(const SymbolFunction& function)
    {
        if (!function.decl())
            return SourceCodeRef::invalid();
        return function.codeRef();
    }

    void setWaitJitCompleted(TaskContext& ctx, const SymbolFunction& function, const Symbol* waiterSymbol)
    {
        TaskState& wait   = ctx.state();
        wait.kind         = TaskStateKind::SemaWaitSymJitCompleted;
        wait.nodeRef      = ctx.state().nodeRef.isValid() ? ctx.state().nodeRef : function.declNodeRef();
        wait.codeRef      = ctx.state().codeRef.isValid() ? ctx.state().codeRef : safeCodeRef(function);
        wait.symbol       = &function;
        wait.waiterSymbol = waiterSymbol != &function ? waiterSymbol : nullptr;
    }

    void setWaitJitPatched(TaskContext& ctx, const SymbolFunction& waiterFunction, const SymbolFunction& targetFunction)
    {
        TaskState& wait = ctx.state();
        wait.kind       = TaskStateKind::SemaWaitSymJitPatched;
        wait.nodeRef    = ctx.state().nodeRef.isValid() ? ctx.state().nodeRef : waiterFunction.declNodeRef();
        if (wait.nodeRef.isInvalid())
            wait.nodeRef = targetFunction.declNodeRef();
        wait.codeRef = ctx.state().codeRef.isValid() ? ctx.state().codeRef : safeCodeRef(waiterFunction);
        if (!wait.codeRef.isValid())
            wait.codeRef = safeCodeRef(targetFunction);
        wait.symbol       = &targetFunction;
        wait.waiterSymbol = &waiterFunction != &targetFunction ? &waiterFunction : nullptr;
    }

    Result waitLocalCallDependenciesPatched(TaskContext& ctx, const SymbolFunction& function)
    {
        SmallVector<SymbolFunction*> dependencies;
        function.appendCallDependencies(dependencies);

        for (SymbolFunction* dependency : dependencies)
        {
            if (!dependency || dependency == &function)
                continue;
            if (dependency->isForeign() || dependency->isEmpty() || dependency->isAttribute())
                continue;
            if (dependency->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning))
                continue;
            if (dependency->jitPatchAddress() || dependency->jitEntryAddress())
                continue;
            if (dependency->isIgnored())
            {
                ctx.state().jitEmissionError = true;
                return Result::Error;
            }

            JITPatchJob::schedule(ctx, *dependency);
            if (dependency->jitPatchAddress() || dependency->jitEntryAddress())
                continue;

            setWaitJitPatched(ctx, function, *dependency);
            return Result::Pause;
        }

        return Result::Continue;
    }

    MicroOpBits adapterArgBits(const ABITypeNormalize::NormalizedType& normalizedType)
    {
        if (normalizedType.isFloat)
        {
            const MicroOpBits bits = microOpBitsFromBitWidth(normalizedType.numBits);
            SWC_ASSERT(bits != MicroOpBits::Zero);
            return bits;
        }

        if (normalizedType.numBits == 8 || normalizedType.numBits == 16 || normalizedType.numBits == 32 || normalizedType.numBits == 64)
            return microOpBitsFromBitWidth(normalizedType.numBits);
        return MicroOpBits::B64;
    }

    void emitLoadIncomingArg(MicroBuilder& builder, const CallConv& callConv, uint32_t slotIndex, MicroReg dstReg, const ABITypeNormalize::NormalizedType& normalizedType)
    {
        const MicroOpBits argBits = adapterArgBits(normalizedType);
        if (slotIndex < callConv.numArgRegisterSlots())
        {
            if (normalizedType.isFloat)
            {
                SWC_ASSERT(slotIndex < callConv.floatArgRegs.size());
                builder.emitLoadRegReg(dstReg, callConv.floatArgRegs[slotIndex], argBits);
            }
            else
            {
                SWC_ASSERT(slotIndex < callConv.intArgRegs.size());
                builder.emitLoadRegReg(dstReg, callConv.intArgRegs[slotIndex], argBits);
            }

            return;
        }

        builder.emitLoadRegMem(dstReg, callConv.framePointer, ABICall::incomingArgFrameOffset(callConv, slotIndex), argBits);
    }

    void addAdapterParameter(TaskContext& ctx, SymbolFunction& adapter, const SymbolVariable& sourceParam)
    {
        auto* param = Symbol::make<SymbolVariable>(ctx, sourceParam.decl(), sourceParam.tokRef(), sourceParam.idRef(), SymbolFlagsE::Zero);
        param->setTypeRef(sourceParam.typeRef());
        param->addExtraFlag(SymbolVariableFlagsE::Parameter);
        param->setDeclared(ctx);
        param->setTyped(ctx);
        param->setSemaCompleted(ctx);
        adapter.addParameter(param);
    }

    Result buildClosureAdapterMicroCode(TaskContext& ctx, SymbolFunction& adapter)
    {
        SWC_ASSERT(adapter.isClosure());

        uint32_t regIndex = 1;

        const CallConv&                        callConv      = CallConv::get(adapter.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, callConv, adapter.returnTypeRef(), ABITypeNormalize::Usage::Return);
        const bool                             hasHiddenRet  = normalizedRet.isIndirect;

        MicroBuilder& builder = adapter.microInstrBuilder(ctx);
        builder.setContext(ctx);

        constexpr ABITypeNormalize::NormalizedType pointerArg = {
            .isVoid  = false,
            .isFloat = false,
            .numBits = 64};

        const uint32_t closureContextSlot = hasHiddenRet ? 1 : 0;

        const MicroReg closureContextReg = MicroReg::virtualIntReg(regIndex++);
        emitLoadIncomingArg(builder, callConv, closureContextSlot, closureContextReg, pointerArg);

        const MicroReg targetReg = MicroReg::virtualIntReg(regIndex++);
        builder.emitLoadRegMem(targetReg, closureContextReg, 0, MicroOpBits::B64);

        MicroReg hiddenRetStorageReg = MicroReg::invalid();
        if (hasHiddenRet)
        {
            hiddenRetStorageReg = MicroReg::virtualIntReg(regIndex++);
            emitLoadIncomingArg(builder, callConv, 0, hiddenRetStorageReg, pointerArg);
        }

        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.reserve(adapter.parameters().size());

        for (const SymbolVariable* param : adapter.parameters())
        {
            SWC_ASSERT(param != nullptr);

            const ABITypeNormalize::NormalizedType normalizedParam =
                ABITypeNormalize::normalize(ctx, callConv, param->typeRef(), ABITypeNormalize::Usage::Argument);

            const uint32_t incomingSlot = param->parameterIndex() + (hasHiddenRet ? 1u : 0u) + 1u;

            ABICall::PreparedArg preparedArg;
            preparedArg.kind        = ABICall::PreparedArgKind::Direct;
            preparedArg.isFloat     = normalizedParam.isFloat;
            preparedArg.numBits     = normalizedParam.numBits;
            preparedArg.isAddressed = false;

            if (normalizedParam.isFloat)
                preparedArg.srcReg = MicroReg::virtualFloatReg(regIndex++);
            else
                preparedArg.srcReg = MicroReg::virtualIntReg(regIndex++);

            emitLoadIncomingArg(builder, callConv, incomingSlot, preparedArg.srcReg, normalizedParam);
            preparedArgs.push_back(preparedArg);
        }

        const ABICall::PreparedCall preparedCall = ABICall::prepareArgs(builder, adapter.callConvKind(), preparedArgs, normalizedRet, hiddenRetStorageReg);
        ABICall::callReg(builder, adapter.callConvKind(), targetReg, preparedCall);
        builder.emitRet();

        adapter.setCodeGenPreSolved(ctx);
        SWC_RESULT(adapter.emit(ctx));
        adapter.setCodeGenCompleted(ctx);
        adapter.tryMarkCodeGenJobScheduled();
        return Result::Continue;
    }
}

MicroBuilder& SymbolFunction::microInstrBuilder(TaskContext& ctx) noexcept
{
    microInstrBuilder_.setContext(ctx);
    return microInstrBuilder_;
}

bool SymbolFunction::tryMarkCodeGenJobScheduled() noexcept
{
    return flags_.tryAdd(SymbolFlagsE::CodeGenJobScheduled);
}

bool SymbolFunction::tryMarkJitPatchJobScheduled() noexcept
{
    bool expected = false;
    return jitPatchJobScheduled_.compare_exchange_strong(expected, true, std::memory_order_acq_rel, std::memory_order_acquire);
}

void SymbolFunction::appendJitOrder(SmallVector<SymbolFunction*>& out) const
{
    appendDepOrder(out, *const_cast<SymbolFunction*>(this));
}

Result SymbolFunction::emit(TaskContext& ctx)
{
    if (ctx.state().jitEmissionError)
        return Result::Error;

    const std::scoped_lock lock(emitMutex_);
    if (hasLoweredCode())
        return Result::Continue;
    auto& builder = microInstrBuilder(ctx);
    if (!returnTypeRef().isValid() || returnTypeRef() == ctx.typeMgr().typeVoid())
    {
        builder.setRetUsesAbiRegs(false, false);
    }
    else
    {
        const CallConv&                        callConv      = CallConv::get(callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, callConv, returnTypeRef(), ABITypeNormalize::Usage::Return);
        builder.setRetUsesAbiRegs(!normalizedRet.isFloat, normalizedRet.isFloat);
    }
    SWC_MEM_SCOPE("Backend/MicroLower");
#if SWC_HAS_STATS
    Timer timeMicroLower(Stats::timedMetric(Stats::get().timeMicroLower));
#endif
    const Result emitResult = loweredMicroCode_.emit(ctx, builder, debugStackBaseReg());
    if (emitResult != Result::Continue)
    {
        ctx.state().jitEmissionError = true;
        return emitResult;
    }

    // Before register allocation the debug base is a virtual register; CodeView can only encode a
    // physical one. Replace it with the physical home the backend resolved, so the debug records
    // for locals name a real frame register instead of being dropped.
    if (loweredMicroCode_.debugStackBasePhysReg.isValid())
        setDebugStackBaseReg(loweredMicroCode_.debugStackBasePhysReg);

    // Lowered machine code keeps the emitted bytes/debug info/relocations.
    // The micro builder itself is transient and otherwise retains per-function IR memory.
    builder.releaseMemory();

#if SWC_HAS_STATS
    if (Stats::enabledRuntime())
        Stats::get().numCodeGenFunctions.fetch_add(1, std::memory_order_relaxed);
#endif
    ctx.compiler().notifyAlive();
    return Result::Continue;
}

bool SymbolFunction::hasLoweredCode() const noexcept
{
    return !loweredMicroCode_.bytes.empty();
}

void SymbolFunction::resetJitState() noexcept
{
    const std::scoped_lock lock(emitMutex_);
    jitExecMemory_.reset();
    jitPatchedAddress_.store(nullptr, std::memory_order_release);
    jitEntryAddress_.store(nullptr, std::memory_order_release);
    jitPatchJobScheduled_.store(false, std::memory_order_release);
    jitReadyVersion_.store(0, std::memory_order_release);
}

Result SymbolFunction::ensureClosureAdapter(TaskContext& ctx, SymbolFunction*& outAdapter)
{
    outAdapter = nullptr;
    SWC_ASSERT(isClosure());

    if (SymbolFunction* const publishedAdapter = closureAdapterPublished_.load(std::memory_order_acquire))
    {
        outAdapter = publishedAdapter;
        return Result::Continue;
    }

    const std::scoped_lock lock(closureAdapterMutex_);
    if (SymbolFunction* const publishedAdapter = closureAdapterPublished_.load(std::memory_order_acquire))
    {
        outAdapter = publishedAdapter;
        return Result::Continue;
    }

    const IdentifierRef adapterId = ctx.idMgr().addIdentifierOwned(std::format("__closure_adapter_{}", ctx.compiler().atomicId().fetch_add(1)));
    auto* const         adapter   = make<SymbolFunction>(ctx, decl(), tokRef(), adapterId, SymbolFlagsE::Zero);
    adapter->setOwnerSymMap(ownerSymMap());
    adapter->setReturnTypeRef(returnTypeRef());
    adapter->setCallConvKind(callConvKind());
    if (isClosure())
        adapter->addExtraFlag(SymbolFunctionFlagsE::Closure);
    if (isMethod())
        adapter->addExtraFlag(SymbolFunctionFlagsE::Method);
    if (isThrowable())
        adapter->addExtraFlag(SymbolFunctionFlagsE::Throwable);
    if (isConst())
        adapter->addExtraFlag(SymbolFunctionFlagsE::Const);
    if (hasVariadicParam())
        adapter->addExtraFlag(SymbolFunctionFlagsE::Variadic);
    adapter->setAttributes(ctx, attributes());
    adapter->setRtAttributeFlags(rtAttributeFlags());

    for (const SymbolVariable* param : parameters_)
    {
        SWC_ASSERT(param != nullptr);
        addAdapterParameter(ctx, *adapter, *param);
    }

    adapter->setTypeRef(ctx.typeMgr().addType(TypeInfo::makeFunction(adapter, TypeInfoFlagsE::Zero)));
    adapter->setDeclared(ctx);
    adapter->setTyped(ctx);
    adapter->setSemaCompleted(ctx);

    SWC_RESULT(buildClosureAdapterMicroCode(ctx, *adapter));

    closureAdapterPublished_.store(adapter, std::memory_order_release);
    outAdapter = adapter;
    return Result::Continue;
}

Result SymbolFunction::jit(TaskContext& ctx)
{
    if (ctx.state().jitEmissionError)
        return Result::Error;

    if (hasJitEntryAddress())
        return Result::Continue;

    SmallVector<SymbolFunction*> jitOrder;
    appendDepOrder(jitOrder, *this);
    return jitBatch(ctx, jitOrder);
}

Result SymbolFunction::jitBatch(TaskContext& ctx, const std::span<SymbolFunction* const> functions, const Symbol* waiterSymbol)
{
    if (ctx.state().jitEmissionError)
        return Result::Error;

    const SymbolFunction* pendingFunction       = nullptr;
    const auto*           weakRelocationBlocker = waiterSymbol ? waiterSymbol->safeCast<SymbolFunction>() : nullptr;
    for (SymbolFunction* function : functions)
    {
        if (ctx.state().jitEmissionError)
            return Result::Error;
        if (!function)
            continue;
        if (function->isIgnored())
        {
            ctx.state().jitEmissionError = true;
            return Result::Error;
        }

        if (function->hasJitEntryAddress())
            continue;

        JITPatchJob::schedule(ctx, *function, weakRelocationBlocker);
        if (!pendingFunction)
            pendingFunction = function;
    }

    if (pendingFunction)
    {
        setWaitJitCompleted(ctx, *pendingFunction, waiterSymbol);
        return Result::Pause;
    }

    return Result::Continue;
}

Result SymbolFunction::jitMaterialize(TaskContext& ctx)
{
    if (ctx.state().jitEmissionError)
        return Result::Error;

    if (isIgnored())
    {
        ctx.state().jitEmissionError = true;
        return Result::Error;
    }

    if (hasJitEntryAddress())
        return Result::Continue;

    if (!jitPrepare(ctx) && !hasJitPreparedAddress())
        return ctx.state().jitEmissionError ? Result::Error : Result::Continue;

    SWC_RESULT(jitPatch(ctx));
    SWC_RESULT(waitLocalCallDependenciesPatched(ctx, *this));

    jitFinalize(ctx);
    if (hasJitEntryAddress())
        return Result::Continue;

    ctx.state().jitEmissionError = true;
    return Result::Error;
}

bool SymbolFunction::jitPrepare(TaskContext& ctx)
{
    const std::scoped_lock lock(emitMutex_);
    if (ctx.state().jitEmissionError)
        return false;

    if (hasJitEntryAddress())
        return false;
    if (hasJitPreparedAddress())
        return true;

    if (!hasLoweredCode())
    {
        ctx.state().jitEmissionError = true;
        return false;
    }

    JIT::prepare(ctx, jitExecMemory_, loweredMicroCode_.bytes, loweredMicroCode_.unwindInfo);
    const void* entry = jitExecMemory_.entryPoint();
    if (!entry)
    {
        ctx.state().jitEmissionError = true;
        return false;
    }

    ctx.compiler().registerPreparedJitFunction(this);
    ctx.compiler().notifyAlive();
    return true;
}

Result SymbolFunction::jitPatch(TaskContext& ctx)
{
    const std::scoped_lock lock(emitMutex_);
    if (ctx.state().jitEmissionError)
        return Result::Error;

    if (hasJitEntryAddress())
        return Result::Continue;
    if (!hasJitPreparedAddress())
        return Result::Continue;
    if (hasJitPatchedAddress())
        return Result::Continue;

    auto relocations = loweredMicroCode_.codeRelocations;
    for (MicroRelocation& relocation : relocations)
    {
        if (relocation.kind != MicroRelocation::Kind::LocalFunctionAddress)
            continue;
        if (relocation.targetSymbol != this)
            continue;
        if (relocation.targetAddress != 0)
            continue;

        relocation.targetAddress = MicroRelocation::K_SELF_ADDRESS;
    }

    const Result patchResult = JIT::patch(ctx, jitExecMemory_, relocations, this);
    if (patchResult == Result::Continue)
    {
        jitPatchedAddress_.store(jitExecMemory_.entryPoint(), std::memory_order_release);
        ctx.compiler().notifyAlive();
    }
    if (patchResult == Result::Error)
        ctx.state().jitEmissionError = true;
    return patchResult;
}

void SymbolFunction::jitFinalize(TaskContext& ctx)
{
    const std::scoped_lock lock(emitMutex_);
    if (ctx.state().jitEmissionError)
        return;

    if (hasJitEntryAddress())
        return;
    if (!hasJitPreparedAddress())
        return;

    JIT::finalize(jitExecMemory_);
    void* entry = jitPatchAddress();
    SWC_ASSERT(entry != nullptr);
    jitEntryAddress_.store(entry, std::memory_order_release);
    ctx.compiler().notifyAlive();
}

SWC_END_NAMESPACE();
