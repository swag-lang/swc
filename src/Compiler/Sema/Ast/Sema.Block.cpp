#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isTransparentExpectBlock(Sema& sema)
    {
        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (parentRef.isInvalid())
            return false;

        const AstNode& parentNode = sema.node(parentRef);
        if (parentNode.isNot(AstNodeId::ErrorManagementStmt))
            return false;

        return sema.token(parentNode.codeRef()).id == TokenId::KwdExpect;
    }

    void addUsingSymMapToScope(SemaScope& scope, SymbolMap* usingSymMap)
    {
        SWC_ASSERT(usingSymMap != nullptr);
        for (const SymbolMap* existing : scope.usingSymMaps())
        {
            if (existing == usingSymMap)
                return;
        }

        scope.addUsingSymMap(usingSymMap);
    }

    bool isScriptModuleFile(const Sema& sema)
    {
        const CommandLine& cmdLine = sema.ctx().cmdLine();
        if (!cmdLine.scriptMode || cmdLine.moduleFilePath.empty())
            return false;

        const SourceFile* file = sema.file();
        return file != nullptr && FileSystem::pathEquals(file->path(), cmdLine.moduleFilePath);
    }

    bool isScriptModuleSetupChild(Sema& sema, const AstNodeRef childRef)
    {
        const AstNode& childNode = sema.node(childRef);
        switch (childNode.id())
        {
            case AstNodeId::CompilerImport:
                return true;

            case AstNodeId::CompilerCallOne:
                return sema.token(childNode.codeRef()).id == TokenId::CompilerLoad;

            case AstNodeId::CompilerFunc:
                return sema.token(childNode.codeRef()).id == TokenId::CompilerRun;

            default:
                return false;
        }
    }

    Result filterScriptModuleSetupChild(Sema& sema, const AstNodeRef childRef)
    {
        if (!isScriptModuleFile(sema))
            return Result::Continue;

        // The script file is both its module-setup file and its regular source file. Process
        // setup directives only during the setup pass, and everything else only during the
        // regular pass. Runtime bootstrap files still need full processing in the setup unit
        // so declarations such as `@compiler` remain visible to setup `#run` blocks.
        const bool setupDirective = isScriptModuleSetupChild(sema, childRef);
        if (sema.compiler().isModuleSetupMode())
            return setupDirective ? Result::Continue : Result::SkipChildren;
        return setupDirective ? Result::SkipChildren : Result::Continue;
    }

    // Top-level symbols of an imported-API file are created under the shared import-root namespace
    // (not this module's namespace), so an imported module keeps its own namespace hierarchy
    // (e.g. `Pixel.Color`) instead of being nested under the importer (`Importer.Pixel.Color`).
    // Lookup still uses the module namespace (so builtins like `Swag` and sibling imports resolve).
    SymbolMap* topLevelCreationSymMap(Sema& sema)
    {
        const SourceFile* file = sema.file();
        if (file && file->isImportedApi())
        {
            if (SymbolNamespace* importRoot = sema.compiler().importRootNamespace())
                return importRoot;
        }
        return &sema.moduleNamespace();
    }

    SymbolMap* usingDeclChildSymMap(Sema& sema, AstNodeRef nodeRef)
    {
        const SemaNodeView view = sema.viewSymbol(nodeRef);
        SWC_ASSERT(view.sym());
        SWC_ASSERT(view.sym()->isSymMap());
        return view.sym()->asSymMap();
    }
}

Result AstFile::semaPreDecl(Sema& sema) const
{
    auto* fileNamespace = Symbol::make<SymbolNamespace>(sema.ctx(), this, tokRef(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
    sema.setFileNamespace(*fileNamespace);
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(topLevelCreationSymMap(sema));
    return Result::Continue;
}

Result AstFile::semaPreDeclChild(Sema& sema, const AstNodeRef& childRef)
{
    return filterScriptModuleSetupChild(sema, childRef);
}

Result AstFile::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel);
    sema.curScope().setSymMap(topLevelCreationSymMap(sema));
    return Result::Continue;
}

Result AstFile::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SWC_RESULT(filterScriptModuleSetupChild(sema, childRef));
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
        SymbolMap* usingSymMap = usingDeclChildSymMap(sema, nodeRef);
        addUsingSymMapToScope(sema.curScope(), usingSymMap);

        // Qualified lookups (for example `Enum.Value`) do not walk transient lexical scopes,
        // so persist `using` imports on the owning symbol map as well.
        if (auto* ownerSymMap = SemaFrame::currentSymMap(sema))
            ownerSymMap->addUsingSymMap(usingSymMap);
    }

    return Result::Continue;
}

Result AstUsingDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    addUsingSymMapToScope(sema.curScope(), usingDeclChildSymMap(sema, childRef));
    return Result::Continue;
}

Result AstParenExpr::semaPostNode(Sema& sema)
{
    const AstNodeRef resolvedExprRef = sema.viewZero(nodeExprRef).nodeRef();
    sema.inheritPayload(*this, resolvedExprRef);
    sema.copyResolvedCallArguments(sema.curNodeRef(), resolvedExprRef);
    return Result::Continue;
}

Result AstFunctionBody::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SemaCheck::unreachableCode(sema, sema.curNodeRef(), childRef);
    return Result::Continue;
}

Result AstSwitchCaseBody::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SemaCheck::unreachableCode(sema, sema.curNodeRef(), childRef);
    return Result::Continue;
}

Result AstEmbeddedBlock::semaPreNode(Sema& sema)
{
    const auto& node = sema.curNode().cast<AstEmbeddedBlock>();
    if (isTransparentExpectBlock(sema))
        return Result::Continue;

    // A sema-synthesized '#inject' bindings block behaves like a '#macro' block:
    // its scope is parented to the caller so the injected code cannot see the
    // macro's internals, and the up-lookup scope (used by the binding
    // initializers) reaches back to the macro's own scope.
    if (node.hasFlag(AstEmbeddedBlockFlagsE::InjectBindings))
    {
        if (const auto* inlinePayload = sema.inlinePayload(sema.curNodeRef()); inlinePayload && inlinePayload->callerScope)
        {
            auto* hiddenScope  = sema.curScopePtr();
            auto* bindingScope = sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
            bindingScope->setLookupParent(inlinePayload->callerScope);

            auto frame = sema.frame();
            frame.setUpLookupScope(hiddenScope);
            sema.pushFramePopOnPostNode(frame);
            return Result::Continue;
        }
    }

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstEmbeddedBlock::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    // From the first callee-origin statement of an ordinary-inline root, drop the
    // caller's flow-narrowing facts: the body typechecked standalone and its meaning
    // must not depend on the call site (Auto inlining runs in release only). The
    // materialized argument bindings before that statement are caller code and were
    // sema'd with the facts still live.
    const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
    if (inlinePayload &&
        inlinePayload->inlineRootRef == sema.curNodeRef() &&
        inlinePayload->narrowFactsBodyStartRef == childRef &&
        sema.frame().hasNarrowFacts())
    {
        SemaFrame frame = sema.frame();
        frame.clearNarrowFacts();
        sema.pushFramePopOnPostNode(frame, sema.curNodeRef());
    }

    return Result::Continue;
}

Result AstEmbeddedBlock::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SemaCheck::unreachableCode(sema, sema.curNodeRef(), childRef);
    return Result::Continue;
}

Result AstDeferStmt::semaPreNode(Sema& sema)
{
    const auto&                node    = sema.curNode().cast<AstDeferStmt>();
    constexpr AstModifierFlags allowed = AstModifierFlagsE::Fail | AstModifierFlagsE::NoFail;
    SWC_RESULT(SemaCheck::modifiers(sema, node, node.modifierFlags, allowed));

    if (node.modifierFlags.has(AstModifierFlagsE::Fail) && node.modifierFlags.has(AstModifierFlagsE::NoFail))
        return SemaError::raise(sema, DiagnosticId::sema_err_defer_fail_conflict, sema.curNodeRef());

    if (node.modifierFlags.has(AstModifierFlagsE::Fail) || node.modifierFlags.has(AstModifierFlagsE::NoFail))
        SWC_RESULT(SemaHelpers::requireRuntimeErrorContextDependency(sema, node.codeRef()));

    // A defer body runs at scope exit, not here: narrowing facts valid at the declaration
    // point may no longer hold when it executes.
    if (sema.frame().hasNarrowFacts())
    {
        SemaFrame frame = sema.frame();
        frame.clearNarrowFacts();
        sema.pushFramePopOnPostNode(frame);
    }

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
