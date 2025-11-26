#pragma once
#include "Core/Store.h"
#include "Sema/ConstantValue.h"

SWC_BEGIN_NAMESPACE()
class CompilerInstance;

class ConstantManager
{
    Store<>                                                           store_;
    std::unordered_map<ConstantValue, ConstantRef, ConstantValueHash> map_;
    std::unordered_set<std::string>                                   cacheStr_;
    mutable std::shared_mutex                                         mutex_;

    ConstantRef boolTrue_  = ConstantRef::invalid();
    ConstantRef boolFalse_ = ConstantRef::invalid();

public:
    void setup(const TaskContext& ctx);

    ConstantRef          addConstant(const TaskContext& ctx, const ConstantValue& value);
    ConstantRef          boolTrue() const { return boolTrue_; }
    ConstantRef          boolFalse() const { return boolFalse_; }
    const ConstantValue& get(ConstantRef constantRef) const;
    ConstantRef          convert(const TaskContext& ctx, const ConstantValue& src, TypeInfoRef targetTypeRef, bool& overflow);
};

SWC_END_NAMESPACE()
