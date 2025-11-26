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

ConstantRef ConstantManager::convert(const TaskContext& ctx, const ConstantValue& src, TypeInfoRef targetTypeRef, bool& overflow)
{
    SWC_ASSERT(src.isInt());

    const auto& typeMgr    = ctx.compiler().typeMgr();
    const auto& targetType = typeMgr.get(targetTypeRef);

    // We only support integer target types here
    SWC_ASSERT(targetType.isInt());

    const uint32_t targetBits     = targetType.intBits();
    const bool     targetSigned   = targetType.isIntSigned();
    const bool     targetUnsigned = !targetSigned;

    // Make a working copy of the integer value
    ApsInt value = src.getInt();

    // Keep original signedness for the check
    ApsInt valueForCheck = value;
    valueForCheck.extOrTrunc(targetBits);

    const ApsInt minVal = ApsInt::getMinValue(targetBits, targetUnsigned);
    const ApsInt maxVal = ApsInt::getMaxValue(targetBits, targetUnsigned);

    overflow = (valueForCheck < minVal || valueForCheck > maxVal);

    // Now normalize to the target representation
    if (value.isUnsigned() != targetUnsigned)
        value.setUnsigned(targetUnsigned);

    // Finally, adjust the bit width to the target (this may wrap if overflow == true)
    value.setBitWidth(targetBits);

    // Build the resulting constant with the *target* integer type
    ConstantValue result;
    result.kind_    = ConstantKind::Int;
    result.typeRef_ = targetTypeRef;
    result.int_.val = value;
    return addConstant(ctx, result);
}

SWC_END_NAMESPACE()
