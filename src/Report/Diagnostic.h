#pragma once
#include <variant>

class Logger;
enum class DiagnosticId;

enum class DiagnosticKind
{
    Error,
    Warning,
    Note,
    Hint,
};

class Diagnostic
{
    using Argument = std::variant<std::string, uint64_t, int64_t>;
    DiagnosticId          id_;
    DiagnosticKind        kind_;
    std::vector<Argument> arguments_;

    std::string argumentToString(const Argument& arg) const;
    std::string format() const;

public:
    explicit Diagnostic(DiagnosticKind kind, DiagnosticId id);

    template<typename T>
    void addArgument(T&& arg)
    {
        arguments_.emplace_back(std::forward<T>(arg));
    }

    void log(Logger& logger) const;
};
