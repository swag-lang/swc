#pragma once
#include "Lexer/SourceCodeLocation.h"

SWC_BEGIN_NAMESPACE()

enum class DiagnosticSeverity
{
    Zero,
    Error,
    Warning,
    Note,
    Help,
};

class SourceFile;
class Context;
enum class DiagnosticId;

class DiagnosticElement
{
    friend class Diagnostic;
    friend class UnitTest;

    Utf8               message_;
    DiagnosticId       id_;
    DiagnosticSeverity severity_;

    const SourceFile* file_ = nullptr;

    struct Span
    {
        uint32_t           offset = 0;
        uint32_t           len    = 0;
        DiagnosticSeverity severity;
        Utf8               message;
    };

    std::vector<Span> spans_;

public:
    explicit DiagnosticElement(DiagnosticId id);
    explicit DiagnosticElement(DiagnosticSeverity severity, DiagnosticId id);

    void              setFile(const SourceFile* file) { file_ = file; }
    const SourceFile* file() const { return file_; }

    void        addSpan(const SourceFile* file, uint32_t offset, uint32_t len, DiagnosticSeverity severity = DiagnosticSeverity::Zero, const Utf8& message = Utf8());
    void        addSpan(const SourceCodeLocation& loc, DiagnosticSeverity severity = DiagnosticSeverity::Zero, const Utf8& message = Utf8());
    const auto& spans() const { return spans_; }
    const auto& span(uint32_t index) const { return spans_[index]; }

    Utf8 message() const;
    void setMessage(Utf8 m);

    SourceCodeLocation location(uint32_t spanIndex, const Context& ctx) const;
    std::string_view   idName() const;
    DiagnosticId       id() const { return id_; }
    DiagnosticSeverity severity() const { return severity_; }
    bool               hasCodeLocation() const { return file_ != nullptr && !spans_.empty(); }
    bool               isNoteOrHelp() const;
};

SWC_END_NAMESPACE()
