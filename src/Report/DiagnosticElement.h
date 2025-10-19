#pragma once
#include "Lexer/SourceCodeLocation.h"

class SourceFile;
class CompilerInstance;
enum class DiagnosticKind;
enum class DiagnosticId;

class DiagnosticElement
{
    friend class Diagnostic;
    friend class Verifier;
    using Argument = std::variant<Utf8, uint64_t, int64_t>;

    DiagnosticId      id_;
    DiagnosticKind    kind_;
    const SourceFile* file_   = nullptr;
    uint32_t          offset_ = 0;
    uint32_t          len_    = 0;

    std::vector<Argument> arguments_;

    Utf8 argumentToString(const Argument& arg) const;

public:
    explicit DiagnosticElement(DiagnosticKind kind, DiagnosticId id);

    void setLocation(const SourceFile* file)
    {
        file_ = file;
        len_  = 0;
    }

    void setLocation(const SourceFile* file, uint32_t offset, uint32_t len = 1)
    {
        file_   = file;
        offset_ = offset;
        len_    = len;
    }

    SourceCodeLocation location(const CompilerInstance& ci) const;
    std::string_view   idName(const CompilerInstance& ci) const;

    template<typename T>
    void addArgument(T&& arg)
    {
        arguments_.emplace_back(std::forward<T>(arg));
    }

    Utf8 message(const CompilerInstance& ci) const;
};
