#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

void SymbolStruct::addImpl(Sema& sema, SymbolImpl& symImpl)
{
    std::unique_lock lk(mutexImpls_);
    symImpl.setSymStruct(this);
    impls_.push_back(&symImpl);
    sema.compiler().notifyAlive();
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
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_interface_already_implemented, symImpl);
            diag.addArgument(Diagnostic::ARG_WHAT, name(sema.ctx()));
            auto&       note    = diag.addElement(DiagnosticId::sema_note_other_implementation);
            const auto& srcView = sema.compiler().srcView(itf->srcViewRef());
            note.setSrcView(&srcView);
            note.addSpan(srcView.tokenCodeRange(sema.ctx(), itf->tokRef()), "");
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    // Expose the interface implementation scope under the struct symbol map so we can resolve
    // `StructName.InterfaceName.Symbol`.
    if (const auto* inserted = addSingleSymbol(sema.ctx(), &symImpl); inserted != &symImpl)
        return SemaError::raiseAlreadyDefined(sema, &symImpl, inserted);

    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
    sema.compiler().notifyAlive();
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

        const AstVarDecl*         var     = symVar.decl()->safeCast<AstVarDecl>();
        const AstVarDeclNameList* varList = symVar.decl()->safeCast<AstVarDeclNameList>();

        if (type.isStruct() && &type.payloadSymStruct() == this)
        {
            if (var)
                return SemaError::raise(sema, DiagnosticId::sema_err_struct_circular_reference, var->nodeTypeRef.isValid() ? var->nodeTypeRef : var->nodeInitRef);
            if (varList)
                return SemaError::raise(sema, DiagnosticId::sema_err_struct_circular_reference, varList->nodeTypeRef.isValid() ? varList->nodeTypeRef : varList->nodeInitRef);
        }

        if (var)
        {
            RESULT_VERIFY(sema.waitCompleted(&type, var->nodeTypeRef.isValid() ? var->nodeTypeRef : var->nodeInitRef));
        }

        if (varList)
        {
            RESULT_VERIFY(sema.waitCompleted(&type, varList->nodeTypeRef.isValid() ? varList->nodeTypeRef : varList->nodeInitRef));
        }
    }

    return Result::Continue;
}

void SymbolStruct::computeLayout(Sema& sema)
{
    auto& ctx = sema.ctx();

    sizeInBytes_ = 0;
    alignment_   = 1;

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
