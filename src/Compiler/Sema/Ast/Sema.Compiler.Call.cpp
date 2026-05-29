#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/RuntimeName.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isMacroFunction(const SymbolFunction* function)
    {
        return function && function->attributes().hasRtFlag(RtAttributeFlagsE::Macro);
    }

    bool isMacroInlineContext(const Sema& sema)
    {
        return isMacroFunction(SemaHelpers::effectiveInlinePayload(sema) ? SemaHelpers::effectiveInlinePayload(sema)->sourceFunction : nullptr);
    }

    Result reportCompilerFileError(Sema& sema, DiagnosticId id, AstNodeRef nodeRef, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = SemaError::build(sema, id, nodeRef);
        FileSystem::setDiagnosticPathAndBecause(diag, &sema.ctx(), path, because);
        diag.report(sema.ctx());
        return Result::Error;
    }

    bool isModuleSetupDirectiveContext(const Sema& sema)
    {
        const SourceFile* sourceFile = sema.file();
        return sema.compiler().isModuleSetupMode() &&
               sourceFile != nullptr &&
               sourceFile->hasFlag(FileFlagsE::Module);
    }

    Result ensureModuleSetupDirectiveContext(Sema& sema, AstNodeRef nodeRef)
    {
        if (isModuleSetupDirectiveContext(sema))
            return Result::Continue;

        return SemaError::raise(sema, DiagnosticId::sema_err_module_setup_only_directive, nodeRef, SemaError::ReportLocation::Token);
    }

    std::string_view compilerImportTokenValue(const SourceView& srcView, const TokenRef tokenRef)
    {
        if (tokenRef.isInvalid())
            return {};

        const std::string_view tokenValue = srcView.tokenString(tokenRef);
        if (tokenValue.size() >= 2)
            return tokenValue.substr(1, tokenValue.size() - 2);
        return tokenValue;
    }

    std::string_view moduleImportName(const Sema& sema, const AstCompilerImport& node)
    {
        return compilerImportTokenValue(sema.srcView(node.srcViewRef()), node.tokModuleNameRef);
    }

    std::string_view moduleImportLocation(const Sema& sema, const AstCompilerImport& node)
    {
        return compilerImportTokenValue(sema.srcView(node.srcViewRef()), node.tokLocationRef);
    }

    std::string_view moduleImportVersion(const Sema& sema, const AstCompilerImport& node)
    {
        return compilerImportTokenValue(sema.srcView(node.srcViewRef()), node.tokVersionRef);
    }

    std::string_view moduleImportLink(const Sema& sema, const AstCompilerImport& node)
    {
        return compilerImportTokenValue(sema.srcView(node.srcViewRef()), node.tokLinkRef);
    }

    Result reportInvalidImportConstraintValue(Sema& sema, const AstCompilerImport& node, const TokenRef tokenRef, std::string_view argName, std::string_view value, std::string_view allowedValues)
    {
        Diagnostic diag = SemaError::build(sema, DiagnosticId::sema_err_import_invalid_constraint_value, SourceCodeRef{node.srcViewRef(), tokenRef});
        diag.addArgument(Diagnostic::ARG_ARG, argName);
        diag.addArgument(Diagnostic::ARG_VALUE, value);
        diag.addArgument(Diagnostic::ARG_VALUES, allowedValues);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result resolveModuleImportLinkBackend(Sema& sema, const AstCompilerImport& node, Runtime::BuildCfgBackendKind& outBackendKind)
    {
        outBackendKind = Runtime::BuildCfgBackendKind::None;
        if (node.tokLinkRef.isInvalid())
            return Result::Continue;

        const std::string_view linkValue = moduleImportLink(sema, node);
        if (linkValue == backendKindName(Runtime::BuildCfgBackendKind::SharedLibrary).view())
        {
            outBackendKind = Runtime::BuildCfgBackendKind::SharedLibrary;
            return Result::Continue;
        }

        if (linkValue == backendKindName(Runtime::BuildCfgBackendKind::StaticLibrary).view())
        {
            outBackendKind = Runtime::BuildCfgBackendKind::StaticLibrary;
            return Result::Continue;
        }

        return reportInvalidImportConstraintValue(
            sema,
            node,
            node.tokLinkRef,
            Token::toName(TokenId::KwdLink),
            linkValue,
            std::format("{}|{}",
                        backendKindName(Runtime::BuildCfgBackendKind::SharedLibrary).view(),
                        backendKindName(Runtime::BuildCfgBackendKind::StaticLibrary).view()));
    }

    Result resolveCompilerIncludePath(Sema& sema, AstNodeRef nodeRef, std::string_view rawPath, fs::path& outPath)
    {
        fs::path includePath{std::string(rawPath)};
        if (includePath.is_relative())
        {
            const SourceFile* sourceFile = sema.file();
            if (sourceFile)
                includePath = sourceFile->path().parent_path() / includePath;
        }

        fs::path resolvedPath = includePath;
        Utf8     because;
        if (FileSystem::resolveExistingFile(resolvedPath, because) != Result::Continue)
            return reportCompilerFileError(sema, DiagnosticId::cmdline_err_invalid_file, nodeRef, resolvedPath, because);

        outPath = std::move(resolvedPath);
        return Result::Continue;
    }

    Result loadCompilerIncludeBytes(Sema& sema, AstNodeRef nodeRef, const fs::path& resolvedPath, std::vector<std::byte>& outBytes)
    {
        FileSystem::IoErrorInfo ioError;
        if (FileSystem::readBinaryFile(resolvedPath, outBytes, ioError) != Result::Continue)
        {
            const DiagnosticId diagId = ioError.problem == FileSystem::IoProblem::OpenRead ? DiagnosticId::io_err_open_file : DiagnosticId::io_err_read_file;
            return reportCompilerFileError(sema, diagId, nodeRef, resolvedPath, ioError.because);
        }

        return Result::Continue;
    }

    const SemaClone::ParamBinding* findInjectInlineBinding(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;

        const auto* inlinePayload = SemaHelpers::effectiveInlinePayload(sema);
        if (!inlinePayload)
            return nullptr;

        const auto* identifier = sema.node(nodeRef).safeCast<AstIdentifier>();
        if (!identifier)
            return nullptr;

        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), identifier->codeRef());
        for (const auto& binding : inlinePayload->argMappings)
        {
            if (binding.idRef == idRef)
                return &binding;
        }

        return nullptr;
    }

    AstNodeRef rawInjectedNodeRef(Sema& sema, AstNodeRef nodeRef)
    {
        if (const auto* binding = findInjectInlineBinding(sema, nodeRef); binding && binding->exprRef.isValid())
        {
            const AstNode& bindingNode = sema.node(binding->exprRef);
            if (bindingNode.is(AstNodeId::CompilerCodeExpr))
                return bindingNode.cast<AstCompilerCodeExpr>().nodeExprRef;
            if (bindingNode.is(AstNodeId::CompilerCodeBlock))
                return bindingNode.cast<AstCompilerCodeBlock>().nodeBodyRef;
            return binding->exprRef;
        }

        AstNodeRef       resultRef   = nodeRef;
        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isValid())
            resultRef = resolvedRef;

        const AstNode& resultNode = sema.node(resultRef);
        if (resultNode.is(AstNodeId::CompilerCodeExpr))
            return resultNode.cast<AstCompilerCodeExpr>().nodeExprRef;
        if (resultNode.is(AstNodeId::CompilerCodeBlock))
            return resultNode.cast<AstCompilerCodeBlock>().nodeBodyRef;

        return resultRef;
    }

    Result validateInjectArgument(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef rawRef = rawInjectedNodeRef(sema, nodeRef);
        if (rawRef != nodeRef)
            return Result::Continue;

        const TypeRef typeRef = sema.viewType(nodeRef).typeRef();
        if (typeRef.isValid() && sema.typeMgr().get(typeRef).isCodeBlock())
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_inject_requires_code, nodeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, typeRef.isValid() ? sema.typeMgr().get(typeRef).toName(sema.ctx()) : Utf8{"<unknown>"});
        diag.report(sema.ctx());
        return Result::Error;
    }

    AstNodeId injectReplacementNodeId(TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::KwdBreak:
                return AstNodeId::BreakStmt;
            case TokenId::KwdContinue:
                return AstNodeId::ContinueStmt;
            default:
                return AstNodeId::Invalid;
        }
    }

    void appendInjectReplacement(SmallVector<SemaClone::NodeReplacement>& outReplacements, AstNodeId nodeId, AstNodeRef replacementRef)
    {
        if (replacementRef.isInvalid())
            return;

        const bool topLevelBreakableOnly = nodeId == AstNodeId::BreakStmt || nodeId == AstNodeId::ContinueStmt;
        outReplacements.push_back({nodeId, replacementRef, topLevelBreakableOnly});
    }

    bool canResolveInjectDependencyIdentifier(const Sema& sema, const SourceCodeRef& codeRef)
    {
        if (!codeRef.isValid())
            return false;

        const SourceView& srcView = sema.srcView(codeRef.srcViewRef);
        if (codeRef.tokRef.get() >= srcView.tokens().size())
            return false;

        const Token& tok = srcView.token(codeRef.tokRef);
        return tok.byteStart + tok.byteLength <= srcView.stringView().size();
    }

    bool injectCloneDependsOnContext(Sema& sema, AstNodeRef nodeRef, std::span<const SemaClone::ParamBinding> bindings, std::span<const SemaClone::NodeReplacement> replacements)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(nodeRef);
        for (const auto& replacement : replacements)
        {
            if (replacement.nodeId == node.id())
                return true;
        }

        if (const auto* identifier = node.safeCast<AstIdentifier>())
        {
            IdentifierRef idRef = IdentifierRef::invalid();
            const auto    view  = SemaNodeView(sema, nodeRef, SemaNodeViewPartE::Symbol, SemaNodeViewResolveE::Stored);
            if (view.sym())
                idRef = view.sym()->idRef();
            else if (canResolveInjectDependencyIdentifier(sema, identifier->codeRef()))
                idRef = sema.idMgr().addIdentifier(sema.ctx(), identifier->codeRef());
            else
                return true;

            for (const auto& binding : bindings)
            {
                if (binding.idRef == idRef)
                    return true;
            }
        }

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (injectCloneDependsOnContext(sema, childRef, bindings, replacements))
                return true;
        }

        return false;
    }

    void appendInjectReplacements(Sema& sema, const AstCompilerInject& node, SmallVector<SemaClone::NodeReplacement>& outReplacements)
    {
        SmallVector<TokenRef>   replacementInstructionRefs;
        SmallVector<AstNodeRef> replacementNodeRefs;
        sema.ast().appendTokens(replacementInstructionRefs, node.spanReplaceInstructionRef);
        sema.ast().appendNodes(replacementNodeRefs, node.spanReplaceNodeRef);
        SWC_ASSERT(replacementInstructionRefs.size() == replacementNodeRefs.size());

        for (uint32_t i = 0; i < replacementInstructionRefs.size(); i++)
        {
            const TokenId   replacementId = sema.srcView(node.srcViewRef()).token(replacementInstructionRefs[i]).id;
            const AstNodeId nodeId        = injectReplacementNodeId(replacementId);
            SWC_ASSERT(nodeId != AstNodeId::Invalid);
            appendInjectReplacement(outReplacements, nodeId, replacementNodeRefs[i]);
        }
    }

    bool shouldPreResolveMacroInjectCallerIdentifier(const Sema& sema, AstNodeRef nodeRef, AstNodeRef parentRef)
    {
        if (nodeRef.isInvalid())
            return false;

        const auto* identifier = sema.node(nodeRef).safeCast<AstIdentifier>();
        if (!identifier || identifier->hasFlag(AstIdentifierFlagsE::PreResolvedSymbol) || !identifier->codeRef().isValid())
            return false;

        if (!parentRef.isValid())
            return true;

        const AstNode& parentNode = sema.node(parentRef);
        if (const auto* member = parentNode.safeCast<AstMemberAccessExpr>())
            return member->nodeRightRef != nodeRef;
        if (parentNode.is(AstNodeId::AutoMemberAccessExpr))
            return false;

        return true;
    }

    bool shouldSkipMacroInjectPreResolveChild(const AstNode& parentNode, AstNodeRef childRef)
    {
        if (const auto* closureExpr = parentNode.safeCast<AstClosureExpr>())
            return childRef == closureExpr->nodeBodyRef;

        if (const auto* functionExpr = parentNode.safeCast<AstFunctionExpr>())
            return childRef == functionExpr->nodeBodyRef;

        if (const auto* functionDecl = parentNode.safeCast<AstFunctionDecl>())
            return childRef == functionDecl->nodeBodyRef;

        return false;
    }

    bool isReadyMacroInjectPreResolveSymbol(const Symbol& symbol)
    {
        if (!symbol.isDeclared())
            return false;
        if (symbol.isFunction() && symbol.cast<SymbolFunction>().isGenericRoot())
            return true;
        if (symbol.isStruct() && symbol.cast<SymbolStruct>().isGenericRoot())
            return true;
        return symbol.isTyped();
    }

    Result preResolveMacroInjectCallerIdentifiers(Sema& sema, AstNodeRef nodeRef, const SemaInlinePayload& inlinePayload, AstNodeRef parentRef = AstNodeRef::invalid())
    {
        if (nodeRef.isInvalid() || !inlinePayload.callerScope)
            return Result::Continue;

        if (shouldPreResolveMacroInjectCallerIdentifier(sema, nodeRef, parentRef))
        {
            MatchContext lookUpCxt;
            lookUpCxt.codeRef                = sema.node(nodeRef).codeRef();
            lookUpCxt.noWaitOnEmpty          = true;
            lookUpCxt.noWaitOnPendingSymbols = true;

            const auto savedFrame = sema.frame();
            auto&      frame      = sema.frame();
            while (!frame.bindingVars().empty())
                frame.popBindingVar();
            while (!frame.bindingTypes().empty())
                frame.popBindingType();
            frame.setCurrentInlinePayload(inlinePayload.parentInlinePayload);
            frame.setInlineContextRootRef(AstNodeRef::invalid());
            frame.setLookupScope(inlinePayload.callerScope);
            frame.setLookupScopeOverrideNodes(nullptr);
            frame.setUpLookupScope(inlinePayload.callerScope);
            for (SymbolVariable* bindingVar : inlinePayload.callerBindingVars)
                frame.pushBindingVar(bindingVar);
            for (const TypeRef bindingType : inlinePayload.callerBindingTypes)
                frame.pushBindingType(bindingType);

            const IdentifierRef idRef       = SemaHelpers::resolveIdentifier(sema, sema.node(nodeRef).codeRef());
            const Result        matchResult = Match::match(sema, lookUpCxt, idRef);
            sema.frame()                    = savedFrame;
            if (matchResult == Result::Continue &&
                lookUpCxt.count() == 1 &&
                lookUpCxt.first() &&
                isReadyMacroInjectPreResolveSymbol(*lookUpCxt.first()))
            {
                sema.setSymbol(nodeRef, lookUpCxt.first());
                sema.node(nodeRef).cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::PreResolvedSymbol | AstIdentifierFlagsE::MacroInjectCallerBinding);
            }
        }

        SmallVector<AstNodeRef> children;
        const AstNode&          parentNode = sema.node(nodeRef);
        parentNode.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (shouldSkipMacroInjectPreResolveChild(parentNode, childRef))
                continue;
            SWC_RESULT(preResolveMacroInjectCallerIdentifiers(sema, childRef, inlinePayload, nodeRef));
        }

        return Result::Continue;
    }

    SemaLookupScopeOverrideNodes* makeLookupScopeOverrideNodes(Sema& sema, AstNodeRef rootRef)
    {
        SWC_ASSERT(rootRef.isValid());

        auto* payload = sema.compiler().allocate<SemaLookupScopeOverrideNodes>();
        payload->ast  = &sema.ast();

        // Macro-inject lookup overrides are bounded to the cloned subtree. Materialize
        // that node set once so later lookups do not need to rescan parent chains.
        SmallVector<AstNodeRef> pending;
        pending.push_back(rootRef);
        while (!pending.empty())
        {
            const AstNodeRef nodeRef = pending.back();
            pending.pop_back();
            if (!payload->nodeRefs.insert(nodeRef).second)
                continue;

            SmallVector<AstNodeRef> children;
            sema.node(nodeRef).collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
            {
                if (childRef.isValid())
                    pending.push_back(childRef);
            }
        }

        return payload;
    }

    Result substituteCompilerInject(Sema& sema, AstNodeRef ownerRef, AstNodeRef exprRef, std::span<const SemaClone::NodeReplacement> replacements = std::span<const SemaClone::NodeReplacement>{})
    {
        SWC_RESULT(validateInjectArgument(sema, exprRef));

        const AstNodeRef rawRef = rawInjectedNodeRef(sema, exprRef);
        if (rawRef.isInvalid())
            return Result::Error;

        std::span<const SemaClone::ParamBinding> bindings;
        const auto*                              inlinePayload = SemaHelpers::effectiveInlinePayload(sema);
        const bool                               isMixinInject = inlinePayload &&
                                   inlinePayload->sourceFunction &&
                                   inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
        const bool isMacroInject = inlinePayload &&
                                   inlinePayload->sourceFunction &&
                                   inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Macro);
        bool injectsVoidCode = false;
        if (const TypeRef exprTypeRef = sema.viewType(exprRef).typeRef(); exprTypeRef.isValid())
        {
            const TypeInfo& exprType = sema.typeMgr().get(exprTypeRef);
            injectsVoidCode          = exprType.isCodeBlock() && exprType.payloadTypeRef() == sema.typeMgr().typeVoid();
        }
        if (isMixinInject)
        {
            // Mixin code arguments are re-cloned during #inject, so keep the active
            // inline bindings alive for that clone to preserve access to mixin params.
            bindings = inlinePayload->argMappings.span();
        }

        AstNodeRef clonedRef                     = AstNodeRef::invalid();
        const bool preserveResolvedCallerSymbols = isMacroInject;
        if (sema.node(exprRef).is(AstNodeId::CompilerCodeExpr) &&
            !injectCloneDependsOnContext(sema, rawRef, bindings, replacements))
        {
            const SemaClone::CloneContext cloneContext{std::span<const SemaClone::ParamBinding>{}};
            if (preserveResolvedCallerSymbols)
                clonedRef = SemaClone::cloneAstPreservingResolvedIdentifierSymbols(sema, rawRef, cloneContext);
            else
                clonedRef = SemaClone::cloneAst(sema, rawRef, cloneContext);
        }
        else
        {
            const SemaClone::CloneContext cloneContext{bindings, replacements};
            if (preserveResolvedCallerSymbols)
                clonedRef = SemaClone::cloneAstPreservingResolvedIdentifierSymbols(sema, rawRef, cloneContext);
            else
                clonedRef = SemaClone::cloneAst(sema, rawRef, cloneContext);
        }
        if (clonedRef.isInvalid())
            return Result::Error;

        sema.setSubstitute(ownerRef, clonedRef);
        if (isMacroInject)
        {
            SWC_RESULT(preResolveMacroInjectCallerIdentifiers(sema, clonedRef, *inlinePayload));
            if (injectsVoidCode)
            {
                auto* inlineOverridePayload                = sema.compiler().allocate<SemaInlineContextOverride>();
                inlineOverridePayload->targetInlinePayload = inlinePayload->parentInlinePayload;
                sema.setInlineContextOverride(clonedRef, inlineOverridePayload);
            }

            auto       frame       = sema.frame();
            SemaScope* callerScope = inlinePayload->callerScope;
            SemaScope* injectScope = sema.lookupScope();
            // Caller aliases/bindings still come from the parent inline payload, but the
            // cloned #inject subtree is not structurally inside that original inline root.
            frame.setCurrentInlinePayload(inlinePayload->parentInlinePayload);
            frame.setInlineContextRootRef(AstNodeRef::invalid());
            frame.setLookupScope(injectScope ? injectScope : callerScope);
            frame.setLookupScopeOverrideNodes(makeLookupScopeOverrideNodes(sema, clonedRef));
            frame.setUpLookupScope(inlinePayload->upLookupScope ? inlinePayload->upLookupScope : callerScope);
            for (SymbolVariable* bindingVar : inlinePayload->callerBindingVars)
                frame.pushBindingVar(bindingVar);
            for (const TypeRef bindingType : inlinePayload->callerBindingTypes)
                frame.pushBindingType(bindingType);
            sema.pushFramePopOnPostNode(frame, clonedRef);
        }
        sema.restartCurrentNode(clonedRef);
        return Result::Continue;
    }

    bool tryGetCodeString(Sema& sema, AstNodeRef nodeRef, Utf8& outValue)
    {
        const AstNodeRef rawRef = rawInjectedNodeRef(sema, nodeRef);
        if (rawRef == nodeRef)
            return false;

        const SourceCodeRange codeRange = sema.node(rawRef).codeRangeWithChildren(sema.ctx(), sema.ast());
        if (!codeRange.srcView || !codeRange.len)
            return false;

        outValue = Utf8{codeRange.srcView->codeView(codeRange.offset, codeRange.len)};
        return true;
    }

    Result tryFoldCompilerTagConstExpr(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNode& node = sema.node(nodeRef);

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (childRef.isValid())
                SWC_RESULT(tryFoldCompilerTagConstExpr(sema, childRef));
        }

        if (!node.is(AstNodeId::CallExpr) &&
            !node.is(AstNodeId::AliasCallExpr) &&
            !node.is(AstNodeId::IntrinsicCallExpr))
            return Result::Continue;

        if (sema.viewConstant(nodeRef).hasConstant())
            return Result::Continue;

        const SemaNodeView symView(sema, nodeRef, SemaNodeViewPartE::Symbol);
        auto* const        calledFn = symView.sym() ? symView.sym()->safeCast<SymbolFunction>() : nullptr;
        if (!calledFn || !calledFn->attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
            return Result::Continue;

        SmallVector<ResolvedCallArgument> resolvedArgs;
        sema.appendResolvedCallArguments(nodeRef, resolvedArgs);
        return SemaJIT::tryRunConstCall(sema, *calledFn, nodeRef, resolvedArgs.span());
    }

    bool hasNonConstExprCall(Sema& sema, AstNodeRef nodeRef, AstNodeRef& outBadRef)
    {
        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::CallExpr) ||
            node.is(AstNodeId::AliasCallExpr) ||
            node.is(AstNodeId::IntrinsicCallExpr))
        {
            const SemaNodeView symView(sema, nodeRef, SemaNodeViewPartE::Symbol);
            const auto* const  calledFn = symView.sym() ? symView.sym()->safeCast<SymbolFunction>() : nullptr;
            if (!calledFn || !calledFn->attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
            {
                outBadRef = nodeRef;
                return true;
            }
        }

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (childRef.isValid() && hasNonConstExprCall(sema, childRef, outBadRef))
                return true;
        }

        return false;
    }

    Result requireCompilerTagConstExpr(Sema& sema, AstNodeRef nodeRef)
    {
        const SemaNodeView symView(sema, nodeRef, SemaNodeViewPartE::Symbol);
        const auto*        calledFn = symView.sym() ? symView.sym()->safeCast<SymbolFunction>() : nullptr;
        if (calledFn && !calledFn->attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
        {
            return SemaError::raiseExprNotConst(sema, nodeRef);
        }

        AstNodeRef badRef = AstNodeRef::invalid();
        if (!hasNonConstExprCall(sema, nodeRef, badRef))
            return Result::Continue;

        return SemaError::raiseExprNotConst(sema, badRef.isValid() ? badRef : nodeRef);
    }
}
namespace
{
    TypeRef compilerOperandTypeRefFromSymbol(const Symbol& symbol)
    {
        if (symbol.typeRef().isValid())
            return symbol.typeRef();

        if (const auto* alias = symbol.safeCast<SymbolAlias>())
        {
            if (alias->underlyingTypeRef().isValid())
                return alias->underlyingTypeRef();
            if (alias->aliasedSymbol() && alias->aliasedSymbol()->typeRef().isValid())
                return alias->aliasedSymbol()->typeRef();
        }

        return TypeRef::invalid();
    }

    void hydrateCompilerTypeOperandFromTypedSymbol(Sema& sema, SemaNodeView& view)
    {
        if (view.typeRef().isValid() || !view.nodeRef().isValid())
            return;

        SemaNodeView typeSymbolView(sema, view.nodeRef(), SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        if (!typeSymbolView.sym() || !typeSymbolView.sym()->isType())
            return;

        const TypeRef symbolTypeRef = compilerOperandTypeRefFromSymbol(*typeSymbolView.sym());
        if (!symbolTypeRef.isValid())
            return;

        sema.setType(typeSymbolView.nodeRef(), symbolTypeRef);
        view = SemaNodeView(sema, view.nodeRef(), SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
    }

    SymbolStruct* compilerGenericRootStructFromView(Sema& sema, const SemaNodeView& view)
    {
        if (view.sym() && view.sym()->isStruct())
        {
            auto& st = view.sym()->cast<SymbolStruct>();
            if (st.isGenericRoot() && !st.isGenericInstance())
                return &st;
        }

        TypeRef representedTypeRef = TypeRef::invalid();
        if (view.type() && view.type()->isTypeValue())
            representedTypeRef = view.type()->payloadTypeRef();
        else if (view.type())
        {
            representedTypeRef = view.type()->unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Alias);
            if (!representedTypeRef.isValid() && view.type()->isStruct())
                representedTypeRef = view.typeRef();
        }

        if (!representedTypeRef.isValid())
            return nullptr;

        Symbol* representedSym = sema.typeMgr().get(representedTypeRef).getSymbol();
        if (!representedSym || !representedSym->isStruct())
            return nullptr;

        auto& st = representedSym->cast<SymbolStruct>();
        if (!st.isGenericRoot() || st.isGenericInstance())
            return nullptr;

        return &st;
    }

    Result instantiateCompilerGenericTypeOperand(Sema& sema, SemaNodeView& view)
    {
        hydrateCompilerTypeOperandFromTypedSymbol(sema, view);

        auto* genericRoot = compilerGenericRootStructFromView(sema, view);
        if (!genericRoot)
            return Result::Continue;

        SymbolStruct* instance = nullptr;
        SWC_RESULT(SemaGeneric::instantiateStructFromContext(sema, *genericRoot, instance));
        if (!instance)
            return Result::Continue;

        const TypeRef specializedTypeRef = SemaHelpers::ensureStructTypeRef(sema, *instance);
        sema.setSymbol(view.nodeRef(), instance);
        if (specializedTypeRef.isValid())
            sema.setType(view.nodeRef(), specializedTypeRef);
        view.recompute(sema, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        return Result::Continue;
    }

    bool isUnresolvedGenericRootCompilerTypeOperand(Sema& sema, const SemaNodeView& view)
    {
        const SymbolStruct* genericRoot = compilerGenericRootStructFromView(sema, view);
        if (!genericRoot)
            return false;

        TypeRef unresolvedTypeRef = TypeRef::invalid();
        if (view.sym())
            unresolvedTypeRef = compilerOperandTypeRefFromSymbol(*view.sym());
        if (!unresolvedTypeRef.isValid())
            unresolvedTypeRef = genericRoot->typeRef();

        return !view.typeRef().isValid() || view.typeRef() == unresolvedTypeRef;
    }

    Result concretizeViewConstant(Sema& sema, SemaNodeView& view)
    {
        if (!view.cstRef().isValid())
            return Result::Continue;

        ConstantRef newCstRef;
        SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unknown));
        sema.setConstant(view.nodeRef(), newCstRef);
        view.recompute(sema, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        return Result::Continue;
    }

    Result specializeCompilerOperandConcreteTypeRef(Sema& sema, TypeRef& ioTypeRef)
    {
        if (!ioTypeRef.isValid())
            return Result::Continue;

        Symbol* symbol = sema.typeMgr().get(ioTypeRef).getSymbol();
        if (!symbol || !symbol->isStruct())
            return Result::Continue;

        auto& st = symbol->cast<SymbolStruct>();
        if (!st.isGenericRoot() || st.isGenericInstance())
            return Result::Continue;

        SymbolStruct* instance = nullptr;
        SWC_RESULT(SemaGeneric::instantiateStructFromContext(sema, st, instance));
        if (instance)
            ioTypeRef = instance->typeRef();

        return Result::Continue;
    }

    TypeRef constQualifiedArrayTypeRefFromResolvedType(Sema& sema, const TypeInfo& resolvedType)
    {
        TypeInfoFlags reflectedFlags = resolvedType.flags();
        reflectedFlags.add(TypeInfoFlagsE::Const);
        SmallVector<uint64_t> dims;
        for (const uint64_t dim : resolvedType.payloadArrayDims())
            dims.push_back(dim);
        return sema.typeMgr().addType(TypeInfo::makeArray(dims, resolvedType.payloadArrayElemTypeRef(), reflectedFlags));
    }

    TypeRef preserveTopLevelConstForReflectedAggregateLiteral(Sema& sema, TypeRef originalTypeRef, TypeRef resolvedTypeRef)
    {
        if (!originalTypeRef.isValid() || !resolvedTypeRef.isValid())
            return resolvedTypeRef;

        const TypeInfo& originalType = sema.typeMgr().get(originalTypeRef);
        if (!originalType.isConst())
            return resolvedTypeRef;

        const TypeInfo& resolvedType = sema.typeMgr().get(resolvedTypeRef);
        if (resolvedType.isConst() || !resolvedType.isArray())
            return resolvedTypeRef;
        return constQualifiedArrayTypeRefFromResolvedType(sema, resolvedType);
    }

    TypeRef reflectedCompilerValueTypeRef(Sema& sema, TypeRef originalTypeRef, ConstantRef cstRef)
    {
        const TypeRef resolvedTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(sema, originalTypeRef, cstRef);
        return preserveTopLevelConstForReflectedAggregateLiteral(sema, originalTypeRef, resolvedTypeRef);
    }

    Result resolveCompilerOperandConcreteType(Sema& sema, SemaNodeView& view, AstNodeRef childRef, TypeRef& outTypeRef)
    {
        hydrateCompilerTypeOperandFromTypedSymbol(sema, view);

        if (!view.typeRef().isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, childRef);

        SWC_RESULT(concretizeViewConstant(sema, view));

        const TypeRef              viewTypeRef = view.typeRef();
        const ConstantRef          viewCstRef  = view.cstRef();
        const TypeInfo* const      viewType    = view.type();
        const ConstantValue* const viewCst     = view.cst();
        SWC_ASSERT(viewType != nullptr);
        SWC_ASSERT(!viewCstRef.isValid() || viewCst != nullptr);

        outTypeRef            = viewTypeRef;
        const bool isTypeLike = viewType->isTypeValue() || viewType->isAnyTypeInfo(sema.ctx()) || sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), viewTypeRef);
        if (isTypeLike)
        {
            outTypeRef = SemaHelpers::resolveRepresentedTypeRef(sema, view);
            if (!outTypeRef.isValid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, childRef);
            SWC_RESULT(specializeCompilerOperandConcreteTypeRef(sema, outTypeRef));
            return Result::Continue;
        }

        if (viewCstRef.isValid())
            outTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(sema, outTypeRef, viewCstRef);

        SWC_RESULT(specializeCompilerOperandConcreteTypeRef(sema, outTypeRef));
        return Result::Continue;
    }

    const SymbolStruct* compilerOffsetOwnerStruct(const SymbolVariable& symVar)
    {
        const SymbolMap* owner = symVar.ownerSymMap();
        while (owner)
        {
            if (owner->isStruct())
                return &owner->cast<SymbolStruct>();
            owner = owner->ownerSymMap();
        }

        return nullptr;
    }

    void assertConcreteStructCompilerSizeOperand(const TypeInfo& typeInfo)
    {
        if (!typeInfo.isStruct())
            return;

        const auto& symStruct = typeInfo.payloadSymStruct();
        if (!symStruct.isGenericRoot() || symStruct.isGenericInstance())
            return;

#if SWC_DEV_MODE
        Utf8 detail;
        detail += std::format("  structPtr={} semaCompleted={} typed={} declared={} genericRoot={} genericInstance={} union={} fields={} declNodeRef={}\n",
                              static_cast<const void*>(&symStruct),
                              symStruct.isSemaCompleted(),
                              symStruct.isTyped(),
                              symStruct.isDeclared(),
                              symStruct.isGenericRoot(),
                              symStruct.isGenericInstance(),
                              symStruct.isUnion(),
                              symStruct.fields().size(),
                              symStruct.declNodeRef().get());
        swcAssertDetail("compiler #sizeof/#alignof operand must be a concrete struct instance", __FILE__, __LINE__, detail.view());
#endif

        SWC_ASSERT(!symStruct.isGenericRoot() || symStruct.isGenericInstance());
    }

    void assertConcreteStructCompilerSizeValue(const TypeInfo& typeInfo, const uint64_t value)
    {
        if (!typeInfo.isStruct())
            return;

        const auto& symStruct = typeInfo.payloadSymStruct();
        if (symStruct.isGenericRoot() && !symStruct.isGenericInstance())
            return;

#if SWC_DEV_MODE
        if (!value)
        {
            Utf8 detail;
            detail += std::format("  structPtr={} semaCompleted={} typed={} declared={} genericRoot={} genericInstance={} union={} fields={} declNodeRef={}\n",
                                  static_cast<const void*>(&symStruct),
                                  symStruct.isSemaCompleted(),
                                  symStruct.isTyped(),
                                  symStruct.isDeclared(),
                                  symStruct.isGenericRoot(),
                                  symStruct.isGenericInstance(),
                                  symStruct.isUnion(),
                                  symStruct.fields().size(),
                                  symStruct.declNodeRef().get());
            swcAssertDetail("compiler #sizeof/#alignof concrete struct value must be non-zero", __FILE__, __LINE__, detail.view());
        }
#endif

        SWC_ASSERT(value != 0);
    }

    Result ensureCompilerOffsetOperandReady(Sema& sema, const SymbolVariable& symVar, AstNodeRef childRef)
    {
        const SymbolStruct* ownerStruct = compilerOffsetOwnerStruct(symVar);
        if (!ownerStruct)
            return Result::Continue;

        if (ownerStruct->isGenericRoot() && !ownerStruct->isGenericInstance())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_offsetof, childRef);

        SWC_RESULT(sema.waitSemaCompleted(ownerStruct, sema.node(childRef).codeRef()));

#if SWC_DEV_MODE
        if (!ownerStruct->hasConcreteLayout())
        {
            Utf8 detail;
            detail += std::format("  structPtr={} semaCompleted={} typed={} declared={} genericRoot={} genericInstance={} union={} fields={} declNodeRef={}\n",
                                  static_cast<const void*>(ownerStruct),
                                  ownerStruct->isSemaCompleted(),
                                  ownerStruct->isTyped(),
                                  ownerStruct->isDeclared(),
                                  ownerStruct->isGenericRoot(),
                                  ownerStruct->isGenericInstance(),
                                  ownerStruct->isUnion(),
                                  ownerStruct->fields().size(),
                                  ownerStruct->declNodeRef().get());
            swcAssertDetail("compiler #offsetof owner struct must have a concrete layout", __FILE__, __LINE__, detail.view());
        }
#endif

        if (!ownerStruct->hasConcreteLayout())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_offsetof, childRef);

        return Result::Continue;
    }

    Result semaCompilerTypeOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        const AstNode&   child    = sema.node(childRef);
        SemaNodeView     view     = sema.viewTypeConstant(childRef);
        SWC_ASSERT(view.typeRef().isValid());

        SWC_RESULT(concretizeViewConstant(sema, view));

        const TypeRef resolvedTypeRef = reflectedCompilerValueTypeRef(sema, view.typeRef(), view.cstRef());

        if (view.type() && view.type()->isTypeValue())
        {
            if (child.is(AstNodeId::CompilerTypeExpr))
            {
                const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), view.type()->payloadTypeRef()));
                sema.setConstant(sema.curNodeRef(), cstRef);
                return Result::Continue;
            }

            ConstantRef typeInfoCstRef = ConstantRef::invalid();
            SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, view.type()->payloadTypeRef(), view.nodeRef()));

            const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
            const ConstantRef    cstRef      = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), typeInfoCst.typeRef()));
            sema.setConstant(sema.curNodeRef(), cstRef);
            return Result::Continue;
        }

        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), resolvedTypeRef));
        sema.setConstant(sema.curNodeRef(), cstRef);
        return Result::Continue;
    }

    Result semaCompilerKindOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     view     = sema.viewType(childRef);
        SWC_ASSERT(view.typeRef().isValid());

        const TypeRef   enumTypeRef = view.type()->unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Alias);
        const TypeInfo& enumType    = sema.typeMgr().get(enumTypeRef);
        if (enumType.isEnum())
        {
            const TypeRef     typeRef = enumType.payloadSymEnum().underlyingTypeRef();
            const ConstantRef cstRef  = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), typeRef));
            sema.setConstant(sema.curNodeRef(), cstRef);
            return Result::Continue;
        }

        return semaCompilerTypeOf(sema, node);
    }

    Result semaCompilerDeclType(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     view     = sema.viewTypeConstant(childRef);
        TypeRef          typeRef  = TypeRef::invalid();
        SWC_RESULT(resolveCompilerOperandConcreteType(sema, view, childRef, typeRef));

        sema.setType(sema.curNodeRef(), typeRef);
        return Result::Continue;
    }

    Result semaCompilerSizeOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     view(sema, childRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        SWC_RESULT(instantiateCompilerGenericTypeOperand(sema, view));
        if (isUnresolvedGenericRootCompilerTypeOperand(sema, view))
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_sizeof, childRef);
        if (!view.typeRef().isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_sizeof, childRef);
        TypeRef typeRef = TypeRef::invalid();
        SWC_RESULT(resolveCompilerOperandConcreteType(sema, view, childRef, typeRef));

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isStruct())
        {
            const auto& symStruct = typeInfo.payloadSymStruct();
            if (symStruct.isGenericRoot() && !symStruct.isGenericInstance())
                return SemaError::raise(sema, DiagnosticId::sema_err_invalid_sizeof, childRef);
        }

        assertConcreteStructCompilerSizeOperand(typeInfo);
        SWC_RESULT(sema.waitSemaCompleted(&typeInfo, childRef));
        const uint64_t sizeOf = typeInfo.sizeOf(sema.ctx());
        assertConcreteStructCompilerSizeValue(typeInfo, sizeOf);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), sizeOf));
        return Result::Continue;
    }

    Result semaCompilerOffsetOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     view(sema, childRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        SWC_RESULT(instantiateCompilerGenericTypeOperand(sema, view));
        if (!view.hasSymbol() && !view.hasType() && !view.hasConstant())
            return Result::Error;
        if (!view.sym() || !view.sym()->isVariable())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_offsetof, childRef);

        const SymbolVariable& symVar = view.sym()->cast<SymbolVariable>();
        SWC_RESULT(ensureCompilerOffsetOperandReady(sema, symVar, childRef));
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), symVar.offset()));
        return Result::Continue;
    }

    Result semaCompilerAlignOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     view(sema, childRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        SWC_RESULT(instantiateCompilerGenericTypeOperand(sema, view));
        if (isUnresolvedGenericRootCompilerTypeOperand(sema, view))
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_alignof, childRef);
        if (!view.typeRef().isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_alignof, childRef);
        TypeRef typeRef = TypeRef::invalid();
        SWC_RESULT(resolveCompilerOperandConcreteType(sema, view, childRef, typeRef));

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isStruct())
        {
            const auto& symStruct = typeInfo.payloadSymStruct();
            if (symStruct.isGenericRoot() && !symStruct.isGenericInstance())
                return SemaError::raise(sema, DiagnosticId::sema_err_invalid_alignof, childRef);
        }

        assertConcreteStructCompilerSizeOperand(typeInfo);
        SWC_RESULT(sema.waitSemaCompleted(&typeInfo, childRef));
        const uint64_t alignOf = typeInfo.alignOf(sema.ctx());
        assertConcreteStructCompilerSizeValue(typeInfo, alignOf);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), alignOf));
        return Result::Continue;
    }

    Result semaCompilerNameOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext& ctx        = sema.ctx();
        const AstNodeRef   childRef   = node.nodeArgRef;
        SemaNodeView       symbolView = sema.viewSymbol(childRef);
        if (symbolView.sym() && !symbolView.sym()->isType())
        {
            const std::string_view name  = symbolView.sym()->name(ctx);
            const ConstantValue    value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        SemaNodeView typeView = sema.viewTypeConstant(childRef);
        SWC_RESULT(SemaCheck::isValueOrType(sema, typeView));
        if (const TypeRef resolvedTypeRef = SemaHelpers::resolveRepresentedTypeRef(sema, typeView); resolvedTypeRef.isValid())
        {
            const Utf8          name  = sema.typeMgr().get(resolvedTypeRef).toName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        if (symbolView.sym() && symbolView.sym()->isType() && typeView.typeRef().isValid())
        {
            const Utf8          name  = sema.typeMgr().get(typeView.typeRef()).toName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        if (symbolView.sym())
        {
            const std::string_view name  = symbolView.sym()->name(ctx);
            const ConstantValue    value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_failed_nameof, childRef);
        if (typeView.typeRef().isValid())
            diag.addArgument(Diagnostic::ARG_TYPE, typeView.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result semaCompilerFullNameOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext& ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewSymbol(childRef);
        if (view.sym() && !view.sym()->isType())
        {
            const Utf8          name  = view.sym()->getFullScopedName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        SemaNodeView typedView = sema.viewTypeConstant(childRef);
        SWC_RESULT(SemaCheck::isValueOrType(sema, typedView));
        if (const TypeRef resolvedTypeRef = SemaHelpers::resolveRepresentedTypeRef(sema, typedView); resolvedTypeRef.isValid())
        {
            const Utf8          name  = sema.typeMgr().get(resolvedTypeRef).toFullName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        if (view.sym() && view.sym()->isType() && typedView.typeRef().isValid())
        {
            const Utf8          name  = sema.typeMgr().get(typedView.typeRef()).toFullName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        if (view.sym())
        {
            const Utf8          name  = view.sym()->getFullScopedName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        return semaCompilerNameOf(sema, node);
    }

    Result semaCompilerStringOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext& ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        Utf8               codeValue;
        if (tryGetCodeString(sema, childRef, codeValue))
        {
            const ConstantValue value = ConstantValue::makeString(ctx, codeValue);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        const SemaNodeView view = sema.viewConstant(childRef);

        if (view.cst())
        {
            const Utf8          name  = view.cst()->toString(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        return semaCompilerNameOf(sema, node);
    }

    Result semaCompilerDefined(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext& ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewSymbol(childRef);

        const bool          isDefined = view.sym() != nullptr || (view.hasSymbolList() && !view.symList().empty());
        const ConstantValue value     = ConstantValue::makeBool(ctx, isDefined);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
        return Result::Continue;
    }

    Result semaCompilerIsConstExpr(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext&  ctx      = sema.ctx();
        const AstNodeRef    childRef = node.nodeArgRef;
        const SemaNodeView  view     = sema.viewConstant(childRef);
        const bool          result   = view.hasConstant() || sema.isFoldedTypedConst(childRef);
        const ConstantValue value    = ConstantValue::makeBool(ctx, result);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
        return Result::Continue;
    }

    Result semaCompilerSafety(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext& ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        SWC_RESULT(SemaCheck::isConstant(sema, childRef));

        const SemaNodeView view = sema.viewConstant(childRef);
        SWC_ASSERT(view.cst() != nullptr);

        const ConstantValue* constant = view.cst();
        if (constant->isEnumValue())
            constant = &sema.cstMgr().get(constant->getEnumValue());

        SWC_ASSERT(constant->isInt());
        SWC_ASSERT(constant->getInt().fits64());

        const auto          requestedSafety = static_cast<Runtime::SafetyWhat>(constant->getInt().asI64());
        const bool          enabled         = sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, requestedSafety);
        const ConstantValue value           = ConstantValue::makeBool(ctx, enabled);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
        return Result::Continue;
    }

    Result semaCompilerLocation(Sema& sema, const AstCompilerCallOne& node)
    {
        TypeRef typeRef = TypeRef::invalid();
        SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, node.codeRef()));

        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewSymbol(childRef);
        if (!view.sym())
        {
            auto          diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_location, childRef);
            const TypeRef ref  = sema.viewType(childRef).typeRef();
            if (ref.isValid())
                diag.addArgument(Diagnostic::ARG_TYPE, ref);
            diag.report(sema.ctx());
            return Result::Error;
        }

        const SourceCodeRange codeRange = view.sym()->codeRange(sema.ctx());
        ConstantRef           cstRef    = ConstantRef::invalid();
        SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(sema, cstRef, codeRange, view.sym()->safeCast<SymbolFunction>()));
        sema.setConstant(sema.curNodeRef(), cstRef);
        return Result::Continue;
    }

    Result semaCompilerForeignLib(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SWC_RESULT(SemaCheck::isConstant(sema, childRef));

        const SemaNodeView view = sema.viewConstant(childRef);
        SWC_ASSERT(view.cst());
        if (!view.cst()->isString())
            return SemaError::raiseInvalidType(sema, childRef, view.cst()->typeRef(), sema.typeMgr().typeString());

        sema.compiler().registerForeignLib(view.cst()->getString());
        return Result::Continue;
    }

    Result resolveCompilerTagName(Sema& sema, AstNodeRef nodeRef, std::string_view& outName)
    {
        outName = {};
        SWC_RESULT(tryFoldCompilerTagConstExpr(sema, nodeRef));
        SWC_RESULT(SemaCheck::isConstant(sema, nodeRef));
        SWC_RESULT(requireCompilerTagConstExpr(sema, nodeRef));

        const SemaNodeView view = sema.viewConstant(nodeRef);
        SWC_ASSERT(view.cst());
        if (!view.cst()->isString())
            return SemaError::raiseInvalidType(sema, nodeRef, view.cst()->typeRef(), sema.typeMgr().typeString());

        outName = view.cst()->getString();
        return Result::Continue;
    }

    Result resolveCompilerTagRequestedType(Sema& sema, AstNodeRef nodeRef, TypeRef& outTypeRef)
    {
        outTypeRef            = TypeRef::invalid();
        SemaNodeView typeView = sema.viewTypeConstant(nodeRef);
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, typeView));

        outTypeRef = SemaHelpers::resolveRepresentedTypeRef(sema, typeView);

        if (!outTypeRef.isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_not_type, nodeRef);
        return Result::Continue;
    }

    Result semaCompilerHasTag(Sema& sema, const AstCompilerCallOne& node)
    {
        std::string_view tagName;
        SWC_RESULT(resolveCompilerTagName(sema, node.nodeArgRef, tagName));

        const bool hasTag = sema.compiler().findCompilerTag(tagName) != nullptr;
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(hasTag));
        return Result::Continue;
    }

    Result semaCompilerGetTag(Sema& sema, const AstCompilerCall& node)
    {
        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        if (children.size() != 3)
            return Result::Continue;

        const AstNodeRef nameRef         = children[0];
        const AstNodeRef typeNodeRef     = children[1];
        const AstNodeRef defaultValueRef = children[2];

        std::string_view tagName;
        SWC_RESULT(resolveCompilerTagName(sema, nameRef, tagName));

        TypeRef requestedTypeRef = TypeRef::invalid();
        SWC_RESULT(resolveCompilerTagRequestedType(sema, typeNodeRef, requestedTypeRef));

        SWC_RESULT(tryFoldCompilerTagConstExpr(sema, defaultValueRef));
        SWC_RESULT(SemaCheck::isConstant(sema, defaultValueRef));
        SWC_RESULT(requireCompilerTagConstExpr(sema, defaultValueRef));
        SemaNodeView defaultView = sema.viewNodeTypeConstant(defaultValueRef);
        SWC_ASSERT(defaultView.cstRef().isValid());
        SWC_RESULT(Cast::cast(sema, defaultView, requestedTypeRef, CastKind::Initialization));
        const ConstantRef typedDefaultRef = defaultView.cstRef();
        SWC_ASSERT(typedDefaultRef.isValid());

        if (const auto* tag = sema.compiler().findCompilerTag(tagName))
        {
            const TypeRef tagTypeRef = sema.cstMgr().get(tag->cstRef).typeRef();
            CastRequest   castRequest(CastKind::Implicit);
            castRequest.errorNodeRef = typeNodeRef;
            castRequest.setConstantFoldingSrc(tag->cstRef);
            const Result castResult = Cast::castAllowed(sema, castRequest, tagTypeRef, requestedTypeRef);
            if (castResult == Result::Pause)
                return Result::Pause;
            if (castResult != Result::Continue)
                return Cast::emitCastFailure(sema, castRequest.failure);

            sema.setConstant(sema.curNodeRef(), tag->cstRef);
            return Result::Continue;
        }

        sema.setConstant(sema.curNodeRef(), typedDefaultRef);
        return Result::Continue;
    }

    Result semaCompilerInclude(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext& ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        SWC_RESULT(SemaCheck::isConstant(sema, childRef));

        const SemaNodeView view = sema.viewConstant(childRef);
        SWC_ASSERT(view.cst());
        if (!view.cst()->isString())
            return SemaError::raiseInvalidType(sema, childRef, view.cst()->typeRef(), sema.typeMgr().typeString());

        fs::path               resolvedPath;
        std::vector<std::byte> bytes;
        SWC_RESULT(resolveCompilerIncludePath(sema, childRef, view.cst()->getString(), resolvedPath));
        SWC_RESULT(loadCompilerIncludeBytes(sema, childRef, resolvedPath, bytes));

        SmallVector4<uint64_t> dims;
        dims.push_back(bytes.size());
        const TypeRef       arrayTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), sema.typeMgr().typeU8()));
        const ConstantValue value        = ConstantValue::makeArray(ctx, arrayTypeRef, asByteSpan(bytes));
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
        return Result::Continue;
    }

    Result semaCompilerLoad(Sema& sema, const AstCompilerCallOne& node)
    {
        SWC_RESULT(ensureModuleSetupDirectiveContext(sema, sema.curNodeRef()));

        const AstNodeRef childRef = node.nodeArgRef;
        SWC_RESULT(SemaCheck::isConstant(sema, childRef));

        const SemaNodeView view = sema.viewConstant(childRef);
        SWC_ASSERT(view.cst());
        if (!view.cst()->isString())
            return SemaError::raiseInvalidType(sema, childRef, view.cst()->typeRef(), sema.typeMgr().typeString());

        fs::path resolvedPath;
        SWC_RESULT(resolveCompilerIncludePath(sema, childRef, view.cst()->getString(), resolvedPath));
        return sema.compiler().registerModuleSetupLoad(resolvedPath);
    }

    Result semaCompilerRunes(Sema& sema, const AstCompilerCallOne& node)
    {
        TaskContext&     ctx      = sema.ctx();
        const AstNodeRef childRef = node.nodeArgRef;
        SWC_RESULT(SemaCheck::isConstant(sema, childRef));

        const SemaNodeView view = sema.viewConstant(childRef);
        SWC_ASSERT(view.cst());
        if (!view.cst()->isString())
            return SemaError::raiseInvalidType(sema, childRef, view.cst()->typeRef(), sema.typeMgr().typeString());

        const std::string_view str = view.cst()->getString();
        std::vector<char32_t>  runes;
        runes.reserve(str.size());

        const auto* cur = reinterpret_cast<const char8_t*>(str.data());
        const auto* end = cur + str.size();
        while (cur < end)
        {
            const auto [next, cp, eat] = Utf8Helper::decodeOneChar(cur, end);
            if (!next)
            {
                // Keep constexpr conversion robust for any non-literal string payload by mirroring runtime UTF-8 decoding.
                runes.push_back(0xFFFD);
                ++cur;
                continue;
            }

            SWC_ASSERT(eat != 0);
            runes.push_back(cp);
            cur = next;
        }

        const ByteSpan      bytes = {reinterpret_cast<const std::byte*>(runes.data()), runes.size() * sizeof(char32_t)};
        const ConstantValue value = ConstantValue::makeSlice(ctx, sema.typeMgr().typeRune(), bytes, TypeInfoFlagsE::Const);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
        return Result::Continue;
    }
}

Result AstCompilerImport::semaPostNode(Sema& sema) const
{
    SWC_RESULT(ensureModuleSetupDirectiveContext(sema, sema.curNodeRef()));
    auto linkBackendKind = Runtime::BuildCfgBackendKind::None;
    SWC_RESULT(resolveModuleImportLinkBackend(sema, *this, linkBackendKind));
    return sema.compiler().registerModuleSetupImport(moduleImportName(sema, *this), moduleImportLocation(sema, *this), moduleImportVersion(sema, *this), linkBackendKind);
}

Result AstCompilerCallOne::semaPostNode(Sema& sema) const
{
    const Token& tok = sema.token(codeRef());
    switch (tok.id)
    {
        case TokenId::CompilerTypeOf:
            return semaCompilerTypeOf(sema, *this);
        case TokenId::CompilerKindOf:
            return semaCompilerKindOf(sema, *this);
        case TokenId::CompilerDeclType:
            return semaCompilerDeclType(sema, *this);
        case TokenId::CompilerNameOf:
            return semaCompilerNameOf(sema, *this);
        case TokenId::CompilerFullNameOf:
            return semaCompilerFullNameOf(sema, *this);
        case TokenId::CompilerStringOf:
            return semaCompilerStringOf(sema, *this);
        case TokenId::CompilerSizeOf:
            return semaCompilerSizeOf(sema, *this);
        case TokenId::CompilerOffsetOf:
            return semaCompilerOffsetOf(sema, *this);
        case TokenId::CompilerAlignOf:
            return semaCompilerAlignOf(sema, *this);
        case TokenId::CompilerDefined:
            return semaCompilerDefined(sema, *this);
        case TokenId::CompilerIsConstExpr:
            return semaCompilerIsConstExpr(sema, *this);
        case TokenId::CompilerSafety:
            return semaCompilerSafety(sema, *this);
        case TokenId::CompilerLocation:
            return semaCompilerLocation(sema, *this);
        case TokenId::CompilerForeignLib:
            return semaCompilerForeignLib(sema, *this);
        case TokenId::CompilerInclude:
            return semaCompilerInclude(sema, *this);
        case TokenId::CompilerInject:
            return substituteCompilerInject(sema, sema.curNodeRef(), nodeArgRef);
        case TokenId::CompilerHasTag:
            return semaCompilerHasTag(sema, *this);
        case TokenId::CompilerRunes:
            return semaCompilerRunes(sema, *this);

        case TokenId::CompilerLoad:
            return semaCompilerLoad(sema, *this);

        default:
            SWC_INTERNAL_ERROR();
    }
}

Result AstCompilerCallOne::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeArgRef)
        return Result::Continue;

    const Token& tok = sema.token(codeRef());
    if (tok.id == TokenId::CompilerForeignLib ||
        tok.id == TokenId::CompilerHasTag ||
        tok.id == TokenId::CompilerInclude ||
        tok.id == TokenId::CompilerLoad ||
        tok.id == TokenId::CompilerRunes ||
        tok.id == TokenId::CompilerDeclType)
        SemaHelpers::pushConstExprRequirement(sema, childRef);

    return Result::Continue;
}

Result AstCompilerMacro::semaPreNode(Sema& sema)
{
    if (isMacroInlineContext(sema))
        return Result::Continue;

    if (isMacroFunction(sema.currentFunction()))
        return Result::Continue;

    return SemaError::raise(sema, DiagnosticId::sema_err_macro_requires_macro_fn, sema.curNodeRef());
}

Result AstCompilerMacro::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    if (!isMacroInlineContext(sema))
        return Result::SkipChildren;

    auto& bodyNode = sema.node(childRef).cast<AstEmbeddedBlock>();
    bodyNode.addFlag(AstEmbeddedBlockFlagsE::CompilerMacroBody);

    auto* hiddenScope = sema.curScopePtr();
    auto* callerScope = sema.resolvedUpLookupScope();
    if (const auto* inlinePayload = SemaHelpers::effectiveInlinePayload(sema);
        inlinePayload &&
        inlinePayload->sourceFunction &&
        inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Macro) &&
        inlinePayload->callerScope)
    {
        callerScope = inlinePayload->callerScope;
    }

    auto* macroScope = sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);
    macroScope->setLookupParent(callerScope);

    auto frame = sema.frame();
    frame.setUpLookupScope(hiddenScope);
    sema.pushFramePopOnPostChild(frame, childRef);
    return Result::Continue;
}

Result AstCompilerInject::semaPreNodeChild(const Sema& sema, const AstNodeRef& childRef)
{
    const auto& node = sema.curNode().cast<AstCompilerInject>();
    return childRef == node.nodeExprRef ? Result::Continue : Result::SkipChildren;
}

Result AstCompilerInject::semaPostNode(Sema& sema) const
{
    SmallVector<SemaClone::NodeReplacement> replacements;
    appendInjectReplacements(sema, *this, replacements);
    return substituteCompilerInject(sema, sema.curNodeRef(), nodeExprRef, replacements.span());
}

Result AstCompilerCall::semaPostNode(Sema& sema) const
{
    const Token& tok = sema.token(codeRef());
    switch (tok.id)
    {
        case TokenId::CompilerGetTag:
            return semaCompilerGetTag(sema, *this);

        default:
            SWC_INTERNAL_ERROR();
    }
}

SWC_END_NAMESPACE();
