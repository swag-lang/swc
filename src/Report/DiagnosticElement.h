#pragma once
#include "Lexer/SourceCodeLocation.h"
#include "Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;
class TaskContext;
enum class DiagnosticId;

class DiagnosticElement
{
public:
    explicit DiagnosticElement(DiagnosticId id);
    explicit DiagnosticElement(DiagnosticSeverity severity, DiagnosticId id);

    void              setSrcView(const SourceView* srcView) { srcView_ = srcView; }
    const SourceView* srcView() const { return srcView_; }

    void        addSpan(const SourceView* srcView, uint32_t offset, uint32_t len, DiagnosticSeverity severity = DiagnosticSeverity::Zero, const Utf8& message = Utf8());
    void        addSpan(const SourceCodeLocation& loc, const Utf8& message = "", DiagnosticSeverity severity = DiagnosticSeverity::Zero);
    void        addSpan(const SourceCodeLocation& loc, DiagnosticId diagId, DiagnosticSeverity severity = DiagnosticSeverity::Zero);
    const auto& spans() const { return spans_; }
    auto&       span(uint32_t index) { return spans_[index]; }
    const auto& span(uint32_t index) const { return spans_[index]; }
    bool        hasCodeLocation() const { return srcView_ != nullptr && !spans_.empty(); }

    Utf8 message() const;
    void setMessage(Utf8 m);

    SourceCodeLocation location(uint32_t spanIndex, const TaskContext& ctx) const;
    SourceCodeLocation location(const DiagnosticSpan& span, const TaskContext& ctx) const;
    std::string_view   idName() const;
    DiagnosticId       id() const { return id_; }
    DiagnosticSeverity severity() const { return severity_; }
    void               setSeverity(DiagnosticSeverity sev) { severity_ = sev; }
    bool               isNoteOrHelp() const;

private:
    Utf8                        message_;
    DiagnosticId                id_;
    DiagnosticSeverity          severity_;
    const SourceView*           srcView_ = nullptr;
    std::vector<DiagnosticSpan> spans_;
};

SWC_END_NAMESPACE();
