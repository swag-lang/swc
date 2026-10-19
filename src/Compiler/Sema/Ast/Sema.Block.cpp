#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
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

    // Scripts and files reached by setup #load also compile as ordinary source.
    // Both may declare nested #import and #load directives. A module.swg belongs
    // entirely to the setup pass and never compiles as ordinary source.
    bool isModuleSetupStatedSourceFile(const Sema& sema)
    {
        const SourceFile* file = sema.file();
        if (!file)
            return false;
        if (file->hasFlag(FileFlagsE::SetupLoaded))
            return true;

        const CommandLine& cmdLine = sema.ctx().cmdLine();
        if (!cmdLine.scriptMode || cmdLine.moduleFilePath.empty())
            return false;

        return FileSystem::pathEquals(file->path(), cmdLine.moduleFilePath);
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
        if (!isModuleSetupStatedSourceFile(sema))
            return Result::Continue;

        // Split setup directives from ordinary source: the setup pass runs before
        // imports, while declarations such as using Core need the imported symbols.
        // Runtime bootstrap declarations must remain visible to setup #run blocks.
        const bool setupDirective = isScriptModuleSetupChild(sema, childRef);
        if (sema.compiler().isModuleSetupMode())
            return setupDirective ? Result::Continue : Result::SkipChildren;

        return setupDirective ? Result::SkipChildren : Result::Continue;
    }

    // Imported APIs and runtime files share the import root so scoped names and
    // runtime type identities stay consistent across modules. Creation must retain
    // Lib.Color rather than Importer.Lib.Color; lookup still uses the module
    // namespace to resolve builtins and sibling imports.
    SymbolMap* topLevelCreationSymMap(Sema& sema)
    {
        const SourceFile* file = sema.file();
        if (file && (file->isImportedApi() || file->isRuntime()))
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

    SmallVector<SymbolMap*> segmentSymMaps;
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

        SymbolFlags flags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
        if (sema.frame().currentAccess() == SymbolAccess::Private)
            flags.add(SymbolFlagsE::Private);

        auto*   ns  = Symbol::make<SymbolNamespace>(ctx, node, tokRef, idRef, flags);
        Symbol* res = symMap->addSingleSymbol(ctx, ns);

        if (!res->isNamespace())
        {
            SemaError::raiseAlreadyDefined(sema, ns, res);
            continue;
        }

        symMap = res->asSymMap();
        segmentSymMaps.push_back(symMap);
    }

    // One scope per segment, as nested blocks would open them: the body of 'namespace A.B' sees
    // what 'A' declares, exactly like the body of 'namespace A { namespace B {} }'. The last scope
    // is the namespace that receives the declarations.
    if (segmentSymMaps.empty())
        segmentSymMaps.push_back(symMap);

    const AstNodeRef popNodeRef = node->is(AstNodeId::CompilerGlobal) ? sema.visit().parentNodeRef(0) : AstNodeRef::invalid();
    for (SymbolMap* segmentSymMap : segmentSymMaps)
    {
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel, popNodeRef);
        sema.curScope().setSymMap(segmentSymMap);
    }

    return Result::Continue;
}

Result AstNamespaceDecl::popNamespace(Sema& sema, SpanRef spanNameRef)
{
    const size_t count = sema.ast().spanSize(spanNameRef);
    for (size_t i = 0; i < count; ++i)
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
    const auto nodes = sema.ast().nodeSpan(spanChildrenRef);
    for (auto chunk = nodes.chunksBegin(); chunk != nodes.chunksEnd(); ++chunk)
    {
        for (const AstNodeRef& nodeRef : std::span(static_cast<const AstNodeRef*>(chunk->ptr), chunk->count))
        {
            SymbolMap* usingSymMap = usingDeclChildSymMap(sema, nodeRef);
            SemaScope::addUsingSymMapIfMissing(sema.curScope(), usingSymMap);

            // Qualified lookups (for example `Enum.Value`) do not walk transient lexical scopes,
            // so persist `using` imports on the owning symbol map as well.
            SymbolMap* ownerSymMap = SemaFrame::currentSymMap(sema);

            // Runtime top-level usings form each module's prelude, including its
            // generated imported APIs. Unqualified lookup skips persisted usings
            // on the import root, so retain them on the module namespace instead.
            if (ownerSymMap && ownerSymMap == sema.compiler().importRootNamespace())
            {
                const SourceFile* file = sema.file();
                if (file && file->isRuntime())
                    ownerSymMap = &sema.moduleNamespace();
            }

            if (ownerSymMap)
            {
                const SourceFile* sourceFile = sema.file();

                const SymbolMap::SourceRevision sourceRevision{
                    .fileRef  = sourceFile ? sourceFile->ref() : FileRef::invalid(),
                    .revision = sourceFile ? sourceFile->revisionId() : 0,
                };

                ownerSymMap->addUsingSymMap(sema.ctx(), usingSymMap, sourceRevision);
            }
        }
    }

    return Result::Continue;
}

Result AstUsingDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SemaScope::addUsingSymMapIfMissing(sema.curScope(), usingDeclChildSymMap(sema, childRef));
    return Result::Continue;
}

Result AstParenExpr::semaPostNode(Sema& sema)
{
    const AstNodeRef resolvedExprRef = sema.resolvedNodeRef(nodeExprRef);
    sema.inheritPayload(*this, resolvedExprRef);
    sema.copyResolvedCallArguments(sema.curNodeRef(), resolvedExprRef);

    return Result::Continue;
}

Result AstFunctionBody::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SemaHelpers::scopeBindingsForStatement(sema);
    return Result::Continue;
}

Result AstFunctionBody::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SemaCheck::unreachableCode(sema, sema.curNodeRef(), childRef);
    return Result::Continue;
}

Result AstSwitchCaseBody::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SemaHelpers::scopeBindingsForStatement(sema);
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
            sema.pushFramePopOnPostNode(std::move(frame));

            return Result::Continue;
        }
    }

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstEmbeddedBlock::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    // An ordinary inline body must keep its standalone meaning, independent of
    // caller narrowing facts. Preserve those facts for the argument bindings,
    // then clear them at the first statement originating in the callee.
    const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
    if (inlinePayload &&
        inlinePayload->inlineRootRef == sema.curNodeRef() &&
        inlinePayload->narrowFactsBodyStartRef == childRef &&
        sema.frame().hasNarrowFacts())
    {
        SemaFrame frame = sema.frame();
        frame.clearNarrowFacts();
        sema.pushFramePopOnPostNode(std::move(frame), sema.curNodeRef());
    }

    SemaHelpers::scopeBindingsForStatement(sema);
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

    // A single deferred statement needs the same lexical lifetime as a braced body. In
    // particular, a catch capture belongs to this execution, not to the scope being unwound.
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);

    // A defer body runs at scope exit, not here: narrowing facts valid at the declaration
    // point may no longer hold when it executes, and what the body invalidates cannot reach
    // back to the statements written before that exit.
    {
        SemaFrame frame = sema.frame();
        frame.clearNarrowFacts();
        frame.setDeferBody();
        frame.setDeferOwner();

        // Control flow cannot leave a body that runs while its scope is already being left: the
        // loops, switches and named scopes around the 'defer' are out of reach from inside it.
        frame.setCurrentBreakContent(AstNodeRef::invalid(), SemaFrame::BreakContextKind::None);
        frame.setCurrentCompilerScope(AstNodeRef::invalid());
        frame.setCurrentNamedCompilerScope(nullptr);

        sema.pushFramePopOnPostNode(std::move(frame));
    }

    return Result::Continue;
}

Result AstNamedArgument::semaPostNode(Sema& sema)
{
    const AstNodeRef resolvedArgRef = sema.resolvedNodeRef(nodeArgRef);
    sema.inheritPayload(*this, resolvedArgRef);
    sema.copyResolvedCallArguments(sema.curNodeRef(), resolvedArgRef);

    return Result::Continue;
}

SWC_END_NAMESPACE();
