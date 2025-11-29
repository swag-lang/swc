#include "pch.h"
#include "Report/Diagnostic.h"
#include "Sema/Sema.h"
#include "Sema/TypeManager.h"

SWC_BEGIN_NAMESPACE()

void Sema::setReportArguments(Diagnostic& diag, SourceViewRef srcViewRef, TokenRef tokenRef) const
{
    const auto& srcView = compiler().srcView(srcViewRef);
    const auto& token   = srcView.token(tokenRef);
    diag.addArgument(Diagnostic::ARG_TOK, Diagnostic::tokenErrorString(*ctx_, ast_->srcView(), tokenRef));
    diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id), false);
    diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Token::toAFamily(token.id), false);
}

Diagnostic Sema::reportError(DiagnosticId id, AstNodeRef nodeRef)
{
    auto        diag    = Diagnostic::get(id, ast().srcView().fileRef());
    const auto& nodePtr = node(nodeRef);
    setReportArguments(diag, nodePtr.srcViewRef(), nodePtr.tokRef());

    const auto loc = node(nodeRef).location(ctx(), ast());
    diag.last().addSpan(loc, "");

    return diag;
}

Diagnostic Sema::reportError(DiagnosticId id, AstNodeRef nodeRef, SourceViewRef srcViewRef, TokenRef tokenRef)
{
    auto diag = Diagnostic::get(id, ast().srcView().fileRef());
    setReportArguments(diag, srcViewRef, tokenRef);

    const auto loc = node(nodeRef).location(ctx(), ast());
    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);

    const auto& srcView = compiler().srcView(srcViewRef);
    diag.last().addSpan(Diagnostic::tokenErrorLocation(ctx(), srcView, tokenRef), "");

    return diag;
}

Diagnostic Sema::reportError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokenRef)
{
    auto diag = Diagnostic::get(id, ast().srcView().fileRef());
    setReportArguments(diag, srcViewRef, tokenRef);

    const auto& srcView = compiler().srcView(srcViewRef);
    diag.last().addSpan(Diagnostic::tokenErrorLocation(ctx(), srcView, tokenRef), "");

    return diag;
}

void Sema::raiseError(DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokenRef)
{
    const auto diag = reportError(id, srcViewRef, tokenRef);
    diag.report(ctx());
}

void Sema::raiseError(DiagnosticId id, AstNodeRef nodeRef)
{
    const auto diag = reportError(id, nodeRef);
    diag.report(ctx());
}

void Sema::raiseInvalidType(AstNodeRef nodeRef, TypeInfoRef srcTypeRef, TypeInfoRef targetTypeRef)
{
    auto diag = reportError(DiagnosticId::sema_err_invalid_type, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, typeMgr().typeToString(srcTypeRef));
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, typeMgr().typeToString(targetTypeRef));
    diag.report(ctx());
}

void Sema::raiseCannotCast(AstNodeRef nodeRef, TypeInfoRef srcTypeRef, TypeInfoRef targetTypeRef)
{
    auto diag = reportError(DiagnosticId::sema_err_cannot_cast, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    diag.report(ctx());
}

void Sema::raiseLiteralOverflow(AstNodeRef nodeRef, TypeInfoRef targetTypeRef)
{
    auto diag = reportError(DiagnosticId::sema_err_literal_overflow, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    diag.report(ctx());
}

void Sema::raiseExprNotConst(AstNodeRef nodeRef)
{
    return raiseError(DiagnosticId::sema_err_expr_not_const, nodeRef);
}

void Sema::raiseInternalError(const AstNode& node)
{
    raiseError(DiagnosticId::sema_err_internal, node.srcViewRef(), node.tokRef());
}

SWC_END_NAMESPACE()
