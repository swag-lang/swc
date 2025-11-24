#pragma once
#include "Core/Store.h"
#include "Math/ApValue.h"

SWC_BEGIN_NAMESPACE()
class CompilerInstance;

class ConstantManager
{
    Store<>                                                     store_;
    std::unordered_map<ApValue, ConstantRef, ConstantValueHash> map_;
    std::unordered_set<std::string>                             cacheStr_;
    mutable std::shared_mutex                                   mutex_;

    ConstantRef boolTrue_  = ConstantRef::invalid();
    ConstantRef boolFalse_ = ConstantRef::invalid();

public:
    void           setup(const TaskContext& ctx);
    ConstantRef    addConstant(const TaskContext& ctx, const ApValue& value);
    ConstantRef    boolTrue() const { return boolTrue_; }
    ConstantRef    boolFalse() const { return boolFalse_; }
    const ApValue& get(ConstantRef constantRef) const;
};

SWC_END_NAMESPACE()
