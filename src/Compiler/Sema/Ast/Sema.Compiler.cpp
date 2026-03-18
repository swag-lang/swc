#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
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
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Version.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SymbolFunction* currentLocationFunction(const Sema& sema)
    {
        const auto* inlinePayload = sema.frame().currentInlinePayload();
        if (inlinePayload && inlinePayload->sourceFunction)
            return inlinePayload->sourceFunction;

        return sema.frame().currentFunction();
    }

    bool isDirectFunctionParameterDefault(const Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;
        if (sema.frame().currentFunction() == nullptr)
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

            const Token& scopeTok = sema.token({scopeNode.srcViewRef(), scopeNode.tokNameRef});
            if (scopeTok.string(sema.ast().srcView()) == scopeName)
                return parentRef;
        }
    }

    AstNodeRef rawInjectedNodeRef(Sema& sema, AstNodeRef nodeRef);

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
        Diagnostic diag = Diagnostic::get(id, sema.ast().srcView().fileRef());
        diag.last().addSpan(sema.node(nodeRef).codeRangeWithChildren(sema.ctx(), sema.ast()), "", DiagnosticSeverity::Error);
        SemaError::setReportArguments(sema, diag, nodeRef);
        diag.addArgument(Diagnostic::ARG_PATH, FileSystem::formatFileName(&sema.ctx(), path));
        diag.addArgument(Diagnostic::ARG_BECAUSE, because);
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

        std::error_code ec;
        fs::path        resolvedPath = fs::absolute(includePath, ec);
        if (ec)
            return reportCompilerFileError(sema, DiagnosticId::cmdline_err_invalid_file, nodeRef, includePath, FileSystem::normalizeSystemMessage(ec));

        const fs::path normalizedPath = fs::weakly_canonical(resolvedPath, ec);
        if (!ec)
            resolvedPath = normalizedPath;
        ec.clear();

        if (!fs::exists(resolvedPath, ec))
        {
            const Utf8 because = ec ? FileSystem::normalizeSystemMessage(ec) : Utf8{"path does not exist"};
            return reportCompilerFileError(sema, DiagnosticId::cmdline_err_invalid_file, nodeRef, resolvedPath, because);
        }

        ec.clear();
        if (!fs::is_regular_file(resolvedPath, ec))
        {
            const Utf8 because = ec ? FileSystem::normalizeSystemMessage(ec) : Utf8{"path is not a regular file"};
            return reportCompilerFileError(sema, DiagnosticId::cmdline_err_invalid_file, nodeRef, resolvedPath, because);
        }

        outPath = std::move(resolvedPath);
        return Result::Continue;
    }

    Result loadCompilerIncludeBytes(Sema& sema, AstNodeRef nodeRef, const fs::path& resolvedPath, std::vector<std::byte>& outBytes)
    {
        std::ifstream file(resolvedPath, std::ios::binary | std::ios::ate);
        if (!file)
            return reportCompilerFileError(sema, DiagnosticId::io_err_open_file, nodeRef, resolvedPath, FileSystem::normalizeSystemMessage(Os::systemError()));

        const std::streampos fileSize = file.tellg();
        if (fileSize < 0)
            return reportCompilerFileError(sema, DiagnosticId::io_err_read_file, nodeRef, resolvedPath, "cannot determine file size");

        outBytes.resize(fileSize);
        file.seekg(0, std::ios::beg);
        if (!outBytes.empty() && !file.read(reinterpret_cast<char*>(outBytes.data()), fileSize))
            return reportCompilerFileError(sema, DiagnosticId::io_err_read_file, nodeRef, resolvedPath, FileSystem::normalizeSystemMessage(Os::systemError()));

        return Result::Continue;
    }

    TypeRef makeCodeType(Sema& sema, TypeRef payloadTypeRef)
    {
        return sema.typeMgr().addType(TypeInfo::makeCodeBlock(payloadTypeRef));
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
            const TokenId  replacementId = sema.srcView(node.srcViewRef()).token(replacementInstructionRefs[i]).id;
            const AstNodeId nodeId        = injectReplacementNodeId(replacementId);
            SWC_ASSERT(nodeId != AstNodeId::Invalid);
            appendInjectReplacement(outReplacements, nodeId, replacementNodeRefs[i]);
        }
    }

    Result substituteCompilerInject(Sema& sema, AstNodeRef ownerRef, AstNodeRef exprRef,
                                    std::span<const SemaClone::NodeReplacement> replacements = std::span<const SemaClone::NodeReplacement>{})
    {
        SWC_RESULT(validateInjectArgument(sema, exprRef));

        const AstNodeRef rawRef = rawInjectedNodeRef(sema, exprRef);
        if (rawRef.isInvalid())
            return Result::Error;

        const SemaClone::CloneContext cloneContext{std::span<const SemaClone::ParamBinding>{}, replacements};
        const AstNodeRef              clonedRef = SemaClone::cloneAst(sema, rawRef, cloneContext);
        if (clonedRef.isInvalid())
            return Result::Error;

        sema.setSubstitute(ownerRef, clonedRef);
        sema.visit().restartCurrentNode(clonedRef);
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
    const auto&     node         = sema.curNode().cast<AstScopedBreakStmt>();
    const Token&    tokScopeName = sema.token({node.srcViewRef(), node.tokNameRef});
    const AstNodeRef scopeRef    = findNamedCompilerScope(sema, tokScopeName.string(sema.ast().srcView()));
    if (scopeRef.isValid())
        return Result::Continue;

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_unknown_scope_name, SourceCodeRef{node.srcViewRef(), node.tokNameRef});
    diag.addArgument(Diagnostic::ARG_SYM, tokScopeName.string(sema.ast().srcView()));
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
    sema.setType(sema.curNodeRef(), makeCodeType(sema, payload));
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
    sema.setType(sema.curNodeRef(), makeCodeType(sema, payload));
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

    const SemaNodeView condView = sema.viewConstant(nodeConditionRef);
    SWC_ASSERT(condView.cst());
    if (!condView.cst()->isBool())
        return SemaError::raiseInvalidType(sema, nodeConditionRef, condView.cst()->typeRef(), sema.typeMgr().typeBool());

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
    const Token&       tok     = sema.token(codeRef());
    const SemaNodeView argView = sema.viewConstant(nodeArgRef);
    SWC_ASSERT(argView.hasConstant());
    const ConstantValue& constant = *(argView.cst());
    switch (tok.id)
    {
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
            if (!constant.isString())
                return SemaError::raiseInvalidType(sema, nodeArgRef, constant.typeRef(), sema.typeMgr().typeString());
            break;

        case TokenId::CompilerAssert:
            if (!constant.isBool())
                return SemaError::raiseInvalidType(sema, nodeArgRef, constant.typeRef(), sema.typeMgr().typeBool());
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
    const SourceView&  srcView = sema.ast().srcView();

    switch (tok.id)
    {
        case TokenId::CompilerFile:
        {
            const SourceFile*      file     = sema.ast().srcView().file();
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

        case TokenId::CompilerCallerFunction:
            sema.setType(sema.curNodeRef(), sema.typeMgr().typeString());
            sema.setIsValue(*this);
            break;
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
            sema.setConstant(sema.curNodeRef(), ConstantHelpers::makeSourceCodeLocation(sema, *this, currentLocationFunction(sema)));
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
        SWC_RESULT(SemaCheck::isConstant(sema, node.nodeModeRef));
        const SemaNodeView condView = sema.viewConstant(node.nodeModeRef);

        SWC_ASSERT(condView.cst());
        if (!condView.cst()->isBool())
            return SemaError::raiseInvalidType(sema, node.nodeModeRef, condView.cst()->typeRef(), sema.typeMgr().typeBool());

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

        case Mode::Export:
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
        SemaNodeView     view     = sema.viewTypeConstant(childRef);
        SWC_ASSERT(view.typeRef().isValid());

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

        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), typeRef));
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

        sema.setType(sema.curNodeRef(), view.typeRef());
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
        const SemaNodeView view     = sema.viewSymbol(childRef);
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

        return SemaError::raise(sema, DiagnosticId::sema_err_failed_nameof, childRef);
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

    Result semaCompilerLocation(Sema& sema, const AstCompilerCallOne& node)
    {
        TypeRef typeRef = TypeRef::invalid();
        SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, node.codeRef()));

        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewSymbol(childRef);
        if (!view.sym())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_location, childRef);

        const SourceCodeRange codeRange = view.sym()->codeRange(sema.ctx());
        sema.setConstant(sema.curNodeRef(), ConstantHelpers::makeSourceCodeLocation(sema, codeRange, view.sym()->safeCast<SymbolFunction>()));
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
        case TokenId::CompilerLocation:
            return semaCompilerLocation(sema, *this);
        case TokenId::CompilerForeignLib:
            return semaCompilerForeignLib(sema, *this);
        case TokenId::CompilerInclude:
            return semaCompilerInclude(sema, *this);
        case TokenId::CompilerInject:
            return substituteCompilerInject(sema, sema.curNodeRef(), nodeArgRef);

        case TokenId::CompilerHasTag:
        case TokenId::CompilerRunes:
        case TokenId::CompilerSafety:
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
    if (tok.id == TokenId::CompilerForeignLib || tok.id == TokenId::CompilerInclude)
        SemaHelpers::pushConstExprRequirement(sema, childRef);

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

Result AstCompilerCall::semaPostNode(const Sema& sema) const
{
    const Token& tok = sema.token(codeRef());
    switch (tok.id)
    {
        case TokenId::CompilerGetTag:
            // TODO
            SWC_INTERNAL_ERROR();

        default:
            SWC_INTERNAL_ERROR();
    }
}

Result AstCompilerFunc::semaPreDecl(Sema& sema)
{
    TaskContext& ctx                = sema.ctx();
    const Token& tok                = sema.token(codeRef());
    const bool   ignoreTestFunc     = tok.id == TokenId::CompilerFuncTest && !ctx.cmdLine().isTestMode();
    const bool   ignoreMainFunc     = tok.id == TokenId::CompilerFuncMain && (ctx.cmdLine().backendKindName == "dll" || ctx.cmdLine().backendKindName == "lib");
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
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isIgnored())
        return Result::SkipChildren;

    sym.registerAttributes(sema);
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

    sym.setSemaCompleted(sema.ctx());

    const TokenId tokenId = sema.token(codeRef()).id;
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

Result AstCompilerRunExpr::semaPreNode(Sema& sema)
{
    const AstNodeRef nodeRef = sema.curNodeRef();
    if (!sema.viewSymbol(nodeRef).hasSymbol())
    {
        TaskContext&        ctx   = sema.ctx();
        const IdentifierRef idRef = SemaHelpers::getUniqueIdentifier(sema, "__run_expr");
        const AstNode&      node  = sema.node(nodeRef);

        auto* symFn = Symbol::make<SymbolFunction>(ctx, &node, node.tokRef(), idRef, sema.frame().flagsForCurrentAccess());
        symFn->setOwnerSymMap(SemaFrame::currentSymMap(sema));
        symFn->setDeclNodeRef(nodeRef);
        symFn->setReturnTypeRef(sema.typeMgr().typeVoid());
        symFn->setAttributes(sema.frame().currentAttributes());
        symFn->setDeclared(ctx);
        symFn->setTyped(ctx);
        symFn->setSemaCompleted(ctx);
        sema.setSymbol(nodeRef, symFn);
    }

    SemaFrame frame = sema.frame();
    auto&     symFn = sema.viewSymbol(nodeRef).sym()->cast<SymbolFunction>();
    if (SymbolFunction* currentFn = sema.frame().currentFunction())
        currentFn->addCallDependency(&symFn);

    frame.currentAttributes() = symFn.attributes();
    frame.setCurrentFunction(&symFn);
    frame.addContextFlag(SemaFrameContextFlagsE::RunExpr);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

Result AstCompilerRunExpr::semaPostNode(Sema& sema) const
{
    const SemaNodeView view = sema.viewType(nodeExprRef);
    SWC_ASSERT(view.type() != nullptr);
    if (view.type()->isVoid())
        return SemaError::raise(sema, DiagnosticId::sema_err_run_expr_void, nodeExprRef);

    auto& runExprSymFn = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    SWC_RESULT(SemaJIT::runExpr(sema, runExprSymFn, nodeExprRef));
    sema.inheritPayload(sema.curNode(), nodeExprRef);

    return Result::Continue;
}

SWC_END_NAMESPACE();
