#include "pch.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Main/CompilerInstance.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void setReportArguments(Sema& sema, Diagnostic& diag, const SourceCodeRef& loc)
    {
        SWC_ASSERT(loc.srcViewRef.isValid());
        SWC_ASSERT(loc.tokRef.isValid());

        const auto&       ctx     = sema.ctx();
        const SourceView& srcView = sema.compiler().srcView(loc.srcViewRef);
        const Token&      token   = srcView.token(loc.tokRef);
        const Utf8&       tokStr  = Diagnostic::tokenErrorString(ctx, sema.ast().srcView(), loc.tokRef);

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

    void addSpanWithChildren(DiagnosticElement& element, Sema& sema, AstNodeRef nodeRef, const Utf8& message = "", DiagnosticSeverity severity = DiagnosticSeverity::Note)
    {
        const SourceCodeRange codeRange = sema.node(nodeRef).codeRangeWithChildren(sema.ctx(), sema.ast());
        element.addSpan(codeRange, message, severity);
    }
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, AstNodeRef nodeRef)
{
    auto diag = Diagnostic::get(id, sema.ast().srcView().fileRef());

    const SemaNodeView nodeView(sema, nodeRef);
    setReportArguments(sema, diag, nodeView.node->codeRef());
    setReportArguments(sema, diag, nodeView.sym);
    addSpanWithChildren(diag.last(), sema, nodeRef);

    return diag;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, const SourceCodeRef& codeRef)
{
    auto diag = Diagnostic::get(id, sema.ast().srcView().fileRef());
    setReportArguments(sema, diag, codeRef);

    const auto& srcView = sema.compiler().srcView(codeRef.srcViewRef);
    diag.last().addSpan(Diagnostic::tokenErrorLocation(sema.ctx(), srcView, codeRef.tokRef), "");

    return diag;
}

Result SemaError::raise(Sema& sema, DiagnosticId id, const SourceCodeRef& codeRef)
{
    const auto diag = report(sema, id, codeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raise(Sema& sema, DiagnosticId id, AstNodeRef nodeRef)
{
    const auto diag = report(sema, id, nodeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Diagnostic SemaError::reportCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_cannot_cast, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    return diag;
}

Result SemaError::raiseInvalidType(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_invalid_type, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseRequestedTypeFam(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_expected_type_fam, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    const TypeInfo& ty = sema.typeMgr().get(targetTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE_FAM, ty.toFamily(ctx));
    diag.addArgument(Diagnostic::ARG_A_REQUESTED_TYPE_FAM, Utf8Helper::addArticleAAn(ty.toFamily(ctx)));
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseLiteralOverflow(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_literal_overflow, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, literal.toString(sema.ctx()));
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseExprNotConst(Sema& sema, AstNodeRef nodeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_expr_not_const, nodeRef);

    struct Context
    {
        Sema*      sema;
        AstNodeRef nodeRef;
        AstNodeRef lowest;
    };

    AstNodeRef lowest = AstNodeRef::invalid();
    Ast::visit(sema.ast(), nodeRef, [&](AstNodeRef childRef, const AstNode&) {
        if (childRef == nodeRef)
            return Ast::VisitResult::Continue;

        const SemaNodeView nodeView{sema, childRef};
        if (nodeView.cstRef.isInvalid())
        {
            lowest = childRef;
            return Ast::VisitResult::Continue;
        }

        return Ast::VisitResult::Skip;
    });

    if (lowest.isValid())
    {
        diag.addNote(DiagnosticId::sema_note_not_constant);
        addSpanWithChildren(diag.last(), sema, lowest);
    }

    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseBinaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_binary_operand_type, nodeOp.codeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpanWithChildren(diag.last(), sema, nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseUnaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_unary_operand_type, nodeOp.codeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpanWithChildren(diag.last(), sema, nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseInternal(Sema& sema, const AstNode& node)
{
    return raise(sema, DiagnosticId::sema_err_internal, node.codeRef());
}

Result SemaError::raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_already_defined, symbol->codeRef());
    diag.addNote(DiagnosticId::sema_note_other_definition);
    diag.last().addSpan(otherSymbol->codeRange(ctx));
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_ghosting, symbol->codeRef());
    diag.addNote(DiagnosticId::sema_note_other_definition);
    diag.last().addSpan(otherSymbol->codeRange(ctx));
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseAmbiguousSymbol(Sema& sema, AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_ambiguous_symbol, nodeRef);
    diag.addArgument(Diagnostic::ARG_SYM, symbols.front()->name(ctx));

    for (const auto other : symbols)
    {
        diag.addNote(DiagnosticId::sema_note_could_be);
        diag.last().addSpan(other->codeRange(ctx));
    }

    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseLiteralTooBig(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal)
{
    auto diag = report(sema, DiagnosticId::sema_err_literal_too_big, nodeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, literal.toString(sema.ctx()));
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseDivZero(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef)
{
    const auto diag = report(sema, DiagnosticId::sema_err_division_zero, nodeOp.codeRef());
    addSpanWithChildren(diag.last(), sema, nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raisePointerArithmeticValuePointer(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_pointer_arithmetic_value_ptr, nodeOp.codeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpanWithChildren(diag.last(), sema, nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raisePointerArithmeticVoidPointer(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_pointer_arithmetic_void_ptr, nodeOp.codeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpanWithChildren(diag.last(), sema, nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseInvalidOpEnum(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_invalid_op_enum, nodeOp.codeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpanWithChildren(diag.last(), sema, nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseTypeNotIndexable(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_type_not_indexable, nodeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseIndexOutOfRange(Sema& sema, int64_t index, size_t maxCount, AstNodeRef nodeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_index_out_of_range, nodeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, index);
    diag.addArgument(Diagnostic::ARG_COUNT, maxCount);
    addSpanWithChildren(diag.last(), sema, nodeRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

SWC_END_NAMESPACE();
