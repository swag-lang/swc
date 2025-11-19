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
    void        setup(CompilerInstance& compiler);
    ConstantRef addConstant(const ConstantValue& value);
    ConstantRef boolTrue() const { return boolTrue_; }
    ConstantRef boolFalse() const { return boolFalse_; }
};

SWC_END_NAMESPACE()
