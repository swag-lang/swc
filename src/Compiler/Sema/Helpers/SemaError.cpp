#include "pch.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t K_FORMAT_LIST_LIMIT = 8;

    void appendQuotedListItem(Utf8& out, bool& first, std::string_view name)
    {
        if (!first)
            out += ", ";
        first = false;
        out += '\'';
        out += name;
        out += '\'';
    }

    void ignoreCurrentFunctionOnError(Sema& sema, const DiagnosticId id)
    {
        if (Diagnostic::diagIdSeverity(id) != DiagnosticSeverity::Error)
            return;

        // Overload/spec-op probing can intentionally suppress diagnostics; those speculative
        // failures must not poison the enclosing runtime function.
        if (sema.ctx().silentDiagnostic())
            return;

        if (auto* currentFn = sema.currentFunction())
            currentFn->setIgnored(sema.ctx());
    }
}

SourceCodeRange SemaError::getNodeCodeRange(Sema& sema, AstNodeRef atNodeRef, ReportLocation location)
{
    const TaskContext& ctx  = sema.ctx();
    const AstNode&     node = sema.node(atNodeRef);
    switch (location)
    {
        case ReportLocation::Token:
            return node.codeRange(ctx);
        case ReportLocation::Children:
            return node.codeRangeWithChildren(ctx, sema.ast());
    }

    SWC_UNREACHABLE();
}

void SemaError::setReportArguments(Sema& sema, Diagnostic& diag, const SourceCodeRef& codeRange)
{
    SWC_ASSERT(codeRange.isValid());

    const TaskContext& ctx     = sema.ctx();
    const SourceView&  srcView = sema.srcView(codeRange.srcViewRef);
    const Token&       token   = srcView.token(codeRange.tokRef);
    const Utf8&        tokStr  = Diagnostic::tokenErrorString(ctx, codeRange);

    diag.addArgument(Diagnostic::ARG_TOK, tokStr);
    diag.addArgument(Diagnostic::ARG_TOK_FAM, Token::toFamily(token.id));
    diag.addArgument(Diagnostic::ARG_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(token.id)));
}

void SemaError::setReportArguments(Sema& sema, Diagnostic& diag, const Symbol* sym)
{
    if (!sym)
        return;

    diag.addArgument(Diagnostic::ARG_SYM, sym->name(sema.ctx()));
    diag.addArgument(Diagnostic::ARG_SYM_FAM, sym->toFamily());
    diag.addArgument(Diagnostic::ARG_A_SYM_FAM, Utf8Helper::addArticleAAn(sym->toFamily()));
}

void SemaError::setReportArguments(Sema& sema, Diagnostic& diag, const TypeInfo* type)
{
    if (!type)
        return;

    diag.addArgument(Diagnostic::ARG_TYPE, type->toName(sema.ctx()));
    diag.addArgument(Diagnostic::ARG_SYM_FAM, type->toFamily(sema.ctx()));
    diag.addArgument(Diagnostic::ARG_A_SYM_FAM, Utf8Helper::addArticleAAn(type->toFamily(sema.ctx())));
}

void SemaError::setReportArguments(Sema& sema, Diagnostic& diag, AstNodeRef nodeRef)
{
    const SemaNodeView view = sema.viewNodeTypeSymbol(nodeRef);
    setReportArguments(sema, diag, view.node()->codeRef());
    setReportArguments(sema, diag, view.sym());
    setReportArguments(sema, diag, view.type());
}

void SemaError::addSpan(Sema& sema, DiagnosticElement& element, AstNodeRef atNodeRef, const Utf8& message, DiagnosticSeverity severity)
{
    const SourceCodeRange codeRange = sema.node(atNodeRef).codeRangeWithChildren(sema.ctx(), sema.ast());
    element.addSpan(codeRange, message, severity);
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, const SourceCodeRef& atCodeRef)
{
    ignoreCurrentFunctionOnError(sema, id);

    Diagnostic        diag    = Diagnostic::get(id, sema.ast().srcView().fileRef());
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
    ignoreCurrentFunctionOnError(sema, id);

    Diagnostic diag = Diagnostic::get(id, sema.ast().srcView().fileRef());
    diag.last().addSpan(getNodeCodeRange(sema, atNodeRef, location), "", DiagnosticSeverity::Error);
    setReportArguments(sema, diag, atNodeRef);
    return diag;
}

Result SemaError::raise(Sema& sema, DiagnosticId id, AstNodeRef atNodeRef, ReportLocation location)
{
    const auto diag = report(sema, id, atNodeRef, location);
    diag.report(sema.ctx());
    return Result::Error;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, const AstNode& atNode, ReportLocation location)
{
    return report(sema, id, atNode.nodeRef(sema.ast()), location);
}

Result SemaError::raise(Sema& sema, DiagnosticId id, const AstNode& atNode, ReportLocation location)
{
    const auto diag = report(sema, id, atNode, location);
    diag.report(sema.ctx());
    return Result::Error;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, const Symbol& atSymbol)
{
    auto diag = report(sema, id, atSymbol.codeRef());
    setReportArguments(sema, diag, &atSymbol);
    return diag;
}

Result SemaError::raise(Sema& sema, DiagnosticId id, const Symbol& atSymbol)
{
    const auto diag = report(sema, id, atSymbol);
    diag.report(sema.ctx());
    return Result::Error;
}

Result SemaError::raiseRuntimeUsesCompilerOnlySymbol(Sema& sema, AstNodeRef atNodeRef, const Symbol& symbol)
{
    auto diag = report(sema, DiagnosticId::sema_err_runtime_uses_compiler_only_symbol, atNodeRef);
    setReportArguments(sema, diag, &symbol);

    if (const SymbolFunction* currentFn = sema.currentFunction())
        diag.addArgument(Diagnostic::ARG_WHAT, currentFn->getFullScopedName(sema.ctx()));

    diag.addNote(DiagnosticId::sema_note_compiler_only_symbol);
    diag.last().addSpan(symbol.codeRange(sema.ctx()));
    diag.report(sema.ctx());
    return Result::Error;
}

Utf8 SemaError::formatEnumValueList(const TaskContext& ctx, const SymbolEnum& symEnum)
{
    std::vector<const Symbol*> symbols;
    symEnum.getAllSymbols(symbols);

    Utf8   result;
    bool   first = true;
    size_t count = 0;
    for (const Symbol* symbol : symbols)
    {
        const auto* enumValue = symbol ? symbol->safeCast<SymbolEnumValue>() : nullptr;
        if (!enumValue)
            continue;

        if (count == K_FORMAT_LIST_LIMIT)
        {
            result += ", ...";
            break;
        }

        appendQuotedListItem(result, first, enumValue->name(ctx));
        ++count;
    }

    return result;
}

Utf8 SemaError::formatStructFieldList(const TaskContext& ctx, const SymbolStruct& symStruct)
{
    Utf8   result;
    bool   first = true;
    size_t count = 0;
    for (const SymbolVariable* field : symStruct.fields())
    {
        if (!field)
            continue;

        if (count == K_FORMAT_LIST_LIMIT)
        {
            result += ", ...";
            break;
        }

        appendQuotedListItem(result, first, field->name(ctx));
        ++count;
    }

    return result;
}

SWC_END_NAMESPACE();
