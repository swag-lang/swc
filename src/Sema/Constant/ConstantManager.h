#pragma once
#include "Core/Store.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()
class CompilerInstance;

class ConstantManager
{
    Store                                                             store_;
    std::unordered_map<ConstantValue, ConstantRef, ConstantValueHash> map_;
    std::unordered_set<std::string>                                   cacheStr_;
    mutable std::shared_mutex                                         mutex_;

    ConstantRef cstBool_true_  = ConstantRef::invalid();
    ConstantRef cstBool_false_ = ConstantRef::invalid();
    ConstantRef cstS32_0_      = ConstantRef::invalid();
    ConstantRef cstS32_1_      = ConstantRef::invalid();
    ConstantRef cstS32_neg1_   = ConstantRef::invalid();

public:
    void setup(const TaskContext& ctx);

    ConstantRef          addConstant(const TaskContext& ctx, const ConstantValue& value);
    ConstantRef          cstTrue() const { return cstBool_true_; }
    ConstantRef          cstFalse() const { return cstBool_false_; }
    ConstantRef          cstBool(bool value) const { return value ? cstBool_true_ : cstBool_false_; }
    ConstantRef          cstS32(int32_t value) const;
    ConstantRef          cstNegBool(ConstantRef cstRef) const { return cstRef == cstBool_true_ ? cstBool_false_ : cstBool_true_; }
    const ConstantValue& get(ConstantRef constantRef) const;
};

SWC_END_NAMESPACE()
