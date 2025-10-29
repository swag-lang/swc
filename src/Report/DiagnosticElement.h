#pragma once
#include "Lexer/SourceCodeLocation.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class Context;
enum class DiagnosticSeverity;
enum class DiagnosticId;

class DiagnosticElement
{
    friend class Diagnostic;
    friend class UnitTest;

    Utf8               message_;
    DiagnosticId       id_;
    DiagnosticSeverity severity_;

    const SourceFile* file_   = nullptr;
    uint32_t          offset_ = 0;
    uint32_t          len_    = 0;

public:
    explicit DiagnosticElement(DiagnosticId id);

    explicit DiagnosticElement(DiagnosticSeverity severity, DiagnosticId id) :
        id_(id),
        severity_(severity)
    {
    }

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

    void inheritLocationFrom(const DiagnosticElement& other)
    {
        file_   = other.file_;
        offset_ = other.offset_;
        len_    = other.len_;
    }

    Utf8 message() const;
    void setMessage(Utf8 m) { message_ = std::move(m); }

    SourceCodeLocation location(const Context& ctx) const;
    std::string_view   idName() const;
    DiagnosticId       id() const { return id_; }
    DiagnosticSeverity severity() const { return severity_; }
    bool               hasCodeLocation() const { return file_ != nullptr && len_ > 0; }
};

SWC_END_NAMESPACE()
