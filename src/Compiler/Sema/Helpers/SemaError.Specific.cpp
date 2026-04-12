#include "pch.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    AstNodeRef findLowestNonConstantChild(Sema& sema, AstNodeRef rootRef)
    {
        AstNodeRef lowest = AstNodeRef::invalid();
        Ast::visit(sema.ast(), rootRef, [&](AstNodeRef childRef, const AstNode&) {
            if (childRef == rootRef)
                return Ast::VisitResult::Continue;

            const SemaNodeView view{sema, childRef, SemaNodeViewPartE::Constant};
            if (view.cstRef().isInvalid())
            {
                lowest = childRef;
                return Ast::VisitResult::Continue;
            }

            return Ast::VisitResult::Skip;
        });
        return lowest;
    }
}

namespace
{
    Result raiseSymbolConflict(Sema& sema, DiagnosticId diagId, const Symbol* symbol, const Symbol* otherSymbol)
    {
        TaskContext& ctx  = sema.ctx();
        auto         diag = SemaError::report(sema, diagId, symbol->codeRef());
        diag.addNote(DiagnosticId::sema_note_other_definition);
        diag.last().addSpan(otherSymbol->codeRange(ctx));
        diag.report(ctx);
        return Result::Error;
    }
}

Result SemaError::raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    return raiseSymbolConflict(sema, DiagnosticId::sema_err_already_defined, symbol, otherSymbol);
}

Result SemaError::raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    return raiseSymbolConflict(sema, DiagnosticId::sema_err_ghosting, symbol, otherSymbol);
}

Diagnostic SemaError::reportCannotCast(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_cannot_cast, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    return diag;
}

Result SemaError::raiseCannotCast(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    const auto diag = reportCannotCast(sema, atNodeRef, srcTypeRef, targetTypeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseInvalidType(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    TaskContext& ctx  = sema.ctx();
    auto         diag = report(sema, DiagnosticId::sema_err_invalid_type, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, targetTypeRef);
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseInvalidRangeType(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef)
{
    TaskContext& ctx  = sema.ctx();
    auto         diag = report(sema, DiagnosticId::sema_err_invalid_range_type, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseRequestedTypeFam(Sema& sema, AstNodeRef atNodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef)
{
    TaskContext& ctx  = sema.ctx();
    auto         diag = report(sema, DiagnosticId::sema_err_expected_type_fam, atNodeRef, ReportLocation::Children);
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

    const AstNodeRef lowest = findLowestNonConstantChild(sema, atNodeRef);
    if (lowest.isValid())
    {
        diag.addNote(DiagnosticId::sema_note_not_constant);
        const SemaNodeView lowestView{sema, lowest, SemaNodeViewPartE::Symbol};
        if (lowestView.hasSymbol())
        {
            diag.last().addArgument(Diagnostic::ARG_SYM, lowestView.sym()->name(sema.ctx()));
            diag.last().addArgument(Diagnostic::ARG_A_SYM_FAM, Utf8Helper::addArticleAAn(lowestView.sym()->toFamily()));
        }
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
    TaskContext& ctx  = sema.ctx();
    auto         diag = report(sema, DiagnosticId::sema_err_ambiguous_symbol, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_SYM, symbols.front()->name(ctx));

    for (const auto* other : symbols)
    {
        diag.addNote(DiagnosticId::sema_note_could_be);
        diag.last().addArgument(Diagnostic::ARG_SYM, other->name(ctx));
        diag.last().addArgument(Diagnostic::ARG_A_SYM_FAM, Utf8Helper::addArticleAAn(other->toFamily()));
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

Diagnostic SemaError::reportFoldSafety(Sema& sema, Math::FoldStatus status, AstNodeRef atNodeRef, ReportLocation location)
{
    const DiagnosticId diagId = Math::foldStatusDiagnosticId(status);
    SWC_ASSERT(diagId != DiagnosticId::None);
    return report(sema, diagId, atNodeRef, location);
}

Result SemaError::raiseFoldSafety(Sema& sema, Math::FoldStatus status, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, ReportLocation location)
{
    const DiagnosticId diagId = Math::foldStatusDiagnosticId(status);
    if (diagId == DiagnosticId::None)
        return Result::Continue;

    const auto diag = report(sema, diagId, atNodeRef, location);
    if (nodeValueRef.isValid())
        addSpan(sema, diag.last(), nodeValueRef, "", DiagnosticSeverity::Note);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseDivZero(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef)
{
    return raiseFoldSafety(sema, Math::FoldStatus::DivisionByZero, atNodeRef, nodeValueRef, ReportLocation::Token);
}

namespace
{
    Result raiseTypeWithValueNote(Sema& sema, DiagnosticId diagId, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
    {
        auto diag = SemaError::report(sema, diagId, atNodeRef, SemaError::ReportLocation::Token);
        diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
        SemaError::addSpan(sema, diag.last(), nodeValueRef, "", DiagnosticSeverity::Note);
        diag.report(sema.ctx());
        return Result::Error;
    }
}

Result SemaError::raisePointerArithmeticValuePointer(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    return raiseTypeWithValueNote(sema, DiagnosticId::sema_err_pointer_arithmetic_value_ptr, atNodeRef, nodeValueRef, targetTypeRef);
}

Result SemaError::raisePointerArithmeticVoidPointer(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    return raiseTypeWithValueNote(sema, DiagnosticId::sema_err_pointer_arithmetic_void_ptr, atNodeRef, nodeValueRef, targetTypeRef);
}

Result SemaError::raiseInvalidOpEnum(Sema& sema, AstNodeRef atNodeRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    return raiseTypeWithValueNote(sema, DiagnosticId::sema_err_invalid_op_enum, atNodeRef, nodeValueRef, targetTypeRef);
}

Result SemaError::raiseTypeNotIndexable(Sema& sema, AstNodeRef atNodeRef, TypeRef typeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_type_not_indexable, atNodeRef, ReportLocation::Children);
    diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseTypeArgumentError(Sema& sema, DiagnosticId diagId, const SourceCodeRef& codeRef, TypeRef typeRef)
{
    auto diag = report(sema, diagId, codeRef);
    diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseCodeTypeRestricted(Sema& sema, const SourceCodeRef& codeRef, TypeRef typeRef)
{
    return raiseTypeArgumentError(sema, DiagnosticId::sema_err_code_type_restricted, codeRef, typeRef);
}

Result SemaError::raiseCodeTypeRestricted(Sema& sema, AstNodeRef atNodeRef, TypeRef typeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_code_type_restricted, atNodeRef);
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
