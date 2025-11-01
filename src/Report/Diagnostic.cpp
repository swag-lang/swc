#include "pch.h"
#include "Report/Diagnostic.h"
#include "Core/Utf8Helper.h"
#include "Lexer/SourceFile.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Report/DiagnosticBuilder.h"
#include "Report/DiagnosticElement.h"
#include "Report/Logger.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    struct DiagnosticIdInfo
    {
        DiagnosticId       id;
        DiagnosticSeverity severity;
        std::string_view   name;
        std::string_view   msg;
    };

    constexpr auto makeDiagnosticInfos()
    {
        std::array<DiagnosticIdInfo, static_cast<size_t>(DiagnosticId::Count)> arr{};
#define SWC_DIAG_DEF(id, sev, msg) \
    arr[(size_t) DiagnosticId::id] = {DiagnosticId::id, DiagnosticSeverity::sev, #id, msg};
#include "Diagnostic_Errors_.msg"

#include "Diagnostic_Notes_.msg"

#undef SWC_DIAG_DEF
        return arr;
    }

    constexpr auto DIAGNOSTIC_INFOS = makeDiagnosticInfos();
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

Diagnostic::Diagnostic(const Context& context, const std::optional<SourceFile*>& fileOwner) :
    fileOwner_(fileOwner),
    context_(&context)
{
}

Diagnostic::~Diagnostic()
{
    report(*context_);
}

void Diagnostic::report(const Context& ctx) const
{
    SWC_ASSERT(!elements_.empty());

    if (fileOwner_)
    {
        if (elements_.front()->severity() == DiagnosticSeverity::Error)
            fileOwner_.value()->setHasError();
        if (elements_.front()->severity() == DiagnosticSeverity::Warning)
            fileOwner_.value()->setHasWarning();
    }

    DiagnosticBuilder eng(ctx, *this);
    const auto        msg     = eng.build();
    bool              dismiss = false;

    // Check that diagnostic was not awaited
    if (fileOwner_)
    {
        dismiss = fileOwner_.value()->unittest().verifyExpected(ctx, *this);
    }

    // In tests, suppress diagnostics unless verbose errors are explicitly requested and match the filter.
    if (dismiss && ctx.cmdLine().verboseErrors)
    {
        const auto& filter = ctx.cmdLine().verboseErrorsFilter;
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

    auto           ptr = reinterpret_cast<const uint8_t*>(arg.data());
    const uint8_t* end = ptr + arg.size();
    while (ptr < end)
    {
        auto [buf, wc, eat] = Utf8Helper::decodeOneChar(ptr, end);
        if (!buf)
        {
            ptr++;
            continue;
        }

        if (wc < 128 && !std::isprint(static_cast<int>(wc)))
        {
            char hex[10];
            (void) std::snprintf(hex, sizeof(hex), "<0x%02X>", wc);
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
                sanitized += *ptr++;
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

Diagnostic Diagnostic::raise(const Context& ctx, DiagnosticId id, std::optional<SourceFile*> fileOwner)
{
    Diagnostic diag(ctx, fileOwner);
    diag.addElement(id);
    return diag;
}

SWC_END_NAMESPACE();
