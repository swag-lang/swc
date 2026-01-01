#include "pch.h"

#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/Version.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Report/Logger.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Core/Sema.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/TypeManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstCompilerExpression::semaPostNode(Sema& sema)
{
    if (SemaCheck::isConstant(sema, nodeExprRef) != Result::Success)
        return AstVisitStepResult::Stop;
    sema.semaInherit(*this, nodeExprRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerIf::semaPreDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return AstVisitStepResult::Continue;

    if (childRef == nodeIfBlockRef)
    {
        SemaFrame       frame    = sema.frame();
        SemaCompilerIf* parentIf = frame.compilerIf();
        SemaCompilerIf* ifFrame  = sema.compiler().allocate<SemaCompilerIf>();
        ifFrame->parent          = parentIf;

        frame.setCompilerIf(ifFrame);
        sema.setPayload(nodeIfBlockRef, ifFrame);
        sema.pushFrame(frame);
        return AstVisitStepResult::Continue;
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

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerIf::semaPostDecl(Sema& sema) const
{
    if (nodeElseBlockRef.isValid())
        sema.popFrame();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerIf::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return AstVisitStepResult::Continue;

    const ConstantValue& constant = sema.constantOf(nodeConditionRef);
    if (!constant.isBool())
    {
        SemaError::raiseInvalidType(sema, nodeConditionRef, constant.typeRef(), sema.typeMgr().typeBool());
        return AstVisitStepResult::Stop;
    }

    if (childRef == nodeIfBlockRef && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlockRef && constant.getBool())
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerIf::semaPostNode(Sema& sema) const
{
    // Condition must already be a constant at this point
    SWC_ASSERT(sema.hasConstant(nodeConditionRef));

    const ConstantValue& constant      = sema.constantOf(nodeConditionRef);
    const bool           takenIfBranch = constant.getBool();

    // The block that will be ignored
    const AstNodeRef& ignoredBlockRef = takenIfBranch ? nodeElseBlockRef : nodeIfBlockRef;
    if (!ignoredBlockRef.isValid())
        return AstVisitStepResult::Continue;

    // Retrieve the SemaCompilerIf payload
    if (sema.hasPayload(ignoredBlockRef))
    {
        const SemaCompilerIf* ignoredIfData = sema.payload<SemaCompilerIf>(ignoredBlockRef);
        if (!ignoredIfData)
            return AstVisitStepResult::Continue;

        for (Symbol* sym : ignoredIfData->symbols)
            sym->setIgnored(sema.ctx());
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerDiagnostic::semaPostNode(Sema& sema) const
{
    SWC_ASSERT(sema.hasConstant(nodeArgRef));

    const Token&         tok      = sema.token(srcViewRef(), tokRef());
    const ConstantValue& constant = sema.constantOf(nodeArgRef);
    switch (tok.id)
    {
        case TokenId::CompilerError:
        case TokenId::CompilerWarning:
            if (!constant.isString())
            {
                SemaError::raiseInvalidType(sema, nodeArgRef, constant.typeRef(), sema.typeMgr().typeString());
                return AstVisitStepResult::Stop;
            }
            break;

        case TokenId::CompilerAssert:
            if (!constant.isBool())
            {
                SemaError::raiseInvalidType(sema, nodeArgRef, constant.typeRef(), sema.typeMgr().typeBool());
                return AstVisitStepResult::Stop;
            }
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
            return AstVisitStepResult::Stop;
        }

        case TokenId::CompilerWarning:
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_warn_compiler_warning, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString(), false);
            diag.report(sema.ctx());
            return AstVisitStepResult::Continue;
        }

        case TokenId::CompilerPrint:
        {
            const auto& ctx = sema.ctx();
            ctx.global().logger().lock();
            Logger::print(ctx, constant.toString(ctx));
            Logger::print(ctx, "\n");
            ctx.global().logger().unlock();
            return AstVisitStepResult::Continue;
        }

        case TokenId::CompilerAssert:
            if (!constant.getBool())
            {
                SemaError::raise(sema, DiagnosticId::sema_err_compiler_assert, srcViewRef(), tokRef());
                return AstVisitStepResult::Stop;
            }
            break;

        default:
            break;
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerLiteral::semaPostNode(Sema& sema) const
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

        case TokenId::CompilerBuildCfg:
        case TokenId::CompilerModule:
        case TokenId::CompilerCallerFunction:
        case TokenId::CompilerCallerLocation:
        case TokenId::CompilerArch:
        case TokenId::CompilerCpu:
        case TokenId::CompilerSwagOs:
        case TokenId::CompilerBackend:
        case TokenId::CompilerScopeName:
        case TokenId::CompilerCurLocation:
            return AstVisitStepResult::Continue;

        default:
            SWC_UNREACHABLE();
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerGlobal::semaPreDecl(Sema& sema) const
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
        default:
            break;
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerGlobal::semaPreNode(Sema& sema) const
{
    switch (mode)
    {
        case Mode::AccessPublic:
        case Mode::AccessInternal:
        case Mode::AccessPrivate:
            return semaPreDecl(sema);
        default:
            break;
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerGlobal::semaPostNode(Sema& sema) const
{
    switch (mode)
    {
        case Mode::Skip:
        case Mode::SkipFmt:
        case Mode::Generated:
            return AstVisitStepResult::Continue;

        case Mode::Export:
        case Mode::AttributeList:
        case Mode::Namespace:
        case Mode::CompilerIf:
        case Mode::Using:
            return AstVisitStepResult::SkipChildren;
        default:
            break;
    }

    return AstVisitStepResult::Continue;
}

namespace
{
    AstVisitStepResult semaCompilerTypeOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        SemaNodeView nodeView(sema, node.nodeArgRef);
        SWC_ASSERT(nodeView.typeRef.isValid());

        if (nodeView.cstRef.isValid())
        {
            const ConstantRef newCstRef = sema.cstMgr().concretizeConstant(sema, nodeView.nodeRef, nodeView.cstRef, TypeInfo::Sign::Unknown);
            if (newCstRef.isInvalid())
                return AstVisitStepResult::Stop;
            nodeView.setCstRef(sema, newCstRef);
        }

        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), nodeView.typeRef));
        sema.setConstant(sema.curNodeRef(), cstRef);
        return AstVisitStepResult::Continue;
    }

    AstVisitStepResult semaCompilerKindOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        SemaNodeView nodeView(sema, node.nodeArgRef);
        SWC_ASSERT(nodeView.typeRef.isValid());

        if (nodeView.type->isEnum())
        {
            const TypeRef     typeRef = nodeView.type->enumSym().underlyingTypeRef();
            const ConstantRef cstRef  = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), typeRef));
            nodeView.setCstRef(sema, cstRef);
            sema.setConstant(sema.curNodeRef(), cstRef);
            return AstVisitStepResult::Continue;
        }

        return semaCompilerTypeOf(sema, node);
    }

    AstVisitStepResult semaCompilerSizeOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        SemaNodeView nodeView(sema, node.nodeArgRef);
        if (!nodeView.type)
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_sizeof, node.nodeArgRef);
            return AstVisitStepResult::Stop;
        }

        if (nodeView.type->isTypeValue())
            nodeView.type = &sema.typeMgr().get(nodeView.type->typeRef());
        if (!nodeView.type->isCompleted(sema.ctx()))
            return sema.waitCompleted(nodeView.type, node.nodeArgRef);

        const uint64_t      val = nodeView.type->sizeOf(sema.ctx());
        const ApsInt        value{val, ApsInt::maxBitWidth()};
        const ConstantValue cstVal = ConstantValue::makeIntUnsized(sema.ctx(), value, TypeInfo::Sign::Unknown);
        const ConstantRef   cstRef = sema.cstMgr().addConstant(sema.ctx(), cstVal);
        nodeView.setCstRef(sema, cstRef);
        sema.setConstant(sema.curNodeRef(), cstRef);
        return AstVisitStepResult::Continue;
    }

    AstVisitStepResult semaCompilerOffsetOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        SemaNodeView nodeView(sema, node.nodeArgRef);
        if (!nodeView.sym || !nodeView.sym->isVariable())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_offsetof, node.nodeArgRef);
            return AstVisitStepResult::Stop;
        }

        const SymbolVariable& symVar = nodeView.sym->cast<SymbolVariable>();
        const uint64_t        val    = symVar.offset();
        const ApsInt          value{val, ApsInt::maxBitWidth()};
        const ConstantValue   cstVal = ConstantValue::makeIntUnsized(sema.ctx(), value, TypeInfo::Sign::Unknown);
        const ConstantRef     cstRef = sema.cstMgr().addConstant(sema.ctx(), cstVal);
        nodeView.setCstRef(sema, cstRef);
        sema.setConstant(sema.curNodeRef(), cstRef);
        return AstVisitStepResult::Continue;
    }

    AstVisitStepResult semaCompilerAlignOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        SemaNodeView nodeView(sema, node.nodeArgRef);
        if (!nodeView.type)
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_alignof, node.nodeArgRef);
            return AstVisitStepResult::Stop;
        }

        if (nodeView.type->isTypeValue())
            nodeView.type = &sema.typeMgr().get(nodeView.type->typeRef());
        if (!nodeView.type->isCompleted(sema.ctx()))
            return sema.waitCompleted(nodeView.type, node.nodeArgRef);

        const uint64_t      val = nodeView.type->alignOf(sema.ctx());
        const ApsInt        value{val, ApsInt::maxBitWidth()};
        const ConstantValue cstVal = ConstantValue::makeIntUnsized(sema.ctx(), value, TypeInfo::Sign::Unknown);
        const ConstantRef   cstRef = sema.cstMgr().addConstant(sema.ctx(), cstVal);
        nodeView.setCstRef(sema, cstRef);
        sema.setConstant(sema.curNodeRef(), cstRef);
        return AstVisitStepResult::Continue;
    }

    AstVisitStepResult semaCompilerNameOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        auto&              ctx = sema.ctx();
        const SemaNodeView nodeView(sema, node.nodeArgRef);

        if (nodeView.sym)
        {
            const std::string_view name  = nodeView.sym->name(ctx);
            const ConstantValue    value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return AstVisitStepResult::Continue;
        }

        if (nodeView.type && nodeView.type->isTypeValue())
        {
            const Utf8          name  = sema.typeMgr().get(nodeView.type->typeRef()).toName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return AstVisitStepResult::Continue;
        }

        SemaError::raise(sema, DiagnosticId::sema_err_failed_nameof, node.nodeArgRef);
        return AstVisitStepResult::Stop;
    }

    AstVisitStepResult semaCompilerStringOf(Sema& sema, const AstCompilerCallUnary& node)
    {
        auto&              ctx = sema.ctx();
        const SemaNodeView nodeView(sema, node.nodeArgRef);

        if (nodeView.sym)
        {
            const Utf8          name  = nodeView.sym->getFullScopedName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return AstVisitStepResult::Continue;
        }

        if (nodeView.cst)
        {
            const Utf8          name  = nodeView.cst->toString(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return AstVisitStepResult::Continue;
        }

        if (nodeView.type && nodeView.type->isTypeValue())
        {
            const Utf8          name  = sema.typeMgr().get(nodeView.type->typeRef()).toName(ctx);
            const ConstantValue value = ConstantValue::makeString(ctx, name);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
            return AstVisitStepResult::Continue;
        }

        SemaError::raise(sema, DiagnosticId::sema_err_failed_stringof, node.nodeArgRef);
        return AstVisitStepResult::Stop;
    }

    AstVisitStepResult semaCompilerDefined(Sema& sema, const AstCompilerCallUnary& node)
    {
        const auto&         ctx = sema.ctx();
        const SemaNodeView  nodeView(sema, node.nodeArgRef);
        const bool          isDefined = nodeView.sym != nullptr;
        const ConstantValue value     = ConstantValue::makeBool(ctx, isDefined);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, value));
        return AstVisitStepResult::Continue;
    }
}

AstVisitStepResult AstCompilerCallUnary::semaPostNode(Sema& sema) const
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
            return AstVisitStepResult::SkipChildren;

        default:
            SemaError::raiseInternal(sema, *this);
            return AstVisitStepResult::Stop;
    }
}

SWC_END_NAMESPACE()
