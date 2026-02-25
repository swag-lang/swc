#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Backend/JIT/JIT.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"
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
            SymbolFunction* const function = current.function;
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

            visitStates[function] = DepVisitState::Visiting;
            stack.push_back({.function = function, .expanded = true});

            SmallVector<SymbolFunction*> dependencies;
            function->appendCallDependencies(dependencies);
            for (const auto dependency : std::ranges::reverse_view(dependencies))
            {
                if (!dependency || dependency == function)
                    continue;
                stack.push_back({.function = dependency, .expanded = false});
            }
        }
    }

    bool isLocalLayoutReady(TaskContext& ctx, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return false;

        const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
        if (typeInfo.isIntUnsized() || typeInfo.isFloatUnsized() || typeInfo.isVoid() || typeInfo.isUndefined() || typeInfo.isAnyVariadic())
            return false;

        if (typeInfo.isArray())
        {
            if (typeInfo.payloadArrayDims().empty())
                return false;
            return isLocalLayoutReady(ctx, typeInfo.payloadArrayElemTypeRef());
        }

        if (typeInfo.isAggregate())
        {
            const auto& aggregateTypes = typeInfo.payloadAggregate().types;
            if (aggregateTypes.empty())
                return false;
            for (const TypeRef elemTypeRef : aggregateTypes)
            {
                if (!isLocalLayoutReady(ctx, elemTypeRef))
                    return false;
            }
        }

        if (typeInfo.isAlias())
            return isLocalLayoutReady(ctx, typeInfo.payloadSymAlias().underlyingTypeRef());

        if (typeInfo.isEnum())
            return isLocalLayoutReady(ctx, typeInfo.payloadSymEnum().underlyingTypeRef());

        if (typeInfo.isTypeValue())
            return isLocalLayoutReady(ctx, typeInfo.payloadTypeRef());

        return true;
    }
}

Utf8 SymbolFunction::computeName(const TaskContext& ctx) const
{
    Utf8 out;
    out += hasExtraFlag(SymbolFunctionFlagsE::Method) ? "mtd" : "func";
    out += hasExtraFlag(SymbolFunctionFlagsE::Closure) ? "||" : "";
    out += "(";
    for (size_t i = 0; i < parameters_.size(); ++i)
    {
        if (i != 0)
            out += ", ";

        if (parameters_[i]->idRef().isValid())
        {
            out += parameters_[i]->name(ctx);
            out += ": ";
        }

        const TypeInfo& paramType = ctx.typeMgr().get(parameters_[i]->typeRef());
        out += paramType.toName(ctx);
    }
    out += ")";

    if (returnType_ != ctx.typeMgr().typeVoid())
    {
        out += "->";
        const TypeInfo& returnType = ctx.typeMgr().get(returnType_);
        out += returnType.toName(ctx);
    }

    out += hasExtraFlag(SymbolFunctionFlagsE::Throwable) ? " throw" : "";
    return out;
}

Utf8 SymbolFunction::resolveForeignFunctionName(const TaskContext& ctx) const
{
    if (!isForeign())
        return {};

    if (!foreignFunctionName().empty())
        return Utf8{foreignFunctionName()};

    return Utf8{name(ctx)};
}

void SymbolFunction::setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags)
{
    if (parserFlags.has(AstFunctionFlagsE::Method))
        addExtraFlag(SymbolFunctionFlagsE::Method);
    if (parserFlags.has(AstFunctionFlagsE::Throwable))
        addExtraFlag(SymbolFunctionFlagsE::Throwable);
    if (parserFlags.has(AstFunctionFlagsE::Closure))
        addExtraFlag(SymbolFunctionFlagsE::Closure);
    if (parserFlags.has(AstFunctionFlagsE::Const))
        addExtraFlag(SymbolFunctionFlagsE::Const);
}

void SymbolFunction::addParameter(SymbolVariable* sym)
{
    SWC_ASSERT(sym != nullptr);
    sym->setParameterIndex(static_cast<uint32_t>(parameters_.size()));
    parameters_.push_back(sym);
}

void SymbolFunction::addLocalVariable(TaskContext& ctx, SymbolVariable* sym)
{
    SWC_ASSERT(sym != nullptr);
    if (std::ranges::find(localVariables_, sym) != localVariables_.end())
        return;

    localVariables_.push_back(sym);
    while (numComputedLocals_ < localVariables_.size())
    {
        SymbolVariable* const local = localVariables_[numComputedLocals_];
        SWC_ASSERT(local != nullptr);

        const TypeRef typeRef = local->typeRef();
        if (!isLocalLayoutReady(ctx, typeRef))
            return;

        const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
        const uint64_t  size      = typeInfo.sizeOf(ctx);
        const uint32_t  alignment = typeInfo.alignOf(ctx);
        SWC_ASSERT(size > 0);
        SWC_ASSERT(alignment > 0);

        localStackOffset_ = Math::alignUpU64(localStackOffset_, alignment);
        SWC_ASSERT(localStackOffset_ <= std::numeric_limits<uint32_t>::max());
        local->setOffset(static_cast<uint32_t>(localStackOffset_));
        localStackOffset_ += size;
        numComputedLocals_++;
    }
}

MicroBuilder& SymbolFunction::microInstrBuilder(TaskContext& ctx) noexcept
{
    microInstrBuilder_.setContext(ctx);
    return microInstrBuilder_;
}

bool SymbolFunction::tryMarkCodeGenJobScheduled() noexcept
{
    bool expected = false;
    return codeGenJobScheduled_.compare_exchange_strong(expected, true, std::memory_order_acq_rel);
}

void SymbolFunction::addCallDependency(SymbolFunction* sym)
{
    if (!sym || sym == this)
        return;

    std::scoped_lock lock(callDepsMutex_);
    if (std::ranges::find(callDependencies_, sym) != callDependencies_.end())
        return;
    callDependencies_.push_back(sym);
}

void SymbolFunction::appendCallDependencies(SmallVector<SymbolFunction*>& out) const
{
    std::scoped_lock lock(callDepsMutex_);
    out.reserve(out.size() + callDependencies_.size());
    for (SymbolFunction* dep : callDependencies_)
        out.push_back(dep);
}

Result SymbolFunction::emit(TaskContext& ctx)
{
    if (ctx.state().jitEmissionError)
        return Result::Error;

    std::scoped_lock lock(emitMutex_);
    if (hasLoweredCode())
        return Result::Continue;
    auto& builder = microInstrBuilder(ctx);
#if SWC_HAS_STATS
    Timer timeMicroLower(&Stats::get().timeMicroLower);
#endif
    const Result emitResult = loweredMicroCode_.emit(ctx, builder);
    if (emitResult != Result::Continue)
    {
        ctx.state().jitEmissionError = true;
        return emitResult;
    }
#if SWC_HAS_STATS
    Stats::get().numCodeGenFunctions.fetch_add(1, std::memory_order_relaxed);
#endif
    ctx.compiler().notifyAlive();
    return Result::Continue;
}

bool SymbolFunction::hasLoweredCode() const noexcept
{
    return !loweredMicroCode_.bytes.empty();
}

void SymbolFunction::jit(TaskContext& ctx)
{
    if (ctx.state().jitEmissionError)
        return;

    if (hasJitEntryAddress())
        return;

    SmallVector<SymbolFunction*> jitOrder;
    appendDepOrder(jitOrder, *this);
    for (SymbolFunction* function : jitOrder)
    {
        if (ctx.state().jitEmissionError)
            return;
        function->jitEmit(ctx);
    }
}

void SymbolFunction::jitEmit(TaskContext& ctx)
{
    std::scoped_lock lock(emitMutex_);
    if (ctx.state().jitEmissionError)
        return;

    if (hasJitEntryAddress())
        return;

    if (!hasLoweredCode())
    {
        ctx.state().jitEmissionError = true;
        return;
    }

    JIT::emit(ctx, jitExecMemory_, asByteSpan(loweredMicroCode_.bytes), loweredMicroCode_.codeRelocations);
    void* const entry = jitExecMemory_.entryPoint();
    if (!entry)
    {
        ctx.state().jitEmissionError = true;
        return;
    }

    jitEntryAddress_.store(entry, std::memory_order_release);

    ctx.compiler().notifyAlive();
}

bool SymbolFunction::deepCompare(const SymbolFunction& otherFunc) const noexcept
{
    if (this == &otherFunc)
        return true;

    if (idRef() != otherFunc.idRef())
        return false;
    if (returnTypeRef() != otherFunc.returnTypeRef())
        return false;
    if (extraFlags() != otherFunc.extraFlags())
        return false;
    if (callConvKind() != otherFunc.callConvKind())
        return false;
    if (rtAttributeFlags() != otherFunc.rtAttributeFlags())
        return false;

    const auto& params1 = parameters();
    const auto& params2 = otherFunc.parameters();
    if (params1.size() != params2.size())
        return false;

    for (uint32_t i = 0; i < params1.size(); ++i)
    {
        if (params1[i]->typeRef() != params2[i]->typeRef())
            return false;
    }

    return true;
}

SymbolStruct* SymbolFunction::ownerStruct()
{
    if (SymbolMap* symMap = ownerSymMap())
    {
        if (symMap->isImpl())
            return symMap->cast<SymbolImpl>().symStruct();
        if (symMap->isStruct())
            return &symMap->cast<SymbolStruct>();
    }

    return nullptr;
}

const SymbolStruct* SymbolFunction::ownerStruct() const
{
    if (const SymbolMap* symMap = ownerSymMap())
    {
        if (symMap->isImpl())
            return symMap->cast<SymbolImpl>().symStruct();
        if (symMap->isStruct())
            return &symMap->cast<SymbolStruct>();
    }

    return nullptr;
}

SWC_END_NAMESPACE();
