#include "pch.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

Result SemaError::raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    TaskContext& ctx = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_already_defined, symbol->codeRef());
    diag.addNote(DiagnosticId::sema_note_other_definition);
    diag.last().addSpan(otherSymbol->codeRange(ctx));
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    TaskContext& ctx = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_ghosting, symbol->codeRef());
    diag.addNote(DiagnosticId::sema_note_other_definition);
    diag.last().addSpan(otherSymbol->codeRange(ctx));
    diag.report(ctx);
    return Result::Error;
}

Diagnostic SemaError::reportCannotCast(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_cannot_cast, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    return diag;
}

Result SemaError::raiseInvalidType(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    TaskContext& ctx = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_invalid_type, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseInvalidRangeType(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef)
{
    TaskContext& ctx = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_invalid_range_type, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseRequestedTypeFam(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    TaskContext& ctx = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_expected_type_fam, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    const TypeInfo& ty = sema.typeMgr().get(targetTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE_FAM, ty.toFamily(ctx));
    diag.addArgument(Diagnostic::ARG_A_REQUESTED_TYPE_FAM, Utf8Helper::addArticleAAn(ty.toFamily(ctx)));
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseLiteralOverflow(Sema& sema, AstNodeRef atNodeRef, const ConstantValue& literal, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_literal_overflow, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    diag.addArgument(Diagnostic::ARG_VALUE, literal.toString(sema.ctx()));
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseExprNotConst(Sema& sema, AstNodeRef atNodeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_expr_not_const, atNodeRef, ReportLocation::Children);

    AstNodeRef lowest = AstNodeRef::invalid();
    Ast::visit(sema.ast(), atNodeRef, [&](AstNodeRef childRef, const AstNode&) {
        if (childRef == atNodeRef)
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
        addSpan(sema, diag.last(), lowest);
    }

    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseBinaryOperandType(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef leftTypeRef, TypeRef rightTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_binary_operand_type, atNodeRef, ReportLocation::Token);
    diag.addArgument(Diagnostic::ARG_LEFT, leftTypeRef);
    diag.addArgument(Diagnostic::ARG_RIGHT, rightTypeRef);
    addSpan(sema, diag.last(), nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseUnaryOperandType(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_unary_operand_type, atNodeRef, ReportLocation::Token);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpan(sema, diag.last(), nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseAmbiguousSymbol(Sema& sema, AstNodeRef atNodeRef, std::span<const Symbol*> symbols)
{
    TaskContext& ctx = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_ambiguous_symbol, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_SYM, symbols.front()->name(ctx));

    for (const auto other : symbols)
    {
        diag.addNote(DiagnosticId::sema_note_could_be);
        diag.last().addSpan(other->codeRange(ctx));
    }

    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseLiteralTooBig(Sema& sema, AstNodeRef atNodeRef, const ConstantValue& literal)
{
    auto diag = report(sema, DiagnosticId::sema_err_literal_too_big, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_VALUE, literal.toString(sema.ctx()));
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseDivZero(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef)
{
    const auto diag = report(sema, DiagnosticId::sema_err_division_zero, atNodeRef, ReportLocation::Token);
    addSpan(sema, diag.last(), nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raisePointerArithmeticValuePointer(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_pointer_arithmetic_value_ptr, atNodeRef, ReportLocation::Token);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpan(sema, diag.last(), nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raisePointerArithmeticVoidPointer(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_pointer_arithmetic_void_ptr, atNodeRef, ReportLocation::Token);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpan(sema, diag.last(), nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseInvalidOpEnum(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_invalid_op_enum, atNodeRef, ReportLocation::Token);
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    addSpan(sema, diag.last(), nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseTypeNotIndexable(Sema& sema, AstNodeRef atNodeRef, TypeRef typeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_type_not_indexable, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseIndexOutOfRange(Sema& sema, AstNodeRef atNodeRef, int64_t index, size_t maxCount)
{
    auto diag = report(sema, DiagnosticId::sema_err_index_out_of_range, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_VALUE, index);
    diag.addArgument(Diagnostic::ARG_COUNT, maxCount);
    diag.report(sema.ctx());
    return Result::Error;
}

SWC_END_NAMESPACE();
