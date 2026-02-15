#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

void SymbolInterface::addFunction(SymbolFunction* sym)
{
    SWC_ASSERT(sym != nullptr);
    sym->setInterfaceMethodSlot(static_cast<uint32_t>(functions_.size()));
    functions_.push_back(sym);
}

Result SymbolInterface::canBeCompleted(Sema& sema) const
{
    for (const auto method : functions_)
    {
        auto& symFunc = method->cast<SymbolFunction>();
        RESULT_VERIFY(sema.waitSemaCompleted(&symFunc, symFunc.codeRef()));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
