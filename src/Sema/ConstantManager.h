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

    ConstantRef cstBoolTrue_  = ConstantRef::invalid();
    ConstantRef cstBoolFalse_ = ConstantRef::invalid();

public:
    void setup(const TaskContext& ctx);

    ConstantRef          addConstant(const TaskContext& ctx, const ConstantValue& value);
    ConstantRef          cstTrue() const { return cstBoolTrue_; }
    ConstantRef          cstFalse() const { return cstBoolFalse_; }
    ConstantRef          cstBool(bool value) const { return value ? cstBoolTrue_ : cstBoolFalse_; }
    const ConstantValue& get(ConstantRef constantRef) const;
};

SWC_END_NAMESPACE()
