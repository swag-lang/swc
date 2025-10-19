#pragma once

class Reporter;
enum class DiagnosticKind;
enum class DiagnosticId;

class DiagnosticElement
{
private:
    friend class Diagnostic;
    using Argument = std::variant<std::string, uint64_t, int64_t>;
    DiagnosticId          id_;
    DiagnosticKind        kind_;
    std::vector<Argument> arguments_;

    std::string argumentToString(const Argument& arg) const;

public:
    explicit DiagnosticElement(DiagnosticKind kind, DiagnosticId id);

    template<typename T>
    void addArgument(T&& arg)
    {
        arguments_.emplace_back(std::forward<T>(arg));
    }

    std::string format(const Reporter& reporter) const;
};
