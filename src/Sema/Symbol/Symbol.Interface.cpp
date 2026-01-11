#include "pch.h"
#include "Sema/Symbol/Symbol.Interface.h"
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

Result SymbolInterface::canBeCompleted(Sema& sema) const
{
    for (const auto method : methods_)
    {
        auto& symFunc = method->cast<SymbolFunction>();
        if (!symFunc.isCompleted())
        {
            sema.waitCompleted(&symFunc, symFunc.srcViewRef(), symFunc.tokRef());
            return Result::Pause;
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
