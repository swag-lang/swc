#include "pch.h"
#include "Sema/Constant/ConstantManager.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

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

    // Struct constants: always copy payload into an internal buffer; no set/unification
    if (value.isStruct())
    {
        std::unique_lock lk(shard.mutex);

        shard.cacheStruct.emplace_back(std::string(value.getStruct()));
        const auto& copied = shard.cacheStruct.back();
        const auto  view   = std::string_view(copied.data(), copied.size());

        const ConstantValue stored = ConstantValue::makeStruct(ctx, value.typeRef(), view);

        const uint32_t localIndex = shard.store.push_back(stored);
        SWC_ASSERT(localIndex < LOCAL_MASK);
        ConstantRef result = ConstantRef{(shardIndex << LOCAL_BITS) | localIndex};

#if SWC_HAS_STATS
        Stats::get().numConstants.fetch_add(1);
        Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

#if SWC_HAS_REF_DEBUG_INFO
        result.setDbgPtr(&getNoLock(result));
#endif
        return result;
    }

    {
        std::shared_lock lk(shard.mutex);
        if (const auto it = shard.map.find(value); it != shard.map.end())
            return it->second;
    }

    std::unique_lock lk(shard.mutex);

    ConstantRef result;
    if (!value.isString())
    {
        auto [it, inserted] = shard.map.try_emplace(value, ConstantRef{});
        if (!inserted)
            return it->second;

        const uint32_t localIndex = shard.store.push_back(value);
        SWC_ASSERT(localIndex < LOCAL_MASK);
        result     = ConstantRef{(shardIndex << LOCAL_BITS) | localIndex};
        it->second = result;
    }

    // For a string, we need to create a copy of the constant value so that it references the
    // internal string constant store which will contain a copy of the input string_view
    else
    {
        if (const auto it = shard.map.find(value); it != shard.map.end())
            return it->second;

        auto [itStr, _]     = shard.cacheStr.insert(std::string(value.getString()));
        const auto view     = std::string_view(itStr->data(), itStr->size());
        const auto strValue = ConstantValue::makeString(ctx, view);

        const uint32_t localIndex = shard.store.push_back(strValue);
        SWC_ASSERT(localIndex < LOCAL_MASK);
        result = ConstantRef{(shardIndex << LOCAL_BITS) | localIndex};
        shard.map.emplace(strValue, result);
    }

#if SWC_HAS_STATS
    Stats::get().numConstants.fetch_add(1);
    Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

#if SWC_HAS_REF_DEBUG_INFO
    result.setDbgPtr(&getNoLock(result));
#endif

    return result;
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
