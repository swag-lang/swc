#include "pch.h"
#include "Support/Report/Diagnostic.h"
#include "Compiler/Verify.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/DiagnosticBuilder.h"
#include "Support/Report/DiagnosticElement.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct DiagnosticIdInfo // NOLINT(clang-diagnostic-padded)
    {
        std::string_view              name;
        std::vector<std::string_view> messages;
        DiagnosticSeverity            severity;
        DiagnosticId                  id = DiagnosticId::None;
    };

    template<size_t N>
    void addDiagnosticInfo(std::array<DiagnosticIdInfo, N>& infos, DiagnosticId id, std::string_view name, DiagnosticSeverity severity, std::string_view msg)
    {
        DiagnosticIdInfo& info = infos[static_cast<size_t>(id)];
        if (info.id == DiagnosticId::None)
        {
            info.id       = id;
            info.name     = name;
            info.severity = severity;
        }
        else
        {
            SWC_ASSERT(info.id == id);
            SWC_ASSERT(info.name == name);
            SWC_ASSERT(info.severity == severity);
        }

        info.messages.push_back(msg);
    }

    std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> makeDiagnosticInfos()
    {
        std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> arr{};

#define SWC_DIAG_DEF(id, sev, msg) \
    addDiagnosticInfo(arr, DiagnosticId::id, #id, DiagnosticSeverity::sev, msg);
#include "Support/Report/Msg/Errors.msg"

#include "Support/Report/Msg/Notes.msg"

#undef SWC_DIAG_DEF
        return arr;
    }

    const std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> DIAGNOSTIC_INFOS = makeDiagnosticInfos();

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
    SWC_ASSERT(DIAGNOSTIC_INFOS[static_cast<size_t>(id)].id == id);
    const std::vector<std::string_view>& msgs = DIAGNOSTIC_INFOS[static_cast<size_t>(id)].messages;
    SWC_ASSERT(!msgs.empty());
    return msgs.front();
}

std::span<const std::string_view> Diagnostic::diagIdMessages(DiagnosticId id)
{
    SWC_ASSERT(DIAGNOSTIC_INFOS[static_cast<size_t>(id)].id == id);
    return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].messages;
}

std::string_view Diagnostic::diagIdName(DiagnosticId id)
{
    SWC_ASSERT(DIAGNOSTIC_INFOS[static_cast<size_t>(id)].id == id);
    return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].name;
}

DiagnosticSeverity Diagnostic::diagIdSeverity(DiagnosticId id)
{
    SWC_ASSERT(DIAGNOSTIC_INFOS[static_cast<size_t>(id)].id == id);
    return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].severity;
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

void Diagnostic::addDidYouMeanNote(const std::optional<Utf8> suggestion)
{
    if (!suggestion.has_value())
        return;

    DiagnosticElement& note = addElement(DiagnosticId::cmd_note_did_you_mean);
    note.setSeverity(DiagnosticSeverity::Note);
    // Store {value} on the note itself so it does not get shadowed by a parent
    // diagnostic argument using the same placeholder.
    note.addArgument(Diagnostic::ARG_VALUE, suggestion.value());
}

void Diagnostic::addArgument(std::string_view name, std::string_view arg)
{
    Utf8 sanitized;
    sanitized.reserve(arg.size());

    const auto*    ptr = reinterpret_cast<const char8_t*>(arg.data());
    const char8_t* end = ptr + arg.size();
    while (ptr < end)
    {
        auto [buf, wc, eat] = Utf8Helper::decodeOneChar(ptr, end);
        if (!buf)
        {
            ptr++;
            continue;
        }

        if ((wc < 128 && !std::isprint(static_cast<int>(wc))) || wc >= 128)
        {
            char hex[10];
            (void) std::snprintf(hex, sizeof(hex), "\\x%02X", static_cast<uint32_t>(wc));
            sanitized += hex;
            ptr = buf;
        }
        else if (wc == '\t' || wc == '\n' || wc == '\r')
        {
            sanitized += ' ';

            ptr = buf;
        }
        else
        {
            while (ptr < buf)
                sanitized += static_cast<char>(*ptr++);
        }
    }

    // Replace it if the same argument already exists
    for (Argument& a : arguments_)
    {
        if (a.name == name)
        {
            a.val = std::move(sanitized);
            return;
        }
    }

    arguments_.emplace_back(DiagnosticArgument{.name = name, .val = std::move(sanitized)});
}

Diagnostic Diagnostic::get(DiagnosticId id, FileRef file)
{
    Diagnostic diag(file);
    diag.addElement(id);
    return diag;
}

void Diagnostic::report(TaskContext& ctx) const
{
    if (elements_.empty())
        return;
    if (silent() || ctx.silentDiagnostic())
        return;

    DiagnosticBuilder eng(ctx, *this);
    const Utf8        msg     = eng.build();
    bool              dismiss = false;

    if (ctx.hasCompiler() && !ctx.compiler().tryRegisterReportedDiagnostic(msg))
        return;

    // Check that diagnostic was not awaited
    if (fileOwner_.isValid())
    {
        SWC_ASSERT(ctx.hasCompiler());
        const SourceFile& file = ctx.compiler().file(fileOwner_);
        dismiss                = file.unitTest().verifyExpected(ctx, *this);
    }

    if (dismiss && shouldReportExpectedFrontEndError(ctx, *this))
        dismiss = false;

    // Count only diagnostics that are not suppressed by source-driven expectations.
    switch (elements_.front()->severity())
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
                    const SourceCodeRange startRange = elements_.front()->codeRange(0, ctx);
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
            for (const std::shared_ptr<DiagnosticElement>& e : elements_)
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

        if (CompilerInstance::dbgDevStop && !orgDismissed)
            Os::panicBox("[DevMode] ERROR raised!");
    }
}

SWC_END_NAMESPACE();
