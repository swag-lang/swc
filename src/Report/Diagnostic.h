#pragma once
#include <variant>

enum class DiagnosticId;

class Diagnostic
{
public:
    explicit Diagnostic(DiagnosticId id);

    template<typename T>
    void addArgument(T&& arg)
    {
        arguments_.emplace_back(std::forward<T>(arg));
    }

private:
    DiagnosticId                        id_;
    std::vector<std::variant<Fs::path>> arguments_;
};
