#pragma once
#include <variant>

class Logger;
enum class DiagnosticId;

class Diagnostic
{
private:
    using Argument = std::variant<std::string, uint64_t, int64_t>;

    std::string argumentToString(const Argument& arg) const;
    std::string format() const;

    DiagnosticId          id_;
    std::vector<Argument> arguments_;

public:
    explicit Diagnostic(DiagnosticId id);

    template<typename T>
    void addArgument(T&& arg)
    {
        arguments_.emplace_back(std::forward<T>(arg));
    }

    [[nodiscard]] DiagnosticId id() const { return id_; }
    void log(Logger& logger);
};
