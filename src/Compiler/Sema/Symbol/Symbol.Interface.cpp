#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

Result SymbolInterface::canBeCompleted(Sema& sema) const
{
    for (const auto method : functions_)
    {
        auto& symFunc = method->cast<SymbolFunction>();
        RESULT_VERIFY(sema.waitCompleted(&symFunc, symFunc.codeRef()));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
