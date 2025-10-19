#pragma once
#include "Lexer/SourceCodeLocation.h"

class SourceFile;
class Reporter;
enum class DiagnosticKind;
enum class DiagnosticId;

class DiagnosticElement
{
    friend class Diagnostic;
    using Argument = std::variant<std::string, uint64_t, int64_t>;

    DiagnosticId      id_;
    DiagnosticKind    kind_;
    const SourceFile* file_   = nullptr;
    uint32_t          offset_ = 0;
    uint32_t          len_    = 0;

    std::vector<Argument> arguments_;

    std::string argumentToString(const Argument& arg) const;

public:
    explicit DiagnosticElement(DiagnosticKind kind, DiagnosticId id);

    void setLocation(const SourceFile* file)
    {
        file_   = file;
        len_    = 0;
    }

    void setLocation(const SourceFile* file, uint32_t offset, uint32_t len = 1)
    {
        file_   = file;
        offset_ = offset;
        len_    = len;
    }

    SourceCodeLocation getLocation() const;

    template<typename T>
    void addArgument(T&& arg)
    {
        arguments_.emplace_back(std::forward<T>(arg));
    }

    std::string format(const Reporter& reporter) const;
};
