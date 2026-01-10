#include "pch.h"
#include "Sema/Symbol/Symbol.Struct.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

void SymbolStruct::addImpl(SymbolImpl& symImpl)
{
    std::unique_lock lk(mutexImpls_);
    symImpl.setSymStruct(this);
    impls_.push_back(&symImpl);
}

std::vector<SymbolImpl*> SymbolStruct::impls() const
{
    std::shared_lock lk(mutexImpls_);
    return impls_;
}

void SymbolStruct::addInterface(SymbolImpl& symImpl)
{
    std::unique_lock lk(mutexInterfaces_);
    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
}

Result SymbolStruct::addInterface(Sema& sema, SymbolImpl& symImpl)
{
    std::unique_lock lk(mutexInterfaces_);
    for (const auto itf : interfaces_)
    {
        if (itf->idRef() == symImpl.idRef())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_interface_already_implemented, symImpl.srcViewRef(), symImpl.tokRef());
            diag.addArgument(Diagnostic::ARG_SYM, symImpl.name(sema.ctx()));
            diag.addArgument(Diagnostic::ARG_WHAT, name(sema.ctx()));
            auto& note = diag.addElement(DiagnosticId::sema_note_other_implementation);
            note.setSrcView(&sema.compiler().srcView(itf->srcViewRef()));
            note.addSpan(Diagnostic::tokenErrorLocation(sema.ctx(), sema.compiler().srcView(symImpl.srcViewRef()), symImpl.tokRef()), "");
            diag.report(sema.ctx());
            return Result::Stop;
        }
    }

    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
    return Result::Continue;
}

std::vector<SymbolImpl*> SymbolStruct::interfaces() const
{
    std::shared_lock lk(mutexInterfaces_);
    return interfaces_;
}

Result SymbolStruct::canBeCompleted(Sema& sema) const
{
    for (const auto field : fields_)
    {
        auto& symVar = field->cast<SymbolVariable>();
        if (symVar.isIgnored())
            continue;

        auto& type = symVar.typeInfo(sema.ctx());

        if (type.isStruct() && &type.symStruct() == this)
        {
            const AstVarDecl* var = symVar.decl()->cast<AstVarDecl>();
            return SemaError::raise(sema, DiagnosticId::sema_err_struct_circular_reference, var->nodeTypeRef.isValid() ? var->nodeTypeRef : var->nodeInitRef);
        }

        if (!type.isCompleted(sema.ctx()))
        {
            const AstVarDecl* var = symVar.decl()->cast<AstVarDecl>();
            sema.waitCompleted(&type, var->nodeTypeRef.isValid() ? var->nodeTypeRef : var->nodeInitRef);
            return Result::Pause;
        }
    }

    return Result::Continue;
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

SWC_END_NAMESPACE();
