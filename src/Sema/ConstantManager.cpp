#include "pch.h"
#include "Sema/ConstantManager.h"
#include "Main/CompilerInstance.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void ConstantManager::setup(CompilerInstance& compiler)
{
    boolTrue_  = addConstant({.typeRef = compiler.typeMgr().getBool(), .b = true});
    boolFalse_ = addConstant({.typeRef = compiler.typeMgr().getBool(), .b = false});
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
