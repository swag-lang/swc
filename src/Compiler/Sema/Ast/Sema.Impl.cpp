#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstImpl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIdentRef || childRef == nodeForRef)
        return Result::Continue;

    const SymbolImpl* symImpl = sema.frame().currentImpl();
    if (!symImpl || !symImpl->isForStruct())
        return Result::Continue;

    const SymbolStruct* symStruct = symImpl->symStruct();
    if (!symStruct || !symStruct->isGenericRoot())
        return Result::Continue;

    return Result::SkipChildren;
}

Result AstImpl::semaPostDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIdentRef)
    {
        const SemaNodeView identView{sema, nodeIdentRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Symbol};
        IdentifierRef      idRef = IdentifierRef::invalid();
        if (identView.hasSymbol())
            idRef = identView.sym()->idRef();
        else
            idRef = sema.idMgr().addIdentifier(sema.ctx(), identView.node()->codeRef());
        auto* sym = Symbol::make<SymbolImpl>(sema.ctx(), this, tokRef(), idRef, SymbolFlagsE::Zero);
        sema.setSymbol(sema.curNodeRef(), sym);
        if (identView.hasSymbol())
        {
            Symbol* const target = identView.sym();
            if (target->isStruct())
                sym->setSymStruct(&target->cast<SymbolStruct>());
            else if (target->isEnum())
                sym->setSymEnum(&target->cast<SymbolEnum>());
            else if (target->isInterface())
                sym->setSymInterface(&target->cast<SymbolInterface>());
        }

        // An `impl` block will be registered to its target (struct/enum/interface) only in the
        // second pass, once the name lookup has run. Track pending registrations so completion of
        // structs can't happen before all impls are attached.
        sema.compiler().incPendingImplRegistrations();

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
        sema.curScope().setSymMap(sym);
    }

    return Result::Continue;
}

Result AstImpl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    auto& symImpl = sema.curViewSymbol().sym()->cast<SymbolImpl>();

    // After the first name
    if (childRef == nodeIdentRef)
    {
        const SemaNodeView identView = sema.viewSymbol(nodeIdentRef);
        Symbol&            sym       = *(identView.sym());
        symImpl.setIdRef(sym.idRef());
        if (nodeForRef.isInvalid())
        {
            if (sym.isStruct())
                sym.cast<SymbolStruct>().addImpl(sema, symImpl);
            else if (sym.isEnum())
                sym.cast<SymbolEnum>().addImpl(sema, symImpl);
            else
                return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeIdentRef);
        }
        else
        {
            if (!sym.isInterface())
                return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_interface, nodeIdentRef);
            symImpl.setSymInterface(&sym.cast<SymbolInterface>());
        }

        if (nodeForRef.isValid())
            return Result::Continue;
    }

    // After the 'for' name, if defined
    if (childRef == nodeForRef)
    {
        const SemaNodeView identView = sema.viewType(nodeIdentRef);
        const SemaNodeView forView   = sema.viewSymbol(nodeForRef);
        if (!forView.sym()->isStruct())
            return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeForRef);

        SWC_RESULT(forView.sym()->cast<SymbolStruct>().addInterface(sema, symImpl));

        symImpl.addExtraFlag(SymbolImplFlagsE::ForInterface);
        symImpl.setTypeRef(identView.typeRef());
        symImpl.setDeclared(sema.ctx());
        symImpl.setTyped(sema.ctx());
    }

    // Before the body
    if ((childRef == nodeIdentRef && nodeForRef.isInvalid()) || childRef == nodeForRef)
    {
        // The target has been resolved and the impl has been attached at this point.
        // Only resolve pending registrations when there is no error.
        if (!symImpl.isPendingRegistrationResolved())
        {
            symImpl.setPendingRegistrationResolved();
            sema.compiler().decPendingImplRegistrations();
        }

        auto frame = sema.frame();
        frame.setCurrentImpl(&symImpl);
        sema.pushFramePopOnPostNode(frame);
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
        sema.curScope().setSymMap(symImpl.asSymMap());
    }

    return Result::Continue;
}

void AstImpl::semaErrorCleanup(Sema& sema, AstNodeRef nodeRef)
{
    const SemaNodeView view = sema.viewSymbol(nodeRef);
    if (!view.hasSymbol())
        return;
    auto& symImpl = view.sym()->cast<SymbolImpl>();
    if (!symImpl.isPendingRegistrationResolved())
    {
        symImpl.setPendingRegistrationResolved();
        sema.compiler().decPendingImplRegistrations();
    }
}

SWC_END_NAMESPACE();
