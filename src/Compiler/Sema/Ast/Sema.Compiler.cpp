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
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/Version.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct CompilerIfSemaPayload
    {
        SemaCompilerIf* ifData   = nullptr;
        SemaCompilerIf* elseData = nullptr;
    };

    CompilerIfSemaPayload& ensureCompilerIfSemaPayload(Sema& sema, AstNodeRef nodeRef)
    {
        if (auto* payload = sema.semaPayload<CompilerIfSemaPayload>(nodeRef))
            return *payload;

        auto* payload = sema.compiler().allocate<CompilerIfSemaPayload>();
        sema.setSemaPayload(nodeRef, payload);
        return *payload;
    }

    bool isDirectFunctionParameterDefault(const Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNodeRef parentRef = sema.visit().parentNodeRef();
        if (parentRef.isInvalid())
            return false;

        const AstNode& parentNode = sema.node(parentRef);
        if (const auto* singleVar = parentNode.safeCast<AstSingleVarDecl>())
            return singleVar->hasFlag(AstVarDeclFlagsE::Parameter) && singleVar->nodeInitRef == nodeRef;

        if (const auto* multiVar = parentNode.safeCast<AstMultiVarDecl>())
            return multiVar->hasFlag(AstVarDeclFlagsE::Parameter) && multiVar->nodeInitRef == nodeRef;

        if (const auto* lambdaParam = parentNode.safeCast<AstLambdaParam>())
            return lambdaParam->nodeDefaultValueRef == nodeRef;

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

    Result castCompilerConditionToBool(Sema& sema, AstNodeRef nodeRef)
    {
        SWC_RESULT(SemaCheck::isConstant(sema, nodeRef));

        SemaNodeView view = sema.viewNodeTypeConstant(nodeRef);
        SWC_RESULT(SemaCheck::isValue(sema, view.nodeRef()));
        return Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr);
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
    const auto&         node = sema.curNode().cast<AstScopedBreakStmt>();
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
        SemaFrame              frame   = sema.frame();
        CompilerIfSemaPayload& payload = ensureCompilerIfSemaPayload(sema, sema.curNodeRef());
        if (!payload.ifData)
        {
            payload.ifData         = sema.compiler().allocate<SemaCompilerIf>();
            payload.ifData->parent = frame.currentCompilerIf();
        }

        frame.setCurrentCompilerIf(payload.ifData);
        sema.pushFramePopOnPostChild(frame, childRef);
        return Result::Continue;
    }

    SWC_ASSERT(childRef == nodeElseBlockRef);
    if (nodeElseBlockRef.isValid())
    {
        SemaFrame              frame   = sema.frame();
        CompilerIfSemaPayload& payload = ensureCompilerIfSemaPayload(sema, sema.curNodeRef());
        if (!payload.elseData)
        {
            payload.elseData         = sema.compiler().allocate<SemaCompilerIf>();
            payload.elseData->parent = frame.currentCompilerIf();
        }

        frame.setCurrentCompilerIf(payload.elseData);
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

    if (childRef == nodeIfBlockRef || childRef == nodeElseBlockRef)
    {
        SemaFrame              frame   = sema.frame();
        CompilerIfSemaPayload& payload = ensureCompilerIfSemaPayload(sema, sema.curNodeRef());
        SemaCompilerIf*&       branch  = childRef == nodeIfBlockRef ? payload.ifData : payload.elseData;
        if (!branch)
        {
            branch         = sema.compiler().allocate<SemaCompilerIf>();
            branch->parent = frame.currentCompilerIf();
        }

        frame.setCurrentCompilerIf(branch);
        sema.pushFramePopOnPostChild(frame, childRef);
    }

    return Result::Continue;
}

Result AstCompilerIf::semaPostNode(Sema& sema) const
{
    // Condition must already be a constant at this point
    const SemaNodeView condView = sema.viewConstant(nodeConditionRef);
    SWC_ASSERT(condView.hasConstant());
    SWC_ASSERT(condView.cst());
    const bool takenIfBranch = condView.cst()->getBool();

    const CompilerIfSemaPayload* payload        = sema.semaPayload<CompilerIfSemaPayload>(sema.curNodeRef());
    const SemaCompilerIf*        selectedIfData = payload ? (takenIfBranch ? payload->ifData : payload->elseData) : nullptr;
    if (selectedIfData)
    {
        for (Symbol* sym : selectedIfData->symbols)
        {
            if (sym && !sym->isIgnored())
                SemaHelpers::ensureCurrentLocalScopeSymbol(sema, sym);
        }
    }

    // The block that will be ignored
    const SemaCompilerIf* ignoredIfData = payload ? (takenIfBranch ? payload->elseData : payload->ifData) : nullptr;
    if (ignoredIfData)
    {
        for (Symbol* sym : ignoredIfData->symbols)
            if (sym)
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

        case TokenId::CompilerCommand:
        {
            TypeRef typeRef = TypeRef::invalid();
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::CompilerCommand, typeRef, codeRef()));
            const ConstantRef   valueCst     = sema.cstMgr().addS32(ctx, static_cast<int32_t>(compilerCommandFromKind(sema.ctx().cmdLine().command)));
            const ConstantValue enumValue    = ConstantValue::makeEnumValue(ctx, valueCst, typeRef);
            const ConstantRef   enumValueRef = sema.cstMgr().addConstant(ctx, enumValue);
            sema.setConstant(sema.curNodeRef(), enumValueRef);
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
        case Mode::Generated:
        case Mode::AttributeList:
            return Result::Continue;

        case Mode::CompilerIf:
            return semaCompilerGlobalIf(sema, *this);

        case Mode::Using:
            // TODO
            return Result::SkipChildren;

        default:
            break;
    }

    return Result::Continue;
}
SWC_END_NAMESPACE();
