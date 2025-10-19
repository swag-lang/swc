#pragma once

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
    const SourceFile* file_;
    uint32_t          offset_ = UINT32_MAX;
    uint32_t          len_    = 0;

    std::vector<Argument> arguments_;

    std::string argumentToString(const Argument& arg) const;

public:
    explicit DiagnosticElement(DiagnosticKind kind, DiagnosticId id);

    void setLocation(const SourceFile* file)
    {
        file_   = file;
        offset_ = UINT32_MAX;
        len_    = 0;
    }

    void setLocation(const SourceFile* file, uint32_t offset, uint32_t len = 1)
    {
        file_   = file;
        offset_ = offset;
        len_    = len;
    }

    template<typename T>
    void addArgument(T&& arg)
    {
        arguments_.emplace_back(std::forward<T>(arg));
    }

    std::string format(const Reporter& reporter) const;
};
