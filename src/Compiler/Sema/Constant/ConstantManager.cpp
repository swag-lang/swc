#include "pch.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Main/CompilerInstance.h"
#include "Support/Core/FlatTable.h"
#include "Support/Core/PointerSet.h"
#include "Support/Math/Hash.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    ConstantManager::InternStripe& internStripe(ConstantManager::Shard& shard, uint32_t routingHash)
    {
        const uint32_t index = (routingHash >> ConstantStorageLayout::SHARD_BITS) & (ConstantManager::INTERN_STRIPE_COUNT - 1);
        return shard.internStripes[index];
    }

    uint32_t internSlot(uint32_t hash, uint32_t capacity)
    {
        // The low bits already chose the shard and the stripe.
        return (hash >> (ConstantStorageLayout::SHARD_BITS + ConstantManager::INTERN_STRIPE_BITS)) & (capacity - 1);
    }

    // Every worker folds literals and asks for the same common constants, so the lookup of an
    // existing one takes no lock. Only the insertion path locks the stripe.
    ConstantRef findInterned(const ConstantManager::InternStripe& stripe, const ConstantValue& value, uint32_t hash)
    {
        const ConstantManager::InternTable* table = stripe.table.load(std::memory_order_acquire);
        if (!table)
            return ConstantRef::invalid();

        const uint32_t mask = table->capacity - 1;
        for (uint32_t i = internSlot(hash, table->capacity);; i = (i + 1) & mask)
        {
            const ConstantValue* stored = table->values[i].load(std::memory_order_acquire);
            if (!stored)
                return ConstantRef::invalid();
            if (table->hashes[i].load(std::memory_order_relaxed) != hash || !(*stored == value))
                continue;

            ConstantRef ref{table->refs[i].load(std::memory_order_relaxed)};
#if SWC_HAS_REF_DEBUG_INFO
            ref.dbgPtr = stored;
#endif
            return ref;
        }
    }

    void placeInterned(ConstantManager::InternTable& table, const ConstantValue* value, uint32_t hash, uint32_t ref)
    {
        const uint32_t mask = table.capacity - 1;
        uint32_t       i    = internSlot(hash, table.capacity);
        while (table.values[i].load(std::memory_order_relaxed))
            i = (i + 1) & mask;
        // Hash and reference go first: a reader that sees the value reads a complete slot.
        table.hashes[i].store(hash, std::memory_order_relaxed);
        table.refs[i].store(ref, std::memory_order_relaxed);
        table.values[i].store(value, std::memory_order_release);
        table.size++;
    }

    // Called under the stripe mutex. The stripe takes ownership of the canonical constant, and
    // the table it is published in is the only index: writers probe it again under the mutex,
    // where nobody else can add a constant or replace the table.
    ConstantRef publishInterned(ConstantManager::InternStripe& stripe, ConstantManager::StoredConstant canonical, ConstantRef ref, uint32_t hash)
    {
        const ConstantValue& value = *canonical;
        stripe.owned.push_back(std::move(canonical));

        // Keeping the load at or below one half bounds every probe and guarantees an empty slot.
        ConstantManager::InternTable* table = stripe.table.load(std::memory_order_relaxed);
        if (!table || (table->size + 1) * 2 > table->capacity)
        {
            auto grown      = std::make_unique<ConstantManager::InternTable>();
            grown->capacity = table ? table->capacity * 2 : 64;
            grown->values   = std::make_unique<std::atomic<const ConstantValue*>[]>(grown->capacity);
            grown->hashes   = std::make_unique<std::atomic<uint32_t>[]>(grown->capacity);
            grown->refs     = std::make_unique<std::atomic<uint32_t>[]>(grown->capacity);
            if (table)
            {
                for (uint32_t i = 0; i < table->capacity; ++i)
                {
                    if (const ConstantValue* old = table->values[i].load(std::memory_order_relaxed))
                        placeInterned(*grown, old, table->hashes[i].load(std::memory_order_relaxed), table->refs[i].load(std::memory_order_relaxed));
                }
            }

            table = grown.get();
            stripe.tables.push_back(std::move(grown));
            stripe.table.store(table, std::memory_order_release);
        }

        placeInterned(*table, &value, hash, ref.get());
        return ref;
    }
}

// Each manager owns a separate table per calling thread. The flat key array keeps
// repeated graph walks cheap; the deque preserves entry addresses while the table grows.
struct ConstantManager::WalkedAllocations
{
    const std::thread::id threadId = std::this_thread::get_id();

    std::vector<uint64_t>       keys;
    std::unique_ptr<uint32_t[]> entryIndices;
    // A deque, so an entry handed out stays put when the next one is recorded.
    std::deque<ConstantManager::WalkedAllocation> entries;
    size_t                                        used = 0;

    WalkedAllocations()
    {
        keys.resize(1024);
        entryIndices = std::make_unique_for_overwrite<uint32_t[]>(keys.size());
    }

    ConstantManager::WalkedAllocation& slotFor(const uint64_t key)
    {
        const size_t mask  = keys.size() - 1;
        size_t       index = FlatTable::slotIndex(key, mask);
        while (keys[index] != 0)
        {
            if (keys[index] == key)
                return entries[entryIndices[index]];
            index = (index + 1) & mask;
        }

        keys[index]         = key;
        entryIndices[index] = static_cast<uint32_t>(entries.size());
        entries.emplace_back();
        ++used;

        ConstantManager::WalkedAllocation& slot = entries.back();
        if (used * 4 > keys.size() * 3)
            grow();
        return slot;
    }

    void grow()
    {
        std::vector<uint64_t> oldKeys         = std::move(keys);
        auto                  oldEntryIndices = std::move(entryIndices);
        keys.assign(oldKeys.size() * 2, 0);
        entryIndices = std::make_unique_for_overwrite<uint32_t[]>(keys.size());

        const size_t mask = keys.size() - 1;
        for (size_t i = 0; i < oldKeys.size(); ++i)
        {
            if (oldKeys[i] == 0)
                continue;
            size_t index = FlatTable::slotIndex(oldKeys[i], mask);
            while (keys[index] != 0)
                index = (index + 1) & mask;
            keys[index]         = oldKeys[i];
            entryIndices[index] = oldEntryIndices[i];
        }
    }
};

ConstantManager::ConstantManager()
{
    for (Shard& shard : shards_)
        shard.dataSegment.enableProximityStorage();

    for (auto& ref : smallScalarRefs_)
        ref.store(INVALID_REF, std::memory_order_relaxed);
}

ConstantManager::~ConstantManager() = default;

void ConstantManager::setup(const TaskContext& ctx)
{
    cstBool_true_  = addConstant(ctx, ConstantValue::makeBool(ctx, true));
    cstBool_false_ = addConstant(ctx, ConstantValue::makeBool(ctx, false));
    cstS32_0_      = addS32(ctx, 0);
    cstS32_1_      = addS32(ctx, 1);
    cstS32_neg1_   = addS32(ctx, -1);
    cstNull_       = addConstant(ctx, ConstantValue::makeNull(ctx));

    // Scalar float bitwise forms read a complete 16-byte operand. The payload buffer is packed
    // at byte alignment, so the two negation masks get aligned storage of their own, shared by
    // every use.
    const auto addSignMask = [&](const uint32_t signByte, const std::byte*& outStorage, DataSegmentRef& outRef) {
        std::array<std::byte, 16> mask = {};
        mask[signByte]                 = std::byte{0x80};
        const auto [storage, offset]   = shards_[0].dataSegment.addSpan(mask, 16);
        outStorage                     = storage.data();
        outRef                         = {.shardIndex = 0, .offset = offset};
    };

    addSignMask(3, floatSignMask32_, floatSignMaskRef32_);
    addSignMask(7, floatSignMask64_, floatSignMaskRef64_);
}

ConstantRef ConstantManager::addS32(const TaskContext& ctx, int32_t value)
{
    const ConstantRef cstRef = cachedS32(value);
    if (cstRef.isValid())
    {
        return cstRef;
    }

    return addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(value, 32, false), 32, TypeInfo::Sign::Signed));
}

ConstantRef ConstantManager::addInt(const TaskContext& ctx, uint64_t value)
{
    const ApsInt        val{value, ApsInt::maxBitWidth()};
    const ConstantValue cstVal = ConstantValue::makeIntUnsized(ctx, val, TypeInfo::Sign::Unknown);
    return addConstant(ctx, cstVal);
}

ConstantRef ConstantManager::addZeroPayloadConstant(TaskContext& ctx, const TypeRef typeRef)
{
    SWC_ASSERT(typeRef.isValid());
    if (typeRef.isInvalid())
        return ConstantRef::invalid();

    const uint32_t    cacheShardIndex = zeroPayloadConstantCacheShard(typeRef);
    const ConstantRef cached          = findZeroPayloadConstant(cacheShardIndex, typeRef);
    if (cached.isValid())
        return cached;

    const TypeInfo& storageType = ctx.typeMgr().unwrapAliasEnumTypeOrSelf(ctx, typeRef);
    SWC_ASSERT(storageType.isStruct() || storageType.isString() || storageType.isAny() || storageType.isInterface() || storageType.isArray() || (storageType.isFunction() && storageType.isLambdaClosure()));

    const uint64_t sizeOf = storageType.sizeOf(ctx);
    SWC_ASSERT(sizeOf && sizeOf <= std::numeric_limits<uint32_t>::max());
    if (!sizeOf || sizeOf > std::numeric_limits<uint32_t>::max())
        return ConstantRef::invalid();

    SmallVector<std::byte> bytes;
    bytes.resize(sizeOf);

    ConstantValue value;
    if (storageType.isArray())
        value = ConstantValue::makeArrayBorrowed(ctx, typeRef, std::span{bytes.data(), bytes.size()});
    else
        value = ConstantValue::makeStructBorrowed(ctx, typeRef, std::span{bytes.data(), bytes.size()});

    const ConstantRef cstRef = addConstant(ctx, value);
    if (cstRef.isInvalid())
        return ConstantRef::invalid();

    return publishZeroPayloadConstant(cacheShardIndex, typeRef, cstRef);
}

std::string_view ConstantManager::addString(const TaskContext& ctx, std::string_view str)
{
    SWC_UNUSED(ctx);
    const uint32_t shardIndex = std::hash<std::string_view>{}(str) & (ConstantStorageLayout::SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    Shard& shard = shards_[shardIndex];
    return shard.dataSegment.addString(str).first;
}

namespace
{
    bool resolveBorrowedPayloadRef(DataSegmentRef& outRef, const ConstantManager& manager, const ConstantValue& value)
    {
        const void* payloadPtr = nullptr;
        if (value.isStruct())
            payloadPtr = value.getStruct().data();
        else if (value.isArray())
            payloadPtr = value.getArray().data();
        else if (value.isSlice())
            payloadPtr = value.getSlice().data();

        if (!payloadPtr)
            return false;

        if (value.resolveDataSegmentRef(outRef, payloadPtr))
            return true;

        return manager.resolveDataSegmentRef(outRef, payloadPtr);
    }

    bool isBorrowedPayloadBackedByDataSegment(const ConstantManager& manager, const ConstantValue& value)
    {
        DataSegmentRef ref;
        return resolveBorrowedPayloadRef(ref, manager, value);
    }

    uint32_t payloadByteSize(const ConstantValue& value)
    {
        if (value.isStruct())
            return static_cast<uint32_t>(value.getStruct().size());
        if (value.isArray())
            return static_cast<uint32_t>(value.getArray().size());
        SWC_ASSERT(value.isSlice());
        return static_cast<uint32_t>(value.getSlice().size());
    }

    std::pair<std::span<const std::byte>, Ref> addStableSlicePayload(DataSegment& segment, const std::span<const std::byte> payload, const uint64_t count)
    {
        if (!payload.empty() || (!payload.data() && !count))
            return segment.addSpan(payload);

        constexpr std::array sentinel{std::byte{}};
        const auto [storage, ref] = segment.addSpan(sentinel);
        return {std::span{storage.data(), 0}, ref};
    }

    ConstantRef addCstFinalize(const ConstantManager& manager, ConstantRef cstRef)
    {
#if SWC_HAS_REF_DEBUG_INFO
        cstRef.dbgPtr = &manager.get(cstRef);
#endif
        return cstRef;
    }

    ConstantRef addCstSpanPayload(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t routingHash, const ConstantValue& value)
    {
        ConstantManager::InternStripe& stripe = internStripe(shard, routingHash);
        const ConstantRef              found  = findInterned(stripe, value, routingHash);
        if (found.isValid())
            return found;

        ConstantValue stored     = value;
        uint32_t      localIndex = INVALID_REF;
        ConstantRef   result;

        const std::unique_lock lk(stripe.mutex);
        const ConstantRef      existing = findInterned(stripe, value, routingHash);
        if (existing.isValid())
            return existing;

        const uint32_t shardIndex = routingHash & (ConstantStorageLayout::SHARD_COUNT - 1);
        if (value.isStruct())
        {
            const auto [view, ref] = shard.dataSegment.addSpan(value.getStruct());
            stored.setPayloadStruct(view);
            stored.setDataSegmentRef({.shardIndex = shardIndex, .offset = ref});
        }
        else if (value.isArray())
        {
            const auto [view, ref] = shard.dataSegment.addSpan(value.getArray());
            stored.setPayloadArray(view);
            stored.setDataSegmentRef({.shardIndex = shardIndex, .offset = ref});
        }
        else
        {
            SWC_ASSERT(value.isSlice());
            const auto [view, ref] = addStableSlicePayload(shard.dataSegment, value.getSlice(), value.getSliceCount());
            stored.setPayloadSlice(view, value.getSliceCount());
            stored.setDataSegmentRef({.shardIndex = shardIndex, .offset = ref});
        }

        localIndex = shard.dataSegment.add(stored);
        ConstantManager::StoredConstant canonical(shard.dataSegment.ptr<ConstantValue>(localIndex));
        SWC_ASSERT(localIndex < ConstantStorageLayout::LOCAL_MASK);
        result = addCstFinalize(manager, ConstantRef{(shardIndex << ConstantStorageLayout::LOCAL_BITS) | localIndex});
        return publishInterned(stripe, std::move(canonical), result, routingHash);
    }

    ConstantRef addCstString(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t hash, const TaskContext& ctx, const ConstantValue& value)
    {
        ConstantManager::InternStripe& stripe = internStripe(shard, hash);
        const ConstantRef              found  = findInterned(stripe, value, hash);
        if (found.isValid())
            return found;

        uint32_t    localIndex = INVALID_REF;
        ConstantRef result;

        {
            const std::unique_lock lk(stripe.mutex);
            const ConstantRef      existing = findInterned(stripe, value, hash);
            if (existing.isValid())
                return existing;

            const uint32_t shardIndex   = hash & (ConstantStorageLayout::SHARD_COUNT - 1);
            const bool     preserveType = ctx.typeMgr().get(value.typeRef()).isString();
            if (!preserveType)
            {
                // Alias inputs can miss with their original type but normalize to an existing key.
                // Check before allocating a constant that would be discarded at insertion.
                const ConstantValue normalizedValue = ConstantValue::makeString(ctx, value.getString());
                hash                                = Math::hash(normalizedValue.hash());
                const ConstantRef normalized        = findInterned(stripe, normalizedValue, hash);
                if (normalized.isValid())
                    return normalized;
            }

            const std::pair<std::string_view, Ref> res      = shard.dataSegment.addString(value.getString());
            ConstantValue                          strValue = ConstantValue::makeString(ctx, res.first);
            if (preserveType)
                strValue.setTypeRef(value.typeRef());
            strValue.setDataSegmentRef({.shardIndex = shardIndex, .offset = res.second});
            localIndex = shard.dataSegment.add(strValue);
            ConstantManager::StoredConstant canonical(shard.dataSegment.ptr<ConstantValue>(localIndex));
            SWC_ASSERT(localIndex < ConstantStorageLayout::LOCAL_MASK);
            result = addCstFinalize(manager, ConstantRef{(shardIndex << ConstantStorageLayout::LOCAL_BITS) | localIndex});
            result = publishInterned(stripe, std::move(canonical), result, hash);
        }

        return result;
    }

    void updateStoredDataSegmentRef(ConstantManager::Shard& shard, const ConstantRef cstRef, const DataSegmentRef ref)
    {
        if (ref.isInvalid())
            return;

        const uint32_t localIndex = cstRef.get() & ConstantStorageLayout::LOCAL_MASK;
        ConstantValue* stored     = shard.dataSegment.ptr<ConstantValue>(localIndex);
        SWC_ASSERT(stored != nullptr);
        if (!stored)
            return;

        const DataSegmentRef storedRef = stored->dataSegmentRef();
        if (storedRef.isValid() && storedRef.shardIndex == ref.shardIndex && storedRef.offset == ref.offset)
            return;

        stored->setDataSegmentRef(ref);
    }

    void enrichPointerDataSegmentRef(const ConstantManager& manager, ConstantValue& value)
    {
        if (!value.isAnyPointer())
            return;
        if (value.dataSegmentRef().isValid())
            return;

        const uint64_t ptrValue = value.isValuePointer() ? value.getValuePointer() : value.getBlockPointer();
        if (!ptrValue)
            return;

        DataSegmentRef ref;
        if (manager.resolveDataSegmentRef(ref, reinterpret_cast<const void*>(ptrValue)))
            value.setDataSegmentRef(ref);
    }

    ConstantRef addCstOther(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const ConstantValue& value)
    {
        const bool                   borrowedPayload = value.isSpanPayload() && value.isPayloadBorrowed();
        std::optional<ConstantValue> enriched;
        bool                         canDeduplicateByValue = true;
        // Only these fixed-size payloads need mutable preparation. Aggregate vectors can be
        // looked up directly and copied into owned storage only when interning misses.
        if (value.isAnyPointer() || borrowedPayload)
        {
            enriched.emplace(value);
            enrichPointerDataSegmentRef(manager, *enriched);
            const uint32_t payloadSize = borrowedPayload ? payloadByteSize(*enriched) : 0;
            if (payloadSize)
            {
                DataSegmentRef ref;
                SWC_ASSERT(isBorrowedPayloadBackedByDataSegment(manager, *enriched));
                if (resolveBorrowedPayloadRef(ref, manager, *enriched))
                    enriched->setDataSegmentRef(ref);
                // Borrowed payload equality only captures bytes. Allocations that also carry relocations
                // need their own constant entries because the relocation graph changes the runtime value.
                const DataSegmentRef storedRef = enriched->dataSegmentRef();
                canDeduplicateByValue          = storedRef.isInvalid() || !manager.shardDataSegment(storedRef.shardIndex).hasRelocations(storedRef.offset, payloadSize);
            }
        }

        const ConstantValue& stored = enriched ? *enriched : value;
        // The input may itself be interned and have its location enriched concurrently. Keep
        // one snapshot for locking, updates, and publication; location is not part of identity.
        const DataSegmentRef           dataRef     = stored.dataSegmentRef();
        ConstantManager::InternStripe* stripe      = nullptr;
        uint32_t                       routingHash = 0;
        if (canDeduplicateByValue)
        {
            routingHash = Math::hash(stored.hash());
            stripe      = &internStripe(shard, routingHash);
            if (dataRef.isInvalid())
            {
                const ConstantRef found = findInterned(*stripe, stored, routingHash);
                if (found.isValid())
                    return found;
            }
        }

        uint32_t    localIndex = INVALID_REF;
        ConstantRef result;
        {
            if (canDeduplicateByValue)
            {
                const std::unique_lock lk(stripe->mutex);
                const ConstantRef      existing = findInterned(*stripe, stored, routingHash);
                if (existing.isValid())
                {
                    updateStoredDataSegmentRef(shard, existing, dataRef);
                    return existing;
                }

                localIndex = shard.dataSegment.add(stored);
                ConstantManager::StoredConstant canonical(shard.dataSegment.ptr<ConstantValue>(localIndex));
                SWC_ASSERT(localIndex < ConstantStorageLayout::LOCAL_MASK);
                canonical->setDataSegmentRef(dataRef);
                result = addCstFinalize(manager, ConstantRef{(shardIndex << ConstantStorageLayout::LOCAL_BITS) | localIndex});
                return publishInterned(*stripe, std::move(canonical), result, routingHash);
            }
            else
            {
                localIndex = shard.dataSegment.add(stored);
                SWC_ASSERT(localIndex < ConstantStorageLayout::LOCAL_MASK);
                shard.dataSegment.ptr<ConstantValue>(localIndex)->setDataSegmentRef(dataRef);
                result = ConstantRef{(shardIndex << ConstantStorageLayout::LOCAL_BITS) | localIndex};
            }
        }

        return addCstFinalize(manager, result);
    }

    TypeRef normalizeTypeInfoTargetArray(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        TypeManager&    typeMgr = sema.typeMgr();
        const TypeInfo& type    = typeMgr.get(typeRef);
        if (type.isArray())
            return typeRef;
        if (!type.isAggregateArray())
            return TypeRef::invalid();

        const auto& elemTypes = type.payloadAggregate().types;
        if (elemTypes.empty())
            return TypeRef::invalid();

        TypeRef concreteElemTypeRef = TypeRef::invalid();
        for (TypeRef elemTypeRef : elemTypes)
        {
            const TypeInfo& elemType = typeMgr.get(elemTypeRef);
            if (elemType.isAggregateArray())
                elemTypeRef = normalizeTypeInfoTargetArray(sema, elemTypeRef);

            if (!elemTypeRef.isValid())
                return TypeRef::invalid();

            if (!concreteElemTypeRef.isValid())
                concreteElemTypeRef = elemTypeRef;
            else if (concreteElemTypeRef != elemTypeRef)
                return TypeRef::invalid();
        }

        SmallVector<uint64_t> dims;
        SmallVector<TypeRef>  indexTypeRefs;
        dims.push_back(elemTypes.size());
        if (typeMgr.get(concreteElemTypeRef).isArray())
        {
            const TypeInfo& concreteElemType = typeMgr.get(concreteElemTypeRef);
            const auto&     childDims        = concreteElemType.payloadArrayDims();
            dims.insert(dims.end(), childDims.begin(), childDims.end());
            if (!concreteElemType.payloadArrayIndexTypeRefs().empty())
            {
                indexTypeRefs.push_back(TypeRef::invalid());
                const auto& childIndexTypeRefs = concreteElemType.payloadArrayIndexTypeRefs();
                indexTypeRefs.insert(indexTypeRefs.end(), childIndexTypeRefs.begin(), childIndexTypeRefs.end());
            }
            concreteElemTypeRef = concreteElemType.payloadArrayElemTypeRef();
        }

        return typeMgr.addArrayType(dims.span(), concreteElemTypeRef, type.flags(), indexTypeRefs.span());
    }

    TypeRef normalizeTypeInfoTarget(Sema& sema, TypeRef typeRef)
    {
        const TypeRef normalizedArray = normalizeTypeInfoTargetArray(sema, typeRef);
        if (normalizedArray.isValid())
            return normalizedArray;

        return typeRef;
    }
}

ConstantRef ConstantManager::addConstant(const TaskContext& ctx, const ConstantValue& value)
{
    const ConstantRef builtin = tryGetBuiltinConstant(ctx, value);
    if (builtin.isValid())
    {
        return builtin;
    }

    uint32_t cacheIndex = INVALID_REF;
    if (smallScalarCacheIndex(cacheIndex, ctx, value))
    {
        const ConstantRef cached = tryGetSmallScalarCache(cacheIndex);
        if (cached.isValid())
            return cached;

        const ConstantRef cstRef = addConstantSlow(ctx, value);
        return publishSmallScalarCache(cacheIndex, cstRef);
    }

    return addConstantSlow(ctx, value);
}

ConstantRef ConstantManager::addConstantSlow(const TaskContext& ctx, const ConstantValue& value)
{
    const uint32_t routingHash = Math::hash(value.hash());
    const uint32_t shardIndex  = routingHash & (ConstantStorageLayout::SHARD_COUNT - 1);
    const bool     isSpanValue = value.isSpanPayload();
    if (isSpanValue && value.isPayloadBorrowed())
    {
        DataSegmentRef payloadRef;
        if (resolveBorrowedPayloadRef(payloadRef, *this, value))
        {
            SWC_ASSERT(payloadRef.shardIndex < ConstantStorageLayout::SHARD_COUNT);
            ConstantValue valueToAdd = value;
            valueToAdd.setDataSegmentRef(payloadRef);
            return addCstOther(*this, shards_[payloadRef.shardIndex], payloadRef.shardIndex, valueToAdd);
        }
    }

    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    Shard& shard = shards_[shardIndex];

    if (isSpanValue)
        return addCstSpanPayload(*this, shard, routingHash, value);

    if (value.isString())
        return addCstString(*this, shard, routingHash, ctx, value);

    return addCstOther(*this, shard, shardIndex, value);
}

namespace
{
    // A materialized payload constant borrows its bytes from a data segment, which picks its shard.
    DataSegmentRef materializedPayloadDataRef(const ConstantValue& value)
    {
        SWC_ASSERT(value.isSpanPayload());
        SWC_ASSERT(value.isPayloadBorrowed());

        const DataSegmentRef dataRef = value.dataSegmentRef();
        SWC_ASSERT(dataRef.isValid());
        SWC_ASSERT(dataRef.shardIndex < ConstantStorageLayout::SHARD_COUNT);
        return dataRef;
    }
}

ConstantRef ConstantManager::addMaterializedPayloadConstant(const ConstantValue& value)
{
    const DataSegmentRef dataRef = materializedPayloadDataRef(value);
    Shard&               shard   = shards_[dataRef.shardIndex];
    return addCstOther(*this, shard, dataRef.shardIndex, value);
}

ConstantRef ConstantManager::addUniqueMaterializedPayloadConstant(const ConstantValue& value)
{
    const DataSegmentRef dataRef    = materializedPayloadDataRef(value);
    Shard&               shard      = shards_[dataRef.shardIndex];
    const uint32_t       localIndex = shard.dataSegment.add(value);
    SWC_ASSERT(localIndex < ConstantStorageLayout::LOCAL_MASK);
    const auto result = ConstantRef{(dataRef.shardIndex << ConstantStorageLayout::LOCAL_BITS) | localIndex};

    return addCstFinalize(*this, result);
}

size_t ConstantManager::SourceLocationKeyHash::operator()(const SourceLocationKey& key) const noexcept
{
    return Math::hash(std::as_bytes(std::span{key}));
}

ConstantRef ConstantManager::addSourceCodeLocation(const TaskContext& ctx, TypeRef typeRef, const Runtime::SourceCodeLocation& location)
{
    const std::string_view fileName{location.fileName.ptr, location.fileName.length};
    const std::string_view funcName = location.funcName.length ? std::string_view{location.funcName.ptr, location.funcName.length} : std::string_view{};
    // Route by content, never addresses: allocation order must not choose which strings
    // a location shares in the emitted image.
    uint32_t hash                     = Math::hash(fileName);
    hash                              = Math::hashCombine(hash, Math::hash(funcName));
    hash                              = Math::hashCombine(hash, location.lineStart);
    hash                              = Math::hashCombine(hash, location.colStart);
    hash                              = Math::hashCombine(hash, location.colEnd - location.colStart);
    const uint32_t shardIndex         = hash & (ConstantStorageLayout::SHARD_COUNT - 1);
    Shard&         shard              = shards_[shardIndex];
    auto&          segment            = shard.dataSegment;
    const auto [fileView, fileOffset] = segment.addString(fileName);
    const auto [funcView, funcOffset] = funcName.empty() ? std::pair{std::string_view{}, Ref{INVALID_REF}} : segment.addString(funcName);
    const SourceLocationKey key{typeRef.get(), fileOffset, funcOffset, location.lineStart, location.lineEnd, location.colStart, location.colEnd};

    // Publish only after both string relocations exist. Concurrent code-generation jobs
    // must receive the same complete allocation, not duplicate or partly initialized data.
    const std::unique_lock lock(shard.sourceLocationMutex);
    const auto             found = shard.sourceLocationMap.find(key);
    if (found != shard.sourceLocationMap.end())
        return found->second;

    const auto [offset, storage] = segment.reserve<Runtime::SourceCodeLocation>();
    *storage                     = location;
    storage->fileName            = {.ptr = fileView.data(), .length = fileView.size()};
    storage->funcName            = {.ptr = funcView.data(), .length = funcView.size()};
    segment.addRelocation(offset + offsetof(Runtime::SourceCodeLocation, fileName.ptr), fileOffset);
    if (!funcName.empty())
        segment.addRelocation(offset + offsetof(Runtime::SourceCodeLocation, funcName.ptr), funcOffset);
    ConstantValue value = ConstantValue::makeStructBorrowed(ctx, typeRef, std::span{reinterpret_cast<const std::byte*>(storage), sizeof(*storage)});
    value.setDataSegmentRef({.shardIndex = shardIndex, .offset = offset});
    const ConstantRef result = addUniqueMaterializedPayloadConstant(value);
    shard.sourceLocationMap.emplace(key, result);
    return result;
}

ConstantRef ConstantManager::cachedS32(int32_t value) const
{
    switch (value)
    {
        case -1:
            return cstS32_neg1_.isValid() ? cstS32_neg1_ : ConstantRef::invalid();
        case 0:
            return cstS32_0_.isValid() ? cstS32_0_ : ConstantRef::invalid();
        case 1:
            return cstS32_1_.isValid() ? cstS32_1_ : ConstantRef::invalid();
        default:
            return ConstantRef::invalid();
    }
}

ConstantRef ConstantManager::constantRefFromRaw(const uint32_t raw) const
{
    SWC_ASSERT(raw != INVALID_REF);
    ConstantRef cstRef{raw};
#if SWC_HAS_REF_DEBUG_INFO
    cstRef.dbgPtr = &get(cstRef);
#endif
    return cstRef;
}

ConstantRef ConstantManager::publishSmallScalarCache(const uint32_t cacheIndex, const ConstantRef cstRef)
{
    SWC_ASSERT(cacheIndex < smallScalarRefs_.size());
    SWC_ASSERT(cstRef.isValid());

    uint32_t expected = INVALID_REF;
    if (smallScalarRefs_[cacheIndex].compare_exchange_strong(expected, cstRef.get(), std::memory_order_release, std::memory_order_acquire))
        return cstRef;

    const ConstantRef cached = constantRefFromRaw(expected);
    SWC_ASSERT(cached == cstRef);
    return cached;
}

ConstantRef ConstantManager::publishTypeInfoCache(Shard& shard, const TypeRef typeRef, const ConstantRef cstRef)
{
    SWC_ASSERT(typeRef.isValid());
    SWC_ASSERT(cstRef.isValid());

    const std::unique_lock lk(shard.typeInfoMutex);
    if (const ConstantRef* existing = shard.typeInfoMap.find(typeRef.get()))
    {
        SWC_ASSERT(*existing == cstRef);
        return *existing;
    }

    shard.typeInfoMap.emplace(typeRef.get(), cstRef);
    return cstRef;
}

ConstantRef ConstantManager::tryGetBuiltinConstant(const TaskContext& ctx, const ConstantValue& value) const
{
    if (value.isBool() && value.typeRef() == ctx.typeMgr().typeBool())
    {
        const ConstantRef cstRef = cstBool(value.getBool());
        return cstRef.isValid() ? cstRef : ConstantRef::invalid();
    }

    if (value.isNull() && value.typeRef() == ctx.typeMgr().typeNull())
        return cstNull_.isValid() ? cstNull_ : ConstantRef::invalid();

    if (!value.isInt() || value.typeRef() != ctx.typeMgr().typeS32())
        return ConstantRef::invalid();

    const ApsInt& intValue = value.getInt();
    if (intValue.isUnsigned() || intValue.bitWidth() != 32 || !intValue.fits64())
        return ConstantRef::invalid();

    return cachedS32(static_cast<int32_t>(intValue.asI64()));
}

ConstantRef ConstantManager::tryGetSmallScalarCache(const uint32_t cacheIndex) const
{
    SWC_ASSERT(cacheIndex < smallScalarRefs_.size());
    const uint32_t raw = smallScalarRefs_[cacheIndex].load(std::memory_order_acquire);
    if (raw == INVALID_REF)
        return ConstantRef::invalid();

    return constantRefFromRaw(raw);
}

ConstantRef ConstantManager::tryGetTypeInfoCache(const Shard& shard, const TypeRef typeRef)
{
    SWC_ASSERT(typeRef.isValid());

    const std::shared_lock lk(shard.typeInfoMutex);
    const ConstantRef*     found = shard.typeInfoMap.find(typeRef.get());
    return found ? *found : ConstantRef::invalid();
}

uint32_t ConstantManager::zeroPayloadConstantCacheShard(const TypeRef typeRef)
{
    SWC_ASSERT(typeRef.isValid());
    return typeRef.get() & (ConstantStorageLayout::SHARD_COUNT - 1);
}

ConstantRef ConstantManager::findZeroPayloadConstant(const uint32_t shardIndex, const TypeRef typeRef) const
{
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    SWC_ASSERT(typeRef.isValid());

    const Shard&           shard = shards_[shardIndex];
    const std::shared_lock lock(shard.zeroPayloadMutex);
    const ConstantRef*     found = shard.zeroPayloadMap.find(typeRef.get());
    return found ? *found : ConstantRef::invalid();
}

ConstantRef ConstantManager::publishZeroPayloadConstant(const uint32_t shardIndex, const TypeRef typeRef, const ConstantRef cstRef)
{
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    SWC_ASSERT(typeRef.isValid());
    SWC_ASSERT(cstRef.isValid());

    Shard&                 shard = shards_[shardIndex];
    const std::unique_lock lock(shard.zeroPayloadMutex);
    if (const ConstantRef* existing = shard.zeroPayloadMap.find(typeRef.get()))
    {
        SWC_ASSERT(*existing == cstRef);
        return *existing;
    }

    shard.zeroPayloadMap.emplace(typeRef.get(), cstRef);
    return cstRef;
}

bool ConstantManager::smallScalarCacheIndex(uint32_t& outIndex, const TaskContext& ctx, const ConstantValue& value) const
{
    outIndex = INVALID_REF;
    if (!value.isInt())
        return false;

    const uint32_t typeIndex = smallIntTypeIndex(ctx, value.typeRef());
    if (typeIndex == INVALID_REF)
        return false;

    const TypeInfo& type     = ctx.typeMgr().get(value.typeRef());
    const ApsInt&   intValue = value.getInt();
    if (type.isIntUnsigned() != intValue.isUnsigned())
        return false;

    const uint32_t typeBits = type.payloadIntBits();
    if (typeBits)
    {
        if (intValue.bitWidth() != typeBits)
            return false;
    }
    else if (intValue.bitWidth() != ApsInt::maxBitWidth())
    {
        return false;
    }

    int64_t scalarValue = 0;
    if (intValue.isUnsigned())
    {
        if (!intValue.fits64())
            return false;

        const uint64_t rawValue = intValue.as64();
        if (rawValue > static_cast<uint64_t>(SMALL_INT_MAX))
            return false;

        scalarValue = static_cast<int64_t>(rawValue);
    }
    else
    {
        if (!intValue.fits64())
            return false;

        scalarValue = intValue.asI64();
    }

    if (scalarValue < SMALL_INT_MIN || scalarValue > SMALL_INT_MAX)
        return false;

    outIndex = typeIndex * SMALL_INT_RANGE + static_cast<uint32_t>(scalarValue - SMALL_INT_MIN);
    SWC_ASSERT(outIndex < smallScalarRefs_.size());
    return true;
}

uint32_t ConstantManager::smallIntTypeIndex(const TaskContext& ctx, TypeRef typeRef)
{
    const TypeManager& typeMgr = ctx.typeMgr();
    if (typeRef == typeMgr.typeInt())
        return 0;
    if (typeRef == typeMgr.typeIntSigned())
        return 1;
    if (typeRef == typeMgr.typeIntUnsigned())
        return 2;

    if (typeRef == typeMgr.typeU8())
        return 3;
    if (typeRef == typeMgr.typeU16())
        return 4;
    if (typeRef == typeMgr.typeU32())
        return 5;
    if (typeRef == typeMgr.typeU64())
        return 6;

    if (typeRef == typeMgr.typeS8())
        return 7;
    if (typeRef == typeMgr.typeS16())
        return 8;
    if (typeRef == typeMgr.typeS32())
        return 9;
    if (typeRef == typeMgr.typeS64())
        return 10;

    return INVALID_REF;
}

std::string_view ConstantManager::addPayloadBuffer(std::string_view payload, DataSegmentRef* outRef)
{
    const uint32_t shardIndex = std::hash<std::string_view>{}(payload) & (ConstantStorageLayout::SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    Shard& shard           = shards_[shardIndex];
    const auto [view, ref] = shard.dataSegment.addString(payload);
    const DataSegmentRef dataRef{.shardIndex = shardIndex, .offset = ref};
    if (outRef)
        *outRef = dataRef;
    return view;
}

std::string_view ConstantManager::addPayloadBuffer(std::string_view payload, DataSegmentRef* outRef, uint32_t align)
{
    const uint32_t shardIndex = std::hash<std::string_view>{}(payload) & (ConstantStorageLayout::SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    Shard& shard           = shards_[shardIndex];
    const auto [span, ref] = shard.dataSegment.addSpan(std::span{reinterpret_cast<const std::byte*>(payload.data()), payload.size()}, align);
    if (outRef)
        *outRef = DataSegmentRef{.shardIndex = shardIndex, .offset = ref};
    return {reinterpret_cast<const char*>(span.data()), span.size()};
}

// Returns the 16-byte aligned mask whose first f32 or f64 lane holds only the sign bit.
const std::byte* ConstantManager::floatSignMask(const bool is64, DataSegmentRef& outRef) const
{
    SWC_ASSERT(floatSignMask32_ && floatSignMask64_);
    outRef = is64 ? floatSignMaskRef64_ : floatSignMaskRef32_;
    return is64 ? floatSignMask64_ : floatSignMask32_;
}

ConstantRef ConstantManager::cstS32(int32_t value) const
{
    switch (value)
    {
        case -1:
            return cstS32_neg1_;
        case 0:
            return cstS32_0_;
        case 1:
            return cstS32_1_;
        default:
            SWC_UNREACHABLE();
    }
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    SWC_ASSERT(constantRef.isValid());
    const uint32_t shardIndex = constantRef.get() >> ConstantStorageLayout::LOCAL_BITS;
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    const uint32_t localIndex = constantRef.get() & ConstantStorageLayout::LOCAL_MASK;
    return *(shards_[shardIndex].dataSegment.ptr<ConstantValue>(localIndex));
}

Result ConstantManager::makeTypeInfo(Sema& sema, ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef, const TypeInfoLockMode lockMode)
{
    TaskContext& ctx = sema.ctx();
    typeRef          = normalizeTypeInfoTarget(sema, typeRef);
    // Type-info graphs share dependencies. Keep them in one cache so a type and
    // its interface tables retain one identity regardless of the requesting root.
    constexpr uint32_t shardIndex = 0;
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    Shard& shard = shards_[shardIndex];

    const ConstantRef cachedBeforeBuild = tryGetTypeInfoCache(shard, typeRef);
    if (cachedBeforeBuild.isValid())
    {
        outRef = cachedBeforeBuild;
        return Result::Continue;
    }

    TypeGen::TypeGenResult  infoResult;
    const TypeGen::LockMode typeGenLockMode = lockMode == TypeInfoLockMode::TryLock ? TypeGen::LockMode::TryLock : TypeGen::LockMode::Wait;
    SWC_RESULT(sema.typeGen().makeTypeInfo(sema, shard.dataSegment, typeRef, ownerNodeRef, infoResult, typeGenLockMode));
    SWC_ASSERT(infoResult.span.data());

    const ConstantRef cachedAfterBuild = tryGetTypeInfoCache(shard, typeRef);
    if (cachedAfterBuild.isValid())
    {
        outRef = cachedAfterBuild;
        return Result::Continue;
    }

    // Keep the precise generated runtime payload type (TypeInfoNative, TypeInfoArray, ...).
    const uint64_t       ptrValue = reinterpret_cast<uint64_t>(infoResult.span.data());
    ConstantValue        value    = ConstantValue::makeValuePointer(ctx, infoResult.rtTypeRef, ptrValue, TypeInfoFlagsE::Const);
    const DataSegmentRef dataRef{.shardIndex = shardIndex, .offset = infoResult.offset};
    value.setDataSegmentRef(dataRef);
    outRef = publishTypeInfoCache(shard, typeRef, addConstant(sema.ctx(), value));
    sema.compiler().notifyAlive();
    return Result::Continue;
}

TypeRef ConstantManager::makeTypeValue(Sema& sema, ConstantRef cstRef) const
{
    if (!cstRef.isValid())
        return TypeRef::invalid();

    const ConstantValue& cst  = get(cstRef);
    const TypeInfo&      type = sema.typeMgr().get(cst.typeRef());
    if (!type.isAnyTypeInfo(sema.ctx()))
        return TypeRef::invalid();

    if (cst.isValuePointer())
    {
        const auto*   ptr = reinterpret_cast<const void*>(cst.getValuePointer());
        const TypeRef res = sema.typeGen().getBackTypeRef(ptr);
        if (res.isValid())
            return res;
    }

    return cst.typeRef();
}

DataSegment& ConstantManager::shardDataSegment(const uint32_t index)
{
    SWC_ASSERT(index < ConstantStorageLayout::SHARD_COUNT);
    return shards_[index].dataSegment;
}

const DataSegment& ConstantManager::shardDataSegment(const uint32_t index) const
{
    SWC_ASSERT(index < ConstantStorageLayout::SHARD_COUNT);
    return shards_[index].dataSegment;
}

uint64_t ConstantManager::relocationVersionSum() const noexcept
{
    uint64_t sum = 0;
    for (const Shard& shard : shards_)
        sum += shard.dataSegment.relocationVersion();
    return sum;
}

bool ConstantManager::resolveDataSegmentRef(DataSegmentRef& outRef, const void* ptr) const noexcept
{
    outRef = {};
    if (!ptr)
        return false;

    for (uint32_t shardIndex = 0; shardIndex < ConstantStorageLayout::SHARD_COUNT; ++shardIndex)
    {
        const Ref ref = shards_[shardIndex].dataSegment.findRef(ptr);
        if (ref == INVALID_REF)
            continue;

        outRef = {
            .shardIndex = shardIndex,
            .offset     = ref,
        };
        return true;
    }

    return false;
}

ConstantManager::WalkedAllocations& ConstantManager::walkedAllocations() const
{
    // Registration happens only on an owner switch. A thread's table remains private and
    // keeps its entries when work from another live manager runs on that thread.
    const auto            threadId = std::this_thread::get_id();
    const std::lock_guard lock(walkedAllocationsMutex_);
    for (const auto& cache : walkedAllocations_)
    {
        if (cache->threadId == threadId)
            return *cache;
    }

    walkedAllocations_.push_back(std::make_unique<WalkedAllocations>());
    return *walkedAllocations_.back();
}

const ConstantManager::WalkedAllocation* ConstantManager::walkedAllocation(const uint32_t shardIndex, const uint32_t offset) const
{
    struct ThreadCache
    {
        uint64_t           ownerId = 0;
        WalkedAllocations* cache   = nullptr;
    };

    // TLS remembers where to find the last owner's table, but owns no allocation. Segment
    // identities are never reused, so a destroyed manager's pointer cannot be used again,
    // even when the next manager occupies the same address. Keep registration off the hot path.
    static thread_local ThreadCache current;
    const uint64_t                  ownerId = shards_[0].dataSegment.id();
    if (current.ownerId != ownerId)
        current = {.ownerId = ownerId, .cache = &walkedAllocations()};

    const DataSegment& segment = shardDataSegment(shardIndex);
    // The version is read before the relocations: one added in between is served again by the
    // next lookup, never missed.
    const uint64_t version = segment.relocationVersion();
    // Keep every offset bit: neighboring byte offsets must not overwrite each other's
    // entries. The high bit makes the first shard's offset zero a nonempty table key.
    const uint64_t    key    = 1ULL << 63 | static_cast<uint64_t>(shardIndex) << 32 | offset;
    WalkedAllocation& walked = current.cache->slotFor(key);
    if (walked.relocationVersion == version)
        return &walked;

    DataSegmentAllocation allocation;
    if (!segment.findAllocation(allocation, offset))
        return nullptr;

    segment.copyRelocations(walked.relocations, allocation.offset, allocation.size);
    walked.relocationVersion = version;
    walked.allocation        = allocation;
    return &walked;
}

bool ConstantManager::hasUnpublishedFunctionRelocations(const std::span<const DataSegmentRef> roots) const
{
    if (roots.empty())
        return false;

    SmallVector<DataSegmentRef> pending;

    // Roots commonly share runtime type graphs; scan their union once per query. Reuse
    // the worker's table capacity, but clear membership so later queries observe newly
    // published metadata.
    static thread_local StampedKeySet visited;
    visited.clear();

    for (const DataSegmentRef root : roots)
    {
        pending.push_back(root);
        while (!pending.empty())
        {
            const DataSegmentRef current = pending.back();
            pending.pop_back();

            const WalkedAllocation* walked = walkedAllocation(current.shardIndex, current.offset);
            if (!walked)
                continue;

            // The high bit keeps the first allocation of the first shard from packing to zero,
            // which the table reads as a free slot.
            const uint64_t key = 1ULL << 63 | static_cast<uint64_t>(current.shardIndex) << 32 | walked->allocation.offset;
            if (!visited.insert(key))
                continue;

            for (const DataSegmentRelocation& relocation : walked->relocations)
            {
                if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
                {
                    const uint32_t shard = relocation.targetShardIndex == INVALID_REF ? current.shardIndex : relocation.targetShardIndex;
                    pending.push_back({.shardIndex = shard, .offset = relocation.targetOffset});
                }
                else if (relocation.targetSymbol && !relocation.targetSymbol->isForeign() && !relocation.targetSymbol->jitEntryAddress())
                    return true;
            }
        }
    }

    return false;
}

bool ConstantManager::resolveConstantDataSegmentRef(DataSegmentRef& outRef, const ConstantRef cstRef, const void* ptr) const noexcept
{
    outRef = {};
    if (cstRef.isValid())
    {
        const ConstantValue& cst = get(cstRef);
        if (cst.resolveDataSegmentRef(outRef, ptr))
        {
            if (outRef.shardIndex < ConstantStorageLayout::SHARD_COUNT && shards_[outRef.shardIndex].dataSegment.findRef(ptr) == outRef.offset)
                return true;
        }
    }

    return resolveDataSegmentRef(outRef, ptr);
}

DataSegmentRef ConstantManager::findConstantStorage(const ConstantRef cstRef, const TypeRef storageTypeRef) const
{
    SWC_ASSERT(cstRef.isValid() && storageTypeRef.isValid());
    const uint64_t         key   = (static_cast<uint64_t>(cstRef.get()) << 32) | storageTypeRef.get();
    const Shard&           shard = shards_[cstRef.get() >> ConstantStorageLayout::LOCAL_BITS];
    const std::shared_lock lock(shard.constantStorageMutex);
    const DataSegmentRef*  found = shard.constantStorageMap.find(key);
    return found ? *found : DataSegmentRef{};
}

DataSegmentRef ConstantManager::publishConstantStorage(const ConstantRef cstRef, const TypeRef storageTypeRef, const DataSegmentRef dataRef)
{
    SWC_ASSERT(cstRef.isValid() && storageTypeRef.isValid() && dataRef.isValid());
    const uint64_t         key   = (static_cast<uint64_t>(cstRef.get()) << 32) | storageTypeRef.get();
    Shard&                 shard = shards_[cstRef.get() >> ConstantStorageLayout::LOCAL_BITS];
    const std::unique_lock lock(shard.constantStorageMutex);
    // Materialization happens outside the cache lock. Concurrent callers all use
    // the first fully materialized allocation, preserving constant address identity.
    if (const DataSegmentRef* existing = shard.constantStorageMap.find(key))
        return *existing;
    shard.constantStorageMap.emplace(key, dataRef);
    return dataRef;
}

uint32_t ConstantManager::runtimeBufferConstantCacheShard(const TypeRef typeRef, const void* targetPtr, const uint64_t count)
{
    const RuntimeBufferConstantCacheKey key{
        .typeRef   = typeRef,
        .targetPtr = reinterpret_cast<uintptr_t>(targetPtr),
        .count     = count,
    };
    return static_cast<uint32_t>(RuntimeBufferConstantCacheKeyHash{}(key)) & (ConstantStorageLayout::SHARD_COUNT - 1);
}

ConstantRef ConstantManager::findRuntimeBufferConstant(const uint32_t shardIndex, const TypeRef typeRef, const void* targetPtr, const uint64_t count) const
{
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    const RuntimeBufferConstantCacheKey key{
        .typeRef   = typeRef,
        .targetPtr = reinterpret_cast<uintptr_t>(targetPtr),
        .count     = count,
    };

    const Shard&           shard = shards_[shardIndex];
    const std::shared_lock lock(shard.runtimeBufferMutex);
    const auto             it = shard.runtimeBufferMap.find(key);
    if (it == shard.runtimeBufferMap.end())
        return ConstantRef::invalid();
    return it->second;
}

ConstantRef ConstantManager::publishRuntimeBufferConstant(const uint32_t shardIndex, const TypeRef typeRef, const void* targetPtr, const uint64_t count, const ConstantRef cstRef)
{
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    SWC_ASSERT(cstRef.isValid());
    const RuntimeBufferConstantCacheKey key{
        .typeRef   = typeRef,
        .targetPtr = reinterpret_cast<uintptr_t>(targetPtr),
        .count     = count,
    };

    Shard&                 shard = shards_[shardIndex];
    const std::unique_lock lock(shard.runtimeBufferMutex);
    auto [it, inserted] = shard.runtimeBufferMap.try_emplace(key, cstRef);
    return inserted ? cstRef : it->second;
}

uint32_t ConstantManager::runtimeStringConstantCacheShard(const TypeRef typeRef, const std::string_view value)
{
    const RuntimeStringConstantCacheLookupKey key{
        .typeRef = typeRef,
        .value   = value,
    };
    return static_cast<uint32_t>(RuntimeStringConstantCacheKeyHash{}(key)) & (ConstantStorageLayout::SHARD_COUNT - 1);
}

ConstantRef ConstantManager::findRuntimeStringConstant(const uint32_t shardIndex, const TypeRef typeRef, const std::string_view value) const
{
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    const RuntimeStringConstantCacheLookupKey key{
        .typeRef = typeRef,
        .value   = value,
    };

    const Shard&           shard = shards_[shardIndex];
    const std::shared_lock lock(shard.runtimeStringMutex);
    const auto             it = shard.runtimeStringMap.find(key);
    if (it == shard.runtimeStringMap.end())
        return ConstantRef::invalid();
    return it->second;
}

ConstantRef ConstantManager::publishRuntimeStringConstant(const uint32_t shardIndex, const TypeRef typeRef, const std::string_view value, const ConstantRef cstRef)
{
    SWC_ASSERT(shardIndex < ConstantStorageLayout::SHARD_COUNT);
    SWC_ASSERT(cstRef.isValid());
    RuntimeStringConstantCacheKey key;
    key.typeRef = typeRef;
    key.value   = Utf8(value);

    Shard&                 shard = shards_[shardIndex];
    const std::unique_lock lock(shard.runtimeStringMutex);
    auto [it, inserted] = shard.runtimeStringMap.try_emplace(std::move(key), cstRef);
    return inserted ? cstRef : it->second;
}

SWC_END_NAMESPACE();
