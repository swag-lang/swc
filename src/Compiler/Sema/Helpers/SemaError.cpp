#include "pch.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Assert.h"
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

    bool hasSeenGenericContext(std::span<const Symbol*> seen, const Symbol* symbol)
    {
        for (const Symbol* it : seen)
        {
            if (it == symbol)
                return true;
        }

        return false;
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
        SmallVector<SemaGeneric::GenericParamDesc> params;
        SmallVector<GenericInstanceKey>            args;
        if (!SemaGeneric::Internal::loadFunctionInstanceGenericArgs(sema, function, params, args))
            return;

        const SymbolFunction* root = function.genericRootSym();
        SWC_ASSERT(root != nullptr);
        if (hasSeenGenericContext(seen.span(), root))
            return;

        seen.push_back(root);
        const Utf8 bindings = SemaGeneric::Internal::formatGenericInstanceBindings(sema, params.span(), args.span());
        addGenericContextNote(sema, diag, *root, "function", bindings);
    }

    void addStructGenericContext(Sema& sema, Diagnostic& diag, const SymbolStruct& st, SmallVector<const Symbol*>& seen)
    {
        SmallVector<SemaGeneric::GenericParamDesc> params;
        SmallVector<GenericInstanceKey>            args;
        if (!SemaGeneric::Internal::loadStructInstanceGenericArgs(sema, st, params, args))
            return;

        const SymbolStruct* root = st.genericRootSym();
        SWC_ASSERT(root != nullptr);
        if (hasSeenGenericContext(seen.span(), root))
            return;

        seen.push_back(root);
        const Utf8 bindings = SemaGeneric::Internal::formatGenericInstanceBindings(sema, params.span(), args.span());
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
            addGenericContextNotesFromSymbolMap(sema, diag, sema.curScopePtr() ? sema.curSymMap() : sema.topSymMap(), seen);
    }

    void addExpansionContextNotes(Sema& sema, Diagnostic& diag, const DiagnosticId id)
    {
        if (Diagnostic::diagIdSeverity(id) != DiagnosticSeverity::Error)
            return;
        if (sema.ctx().silentDiagnostic())
            return;

        constexpr uint32_t expansionLimit = 4;
        uint32_t           expansionCount = 0;
        std::unordered_set<const SemaInlinePayload*> seenPayloads;

        const auto addPayloadChain = [&](const SemaInlinePayload* payload)
        {
            while (payload && expansionCount < expansionLimit)
            {
                if (!seenPayloads.insert(payload).second)
                {
                    payload = payload->parentInlinePayload;
                    continue;
                }

                const SymbolFunction* function = payload->sourceFunction;
                if (function && payload->callRef.isValid())
                {
                    const bool isMacro = function->attributes().hasRtFlag(RtAttributeFlagsE::Macro);
                    const bool isMixin = function->attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
                    if (isMacro || isMixin)
                    {
                        diag.addNote(DiagnosticId::sema_note_expansion_invoked_here);
                        diag.last().addArgument(Diagnostic::ARG_WHAT, isMacro ? "macro" : "mixin");
                        diag.last().addArgument(Diagnostic::ARG_SYM, function->name(sema.ctx()));
                        SemaError::addSpan(sema, diag.last(), payload->callRef);
                        ++expansionCount;
                    }
                }

                payload = payload->parentInlinePayload;
            }
        };

        addPayloadChain(SemaHelpers::effectiveInlinePayload(sema));
        addPayloadChain(sema.frame().currentInlinePayload());

        for (uint32_t i = 0; expansionCount < expansionLimit; i++)
        {
            const AstNodeRef nodeRef = i ? sema.visit().parentNodeRef(i - 1) : sema.curNodeRef();
            if (nodeRef.isInvalid())
                break;
            addPayloadChain(sema.inlinePayload(nodeRef));
        }
    }

    Diagnostic buildDiagnostic(DiagnosticId id, FileRef fileRef, const SourceCodeRange& codeRange)
    {
        Diagnostic diag = Diagnostic::get(id, fileRef);
        diag.last().addSpan(codeRange);
        return diag;
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

SemaError::SymbolDiagnosticOrigin SemaError::symbolDiagnosticOrigin(const Sema& sema, const Symbol& symbol)
{
    if (!symbol.decl() || symbol.srcViewRef().isInvalid())
        return SymbolDiagnosticOrigin::Unknown;

    const SourceFile* sourceFile = sema.ownerSourceFile(symbol.srcViewRef());
    if (!sourceFile)
        return SymbolDiagnosticOrigin::Unknown;

    if (sourceFile->hasFlag(FileFlagsE::ImportedApi) || sourceFile->hasFlag(FileFlagsE::Runtime))
        return SymbolDiagnosticOrigin::ExternalDependency;
    if (sourceFile->hasFlag(FileFlagsE::Module) || sourceFile->hasFlag(FileFlagsE::ModuleSrc) || sourceFile->hasFlag(FileFlagsE::CustomSrc))
        return SymbolDiagnosticOrigin::CurrentModule;

    return SymbolDiagnosticOrigin::Unknown;
}

bool SemaError::isCurrentModuleSymbol(const Sema& sema, const Symbol& symbol)
{
    return symbolDiagnosticOrigin(sema, symbol) == SymbolDiagnosticOrigin::CurrentModule;
}

DiagnosticElement* SemaError::addCurrentModuleHelp(Sema& sema, Diagnostic& diag, const Symbol& symbol, DiagnosticId id)
{
    if (!isCurrentModuleSymbol(sema, symbol))
        return nullptr;

    DiagnosticElement& element = diag.addElement(id);
    element.addSpan(symbol.codeRange(sema.ctx()));
    return &element;
}

void SemaError::setReportArguments(Sema& sema, Diagnostic& diag, const SourceCodeRef& codeRange)
{
    SourceCodeRange tokenCodeRange;
    if (!sema.compiler().tryTokenCodeRange(sema.ctx(), tokenCodeRange, codeRange))
        return;

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

Diagnostic SemaError::build(Sema& sema, DiagnosticId id, const SourceCodeRef& atCodeRef)
{
    SourceCodeRange codeRange;
    Diagnostic      diag;
    if (sema.compiler().tryTokenCodeRange(sema.ctx(), codeRange, atCodeRef))
        diag = buildDiagnostic(id, codeRange.srcView->fileRef(), codeRange);
    else
        diag = Diagnostic::get(id, FileRef::invalid());
    setReportArguments(sema, diag, atCodeRef);
    return diag;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, const SourceCodeRef& atCodeRef)
{
    ignoreCurrentFunctionOnError(sema, id);

    Diagnostic diag = build(sema, id, atCodeRef);
    addGenericContextNotes(sema, diag, id);
    addExpansionContextNotes(sema, diag, id);
    return diag;
}

Result SemaError::raise(Sema& sema, DiagnosticId id, const SourceCodeRef& atCodeRef)
{
    const auto diag = report(sema, id, atCodeRef);
    diag.report(sema.ctx());
    return Result::Error;
}

Diagnostic SemaError::build(Sema& sema, DiagnosticId id, AstNodeRef atNodeRef, ReportLocation location)
{
    const FileRef fileRef = sema.srcView(sema.node(atNodeRef).srcViewRef()).fileRef();
    Diagnostic    diag    = buildDiagnostic(id, fileRef, getNodeCodeRange(sema, atNodeRef, location));
    setReportArguments(sema, diag, atNodeRef);
    return diag;
}

Diagnostic SemaError::report(Sema& sema, DiagnosticId id, AstNodeRef atNodeRef, ReportLocation location)
{
    ignoreCurrentFunctionOnError(sema, id);

    Diagnostic diag = build(sema, id, atNodeRef, location);
    addGenericContextNotes(sema, diag, id);
    addExpansionContextNotes(sema, diag, id);
    return diag;
}

Result SemaError::raise(Sema& sema, DiagnosticId id, AstNodeRef atNodeRef, ReportLocation location)
{
    const auto diag = report(sema, id, atNodeRef, location);
    diag.report(sema.ctx());
    return Result::Error;
}

Diagnostic SemaError::build(Sema& sema, DiagnosticId id, const AstNode& atNode, ReportLocation location)
{
    return build(sema, id, atNode.nodeRef(sema.ast()), location);
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
