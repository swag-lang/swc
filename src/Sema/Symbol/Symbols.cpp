#include "pch.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"

SWC_BEGIN_NAMESPACE()

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

void SymbolStruct::computeLayout(Sema& sema)
{
    auto& ctx = sema.ctx();

    sizeInBytes_ = 0;
    alignment_   = 0;

    for (const auto field : fields_)
    {
        SymbolVariable& symVar = field->cast<SymbolVariable>();
        if (symVar.isIgnored())
            continue;
        if (symVar.typeRef().isInvalid())
            continue; // TODO

        const TypeInfo& type = symVar.typeInfo(ctx);

        const uint64_t sizeOf  = type.sizeOf(ctx);
        const uint64_t alignOf = std::max(1ULL, sizeOf); // TODO: implement real alignOf, for now use sizeOf
        alignment_             = static_cast<uint32_t>(std::max(static_cast<uint64_t>(alignment_), alignOf));

        const uint64_t padding = (alignOf - (sizeInBytes_ % alignOf)) % alignOf;
        sizeInBytes_ += padding;

        symVar.setOffset(static_cast<uint32_t>(sizeInBytes_));
        sizeInBytes_ += sizeOf;
    }

    if (alignment_ > 0)
    {
        const auto padding = (alignment_ - (sizeInBytes_ % alignment_)) % alignment_;
        sizeInBytes_ += padding;
    }

    sizeInBytes_ = std::max(sizeInBytes_, 1ULL);
}

SWC_END_NAMESPACE()
