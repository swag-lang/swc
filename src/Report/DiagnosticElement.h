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
    explicit DiagnosticElement(DiagnosticSeverity severity, DiagnosticId id);

    void setLocation(const SourceFile* file);
    void setLocation(const SourceFile* file, uint32_t offset, uint32_t len = 1);
    void setLocation(const SourceCodeLocation& loc);
    void setLocation(const SourceCodeLocation& locStart, const SourceCodeLocation& locEnd);
    void inheritLocationFrom(const DiagnosticElement& other);

    Utf8 message() const;
    void setMessage(Utf8 m) { message_ = std::move(m); }

    SourceCodeLocation location(const Context& ctx) const;
    std::string_view   idName() const;
    DiagnosticId       id() const { return id_; }
    DiagnosticSeverity severity() const { return severity_; }
    bool               hasCodeLocation() const { return file_ != nullptr && len_ > 0; }
    bool               isNoteOrHelp() const;
};

SWC_END_NAMESPACE()
