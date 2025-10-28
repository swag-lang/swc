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
#include "Report/DiagnosticIds_Errors_.inc"

#include "Report/DiagnosticIds_Notes_.inc"

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
    {.id = DiagnosticId::None, .severity = DiagnosticSeverity::Error, .name = "", .msg = ""},
#define SWC_DIAG_DEF(id, sev, msg) {DiagnosticId::id, DiagnosticSeverity::sev, #id, msg},
#include "DiagnosticIds_Errors_.inc"

#include "DiagnosticIds_Notes_.inc"

#undef SWC_DIAG_DEF
};

class Diagnostic
{
    std::vector<std::shared_ptr<DiagnosticElement>> elements_;
    std::optional<SourceFile*>                      fileOwner_ = std::nullopt;
    const Context*                                  context_   = nullptr;

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
    void report(const Context& ctx) const;

public:
    constexpr static std::string_view ARG_TOK     = "{tok}";
    constexpr static std::string_view ARG_EXPECT  = "{expect}";
    constexpr static std::string_view ARG_AFTER   = "{after}";
    constexpr static std::string_view ARG_REASON  = "{reason}";
    constexpr static std::string_view ARG_PATH    = "{path}";
    constexpr static std::string_view ARG_ARG     = "{arg}";
    constexpr static std::string_view ARG_COMMAND = "{command}";
    constexpr static std::string_view ARG_VALUE   = "{value}";
    constexpr static std::string_view ARG_VALUES  = "{values}";
    constexpr static std::string_view ARG_LONG    = "{long}";
    constexpr static std::string_view ARG_SHORT   = "{short}";

    explicit Diagnostic(const Context& context, const std::optional<SourceFile*>& fileOwner = std::nullopt) :
        fileOwner_(fileOwner),
        context_(&context)
    {
    }

    ~Diagnostic()
    {
        SWC_ASSERT(context_);
        report(*context_);
    }

    const std::vector<std::shared_ptr<DiagnosticElement>>& elements() const { return elements_; }
    const std::optional<SourceFile*>&                      fileOwner() const { return fileOwner_; }

    DiagnosticElement& addElement(DiagnosticId id);
    DiagnosticElement& last() const { return *elements_.back(); }

    template<typename T>
    Diagnostic addArgument(std::string_view name, T&& arg)
    {
        last().addArgument(name, std::forward<T>(arg));
        return *this;
    }

    static Diagnostic raise(const Context& ctx, DiagnosticId id, std::optional<SourceFile*> fileOwner = std::nullopt)
    {
        Diagnostic diag(ctx, fileOwner);
        diag.addElement(id);
        return diag;
    }

    static std::string_view   diagIdMessage(DiagnosticId id) { return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].msg; }
    static std::string_view   diagIdName(DiagnosticId id) { return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].name; }
    static DiagnosticSeverity diagIdSeverity(DiagnosticId id) { return DIAGNOSTIC_INFOS[static_cast<size_t>(id)].severity; }
};

SWC_END_NAMESPACE();
