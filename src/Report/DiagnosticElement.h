#pragma once
#include "Lexer/SourceCodeLocation.h"
#include "Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class TaskContext;
enum class DiagnosticId;

class DiagnosticElement
{
    Utf8               message_;
    DiagnosticId       id_;
    DiagnosticSeverity severity_;

    const SourceFile* file_ = nullptr;

    std::vector<DiagnosticSpan> spans_;

public:
    explicit DiagnosticElement(DiagnosticId id);
    explicit DiagnosticElement(DiagnosticSeverity severity, DiagnosticId id);

    void              setFile(const SourceFile* file) { file_ = file; }
    const SourceFile* file() const { return file_; }

    void        addSpan(const SourceFile* file, uint32_t offset, uint32_t len, DiagnosticSeverity severity = DiagnosticSeverity::Zero, const Utf8& message = Utf8());
    void        addSpan(const SourceCodeLocation& loc, const Utf8& message, DiagnosticSeverity severity = DiagnosticSeverity::Zero);
    void        addSpan(const SourceCodeLocation& loc, DiagnosticId diagId, DiagnosticSeverity severity = DiagnosticSeverity::Zero);
    const auto& spans() const { return spans_; }
    auto&       span(uint32_t index) { return spans_[index]; }
    const auto& span(uint32_t index) const { return spans_[index]; }
    bool        hasCodeLocation() const { return file_ != nullptr && !spans_.empty(); }

    Utf8 message() const;
    void setMessage(Utf8 m);

    SourceCodeLocation location(uint32_t spanIndex, const TaskContext& ctx) const;
    SourceCodeLocation location(const DiagnosticSpan& span, const TaskContext& ctx) const;
    std::string_view   idName() const;
    DiagnosticId       id() const { return id_; }
    DiagnosticSeverity severity() const { return severity_; }
    bool               isNoteOrHelp() const;
};

SWC_END_NAMESPACE()
