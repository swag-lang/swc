#include "pch.h"
#include "Support/Report/Diagnostic.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/DiagnosticBuilder.h"
#include "Support/Report/DiagnosticElement.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct DiagnosticIdInfo // NOLINT(clang-diagnostic-padded)
    {
        std::string_view   name;
        uint16_t           firstMessage = 0;
        uint16_t           messageCount = 0;
        DiagnosticSeverity severity     = DiagnosticSeverity::Error;
    };

    constexpr auto DIAGNOSTIC_MESSAGES = std::to_array<std::string_view>({
#define SWC_DIAG_DEF(id, sev, msg) msg,
#include "Support/Report/Msg/Errors.msg"
#include "Support/Report/Msg/Notes.msg"
#undef SWC_DIAG_DEF
    });

    constexpr size_t DIAGNOSTIC_MESSAGE_COUNT = DIAGNOSTIC_MESSAGES.size();
    static_assert(DIAGNOSTIC_MESSAGE_COUNT <= std::numeric_limits<uint16_t>::max());

    struct DiagnosticMessageDefinition
    {
        DiagnosticId       id;
        std::string_view   name;
        DiagnosticSeverity severity;
    };

    consteval std::array<DiagnosticMessageDefinition, DIAGNOSTIC_MESSAGE_COUNT> makeDiagnosticMessageDefinitions()
    {
        return {{
#define SWC_DIAG_DEF(id, sev, msg) {DiagnosticId::id, #id, DiagnosticSeverity::sev},
#include "Support/Report/Msg/Errors.msg"
#include "Support/Report/Msg/Notes.msg"
#undef SWC_DIAG_DEF
        }};
    }

    constexpr auto DIAGNOSTIC_MESSAGE_DEFINITIONS = makeDiagnosticMessageDefinitions();

    consteval bool validateDiagnosticMessageDefinitions()
    {
        std::array<bool, static_cast<size_t>(DiagnosticId::Count)> seen{};
        const DiagnosticMessageDefinition*                         previous = nullptr;
        for (const DiagnosticMessageDefinition& definition : DIAGNOSTIC_MESSAGE_DEFINITIONS)
        {
            const size_t idIndex = static_cast<size_t>(definition.id);
            if (idIndex == 0 || idIndex >= seen.size())
                return false;

            if (!previous || definition.id != previous->id)
            {
                if (seen[idIndex])
                    return false;
                seen[idIndex] = true;
            }
            else if (definition.name != previous->name || definition.severity != previous->severity)
            {
                return false;
            }

            previous = &definition;
        }

        for (size_t idIndex = 1; idIndex < seen.size(); ++idIndex)
        {
            if (!seen[idIndex])
                return false;
        }
        return true;
    }

    static_assert(validateDiagnosticMessageDefinitions(), "each diagnostic id needs one contiguous message group with a stable name and severity");

    consteval std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> makeDiagnosticInfos()
    {
        std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> result{};

        for (size_t messageIndex = 0; messageIndex < DIAGNOSTIC_MESSAGE_DEFINITIONS.size(); ++messageIndex)
        {
            const DiagnosticMessageDefinition& definition = DIAGNOSTIC_MESSAGE_DEFINITIONS[messageIndex];
            DiagnosticIdInfo&                  info       = result[static_cast<size_t>(definition.id)];
            if (!info.messageCount)
            {
                info.name         = definition.name;
                info.firstMessage = static_cast<uint16_t>(messageIndex);
                info.severity     = definition.severity;
            }
            ++info.messageCount;
        }

        return result;
    }

    constexpr auto DIAGNOSTIC_INFOS = makeDiagnosticInfos();

    uint32_t codeRangeEndLine(const TaskContext& ctx, const SourceCodeRange& codeRange)
    {
        if (codeRange.srcView == nullptr || codeRange.len == 0)
            return codeRange.line;

        SourceCodeRange endRange;
        endRange.fromOffset(ctx, *codeRange.srcView, codeRange.offset + codeRange.len - 1, 1);
        return endRange.line;
    }

    bool isFrontEndError(const Diagnostic& diagnostic)
    {
        if (diagnostic.elements().empty())
            return false;

        const std::string_view idName = diagnostic.elements().front()->idName();
        return idName.starts_with("lex_err_") || idName.starts_with("parser_err_");
    }

    bool shouldReportExpectedFrontEndError(const TaskContext& ctx, const Diagnostic& diagnostic)
    {
        const CommandLine& cmdLine = ctx.cmdLine();
        if (cmdLine.command != CommandKind::Test)
            return false;
        if (cmdLine.lexOnly || cmdLine.syntaxOnly || cmdLine.semaOnly)
            return false;

        return isFrontEndError(diagnostic);
    }

    void addGeneratedSourceOrigin(TaskContext& ctx, Diagnostic& diagnostic)
    {
        if (!ctx.hasCompiler() || diagnostic.elements().empty())
            return;

        const DiagnosticElement& primary = *diagnostic.elements().front();
        if (!primary.hasSpans() || primary.id() == DiagnosticId::sema_err_ast_recursive_expansion)
            return;

        const SourceView* sourceView = primary.srcView();
        if (!sourceView)
            return;

        std::vector<SourceCodeRange>      originRanges;
        std::unordered_set<SourceViewRef> visitedViews;
        visitedViews.insert(sourceView->ref());

        constexpr size_t maxOriginDepth = 256;
        while (originRanges.size() < maxOriginDepth)
        {
            const SourceCodeRef originRef = sourceView->debugSourceCodeRef();
            if (!originRef.isValid() || !visitedViews.insert(originRef.srcViewRef).second)
                break;

            SourceCodeRange originRange;
            if (!ctx.compiler().tryTokenCodeRange(ctx, originRange, originRef))
                break;

            originRanges.push_back(originRange);
            sourceView = &ctx.compiler().srcView(originRef.srcViewRef);
        }

        if (originRanges.empty())
            return;

        constexpr size_t maxDisplayedOrigins = 4;
        const size_t     sequentialOrigins   = originRanges.size() > maxDisplayedOrigins ? maxDisplayedOrigins - 1 : originRanges.size();
        for (size_t idx = 0; idx < sequentialOrigins; idx++)
        {
            diagnostic.addNote(DiagnosticId::sema_note_generated_source_origin);
            diagnostic.last().addSpan(originRanges[idx]);
        }

        if (originRanges.size() > maxDisplayedOrigins)
        {
            diagnostic.addNote(DiagnosticId::sema_note_generated_source_root);
            diagnostic.last().addSpan(originRanges.back());
        }
    }
}

Utf8 Diagnostic::tokenErrorString(const TaskContext& ctx, const SourceCodeRef& codeRef)
{
    const SourceView& srcView = ctx.compiler().srcView(codeRef.srcViewRef);
    const Token&      token   = srcView.token(codeRef.tokRef);
    const Utf8        str     = token.string(srcView);

    constexpr uint32_t         maxTokenStrLen = 40;
    constexpr std::string_view tokenEllipsis  = " ...";
    if (token.hasFlag(TokenFlagsE::EolInside))
    {
        const size_t pos = str.find_first_of("\n\r");
        if (pos != Utf8::npos)
            return Utf8Helper::truncate(str.substr(0, pos), {.maxChars = maxTokenStrLen, .ellipsis = tokenEllipsis, .forceEllipsis = true});
    }

    return Utf8Helper::truncate(str, {.maxChars = maxTokenStrLen, .ellipsis = tokenEllipsis});
}

std::string_view Diagnostic::diagIdMessage(DiagnosticId id)
{
    const DiagnosticIdInfo& info = DIAGNOSTIC_INFOS[static_cast<size_t>(id)];
    SWC_ASSERT(info.messageCount);
    return DIAGNOSTIC_MESSAGES[info.firstMessage];
}

std::span<const std::string_view> Diagnostic::diagIdMessages(DiagnosticId id)
{
    const DiagnosticIdInfo& info = DIAGNOSTIC_INFOS[static_cast<size_t>(id)];
    SWC_ASSERT(info.messageCount);
    return {DIAGNOSTIC_MESSAGES.data() + info.firstMessage, info.messageCount};
}

std::string_view Diagnostic::diagIdName(DiagnosticId id)
{
    const DiagnosticIdInfo& info = DIAGNOSTIC_INFOS[static_cast<size_t>(id)];
    SWC_ASSERT(info.messageCount);
    return info.name;
}

DiagnosticSeverity Diagnostic::diagIdSeverity(DiagnosticId id)
{
    const DiagnosticIdInfo& info = DIAGNOSTIC_INFOS[static_cast<size_t>(id)];
    SWC_ASSERT(info.messageCount);
    return info.severity;
}

Diagnostic::Diagnostic(FileRef file) :
    fileOwner_(file)
{
}

DiagnosticElement& Diagnostic::addElement(DiagnosticId id)
{
    auto               ptr = std::make_shared<DiagnosticElement>(id);
    DiagnosticElement* raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return *raw;
}

void Diagnostic::addNote(DiagnosticId id)
{
    if (id == DiagnosticId::None)
        return;
    auto               ptr = std::make_shared<DiagnosticElement>(id);
    DiagnosticElement* raw = ptr.get();
    raw->setSeverity(DiagnosticSeverity::Note);
    elements_.emplace_back(std::move(ptr));
}

void Diagnostic::addDidYouMeanNote(const std::optional<Utf8>& suggestion)
{
    if (!suggestion.has_value())
        return;

    DiagnosticElement& note = addElement(DiagnosticId::cmd_note_did_you_mean);
    note.setSeverity(DiagnosticSeverity::Note);
    // Store {value} on the note itself so it does not get shadowed by a parent
    // diagnostic argument using the same placeholder.
    note.addArgument(ARG_VALUE, suggestion.value());
}

void Diagnostic::addArgument(std::string_view name, std::string_view arg)
{
    setDiagnosticArgument(arguments_, name, arg);
}

void Diagnostic::removeArgument(const std::string_view name)
{
    std::erase_if(arguments_, [name](const Argument& argument) { return argument.name == name; });
}

Diagnostic Diagnostic::get(DiagnosticId id, FileRef file)
{
    Diagnostic diag(file);
    diag.addElement(id);
    return diag;
}

void Diagnostic::setSourceWarningLevels(const std::optional<WarningLevel>& blanketLevel, const std::optional<WarningLevel>& level)
{
    sourceBlanketWarningLevel_ = blanketLevel;
    sourceWarningLevel_        = level;
}

bool Diagnostic::applyWarningPolicy(const TaskContext& ctx)
{
    DiagnosticElement& primary = *elements_.front();
    if (primary.severity() != DiagnosticSeverity::Warning)
        return true;

    WarningLevelQuery query;
    query.id                 = primary.id();
    query.cmdLine            = &ctx.cmdLine().warningPolicy;
    query.buildCfg           = ctx.hasCompiler() ? &ctx.compiler().warningPolicy() : nullptr;
    query.sourceBlanketLevel = sourceBlanketWarningLevel_;
    query.sourceLevel        = sourceWarningLevel_;

    switch (resolveWarningLevel(query))
    {
        case WarningLevel::Disable:
            return false;
        case WarningLevel::Warning:
            return true;
        case WarningLevel::Error:
            break;
    }

    // Elements are shared with the diagnostic this copy came from, so the promoted one gets
    // its own element rather than turning the original's warning into an error too.
    elements_.front() = std::make_shared<DiagnosticElement>(primary);
    elements_.front()->setSeverity(DiagnosticSeverity::Error);
    return true;
}

void Diagnostic::report(TaskContext& ctx) const
{
    if (elements_.empty())
        return;
    if (silent() || ctx.silentDiagnostic())
        return;
    Diagnostic reportedDiagnostic = *this;
    if (!reportedDiagnostic.applyWarningPolicy(ctx))
        return;

    addGeneratedSourceOrigin(ctx, reportedDiagnostic);

    DiagnosticBuilder eng(ctx, reportedDiagnostic);
    const Utf8        msg     = eng.build();
    bool              dismiss = false;

    if (ctx.hasCompiler() && !ctx.compiler().tryRegisterReportedDiagnostic(msg))
        return;

    // Check that diagnostic was not awaited
    if (fileOwner_.isValid())
    {
        SWC_ASSERT(ctx.hasCompiler());
        const SourceFile& file = ctx.compiler().file(fileOwner_);
        dismiss                = file.unitTest().verifyExpected(ctx, reportedDiagnostic);

        std::unordered_set verifiedFiles = {&file};
        for (const std::shared_ptr<DiagnosticElement>& element : reportedDiagnostic.elements())
        {
            const SourceView* sourceView = element->srcView();
            const SourceFile* sourceFile = sourceView ? sourceView->file() : nullptr;
            if (!sourceFile || !verifiedFiles.insert(sourceFile).second)
                continue;

            dismiss = sourceFile->unitTest().verifyExpected(ctx, reportedDiagnostic) || dismiss;
        }
    }

    if (dismiss && shouldReportExpectedFrontEndError(ctx, reportedDiagnostic))
        dismiss = false;

    // Count only diagnostics that are not suppressed by source-driven expectations.
    switch (reportedDiagnostic.elements_.front()->severity())
    {
        case DiagnosticSeverity::Error:
            if (!dismiss && ctx.reportToStats())
                Stats::addError();
            ctx.setHasError();
            if (ctx.hasCompiler())
            {
                ctx.compiler().notifyAlive();
                if (fileOwner_.isValid())
                {
                    SourceFile& file = ctx.compiler().file(fileOwner_);
                    file.setHasError();
                    const SourceCodeRange startRange = reportedDiagnostic.elements_.front()->codeRange(0, ctx);
                    file.addErrorLineRange(startRange.line, codeRangeEndLine(ctx, startRange));
                }
            }
            break;
        case DiagnosticSeverity::Warning:
            if (!dismiss && ctx.reportToStats())
                Stats::get().numWarnings.fetch_add(1);
            ctx.setHasWarning();
            if (ctx.hasCompiler())
            {
                ctx.compiler().notifyAlive();
                if (fileOwner_.isValid())
                {
                    SourceFile& file = ctx.compiler().file(fileOwner_);
                    file.setHasWarning();
                }
            }
            break;
        default:
            break;
    }

    // In tests, suppress diagnostics unless verbose errors are explicitly requested and match the filter.
    const bool orgDismissed = dismiss;
    if (dismiss && ctx.cmdLine().verboseVerify)
    {
        const Utf8& filter = ctx.cmdLine().verboseVerifyFilter;
        if (filter.empty())
            dismiss = false;
        else if (msg.find(filter) != Utf8::npos)
            dismiss = false;
        else
        {
            for (const std::shared_ptr<DiagnosticElement>& e : reportedDiagnostic.elements())
            {
                if (e->idName().find(filter) != Utf8::npos)
                    dismiss = false;
            }
        }
    }

    // Log diagnostic
    if (!dismiss)
    {
        Logger::print(ctx, msg);

        if (CompilerInstance::dbgDevStop && ctx.cmdLine().devStopDiagnostics && !orgDismissed)
            Os::panicBox("DevMode: compiler diagnostic reported");
    }
}

SWC_END_NAMESPACE();
