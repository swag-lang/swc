#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Main/CompilerInstance.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

Result AstFile::semaPreDecl(Sema& sema) const
{
    SymbolNamespace* fileNamespace = Symbol::make<SymbolNamespace>(sema.ctx(), this, tokRef(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    sema.semaInfo().setFileNamespace(*fileNamespace);
    sema.pushScope(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(&sema.semaInfo().moduleNamespace());
    return Result::Continue;
}

Result AstFile::semaPostDecl(Sema& sema)
{
    sema.popScope();
    return Result::Continue;
}

Result AstFile::semaPreNode(Sema& sema)
{
    sema.pushScope(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(&sema.semaInfo().moduleNamespace());
    return Result::Continue;
}

Result AstFile::semaPostNode(Sema& sema)
{
    sema.popScope();
    return Result::Continue;
}

Result AstNamespaceDecl::pushNamespace(Sema& sema, const AstNode* node, SpanRef spanNameRef)
{
    auto& ctx = sema.ctx();

    SmallVector<TokenRef> namesRef;
    sema.ast().tokens(namesRef, spanNameRef);

    const SourceView& srcView = ctx.compiler().srcView(node->srcViewRef());
    SymbolMap*        symMap  = SemaFrame::currentSymMap(sema);

    for (const auto& tokRef : namesRef)
    {
        if (!srcView.isRuntimeFile())
        {
            const Token& tok = srcView.token(tokRef);
            if (LangSpec::isReservedNamespace(tok.string(srcView)))
                return SemaError::raise(sema, DiagnosticId::sema_err_reserved_swag_ns, node->srcViewRef(), tokRef);
        }

        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), node->srcViewRef(), tokRef);
        sema.frame().pushNs(idRef);

        constexpr SymbolFlags flags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::Completed;
        SymbolNamespace*      ns    = Symbol::make<SymbolNamespace>(ctx, node, tokRef, idRef, flags);
        Symbol*               res   = symMap->addSingleSymbol(ctx, ns);

        if (!res->isNamespace())
        {
            SemaError::raiseAlreadyDefined(sema, ns, res);
            continue;
        }

        symMap = res->asSymMap();
    }

    sema.pushScope(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(symMap);

    return Result::Continue;
}

Result AstNamespaceDecl::popNamespace(Sema& sema, SpanRef spanNameRef)
{
    SmallVector<TokenRef> namesRef;
    sema.ast().tokens(namesRef, spanNameRef);
    for (size_t i = 0; i < namesRef.size(); ++i)
        sema.frame().popNs();
    sema.popScope();
    return Result::Continue;
}

Result AstNamespaceDecl::semaPreDecl(Sema& sema) const
{
    return pushNamespace(sema, this, spanNameRef);
}

Result AstNamespaceDecl::semaPostDecl(Sema& sema) const
{
    return popNamespace(sema, spanNameRef);
}

Result AstNamespaceDecl::semaPreNode(Sema& sema) const
{
    return semaPreDecl(sema);
}

Result AstNamespaceDecl::semaPostNode(Sema& sema) const
{
    return semaPostDecl(sema);
}

Result AstUsingDecl::semaPostNode(Sema& sema) const
{
    SmallVector<AstNodeRef> nodeRefs;
    sema.ast().nodes(nodeRefs, spanChildrenRef);
    for (const auto& nodeRef : nodeRefs)
    {
        if (!sema.hasSymbol(nodeRef))
            return SemaError::raiseInternal(sema, *this);
        Symbol& sym = sema.symbolOf(nodeRef);

        if (sym.isNamespace())
        {
            sema.curScope().addUsingSymMap(sym.asSymMap());
            continue;
        }
        
        return SemaError::raiseInternal(sema, *this);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE()
