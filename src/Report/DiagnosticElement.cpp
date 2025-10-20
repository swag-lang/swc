#include "pch.h"

#include "DiagnosticIds.h"
#include "Main/CompilerContext.h"
#include "Main/CompilerInstance.h"
#include "Report/DiagnosticElement.h"

DiagnosticElement::DiagnosticElement(DiagnosticKind kind, DiagnosticId id) :
    id_(id),
    kind_(kind)
{
}

// Helper function to convert variant argument to string
Utf8 DiagnosticElement::argumentToString(const Argument& arg) const
{
    return std::visit([]<typename T0>(const T0& value) -> Utf8 {
        using T = std::decay_t<T0>;
        if constexpr (std::is_same_v<T, Utf8>)
        {
            return value;
        }
        else if constexpr (std::is_same_v<T, uint64_t>)
        {
            return std::to_string(value);
        }
        else if constexpr (std::is_same_v<T, int64_t>)
        {
            return std::to_string(value);
        }
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

std::string_view DiagnosticElement::idName(CompilerContext& ctx) const
{
    return ctx.ci().diagIds().diagName(id_);
}

// Format a string by replacing %0, %1, etc. with registered arguments
Utf8 DiagnosticElement::message(CompilerContext& ctx) const
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
