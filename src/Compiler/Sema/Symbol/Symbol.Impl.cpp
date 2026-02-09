#include "pch.h"

#include "Compiler/Lexer/LangSpec.h"
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
    std::unique_lock lk(mutex_);
    if (LangSpec::isSpecOpName(sym->name(ctx)))
        specOps_.push_back(sym);
}

SWC_END_NAMESPACE();
