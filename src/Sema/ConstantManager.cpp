#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Main/CompilerInstance.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(CompilerInstance& compiler)
{
    boolTrue_  = addConstant({.typeRef = compiler.typeMgr().typeBool(), .b = true});
    boolFalse_ = addConstant({.typeRef = compiler.typeMgr().typeBool(), .b = false});
}

ConstantRef ConstantManager::addConstant(const ConstantValue& value)
{
    return ConstantRef{store_.push_back(value)};
}

SWC_END_NAMESPACE()
