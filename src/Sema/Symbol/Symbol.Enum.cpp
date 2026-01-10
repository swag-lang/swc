#include "pch.h"
#include "Sema/Symbol/Symbol.Enum.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE();

void SymbolEnum::merge(TaskContext& ctx, SymbolMap* other)
{
    SymbolMap::merge(ctx, other);
}

bool SymbolEnum::computeNextValue(Sema& sema, SourceViewRef srcViewRef, TokenRef tokRef)
{
    bool overflow = false;

    // Update enum "nextValue" = value << 1
    if (isEnumFlags())
    {
        if (nextValue().isZero())
        {
            const ApsInt one(1, nextValue().bitWidth(), nextValue().isUnsigned());
            nextValue().add(one, overflow);
        }
        else if (!nextValue().isPowerOf2())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_flag_enum_power_2, srcViewRef, tokRef);
            diag.addArgument(Diagnostic::ARG_VALUE, nextValue().toString());
            diag.report(sema.ctx());
            return false;
        }
        else
        {
            nextValue().shiftLeft(1, overflow);
        }
    }

    // Update enum "nextValue" = value + 1
    else
    {
        const ApsInt one(1, nextValue().bitWidth(), nextValue().isUnsigned());
        nextValue().add(one, overflow);
    }

    if (overflow)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_literal_overflow, srcViewRef, tokRef);
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, underlyingTypeRef());
        diag.report(sema.ctx());
        return false;
    }

    return true;
}

SWC_END_NAMESPACE();
