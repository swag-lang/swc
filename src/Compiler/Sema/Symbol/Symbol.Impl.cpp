#include "pch.h"

#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

SymbolStruct* SymbolImpl::symStruct() const
{
    SWC_ASSERT(isForStruct());
    return ownerStruct_;
}

void SymbolImpl::setSymStruct(SymbolStruct* sym)
{
    removeExtraFlag(SymbolImplFlagsE::ForEnum);
    addExtraFlag(SymbolImplFlagsE::ForStruct);
    ownerStruct_ = sym;
}

SymbolEnum* SymbolImpl::symEnum() const
{
    SWC_ASSERT(isForEnum());
    return ownerEnum_;
}

void SymbolImpl::setSymEnum(SymbolEnum* sym)
{
    removeExtraFlag(SymbolImplFlagsE::ForStruct);
    addExtraFlag(SymbolImplFlagsE::ForEnum);
    ownerEnum_ = sym;
}

void SymbolImpl::addFunction(const TaskContext& ctx, SymbolFunction* sym)
{
    SWC_UNUSED(ctx);
    std::unique_lock lk(mutex_);
    if (sym->specOpKind() != SpecOpKind::None && sym->specOpKind() != SpecOpKind::Invalid)
        specOps_.push_back(sym);
}

std::vector<SymbolFunction*> SymbolImpl::specOps() const
{
    std::shared_lock lk(mutex_);
    return specOps_;
}

SWC_END_NAMESPACE();
