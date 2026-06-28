#include "pch.h"
#include "Support/Report/Assert.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t K_COMPILER_AST_MAX_EXPANSION_DEPTH = 64;

    AstNodeRef compilerRunFunctionStorageRef(const AstNode& node)
    {
        if (const auto* runBlock = node.safeCast<AstCompilerRunBlock>())
            return runBlock->nodeBodyRef;
        return AstNodeRef::invalid();
    }

    Result reportCompilerFileError(Sema& sema, DiagnosticId id, AstNodeRef nodeRef, const fs::path& path, const Utf8& because)
    {
        Diagnostic diag = SemaError::build(sema, id, nodeRef);
        FileSystem::setDiagnosticPathAndBecause(diag, &sema.ctx(), path, because);
        diag.report(sema.ctx());
        return Result::Error;
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

    const Sema::ActiveCompilerAstExpansion* findActiveCompilerAstExpansion(const Sema& sema, std::string_view generatedCode)
    {
        const auto& stack = sema.compilerAstExpansions();
        for (const auto& it : std::views::reverse(stack))
        {
            if (it.generatedCode.view() == generatedCode)
                return &it;
        }

        return nullptr;
    }

    Result reportCompilerAstRecursiveExpansion(Sema& sema, AstNodeRef ownerRef, const Sema::ActiveCompilerAstExpansion& previous)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_ast_recursive_expansion, ownerRef);
        if (previous.codeRange.srcView && previous.codeRange.len)
        {
            auto& note = diag.addElement(DiagnosticId::sema_note_other_ast_expansion);
            note.setSeverity(DiagnosticSeverity::Note);
            note.addSpan(previous.codeRange, "");
        }

        diag.report(sema.ctx());
        return Result::Error;
    }

    Result reportCompilerAstExpansionTooDeep(Sema& sema, AstNodeRef ownerRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_ast_expansion_too_deep, ownerRef);
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(K_COMPILER_AST_MAX_EXPANSION_DEPTH));
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result validateCompilerAstExpansion(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode)
    {
        const auto& stack = sema.compilerAstExpansions();
        if (stack.size() >= K_COMPILER_AST_MAX_EXPANSION_DEPTH)
            return reportCompilerAstExpansionTooDeep(sema, ownerRef);

        if (const auto* previous = findActiveCompilerAstExpansion(sema, generatedCode))
            return reportCompilerAstRecursiveExpansion(sema, ownerRef, *previous);

        return Result::Continue;
    }

    void pushCompilerAstExpansion(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode)
    {
        auto& stack = sema.compilerAstExpansions();
        stack.push_back({});
        stack.back().generatedCode = Utf8{generatedCode};
        stack.back().codeRange     = sema.node(ownerRef).codeRangeWithChildren(sema.ctx(), sema.ast());
    }

    Result popCompilerAstExpansion(Sema& sema, AstNodeRef nodeRef)
    {
        SWC_UNUSED(nodeRef);

        auto& stack = sema.compilerAstExpansions();
        SWC_ASSERT(!stack.empty());
        if (!stack.empty())
            stack.pop_back();

        return Result::Continue;
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

    ParserGeneratedMode parseCompilerAstModeForNodeId(const AstNodeId nodeId)
    {
        switch (nodeId)
        {
            case AstNodeId::AggregateBody:
                return ParserGeneratedMode::Aggregate;

            case AstNodeId::EnumBody:
                return ParserGeneratedMode::Enum;

            case AstNodeId::File:
            case AstNodeId::TopLevelBlock:
            case AstNodeId::Impl:
                return ParserGeneratedMode::TopLevel;

            default:
                return ParserGeneratedMode::Embedded;
        }
    }

    ParserGeneratedMode compilerAstParseMode(const Sema& sema, AstNodeRef ownerRef)
    {
        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (!parentRef.isValid())
            return ParserGeneratedMode::TopLevel;

        const AstNode& parentNode = sema.node(parentRef);
        if (parentNode.is(AstNodeId::AccessModifier))
        {
            const AstNodeRef grandParentRef = sema.visit().parentNodeRef(1);
            if (grandParentRef.isValid())
                return parseCompilerAstModeForNodeId(sema.node(grandParentRef).id());
        }

        SWC_UNUSED(ownerRef);
        return parseCompilerAstModeForNodeId(parentNode.id());
    }

    bool compilerAstParseModeFromMixinCaller(const Sema& sema, ParserGeneratedMode& outMode)
    {
        const auto* inlinePayload = SemaHelpers::effectiveInlinePayload(sema);
        if (!inlinePayload || !inlinePayload->sourceFunction || !inlinePayload->callerScope)
            return false;
        if (!inlinePayload->sourceFunction->attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;

        if (inlinePayload->callerImpl)
        {
            outMode = ParserGeneratedMode::TopLevel;
            return true;
        }

        for (const SemaScope* scope = inlinePayload->callerScope; scope; scope = scope->parent())
        {
            if (scope->isImpl())
            {
                outMode = ParserGeneratedMode::TopLevel;
                return true;
            }

            const SymbolMap* symMap = scope->symMap();
            if (symMap)
            {
                if (symMap->isStruct())
                {
                    outMode = ParserGeneratedMode::Aggregate;
                    return true;
                }

                if (symMap->isEnum())
                {
                    outMode = ParserGeneratedMode::Enum;
                    return true;
                }

                if (symMap->isImpl() || symMap->isNamespace() || symMap->isModule())
                {
                    outMode = ParserGeneratedMode::TopLevel;
                    return true;
                }

                if (symMap->isFunction())
                {
                    outMode = ParserGeneratedMode::Embedded;
                    return true;
                }
            }

            if (scope->isLocal())
            {
                outMode = ParserGeneratedMode::Embedded;
                return true;
            }

            if (scope->isTopLevel())
            {
                outMode = ParserGeneratedMode::TopLevel;
                return true;
            }
        }

        return false;
    }

    Result createCompilerAstGeneratedSource(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode, SourceView*& outSrcView, TokenRef& outStartTokRef)
    {
        outSrcView     = nullptr;
        outStartTokRef = TokenRef::invalid();

        uint32_t   sectionCodeOffset = 0;
        const Utf8 sectionText       = buildCompilerAstGeneratedSection(sema, ownerRef, generatedCode, sectionCodeOffset);

        CompilerInstance::GeneratedSourceAppendResult appendResult;
        Utf8                                          because;
        if (sema.compiler().appendGeneratedSource(appendResult, because, sectionText.view(), sectionCodeOffset) != Result::Continue)
            return reportCompilerFileError(sema, DiagnosticId::sema_err_ast_file_write_failed, ownerRef, appendResult.path, because);

        SourceFile& sourceFile = sema.compiler().addLoadedFile(appendResult.path, FileFlagsE::CustomSrc | FileFlagsE::SkipFmt, appendResult.snapshot.view());
        sourceFile.ast().srcView().setLineOffset(appendResult.lineOffset);
        sourceFile.unitTest().tokenize(sema.ctx());

        SourceView& srcView = sourceFile.ast().srcView();
        if (const SourceFile* ownerFile = sema.file())
        {
            srcView.setOwnerFileRef(ownerFile->ref());
            srcView.setDebugSourceCodeRef(sema.node(ownerRef).codeRef());
            if (const SymbolNamespace* moduleNamespace = ownerFile->moduleNamespace())
                sourceFile.setModuleNamespace(*const_cast<SymbolNamespace*>(moduleNamespace));
        }

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

    Result declareCompilerAstGeneratedTopLevel(Sema& sema, AstNodeRef generatedRef, const ParserGeneratedMode parseMode)
    {
        if (parseMode != ParserGeneratedMode::TopLevel)
            return Result::Continue;

        Sema         generatedDeclSema(sema.ctx(), sema, generatedRef, true);
        const Result declResult = generatedDeclSema.execResult();
        SWC_ASSERT(declResult != Result::Pause);
        return declResult;
    }

    bool isCurrentCompilerAstExpansionNode(Sema& sema, AstNodeRef ownerRef)
    {
        if (ownerRef != sema.curNodeRef())
            return false;

        const AstNode& owner = sema.node(ownerRef);
        if (!owner.is(AstNodeId::CompilerFunc) && !owner.is(AstNodeId::CompilerShortFunc))
            return false;

        return sema.token(owner.codeRef()).id == TokenId::CompilerAst;
    }

    Result parseCompilerAstGenerated(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode, AstNodeRef& outGeneratedRef)
    {
        outGeneratedRef = AstNodeRef::invalid();
        auto parseMode  = ParserGeneratedMode::Embedded;
        if (!compilerAstParseModeFromMixinCaller(sema, parseMode))
            parseMode = compilerAstParseMode(sema, ownerRef);

        SourceView* generatedSrcView = nullptr;
        TokenRef    generatedStartTokRef;
        SWC_RESULT(createCompilerAstGeneratedSource(sema, ownerRef, generatedCode, generatedSrcView, generatedStartTokRef));
        SWC_ASSERT(generatedSrcView != nullptr);
        if (!generatedSrcView)
            return Result::Error;

        const uint64_t errorsBefore = Stats::getNumErrors();
        Parser         parser;
        outGeneratedRef = parser.parseGenerated(sema.ctx(), sema.ast(), *generatedSrcView, parseMode, generatedStartTokRef);
        if (Stats::getNumErrors() != errorsBefore)
            return Result::Error;
        if (!outGeneratedRef.isValid())
            return Result::Error;

        if (isCurrentCompilerAstExpansionNode(sema, ownerRef))
            sema.processCurrentPostNodePopsNow();
        SWC_RESULT(declareCompilerAstGeneratedTopLevel(sema, outGeneratedRef, parseMode));
        return Result::Continue;
    }

    Result substituteCompilerAstString(Sema& sema, AstNodeRef ownerRef, std::string_view generatedCode)
    {
        SWC_RESULT(validateCompilerAstExpansion(sema, ownerRef, generatedCode));

        AstNodeRef generatedRef = AstNodeRef::invalid();
        SWC_RESULT(parseCompilerAstGenerated(sema, ownerRef, generatedCode, generatedRef));
        pushCompilerAstExpansion(sema, ownerRef, generatedCode);
        sema.deferPostNodeAction(generatedRef, popCompilerAstExpansion);
        sema.setSubstitute(ownerRef, generatedRef);
        sema.restartCurrentNode(generatedRef);
        return Result::Continue;
    }

    Result castCompilerAstResultToString(Sema& sema, SemaNodeView& ioView)
    {
        if (!ioView.typeRef().isValid())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_ast_requires_string, ioView.nodeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, sema.typeMgr().typeVoid());
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!compilerAstStringType(sema, ioView.typeRef()))
        {
            CastRequest castRequest(CastKind::Implicit);
            castRequest.flags.add(CastFlagsE::ForceConstEval);
            castRequest.errorNodeRef       = ioView.nodeRef();
            const Result castAllowedResult = Cast::castAllowed(sema, castRequest, ioView.typeRef(), sema.typeMgr().typeString());
            if (castAllowedResult == Result::Pause)
                return Result::Pause;

            if (castAllowedResult != Result::Continue)
            {
                const TypeRef reportedTypeRef = ioView.typeRef().isValid() ? ioView.typeRef() : sema.typeMgr().typeVoid();
                auto          diag            = SemaError::report(sema, DiagnosticId::sema_err_ast_requires_string, ioView.nodeRef());
                diag.addArgument(Diagnostic::ARG_TYPE, sema.typeMgr().get(reportedTypeRef).toName(sema.ctx()));
                diag.report(sema.ctx());
                return Result::Error;
            }

            SWC_RESULT(Cast::cast(sema, ioView, sema.typeMgr().typeString(), CastKind::Implicit, CastFlagsE::ForceConstEval));
            ioView = SemaNodeView(sema, ioView.nodeRef(), SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }

        if (ioView.cst() && ioView.cst()->isString())
            return Result::Continue;

        const TypeRef reportedTypeRef = ioView.typeRef().isValid() ? ioView.typeRef() : sema.typeMgr().typeVoid();
        auto          diag            = SemaError::report(sema, DiagnosticId::sema_err_ast_requires_string, ioView.nodeRef());
        diag.addArgument(Diagnostic::ARG_TYPE, sema.typeMgr().get(reportedTypeRef).toName(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    SymbolFunction& registerCompilerBodyFunction(Sema& sema, const AstNode& node, std::string_view name)
    {
        auto& sym = SemaHelpers::registerUniqueSymbol<SymbolFunction>(sema, node, name);
        sym.setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, sym));
        sym.setDeclNodeRef(sema.curNodeRef());
        sym.setDeclNodePayloadContext(&sema.currentNodePayloadContext());
        return sym;
    }

    Result enterCompilerBodyFunction(Sema& sema, SymbolFunction& symFn, TypeRef returnTypeRef)
    {
        if (symFn.isIgnored())
            return Result::SkipChildren;

        // Generic instantiation can restart a completed compiler body while its JIT codegen is still joining.
        // Keep the inferred `#ast` return type stable once a return statement has established it.
        if (returnTypeRef.isValid() || !symFn.returnTypeRef().isValid())
            symFn.setReturnTypeRef(returnTypeRef);

        auto frame                = sema.frame();
        frame.currentAttributes() = symFn.attributes();
        frame.setEnclosingFunction(sema.currentFunction());
        frame.setCurrentFunction(&symFn);

        sema.pushFramePopOnPostNode(frame);
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
        sema.curScope().setSymMap(&symFn);
        return Result::Continue;
    }

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
            symFn->setDeclNodePayloadContext(&sema.currentNodePayloadContext());
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
        frame.setEnclosingFunction(sema.currentFunction());
        frame.setCurrentFunction(&symFn);
        frame.addContextFlag(SemaFrameContextFlagsE::RunExpr);
        sema.pushFramePopOnPostNode(frame);
        return Result::Continue;
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
    SemaNodeView view = sema.viewNodeTypeConstant(nodeBodyRef);
    SWC_RESULT(castCompilerAstResultToString(sema, view));
    return substituteCompilerAstString(sema, sema.curNodeRef(), view.cst()->getString());
}

Result AstCompilerMessageFunc::semaPreNode(Sema& sema)
{
    if (sema.enteringState())
    {
        const AstNodeRef curNodeRef = sema.curNodeRef();
        if (!sema.viewSymbol(curNodeRef).hasSymbol())
            registerCompilerBodyFunction(sema, sema.curNode(), "message");

        auto& declaredSym = sema.viewSymbol(curNodeRef).sym()->cast<SymbolFunction>();
        declaredSym.registerAttributes(sema);
        declaredSym.setDeclared(sema.ctx());
    }

    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    return enterCompilerBodyFunction(sema, sym, sema.typeMgr().typeVoid());
}

Result AstCompilerMessageFunc::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamRef)
        SemaHelpers::pushConstExprRequirement(sema, childRef);
    return Result::Continue;
}

Result AstCompilerMessageFunc::semaPostNode(Sema& sema) const
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isIgnored())
        return Result::Continue;

    SWC_RESULT(SemaCheck::isConstant(sema, nodeParamRef));
    const SemaNodeView finalMaskView = sema.viewConstant(nodeParamRef);
    SWC_ASSERT(finalMaskView.cst() != nullptr);
    const ConstantValue* maskValue = finalMaskView.cst();
    if (maskValue->isEnumValue())
        maskValue = &sema.cstMgr().get(maskValue->getEnumValue());

    if (!maskValue->isInt())
        return SemaError::raiseInvalidType(sema, nodeParamRef, finalMaskView.typeRef(), sema.typeMgr().typeU64());

    sym.setSemaCompleted(sema.ctx());
    sema.compiler().registerCompilerMessageFunction(&sym, sema.curNodeRef(), maskValue->getInt().as64());
    return Result::Continue;
}

Result AstCompilerFunc::semaPreDecl(Sema& sema)
{
    TaskContext& ctx                = sema.ctx();
    const Token& tok                = sema.token(codeRef());
    const bool   ignoreTestFunc     = tok.id == TokenId::CompilerFuncTest && !ctx.cmdLine().sourceDrivenTest;
    const bool   ignoreMainFunc     = tok.id == TokenId::CompilerFuncMain && !ctx.cmdLine().scriptMode && ctx.cmdLine().backendKind != Runtime::BuildCfgBackendKind::Executable;
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
    sym.setDeclNodePayloadContext(&sema.currentNodePayloadContext());
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
        {
            const Result declResult = sema.curNode().cast<AstCompilerFunc>().semaPreDecl(sema);
            if (declResult == Result::Error || declResult == Result::Pause)
                return declResult;
        }

        if (!sema.viewSymbol(curNodeRef).hasSymbol())
            return Result::Error;

        auto& declaredSym = sema.viewSymbol(curNodeRef).sym()->cast<SymbolFunction>();
        declaredSym.registerAttributes(sema);
        declaredSym.setDeclared(sema.ctx());
    }

    auto&         sym           = sema.viewStored(sema.curNodeRef(), SemaNodeViewPartE::Symbol).sym()->cast<SymbolFunction>();
    const TypeRef returnTypeRef = tokenId == TokenId::CompilerAst ? sema.typeMgr().typeString() : sema.typeMgr().typeVoid();
    return enterCompilerBodyFunction(sema, sym, returnTypeRef);
}

Result AstCompilerFunc::semaPostNode(Sema& sema) const
{
    const SemaNodeView symView = sema.viewStored(sema.curNodeRef(), SemaNodeViewPartE::Symbol);
    if (!symView.hasSymbol())
        return Result::Continue;

    auto& sym = symView.sym()->cast<SymbolFunction>();
    if (sym.isIgnored())
        return Result::Continue;

    const TokenId tokenId = sema.token(codeRef()).id;
    if (tokenId == TokenId::CompilerAst)
    {
        sym.setTyped(sema.ctx());
        sym.setSemaCompleted(sema.ctx());
        SWC_RESULT(SemaJIT::runFunctionResult(sema, sym, sema.curNodeRef()));

        SemaNodeView resultView = sema.viewNodeTypeConstant(sema.curNodeRef());
        SWC_RESULT(castCompilerAstResultToString(sema, resultView));
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
