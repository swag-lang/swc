#pragma once
#include "Core/Store.h"
#include "Sema/ConstantValue.h"

SWC_BEGIN_NAMESPACE()
class CompilerInstance;

class ConstantManager
{
    Store<> store_;

    ConstantRef boolTrue_  = ConstantRef::invalid();
    ConstantRef boolFalse_ = ConstantRef::invalid();

public:
    void                 setup(TaskContext& ctx);
    ConstantRef          addConstant(const ConstantValue& value);
    ConstantRef          boolTrue() const { return boolTrue_; }
    ConstantRef          boolFalse() const { return boolFalse_; }
    const ConstantValue& get(ConstantRef constantRef) const;
};

SWC_END_NAMESPACE()
