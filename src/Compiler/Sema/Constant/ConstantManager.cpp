#include "pch.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

void ConstantManager::setup(TaskContext& ctx)
{
    cstBool_true_  = addConstant(ctx, ConstantValue::makeBool(ctx, true));
    cstBool_false_ = addConstant(ctx, ConstantValue::makeBool(ctx, false));
    cstS32_0_      = addS32(ctx, 0);
    cstS32_1_      = addS32(ctx, 1);
    cstS32_neg1_   = addS32(ctx, -1);
    cstNull_       = addConstant(ctx, ConstantValue::makeNull(ctx));
    cstUndefined_  = addConstant(ctx, ConstantValue::makeUndefined(ctx));
}

ConstantRef ConstantManager::addS32(TaskContext& ctx, int32_t value)
{
    return addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(value, 32, false), 32, TypeInfo::Sign::Signed));
}

ConstantRef ConstantManager::addInt(TaskContext& ctx, uint64_t value)
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
    ConstantRef addCstFinalize(const ConstantManager& manager, ConstantRef cstRef)
    {
#if SWC_HAS_STATS
        Stats::get().numConstants.fetch_add(1);
        Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

#if SWC_HAS_REF_DEBUG_INFO
        cstRef.dbgPtr = &manager.get(cstRef);
#endif
        return cstRef;
    }

    ConstantRef addCstStruct(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        SWC_UNUSED(ctx);
        ConstantValue stored = value;

        std::unique_lock lk(shard.mutex);
        const auto [view, ref] = shard.dataSegment.addSpan(value.getStruct());
        stored.setPayloadStruct(view);

        const uint32_t localIndex = shard.dataSegment.add(stored);
        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        const ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        return addCstFinalize(manager, result);
    }

    ConstantRef addCstArray(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        SWC_UNUSED(ctx);
        ConstantValue stored = value;

        std::unique_lock lk(shard.mutex);
        const auto [view, ref] = shard.dataSegment.addSpan(value.getArray());
        stored.setPayloadArray(view);

        const uint32_t localIndex = shard.dataSegment.add(stored);
        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        const ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        return addCstFinalize(manager, result);
    }

    ConstantRef addCstSlice(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        SWC_UNUSED(ctx);
        ConstantValue stored = value;

        std::unique_lock lk(shard.mutex);
        const auto [view, ref] = shard.dataSegment.addSpan(value.getSlice());
        stored.setPayloadSlice(view);

        const uint32_t localIndex = shard.dataSegment.add(stored);
        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        const ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        return addCstFinalize(manager, result);
    }

    ConstantRef addCstString(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        {
            std::shared_lock lk(shard.mutex);
            if (const auto it = shard.map.find(value); it != shard.map.end())
                return it->second;
        }

        std::unique_lock lk(shard.mutex);
        if (const auto it = shard.map.find(value); it != shard.map.end())
            return it->second;

        const std::pair<std::string_view, Ref> res        = shard.dataSegment.addString(value.getString());
        const ConstantValue                    strValue   = ConstantValue::makeString(ctx, res.first);
        const uint32_t                         localIndex = shard.dataSegment.add(strValue);
        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        shard.map.emplace(strValue, result);
        return addCstFinalize(manager, result);
    }

    ConstantRef addCstOther(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        SWC_UNUSED(ctx);
        {
            std::shared_lock lk(shard.mutex);
            if (const auto it = shard.map.find(value); it != shard.map.end())
                return it->second;
        }

        std::unique_lock lk(shard.mutex);
        auto [it, inserted] = shard.map.try_emplace(value, ConstantRef{});
        if (!inserted)
            return it->second;

        const uint32_t localIndex = shard.dataSegment.add(value);
        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        const ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        it->second = result;
        return addCstFinalize(manager, result);
    }
}

ConstantRef ConstantManager::addConstant(const TaskContext& ctx, const ConstantValue& value)
{
    const uint32_t shardIndex = value.hash() & (SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    Shard& shard = shards_[shardIndex];

    if (value.isStruct())
    {
        if (value.isPayloadBorrowed())
            return addCstOther(*this, shard, shardIndex, ctx, value);
        return addCstStruct(*this, shard, shardIndex, ctx, value);
    }
    if (value.isArray())
    {
        if (value.isPayloadBorrowed())
            return addCstOther(*this, shard, shardIndex, ctx, value);
        return addCstArray(*this, shard, shardIndex, ctx, value);
    }
    if (value.isSlice())
    {
        if (value.isPayloadBorrowed())
            return addCstOther(*this, shard, shardIndex, ctx, value);
        return addCstSlice(*this, shard, shardIndex, ctx, value);
    }
    if (value.isString())
        return addCstString(*this, shard, shardIndex, ctx, value);

    return addCstOther(*this, shard, shardIndex, ctx, value);
}

std::string_view ConstantManager::addPayloadBuffer(std::string_view payload)
{
    const uint32_t shardIndex = std::hash<std::string_view>{}(payload) & (SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    Shard& shard = shards_[shardIndex];
    return shard.dataSegment.addString(payload).first;
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
    return *SWC_CHECK_NOT_NULL(shards_[shardIndex].dataSegment.ptr<ConstantValue>(localIndex));
}

Result ConstantManager::makeTypeInfo(Sema& sema, ConstantRef& outRef, TypeRef typeRef, AstNodeRef ownerNodeRef)
{
    TaskContext&   ctx        = sema.ctx();
    const uint32_t shardIndex = typeRef.get() & (SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    Shard& shard = shards_[shardIndex];

    TypeGen::TypeGenResult infoResult;

    {
        std::unique_lock lk(shard.mutex);
        RESULT_VERIFY(sema.typeGen().makeTypeInfo(sema, shard.dataSegment, typeRef, ownerNodeRef, infoResult));
    }

    // 'typeinfo(T)' produces a value of the built-in 'TypeInfo' type.
    // That type is a pointer to the runtime typeinfo payload stored in the 'DataSegment'.
    SWC_ASSERT(infoResult.span.data());
    const uint64_t      ptrValue = reinterpret_cast<uint64_t>(infoResult.span.data());
    const ConstantValue value    = ConstantValue::makeValuePointer(ctx, sema.typeMgr().structTypeInfo(), ptrValue, TypeInfoFlagsE::Const);
    ConstantValue       stored   = value;
    stored.setTypeRef(sema.typeMgr().typeTypeInfo());
    outRef = addConstant(sema.ctx(), stored);
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
        auto          ptr = reinterpret_cast<const void*>(cst.getValuePointer());
        const TypeRef res = sema.typeGen().getBackTypeRef(ptr);
        if (res.isValid())
            return res;
    }

    return cst.typeRef();
}

SWC_END_NAMESPACE();
