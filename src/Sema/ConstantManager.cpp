#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(const TaskContext& ctx)
{
    boolTrue_  = addConstant(ctx, ConstantValue::makeBool(ctx, true));
    boolFalse_ = addConstant(ctx, ConstantValue::makeBool(ctx, false));
}

ConstantRef ConstantManager::addConstant(const TaskContext& ctx, const ConstantValue& value)
{
    {
        std::shared_lock lk(mutex_);
        if (const auto it = map_.find(value); it != map_.end())
            return it->second;
    }

    std::unique_lock lk(mutex_);
    if (const auto it = map_.find(value); it != map_.end())
        return it->second;

#if SWC_HAS_STATS
    Stats::get().numConstants.fetch_add(1);
    Stats::get().memConstants.fetch_add(sizeof(ConstantValue), std::memory_order_relaxed);
#endif

    if (value.isString())
    {
        auto [itStr, _] = cacheStr_.insert(std::string(value.getString()));
        auto stored     = ConstantValue::makeString(ctx, std::string_view(itStr->data(), itStr->size()));

        const ConstantRef ref{store_.push_back(stored)};
        map_.emplace(stored, ref);
        return ref;
    }

    const ConstantRef ref{store_.push_back(value)};
    map_.emplace(value, ref);
    return ref;
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    std::shared_lock lk(mutex_);
    SWC_ASSERT(constantRef.isValid());
    return *store_.ptr<ConstantValue>(constantRef.get());
}

ConstantValue ConstantManager::convert(const TaskContext& ctx, const ConstantValue& src, TypeInfoRef targetTypeRef, bool& overflow)
{
    SWC_ASSERT(src.isInt());

    const auto& typeMgr    = ctx.compiler().typeMgr();
    const auto& targetType = typeMgr.get(targetTypeRef);

    // We only support integer target types here
    SWC_ASSERT(targetType.isInt());

    const uint32_t targetBits   = targetType.intBits();
    const bool     targetSigned = targetType.isIntSigned();

    // We only allow 8/16/32/64 bits as per your requirement
    SWC_ASSERT(targetBits == 8u || targetBits == 16u || targetBits == 32u || targetBits == 64u);

    // Make a working copy of the integer value
    ApsInt value = src.getInt();

    // First, normalize the signedness to the target
    if (value.isUnsigned() != targetSigned)
        value.setUnsigned(targetSigned);

    // Now check if it fits in the target range
    // (assuming ApsInt has APSInt-like helpers)
    const ApsInt minVal = ApsInt::getMinValue(targetBits, targetSigned);
    const ApsInt maxVal = ApsInt::getMaxValue(targetBits, targetSigned);

    if (value < minVal || value > maxVal)
    {
        overflow = true;
    }

    // Safe to cast: change bit width to the target
    value.setBitWidth(targetBits);

    // Build the resulting constant with the *target* integer type
    ConstantValue result;
    result.kind_    = ConstantKind::Int;
    result.typeRef_ = targetTypeRef;
    result.int_.val = value;
    return result;
}

SWC_END_NAMESPACE()
