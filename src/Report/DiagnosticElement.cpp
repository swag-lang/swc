#include "pch.h"

#include "Core/Utf8Helper.h"
#include "Diagnostic.h"
#include "DiagnosticElement.h"

SWC_BEGIN_NAMESPACE();

DiagnosticElement::DiagnosticElement(DiagnosticId id) :
    id_(id),
    severity_(Diagnostic::diagIdSeverity(id))
{
}

// Helper function to convert variant argument to string
Utf8 DiagnosticElement::argumentToString(const Argument& arg) const
{
    return std::visit([]<typename T0>(const T0& value) -> Utf8 {
        using T = std::decay_t<T0>;
        if constexpr (std::is_same_v<T, Utf8>)
            return value;
        else if constexpr (std::is_same_v<T, uint64_t>)
            return std::to_string(value);
        else if constexpr (std::is_same_v<T, int64_t>)
            return std::to_string(value);
        return "";
    },
                      arg.val);
}

SourceCodeLocation DiagnosticElement::location(const Context& ctx) const
{
    SourceCodeLocation loc;
    loc.fromOffset(ctx, file_, offset_, len_);
    return loc;
}

std::string_view DiagnosticElement::idName() const
{
    return Diagnostic::diagIdName(id_);
}

// Format a string by replacing %0, %1, etc. with registered arguments
Utf8 DiagnosticElement::message() const
{
    if (!message_.empty())
        return message_;

    Utf8 result{Diagnostic::diagIdMessage(id_)};

    // Replace placeholders in reverse order to avoid issues with %10 versus %1
    for (int i = static_cast<int>(arguments_.size()) - 1; i >= 0; --i)
    {
        Utf8 placeholder = Utf8("{") + Utf8(arguments_[i].name) + Utf8("}");
        Utf8 replacement = argumentToString(arguments_[i]);

        size_t pos = 0;
        while ((pos = result.find(placeholder, pos)) != Utf8::npos)
        {
            result.replace(pos, placeholder.length(), replacement);
            pos += replacement.length();
        }
    }

    return result;
}

void DiagnosticElement::addArgument(std::string_view name, std::string_view arg)
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
            char hex[5];
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
                sanitized += *ptr++;
        }
    }

    arguments_.emplace_back(Argument{.name = name, .val = std::move(sanitized)});
}

SWC_END_NAMESPACE();
