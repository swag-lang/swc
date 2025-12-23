#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstFile::semaPreNode(Sema& sema) const
{
    SymbolNamespace* fileNamespace = Symbol::make<SymbolNamespace>(sema.ctx(), this, IdentifierRef::invalid(), SymbolFlagsE::Zero);
    sema.semaInfo().setFileNamespace(*fileNamespace);
    sema.pushScope(SemaScopeFlagsE::TopLevel);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstFile::semaPostNode(Sema& sema)
{
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstNamespaceDecl::semaPreNode(Sema& sema) const
{
    auto& ctx = sema.ctx();

    SmallVector<TokenRef> namesRef;
    sema.ast().tokens(namesRef, spanNameRef);

    SymbolMap* symMap = SemaFrame::currentSymMap(sema);
    for (const auto& nameRef : namesRef)
    {
        const Token&        tok   = sema.token(srcViewRef(), nameRef);
        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), nameRef);
        sema.frame().pushNs(idRef);

        SymbolNamespace* ns  = ctx.compiler().allocate<SymbolNamespace>(ctx, nullptr, idRef, SymbolFlagsE::Zero);
        Symbol*          res = symMap->addSingleSymbol(ctx, ns);

        if (!res->is(SymbolKind::Namespace))
        {
            SWC_UNREACHABLE();
        }

        symMap = static_cast<SymbolMap*>(static_cast<SymbolNamespace*>(res));
    }

    sema.pushScope(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(symMap);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstNamespaceDecl::semaPostNode(Sema& sema) const
{
    SmallVector<TokenRef> namesRef;
    sema.ast().tokens(namesRef, spanNameRef);
    for (size_t i = 0; i < namesRef.size(); ++i)
        sema.frame().popNs();
    sema.popScope();
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
