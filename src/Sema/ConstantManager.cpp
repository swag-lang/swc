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

    // Create a copy for overflow checking with the SOURCE signedness
    ApsInt valueForCheck = value;

    // Set the target signedness for comparison
    if (valueForCheck.isUnsigned() != targetUnsigned)
        valueForCheck.setUnsigned(targetUnsigned);

    // Get min/max values for the target type
    const ApsInt minVal = ApsInt::minValue(targetBits, targetUnsigned);
    const ApsInt maxVal = ApsInt::maxValue(targetBits, targetUnsigned);

    // Extend valueForCheck to match the bit width for comparison
    // This ensures we can properly compare against min/max without truncation
    const uint32_t sourceBits = valueForCheck.bitWidth();
    if (sourceBits < targetBits)
    {
        valueForCheck.resize(targetBits);
    }

    // Also extend min/max to the source bit width if needed for comparison
    ApsInt minValExtended = minVal;
    ApsInt maxValExtended = maxVal;
    if (targetBits < sourceBits)
    {
        minValExtended.resize(sourceBits);
        maxValExtended.resize(sourceBits);
        overflow = (valueForCheck < minValExtended || valueForCheck > maxValExtended);
    }
    else
    {
        overflow = (valueForCheck < minVal || valueForCheck > maxVal);
    }

    // Now normalize to the target representation
    if (value.isUnsigned() != targetUnsigned)
        value.setUnsigned(targetUnsigned);

    // Finally, adjust the bit width to the target (this may wrap if overflow == true)
    value.resize(targetBits);

    // Build the resulting constant with the *target* integer type
    ConstantValue result;
    result.kind_    = ConstantKind::Int;
    result.typeRef_ = targetTypeRef;
    result.int_.val = value;
    return addConstant(ctx, result);
}
SWC_END_NAMESPACE()
