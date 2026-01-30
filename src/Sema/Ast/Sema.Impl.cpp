#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/Ast/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Match/Match.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstImpl::semaPostDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIdentRef)
    {
        const SemaNodeView  identView(sema, nodeIdentRef);
        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), identView.node->srcViewRef(), identView.node->tokRef());
        SymbolImpl*         sym   = Symbol::make<SymbolImpl>(sema.ctx(), this, tokRef(), idRef, SymbolFlagsE::Zero);
        sema.setSymbol(sema.curNodeRef(), sym);

        // An `impl` block will be registered to its target (struct/enum/interface) only in the
        // second pass, once name lookup has run. Track pending registrations so completion of
        // structs can't happen before all impls are attached.
        sema.compiler().incPendingImplRegistrations();

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
        sema.curScope().setSymMap(sym);
    }

    return Result::Continue;
}

Result AstImpl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    SymbolImpl& symImpl = sema.symbolOf(sema.curNodeRef()).cast<SymbolImpl>();

    // After the first name
    if (childRef == nodeIdentRef)
    {
        const SemaNodeView identView(sema, nodeIdentRef);
        if (!identView.sym)
            return SemaError::raiseInternal(sema, *identView.node);

        Symbol& sym = *identView.sym;
        if (hasFlag(AstImplFlagsE::Enum))
        {
            if (!sym.isEnum())
                return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_enum, nodeIdentRef);
            sym.cast<SymbolEnum>().addImpl(sema, symImpl);
        }
        else if (nodeForRef.isInvalid())
        {
            if (!sym.isStruct())
                return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeIdentRef);
            sym.cast<SymbolStruct>().addImpl(sema, symImpl);
        }
        else
        {
            if (!sym.isInterface())
                return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_interface, nodeIdentRef);
        }

        if (nodeForRef.isValid())
            return Result::Continue;
    }

    // After the 'for' name, if defined
    if (childRef == nodeForRef)
    {
        const SemaNodeView identView(sema, nodeIdentRef);
        const SemaNodeView forView(sema, nodeForRef);
        if (!forView.sym)
            return SemaError::raiseInternal(sema, *forView.node);
        if (!forView.sym->isStruct())
            return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeForRef);

        RESULT_VERIFY(forView.sym->cast<SymbolStruct>().addInterface(sema, symImpl));

        symImpl.setTypeRef(identView.typeRef);
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

SWC_END_NAMESPACE();
