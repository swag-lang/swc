#include "pch.h"

#include "DiagnosticIds.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagnosticElement.h"

DiagnosticElement::DiagnosticElement(DiagnosticSeverity kind, DiagnosticId id) :
    id_(id),
    severity_(kind)
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
                      arg);
}

SourceCodeLocation DiagnosticElement::location(CompilerContext& ctx) const
{
    SourceCodeLocation loc;
    loc.fromOffset(ctx, file_, offset_, len_);
    return loc;
}

std::string_view DiagnosticElement::idName(const CompilerContext& ctx) const
{
    return ctx.ci().diagIds().diagName(id_);
}

// Format a string by replacing %0, %1, etc. with registered arguments
Utf8 DiagnosticElement::message(const CompilerContext& ctx) const
{
    Utf8 result{ctx.ci().diagIds().diagMessage(id_)};

    // Replace placeholders in reverse order to avoid issues with %10 versus %1
    for (int i = static_cast<int>(arguments_.size()) - 1; i >= 0; --i)
    {
        Utf8 placeholder = "%" + std::to_string(i);
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

void DiagnosticElement::addArgument(std::string_view arg)
{
    Utf8 sanitized;
    sanitized.reserve(arg.size());

    for (const uint8_t ch : arg)
    {
        if (std::isprint(ch))
            sanitized += ch;
        else if (ch == '\t' || ch == '\n' || ch == '\r')
            sanitized += ' ';
        else
        {
            // Convert to \xHH format
            char hex[5];
            (void) std::snprintf(hex, sizeof(hex), "\\x%02X", ch);
            sanitized += hex;
        }
    }

    arguments_.emplace_back(std::move(sanitized));
}
