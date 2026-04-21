#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/Version.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    AstNodeRef compilerRunFunctionStorageRef(const AstNode& node)
    {
        if (const auto* runBlock = node.safeCast<AstCompilerRunBlock>())
            return runBlock->nodeBodyRef;
        return AstNodeRef::invalid();
    }

    bool isMacroFunction(const SymbolFunction* function)
    {
        return function && function->attributes().hasRtFlag(RtAttributeFlagsE::Macro);
    }

    bool isMacroInlineContext(const Sema& sema)
    {
        return isMacroFunction(sema.frame().currentInlinePayload() ? sema.frame().currentInlinePayload()->sourceFunction : nullptr);
    }

    bool isDirectFunctionParameterDefault(const Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;
        if (sema.isGlobalScope())
            return false;

        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (parentRef.isInvalid())
            return false;

        const AstNode& parentNode = sema.node(parentRef);
        if (const auto* singleVar = parentNode.safeCast<AstSingleVarDecl>())
            return singleVar->hasFlag(AstVarDeclFlagsE::Parameter) && singleVar->nodeInitRef == nodeRef;

        if (const auto* multiVar = parentNode.safeCast<AstMultiVarDecl>())
            return multiVar->hasFlag(AstVarDeclFlagsE::Parameter) && multiVar->nodeInitRef == nodeRef;

        return false;
    }

    AstNodeRef findNamedCompilerScope(Sema& sema, std::string_view scopeName)
    {
        for (size_t parentIndex = 0;; ++parentIndex)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                return AstNodeRef::invalid();

            const AstNode& parentNode = sema.ast().node(parentRef);
            if (parentNode.isNot(AstNodeId::CompilerScope))
                continue;

            const auto& scopeNode = parentNode.cast<AstCompilerScope>();
            if (scopeNode.tokNameRef.isInvalid())
                continue;

            const SourceCodeRef scopeCodeRef{scopeNode.srcViewRef(), scopeNode.tokNameRef};
            const Token&        scopeTok = sema.token(scopeCodeRef);
            if (scopeTok.string(sema.srcView(scopeCodeRef.srcViewRef)) == scopeName)
                return parentRef;
        }
    }

    constexpr Runtime::TargetOs nativeTargetOs()
    {
#ifdef _WIN32
        return Runtime::TargetOs::Windows;
#else
        return Runtime::TargetOs::Linux;
#endif
    }

    Result reportCompilerFileError(Sema& sema, DiagnosticId id, AstNodeRef nodeRef, const fs::path& path, const Utf8& because)
    {
        const FileRef fileRef = sema.srcView(sema.node(nodeRef).srcViewRef()).fileRef();
        Diagnostic    diag    = Diagnostic::get(id, fileRef);
        diag.last().addSpan(sema.node(nodeRef).codeRangeWithChildren(sema.ctx(), sema.ast()), "", DiagnosticSeverity::Error);
        SemaError::setReportArguments(sema, diag, nodeRef);
        FileSystem::setDiagnosticPathAndBecause(diag, &sema.ctx(), path, because);
        diag.report(sema.ctx());
        return Result::Error;
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

    AstNodeRef rawInjectedNodeRef(Sema& sema, AstNodeRef nodeRef)
    {
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

        outReplacements.push_back({nodeId, replacementRef});
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

    Result substituteCompilerInject(Sema& sema, AstNodeRef ownerRef, AstNodeRef exprRef, std::span<const SemaClone::NodeReplacement> replacements = std::span<const SemaClone::NodeReplacement>{})
    {
        SWC_RESULT(validateInjectArgument(sema, exprRef));

        const AstNodeRef rawRef = rawInjectedNodeRef(sema, exprRef);
        if (rawRef.isInvalid())
            return Result::Error;

        std::span<const SemaClone::ParamBinding> bindings;
        if (const auto* inlinePayload = sema.frame().currentInlinePayload();
            inlinePayload &&
            inlinePayload->sourceFunction &&
            inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        {
            // Mixin code arguments are re-cloned during #inject, so keep the active
            // inline bindings alive for that clone to preserve access to mixin params.
            bindings = inlinePayload->argMappings.span();
        }

        const SemaClone::CloneContext cloneContext{bindings, replacements};
        const AstNodeRef              clonedRef = SemaClone::cloneAst(sema, rawRef, cloneContext);
        if (clonedRef.isInvalid())
            return Result::Error;

        sema.setSubstitute(ownerRef, clonedRef);
        sema.visit().restartCurrentNode(clonedRef);
        return Result::Continue;
    }

    bool compilerAstStringType(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return false;

        const TypeRef unwrappedTypeRef = sema.typeMgr().get(typeRef).unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (!unwrappedTypeRef.isValid())
            return false;
        return sema.typeMgr().get(unwrappedTypeRef).isString();
    }

    fs::path compilerAstGeneratedDirectory(const Sema& sema)
    {
        if (!sema.ctx().cmdLine().workDir.empty())
            return sema.ctx().cmdLine().workDir;

        return Os::getTemporaryPath().lexically_normal();
    }

    std::string_view compilerAstLineEnding(const SourceView& srcView)
    {
        const std::string_view source = srcView.stringView();
        if (source.find("\r\n") != std::string_view::npos)
            return "\r\n";

        return "\n";
    }

    Utf8 compilerAstSourcePath(const SourceView& srcView)
    {
        if (const SourceFile* file = srcView.file())
            return Utf8{file->path().string()};

        return "<unknown>";
    }

    Utf8 buildCompilerAstGeneratedSection(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode, uint32_t& outCodeOffset)
    {
        const AstNode&         ownerNode    = sema.node(ownerRef);
        const SourceView&      ownerSrcView = sema.srcView(ownerNode.srcViewRef());
        const SourceCodeRange  codeRange    = ownerNode.codeRange(sema.ctx());
        const std::string_view eol          = compilerAstLineEnding(ownerSrcView);
        const Utf8             sourcePath   = compilerAstSourcePath(ownerSrcView);

        Utf8 section;
        section.reserve(sourcePath.size() + generatedCode.size() + 64);
        section += "// #ast source: ";
        section += sourcePath;
        section += eol;
        section += "// #ast line: ";
        section += std::to_string(codeRange.line);
        section += eol;

        outCodeOffset = static_cast<uint32_t>(section.size());
        section += generatedCode;
        if (!section.empty() && section.back() != '\n' && section.back() != '\r')
            section += eol;

        return section;
    }

    uint32_t compilerAstTokenStartOffset(const SourceView& srcView, const Token& token)
    {
        if (token.id == TokenId::Identifier)
            return srcView.identifiers()[token.byteStart].byteStart;

        return token.byteStart;
    }

    TokenRef findCompilerAstStartTokenRef(const SourceView& srcView, const uint32_t codeStartOffset)
    {
        const uint32_t numTokens = srcView.numTokens();
        if (!numTokens)
            return TokenRef::invalid();

        for (uint32_t i = 0; i < numTokens; i++)
        {
            const TokenRef tokRef(i);
            if (compilerAstTokenStartOffset(srcView, srcView.token(tokRef)) >= codeStartOffset)
                return tokRef;
        }

        return TokenRef(numTokens - 1);
    }

    ParserGeneratedMode compilerAstParseMode(const Sema& sema, AstNodeRef ownerRef)
    {
        auto parseModeForNodeId = [](const AstNodeId nodeId) {
            switch (nodeId)
            {
                case AstNodeId::AggregateBody:
                    return ParserGeneratedMode::Aggregate;

                case AstNodeId::EnumBody:
                    return ParserGeneratedMode::Enum;

                case AstNodeId::File:
                case AstNodeId::TopLevelBlock:
                    return ParserGeneratedMode::TopLevel;

                default:
                    return ParserGeneratedMode::Embedded;
            }
        };

        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (!parentRef.isValid())
            return ParserGeneratedMode::TopLevel;

        const AstNode& parentNode = sema.node(parentRef);
        if (parentNode.is(AstNodeId::AccessModifier))
        {
            const AstNodeRef grandParentRef = sema.visit().parentNodeRef(1);
            if (grandParentRef.isValid())
                return parseModeForNodeId(sema.node(grandParentRef).id());
        }

        SWC_UNUSED(ownerRef);
        return parseModeForNodeId(parentNode.id());
    }

    Result createCompilerAstGeneratedSource(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode, SourceView*& outSrcView, TokenRef& outStartTokRef)
    {
        outSrcView     = nullptr;
        outStartTokRef = TokenRef::invalid();

        uint32_t sectionCodeOffset = 0;
        const Utf8 sectionText = buildCompilerAstGeneratedSection(sema, ownerRef, generatedCode, sectionCodeOffset);
        const fs::path directory = compilerAstGeneratedDirectory(sema);

        CompilerInstance::GeneratedSourceAppendResult appendResult;
        Utf8                                          because;
        if (sema.compiler().appendGeneratedSource(appendResult, because, directory, sectionText.view(), sectionCodeOffset) != Result::Continue)
        {
            const fs::path errorPath = appendResult.path.empty() ? directory : appendResult.path;
            return reportCompilerFileError(sema, DiagnosticId::sema_err_ast_file_write_failed, ownerRef, errorPath, because);
        }

        sema.compiler().registerInMemoryFile(appendResult.path, appendResult.snapshot);
        SourceFile& sourceFile = sema.compiler().addFile(appendResult.path, FileFlagsE::CustomSrc | FileFlagsE::SkipFmt);
        SWC_RESULT(sourceFile.loadContent(sema.ctx()));

        SourceView& srcView = sourceFile.ast().srcView();
        if (const SourceFile* ownerFile = sema.file())
            srcView.setOwnerFileRef(ownerFile->ref());

        const uint64_t errorsBefore = Stats::getNumErrors();
        Lexer          lexer;
        lexer.tokenize(sema.ctx(), srcView, LexerFlagsE::Default);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;
        if (srcView.mustSkip())
            return Result::Error;

        outStartTokRef = findCompilerAstStartTokenRef(srcView, appendResult.codeStartOffset);
        outSrcView     = &srcView;
        return Result::Continue;
    }

    Result parseCompilerAstGenerated(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode, AstNodeRef& outGeneratedRef)
    {
        outGeneratedRef = AstNodeRef::invalid();

        SourceView* generatedSrcView = nullptr;
        TokenRef    generatedStartTokRef;
        SWC_RESULT(createCompilerAstGeneratedSource(sema, ownerRef, generatedCode, generatedSrcView, generatedStartTokRef));
        SWC_ASSERT(generatedSrcView != nullptr);
        if (!generatedSrcView)
            return Result::Error;

        const uint64_t errorsBefore = Stats::getNumErrors();
        Parser         parser;
        outGeneratedRef = parser.parseGenerated(sema.ctx(), sema.ast(), *generatedSrcView, compilerAstParseMode(sema, ownerRef), generatedStartTokRef);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;
        if (!outGeneratedRef.isValid())
            return Result::Error;

        return Result::Continue;
    }

    Result substituteCompilerAstString(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode)
    {
        AstNodeRef generatedRef = AstNodeRef::invalid();
        SWC_RESULT(parseCompilerAstGenerated(sema, ownerRef, generatedCode, generatedRef));
        sema.setSubstitute(ownerRef, generatedRef);
        sema.visit().restartCurrentNode(generatedRef);
        return Result::Continue;
    }

    Result requireCompilerAstStringResult(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef)
    {
        if (compilerAstStringType(sema, typeRef))
            return Result::Continue;

        const TypeRef reportedTypeRef = typeRef.isValid() ? typeRef : sema.typeMgr().typeVoid();
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_ast_requires_string, nodeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, sema.typeMgr().get(reportedTypeRef).toName(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
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

    Result castCompilerConditionToBool(Sema& sema, AstNodeRef nodeRef)
    {
        SWC_RESULT(SemaCheck::isConstant(sema, nodeRef));

        SemaNodeView view = sema.viewNodeTypeConstant(nodeRef);
        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));
        return Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr);
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
        if (const auto* const calledFn = symView.sym() ? symView.sym()->safeCast<SymbolFunction>() : nullptr;
            calledFn && !calledFn->attributes().hasRtFlag(RtAttributeFlagsE::ConstExpr))
        {
            return SemaError::raiseExprNotConst(sema, nodeRef);
        }

        AstNodeRef badRef = AstNodeRef::invalid();
        if (!hasNonConstExprCall(sema, nodeRef, badRef))
            return Result::Continue;

        return SemaError::raiseExprNotConst(sema, badRef.isValid() ? badRef : nodeRef);
    }
}

Result AstCompilerScope::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    SemaFrame frame = sema.frame();
    frame.setCurrentBreakContent(sema.curNodeRef(), SemaFrame::BreakContextKind::Scope);
    sema.pushFramePopOnPostChild(frame, childRef);
    return Result::Continue;
}

Result AstScopedBreakStmt::semaPreNode(Sema& sema)
{
    const auto&      node         = sema.curNode().cast<AstScopedBreakStmt>();
    const SourceCodeRef nameCodeRef{node.srcViewRef(), node.tokNameRef};
    const Token&        tokScopeName = sema.token(nameCodeRef);
    const AstNodeRef    scopeRef     = findNamedCompilerScope(sema, tokScopeName.string(sema.srcView(nameCodeRef.srcViewRef)));
    if (scopeRef.isValid())
        return Result::Continue;

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_unknown_scope_name, SourceCodeRef{node.srcViewRef(), node.tokNameRef});
    diag.addArgument(Diagnostic::ARG_SYM, tokScopeName.string(sema.srcView(nameCodeRef.srcViewRef)));
    diag.report(sema.ctx());
    return Result::Error;
}

Result AstCompilerCodeBlock::semaPreNodeChild(const Sema& sema, const AstNodeRef& childRef) const
{
    SWC_UNUSED(sema);
    return childRef == nodeBodyRef ? Result::SkipChildren : Result::Continue;
}

Result AstCompilerCodeBlock::semaPostNode(Sema& sema) const
{
    const TypeRef payload = this->payloadTypeRef.isValid() ? payloadTypeRef : sema.typeMgr().typeVoid();
    sema.setType(sema.curNodeRef(), sema.typeMgr().addType(TypeInfo::makeCodeBlock(payload)));
    sema.setIsValue(sema.curNodeRef());
    sema.unsetIsLValue(sema.curNodeRef());
    return Result::Continue;
}

Result AstCompilerCodeExpr::semaPreNodeChild(const Sema& sema, const AstNodeRef& childRef) const
{
    SWC_UNUSED(sema);
    return childRef == nodeExprRef ? Result::SkipChildren : Result::Continue;
}

Result AstCompilerCodeExpr::semaPostNode(Sema& sema) const
{
    const TypeRef payload = this->payloadTypeRef.isValid() ? payloadTypeRef : sema.typeMgr().typeAny();
    sema.setType(sema.curNodeRef(), sema.typeMgr().addType(TypeInfo::makeCodeBlock(payload)));
    sema.setIsValue(sema.curNodeRef());
    sema.unsetIsLValue(sema.curNodeRef());
    return Result::Continue;
}

Result AstCompilerExpression::semaPostNode(Sema& sema)
{
    SWC_RESULT(SemaCheck::isConstant(sema, nodeExprRef));
    sema.inheritPayload(*this, nodeExprRef);
    return Result::Continue;
}

Result AstCompilerExpression::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeExprRef)
        SemaHelpers::pushConstExprRequirement(sema, childRef);
    return Result::Continue;
}

Result AstCompilerIf::semaPreDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return Result::Continue;

    if (childRef == nodeIfBlockRef)
    {
        SemaFrame       frame    = sema.frame();
        SemaCompilerIf* parentIf = frame.currentCompilerIf();
        auto*           ifFrame  = sema.compiler().allocate<SemaCompilerIf>();
        ifFrame->parent          = parentIf;

        frame.setCurrentCompilerIf(ifFrame);
        sema.setSemaPayload(nodeIfBlockRef, ifFrame);
        sema.pushFramePopOnPostChild(frame, childRef);
        return Result::Continue;
    }

    SWC_ASSERT(childRef == nodeElseBlockRef);
    if (nodeElseBlockRef.isValid())
    {
        SemaFrame       frame     = sema.frame();
        SemaCompilerIf* parentIf  = frame.currentCompilerIf();
        auto*           elseFrame = sema.compiler().allocate<SemaCompilerIf>();
        elseFrame->parent         = parentIf;

        frame.setCurrentCompilerIf(elseFrame);
        sema.setSemaPayload(nodeElseBlockRef, elseFrame);
        sema.pushFramePopOnPostChild(frame, childRef);
    }

    return Result::Continue;
}

Result AstCompilerIf::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
    {
        SemaHelpers::pushConstExprRequirement(sema, childRef);
        return Result::Continue;
    }

    SWC_RESULT(castCompilerConditionToBool(sema, nodeConditionRef));

    const SemaNodeView condView = sema.viewConstant(nodeConditionRef);
    SWC_ASSERT(condView.cst() && condView.cst()->isBool());

    if (childRef == nodeIfBlockRef && !condView.cst()->getBool())
        return Result::SkipChildren;
    if (childRef == nodeElseBlockRef && condView.cst()->getBool())
        return Result::SkipChildren;

    return Result::Continue;
}

Result AstCompilerIf::semaPostNode(Sema& sema) const
{
    // Condition must already be a constant at this point
    const SemaNodeView condView = sema.viewConstant(nodeConditionRef);
    SWC_ASSERT(condView.hasConstant());
    SWC_ASSERT(condView.cst());
    const bool takenIfBranch = condView.cst()->getBool();

    // The block that will be ignored
    const AstNodeRef& ignoredBlockRef = takenIfBranch ? nodeElseBlockRef : nodeIfBlockRef;
    if (!ignoredBlockRef.isValid())
        return Result::Continue;

    // Retrieve the SemaCompilerIf payload
    if (sema.hasSemaPayload(ignoredBlockRef))
    {
        const SemaCompilerIf* ignoredIfData = sema.semaPayload<SemaCompilerIf>(ignoredBlockRef);
        if (!ignoredIfData)
            return Result::Continue;

        for (Symbol* sym : ignoredIfData->symbols)
            sym->setIgnored(sema.ctx());
    }

    return Result::Continue;
}

Result AstCompilerDiagnostic::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeArgRef)
        SemaHelpers::pushConstExprRequirement(sema, childRef);
    return Result::Continue;
}

Result AstCompilerDiagnostic::semaPostNode(Sema& sema) const
{
    const Token& tok = sema.token(codeRef());
    if (tok.id == TokenId::CompilerAssert)
        SWC_RESULT(castCompilerConditionToBool(sema, nodeArgRef));

    const SemaNodeView   argView  = sema.viewConstant(nodeArgRef);
    const ConstantValue& constant = *(argView.cst());
    SWC_ASSERT(argView.hasConstant());
    switch (tok.id)
    {
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
            if (!constant.isString())
                return SemaError::raiseInvalidType(sema, nodeArgRef, constant.typeRef(), sema.typeMgr().typeString());
            break;

        case TokenId::CompilerAssert:
            if (!constant.getBool())
                return SemaError::raise(sema, DiagnosticId::sema_err_compiler_assert, codeRef());
            break;

        default:
            break;
    }

    switch (tok.id)
    {
        case TokenId::CompilerError:
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_compiler_error, codeRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString());
            diag.report(sema.ctx());
            return Result::Error;
        }

        case TokenId::CompilerWarning:
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_warn_compiler_warning, codeRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString());
            diag.report(sema.ctx());
            return Result::Continue;
        }

        case TokenId::CompilerPrint:
        {
            const TaskContext& ctx = sema.ctx();
            ctx.global().logger().lock();
            Logger::print(ctx, constant.toString(ctx));
            Logger::print(ctx, "\n");
            ctx.global().logger().unlock();
            return Result::Continue;
        }

        case TokenId::CompilerAssert:
            if (!constant.getBool())
                return SemaError::raise(sema, DiagnosticId::sema_err_compiler_assert, codeRef());
            break;

        default:
            break;
    }

    return Result::Continue;
}

Result AstCompilerLiteral::semaPostNode(Sema& sema)
{
    const TaskContext& ctx     = sema.ctx();
    const Token&       tok     = sema.token(codeRef());
    const SourceView&  srcView = sema.srcView(codeRef().srcViewRef);

    switch (tok.id)
    {
        case TokenId::CompilerFile:
        {
            const SourceFile*      file     = srcView.file();
            const std::string_view nameView = sema.cstMgr().addString(ctx, file ? file->path().string() : "");
            const ConstantValue    val      = ConstantValue::makeString(ctx, nameView);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerLine:
        {
            const SourceCodeRange codeRange = tok.codeRange(ctx, srcView);
            const ConstantValue&  val       = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(codeRange.line), 0, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcVersion:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_VERSION), 0, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcRevision:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_REVISION), 0, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcBuildNum:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_BUILD_NUM), 0, TypeInfo::Sign::Unsigned);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerOs:
        {
            TypeRef typeRef = TypeRef::invalid();
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::TargetOs, typeRef, codeRef()));
            const ConstantRef   valueCst     = sema.cstMgr().addS32(ctx, static_cast<int32_t>(sema.ctx().cmdLine().targetOs));
            const ConstantValue enumValue    = ConstantValue::makeEnumValue(ctx, valueCst, typeRef);
            const ConstantRef   enumValueRef = sema.cstMgr().addConstant(ctx, enumValue);
            sema.setConstant(sema.curNodeRef(), enumValueRef);
            break;
        }

        case TokenId::CompilerCallerLocation:
        {
            TypeRef typeRef = TypeRef::invalid();
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, codeRef()));
            if (!isDirectFunctionParameterDefault(sema, sema.curNodeRef()))
                return SemaError::raise(sema, DiagnosticId::sema_err_caller_location_default_only, codeRef());
            sema.setType(sema.curNodeRef(), typeRef);
            sema.setIsValue(*this);
            break;
        }
        case TokenId::CompilerCurLocation:
        {
            TypeRef typeRef = TypeRef::invalid();
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, codeRef()));
            ConstantRef cstRef = ConstantRef::invalid();
            SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(sema, cstRef, *this, SemaHelpers::currentLocationFunction(sema)));
            sema.setConstant(sema.curNodeRef(), cstRef);
            break;
        }

        case TokenId::CompilerArch:
        {
            TypeRef typeRef = TypeRef::invalid();
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::TargetArch, typeRef, codeRef()));
            const ConstantRef   valueCst     = sema.cstMgr().addS32(ctx, static_cast<int32_t>(sema.ctx().cmdLine().targetArch));
            const ConstantValue enumValue    = ConstantValue::makeEnumValue(ctx, valueCst, typeRef);
            const ConstantRef   enumValueRef = sema.cstMgr().addConstant(ctx, enumValue);
            sema.setConstant(sema.curNodeRef(), enumValueRef);
            break;
        }

        case TokenId::CompilerCpu:
        {
            const ConstantValue value = ConstantValue::makeString(ctx, sema.ctx().cmdLine().targetCpu);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            break;
        }

        case TokenId::CompilerBuildCfg:
        {
            const ConstantValue value = ConstantValue::makeString(ctx, sema.ctx().cmdLine().buildCfg);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            break;
        }

        case TokenId::CompilerSwagOs:
        {
            TypeRef typeRef = TypeRef::invalid();
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::TargetOs, typeRef, codeRef()));
            const ConstantRef   valueCst     = sema.cstMgr().addS32(ctx, static_cast<int32_t>(nativeTargetOs()));
            const ConstantValue enumValue    = ConstantValue::makeEnumValue(ctx, valueCst, typeRef);
            const ConstantRef   enumValueRef = sema.cstMgr().addConstant(ctx, enumValue);
            sema.setConstant(sema.curNodeRef(), enumValueRef);
            break;
        }

        case TokenId::CompilerModule:
        case TokenId::CompilerScopeName:
            // TODO
            SWC_INTERNAL_ERROR();

        default:
            SWC_INTERNAL_ERROR();
    }

    return Result::Continue;
}

Result AstCompilerGlobal::semaPreDecl(Sema& sema) const
{
    switch (mode)
    {
        case Mode::Export:
        case Mode::AccessPublic:
            sema.frame().setCurrentAccess(SymbolAccess::Public);
            break;
        case Mode::AccessFilePrivate:
            sema.frame().setCurrentAccess(SymbolAccess::FilePrivate);
            break;
        case Mode::AccessModulePrivate:
            sema.frame().setCurrentAccess(SymbolAccess::ModulePrivate);
            break;
        case Mode::Namespace:
            return AstNamespaceDecl::pushNamespace(sema, this, spanNameRef);
        default:
            break;
    }

    return Result::Continue;
}

Result AstCompilerGlobal::semaPreNode(Sema& sema) const
{
    return semaPreDecl(sema);
}

Result AstCompilerGlobal::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (mode == Mode::CompilerIf && childRef == nodeModeRef)
        SemaHelpers::pushConstExprRequirement(sema, childRef);

    if (mode == Mode::AttributeList && childRef == nodeModeRef)
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Zero, childRef);
    return Result::Continue;
}

namespace
{
    Result semaCompilerGlobalIf(Sema& sema, const AstCompilerGlobal& node)
    {
        SWC_RESULT(castCompilerConditionToBool(sema, node.nodeModeRef));

        const SemaNodeView condView = sema.viewConstant(node.nodeModeRef);
        SWC_ASSERT(condView.cst() && condView.cst()->isBool());

        sema.frame().setGlobalCompilerIfEnabled(condView.cst()->getBool());
        return Result::SkipChildren;
    }
}

Result AstCompilerGlobal::semaPostNode(Sema& sema) const
{
    switch (mode)
    {
        case Mode::Skip:
        case Mode::Generated:
        case Mode::AttributeList:
            return Result::Continue;

        case Mode::CompilerIf:
            return semaCompilerGlobalIf(sema, *this);

        case Mode::Using:
        case Mode::SkipFmt:
            // TODO
            return Result::SkipChildren;

        default:
            break;
    }

    return Result::Continue;
}

namespace
{
    Result semaCompilerTypeOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        const AstNode&   child    = sema.node(childRef);
        SemaNodeView     view     = sema.viewTypeConstant(childRef);
        SWC_ASSERT(view.typeRef().isValid());

        if (view.cstRef().isValid())
        {
            ConstantRef newCstRef;
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unknown));
            sema.setConstant(view.nodeRef(), newCstRef);
            view.recompute(sema, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }

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

        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), view.typeRef()));
        sema.setConstant(sema.curNodeRef(), cstRef);
        return Result::Continue;
    }

    Result semaCompilerKindOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef childRef = node.nodeArgRef;
        SemaNodeView     view     = sema.viewType(childRef);
        SWC_ASSERT(view.typeRef().isValid());

        if (view.type()->isEnum())
        {
            const TypeRef     typeRef = view.type()->payloadSymEnum().underlyingTypeRef();
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
        if (!view.typeRef().isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, childRef);

        if (view.cstRef().isValid())
        {
            ConstantRef newCstRef;
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, view.nodeRef(), view.cstRef(), TypeInfo::Sign::Unknown));
            sema.setConstant(view.nodeRef(), newCstRef);
            view.recompute(sema, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }

        TypeRef typeRef = view.typeRef();
        if (view.type() && view.type()->isTypeValue())
            typeRef = view.type()->payloadTypeRef();
        else if (view.type() && view.type()->isAnyTypeInfo(sema.ctx()))
        {
            const TypeRef resolvedTypeRef = sema.cstMgr().makeTypeValue(sema, view.cstRef());
            if (!resolvedTypeRef.isValid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, childRef);
            typeRef = resolvedTypeRef;
        }

        sema.setType(sema.curNodeRef(), typeRef);
        return Result::Continue;
    }

    Result semaCompilerSizeOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewType(childRef);
        if (!view.type())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_sizeof, childRef);
        SWC_RESULT(sema.waitSemaCompleted(view.type(), childRef));

        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), view.type()->sizeOf(sema.ctx())));
        return Result::Continue;
    }

    Result semaCompilerOffsetOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewNodeTypeConstantSymbol(childRef);
        if (!view.hasSymbol() && !view.hasType() && !view.hasConstant())
            return Result::Error;
        if (!view.sym() || !view.sym()->isVariable())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_offsetof, childRef);

        const SymbolVariable& symVar = view.sym()->cast<SymbolVariable>();
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), symVar.offset()));
        return Result::Continue;
    }

    Result semaCompilerAlignOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewType(childRef);
        if (!view.type())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_alignof, childRef);
        SWC_RESULT(sema.waitSemaCompleted(view.type(), childRef));

        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), view.type()->alignOf(sema.ctx())));
        return Result::Continue;
    }

    Result semaCompilerNameOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext& ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        SemaNodeView       view     = sema.viewTypeSymbol(childRef);

        if (view.sym())
        {
            const std::string_view name  = view.sym()->name(ctx);
            const ConstantValue    value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        SWC_RESULT(SemaCheck::isValueOrType(sema, view));
        if (view.type() && view.type()->isTypeValue())
        {
            const Utf8          name  = sema.typeMgr().get(view.type()->payloadTypeRef()).toName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_failed_nameof, childRef);
        if (view.typeRef().isValid())
            diag.addArgument(Diagnostic::ARG_TYPE, view.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result semaCompilerFullNameOf(Sema& sema, const AstCompilerCallOne& node)
    {
        const TaskContext& ctx      = sema.ctx();
        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewSymbol(childRef);

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

        const bool          isDefined = view.sym() != nullptr;
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

        if (typeView.type() && typeView.type()->isTypeValue())
            outTypeRef = typeView.type()->payloadTypeRef();
        else if (typeView.cstRef().isValid())
            outTypeRef = sema.cstMgr().makeTypeValue(sema, typeView.cstRef());

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
            // TODO
            SWC_INTERNAL_ERROR();

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

Result AstCompilerShortFunc::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    if (sema.token(codeRef()).id == TokenId::CompilerAst)
        SemaHelpers::pushConstExprRequirement(sema, childRef);
    return Result::Continue;
}

Result AstCompilerShortFunc::semaPostNode(Sema& sema) const
{
    if (sema.token(codeRef()).id != TokenId::CompilerAst)
        return Result::Continue;

    SWC_RESULT(SemaCheck::isConstant(sema, nodeBodyRef));
    const SemaNodeView view = sema.viewTypeConstant(nodeBodyRef);
    SWC_RESULT(requireCompilerAstStringResult(sema, nodeBodyRef, view.typeRef()));
    if (!view.cst() || !view.cst()->isString())
        return Result::Error;

    return substituteCompilerAstString(sema, sema.curNodeRef(), view.cst()->getString());
}

Result AstCompilerFunc::semaPreDecl(Sema& sema)
{
    TaskContext& ctx                = sema.ctx();
    const Token& tok                = sema.token(codeRef());
    const bool   ignoreTestFunc     = tok.id == TokenId::CompilerFuncTest && !ctx.cmdLine().sourceDrivenTest;
    const bool   ignoreMainFunc     = tok.id == TokenId::CompilerFuncMain && (ctx.cmdLine().backendKind == Runtime::BuildCfgBackendKind::SharedLibrary ||
                                                                        ctx.cmdLine().backendKind == Runtime::BuildCfgBackendKind::StaticLibrary);
    const bool   ignoreCompilerFunc = ignoreTestFunc || ignoreMainFunc;

    if (tok.id == TokenId::CompilerFuncMain && !ignoreMainFunc)
    {
        if (!ctx.compiler().setMainFunc(this))
        {
            auto  diag = SemaError::report(sema, DiagnosticId::sema_err_already_defined, codeRef());
            auto& note = diag.addElement(DiagnosticId::sema_note_other_definition);
            note.setSeverity(DiagnosticSeverity::Note);
            const AstCompilerFunc* mainFunc = ctx.compiler().mainFunc();
            const SourceView&      srcView  = mainFunc->srcView(ctx);
            note.addSpan(srcView.tokenCodeRange(ctx, mainFunc->tokRef()));
            diag.report(ctx);
            return Result::Error;
        }
    }

    std::string_view name;
    switch (tok.id)
    {
        case TokenId::CompilerRun:
        case TokenId::CompilerAst:
            name = "run";
            break;
        case TokenId::CompilerFuncTest:
            name = "test";
            break;
        case TokenId::CompilerFuncInit:
            name = "init";
            break;
        case TokenId::CompilerFuncDrop:
            name = "drop";
            break;
        case TokenId::CompilerFuncMain:
            name = "main";
            break;
        case TokenId::CompilerFuncPreMain:
            name = "premain";
            break;
        case TokenId::CompilerFuncMessage:
            name = "message";
            break;
        default:
            name = "func";
            break;
    }

    auto& sym = SemaHelpers::registerUniqueSymbol<SymbolFunction>(sema, *this, name);
    sym.setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, sym));
    sym.setDeclNodeRef(sema.curNodeRef());
    if (ignoreCompilerFunc)
    {
        sym.setIgnored(ctx);
        sym.setDeclared(ctx);
        sym.setTyped(ctx);
        sym.setSemaCompleted(ctx);
    }
    return Result::SkipChildren;
}

Result AstCompilerFunc::semaPreNode(Sema& sema)
{
    const TokenId tokenId = sema.token(sema.curNode().codeRef()).id;
    if (sema.enteringState())
    {
        const AstNodeRef curNodeRef = sema.curNodeRef();
        if (!sema.viewSymbol(curNodeRef).hasSymbol())
            sema.curNode().cast<AstCompilerFunc>().semaPreDecl(sema);

        auto& declaredSym = sema.viewSymbol(curNodeRef).sym()->cast<SymbolFunction>();
        declaredSym.registerAttributes(sema);
        declaredSym.setDeclared(sema.ctx());
    }

    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isIgnored())
        return Result::SkipChildren;

    if (tokenId == TokenId::CompilerAst)
        sym.setReturnTypeRef(TypeRef::invalid());
    else
        sym.setReturnTypeRef(sema.typeMgr().typeVoid());

    auto frame                = sema.frame();
    frame.currentAttributes() = sym.attributes();
    frame.setCurrentFunction(&sym);

    sema.pushFramePopOnPostNode(frame);
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstCompilerFunc::semaPostNode(Sema& sema) const
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isIgnored())
        return Result::Continue;

    const TokenId tokenId = sema.token(codeRef()).id;
    if (tokenId == TokenId::CompilerAst)
    {
        SWC_RESULT(requireCompilerAstStringResult(sema, sema.curNodeRef(), sym.returnTypeRef()));
        sym.setTyped(sema.ctx());
        sym.setSemaCompleted(sema.ctx());
        SWC_RESULT(SemaJIT::runFunctionResult(sema, sym, sema.curNodeRef()));

        const SemaNodeView resultView = sema.viewConstant(sema.curNodeRef());
        SWC_ASSERT(resultView.cst() != nullptr && resultView.cst()->isString());
        if (!resultView.cst() || !resultView.cst()->isString())
            return Result::Error;

        return substituteCompilerAstString(sema, sema.curNodeRef(), resultView.cst()->getString());
    }

    sym.setSemaCompleted(sema.ctx());

    switch (tokenId)
    {
        case TokenId::CompilerFuncTest:
            sema.compiler().registerNativeTestFunction(&sym);
            break;
        case TokenId::CompilerFuncInit:
            sema.compiler().registerNativeInitFunction(&sym);
            break;
        case TokenId::CompilerFuncDrop:
            sema.compiler().registerNativeDropFunction(&sym);
            break;
        case TokenId::CompilerFuncMain:
            sema.compiler().registerNativeMainFunction(&sym);
            break;
        case TokenId::CompilerFuncPreMain:
            sema.compiler().registerNativePreMainFunction(&sym);
            break;
        default:
            break;
    }

    if (tokenId != TokenId::CompilerRun)
        return Result::Continue;

    return SemaJIT::runStatement(sema, sym, sema.curNodeRef());
}

namespace
{
    void finalizeCompilerRunFunction(TaskContext& ctx, SymbolFunction& symFn, TypeRef returnTypeRef)
    {
        SWC_ASSERT(returnTypeRef.isValid());
        symFn.setReturnTypeRef(returnTypeRef);
        symFn.setTyped(ctx);
        symFn.setSemaCompleted(ctx);
    }

    Result setupCompilerRunFunction(Sema& sema, TypeRef returnTypeRef)
    {
        const AstNodeRef nodeRef = sema.curNodeRef();
        const AstNode&   node    = sema.node(nodeRef);
        AstNodeRef       symRef  = compilerRunFunctionStorageRef(node);
        if (symRef.isInvalid())
            symRef = nodeRef;

        if (!sema.viewSymbol(symRef).hasSymbol())
        {
            TaskContext&        ctx   = sema.ctx();
            const IdentifierRef idRef = SemaHelpers::getUniqueIdentifier(sema, "__run_expr");

            auto* symFn = Symbol::make<SymbolFunction>(ctx, &node, node.tokRef(), idRef, sema.frame().flagsForCurrentAccess());
            symFn->setOwnerSymMap(SemaFrame::currentSymMap(sema));
            symFn->setDeclNodeRef(nodeRef);
            symFn->setReturnTypeRef(returnTypeRef);
            symFn->setAttributes(ctx, sema.frame().currentAttributes());
            symFn->setDeclared(ctx);
            sema.setSymbol(symRef, symFn);
        }

        SemaFrame frame = sema.frame();
        auto&     symFn = sema.viewSymbol(symRef).sym()->cast<SymbolFunction>();

        // `#run` lowers to a helper function that is executed during sema. The enclosing
        // runtime function must not keep it as a normal runtime call dependency, or JIT/native
        // test discovery will try to prepare a compile-time-only helper that never survives
        // into the final runtime dependency graph.

        frame.currentAttributes() = symFn.attributes();
        frame.setCurrentFunction(&symFn);
        frame.addContextFlag(SemaFrameContextFlagsE::RunExpr);
        sema.pushFramePopOnPostNode(frame);
        return Result::Continue;
    }
}

Result AstCompilerRunBlock::semaPreNode(Sema& sema)
{
    return setupCompilerRunFunction(sema, TypeRef::invalid());
}

Result AstCompilerRunBlock::semaPostNode(Sema& sema)
{
    const auto& node         = sema.curNode().cast<AstCompilerRunBlock>();
    auto*       runExprSymFn = sema.currentFunction();
    SWC_ASSERT(runExprSymFn != nullptr);

    const TypeRef returnTypeRef = runExprSymFn->returnTypeRef();
    if (!returnTypeRef.isValid() || sema.typeMgr().get(returnTypeRef).isVoid())
        return SemaError::raise(sema, DiagnosticId::sema_err_run_expr_void, sema.curNodeRef());

    sema.setType(sema.curNodeRef(), returnTypeRef);
    sema.setIsValue(sema.curNodeRef());
    sema.unsetIsLValue(sema.curNodeRef());
    finalizeCompilerRunFunction(sema.ctx(), *runExprSymFn, returnTypeRef);
    if (node.hasFlag(AstCompilerRunBlockFlagsE::Immediate))
        return SemaJIT::runExprImmediate(sema, *runExprSymFn, sema.curNodeRef());
    return SemaJIT::runExpr(sema, *runExprSymFn, sema.curNodeRef());
}

Result AstCompilerRunExpr::semaPreNode(Sema& sema)
{
    return setupCompilerRunFunction(sema, sema.typeMgr().typeVoid());
}

Result AstCompilerRunExpr::semaPostNode(Sema& sema) const
{
    const SemaNodeView view = sema.viewType(nodeExprRef);
    SWC_ASSERT(view.type() != nullptr);
    if (view.type()->isVoid())
        return SemaError::raise(sema, DiagnosticId::sema_err_run_expr_void, nodeExprRef);

    auto& runExprSymFn = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    finalizeCompilerRunFunction(sema.ctx(), runExprSymFn, view.typeRef());
    SWC_RESULT(SemaJIT::runExpr(sema, runExprSymFn, nodeExprRef));
    sema.inheritPayload(sema.curNode(), nodeExprRef);

    return Result::Continue;
}

SWC_END_NAMESPACE();
