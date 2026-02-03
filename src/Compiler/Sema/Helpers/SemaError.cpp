#include "pch.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    SourceCodeRange getNodeCodeRange(Sema& sema, AstNodeRef atNodeRef, SemaError::ReportLocation location)
    {
        const auto& ctx  = sema.ctx();
        const auto& node = sema.node(atNodeRef);
        switch (location)
        {
            case SemaError::ReportLocation::Token:
                return node.codeRange(ctx);
            case SemaError::ReportLocation::Children:
                return node.codeRangeWithChildren(ctx, sema.ast());
        }

        SWC_UNREACHABLE();
    }

    void setReportArguments(Sema& sema, Diagnostic& diag, const SourceCodeRef& codeRange)
    {
        SWC_ASSERT(codeRange.isValid());

        const auto&       ctx     = sema.ctx();
        const SourceView& srcView = sema.srcView(codeRange.srcViewRef);
        const Token&      token   = srcView.token(codeRange.tokRef);
        const Utf8&       tokStr  = Diagnostic::tokenErrorString(ctx, codeRange);

        diag.addArgument(Diagnostic::ARG_TOK, tokStr);
        diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id));
        diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(token.id)));
    }

    void setReportArguments(Sema& sema, Diagnostic& diag, const Symbol* sym)
    {
        if (!sym)
            return;

        diag.addArgument(Diagnostic::ARG_SYM, sym->name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_SYM_FAM, sym->toFamily());
        diag.addArgument(Diagnostic::ARG_A_SYM_FAM, Utf8Helper::addArticleAAn(sym->toFamily()));
    }
}

void SemaError::addSpan(Sema& sema, DiagnosticElement& element, AstNodeRef atNodeRef, const Utf8& message, DiagnosticSeverity severity)
{
    const SourceCodeRange codeRange = sema.node(atNodeRef).codeRangeWithChildren(sema.ctx(), sema.ast());
    element.addSpan(codeRange, message, severity);
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, const SourceCodeRef& atCodeRef)
{
    auto              diag    = Diagnostic::get(id, sema.ast().srcView().fileRef());
    const SourceView& srcView = sema.srcView(atCodeRef.srcViewRef);
    diag.last().addSpan(srcView.tokenCodeRange(sema.ctx(), atCodeRef.tokRef), "", DiagnosticSeverity::Error);

    setReportArguments(sema, diag, atCodeRef);
    return diag;
}

Result SemaError::raise(Sema& sema, DiagnosticId id, const SourceCodeRef& atCodeRef)
{
    const auto diag = report(sema, id, atCodeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, AstNodeRef atNodeRef, ReportLocation location)
{
    auto diag = Diagnostic::get(id, sema.ast().srcView().fileRef());
    diag.last().addSpan(getNodeCodeRange(sema, atNodeRef, location), "", DiagnosticSeverity::Error);

    const SemaNodeView nodeView(sema, atNodeRef);
    setReportArguments(sema, diag, nodeView.node->codeRef());
    setReportArguments(sema, diag, nodeView.sym);

    return diag;
}

Result SemaError::raise(Sema& sema, DiagnosticId id, AstNodeRef atNodeRef, ReportLocation location)
{
    const auto diag = report(sema, id, atNodeRef, location);
    diag.report(sema.ctx());
    return Result::Error;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, const Symbol& atSymbol)
{
    return report(sema, id, atSymbol.codeRef());
}

Result SemaError::raise(Sema& sema, DiagnosticId id, const Symbol& atSymbol)
{
    const auto diag = report(sema, id, atSymbol);
    diag.report(sema.ctx());
    return Result::Error;
}

SWC_END_NAMESPACE();
