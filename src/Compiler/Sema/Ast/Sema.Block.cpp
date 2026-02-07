#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result AstFile::semaPreDecl(Sema& sema) const
{
    SymbolNamespace* fileNamespace = Symbol::make<SymbolNamespace>(sema.ctx(), this, tokRef(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    sema.setFileNamespace(*fileNamespace);
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(&sema.moduleNamespace());
    return Result::Continue;
}

Result AstFile::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(&sema.moduleNamespace());
    return Result::Continue;
}

Result AstNamespaceDecl::pushNamespace(Sema& sema, const AstNode* node, SpanRef spanNameRef)
{
    auto& ctx = sema.ctx();

    SmallVector<TokenRef> namesRef;
    sema.ast().appendTokens(namesRef, spanNameRef);

    const SourceView& srcView = ctx.compiler().srcView(node->srcViewRef());
    SymbolMap*        symMap  = SemaFrame::currentSymMap(sema);

    for (const auto& tokRef : namesRef)
    {
        if (!srcView.isRuntimeFile())
        {
            const Token& tok = srcView.token(tokRef);
            if (LangSpec::isReservedNamespace(tok.string(srcView)))
                return SemaError::raise(sema, DiagnosticId::sema_err_reserved_swag_ns, SourceCodeRef{node->srcViewRef(), tokRef});
        }

        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), {node->srcViewRef(), tokRef});
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

    if (node->is(AstNodeId::CompilerGlobal))
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel, sema.visit().parentNodeRef(0));
    else
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel);

    sema.curScope().setSymMap(symMap);
    return Result::Continue;
}

Result AstNamespaceDecl::popNamespace(Sema& sema, SpanRef spanNameRef)
{
    SmallVector<TokenRef> namesRef;
    sema.ast().appendTokens(namesRef, spanNameRef);
    for (size_t i = 0; i < namesRef.size(); ++i)
        sema.frame().popNs();
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
    sema.ast().appendNodes(nodeRefs, spanChildrenRef);
    for (const auto& nodeRef : nodeRefs)
    {
        const SemaNodeView nodeView(sema, nodeRef);
        SWC_ASSERT(nodeView.sym);
        SWC_ASSERT(nodeView.sym->isNamespace());
        sema.curScope().addUsingSymMap(nodeView.sym->asSymMap());
    }

    return Result::Continue;
}

Result AstParenExpr::semaPostNode(Sema& sema)
{
    sema.inheritSema(*this, nodeExprRef);
    return Result::Continue;
}

Result AstNamedArgument::semaPostNode(Sema& sema)
{
    sema.inheritSema(*this, nodeArgRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
