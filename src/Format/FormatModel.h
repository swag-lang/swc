#pragma once
#include "Compiler/Lexer/Token.h"
#include "Format/FormatOptions.h"
#include "Support/Core/Flags.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class SourceView;

// Semantic roles attached to pieces by the classifier. They tell the formatting
// passes what a token *means* (a call paren vs a declaration paren, a struct
// field colon vs a base clause colon, ...) without having to re-query the AST.
enum class FormatRoleE : uint64_t
{
    Zero           = 0,
    CallOpenParen  = 1ULL << 0,  // `(` opening a call argument list
    DeclOpenParen  = 1ULL << 1,  // `(` opening a parameter list (func decl, lambda, attr decl)
    CastCloseParen = 1ULL << 2,  // `)` closing a `cast(...)` type list
    DeclColon      = 1ULL << 3,  // `:` between a declaration name and its type
    BaseClauseColon= 1ULL << 4,  // `:` introducing an underlying type (`enum E: u32`)
    CaseColon      = 1ULL << 5,  // `:` after `case X` / `default`
    AssignOp       = 1ULL << 6,  // assignment operator of an assign statement (incl. compound)
    InitAssign     = 1ULL << 7,  // `=` between a declaration and its initializer
    EnumAssign     = 1ULL << 8,  // `=` of an enum value definition
    BinaryOp       = 1ULL << 9,  // binary / relational / logical symbol operator
    UnaryOp        = 1ULL << 10, // unary prefix operator
    RangeOp        = 1ULL << 11, // `..` of a range expression
    Arrow          = 1ULL << 12, // `->` of a signature or lambda type
    FatArrow       = 1ULL << 13, // `=>` of a short body
    ControlKeyword = 1ULL << 14, // `if`/`elif`/`while`/`for`/`switch`/`return`/`defer`/...
    BlockOpen      = 1ULL << 15, // `{` opening a statement / declaration body
    BlockClose     = 1ULL << 16, // `}` closing a statement / declaration body
    LiteralOpen    = 1ULL << 17, // `{` opening an array / struct literal
    LiteralClose   = 1ULL << 18, // `}` closing an array / struct literal
    AttrOpen       = 1ULL << 19, // `#[` of an attribute list
    AttrClose      = 1ULL << 20, // `]` closing an attribute list
    AttrComma      = 1ULL << 21, // `,` directly inside an attribute list
    StmtStart      = 1ULL << 22, // first piece of a statement / declaration
    CaseLabel      = 1ULL << 23, // `case` / `default` keyword of a switch case
    TrailingDo     = 1ULL << 24, // `do` introducing an inline body
    ElseKeyword    = 1ULL << 25, // `else` / `elif`
    UsingStart     = 1ULL << 26, // first piece of a `using` statement
    VarDeclStart   = 1ULL << 27, // first piece of a `var` / `let` declaration
    ConstDeclStart = 1ULL << 28, // first piece of a `const` declaration
    FieldDeclStart = 1ULL << 29, // first piece of a struct / union field
    EnumValueStart = 1ULL << 30, // first piece of an enum value definition
    AssignStart    = 1ULL << 31, // first piece of an assign statement
    FuncDeclStart  = 1ULL << 32, // first piece of a function declaration
    CastKeyword    = 1ULL << 33, // `cast` keyword
    TernaryOp      = 1ULL << 34, // `?` / `:` of a conditional expression
};
using FormatRoles = EnumFlags<FormatRoleE>;

// The kind of construct a `{ ... }` body belongs to.
enum class FormatBlockKind : uint8_t
{
    Plain,     // bare `{ ... }` statement block
    Function,  // function body
    Control,   // body of `if` / `while` / `for` / `defer` / ...
    Struct,    // struct / union body
    Enum,      // enum body
    Interface, // interface body
    Namespace, // namespace body
    Impl,      // impl body
    Switch,    // switch body
};

struct FormatBlock
{
    uint32_t        openPiece  = 0;     // piece index of `{`
    uint32_t        closePiece = 0;     // piece index of `}`
    uint32_t        headPiece  = 0;     // first piece of the owning statement / declaration
    FormatBlockKind kind       = FormatBlockKind::Plain;
    bool            exprLevel  = false; // embedded in an expression or type (closure body, anonymous struct / tuple type)
};

// One token or comment of the source stream.
struct FormatPiece
{
    static constexpr uint32_t INVALID_INDEX = 0xFFFFFFFFu;

    std::string_view text;
    uint32_t         byteStart  = 0;
    uint32_t         match      = INVALID_INDEX; // matching bracket piece, if any
    uint32_t         depth      = 0;             // bracket nesting depth at this piece
    TokenId          id         = TokenId::Invalid;
    FormatRoles      roles      = FormatRoleE::Zero;
    bool             isComment  = false;
    bool             frozen     = false; // inside a format-off region
    bool             removed    = false; // dropped by a pass (renders as nothing)
    bool             replaced   = false; // text points into the model's owned storage

    bool is(const TokenId other) const { return id == other; }
    bool isNot(const TokenId other) const { return id != other; }
    bool hasRole(const FormatRoleE role) const { return roles.has(role); }
};

// The whitespace between two consecutive pieces. When `modified` is false the
// original text is rendered (through the legacy whitespace options); when true
// the gap renders as `newlines` line breaks followed by `indent`, or as
// `spaces` blanks when `newlines` is zero.
struct FormatGap
{
    std::string_view origText;
    uint32_t         newlines = 0;
    uint32_t         spaces   = 0;
    Utf8             indent;
    bool             modified = false;
    bool             frozen   = false;
};

class FormatModel
{
public:
    void build(const SourceView& srcView, const FormatOptions& options);
    void render(Utf8& output) const;

    std::vector<FormatPiece>& pieces() { return pieces_; }
    const std::vector<FormatPiece>& pieces() const { return pieces_; }
    std::vector<FormatBlock>& blocks() { return blocks_; }
    const std::vector<FormatBlock>& blocks() const { return blocks_; }

    const SourceView&    srcView() const { return *srcView_; }
    const FormatOptions& options() const { return *options_; }

    uint32_t numPieces() const { return static_cast<uint32_t>(pieces_.size()); }
    FormatPiece&       piece(uint32_t index) { return pieces_[index]; }
    const FormatPiece& piece(uint32_t index) const { return pieces_[index]; }
    FormatGap&       gapBefore(uint32_t pieceIndex) { return gaps_[pieceIndex]; }
    const FormatGap& gapBefore(uint32_t pieceIndex) const { return gaps_[pieceIndex]; }
    FormatGap&       trailingGap() { return gaps_.back(); }
    const FormatGap& trailingGap() const { return gaps_.back(); }

    // Maps a token index (in srcView.tokens()) to its piece index.
    uint32_t pieceOfToken(uint32_t tokenIndex) const;

    std::string_view eol() const { return eol_; }

    void setGapSpaces(uint32_t pieceIndex, uint32_t spaces);
    void setGapBreak(uint32_t pieceIndex, uint32_t newlines, std::string_view indent);
    void replaceText(uint32_t pieceIndex, Utf8 text);
    void removePiece(uint32_t pieceIndex);

    bool gapHasNewline(uint32_t pieceIndex) const;
    uint32_t gapNewlineCount(uint32_t pieceIndex) const;
    // Visual width of the gap when it stays on a single line.
    uint32_t gapColumns(uint32_t pieceIndex) const;

    uint32_t prevPiece(uint32_t pieceIndex) const; // previous non-removed piece, INVALID_INDEX if none
    uint32_t nextPiece(uint32_t pieceIndex) const; // next non-removed piece, INVALID_INDEX if none

    // First non-removed piece of the line containing `pieceIndex`.
    uint32_t lineStartOf(uint32_t pieceIndex) const;
    // Indentation text of the line containing `pieceIndex` (as currently configured).
    std::string_view lineIndentOf(uint32_t pieceIndex) const;
    void collectLineStarts(std::vector<uint32_t>& out) const;

    // Recomputes bracket matches and depths (needed after piece reordering).
    void computeBrackets();

    const FormatBlock* blockOfOpen(uint32_t pieceIndex) const;
    const FormatBlock* blockOfClose(uint32_t pieceIndex) const;

    static uint32_t textColumns(std::string_view text, uint32_t tabWidth, uint32_t startColumn = 0);

private:
    void detectEol();
    void markDisabledRegions();
    uint32_t maxAllowedNewlines(uint32_t gapIndex) const;
    void renderGap(Utf8& output, uint32_t gapIndex) const;
    void renderOriginalGap(Utf8& output, uint32_t gapIndex) const;
    void renderPiece(Utf8& output, uint32_t pieceIndex) const;
    void renderCommentPiece(Utf8& output, const FormatPiece& piece) const;
    void renderNumberPiece(Utf8& output, const FormatPiece& piece) const;
    void appendIndent(Utf8& output, std::string_view indentText) const;
    void appendEol(Utf8& output) const;
    std::string_view resolveFinalNewline(const Utf8& output) const;

    const SourceView*        srcView_ = nullptr;
    const FormatOptions*     options_ = nullptr;
    std::vector<FormatPiece> pieces_;
    std::vector<FormatGap>   gaps_; // gaps_[i] precedes pieces_[i]; gaps_.back() trails the last piece
    std::vector<FormatBlock> blocks_;
    std::vector<uint32_t>    tokenToPiece_;
    std::deque<Utf8>         ownedTexts_;
    std::string_view         eol_ = "\n";
};

SWC_END_NAMESPACE();
