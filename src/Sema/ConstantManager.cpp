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
    const ConstantRef ref{store_.push_back(value)};
    return ref;
}

const ConstantValue& ConstantManager::get(ConstantRef constantRef) const
{
    SWC_ASSERT(constantRef.isValid());
    return *store_.ptr<ConstantValue>(constantRef.get());
}

SWC_END_NAMESPACE()
