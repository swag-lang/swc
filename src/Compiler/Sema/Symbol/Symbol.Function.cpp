#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Backend/JIT/JIT.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/ExternalModuleManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class JitVisitState : uint8_t
    {
        Visiting,
        Done,
    };

    struct JitStackEntry
    {
        SymbolFunction* function = nullptr;
        bool            expanded = false;
    };

    bool resolveExternAddress(TaskContext& ctx, uint64_t& outFunctionAddress, const SymbolFunction& targetFunction)
    {
        outFunctionAddress = 0;
        if (!targetFunction.isForeign())
            return false;

        const auto moduleName = targetFunction.foreignModuleName();
        if (moduleName.empty())
            return false;

        const Utf8 functionName = targetFunction.resolveForeignFunctionName(ctx);
        if (functionName.empty())
            return false;

        void* functionAddress = nullptr;
        if (!ctx.compiler().externalModuleMgr().getFunctionAddress(functionAddress, moduleName, functionName))
            return false;

        outFunctionAddress = reinterpret_cast<uint64_t>(functionAddress);
        return outFunctionAddress != 0;
    }

    void patchCallExternTargets(TaskContext& ctx, MicroInstrBuilder& builder)
    {
        auto& instructions = builder.instructions();
        auto& operands     = builder.operands();
        auto& relocations = builder.pointerImmediateRelocations();
        for (auto& reloc : relocations)
        {
            auto* const sym = reloc.targetSymbol;
            if (!sym || !sym->isFunction())
                continue;

            const auto& targetFunction = sym->cast<SymbolFunction>();
            uint64_t    functionAddress = 0;
            if (!resolveExternAddress(ctx, functionAddress, targetFunction))
                continue;

            reloc.targetAddress = functionAddress;

            // Keep the micro immediate in sync as a fallback path.
            auto* const inst = instructions.ptr(reloc.instructionRef);
            if (!inst || inst->op != MicroInstrOpcode::LoadRegImm || inst->numOperands < 3)
                continue;

            auto* const ops = inst->ops(operands);
            if (ops[1].opBits == MicroOpBits::B64)
                ops[2].valueU64 = functionAddress;
        }
    }

    void appendJitOrder(SmallVector<SymbolFunction*>& outJitOrder, SymbolFunction& root)
    {
        std::unordered_map<SymbolFunction*, JitVisitState> visitStates;
        SmallVector<JitStackEntry>                         stack;
        stack.push_back({.function = &root, .expanded = false});

        while (!stack.empty())
        {
            const auto current = stack.back();
            stack.pop_back();
            auto* const function = current.function;
            if (!function)
                continue;

            const auto foundState = visitStates.find(function);
            if (current.expanded)
            {
                if (foundState != visitStates.end() && foundState->second == JitVisitState::Done)
                    continue;

                visitStates[function] = JitVisitState::Done;
                outJitOrder.push_back(function);
                continue;
            }

            if (foundState != visitStates.end())
            {
                if (foundState->second == JitVisitState::Done)
                    continue;
                continue;
            }

            visitStates[function] = JitVisitState::Visiting;
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

MicroInstrBuilder& SymbolFunction::microInstrBuilder(TaskContext& ctx) noexcept
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
    for (auto* dep : callDependencies_)
        out.push_back(dep);
}

void SymbolFunction::emit(TaskContext& ctx)
{
    std::scoped_lock lock(emitMutex_);
    if (hasLoweredCode())
        return;
    auto& builder = microInstrBuilder(ctx);
    patchCallExternTargets(ctx, builder);
    loweredMicroCode_.emit(ctx, builder);
    ctx.compiler().notifyAlive();
}

bool SymbolFunction::hasLoweredCode() const noexcept
{
    return !loweredMicroCode_.bytes.empty();
}

void SymbolFunction::jit(TaskContext& ctx)
{
    if (hasJitEntryAddress())
        return;

    SmallVector<SymbolFunction*> jitOrder;
    appendJitOrder(jitOrder, *this);
    for (auto* function : jitOrder)
        function->jitEmit(ctx);
}

void SymbolFunction::jitEmit(TaskContext& ctx)
{
    std::scoped_lock lock(emitMutex_);
    if (hasJitEntryAddress())
        return;

    SWC_ASSERT(hasLoweredCode());
    JIT::emit(ctx, jitExecMemory_, asByteSpan(loweredMicroCode_.bytes), loweredMicroCode_.codeRelocations);
    auto* const entry = jitExecMemory_.entryPoint();
    SWC_FORCE_ASSERT(entry != nullptr);
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
    SymbolStruct* ownerStruct = nullptr;
    if (auto* symMap = ownerSymMap())
    {
        if (const auto* symImpl = symMap->safeCast<SymbolImpl>())
            ownerStruct = symImpl->symStruct();
        else
            ownerStruct = symMap->safeCast<SymbolStruct>();
    }

    return ownerStruct;
}

const SymbolStruct* SymbolFunction::ownerStruct() const
{
    const SymbolStruct* ownerStruct = nullptr;
    if (const auto* symMap = ownerSymMap())
    {
        if (const auto* symImpl = symMap->safeCast<SymbolImpl>())
            ownerStruct = symImpl->symStruct();
        else
            ownerStruct = symMap->safeCast<SymbolStruct>();
    }

    return ownerStruct;
}

SWC_END_NAMESPACE();
