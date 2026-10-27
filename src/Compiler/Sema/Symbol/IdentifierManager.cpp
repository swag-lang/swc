#include "pch.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Lexer/Token.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

void IdentifierManager::setup(const TaskContext& ctx)
{
    SWC_UNUSED(ctx);
    static_assert(IdentifierRef{}.isInvalid());

    struct PredefinedEntry
    {
        PredefinedName   name;
        std::string_view str;
    };

    static constexpr PredefinedEntry PREDEFINED_NAMES[] = {
        {.name = PredefinedName::Swag, .str = "Swag"},
        {.name = PredefinedName::AttributeUsage, .str = "AttributeUsage"},
        {.name = PredefinedName::AttrUsage, .str = "AttrUsage"},
        {.name = PredefinedName::AttrMulti, .str = "AttrMulti"},
        {.name = PredefinedName::TestTag, .str = "TestTag"},
        {.name = PredefinedName::ConstExpr, .str = "ConstExpr"},
        {.name = PredefinedName::ReadOnly, .str = "ReadOnly"},
        {.name = PredefinedName::PrintMicro, .str = "PrintMicro"},
        {.name = PredefinedName::PrintAst, .str = "PrintAst"},
        {.name = PredefinedName::Compiler, .str = "Compiler"},
        {.name = PredefinedName::Inline, .str = "Inline"},
        {.name = PredefinedName::NoInline, .str = "NoInline"},
        {.name = PredefinedName::Optimize, .str = "Optimize"},
        {.name = PredefinedName::PlaceHolder, .str = "PlaceHolder"},
        {.name = PredefinedName::Macro, .str = "Macro"},
        {.name = PredefinedName::Mixin, .str = "Mixin"},
        {.name = PredefinedName::Implicit, .str = "Implicit"},
        {.name = PredefinedName::EnumFlags, .str = "EnumFlags"},
        {.name = PredefinedName::ReservedEnumAttribute, .str = "__reserved_enum_attribute"},
        {.name = PredefinedName::NoDuplicate, .str = "NoDuplicate"},
        {.name = PredefinedName::FullInit, .str = "FullInit"},
        {.name = PredefinedName::Commutative, .str = "Commutative"},
        {.name = PredefinedName::Operators, .str = "Operators"},
        {.name = PredefinedName::OperatorIgnore, .str = "OperatorIgnore"},
        {.name = PredefinedName::CalleeReturn, .str = "CalleeReturn"},
        {.name = PredefinedName::NoReturn, .str = "NoReturn"},
        {.name = PredefinedName::Foreign, .str = "Foreign"},
        {.name = PredefinedName::Discardable, .str = "Discardable"},
        {.name = PredefinedName::Propagate, .str = "Propagate"},
        {.name = PredefinedName::NoCopy, .str = "NoCopy"},
        {.name = PredefinedName::DynCast, .str = "DynCast"},
        {.name = PredefinedName::Signal, .str = "Signal"},
        {.name = PredefinedName::Opaque, .str = "Opaque"},
        {.name = PredefinedName::NoDoc, .str = "NoDoc"},
        {.name = PredefinedName::Strict, .str = "Strict"},

        {.name = PredefinedName::Me, .str = "me"},

        {.name = PredefinedName::TargetOs, .str = "TargetOs"},
        {.name = PredefinedName::TargetArch, .str = "TargetArch"},
        {.name = PredefinedName::CompilerCommand, .str = "CompilerCommand"},

        {.name = PredefinedName::Operator, .str = "Operator"},
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
        {.name = PredefinedName::OpIndexPtr, .str = "opIndexPtr"},
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
        {.name = PredefinedName::TypeInfoSimd, .str = "TypeInfoSimd"},
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
        {.name = PredefinedName::ProcessInfo, .str = "ProcessInfo"},
        {.name = PredefinedName::GlobalToDrop, .str = "GlobalToDrop"},
        {.name = PredefinedName::BuildCfg, .str = "BuildCfg"},

        {.name = PredefinedName::RuntimeExit, .str = "__exit"},
        {.name = PredefinedName::RuntimeEnsureRuntimeAllocator, .str = "__ensureRuntimeAllocator"},
        {.name = PredefinedName::RuntimeSetupRuntime, .str = "__setupRuntime"},
        {.name = PredefinedName::RuntimeReleaseRuntime, .str = "__releaseRuntime"},
        {.name = PredefinedName::RuntimeCloseRuntime, .str = "__closeRuntime"},

        {.name = PredefinedName::RuntimeHasErr, .str = "__hasErr"},
        {.name = PredefinedName::RuntimeIsErrContext, .str = "__isErrContext"},
        {.name = PredefinedName::RuntimeSetErrRaw, .str = "__setErrRaw"},
        {.name = PredefinedName::RuntimePushErr, .str = "__pushErr"},
        {.name = PredefinedName::RuntimePopErr, .str = "__popErr"},
        {.name = PredefinedName::RuntimeCatchErr, .str = "__catchErr"},
        {.name = PredefinedName::RuntimeEndErr, .str = "__endErr"},
        {.name = PredefinedName::RuntimeBindErr, .str = "__bindErr"},
        {.name = PredefinedName::RuntimeClearErr, .str = "__clearErr"},
        {.name = PredefinedName::RuntimeStoreErr, .str = "__storeErr"},

        {.name = PredefinedName::RuntimeFailedExpect, .str = "__failedExpect"},
        {.name = PredefinedName::RuntimeFailedCast, .str = "__failedCast"},
        {.name = PredefinedName::RuntimePanic, .str = "Swag.panic"},

        {.name = PredefinedName::RuntimeValueBorrowEnter, .str = "__valueBorrowEnter"},
        {.name = PredefinedName::RuntimeValueBorrowLeave, .str = "__valueBorrowLeave"},
        {.name = PredefinedName::RuntimeValueBorrowWrite, .str = "__valueBorrowWrite"},

        {.name = PredefinedName::RuntimeSafetyPanic, .str = "Swag.safetyPanic"},

        {.name = PredefinedName::RuntimeAs, .str = "__borrowAnyValue"},
        {.name = PredefinedName::RuntimeDynamicCast, .str = "__dynamicCast"},
        {.name = PredefinedName::RuntimeTypeCast, .str = "__runtimeTypeCast"},
        {.name = PredefinedName::RuntimeValueCast, .str = "__runtimeValueCast"},
        {.name = PredefinedName::RuntimeIs, .str = "__typeCompatible"},
        {.name = PredefinedName::RuntimeTypeCmp, .str = "Swag.typeCmp"},

        {.name = PredefinedName::RuntimeStringCmp, .str = "Swag.stringCmp"},
        {.name = PredefinedName::RuntimeSliceCmp, .str = "__sliceCmp"},

        {.name = PredefinedName::RuntimeTlsAlloc, .str = "__tlsAlloc"},
        {.name = PredefinedName::RuntimeTlsSetValue, .str = "__tlsSetValue"},
        {.name = PredefinedName::RuntimeTlsGetPtr, .str = "__tlsGetPtr"},
        {.name = PredefinedName::RuntimeTlsGetValue, .str = "__tlsGetValue"},
        {.name = PredefinedName::RuntimeTlsVarPtr, .str = "__tlsVarPtr"},

        {.name = PredefinedName::RuntimeRaiseException, .str = "__raiseException666"},

        {.name = PredefinedName::RuntimeRunTest, .str = "__runTest"},
        {.name = PredefinedName::RuntimeTestsDone, .str = "__testsDone"},

        {.name = PredefinedName::RuntimeParallelRange, .str = "__parallelRange"},
        {.name = PredefinedName::RuntimeParallelRangeFallible, .str = "__parallelRangeFallible"},

        {.name = PredefinedName::ClosureAdapter, .str = "__closure_adapter"},
    };

    for (const auto& it : PREDEFINED_NAMES)
        predefined_[static_cast<size_t>(it.name)] = addIdentifier(it.str);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::Exit)]                   = predefined(PredefinedName::RuntimeExit);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::EnsureRuntimeAllocator)] = predefined(PredefinedName::RuntimeEnsureRuntimeAllocator);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::SetupRuntime)]           = predefined(PredefinedName::RuntimeSetupRuntime);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::ReleaseRuntime)]         = predefined(PredefinedName::RuntimeReleaseRuntime);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::CloseRuntime)]           = predefined(PredefinedName::RuntimeCloseRuntime);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::HasErr)]       = predefined(PredefinedName::RuntimeHasErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::IsErrContext)] = predefined(PredefinedName::RuntimeIsErrContext);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::SetErrRaw)]    = predefined(PredefinedName::RuntimeSetErrRaw);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::PushErr)]      = predefined(PredefinedName::RuntimePushErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::PopErr)]       = predefined(PredefinedName::RuntimePopErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::CatchErr)]     = predefined(PredefinedName::RuntimeCatchErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::EndErr)]       = predefined(PredefinedName::RuntimeEndErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::BindErr)]      = predefined(PredefinedName::RuntimeBindErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::ClearErr)]     = predefined(PredefinedName::RuntimeClearErr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::StoreErr)]     = predefined(PredefinedName::RuntimeStoreErr);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::FailedExpect)] = predefined(PredefinedName::RuntimeFailedExpect);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::FailedCast)]   = predefined(PredefinedName::RuntimeFailedCast);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::Panic)]        = predefined(PredefinedName::RuntimePanic);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::ValueBorrowEnter)] = predefined(PredefinedName::RuntimeValueBorrowEnter);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::ValueBorrowLeave)] = predefined(PredefinedName::RuntimeValueBorrowLeave);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::ValueBorrowWrite)] = predefined(PredefinedName::RuntimeValueBorrowWrite);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::SafetyPanic)] = predefined(PredefinedName::RuntimeSafetyPanic);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::As)]               = predefined(PredefinedName::RuntimeAs);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::DynamicCast)]      = predefined(PredefinedName::RuntimeDynamicCast);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::RuntimeTypeCast)]  = predefined(PredefinedName::RuntimeTypeCast);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::RuntimeValueCast)] = predefined(PredefinedName::RuntimeValueCast);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::Is)]               = predefined(PredefinedName::RuntimeIs);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TypeCmp)]          = predefined(PredefinedName::RuntimeTypeCmp);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TlsAlloc)]    = predefined(PredefinedName::RuntimeTlsAlloc);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TlsSetValue)] = predefined(PredefinedName::RuntimeTlsSetValue);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TlsGetPtr)]   = predefined(PredefinedName::RuntimeTlsGetPtr);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TlsGetValue)] = predefined(PredefinedName::RuntimeTlsGetValue);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TlsVarPtr)]   = predefined(PredefinedName::RuntimeTlsVarPtr);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::RaiseException)] = predefined(PredefinedName::RuntimeRaiseException);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::StringCmp)] = predefined(PredefinedName::RuntimeStringCmp);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::SliceCmp)]  = predefined(PredefinedName::RuntimeSliceCmp);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::RunTest)]   = predefined(PredefinedName::RuntimeRunTest);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::TestsDone)] = predefined(PredefinedName::RuntimeTestsDone);

    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::ParallelRange)]         = predefined(PredefinedName::RuntimeParallelRange);
    runtimeFunctions_[static_cast<size_t>(RuntimeFunctionKind::ParallelRangeFallible)] = predefined(PredefinedName::RuntimeParallelRangeFallible);
}

IdentifierRef IdentifierManager::addIdentifier(const TaskContext& ctx, const SourceCodeRef& codeRef)
{
    const SourceView& srcView = ctx.compiler().srcView(codeRef.srcViewRef);

    // Cloned nodes can temporarily pair the active source view with a borrowed token.
    // If it falls outside this view, return invalid so the caller uses the resolved symbol.
    // The clone's source location is corrected later for diagnostics.
    if (codeRef.tokRef.isInvalid() || codeRef.tokRef.get() >= srcView.tokens().size())
        return IdentifierRef::invalid();

    const Token& tok = srcView.token(codeRef.tokRef);

    if (tok.id == TokenId::Identifier)
    {
        SWC_ASSERT(tok.byteStart < srcView.identifiers().size());
        const SourceIdentifier& identifier = srcView.identifiers()[tok.byteStart];
        SWC_ASSERT(identifier.byteStart + tok.byteLength <= srcView.stringView().size());
        const std::string_view name{srcView.stringView().data() + identifier.byteStart, static_cast<size_t>(tok.byteLength)};
        return addIdentifier(name, identifier.crc);
    }

    SWC_ASSERT(tok.byteStart + tok.byteLength <= srcView.stringView().size());
    return addIdentifier(tok.string(srcView));
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

    // Every token of every file is interned while files are lexed in parallel, and most names
    // already exist, so the lookup takes no lock. Only the insertion path locks the stripe.
    const IdentifierRef found = findInterned(stripe.table.load(std::memory_order_acquire), name, hash);
    if (found.isValid())
        return found;

    // Recheck under the writer mutex: another writer may have inserted the name
    // since the lock-free probe.
    const std::unique_lock lk(stripe.mutex);
    const IdentifierRef    existing = findInterned(stripe.table.load(std::memory_order_relaxed), name, hash);
    if (existing.isValid())
        return existing;

    // Most identifiers borrow source buffers. Copy owned or synthetic names into
    // shard storage so their views remain valid for the compiler lifetime.
    std::string_view storedName = name;
    if (copyName && !name.empty())
    {
        // The stored name must not reference a temporary.
        const std::scoped_lock storeLock(shard.storeMutex);

        const auto [span, _] = shard.stringStore.pushCopySpan(std::span{reinterpret_cast<const std::byte*>(name.data()), name.size()});
        storedName           = std::string_view{reinterpret_cast<const char*>(span.data()), span.size()};
    }

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

    publishInterned(stripe, result, hash);

    return result;
}

uint32_t IdentifierManager::internSlot(uint32_t hash, uint32_t capacity) noexcept
{
    // The low bits already chose the shard and the stripe.
    return (hash >> (SHARD_BITS + INTERN_STRIPE_BITS)) & (capacity - 1);
}

IdentifierRef IdentifierManager::findInterned(const InternTable* table, std::string_view name, uint32_t hash) const noexcept
{
    if (!table)
        return IdentifierRef::invalid();

    const uint32_t mask = table->capacity - 1;
    for (uint32_t i = internSlot(hash, table->capacity);; i = (i + 1) & mask)
    {
        const uint64_t slot = table->slots[i].load(std::memory_order_acquire);
        if (!slot)
            return IdentifierRef::invalid();

        if (static_cast<uint32_t>(slot >> 32) != hash)
            continue;

        IdentifierRef     idRef{static_cast<uint32_t>(slot) - 1};
        const Identifier& identifier = get(idRef);
        if (identifier.name != name)
            continue;
#if SWC_HAS_REF_DEBUG_INFO
        idRef.dbgPtr = &identifier;
#endif
        return idRef;
    }
}

void IdentifierManager::publishInterned(InternStripe& stripe, IdentifierRef idRef, uint32_t hash)
{
    const auto place = [](InternTable& table, uint64_t slot) {
        const uint32_t mask = table.capacity - 1;
        uint32_t       i    = internSlot(static_cast<uint32_t>(slot >> 32), table.capacity);
        while (table.slots[i].load(std::memory_order_relaxed))
            i = (i + 1) & mask;

        table.slots[i].store(slot, std::memory_order_release);
        table.size++;
    };

    // Keeping the load at or below one half bounds every probe and guarantees an empty slot.
    InternTable* table = stripe.table.load(std::memory_order_relaxed);
    if (!table || (table->size + 1) * 2 > table->capacity)
    {
        auto grown      = std::make_unique<InternTable>();
        grown->capacity = table ? table->capacity * 2 : 256;
        grown->slots    = std::make_unique<std::atomic<uint64_t>[]>(grown->capacity);

        if (table)
        {
            for (uint32_t i = 0; i < table->capacity; ++i)
            {
                if (const uint64_t slot = table->slots[i].load(std::memory_order_relaxed))
                    place(*grown, slot);
            }
        }

        table = grown.get();
        stripe.tables.push_back(std::move(grown));
        stripe.table.store(table, std::memory_order_release);
    }

    // The reference is never all ones (local indices stay below LOCAL_MASK), so plus one is never zero.
    place(*table, (static_cast<uint64_t>(hash) << 32) | (static_cast<uint64_t>(idRef.get()) + 1));
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

    // Runtime function names are a tiny fixed set; linear scan keeps setup simple
    // and avoids another map in a path that is not lookup-hot.
    for (uint32_t i = 0; i < static_cast<uint32_t>(RuntimeFunctionKind::Count); i++)
    {
        if (runtimeFunctions_[i] == idRef)
            return static_cast<RuntimeFunctionKind>(i);
    }

    return RuntimeFunctionKind::Count;
}

SWC_END_NAMESPACE();
