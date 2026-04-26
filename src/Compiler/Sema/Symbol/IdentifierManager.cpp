#include "pch.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Lexer/Token.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/ByteSpan.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

void IdentifierManager::setup(const TaskContext& ctx)
{
    SWC_UNUSED(ctx);
    predefined_.fill(IdentifierRef::invalid());
    runtimeFunctions_.fill(IdentifierRef::invalid());

    struct PredefinedEntry
    {
        PredefinedName   name;
        std::string_view str;
    };

    static constexpr PredefinedEntry PREDEFINED_NAMES[] = {
        {.name = PredefinedName::Swag, .str = "Swag"},
        {.name = PredefinedName::AttributeUsage, .str = "AttributeUsage"},
        {.name = PredefinedName::AttrMulti, .str = "AttrMulti"},
        {.name = PredefinedName::ConstExpr, .str = "ConstExpr"},
        {.name = PredefinedName::PrintMicro, .str = "PrintMicro"},
        {.name = PredefinedName::PrintAst, .str = "PrintAst"},
        {.name = PredefinedName::Compiler, .str = "Compiler"},
        {.name = PredefinedName::Inline, .str = "Inline"},
        {.name = PredefinedName::NoInline, .str = "NoInline"},
        {.name = PredefinedName::Optimize, .str = "Optimize"},
        {.name = PredefinedName::CanOverflow, .str = "CanOverflow"},
        {.name = PredefinedName::PlaceHolder, .str = "PlaceHolder"},
        {.name = PredefinedName::NoPrint, .str = "NoPrint"},
        {.name = PredefinedName::Macro, .str = "Macro"},
        {.name = PredefinedName::Mixin, .str = "Mixin"},
        {.name = PredefinedName::Implicit, .str = "Implicit"},
        {.name = PredefinedName::EnumFlags, .str = "EnumFlags"},
        {.name = PredefinedName::EnumIndex, .str = "EnumIndex"},
        {.name = PredefinedName::NoDuplicate, .str = "NoDuplicate"},
        {.name = PredefinedName::Complete, .str = "Complete"},
        {.name = PredefinedName::Overload, .str = "Overload"},
        {.name = PredefinedName::Commutative, .str = "Commutative"},
        {.name = PredefinedName::CalleeReturn, .str = "CalleeReturn"},
        {.name = PredefinedName::Foreign, .str = "Foreign"},
        {.name = PredefinedName::Discardable, .str = "Discardable"},
        {.name = PredefinedName::Tls, .str = "Tls"},
        {.name = PredefinedName::NoCopy, .str = "NoCopy"},
        {.name = PredefinedName::Opaque, .str = "Opaque"},
        {.name = PredefinedName::Incomplete, .str = "Incomplete"},
        {.name = PredefinedName::NoDoc, .str = "NoDoc"},
        {.name = PredefinedName::Strict, .str = "Strict"},
        {.name = PredefinedName::Global, .str = "Global"},
        {.name = PredefinedName::Me, .str = "me"},
        {.name = PredefinedName::TargetOs, .str = "TargetOs"},
        {.name = PredefinedName::TargetArch, .str = "TargetArch"},
        {.name = PredefinedName::OpBinary, .str = "opBinary"},
        {.name = PredefinedName::OpBinaryRight, .str = "opBinaryRight"},
        {.name = PredefinedName::OpUnary, .str = "opUnary"},
        {.name = PredefinedName::OpAssign, .str = "opAssign"},
        {.name = PredefinedName::OpIndexAssign, .str = "opIndexAssign"},
        {.name = PredefinedName::OpCast, .str = "opCast"},
        {.name = PredefinedName::OpEquals, .str = "opEquals"},
        {.name = PredefinedName::OpCompare, .str = "opCompare"},
        {.name = PredefinedName::OpPostCopy, .str = "opPostCopy"},
        {.name = PredefinedName::OpPostMove, .str = "opPostMove"},
        {.name = PredefinedName::OpDrop, .str = "opDrop"},
        {.name = PredefinedName::OpCount, .str = "opCount"},
        {.name = PredefinedName::OpData, .str = "opData"},
        {.name = PredefinedName::OpSet, .str = "opSet"},
        {.name = PredefinedName::OpSetLiteral, .str = "opSetLiteral"},
        {.name = PredefinedName::OpSlice, .str = "opSlice"},
        {.name = PredefinedName::OpIndex, .str = "opIndex"},
        {.name = PredefinedName::OpIndexSet, .str = "opIndexSet"},
        {.name = PredefinedName::OpVisit, .str = "opVisit"},
        {.name = PredefinedName::TypeInfo, .str = "TypeInfo"},
        {.name = PredefinedName::TypeInfoNative, .str = "TypeInfoNative"},
        {.name = PredefinedName::TypeInfoPointer, .str = "TypeInfoPointer"},
        {.name = PredefinedName::TypeInfoStruct, .str = "TypeInfoStruct"},
        {.name = PredefinedName::TypeInfoFunc, .str = "TypeInfoFunc"},
        {.name = PredefinedName::TypeInfoEnum, .str = "TypeInfoEnum"},
        {.name = PredefinedName::TypeInfoArray, .str = "TypeInfoArray"},
        {.name = PredefinedName::TypeInfoSlice, .str = "TypeInfoSlice"},
        {.name = PredefinedName::TypeInfoAlias, .str = "TypeInfoAlias"},
        {.name = PredefinedName::TypeInfoVariadic, .str = "TypeInfoVariadic"},
        {.name = PredefinedName::TypeInfoGeneric, .str = "TypeInfoGeneric"},
        {.name = PredefinedName::TypeInfoNamespace, .str = "TypeInfoNamespace"},
        {.name = PredefinedName::TypeInfoCodeBlock, .str = "TypeInfoCodeBlock"},
        {.name = PredefinedName::TypeInfoKind, .str = "TypeInfoKind"},
        {.name = PredefinedName::TypeInfoNativeKind, .str = "TypeInfoNativeKind"},
        {.name = PredefinedName::TypeInfoFlags, .str = "TypeInfoFlags"},
        {.name = PredefinedName::TypeValue, .str = "TypeValue"},
        {.name = PredefinedName::TypeValueFlags, .str = "TypeValueFlags"},
        {.name = PredefinedName::Attribute, .str = "Attribute"},
        {.name = PredefinedName::AttributeParam, .str = "AttributeParam"},
        {.name = PredefinedName::Interface, .str = "Interface"},
        {.name = PredefinedName::SourceCodeLocation, .str = "SourceCodeLocation"},
        {.name = PredefinedName::ErrorValue, .str = "ErrorValue"},
        {.name = PredefinedName::ScratchAllocator, .str = "ScratchAllocator"},
        {.name = PredefinedName::Context, .str = "Context"},
        {.name = PredefinedName::ContextFlags, .str = "ContextFlags"},
        {.name = PredefinedName::Module, .str = "Module"},
        {.name = PredefinedName::ProcessInfos, .str = "ProcessInfos"},
        {.name = PredefinedName::Gvtd, .str = "Gvtd"},
        {.name = PredefinedName::BuildCfg, .str = "BuildCfg"},
        {.name = PredefinedName::RuntimeExit, .str = "__exit"},
        {.name = PredefinedName::RuntimeTestCountInit, .str = "__testCountInit"},
        {.name = PredefinedName::RuntimeTestCountTick, .str = "__testCountTick"},
        {.name = PredefinedName::RuntimeHasErr, .str = "__hasErr"},
        {.name = PredefinedName::RuntimeIsErrContext, .str = "__isErrContext"},
        {.name = PredefinedName::RuntimeSetErrRaw, .str = "__setErrRaw"},
        {.name = PredefinedName::RuntimePushErr, .str = "__pushErr"},
        {.name = PredefinedName::RuntimePopErr, .str = "__popErr"},
        {.name = PredefinedName::RuntimeCatchErr, .str = "__catchErr"},
        {.name = PredefinedName::RuntimeFailedAssume, .str = "__failedAssume"},
        {.name = PredefinedName::RuntimePanic, .str = "@panic"},
        {.name = PredefinedName::RuntimeSafetyPanic, .str = "@safetypanic"},
        {.name = PredefinedName::RuntimeAs, .str = "@as"},
        {.name = PredefinedName::RuntimeIs, .str = "@is"},
        {.name = PredefinedName::RuntimeTypeCmp, .str = "@typecmp"},
        {.name = PredefinedName::RuntimeStringCmp, .str = "@stringcmp"},
        {.name = PredefinedName::RuntimeTlsAlloc, .str = "__tlsAlloc"},
        {.name = PredefinedName::RuntimeTlsGetPtr, .str = "__tlsGetPtr"},
        {.name = PredefinedName::RuntimeTlsGetValue, .str = "__tlsGetValue"},
        {.name = PredefinedName::RuntimeRaiseException, .str = "__raiseException666"},
    };

    for (const auto& it : PREDEFINED_NAMES)
        predefined_[static_cast<size_t>(it.name)] = addIdentifier(it.str);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::Exit)]           = predefined(PredefinedName::RuntimeExit);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TestCountInit)]  = predefined(PredefinedName::RuntimeTestCountInit);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TestCountTick)]  = predefined(PredefinedName::RuntimeTestCountTick);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::HasErr)]         = predefined(PredefinedName::RuntimeHasErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::IsErrContext)]   = predefined(PredefinedName::RuntimeIsErrContext);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::SetErrRaw)]      = predefined(PredefinedName::RuntimeSetErrRaw);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::PushErr)]        = predefined(PredefinedName::RuntimePushErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::PopErr)]         = predefined(PredefinedName::RuntimePopErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::CatchErr)]       = predefined(PredefinedName::RuntimeCatchErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::FailedAssume)]   = predefined(PredefinedName::RuntimeFailedAssume);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::Panic)]          = predefined(PredefinedName::RuntimePanic);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::SafetyPanic)]    = predefined(PredefinedName::RuntimeSafetyPanic);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::As)]             = predefined(PredefinedName::RuntimeAs);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::Is)]             = predefined(PredefinedName::RuntimeIs);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TypeCmp)]        = predefined(PredefinedName::RuntimeTypeCmp);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TlsAlloc)]       = predefined(PredefinedName::RuntimeTlsAlloc);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TlsGetPtr)]      = predefined(PredefinedName::RuntimeTlsGetPtr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TlsGetValue)]    = predefined(PredefinedName::RuntimeTlsGetValue);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::RaiseException)] = predefined(PredefinedName::RuntimeRaiseException);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::StringCmp)]      = predefined(PredefinedName::RuntimeStringCmp);
}

IdentifierRef IdentifierManager::addIdentifier(const TaskContext& ctx, const SourceCodeRef& codeRef)
{
    const SourceView&      srcView = ctx.compiler().srcView(codeRef.srcViewRef);
    const Token&           tok     = srcView.token(codeRef.tokRef);
    const std::string_view name    = tok.string(srcView);

    if (tok.id == TokenId::Identifier)
    {
        const uint32_t crc = tok.crc(srcView);
        return addIdentifier(name, crc);
    }

    return addIdentifier(name);
}

IdentifierRef IdentifierManager::addIdentifier(std::string_view name)
{
    return addIdentifierInternal(name, Math::hash(name), false);
}

IdentifierRef IdentifierManager::addIdentifier(std::string_view name, uint32_t hash)
{
    return addIdentifierInternal(name, hash, false);
}

IdentifierRef IdentifierManager::addIdentifierOwned(std::string_view name)
{
    return addIdentifierInternal(name, Math::hash(name), true);
}

IdentifierRef IdentifierManager::addIdentifierOwned(std::string_view name, uint32_t hash)
{
    return addIdentifierInternal(name, hash, true);
}

IdentifierRef IdentifierManager::addIdentifierInternal(std::string_view name, uint32_t hash, bool copyName)
{
    const uint32_t shardIndex = hash & (SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    auto&          shard       = shards_[shardIndex];
    const uint32_t stripeIndex = (hash >> SHARD_BITS) & (INTERN_STRIPE_COUNT - 1);
    auto&          stripe      = shard.internStripes[stripeIndex];

    {
        const std::shared_lock lk(stripe.mutex);
        if (const auto* it = stripe.map.find(name, hash))
            return *it;
    }

    const std::unique_lock lk(stripe.mutex);
    if (const auto* it = stripe.map.find(name, hash))
        return *it;

    std::string_view storedName = name;
    if (copyName && !name.empty())
    {
        const std::scoped_lock storeLock(shard.storeMutex);
        const auto [span, _] = shard.stringStore.pushCopySpan(asByteSpan(name));
        storedName           = asStringView(span);
    }

    const auto [it, inserted] = stripe.map.try_emplace(storedName, hash, IdentifierRef{});
    if (!inserted)
        return *it;

#if SWC_HAS_STATS
    if (Stats::enabledRuntime())
        Stats::get().numIdentifiers.fetch_add(1, std::memory_order_relaxed);
#endif

    uint32_t localIndex = INVALID_REF;
    {
        const std::scoped_lock storeLock(shard.storeMutex);
        localIndex = shard.store.pushBack(Identifier{storedName});
        SWC_ASSERT(localIndex < LOCAL_MASK);
    }

    auto result = IdentifierRef{(shardIndex << LOCAL_BITS) | localIndex};
#if SWC_HAS_REF_DEBUG_INFO
    result.dbgPtr = &get(result);
#endif

    *it = result;
    return result;
}

const Identifier& IdentifierManager::get(IdentifierRef idRef) const
{
    SWC_ASSERT(idRef.isValid());
    const auto shardIndex = idRef.get() >> LOCAL_BITS;
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    const auto localIndex = idRef.get() & LOCAL_MASK;
    return *(shards_[shardIndex].store.ptr<Identifier>(localIndex));
}

IdentifierManager::RuntimeFunctionKind IdentifierManager::runtimeFunctionKind(const IdentifierRef idRef) const
{
    if (!idRef.isValid())
        return RuntimeFunctionKind::Count;

    for (uint32_t i = 0; i < static_cast<uint32_t>(RuntimeFunctionKind::Count); i++)
    {
        if (runtimeFunctions_[i] == idRef)
            return static_cast<RuntimeFunctionKind>(i);
    }

    return RuntimeFunctionKind::Count;
}

SWC_END_NAMESPACE();
