#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/LookUpContext.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

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

    LookUpContext lookUpCxt;
    lookUpCxt.srcViewRef = nodeIdent.srcViewRef();
    lookUpCxt.tokRef     = nodeIdent.tokRef();

    RESULT_VERIFY(SemaMatch::match(sema, lookUpCxt, idRef));

    const auto sym = const_cast<Symbol*>(lookUpCxt.first());

    if (hasParserFlag(Enum))
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
    sema.pushScope(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
    sema.curScope().setSymMap(sym.asSymMap());
    return Result::Continue;
}

Result AstImpl::semaPostNode(Sema& sema)
{
    sema.popScope();
    return Result::Continue;
}

SWC_END_NAMESPACE();
