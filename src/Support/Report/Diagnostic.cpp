#include "pch.h"
#include "Support/Report/Diagnostic.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/DiagnosticBuilder.h"
#include "Support/Report/DiagnosticElement.h"
#include "Support/Report/Logger.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct DiagnosticIdInfo // NOLINT(clang-diagnostic-padded)
    {
        std::string_view              name;
        std::vector<std::string_view> msgs;
        DiagnosticSeverity            severity;
        DiagnosticId                  id = DiagnosticId::None;
    };

    std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> makeDiagnosticInfos()
    {
        std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> arr{};

        auto add = [&](DiagnosticId id, std::string_view name, DiagnosticSeverity severity, std::string_view msg) {
            DiagnosticIdInfo& info = arr[static_cast<size_t>(id)];
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
            info.msgs.push_back(msg);
        };

#define SWC_DIAG_DEF(id, sev, msg) \
    add(DiagnosticId::id, #id, DiagnosticSeverity::sev, msg);
#include "Support/Report/Msg/Errors.msg"

#include "Support/Report/Msg/Notes.msg"

#undef SWC_DIAG_DEF
        return arr;
    }

    const std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> DIAGNOSTIC_INFOS = makeDiagnosticInfos();
}

Utf8 Diagnostic::tokenErrorString(const TaskContext& ctx, const SourceCodeRef& codeRef)
{
    const SourceView& srcView = ctx.compiler().srcView(codeRef.srcViewRef);
    const Token&      token   = srcView.token(codeRef.tokRef);
    Utf8              str     = token.string(srcView);

    constexpr static size_t MAX_TOKEN_STR_LEN = 40;
    if (token.hasFlag(TokenFlagsE::EolInside))
    {
        const size_t pos = str.find_first_of("\n\r");
        if (pos != Utf8::npos)
        {
            str = str.substr(0, std::min(pos, static_cast<size_t>(MAX_TOKEN_STR_LEN)));
            str += " ...";
            return str;
        }
    }

    if (str.length() > MAX_TOKEN_STR_LEN)
    {
        str = str.substr(0, MAX_TOKEN_STR_LEN);
        str += " ...";
    }

    return str;
}

std::string_view Diagnostic::diagIdMessage(DiagnosticId id)
{
    SWC_ASSERT(DIAGNOSTIC_INFOS[static_cast<size_t>(id)].id == id);
    const std::vector<std::string_view>& msgs = DIAGNOSTIC_INFOS[static_cast<size_t>(id)].msgs;
    SWC_ASSERT(!msgs.empty());
    return msgs.front();
}

std::span<const std::string_view> Diagnostic::diagIdMessages(DiagnosticId id)
{
    SWC_ASSERT(DIAGNOSTIC_INFOS[static_cast<size_t>(id)].id == id);
    return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].msgs;
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
    std::shared_ptr<DiagnosticElement> ptr = std::make_shared<DiagnosticElement>(id);
    DiagnosticElement*                 raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return *raw;
}

void Diagnostic::addNote(DiagnosticId id)
{
    if (id == DiagnosticId::None)
        return;
    std::shared_ptr<DiagnosticElement> ptr = std::make_shared<DiagnosticElement>(id);
    DiagnosticElement*                 raw = ptr.get();
    raw->setSeverity(DiagnosticSeverity::Note);
    elements_.emplace_back(std::move(ptr));
}

void Diagnostic::addArgument(std::string_view name, std::string_view arg)
{
    Utf8 sanitized;
    sanitized.reserve(arg.size());

    const char8_t* ptr = reinterpret_cast<const char8_t*>(arg.data());
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

    // Check that diagnostic was not awaited
    if (fileOwner_.isValid())
    {
        const SourceFile& file = ctx.compiler().file(fileOwner_);
        dismiss          = file.unitTest().verifyExpected(ctx, *this);
    }

    // Count only errors and warnings not dismissed during tests
    switch (elements_.front()->severity())
    {
        case DiagnosticSeverity::Error:
            if (!dismiss)
                Stats::get().numErrors.fetch_add(1);
            ctx.setHasError();
            if (fileOwner_.isValid())
            {
                SourceFile& file = ctx.compiler().file(fileOwner_);
                file.setHasError();
            }
            break;
        case DiagnosticSeverity::Warning:
            if (!dismiss)
                Stats::get().numWarnings.fetch_add(1);
            ctx.setHasWarning();
            if (fileOwner_.isValid())
            {
                SourceFile& file = ctx.compiler().file(fileOwner_);
                file.setHasWarning();
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
                if (e.get()->idName().find(filter) != Utf8::npos)
                    dismiss = false;
            }
        }
    }

    // Log diagnostic
    if (!dismiss)
    {
        {
            Logger::ScopedLock loggerLock(ctx.global().logger());
            Logger::print(ctx, msg);
        }

        if (CommandLine::dbgDevMode && !orgDismissed)
            Os::panicBox("[DevMode] ERROR raised!");
    }
}

SWC_END_NAMESPACE();
