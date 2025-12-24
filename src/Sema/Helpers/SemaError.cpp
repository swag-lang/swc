#include "pch.h"
#include "Sema/Helpers/SemaError.h"
#include "Main/CompilerInstance.h"
#include "Report/Diagnostic.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void setReportArguments(Sema& sema, Diagnostic& diag, SourceViewRef srcViewRef, TokenRef tokRef)
    {
        const SourceView& srcView = sema.compiler().srcView(srcViewRef);
        const Token&      token   = srcView.token(tokRef);
        const Utf8&       tokStr  = Diagnostic::tokenErrorString(sema.ctx(), sema.ast().srcView(), tokRef);
        diag.addArgument(Diagnostic::ARG_TOK, tokStr);
        diag.addArgument(Diagnostic::ARG_TOK_RAW, tokStr, false);
        diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id), false);
        diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Token::toAFamily(token.id), false);
    }
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, AstNodeRef nodeRef)
{
    auto           diag    = Diagnostic::get(id, sema.ast().srcView().fileRef());
    const AstNode& nodePtr = sema.node(nodeRef);
    setReportArguments(sema, diag, nodePtr.srcViewRef(), nodePtr.tokRef());

    const SourceCodeLocation loc = sema.node(nodeRef).locationWithChildren(sema.ctx(), sema.ast());
    diag.last().addSpan(loc, "");

    return diag;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef)
{
    auto diag = Diagnostic::get(id, sema.ast().srcView().fileRef());
    setReportArguments(sema, diag, srcViewRef, tokRef);

    const auto& srcView = sema.compiler().srcView(srcViewRef);
    diag.last().addSpan(Diagnostic::tokenErrorLocation(sema.ctx(), srcView, tokRef), "");

    return diag;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef, AstNodeRef nodeSpanRef)
{
    auto                     diag = report(sema, id, srcViewRef, tokRef);
    const SourceCodeLocation loc  = sema.node(nodeSpanRef).locationWithChildren(sema.ctx(), sema.ast());
    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);
    return diag;
}

void SemaError::raise(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef)
{
    const auto diag = report(sema, id, srcViewRef, tokRef);
    diag.report(sema.ctx());
}

void SemaError::raise(Sema& sema, DiagnosticId id, AstNodeRef nodeRef)
{
    const auto diag = report(sema, id, nodeRef);
    diag.report(sema.ctx());
}

void SemaError::raiseInvalidType(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_invalid_type, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, sema.typeMgr().typeToName(sema.ctx(), srcTypeRef));
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, sema.typeMgr().typeToName(sema.ctx(), targetTypeRef));
    diag.report(sema.ctx());
}

Diagnostic SemaError::reportCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_cannot_cast, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    return diag;
}

void SemaError::raiseCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    const auto diag = reportCannotCast(sema, nodeRef, srcTypeRef, targetTypeRef);
    diag.report(sema.ctx());
}

void SemaError::raiseLiteralOverflow(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_literal_overflow, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, literal.toString(sema.ctx()));
    diag.report(sema.ctx());
}

void SemaError::raiseLiteralTooBig(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal)
{
    auto diag = report(sema, DiagnosticId::sema_err_literal_too_big, nodeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, literal.toString(sema.ctx()));
    diag.report(sema.ctx());
}

void SemaError::raiseDivZero(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_division_zero, nodeOp.srcViewRef(), nodeOp.tokRef(), nodeValueRef);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    diag.report(sema.ctx());
}

void SemaError::raiseExprNotConst(Sema& sema, AstNodeRef nodeRef)
{
    return raise(sema, DiagnosticId::sema_err_expr_not_const, nodeRef);
}

void SemaError::raiseBinaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_binary_operand_type, nodeOp.srcViewRef(), nodeOp.tokRef(), nodeValueRef);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    diag.report(sema.ctx());
}

void SemaError::raiseInternal(Sema& sema, const AstNode& node)
{
    raise(sema, DiagnosticId::sema_err_internal, node.srcViewRef(), node.tokRef());
}

void SemaError::raiseSymbolAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    auto&                    ctx  = sema.ctx();
    const auto               diag = report(sema, DiagnosticId::sema_err_already_defined, symbol->srcViewRef(), symbol->tokRef());
    const SourceCodeLocation loc  = otherSymbol->loc(ctx);
    diag.last().addSpan(loc, DiagnosticId::sema_note_other_definition);
    diag.report(ctx);
}

SWC_END_NAMESPACE()
