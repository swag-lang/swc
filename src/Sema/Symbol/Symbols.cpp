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

AstVisitStepResult SymbolStruct::canBeCompleted(Sema& sema) const
{
    for (const auto field : fields_)
    {
        auto& symVar = field->cast<SymbolVariable>();
        if (symVar.isIgnored())
            continue;
        if (symVar.typeRef().isInvalid())
            continue; // TODO

        auto& type = symVar.typeInfo(sema.ctx());

        if (type.isStruct() && &type.structSym() == this)
        {
            const AstVarDecl* var = swc::castAst<AstVarDecl>(symVar.decl());
            SemaError::raise(sema, DiagnosticId::sema_err_struct_circular_reference, var->nodeTypeRef.isValid() ? var->nodeTypeRef : var->nodeInitRef);
            return AstVisitStepResult::Stop;
        }

        if (!type.isCompleted(sema.ctx()))
        {
            const AstVarDecl* var = swc::castAst<AstVarDecl>(symVar.decl());
            sema.waitCompleted(&type, var->nodeTypeRef.isValid() ? var->nodeTypeRef : var->nodeInitRef);
            return AstVisitStepResult::Pause;
        }
    }

    return AstVisitStepResult::Continue;
}

void SymbolStruct::computeLayout(Sema& sema)
{
    auto& ctx = sema.ctx();

    sizeInBytes_ = 0;
    alignment_   = 0;

    for (const auto field : fields_)
    {
        auto& symVar = field->cast<SymbolVariable>();
        if (symVar.isIgnored())
            continue;
        if (symVar.typeRef().isInvalid())
            continue; // TODO

        auto& type = symVar.typeInfo(ctx);

        const auto sizeOf  = type.sizeOf(ctx);
        const auto alignOf = type.alignOf(ctx);
        alignment_         = std::max(alignment_, alignOf);

        const auto padding = (alignOf - (sizeInBytes_ % alignOf)) % alignOf;
        sizeInBytes_ += padding;

        symVar.setOffset(static_cast<uint32_t>(sizeInBytes_));
        sizeInBytes_ += sizeOf;
    }

    if (alignment_ > 0)
    {
        const auto padding = (alignment_ - (sizeInBytes_ % alignment_)) % alignment_;
        sizeInBytes_ += padding;
    }
}

SWC_END_NAMESPACE()
