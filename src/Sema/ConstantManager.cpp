#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(TaskContext& ctx)
{
    boolTrue_  = addConstant(ConstantValue::makeBool(ctx, true));
    boolFalse_ = addConstant(ConstantValue::makeBool(ctx, false));
}

ConstantRef ConstantManager::addConstant(const ConstantValue& value)
{
    {
        std::shared_lock lk(mutex_);
        const auto       it = map_.find(value);
        if (it != map_.end())
            return it->second;
    }

    std::unique_lock lk(mutex_);
    const auto [it, inserted] = map_.try_emplace(value, ConstantRef{});
    if (!inserted)
        return it->second;

    const ConstantRef ref{store_.push_back(value)};
    it->second = ref;
    return ref;
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    std::shared_lock lk(mutex_);
    SWC_ASSERT(constantRef.isValid());
    return *store_.ptr<ConstantValue>(constantRef.get());
}

SWC_END_NAMESPACE()
