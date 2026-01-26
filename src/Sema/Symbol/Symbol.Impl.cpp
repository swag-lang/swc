#include "pch.h"
#include "Sema/Symbol/Symbol.impl.h"

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

SWC_END_NAMESPACE();
