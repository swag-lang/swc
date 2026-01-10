#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Match.h"
#include "Sema/Symbol/MatchContext.h"
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

Result AstImpl::semaPreNode(Sema& sema) const
{
    const auto nodeIdent = sema.node(nodeIdentRef);
    const auto idRef     = sema.idMgr().addIdentifier(sema.ctx(), nodeIdent.srcViewRef(), nodeIdent.tokRef());

    MatchContext lookUpCxt;
    lookUpCxt.srcViewRef = nodeIdent.srcViewRef();
    lookUpCxt.tokRef     = nodeIdent.tokRef();

    RESULT_VERIFY(Match::match(sema, lookUpCxt, idRef));

    const auto sym = const_cast<Symbol*>(lookUpCxt.first());

    if (hasFlag(AstImplFlagsE::Enum))
    {
        if (!sym->isEnum())
            return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_enum, nodeIdentRef);
    }
    else if (nodeForRef.isInvalid())
    {
        if (!sym->isStruct())
            return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeIdentRef);
    }

    SymbolImpl& symImpl = sema.symbolOf(sema.curNodeRef()).cast<SymbolImpl>();
    if (sym->isStruct())
        sym->cast<SymbolStruct>().addImpl(symImpl);

    return Result::Continue;
}

Result AstImpl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeIdentRef)
        return Result::Continue;

    SymbolImpl& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolImpl>();

    auto frame = sema.frame();
    frame.setImpl(&sym);
    sema.pushFrame(frame);

    sema.pushScope(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
    sema.curScope().setSymMap(sym.asSymMap());
    return Result::Continue;
}

Result AstImpl::semaPostNode(Sema& sema)
{
    sema.popScope();
    sema.popFrame();
    return Result::Continue;
}

SWC_END_NAMESPACE();
