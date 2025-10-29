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
#define SWC_DIAG_DEF(id) id,
#include "Report/DiagnosticIds_Errors_.def"

#include "Report/DiagnosticIds_Notes_.def"

#undef SWC_DIAG_DEF
};

struct DiagnosticIdInfo
{
    DiagnosticId       id;
    DiagnosticSeverity severity;
    std::string_view   name;
    std::string_view   msg;
};

extern DiagnosticIdInfo g_Diagnostic_Infos[];

class Diagnostic
{
    struct Argument
    {
        std::string_view                      name;
        std::variant<Utf8, uint64_t, int64_t> val;
        bool                                  quoted;
    };

    std::vector<std::shared_ptr<DiagnosticElement>> elements_;
    std::vector<Argument>                           arguments_;
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

    void expandMessageParts(SmallVector<std::unique_ptr<DiagnosticElement>>& elements) const;

    static void writeSubLabel(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg);
    static void writeFileLocation(Utf8& out, const Context& ctx, const std::string& path, uint32_t line, uint32_t col, uint32_t len, uint32_t gutterW);
    static void writeGutter(Utf8& out, const Context& ctx, uint32_t gutterW);
    static void writeHighlightedMessage(Utf8& out, const Context& ctx, DiagnosticSeverity sev, std::string_view msg, const Utf8& reset);
    static void writeGutterSep(Utf8& out, const Context& ctx, uint32_t gutterW);
    static void writeCodeLine(Utf8& out, const Context& ctx, uint32_t gutterW, uint32_t lineNo, std::string_view code);
    static void writeFullUnderline(Utf8& out, const Context& ctx, DiagnosticSeverity sev, const Utf8& msg, uint32_t gutterW, uint32_t columnOneBased, uint32_t underlineLen);

    Utf8 message(const DiagnosticElement& el) const;
    void writeCodeBlock(Utf8& out, const Context& ctx, const DiagnosticElement& el, uint32_t gutterW) const;

    Utf8 build(const Context& ctx) const;
    void report(const Context& ctx) const;

    Utf8 argumentToString(const Argument& arg) const;

public:
    constexpr static std::string_view ARG_TOK          = "{tok}";
    constexpr static std::string_view ARG_END          = "{end}";
    constexpr static std::string_view ARG_TOK_FAM      = "{tok-fam}";
    constexpr static std::string_view ARG_A_TOK_FAM    = "{a-tok-fam}";
    constexpr static std::string_view ARG_EXPECT       = "{expect}";
    constexpr static std::string_view ARG_EXPECT_FAM   = "{expect-fam}";
    constexpr static std::string_view ARG_A_EXPECT_FAM = "{a-expect-fam}";
    constexpr static std::string_view ARG_AFTER        = "{after}";
    constexpr static std::string_view ARG_REASON       = "{reason}";
    constexpr static std::string_view ARG_PATH         = "{path}";
    constexpr static std::string_view ARG_ARG          = "{arg}";
    constexpr static std::string_view ARG_COMMAND      = "{command}";
    constexpr static std::string_view ARG_VALUE        = "{value}";
    constexpr static std::string_view ARG_VALUES       = "{values}";
    constexpr static std::string_view ARG_LONG         = "{long}";
    constexpr static std::string_view ARG_SHORT        = "{short}";

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
    void addArgument(std::string_view name, T&& arg, bool quoted = true)
    {
        arguments_.emplace_back(Argument{name, std::forward<T>(arg), quoted});
    }

    void addArgument(std::string_view name, std::string_view arg, bool quoted = true);

    static Diagnostic raise(const Context& ctx, DiagnosticId id, std::optional<SourceFile*> fileOwner = std::nullopt)
    {
        Diagnostic diag(ctx, fileOwner);
        diag.addElement(id);
        return diag;
    }

    static std::string_view   diagIdMessage(DiagnosticId id) { return g_Diagnostic_Infos[static_cast<size_t>(id)].msg; }
    static std::string_view   diagIdName(DiagnosticId id) { return g_Diagnostic_Infos[static_cast<size_t>(id)].name; }
    static DiagnosticSeverity diagIdSeverity(DiagnosticId id) { return g_Diagnostic_Infos[static_cast<size_t>(id)].severity; }
};

SWC_END_NAMESPACE()
