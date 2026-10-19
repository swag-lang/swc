#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

void SymbolEnum::addImpl(Sema& sema, SymbolImpl& symImpl)
{
    if (impls_.append(sema.ctx(), symImpl, [&] { symImpl.setSymEnum(this); }))
        sema.compiler().notifyAlive();
}

bool SymbolEnum::computeNextValue(Sema& sema, const SourceCodeRef& codeRef)
{
    bool overflow = false;

    // Flag enums start at one, then double a single-bit value.
    if (isEnumFlags())
    {
        if (nextValue().isZero())
        {
            const ApsInt one(1, nextValue().bitWidth(), nextValue().isUnsigned());
            nextValue().add(one, overflow);
        }
        else if (!nextValue().isPowerOf2())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_flag_enum_power_2, codeRef);
            diag.addArgument(Diagnostic::ARG_VALUE, nextValue().toString());
            diag.report(sema.ctx());
            return false;
        }
        else
        {
            nextValue().shiftLeft(1, overflow);
        }
    }
    else
    {
        // Ordinary enums advance by one.
        const ApsInt one(1, nextValue().bitWidth(), nextValue().isUnsigned());
        nextValue().add(one, overflow);
    }

    if (overflow)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_literal_overflow, codeRef);
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, underlyingTypeRef());
        diag.report(sema.ctx());
        return false;
    }

    return true;
}

SWC_END_NAMESPACE();
