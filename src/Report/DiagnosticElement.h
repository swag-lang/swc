#pragma once
#include "Lexer/SourceCodeLocation.h"

class SourceFile;
class CompilerContext;
enum class DiagnosticSeverity;
enum class DiagnosticId;

class DiagnosticElement
{
    friend class Diagnostic;
    friend class UnitTest;
    using Argument = std::variant<Utf8, uint64_t, int64_t>;

    DiagnosticId       id_;
    DiagnosticSeverity severity_;

    const SourceFile* file_   = nullptr;
    uint32_t          offset_ = 0;
    uint32_t          len_    = 0;

    std::vector<Argument> arguments_;

    Utf8 argumentToString(const Argument& arg) const;

public:
    explicit DiagnosticElement(DiagnosticSeverity kind, DiagnosticId id);

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

    void setLocation(const SourceCodeLocation& loc)
    {
        file_   = loc.file;
        offset_ = loc.offset;
        len_    = loc.len;
    }

    SourceCodeLocation location() const;
    std::string_view   idName() const;
    DiagnosticId       id() const { return id_; }
    DiagnosticSeverity severity() const { return severity_; }
    Utf8               message() const;

    template<typename T>
    void addArgument(T&& arg)
    {
        arguments_.emplace_back(std::forward<T>(arg));
    }

    void addArgument(std::string_view arg);
};
