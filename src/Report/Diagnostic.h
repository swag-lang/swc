#pragma once
#include "Report/DiagnosticElement.h"
#include "Report/DiagnosticIds.h"

SWC_BEGIN_NAMESPACE();

class EvalContext;
enum class DiagnosticId;

enum class DiagnosticSeverity
{
    Error,
    Warning,
    Note,
    Hint,
};

class Diagnostic
{
    std::vector<std::unique_ptr<DiagnosticElement>> elements_;
    SourceFile*                                     fileOwner_ = nullptr;

    Utf8 build(EvalContext& ctx) const;

public:
    explicit Diagnostic(SourceFile* fileOwner = nullptr) :
        fileOwner_(fileOwner)
    {
    }

    void                                                   report(EvalContext& ctx) const;
    const std::vector<std::unique_ptr<DiagnosticElement>>& elements() const { return elements_; }
    SourceFile*                                            fileOwner() const { return fileOwner_; }

    DiagnosticElement* addElement(DiagnosticSeverity kind, DiagnosticId id);
    DiagnosticElement* addError(DiagnosticId id) { return addElement(DiagnosticSeverity::Error, id); }

    DiagnosticElement* last() const { return elements_.empty() ? nullptr : elements_.back().get(); }

    static Diagnostic error(DiagnosticId id, SourceFile* fileOwner = nullptr)
    {
        Diagnostic diag(fileOwner);
        diag.addError(id);
        return diag;
    }

    static void reportError(EvalContext& ctx, DiagnosticId id)
    {
        const auto diag = error(id);
        diag.report(ctx);
    }
};

SWC_END_NAMESPACE();
