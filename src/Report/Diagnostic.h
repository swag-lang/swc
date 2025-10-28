#pragma once
#include "Report/DiagnosticElement.h"

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

enum class DiagnosticId
{
    None = 0,
#define SWC_DIAG_DEF(id, sev, msg) id,
#include "DiagnosticIds.inc"

#undef SWC_DIAG_DEF
};

struct DiagnosticIdInfo
{
    DiagnosticId       id;
    DiagnosticSeverity severity;
    std::string_view   name;
    std::string_view   msg;
};

constexpr DiagnosticIdInfo DIAGNOSTIC_INFOS[] = {
    {DiagnosticId::None, DiagnosticSeverity::Error, "", ""},
#define SWC_DIAG_DEF(id, sev, msg) {DiagnosticId::id, DiagnosticSeverity::sev, #id, msg},
#include "DiagnosticIds.inc"

#undef SWC_DIAG_DEF
};

class Diagnostic
{
    std::vector<std::unique_ptr<DiagnosticElement>> elements_;
    std::optional<SourceFile*>                      fileOwner_ = std::nullopt;

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
        SubLabelText,      // secondary label message
        Severity,          // color for severity labels/underlines
        QuoteText,         // color for quoted text based on severity
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

    static AnsiSeq          diagPalette(DiagPart p, std::optional<DiagnosticSeverity> sev = std::nullopt);
    static Utf8             toAnsiSeq(const Context& ctx, const AnsiSeq& s);
    static Utf8             partStyle(const Context& ctx, DiagPart p);
    static Utf8             partStyle(const Context& ctx, DiagPart p, DiagnosticSeverity sev);
    static std::string_view severityStr(DiagnosticSeverity s);
    static uint32_t         digits(uint32_t n);
    static void             expandMessageParts(SmallVector<std::unique_ptr<DiagnosticElement>>& elements);

    static void writeSubLabel(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg, uint32_t gutterW);
    static void writeFileLocation(Utf8& out, const Context& ctx, const std::string& path, uint32_t line, uint32_t col, uint32_t len, uint32_t gutterW);
    static void writeGutter(Utf8& out, const Context& ctx, uint32_t gutterW);
    static void writeHighlightedMessage(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg, const Utf8& reset);
    static void writeGutterSep(Utf8& out, const Context& ctx, uint32_t gutterW);
    static void writeCodeLine(Utf8& out, const Context& ctx, uint32_t gutterW, uint32_t lineNo, std::string_view code);
    static void writeFullUnderline(Utf8& out, const Context& ctx, DiagnosticSeverity sev, const Utf8& msg, uint32_t gutterW, uint32_t columnOneBased, uint32_t underlineLen);
    static void writeCodeBlock(Utf8& out, const Context& ctx, const DiagnosticElement& el, uint32_t gutterW);

    Utf8 build(const Context& ctx) const;

public:
    explicit Diagnostic(const std::optional<SourceFile*>& fileOwner = std::nullopt) :
        fileOwner_(fileOwner)
    {
    }

    void                                                   report(const Context& ctx) const;
    const std::vector<std::unique_ptr<DiagnosticElement>>& elements() const { return elements_; }
    const std::optional<SourceFile*>&                      fileOwner() const { return fileOwner_; }

    DiagnosticElement& addElement(DiagnosticId id);
    DiagnosticElement& last() const { return *elements_.back(); }

    static Diagnostic error(DiagnosticId id, std::optional<SourceFile*> fileOwner = std::nullopt)
    {
        Diagnostic diag(fileOwner);
        diag.addElement(id);
        return diag;
    }

    static std::string_view   diagIdMessage(DiagnosticId id) { return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].msg; }
    static std::string_view   diagIdName(DiagnosticId id) { return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].name; }
    static DiagnosticSeverity diagIdSeverity(DiagnosticId id) { return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].severity; }
};

SWC_END_NAMESPACE();
