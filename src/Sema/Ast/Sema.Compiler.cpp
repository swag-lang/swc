#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/Version.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Report/Logger.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()

Result AstCompilerExpression::semaPostNode(Sema& sema)
{
    RESULT_VERIFY(SemaCheck::isConstant(sema, nodeExprRef));
    sema.semaInherit(*this, nodeExprRef);
    return Result::Continue;
}

Result AstCompilerIf::semaPreDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return Result::Continue;

    if (childRef == nodeIfBlockRef)
    {
        SemaFrame       frame    = sema.frame();
        SemaCompilerIf* parentIf = frame.compilerIf();
        SemaCompilerIf* ifFrame  = sema.compiler().allocate<SemaCompilerIf>();
        ifFrame->parent          = parentIf;

        frame.setCompilerIf(ifFrame);
        sema.setPayload(nodeIfBlockRef, ifFrame);
        sema.pushFrame(frame);
        return Result::Continue;
    }

    // Leaving the 'if' block
    sema.popFrame();

    SWC_ASSERT(childRef == nodeElseBlockRef);
    if (nodeElseBlockRef.isValid())
    {
        SemaFrame       frame     = sema.frame();
        SemaCompilerIf* parentIf  = frame.compilerIf();
        SemaCompilerIf* elseFrame = sema.compiler().allocate<SemaCompilerIf>();
        elseFrame->parent         = parentIf;

        frame.setCompilerIf(elseFrame);
        sema.setPayload(nodeElseBlockRef, elseFrame);
        sema.pushFrame(frame);
    }

    return Result::Continue;
}

Result AstCompilerIf::semaPostDecl(Sema& sema) const
{
    if (nodeElseBlockRef.isValid())
        sema.popFrame();
    return Result::Continue;
}

Result AstCompilerIf::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return Result::Continue;

    const ConstantValue& constant = sema.constantOf(nodeConditionRef);
    if (!constant.isBool())
        return SemaError::raiseInvalidType(sema, nodeConditionRef, constant.typeRef(), sema.typeMgr().typeBool());

    if (childRef == nodeIfBlockRef && !constant.getBool())
        return Result::SkipChildren;
    if (childRef == nodeElseBlockRef && constant.getBool())
        return Result::SkipChildren;

    return Result::Continue;
}

Result AstCompilerIf::semaPostNode(Sema& sema) const
{
    // Condition must already be a constant at this point
    SWC_ASSERT(sema.hasConstant(nodeConditionRef));

    const ConstantValue& constant      = sema.constantOf(nodeConditionRef);
    const bool           takenIfBranch = constant.getBool();

    // The block that will be ignored
    const AstNodeRef& ignoredBlockRef = takenIfBranch ? nodeElseBlockRef : nodeIfBlockRef;
    if (!ignoredBlockRef.isValid())
        return Result::Continue;

    // Retrieve the SemaCompilerIf payload
    if (sema.hasPayload(ignoredBlockRef))
    {
        const SemaCompilerIf* ignoredIfData = sema.payload<SemaCompilerIf>(ignoredBlockRef);
        if (!ignoredIfData)
            return Result::Continue;

        for (Symbol* sym : ignoredIfData->symbols)
            sym->setIgnored(sema.ctx());
    }

    return Result::Continue;
}

Result AstCompilerDiagnostic::semaPostNode(Sema& sema) const
{
    SWC_ASSERT(sema.hasConstant(nodeArgRef));

    const Token&         tok      = sema.token(srcViewRef(), tokRef());
    const ConstantValue& constant = sema.constantOf(nodeArgRef);
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
                return SemaError::raise(sema, DiagnosticId::sema_err_compiler_assert, srcViewRef(), tokRef());
            break;

        default:
            break;
    }

    switch (tok.id)
    {
        case TokenId::CompilerError:
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_compiler_error, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString(), false);
            diag.report(sema.ctx());
            return Result::Stop;
        }

        case TokenId::CompilerWarning:
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_warn_compiler_warning, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString(), false);
            diag.report(sema.ctx());
            return Result::Continue;
        }

        case TokenId::CompilerPrint:
        {
            const auto& ctx = sema.ctx();
            ctx.global().logger().lock();
            Logger::print(ctx, constant.toString(ctx));
            Logger::print(ctx, "\n");
            ctx.global().logger().unlock();
            return Result::Continue;
        }

        case TokenId::CompilerAssert:
            if (!constant.getBool())
                return SemaError::raise(sema, DiagnosticId::sema_err_compiler_assert, srcViewRef(), tokRef());
            break;

        default:
            break;
    }

    return Result::Continue;
}

Result AstCompilerLiteral::semaPostNode(Sema& sema) const
{
    const auto&       ctx     = sema.ctx();
    const Token&      tok     = sema.token(srcViewRef(), tokRef());
    const SourceView& srcView = sema.ast().srcView();

    switch (tok.id)
    {
        case TokenId::CompilerFile:
        {
            const SourceFile*    file = sema.ast().srcView().file();
            const ConstantValue& val  = ConstantValue::makeString(ctx, file ? file->path().string() : "");
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerLine:
        {
            const SourceCodeLocation loc = tok.location(ctx, srcView);
            const ConstantValue&     val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(loc.line), 0, TypeInfo::Sign::Unsigned);
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
            const TypeRef typeRef = sema.typeMgr().enumTargetOs();
            if (typeRef.isInvalid())
                return sema.waitIdentifier(sema.idMgr().nameTargetOs(), srcViewRef(), tokRef());
            const ConstantRef   valueCst     = sema.cstMgr().addS32(ctx, static_cast<int32_t>(sema.ctx().cmdLine().targetOs));
            const ConstantValue enumValue    = ConstantValue::makeEnumValue(ctx, valueCst, typeRef);
            const ConstantRef   enumValueRef = sema.cstMgr().addConstant(ctx, enumValue);
            sema.setConstant(sema.curNodeRef(), enumValueRef);
            break;
        }

        case TokenId::CompilerArch:
        case TokenId::CompilerCpu:
        case TokenId::CompilerBuildCfg:
        case TokenId::CompilerModule:
        case TokenId::CompilerCallerFunction:
        case TokenId::CompilerCallerLocation:
        case TokenId::CompilerSwagOs:
        case TokenId::CompilerBackend:
        case TokenId::CompilerScopeName:
        case TokenId::CompilerCurLocation:
            // TODO
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
            return Result::Continue;

        default:
            SWC_UNREACHABLE();
    }

    return Result::Continue;
}

Result AstCompilerGlobal::semaPreDecl(Sema& sema) const
{
    switch (mode)
    {
        case Mode::AccessPublic:
            sema.frame().setAccess(SymbolAccess::Public);
            break;
        case Mode::AccessInternal:
            sema.frame().setAccess(SymbolAccess::Internal);
            break;
        case Mode::AccessPrivate:
            sema.frame().setAccess(SymbolAccess::Private);
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

Result AstCompilerGlobal::semaPostNode(Sema&) const
{
    switch (mode)
    {
        case Mode::Skip:
        case Mode::SkipFmt:
        case Mode::Generated:
            return Result::Continue;

        case Mode::Export:
        case Mode::AttributeList:
        case Mode::CompilerIf:
        case Mode::Using:
            return Result::SkipChildren;
        default:
            break;
    }

    return Result::Continue;
}

namespace
{
    Result semaCompilerTypeOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        SemaNodeView nodeView(sema, node.nodeArgRef);
        SWC_ASSERT(nodeView.typeRef.isValid());

        if (nodeView.cstRef.isValid())
        {
            ConstantRef newCstRef;
            RESULT_VERIFY(sema.cstMgr().concretizeConstant(sema, newCstRef, nodeView.nodeRef, nodeView.cstRef, TypeInfo::Sign::Unknown));
            nodeView.setCstRef(sema, newCstRef);
        }

        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), nodeView.typeRef));
        sema.setConstant(sema.curNodeRef(), cstRef);
        return Result::Continue;
    }

    Result semaCompilerKindOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        SemaNodeView nodeView(sema, node.nodeArgRef);
        SWC_ASSERT(nodeView.typeRef.isValid());

        if (nodeView.type->isEnum())
        {
            const TypeRef     typeRef = nodeView.type->enumSym().underlyingTypeRef();
            const ConstantRef cstRef  = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), typeRef));
            nodeView.setCstRef(sema, cstRef);
            sema.setConstant(sema.curNodeRef(), cstRef);
            return Result::Continue;
        }

        return semaCompilerTypeOf(sema, node);
    }

    Result semaCompilerSizeOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        const SemaNodeView nodeView(sema, node.nodeArgRef);
        if (!nodeView.type)
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_sizeof, node.nodeArgRef);
        if (!nodeView.type->isCompleted(sema.ctx()))
            return sema.waitCompleted(nodeView.type, node.nodeArgRef);

        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), nodeView.type->sizeOf(sema.ctx())));
        return Result::Continue;
    }

    Result semaCompilerOffsetOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        const SemaNodeView nodeView(sema, node.nodeArgRef);
        if (!nodeView.sym || !nodeView.sym->isVariable())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_offsetof, node.nodeArgRef);

        const SymbolVariable& symVar = nodeView.sym->cast<SymbolVariable>();
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), symVar.offset()));
        return Result::Continue;
    }

    Result semaCompilerAlignOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        const SemaNodeView nodeView(sema, node.nodeArgRef);
        if (!nodeView.type)
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_alignof, node.nodeArgRef);

        if (!nodeView.type->isCompleted(sema.ctx()))
            return sema.waitCompleted(nodeView.type, node.nodeArgRef);

        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addInt(sema.ctx(), nodeView.type->alignOf(sema.ctx())));
        return Result::Continue;
    }

    Result semaCompilerNameOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        auto&              ctx = sema.ctx();
        const SemaNodeView nodeView(sema, node.nodeArgRef);

        if (nodeView.sym)
        {
            const std::string_view name  = nodeView.sym->name(ctx);
            const ConstantValue    value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        if (nodeView.type && nodeView.type->isTypeValue())
        {
            const Utf8          name  = sema.typeMgr().get(nodeView.type->typeRef()).toName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        auto        diag  = SemaError::report(sema, DiagnosticId::sema_err_failed_nameof, node.nodeArgRef);
        const auto& token = sema.token(node.srcViewRef(), node.tokRef());
        if (nodeView.cst && (token.id == TokenId::CompilerNameOf || token.id == TokenId::CompilerFullNameOf))
            diag.addElement(DiagnosticId::sema_help_nameof_instruction);
        diag.report(ctx);
        return Result::Stop;
    }

    Result semaCompilerFullNameOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        const auto&        ctx = sema.ctx();
        const SemaNodeView nodeView(sema, node.nodeArgRef);

        if (nodeView.sym)
        {
            const Utf8          name  = nodeView.sym->getFullScopedName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        return semaCompilerNameOf(sema, node);
    }

    Result semaCompilerStringOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        const auto&        ctx = sema.ctx();
        const SemaNodeView nodeView(sema, node.nodeArgRef);

        if (nodeView.cst)
        {
            const Utf8          name  = nodeView.cst->toString(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return Result::Continue;
        }

        return semaCompilerNameOf(sema, node);
    }

    Result semaCompilerDefined(Sema& sema, const AstCompilerCallUnary& node)
    {
        const auto&         ctx = sema.ctx();
        const SemaNodeView  nodeView(sema, node.nodeArgRef);
        const bool          isDefined = nodeView.sym != nullptr;
        const ConstantValue value     = ConstantValue::makeBool(ctx, isDefined);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
        return Result::Continue;
    }
}

Result AstCompilerCallUnary::semaPostNode(Sema& sema) const
{
    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::CompilerTypeOf:
            return semaCompilerTypeOf(sema, *this);
        case TokenId::CompilerKindOf:
            return semaCompilerKindOf(sema, *this);
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

        case TokenId::CompilerDeclType:
        case TokenId::CompilerRunes:
        case TokenId::CompilerIsConstExpr:
        case TokenId::CompilerInclude:
        case TokenId::CompilerSafety:
        case TokenId::CompilerHasTag:
        case TokenId::CompilerInject:
        case TokenId::CompilerLocation:
        case TokenId::CompilerForeignLib:
        case TokenId::CompilerLoad:
            return Result::SkipChildren;

        default:
            return SemaError::raiseInternal(sema, *this);
    }
}

Result AstCompilerFunc::semaPreDecl(Sema& sema)
{
    auto&        ctx = sema.ctx();
    const Token& tok = sema.token(srcViewRef(), tokRef());
    if (tok.id == TokenId::CompilerFuncMain)
    {
        if (!ctx.compiler().setMainFunc(this))
        {
            auto  diag = SemaError::report(sema, DiagnosticId::sema_err_already_defined, srcViewRef(), tokRef());
            auto& note = diag.addElement(DiagnosticId::sema_note_other_definition);
            note.setSeverity(DiagnosticSeverity::Note);
            note.addSpan(Diagnostic::tokenErrorLocation(ctx, ctx.compiler().mainFunc()->srcView(ctx), ctx.compiler().mainFunc()->tokRef()));
            diag.report(ctx);
            return Result::Stop;
        }
    }

    return Result::SkipChildren;
}

Result AstCompilerFunc::semaPreNode(Sema& sema)
{
    auto& ctx = sema.ctx();

    // Register a unique symbol for the compiler function
    const uint32_t id      = ctx.compiler().atomicId().fetch_add(1);
    const Utf8     name    = std::format("__func_{}", id);
    const auto     idRef   = sema.idMgr().addIdentifier(name);
    const auto     flags   = sema.frame().flagsForCurrentAccess();
    SymbolMap*     symMap  = SemaFrame::currentSymMap(sema);
    auto*          symFunc = Symbol::make<SymbolFunction>(ctx, this, tokRef(), idRef, flags);
    symMap->addSymbol(ctx, symFunc, true);
    sema.setSymbol(sema.curNodeRef(), symFunc);

    sema.pushScope(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstCompilerFunc::semaPostNode(Sema& sema)
{
    sema.popScope();
    return Result::Continue;
}

SWC_END_NAMESPACE()
