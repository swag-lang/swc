#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result AstFile::semaPreDecl(Sema& sema) const
{
    auto* fileNamespace = Symbol::make<SymbolNamespace>(sema.ctx(), this, tokRef(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
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

Result AstFile::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SWC_UNUSED(childRef);
    if (!sema.frame().globalCompilerIfEnabled())
        return Result::SkipChildren;
    return Result::Continue;
}

Result AstNamespaceDecl::pushNamespace(Sema& sema, const AstNode* node, SpanRef spanNameRef)
{
    TaskContext& ctx = sema.ctx();

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

        constexpr SymbolFlags flags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
        auto*                 ns    = Symbol::make<SymbolNamespace>(ctx, node, tokRef, idRef, flags);
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
        const SemaNodeView view = sema.viewSymbol(nodeRef);
        SWC_ASSERT(view.sym());
        SWC_ASSERT(view.sym()->isSymMap());
        SymbolMap* const usingSymMap = view.sym()->asSymMap();
        sema.curScope().addUsingSymMap(usingSymMap);

        // Qualified lookups (for example `Enum.Value`) do not walk transient lexical scopes,
        // so persist `using` imports on the owning symbol map as well.
        if (auto* const ownerSymMap = SemaFrame::currentSymMap(sema))
            ownerSymMap->addUsingSymMap(usingSymMap);
    }

    return Result::Continue;
}

Result AstParenExpr::semaPostNode(Sema& sema)
{
    const AstNodeRef resolvedExprRef = sema.viewZero(nodeExprRef).nodeRef();
    sema.inheritPayload(*this, resolvedExprRef);
    sema.copyResolvedCallArguments(sema.curNodeRef(), resolvedExprRef);
    return Result::Continue;
}

Result AstEmbeddedBlock::semaPreNode(Sema& sema)
{
    const auto& node = sema.curNode().cast<AstEmbeddedBlock>();
    if (node.hasFlag(AstEmbeddedBlockFlagsE::CompilerMacroBody))
        return Result::Continue;

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstDeferStmt::semaPreNode(Sema& sema)
{
    const auto& node = sema.curNode().cast<AstDeferStmt>();
    AstModifierFlags allowed = AstModifierFlagsE::Err | AstModifierFlagsE::NoErr;
    SWC_RESULT(SemaCheck::modifiers(sema, node, node.modifierFlags, allowed));

    if (node.modifierFlags.has(AstModifierFlagsE::Err) && node.modifierFlags.has(AstModifierFlagsE::NoErr))
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_modifier_unsupported, node.codeRef());
        diag.addArgument(Diagnostic::ARG_WHAT, "#err/#noerr");
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (node.modifierFlags.has(AstModifierFlagsE::Err) || node.modifierFlags.has(AstModifierFlagsE::NoErr))
        SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::IsErrContext, node.codeRef()));

    return Result::Continue;
}

Result AstNamedArgument::semaPostNode(Sema& sema)
{
    const AstNodeRef resolvedArgRef = sema.viewZero(nodeArgRef).nodeRef();
    sema.inheritPayload(*this, resolvedArgRef);
    sema.copyResolvedCallArguments(sema.curNodeRef(), resolvedArgRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
