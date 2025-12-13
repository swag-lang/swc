#include "pch.h"

#include "Constant/ConstantManager.h"
#include "Main/Global.h"
#include "Main/Version.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"
#include "Report/DiagnosticDef.h"
#include "Report/Logger.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Sema.h"
#include "Sema/SemaInfo.h"
#include "Sema/Type/TypeManager.h"
#include "SemaCast.h"
#include "SemaNodeView.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstCompilerExpression::semaPostNode(Sema& sema)
{
    if (!sema.hasConstant(nodeExprRef))
    {
        sema.raiseExprNotConst(nodeExprRef);
        return AstVisitStepResult::Stop;
    }

    sema.semaInherit(*this, nodeExprRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerIf::semaPreChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return AstVisitStepResult::Continue;

    const ConstantValue& constant = sema.constantOf(nodeConditionRef);
    if (!constant.isBool())
    {
        sema.raiseInvalidType(nodeConditionRef, constant.typeRef(), sema.typeMgr().getTypeBool());
        return AstVisitStepResult::Stop;
    }

    if (childRef == nodeIfBlockRef && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlockRef && constant.getBool())
        return AstVisitStepResult::SkipChildren;

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
                sema.raiseInvalidType(nodeArgRef, constant.typeRef(), sema.typeMgr().getTypeString());
                return AstVisitStepResult::Stop;
            }
            break;

        case TokenId::CompilerAssert:
            if (!constant.isBool())
            {
                sema.raiseInvalidType(nodeArgRef, constant.typeRef(), sema.typeMgr().getTypeBool());
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
            auto diag = sema.reportError(DiagnosticId::sema_err_compiler_error, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_BECAUSE, constant.getString(), false);
            diag.report(sema.ctx());
            return AstVisitStepResult::Stop;
        }

        case TokenId::CompilerWarning:
        {
            auto diag = sema.reportError(DiagnosticId::sema_warn_compiler_warning, srcViewRef(), tokRef());
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
                sema.raiseError(DiagnosticId::sema_err_compiler_assert, srcViewRef(), tokRef());
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
            const ConstantValue&     val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(loc.line), 0);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcVersion:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_VERSION), 0);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcRevision:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_REVISION), 0);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerSwcBuildNum:
        {
            const ConstantValue& val = ConstantValue::makeInt(ctx, ApsInt::makeUnsigned(SWC_BUILD_NUM), 0);
            sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, val));
            break;
        }

        case TokenId::CompilerBuildCfg:
        case TokenId::CompilerModule:
        case TokenId::CompilerCallerFunction:
        case TokenId::CompilerCallerLocation:
        case TokenId::CompilerOs:
        case TokenId::CompilerArch:
        case TokenId::CompilerCpu:
        case TokenId::CompilerSwagOs:
        case TokenId::CompilerBackend:
        case TokenId::CompilerScopeName:
        case TokenId::CompilerCurLocation:
            sema.raiseInternalError(*this);
            return AstVisitStepResult::Stop;

        default:
            SWC_UNREACHABLE();
    }

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstCompilerGlobal::semaPostNode(Sema& sema) const
{
    switch (mode)
    {
        case Mode::AccessPublic:
            sema.frame().defaultAccess = SymbolAccess::Public;
            break;
        case Mode::AccessInternal:
            sema.frame().defaultAccess = SymbolAccess::Internal;
            break;
        case Mode::AccessPrivate:
            sema.frame().defaultAccess = SymbolAccess::Private;
            break;

        case Mode::Skip:
        case Mode::SkipFmt:
        case Mode::Generated:
        case Mode::Export:
        case Mode::AttributeList:
        case Mode::Namespace:
        case Mode::CompilerIf:
        case Mode::Using:
            sema.raiseInternalError(*this);
            return AstVisitStepResult::Continue;
    };

    return AstVisitStepResult::Continue;
}

namespace
{
    AstVisitStepResult semaCompilerTypeOf(const AstCompilerCallUnary& node, Sema& sema)
    {
        SemaNodeView nodeView(sema, node.nodeArgRef);
        SWC_ASSERT(nodeView.typeRef.isValid());

        if (nodeView.cstRef.isValid())
        {
            bool overflow;
            nodeView.cstRef = SemaCast::concretizeConstant(sema, nodeView.cstRef, overflow);
            if (overflow)
            {
                sema.raiseLiteralTooBig(node.nodeArgRef, sema.cstMgr().get(nodeView.cstRef));
                return AstVisitStepResult::Stop;
            }

            nodeView.typeRef = sema.cstMgr().get(nodeView.cstRef).typeRef();
        }

        const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeInfo(sema.ctx(), nodeView.typeRef));
        sema.setConstant(sema.curNodeRef(), cstRef);
        return AstVisitStepResult::Continue;
    }
}

AstVisitStepResult AstCompilerCallUnary::semaPostNode(Sema& sema) const
{
    const Token& tok = sema.token(srcViewRef(), tokRef());
    switch (tok.id)
    {
        case TokenId::CompilerTypeOf:
            return semaCompilerTypeOf(*this, sema);

        default:
            sema.raiseInternalError(*this);
            return AstVisitStepResult::Stop;
    }
}

SWC_END_NAMESPACE()
