#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Backend/JIT/JIT.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Os/Os.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void patchCodeRelocations(std::span<const std::byte> linearCode, std::span<const MicroInstrCodeRelocation> relocations, JITExecMemory& executableMemory)
    {
        if (relocations.empty())
            return;

        SWC_FORCE_ASSERT(!linearCode.empty());
        auto* const basePtr = executableMemory.entryPoint<uint8_t*>();
        SWC_FORCE_ASSERT(basePtr != nullptr);
        SWC_FORCE_ASSERT(!executableMemory.empty());
        SWC_FORCE_ASSERT(executableMemory.size() >= linearCode.size_bytes());

        SWC_FORCE_ASSERT(Os::makeWritableExecutableMemory(basePtr, executableMemory.size()));

        for (const auto& reloc : relocations)
        {
            auto target = reloc.targetAddress;
            if (target == 0 && reloc.targetSymbol && reloc.targetSymbol->isFunction())
                target = reloc.targetSymbol->cast<SymbolFunction>().jitEntryAddress();

            if (target == 0)
                continue;

            SWC_FORCE_ASSERT(reloc.kind == MicroInstrCodeRelocation::Kind::Rel32);

            const uint64_t patchEndOffset = static_cast<uint64_t>(reloc.codeOffset) + sizeof(int32_t);
            SWC_FORCE_ASSERT(patchEndOffset <= executableMemory.size());

            const auto nextAddress = reinterpret_cast<uint64_t>(basePtr + patchEndOffset);
            const auto delta       = static_cast<int64_t>(target) - static_cast<int64_t>(nextAddress);
            SWC_FORCE_ASSERT(delta >= std::numeric_limits<int32_t>::min() && delta <= std::numeric_limits<int32_t>::max());

            const int32_t disp32 = static_cast<int32_t>(delta);
            std::memcpy(basePtr + reloc.codeOffset, &disp32, sizeof(disp32));
        }

        SWC_FORCE_ASSERT(Os::makeExecutableMemory(basePtr, executableMemory.size()));
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
    loweredMicroCode_.emit(ctx, microInstrBuilder(ctx));
    ctx.compiler().notifyAlive();
}

bool SymbolFunction::hasLoweredCode() const noexcept
{
    return !loweredMicroCode_.bytes.empty();
}

void SymbolFunction::jit(TaskContext& ctx)
{
    std::scoped_lock lock(emitMutex_);
    if (hasJitEntryAddress())
        return;
    SWC_ASSERT(hasLoweredCode());

    JIT::emit(ctx, asByteSpan(loweredMicroCode_.bytes), loweredMicroCode_.codeRelocations, jitExecMemory_);
    const auto entry = reinterpret_cast<uint64_t>(jitExecMemory_.entryPoint<void*>());
    SWC_FORCE_ASSERT(entry != 0);
    jitEntryAddress_.store(entry, std::memory_order_release);

    for (const auto& reloc : loweredMicroCode_.codeRelocations)
    {
        if (!reloc.targetSymbol || !reloc.targetSymbol->isFunction())
            continue;

        auto& targetFunc = reloc.targetSymbol->cast<SymbolFunction>();
        if (&targetFunc != this)
            targetFunc.jit(ctx);
    }

    patchCodeRelocations(asByteSpan(loweredMicroCode_.bytes), loweredMicroCode_.codeRelocations, jitExecMemory_);
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
