#pragma once
#include "Report/DiagnosticElement.h"
#include "Report/DiagnosticIds.h"

SWC_BEGIN_NAMESPACE()

enum class LogColor;

class Context;
enum class DiagnosticId;

enum class DiagnosticSeverity
{
    Error,
    Warning,
    Note,
    Help,
};

class Diagnostic
{
    std::vector<std::unique_ptr<DiagnosticElement>> elements_;
    SourceFile*                                     fileOwner_ = nullptr;

    // Enum for colorable diagnostic parts
    enum class DiagPart : uint8_t
    {
        FileLocationArrow, // "-->"
        FileLocationPath,  // file path or filename
        FileLocationSep,   // ":" between file/line/col
        GutterBar,         // " |"
        LineNumber,        // left-hand line numbers
        CodeText,          // source code line
        SubLabelPrefix,    // secondary label ("note", "help", etc.)
        Reset,             // reset sequence
    };

    struct AnsiSeq
    {
        std::vector<LogColor> seq;
        AnsiSeq(std::initializer_list<LogColor> s) :
            seq(s)
        {
        }
    };

    static AnsiSeq          diagPalette(DiagPart p);
    static Utf8             toAnsiSeq(const Context& ctx, const AnsiSeq& s);
    static Utf8             partStyle(const Context& ctx, DiagPart p);
    static std::string_view severityStr(DiagnosticSeverity s);
    static Utf8             severityColor(const Context& ctx, DiagnosticSeverity s);
    static uint32_t         digits(uint32_t n);
    static void             writeSubLabel(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg, uint32_t gutterW);
    static void             writeFileLocation(Utf8& out, const Context& ctx, const std::string& path, uint32_t line, uint32_t col, uint32_t len, uint32_t gutterW);
    static void             writeGutter(Utf8& out, const Context& ctx, uint32_t gutterW);
    ;
    static void writeGutterSep(Utf8& out, const Context& ctx, uint32_t gutterW);
    static void writeCodeLine(Utf8& out, const Context& ctx, uint32_t gutterW, uint32_t lineNo, std::string_view code);
    static void writeFullUnderline(Utf8& out, const Context& ctx, DiagnosticSeverity sev, const Utf8& msg, uint32_t gutterW, uint32_t columnOneBased, uint32_t underlineLen);
    static void writeCodeBlock(Utf8& out, const Context& ctx, const DiagnosticElement& el, uint32_t gutterW);

    Utf8 build(const Context& ctx) const;

public:
    explicit Diagnostic(SourceFile* fileOwner = nullptr) :
        fileOwner_(fileOwner)
    {
    }

    void                                                   report(const Context& ctx) const;
    const std::vector<std::unique_ptr<DiagnosticElement>>& elements() const { return elements_; }
    SourceFile*                                            fileOwner() const { return fileOwner_; }

    DiagnosticElement* addElement(DiagnosticSeverity kind, DiagnosticId id);
    DiagnosticElement* addError(DiagnosticId id) { return addElement(DiagnosticSeverity::Error, id); }
    DiagnosticElement* addNote(DiagnosticId id) { return addElement(DiagnosticSeverity::Note, id); }
    DiagnosticElement* addHelp(DiagnosticId id) { return addElement(DiagnosticSeverity::Help, id); }

    DiagnosticElement* last() const { return elements_.empty() ? nullptr : elements_.back().get(); }

    static Diagnostic error(DiagnosticId id, SourceFile* fileOwner = nullptr)
    {
        Diagnostic diag(fileOwner);
        diag.addError(id);
        return diag;
    }

    static void reportError(Context& ctx, DiagnosticId id)
    {
        const auto diag = error(id);
        diag.report(ctx);
    }
};

SWC_END_NAMESPACE();
