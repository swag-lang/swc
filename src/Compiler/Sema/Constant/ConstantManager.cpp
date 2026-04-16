#include "pch.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Main/Stats.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void recordConstantBuiltinFastHit()
    {
#if SWC_HAS_STATS
        Stats::get().numConstantBuiltinFastHits.fetch_add(1, std::memory_order_relaxed);
#endif
    }

    void recordConstantSmallScalarCacheHit()
    {
#if SWC_HAS_STATS
        Stats::get().numConstantSmallScalarCacheHits.fetch_add(1, std::memory_order_relaxed);
#endif
    }

    void recordConstantSmallScalarCacheMiss()
    {
#if SWC_HAS_STATS
        Stats::get().numConstantSmallScalarCacheMisses.fetch_add(1, std::memory_order_relaxed);
#endif
    }

    void recordConstantSlowPathCall()
    {
#if SWC_HAS_STATS
        Stats::get().numConstantSlowPathCalls.fetch_add(1, std::memory_order_relaxed);
#endif
    }

    void recordConstantMaterializedPayloadFastPath()
    {
#if SWC_HAS_STATS
        Stats::get().numConstantMaterializedPayloadFastPath.fetch_add(1, std::memory_order_relaxed);
#endif
    }
}

ConstantManager::ConstantManager()
{
    for (auto& ref : smallScalarRefs_)
        ref.store(INVALID_REF, std::memory_order_relaxed);
}

void ConstantManager::setup(const TaskContext& ctx)
{
    cstBool_true_  = addConstant(ctx, ConstantValue::makeBool(ctx, true));
    cstBool_false_ = addConstant(ctx, ConstantValue::makeBool(ctx, false));
    cstS32_0_      = addS32(ctx, 0);
    cstS32_1_      = addS32(ctx, 1);
    cstS32_neg1_   = addS32(ctx, -1);
    cstNull_       = addConstant(ctx, ConstantValue::makeNull(ctx));
    cstUndefined_  = addConstant(ctx, ConstantValue::makeUndefined(ctx));
}

ConstantRef ConstantManager::addS32(const TaskContext& ctx, int32_t value)
{
    if (const ConstantRef cstRef = cachedS32(value); cstRef.isValid())
    {
        recordConstantBuiltinFastHit();
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

std::string_view ConstantManager::addString(const TaskContext& ctx, std::string_view str)
{
    SWC_UNUSED(ctx);
    const uint32_t shardIndex = std::hash<std::string_view>{}(str) & (SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < SHARD_COUNT);
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

    ConstantRef addCstFinalize(const ConstantManager& manager, ConstantRef cstRef)
    {
#if SWC_HAS_STATS
        Stats::get().numConstants.fetch_add(1);
#endif

#if SWC_HAS_REF_DEBUG_INFO
        cstRef.dbgPtr = &manager.get(cstRef);
#endif
        return cstRef;
    }

    ConstantRef addCstSpanPayload(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const ConstantValue& value)
    {
        ConstantValue stored     = value;
        uint32_t      localIndex = INVALID_REF;

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
            const auto [view, ref] = shard.dataSegment.addSpan(value.getSlice());
            stored.setPayloadSlice(view, value.getSliceCount());
            stored.setDataSegmentRef({.shardIndex = shardIndex, .offset = ref});
        }

        localIndex = shard.dataSegment.add(stored);

        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        const ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        return addCstFinalize(manager, result);
    }

    ConstantRef addCstString(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        {
            const std::shared_lock lk(shard.mutex);
            const auto it = shard.map.find(value);
            if (it != shard.map.end())
                return it->second;
        }

        uint32_t    localIndex = INVALID_REF;
        ConstantRef result;

        {
            const std::unique_lock lk(shard.mutex);
            const auto it = shard.map.find(value);
            if (it != shard.map.end())
                return it->second;

            const std::pair<std::string_view, Ref> res      = shard.dataSegment.addString(value.getString());
            ConstantValue                          strValue = ConstantValue::makeString(ctx, res.first);
            strValue.setDataSegmentRef({.shardIndex = shardIndex, .offset = res.second});
            localIndex = shard.dataSegment.add(strValue);
            SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
            result = ConstantRef{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
            shard.map.emplace(strValue, result);
        }

        return addCstFinalize(manager, result);
    }

    void updateStoredDataSegmentRef(ConstantManager::Shard& shard, const ConstantRef cstRef, const DataSegmentRef ref)
    {
        if (ref.isInvalid())
            return;

        const uint32_t localIndex = cstRef.get() & ConstantManager::LOCAL_MASK;
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
        if (!value.isValuePointer() && !value.isBlockPointer())
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

    ConstantRef addCstOther(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        SWC_UNUSED(ctx);
        ConstantValue stored = value;
        enrichPointerDataSegmentRef(manager, stored);
        if ((stored.isStruct() || stored.isArray() || stored.isSlice()) && stored.isPayloadBorrowed())
        {
            DataSegmentRef ref;
            SWC_ASSERT(isBorrowedPayloadBackedByDataSegment(manager, stored));
            if (resolveBorrowedPayloadRef(ref, manager, stored))
                stored.setDataSegmentRef(ref);
        }
        if (stored.dataSegmentRef().isInvalid())
        {
            const std::shared_lock lk(shard.mutex);
            const auto it = shard.map.find(stored);
            if (it != shard.map.end())
                return it->second;
        }
        else
        {
            const std::unique_lock lk(shard.mutex);
            const auto it = shard.map.find(stored);
            if (it != shard.map.end())
            {
                updateStoredDataSegmentRef(shard, it->second, stored.dataSegmentRef());
                return it->second;
            }
        }

        uint32_t    localIndex = INVALID_REF;
        ConstantRef result;
        {
            const std::unique_lock lk(shard.mutex);
            auto [it, inserted] = shard.map.try_emplace(stored, ConstantRef{});
            if (!inserted)
            {
                updateStoredDataSegmentRef(shard, it->second, stored.dataSegmentRef());
                return it->second;
            }

            localIndex = shard.dataSegment.add(stored);
            SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
            result     = ConstantRef{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
            it->second = result;
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
        dims.push_back(elemTypes.size());
        if (typeMgr.get(concreteElemTypeRef).isArray())
        {
            const TypeInfo& concreteElemType = typeMgr.get(concreteElemTypeRef);
            const auto&     childDims        = concreteElemType.payloadArrayDims();
            dims.insert(dims.end(), childDims.begin(), childDims.end());
            concreteElemTypeRef = concreteElemType.payloadArrayElemTypeRef();
        }

        return typeMgr.addType(TypeInfo::makeArray(dims.span(), concreteElemTypeRef, type.flags()));
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
        recordConstantBuiltinFastHit();
        return builtin;
    }

    uint32_t cacheIndex = INVALID_REF;
    if (smallScalarCacheIndex(cacheIndex, ctx, value))
    {
        const ConstantRef cached = tryGetSmallScalarCache(cacheIndex);
        if (cached.isValid())
            return cached;

        recordConstantSmallScalarCacheMiss();
        const ConstantRef cstRef = addConstantSlow(ctx, value);
        return publishSmallScalarCache(cacheIndex, cstRef);
    }

    return addConstantSlow(ctx, value);
}

ConstantRef ConstantManager::addConstantSlow(const TaskContext& ctx, const ConstantValue& value)
{
    recordConstantSlowPathCall();
    uint32_t      shardIndex          = Math::hash(value.hash()) & (SHARD_COUNT - 1);
    const bool    isSpanValue         = value.isStruct() || value.isArray() || value.isSlice();
    bool          keepBorrowedPayload = false;
    ConstantValue valueToAdd          = value;
    if (isSpanValue && value.isPayloadBorrowed())
    {
        DataSegmentRef payloadRef;
        if (resolveBorrowedPayloadRef(payloadRef, *this, valueToAdd))
        {
            shardIndex          = payloadRef.shardIndex;
            keepBorrowedPayload = true;
            valueToAdd.setDataSegmentRef(payloadRef);
        }
    }

    SWC_ASSERT(shardIndex < SHARD_COUNT);
    Shard& shard = shards_[shardIndex];

    if (isSpanValue)
    {
        if (keepBorrowedPayload)
            return addCstOther(*this, shard, shardIndex, ctx, valueToAdd);
        return addCstSpanPayload(*this, shard, shardIndex, valueToAdd);
    }

    if (valueToAdd.isString())
        return addCstString(*this, shard, shardIndex, ctx, valueToAdd);

    return addCstOther(*this, shard, shardIndex, ctx, valueToAdd);
}

ConstantRef ConstantManager::addMaterializedPayloadConstant(const ConstantValue& value)
{
    SWC_ASSERT(value.isStruct() || value.isArray() || value.isSlice());
    SWC_ASSERT(value.isPayloadBorrowed());

    const DataSegmentRef dataRef = value.dataSegmentRef();
    SWC_ASSERT(dataRef.isValid());
    SWC_ASSERT(dataRef.shardIndex < SHARD_COUNT);

    Shard&         shard      = shards_[dataRef.shardIndex];
    const uint32_t localIndex = shard.dataSegment.add(value);
    SWC_ASSERT(localIndex < LOCAL_MASK);

    recordConstantMaterializedPayloadFastPath();
    const ConstantRef result{(dataRef.shardIndex << LOCAL_BITS) | localIndex};
    return addCstFinalize(*this, result);
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
    auto [it, inserted] = shard.typeInfoMap.try_emplace(typeRef, cstRef);
    if (!inserted)
    {
        SWC_ASSERT(it->second == cstRef);
        return it->second;
    }

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

    if (value.isUndefined() && value.typeRef() == ctx.typeMgr().typeUndefined())
        return cstUndefined_.isValid() ? cstUndefined_ : ConstantRef::invalid();

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

    recordConstantSmallScalarCacheHit();
    return constantRefFromRaw(raw);
}

ConstantRef ConstantManager::tryGetTypeInfoCache(const Shard& shard, const TypeRef typeRef)
{
    SWC_ASSERT(typeRef.isValid());

    const std::shared_lock lk(shard.typeInfoMutex);
    const auto             it = shard.typeInfoMap.find(typeRef);
    if (it == shard.typeInfoMap.end())
        return ConstantRef::invalid();
    return it->second;
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
    const uint32_t shardIndex = std::hash<std::string_view>{}(payload) & (SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    Shard& shard           = shards_[shardIndex];
    const auto [view, ref] = shard.dataSegment.addString(payload);
    const DataSegmentRef dataRef{.shardIndex = shardIndex, .offset = ref};
    if (outRef)
        *outRef = dataRef;
    return view;
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
    const uint32_t shardIndex = constantRef.get() >> LOCAL_BITS;
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    const uint32_t localIndex = constantRef.get() & LOCAL_MASK;
    return *(shards_[shardIndex].dataSegment.ptr<ConstantValue>(localIndex));
}

Result ConstantManager::makeTypeInfo(Sema& sema, ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef)
{
    TaskContext& ctx          = sema.ctx();
    typeRef                   = normalizeTypeInfoTarget(sema, typeRef);
    const uint32_t shardIndex = typeRef.get() & (SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    Shard& shard = shards_[shardIndex];

    const ConstantRef cachedBeforeBuild = tryGetTypeInfoCache(shard, typeRef);
    if (cachedBeforeBuild.isValid())
    {
        outRef = cachedBeforeBuild;
        return Result::Continue;
    }

    TypeGen::TypeGenResult infoResult;
    SWC_RESULT(sema.typeGen().makeTypeInfo(sema, shard.dataSegment, typeRef, ownerNodeRef, infoResult));
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
    SWC_ASSERT(index < SHARD_COUNT);
    return shards_[index].dataSegment;
}

const DataSegment& ConstantManager::shardDataSegment(const uint32_t index) const
{
    SWC_ASSERT(index < SHARD_COUNT);
    return shards_[index].dataSegment;
}

bool ConstantManager::resolveDataSegmentRef(DataSegmentRef& outRef, const void* ptr) const noexcept
{
    outRef = {};
    if (!ptr)
        return false;

    for (uint32_t shardIndex = 0; shardIndex < SHARD_COUNT; ++shardIndex)
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

bool ConstantManager::resolveConstantDataSegmentRef(DataSegmentRef& outRef, const ConstantRef cstRef, const void* ptr) const noexcept
{
    outRef = {};
    if (cstRef.isValid())
    {
        const ConstantValue& cst = get(cstRef);
        if (cst.resolveDataSegmentRef(outRef, ptr))
        {
            if (outRef.shardIndex < SHARD_COUNT && shards_[outRef.shardIndex].dataSegment.findRef(ptr) == outRef.offset)
                return true;
        }
    }

    return resolveDataSegmentRef(outRef, ptr);
}

SWC_END_NAMESPACE();
