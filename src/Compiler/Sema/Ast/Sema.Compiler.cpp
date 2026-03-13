#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/Version.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticDef.h"
#include "Support/Report/Logger.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr Runtime::TargetOs nativeTargetOs()
    {
#ifdef _WIN32
        return Runtime::TargetOs::Windows;
#else
        return Runtime::TargetOs::Linux;
#endif
    }
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
        case TokenId::CompilerCurLocation:
        {
            TypeRef typeRef = TypeRef::invalid();
            SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, codeRef()));
            sema.setConstant(sema.curNodeRef(), ConstantHelpers::makeSourceCodeLocation(sema, *this));
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
        const SemaNodeView view     = sema.viewConstant(childRef);

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

    Result semaCompilerLocation(Sema& sema, const AstCompilerCallOne& node)
    {
        TypeRef typeRef = TypeRef::invalid();
        SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::SourceCodeLocation, typeRef, node.codeRef()));

        const AstNodeRef   childRef = node.nodeArgRef;
        const SemaNodeView view     = sema.viewSymbol(childRef);
        if (!view.sym())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_location, childRef);

        const SourceCodeRange codeRange = view.sym()->codeRange(sema.ctx());
        sema.setConstant(sema.curNodeRef(), ConstantHelpers::makeSourceCodeLocation(sema, codeRange));
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
        case TokenId::CompilerLocation:
            return semaCompilerLocation(sema, *this);
        case TokenId::CompilerForeignLib:
            return semaCompilerForeignLib(sema, *this);

        case TokenId::CompilerHasTag:
        case TokenId::CompilerRunes:
        case TokenId::CompilerIsConstExpr:
        case TokenId::CompilerSafety:
        case TokenId::CompilerInject:
        case TokenId::CompilerInclude:
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
    if (tok.id == TokenId::CompilerForeignLib)
        SemaHelpers::pushConstExprRequirement(sema, childRef);

    return Result::Continue;
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
    const bool   ignoreTestFunc     = tok.id == TokenId::CompilerFuncTest && !ctx.cmdLine().test;
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

    SemaFrame frame           = sema.frame();
    auto&     symFn           = sema.viewSymbol(nodeRef).sym()->cast<SymbolFunction>();
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
