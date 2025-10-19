#include "pch.h"

#include "Report/DiagReporter.h"
#include "Report/DiagnosticElement.h"

DiagnosticElement::DiagnosticElement(DiagnosticKind kind, DiagnosticId id) :
    id_(id),
    kind_(kind)
{
}

// Helper function to convert variant argument to string
std::string DiagnosticElement::argumentToString(const Argument& arg) const
{
    return std::visit([]<typename T0>(const T0& value) -> std::string {
        using T = std::decay_t<T0>;
        if constexpr (std::is_same_v<T, std::string>)
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

// Format a string by replacing %0, %1, etc. with registered arguments
std::string DiagnosticElement::format(const DiagReporter& reporter) const
{
    std::string result{reporter.diagMessage(id_)};

    // Replace placeholders in reverse order to avoid issues with %10 versus %1
    for (int i = static_cast<int>(arguments_.size()) - 1; i >= 0; --i)
    {
        std::string placeholder = "%" + std::to_string(i);
        std::string replacement = argumentToString(arguments_[i]);

        size_t pos = 0;
        while ((pos = result.find(placeholder, pos)) != std::string::npos)
        {
            result.replace(pos, placeholder.length(), replacement);
            pos += replacement.length();
        }
    }

    return result;
}
