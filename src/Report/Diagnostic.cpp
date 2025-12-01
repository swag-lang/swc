#include "pch.h"
#include "Report/Diagnostic.h"
#include "Core/Utf8Helper.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Report/DiagnosticBuilder.h"
#include "Report/DiagnosticElement.h"
#include "Report/Logger.h"
#include "Wmf/SourceFile.h"
#include "Wmf/Verify.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct DiagnosticIdInfo // NOLINT(clang-diagnostic-padded)
    {
        std::string_view   name;
        std::string_view   msg;
        DiagnosticSeverity severity;
    };

    constexpr auto makeDiagnosticInfos()
    {
        std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> arr{};
#define SWC_DIAG_DEF(id, sev, msg) \
    arr[(size_t) DiagnosticId::id] = {#id, msg, DiagnosticSeverity::sev};
#include "Diagnostic_Errors_.msg"

#include "Diagnostic_Notes_.msg"

#undef SWC_DIAG_DEF
        return arr;
    }

    constexpr auto DIAGNOSTIC_INFOS = makeDiagnosticInfos();
}

Utf8 Diagnostic::tokenErrorString(const TaskContext&, const SourceView& srcView, TokenRef tokRef)
{
    constexpr static size_t MAX_TOKEN_STR_LEN = 40;
    const Token&            token             = srcView.token(tokRef);
    Utf8                    str               = token.string(srcView);

    if (token.hasFlag(TokenFlagsE::EolInside))
    {
        const auto pos = str.find_first_of("\n\r");
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

SourceCodeLocation Diagnostic::tokenErrorLocation(const TaskContext& ctx, const SourceView& srcView, TokenRef tokRef)
{
    const Token&       token = srcView.token(tokRef);
    SourceCodeLocation loc   = token.location(ctx, srcView);

    if (token.hasFlag(TokenFlagsE::EolInside))
    {
        const auto str = token.string(srcView);
        const auto pos = str.find_first_of("\n\r");
        if (pos != Utf8::npos)
            loc.len = static_cast<uint32_t>(pos);
    }

    return loc;
}

std::string_view Diagnostic::diagIdMessage(DiagnosticId id)
{
    return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].msg;
}

std::string_view Diagnostic::diagIdName(DiagnosticId id)
{
    return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].name;
}

DiagnosticSeverity Diagnostic::diagIdSeverity(DiagnosticId id)
{
    return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].severity;
}

Diagnostic::Diagnostic(FileRef file) :
    fileOwner_(file)
{
}

DiagnosticElement& Diagnostic::addElement(DiagnosticId id)
{
    auto       ptr = std::make_shared<DiagnosticElement>(id);
    const auto raw = ptr.get();
    elements_.emplace_back(std::move(ptr));
    return *raw;
}

void Diagnostic::addArgument(std::string_view name, std::string_view arg, bool quoted)
{
    Utf8 sanitized;
    sanitized.reserve(arg.size());

    auto       ptr = reinterpret_cast<const char8_t*>(arg.data());
    const auto end = ptr + arg.size();
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
            (void) std::snprintf(hex, sizeof(hex), "\\x%02X", wc);
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
    for (auto& a : arguments_)
    {
        if (a.name == name)
        {
            a.val    = std::move(sanitized);
            a.quoted = quoted;
            return;
        }
    }

    arguments_.emplace_back(Argument{.name = name, .quoted = quoted, .val = std::move(sanitized)});
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
        const auto& file = ctx.compiler().file(fileOwner_);
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
                auto& file = ctx.compiler().file(fileOwner_);
                file.setHasError();
            }
            break;
        case DiagnosticSeverity::Warning:
            if (!dismiss)
                Stats::get().numWarnings.fetch_add(1);
            ctx.setHasWarning();
            if (fileOwner_.isValid())
            {
                auto& file = ctx.compiler().file(fileOwner_);
                file.setHasWarning();
            }
            break;
        default:
            break;
    }

    // In tests, suppress diagnostics unless verbose errors are explicitly requested and match the filter.
    if (dismiss && ctx.cmdLine().verboseDiag)
    {
        const auto& filter = ctx.cmdLine().verboseDiagFilter;
        if (filter.empty())
            dismiss = false;
        else if (msg.find(filter) != Utf8::npos)
            dismiss = false;
        else
        {
            for (const auto& e : elements_)
            {
                if (e.get()->idName().find(filter) != Utf8::npos)
                    dismiss = false;
            }
        }
    }

    // Log diagnostic
    if (!dismiss)
    {
        auto& logger = ctx.global().logger();
        logger.lock();
        Logger::print(ctx, msg);
        logger.unlock();
    }
}

SWC_END_NAMESPACE();
