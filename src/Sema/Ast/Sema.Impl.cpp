#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Match.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstImpl::semaPostDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeIdentRef)
        return Result::Continue;

    const SemaNodeView  identView(sema, nodeIdentRef);
    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), identView.node->srcViewRef(), identView.node->tokRef());
    SymbolImpl*         sym   = Symbol::make<SymbolImpl>(sema.ctx(), this, tokRef(), idRef, SymbolFlagsE::Zero);
    sema.setSymbol(sema.curNodeRef(), sym);

    sema.pushScope(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
    sema.curScope().setSymMap(sym);

    return Result::Continue;
}

Result AstImpl::semaPostDecl(Sema& sema)
{
    sema.popScope();
    return Result::Continue;
}

Result AstImpl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    SymbolImpl& symImpl = sema.symbolOf(sema.curNodeRef()).cast<SymbolImpl>();

    // After the first name
    if (childRef == nodeIdentRef)
    {
        const SemaNodeView identView(sema, nodeIdentRef);
        if (identView.symList.size() > 1)
            return SemaError::raiseAmbiguousSymbol(sema, identView.nodeRef, identView.symList);

        SWC_ASSERT(identView.sym);
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
        const SemaNodeView identView(sema, nodeForRef);
        if (identView.symList.size() > 1)
            return SemaError::raiseAmbiguousSymbol(sema, identView.nodeRef, identView.symList);

        SWC_ASSERT(identView.sym);
        if (!identView.sym->isStruct())
            return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeForRef);
        RESULT_VERIFY(identView.sym->cast<SymbolStruct>().addInterface(sema, symImpl));
    }

    // Before the body
    if ((childRef == nodeIdentRef && nodeForRef.isInvalid()) || childRef == nodeForRef)
    {
        auto frame = sema.frame();
        frame.setImpl(&symImpl);
        sema.pushFrame(frame);

        sema.pushScope(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
        sema.curScope().setSymMap(symImpl.asSymMap());
    }

    return Result::Continue;
}

Result AstImpl::semaPostNode(Sema& sema)
{
    sema.popScope();
    sema.popFrame();
    return Result::Continue;
}

SWC_END_NAMESPACE();
