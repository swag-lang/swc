#include "pch.h"
#include "Sema/Constant/ConstantManager.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    ConstantRef addCstFinalize(const ConstantManager& manager, ConstantRef cstRef)
    {
#if SWC_HAS_STATS
        Stats::get().numConstants.fetch_add(1);
        Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

#if SWC_HAS_REF_DEBUG_INFO
        cstRef.setDbgPtr(&manager.getNoLock(cstRef));
#endif
        return cstRef;
    }

    ConstantRef addCstStruct(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        std::unique_lock lk(shard.mutex);
        const auto       view   = ConstantManager::addPayloadBufferNoLock(shard, value.getStruct());
        const auto       stored = ConstantValue::makeStruct(ctx, value.typeRef(), view);

        const uint32_t localIndex = shard.store.push_back(stored);
        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        const ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        return addCstFinalize(manager, result);
    }

    ConstantRef addCstOther(const ConstantManager& manager, ConstantManager::Shard& shard, uint32_t shardIndex, const TaskContext& ctx, const ConstantValue& value)
    {
        {
            std::shared_lock lk(shard.mutex);
            if (const auto it = shard.map.find(value); it != shard.map.end())
                return it->second;
        }

        std::unique_lock lk(shard.mutex);
        auto [it, inserted] = shard.map.try_emplace(value, ConstantRef{});
        if (!inserted)
            return it->second;

        const uint32_t localIndex = shard.store.push_back(value);
        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        const ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        it->second = result;
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

        const auto     view       = ConstantManager::addPayloadBufferNoLock(shard, value.getString());
        const auto     strValue   = ConstantValue::makeString(ctx, view);
        const uint32_t localIndex = shard.store.push_back(strValue);
        SWC_ASSERT(localIndex < ConstantManager::LOCAL_MASK);
        ConstantRef result{(shardIndex << ConstantManager::LOCAL_BITS) | localIndex};
        shard.map.emplace(strValue, result);
        return addCstFinalize(manager, result);
    }
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
    return addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(value, 32, false), 32, TypeInfo::Sign::Signed));
}

ConstantRef ConstantManager::addInt(const TaskContext& ctx, uint64_t value)
{
    const ApsInt        val{value, ApsInt::maxBitWidth()};
    const ConstantValue cstVal = ConstantValue::makeIntUnsized(ctx, val, TypeInfo::Sign::Unknown);
    return addConstant(ctx, cstVal);
}

ConstantRef ConstantManager::addConstant(const TaskContext& ctx, const ConstantValue& value)
{
    const uint32_t shardIndex = value.hash() & (SHARD_COUNT - 1);
    auto&          shard      = shards_[shardIndex];

    if (value.isStruct())
        return addCstStruct(*this, shard, shardIndex, ctx, value);
    if (value.isString())
        return addCstString(*this, shard, shardIndex, ctx, value);
    
    return addCstOther(*this, shard, shardIndex, ctx, value);
}

std::string_view ConstantManager::addString(const TaskContext& ctx, std::string_view str)
{
    return get(addConstant(ctx, ConstantValue::makeString(ctx, str))).getString();
}

std::string_view ConstantManager::addPayloadBuffer(std::string_view payload)
{
    const uint32_t   shardIndex = JobManager::threadIndex() % SHARD_BITS;
    auto&            shard      = shards_[shardIndex];
    std::unique_lock lk(shard.mutex);
    return addPayloadBufferNoLock(shard, payload);
}

std::string_view ConstantManager::addPayloadBufferNoLock(Shard& shard, std::string_view payload)
{
    shard.payload.emplace_back(payload);
    const auto& copied = shard.payload.back();
    return {copied.data(), copied.size()};
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

const ConstantValue& ConstantManager::getNoLock(ConstantRef constantRef) const
{
    SWC_ASSERT(constantRef.isValid());
    const auto shardIndex = constantRef.get() >> LOCAL_BITS;
    const auto localIndex = constantRef.get() & LOCAL_MASK;
    return *shards_[shardIndex].store.ptr<ConstantValue>(localIndex);
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    const auto       shardIndex = constantRef.get() >> LOCAL_BITS;
    std::shared_lock lk(shards_[shardIndex].mutex);
    return getNoLock(constantRef);
}

Result ConstantManager::concretizeConstant(Sema& sema, ConstantRef& result, AstNodeRef nodeOwnerRef, ConstantRef cstRef, TypeInfo::Sign hintSign)
{
    if (!concretizeConstant(sema, result, cstRef, hintSign))
        return SemaError::raiseLiteralTooBig(sema, nodeOwnerRef, get(cstRef));
    return Result::Continue;
}

bool ConstantManager::concretizeConstant(Sema& sema, ConstantRef& result, ConstantRef cstRef, TypeInfo::Sign hintSign)
{
    const auto           ctx     = sema.ctx();
    const ConstantValue& srcCst  = get(cstRef);
    const TypeManager&   typeMgr = ctx.typeMgr();
    const TypeInfo&      ty      = typeMgr.get(srcCst.typeRef());

    if (ty.isIntUnsized())
    {
        TypeInfo::Sign sign = ty.intSign();
        if (sign == TypeInfo::Sign::Unknown)
            sign = hintSign;
        if (sign == TypeInfo::Sign::Unknown)
            sign = TypeInfo::Sign::Signed;

        ApsInt value = srcCst.getIntLike();
        value.setSigned(sign == TypeInfo::Sign::Signed);
        bool           overflow = false;
        const uint32_t destBits = TypeManager::chooseConcreteScalarWidth(value.minBits(), overflow);
        if (overflow)
            return false;

        value.resize(destBits);
        value.setSigned(sign == TypeInfo::Sign::Signed);

        const TypeRef       concreteTypeRef = typeMgr.typeInt(destBits, sign);
        const TypeInfo&     concreteTy      = typeMgr.get(concreteTypeRef);
        const ConstantValue intVal          = ConstantValue::makeFromIntLike(ctx, value, concreteTy);
        result                              = addConstant(ctx, intVal);
        return true;
    }

    if (ty.isFloatUnsized())
    {
        const ApFloat& srcF     = srcCst.getFloat();
        bool           overflow = false;
        const uint32_t destBits = TypeManager::chooseConcreteScalarWidth(srcF.minBits(), overflow);
        if (overflow)
            return false;

        bool                isExact   = false;
        const ApFloat       concreteF = srcF.toFloat(destBits, isExact, overflow);
        const ConstantValue floatVal  = ConstantValue::makeFloat(ctx, concreteF, destBits);
        result                        = addConstant(ctx, floatVal);
        return true;
    }

    result = cstRef;
    return true;
}

SWC_END_NAMESPACE();
