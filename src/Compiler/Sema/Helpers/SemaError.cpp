#include "pch.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr size_t K_FORMAT_LIST_LIMIT = 8;

    // Returns false when the limit is reached (caller should break).
    bool appendQuotedListItem(Utf8& out, bool& first, size_t& count, std::string_view name)
    {
        if (count == K_FORMAT_LIST_LIMIT)
        {
            out += ", ...";
            return false;
        }

        if (!first)
            out += ", ";
        first = false;
        out += '\'';
        out += name;
        out += '\'';
        ++count;
        return true;
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

    Utf8 formatGenericInstanceKey(Sema& sema, const GenericInstanceKey& key)
    {
        if (key.typeRef.isValid())
            return sema.typeMgr().get(key.typeRef).toName(sema.ctx());
        if (key.cstRef.isValid())
            return sema.cstMgr().get(key.cstRef).toString(sema.ctx());
        return "?";
    }

    void appendGenericBinding(Utf8& out, std::string_view name, const Utf8& value)
    {
        if (!out.empty())
            out += ", ";

        out += name;
        out += " = ";
        out += value;
    }

    bool hasSeenGenericContext(std::span<const Symbol*> seen, const Symbol* symbol)
    {
        for (const Symbol* it : seen)
        {
            if (it == symbol)
                return true;
        }

        return false;
    }

    Utf8 formatGenericInstanceBindings(Sema& sema, const AstNode& rootDecl, SpanRef genericParamsRef, std::span<const GenericInstanceKey> args)
    {
        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, rootDecl, genericParamsRef, params);
        if (params.empty() || params.size() != args.size())
            return {};

        Utf8 out;
        for (size_t i = 0; i < params.size(); ++i)
        {
            if (!params[i].idRef.isValid())
                continue;

            appendGenericBinding(out, sema.idMgr().get(params[i].idRef).name, formatGenericInstanceKey(sema, args[i]));
        }

        return out;
    }

    void addGenericContextNote(Sema& sema, Diagnostic& diag, const Symbol& root, std::string_view family, const Utf8& bindings)
    {
        if (bindings.empty())
            return;

        diag.addNote(DiagnosticId::sema_note_generic_context);
        diag.last().addArgument(Diagnostic::ARG_GENERIC_SYM_FAM, family);
        diag.last().addArgument(Diagnostic::ARG_GENERIC_SYM, root.name(sema.ctx()));
        diag.last().addArgument(Diagnostic::ARG_GENERIC_VALUES, bindings);
        diag.last().addSpan(root.codeRange(sema.ctx()));
    }

    void addFunctionGenericContext(Sema& sema, Diagnostic& diag, const SymbolFunction& function, SmallVector<const Symbol*>& seen)
    {
        if (!function.isGenericInstance())
            return;

        const SymbolFunction* root = function.genericRootSym();
        if (!root || hasSeenGenericContext(seen.span(), root))
            return;

        seen.push_back(root);
        const auto* decl = root->decl() ? root->decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!decl || decl->spanGenericParamsRef.isInvalid())
            return;

        SmallVector<GenericInstanceKey> args;
        if (!root->genericInstanceStorage(sema.ctx()).tryGetArgs(function, args))
            return;

        const Utf8 bindings = formatGenericInstanceBindings(sema, *decl, decl->spanGenericParamsRef, args.span());
        addGenericContextNote(sema, diag, *root, "function", bindings);
    }

    void addStructGenericContext(Sema& sema, Diagnostic& diag, const SymbolStruct& st, SmallVector<const Symbol*>& seen)
    {
        if (!st.isGenericInstance())
            return;

        const SymbolStruct* root = st.genericRootSym();
        if (!root || hasSeenGenericContext(seen.span(), root))
            return;

        seen.push_back(root);
        const auto* decl = root->decl() ? root->decl()->safeCast<AstStructDecl>() : nullptr;
        if (!decl || decl->spanGenericParamsRef.isInvalid())
            return;

        SmallVector<GenericInstanceKey> args;
        if (!root->tryGetGenericInstanceArgs(st, args))
            return;

        const Utf8 bindings = formatGenericInstanceBindings(sema, *decl, decl->spanGenericParamsRef, args.span());
        addGenericContextNote(sema, diag, *root, "struct", bindings);
    }

    void addGenericContextNotesFromSymbolMap(Sema& sema, Diagnostic& diag, const SymbolMap* symMap, SmallVector<const Symbol*>& seen)
    {
        for (const SymbolMap* current = symMap; current; current = current->ownerSymMap())
        {
            if (current->isFunction())
                addFunctionGenericContext(sema, diag, current->cast<SymbolFunction>(), seen);
            else if (current->isStruct())
                addStructGenericContext(sema, diag, current->cast<SymbolStruct>(), seen);
            else if (current->isImpl())
            {
                const auto& impl = current->cast<SymbolImpl>();
                if (impl.isForStruct())
                {
                    if (const SymbolStruct* st = impl.symStruct())
                        addStructGenericContext(sema, diag, *st, seen);
                }
            }
        }
    }

    void addGenericContextNotes(Sema& sema, Diagnostic& diag, const DiagnosticId id)
    {
        if (Diagnostic::diagIdSeverity(id) != DiagnosticSeverity::Error)
            return;
        if (sema.ctx().silentDiagnostic())
            return;

        SmallVector<const Symbol*> seen;
        if (const SymbolFunction* currentFn = sema.currentFunction())
            addGenericContextNotesFromSymbolMap(sema, diag, currentFn, seen);
        else
            addGenericContextNotesFromSymbolMap(sema, diag, sema.curSymMap(), seen);
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

    const SourceView& srcView = sema.srcView(atCodeRef.srcViewRef);
    Diagnostic        diag    = Diagnostic::get(id, srcView.fileRef());
    diag.last().addSpan(srcView.tokenCodeRange(sema.ctx(), atCodeRef.tokRef), "", DiagnosticSeverity::Error);

    setReportArguments(sema, diag, atCodeRef);
    addGenericContextNotes(sema, diag, id);
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

    const FileRef fileRef = sema.srcView(sema.node(atNodeRef).srcViewRef()).fileRef();
    Diagnostic    diag    = Diagnostic::get(id, fileRef);
    diag.last().addSpan(getNodeCodeRange(sema, atNodeRef, location), "", DiagnosticSeverity::Error);
    setReportArguments(sema, diag, atNodeRef);
    addGenericContextNotes(sema, diag, id);
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
        if (!appendQuotedListItem(result, first, count, enumValue->name(ctx)))
            break;
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
        if (!appendQuotedListItem(result, first, count, field->name(ctx)))
            break;
    }

    return result;
}

Utf8 SemaError::formatStructMemberList(Sema& sema, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return {};

    const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
    if (typeInfo.isStruct())
        return formatStructFieldList(sema.ctx(), typeInfo.payloadSymStruct());
    if (!typeInfo.isAggregateStruct())
        return {};

    Utf8   result;
    bool   first = true;
    size_t count = 0;
    for (const IdentifierRef idRef : typeInfo.payloadAggregate().names)
    {
        if (!idRef.isValid())
            continue;
        if (!appendQuotedListItem(result, first, count, sema.idMgr().get(idRef).name))
            break;
    }

    return result;
}

SWC_END_NAMESPACE();
