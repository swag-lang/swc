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
    void setReportArguments(Sema& sema, Diagnostic& diag, SourceViewRef srcViewRef, TokenRef tokRef)
    {
        SWC_ASSERT(srcViewRef.isValid());
        SWC_ASSERT(tokRef.isValid());

        const auto&       ctx     = sema.ctx();
        const SourceView& srcView = sema.compiler().srcView(srcViewRef);
        const Token&      token   = srcView.token(tokRef);
        const Utf8&       tokStr  = Diagnostic::tokenErrorString(ctx, sema.ast().srcView(), tokRef);

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

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, AstNodeRef nodeRef)
{
    auto diag = Diagnostic::get(id, sema.ast().srcView().fileRef());

    const SemaNodeView nodeView(sema, nodeRef);
    setReportArguments(sema, diag, nodeView.node->srcViewRef(), nodeView.node->tokRef());
    setReportArguments(sema, diag, nodeView.sym);

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

Result SemaError::raise(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef)
{
    const auto diag = report(sema, id, srcViewRef, tokRef);
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
        const SourceCodeLocation loc = sema.node(lowest).locationWithChildren(sema.ctx(), sema.ast());
        diag.addNote(DiagnosticId::sema_note_not_constant);
        diag.last().addSpan(loc);
    }

    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseBinaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_binary_operand_type, nodeOp.srcViewRef(), nodeOp.tokRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);

    const SourceCodeLocation loc = sema.node(nodeValueRef).locationWithChildren(sema.ctx(), sema.ast());
    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);

    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseUnaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_unary_operand_type, nodeOp.srcViewRef(), nodeOp.tokRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);

    const SourceCodeLocation loc = sema.node(nodeValueRef).locationWithChildren(sema.ctx(), sema.ast());
    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);

    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseInternal(Sema& sema, const AstNode& node)
{
    return raise(sema, DiagnosticId::sema_err_internal, node.srcViewRef(), node.tokRef());
}

Result SemaError::raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_already_defined, symbol->srcViewRef(), symbol->tokRef());
    diag.addNote(DiagnosticId::sema_note_other_definition);
    diag.last().addSpan(otherSymbol->loc(ctx));
    diag.report(ctx);
    return Result::Error;
}

Result SemaError::raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol)
{
    auto& ctx  = sema.ctx();
    auto  diag = report(sema, DiagnosticId::sema_err_ghosting, symbol->srcViewRef(), symbol->tokRef());
    diag.addNote(DiagnosticId::sema_note_other_definition);
    diag.last().addSpan(otherSymbol->loc(ctx));
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
        diag.last().addSpan(other->loc(ctx));
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

Result SemaError::raiseDivZero(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_division_zero, nodeOp.srcViewRef(), nodeOp.tokRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);

    const SourceCodeLocation loc = sema.node(nodeValueRef).locationWithChildren(sema.ctx(), sema.ast());
    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);

    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raisePointerArithmeticValuePointer(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_pointer_arithmetic_value_ptr, nodeOp.srcViewRef(), nodeOp.tokRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);

    const SourceCodeLocation loc = sema.node(nodeValueRef).locationWithChildren(sema.ctx(), sema.ast());
    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);

    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raisePointerArithmeticVoidPointer(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_pointer_arithmetic_void_ptr, nodeOp.srcViewRef(), nodeOp.tokRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);

    const SourceCodeLocation loc = sema.node(nodeValueRef).locationWithChildren(sema.ctx(), sema.ast());
    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);

    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseInvalidOpEnum(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef)
{
    auto diag = report(sema, DiagnosticId::sema_err_invalid_op_enum, nodeOp.srcViewRef(), nodeOp.tokRef());
    diag.addArgument(Diagnostic::ARG_TYPE, targetTypeRef);
    const SourceCodeLocation loc = sema.node(nodeValueRef).locationWithChildren(sema.ctx(), sema.ast());
    diag.last().addSpan(loc, "", DiagnosticSeverity::Note);
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
    diag.report(sema.ctx());
    return Result::Error;
}

SWC_END_NAMESPACE();
