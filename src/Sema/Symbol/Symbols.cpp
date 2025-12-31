#include "pch.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

bool SymbolEnum::assignExplicitValue(Sema& sema, const ConstantValue& val)
{
    if (!typeRef().isValid())
        return false;

    if (underlyingType(sema.ctx()).isInt())
    {
        setNextValue(val.getInt());
        setHasNextValue();
    }

    return true;
}

bool SymbolEnum::computeNextAutoValue(Sema& sema, SourceViewRef srcViewRef, TokenRef tokRef)
{
    if (!underlyingType(sema.ctx()).isInt())
        return false;

    bool overflow = false;

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
    else
    {
        const ApsInt one(1, nextValue().bitWidth(), nextValue().isUnsigned());
        nextValue().add(one, overflow);
    }

    if (overflow)
        return false;

    setHasNextValue();
    return true;
}

const TypeInfo& SymbolEnum::underlyingType(TaskContext& ctx) const
{
    return ctx.typeMgr().get(underlyingTypeRef());
}

SWC_END_NAMESPACE()
