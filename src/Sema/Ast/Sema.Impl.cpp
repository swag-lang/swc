#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Match.h"
#include "Sema/Symbol/MatchContext.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstImpl::semaPreDecl(Sema& sema) const
{
    auto&      ctx = sema.ctx();
    const auto sym = Symbol::make<SymbolImpl>(ctx, this, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    sema.setSymbol(sema.curNodeRef(), sym);

    return Result::Continue;
}

Result AstImpl::semaPostDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeIdentRef)
        return Result::Continue;

    SymbolMap* sym = sema.symbolOf(sema.curNodeRef()).asSymMap();
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
        Symbol& sym = sema.symbolOf(nodeIdentRef);
        if (hasFlag(AstImplFlagsE::Enum))
        {
            if (!sym.isEnum())
                return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_enum, nodeIdentRef);
            sym.cast<SymbolEnum>().addImpl(symImpl);
        }
        else if (nodeForRef.isInvalid())
        {
            if (!sym.isStruct())
                return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeIdentRef);
            sym.cast<SymbolStruct>().addImpl(symImpl);
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
        Symbol& sym = sema.symbolOf(nodeForRef);
        if (!sym.isStruct())
            return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeForRef);
        sym.cast<SymbolStruct>().addInterface(symImpl);
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
