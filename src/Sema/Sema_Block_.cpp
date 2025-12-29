#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
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

    const SourceView& srcView = ctx.compiler().srcView(srcViewRef());
    SymbolMap*        symMap  = SemaFrame::currentSymMap(sema);

    for (const auto& tokRef : namesRef)
    {
        if (!srcView.isRuntimeFile())
        {
            const Token& tok = srcView.token(tokRef);
            if (LangSpec::isReservedNamespace(tok.string(srcView)))
            {
                SemaError::raise(sema, DiagnosticId::sema_err_reserved_swag_ns, srcViewRef(), tokRef);
                return AstVisitStepResult::Stop;
            }
        }

        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokRef);
        sema.frame().pushNs(idRef);

        SymbolFlags      flags = SymbolFlagsE::Declared | SymbolFlagsE::Complete;
        SymbolNamespace* ns    = Symbol::make<SymbolNamespace>(ctx, srcViewRef(), tokRef, idRef, flags);
        Symbol*          res   = symMap->addSingleSymbol(ctx, ns);

        if (!res->isNamespace())
        {
            SemaError::raiseAlreadyDefined(sema, ns, res);
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
