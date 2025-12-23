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

        SymbolNamespace* ns = ctx.compiler().allocate<SymbolNamespace>(ctx, nullptr, idRef, SymbolFlagsE::Zero);
        symMap->addSingleSymbol(ctx, ns);
        symMap = ns;
    }

    sema.pushScope(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(symMap);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstNamespaceDecl::semaPostNode(Sema& sema)
{
    sema.popScope();
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
