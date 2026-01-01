#include "pch.h"
#include "Sema/Constant/ConstantManager.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(const TaskContext& ctx)
{
    cstBool_true_  = addConstant(ctx, ConstantValue::makeBool(ctx, true));
    cstBool_false_ = addConstant(ctx, ConstantValue::makeBool(ctx, false));
    cstS32_0_      = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(0LL, 32, false), 32, TypeInfo::Sign::Signed));
    cstS32_1_      = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(1LL, 32, false), 32, TypeInfo::Sign::Signed));
    cstS32_neg1_   = addConstant(ctx, ConstantValue::makeInt(ctx, ApsInt(-1LL, 32, false), 32, TypeInfo::Sign::Signed));
}

ConstantRef ConstantManager::addConstant(const TaskContext& ctx, const ConstantValue& value)
{
    const uint32_t shardIndex = value.hash() & (SHARD_COUNT - 1);
    auto&          shard      = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutex);
        if (const auto it = shard.map.find(value); it != shard.map.end())
            return it->second;
    }

    std::unique_lock lk(shard.mutex);

    const uint32_t localIndex = shard.store.size() / sizeof(ConstantValue);
    SWC_ASSERT(localIndex < LOCAL_MASK);

    ConstantRef result;
    if (!value.isString())
    {
        auto [it, inserted] = shard.map.try_emplace(value, ConstantRef{});
        if (!inserted)
            return it->second;

        shard.store.push_back(value);
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

        shard.store.push_back(strValue);
        result = ConstantRef{(shardIndex << LOCAL_BITS) | localIndex};
        shard.map.emplace(strValue, result);
    }

#if SWC_HAS_STATS
    Stats::get().numConstants.fetch_add(1);
    Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

#if SWC_HAS_DEBUG_INFO
    result.setDbgPtr(&get(result));
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

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    SWC_ASSERT(constantRef.isValid());
    const auto shardIndex = constantRef.get() >> LOCAL_BITS;
    const auto localIndex = constantRef.get() & LOCAL_MASK;
    return *shards_[shardIndex].store.ptr<ConstantValue>(localIndex * sizeof(ConstantValue));
}

ConstantRef ConstantManager::concretizeConstant(Sema& sema, AstNodeRef nodeOwnerRef, ConstantRef cstRef, TypeInfo::Sign hintSign)
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
        {
            SemaError::raiseLiteralTooBig(sema, nodeOwnerRef, get(cstRef));
            return ConstantRef::invalid();
        }

        value.resize(destBits);

        const TypeRef       concreteTypeRef = typeMgr.typeInt(destBits, sign);
        const TypeInfo&     concreteTy      = typeMgr.get(concreteTypeRef);
        const ConstantValue result          = ConstantValue::makeFromIntLike(ctx, value, concreteTy);
        return addConstant(ctx, result);
    }

    if (ty.isFloatUnsized())
    {
        const ApFloat& srcF     = srcCst.getFloat();
        bool           overflow = false;
        const uint32_t destBits = TypeManager::chooseConcreteScalarWidth(srcF.minBits(), overflow);
        if (overflow)
        {
            SemaError::raiseLiteralTooBig(sema, nodeOwnerRef, get(cstRef));
            return ConstantRef::invalid();
        }

        bool                isExact   = false;
        const ApFloat       concreteF = srcF.toFloat(destBits, isExact, overflow);
        const ConstantValue result    = ConstantValue::makeFloat(ctx, concreteF, destBits);
        return addConstant(ctx, result);
    }

    return cstRef;
}

SWC_END_NAMESPACE()
