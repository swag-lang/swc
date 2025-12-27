#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstFile::semaPreDecl(Sema& sema) const
{
    SymbolNamespace* fileNamespace = Symbol::make<SymbolNamespace>(sema.ctx(), srcViewRef(), tokRef(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    sema.semaInfo().setFileNamespace(*fileNamespace);
    sema.pushScope(SemaScopeFlagsE::TopLevel);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstFile::semaPostDecl(Sema& sema)
{
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstFile::semaPreNode(Sema& sema)
{
    sema.pushScope(SemaScopeFlagsE::TopLevel);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstFile::semaPostNode(Sema& sema)
{
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstNamespaceDecl::semaPreDecl(Sema& sema) const
{
    auto& ctx = sema.ctx();

    SmallVector<TokenRef> namesRef;
    sema.ast().tokens(namesRef, spanNameRef);

    SymbolMap* symMap = SemaFrame::currentSymMap(sema);
    for (const auto& tokRef : namesRef)
    {
        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokRef);
        sema.frame().pushNs(idRef);

        SymbolNamespace* ns  = Symbol::make<SymbolNamespace>(ctx, srcViewRef(), tokRef, idRef, SymbolFlagsE::Complete);
        Symbol*          res = symMap->addSingleSymbol(ctx, ns);

        if (!res->isNamespace())
        {
            SemaError::raiseSymbolAlreadyDefined(sema, ns, res);
            continue;
        }

        symMap = res->asSymMap();
    }

    sema.pushScope(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(symMap);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstNamespaceDecl::semaPostDecl(Sema& sema) const
{
    SmallVector<TokenRef> namesRef;
    sema.ast().tokens(namesRef, spanNameRef);
    for (size_t i = 0; i < namesRef.size(); ++i)
        sema.frame().popNs();
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstNamespaceDecl::semaPreNode(Sema& sema) const
{
    return semaPreDecl(sema);
}

AstVisitStepResult AstNamespaceDecl::semaPostNode(Sema& sema) const
{
    return semaPostDecl(sema);
}

SWC_END_NAMESPACE()
