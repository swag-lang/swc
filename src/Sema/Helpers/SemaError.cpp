#include "pch.h"

#include "Core/Utf8Helper.h"
#include "Main/CompilerInstance.h"
#include "Report/Diagnostic.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"
#include "SemaNodeView.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    void setReportArguments(Sema& sema, Diagnostic& diag, SourceViewRef srcViewRef, TokenRef tokRef, const Symbol* sym = nullptr)
    {
        const auto&       ctx     = sema.ctx();
        const SourceView& srcView = sema.compiler().srcView(srcViewRef);
        const Token&      token   = srcView.token(tokRef);
        const Utf8&       tokStr  = Diagnostic::tokenErrorString(ctx, sema.ast().srcView(), tokRef);

        diag.addArgument(Diagnostic::ARG_TOK, tokStr);
        diag.addArgument(Diagnostic::ARG_TOK_RAW, tokStr, false);
        diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id), false);
        diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(token.id)), false);

        if (sym)
        {
            diag.addArgument(Diagnostic::ARG_SYM, sym->name(ctx));
            diag.addArgument(Diagnostic::ARG_SYM_FAM, sym->toFamily(), false);
            diag.addArgument(Diagnostic::ARG_A_SYM_FAM, Utf8Helper::addArticleAAn(sym->toFamily()), false);
        }
    }
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, AstNodeRef nodeRef)
{
    const SemaNodeView nodeView(sema, nodeRef);
    auto               diag = Diagnostic::get(id, sema.ast().srcView().fileRef());
    setReportArguments(sema, diag, nodeView.node->srcViewRef(), nodeView.node->tokRef(), nodeView.sym);
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
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_invalid_type, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    diag.report(ctx);
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

void SemaError::raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_already_defined, symbol->srcViewRef(), symbol->tokRef());
    diag.addNote(DiagnosticId::sema_note_other_definition);
    diag.last().addSpan(otherSymbol->loc(ctx));
    diag.report(ctx);
}

void SemaError::raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_ghosting, symbol->srcViewRef(), symbol->tokRef());
    diag.addNote(DiagnosticId::sema_note_other_definition);
    diag.last().addSpan(otherSymbol->loc(ctx));
    diag.report(ctx);
}

void SemaError::raiseAmbiguousSymbol(Sema& sema, SourceViewRef srcViewRef, TokenRef tokRef, std::span<const Symbol*> symbols)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_ambiguous_symbol, srcViewRef, tokRef);
    for (const auto other : symbols)
    {
        diag.addNote(DiagnosticId::sema_note_could_be);
        diag.last().addSpan(other->loc(ctx));
    }
    diag.report(ctx);
}

SWC_END_NAMESPACE()
