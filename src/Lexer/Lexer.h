#pragma once
#include "Core/Types.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE();

enum class DiagnosticId;
class Diagnostic;
class Context;
class Global;
class SourceFile;
class LangSpec;

// Flags controlling lexer behavior
enum class LexerFlags : uint32_t
{
    Default,
    ExtractTrivia, // Extract whitespace and comments as separate tokens
};
SWC_ENABLE_BITMASK(LexerFlags);

// Represents a piece of trivia (whitespace/comments) with position info
struct TriviaSpan
{
    TokenRef tokenRef; // Reference to the main token this trivia is associated with
    Token    token;    // The actual trivia token
};

// Container for lexer output - tokens, trivia, and line positions
class LexerOutput
{
protected:
    friend class Lexer;
    friend class Parser;
    std::vector<Token>      tokens_; // Main token stream
    std::vector<TriviaSpan> trivia_; // Whitespace and comments
    std::vector<uint32_t>   lines_;  // Byte offsets of each line start

public:
    const std::vector<TriviaSpan>& trivia() const { return trivia_; }
    const std::vector<Token>&      tokens() const { return tokens_; }
    const std::vector<uint32_t>&   lines() const { return lines_; }
};

// Main lexer class - converts source text into tokens
class Lexer
{
    Token token_     = {}; // Current token being built
    Token prevToken_ = {}; // Previous token for context-sensitive parsing

    SourceFile*     file_          = nullptr; // Source file being lexed
    LexerFlags      lexerFlags_    = LexerFlags::Default;
    const uint8_t*  buffer_        = nullptr; // Current position in source
    const uint8_t*  startBuffer_   = nullptr; // Start of source buffer
    const uint8_t*  endBuffer_     = nullptr; // End of source buffer
    const uint8_t*  startToken_    = nullptr; // Start position of the current token
    Context*        ctx_           = nullptr; // Compilation context
    const LangSpec* langSpec_      = nullptr; // Language specification (character classes, keywords)
    bool            hasTokenError_ = false;   // Current token has an error
    bool            hasUtf8Error_  = false;   // UTF-8 decoding error occurred
    bool            rawMode_       = false;   // Raw mode (for extracting comments/trivia only)

    // Check if character is a terminator after escape char in string/char literal
    static bool isTerminatorAfterEscapeChar(uint8_t c, TokenId container);

    // Consume one logical end-of-line (handles CRLF, CR, LF)
    void eatOneEol();

    // Consume one UTF-8 character
    void eatUtf8Char();

    // Add current token to output stream
    void pushToken();

    // Report UTF-8 decoding error
    void reportUtf8Error(DiagnosticId id, uint32_t offset, uint32_t len = 1);

    // Report lexical error in current token
    void reportTokenError(DiagnosticId id, uint32_t offset, uint32_t len = 1);

    // Check for BOM (Byte Order Mark) and validate file encoding
    void checkFormat(const Context& ctx, uint32_t& startOffset);

    // Parse escape sequence (\n, \t, \xHH, \uHHHH, \UHHHHHHHH)
    void lexEscape(TokenId containerToken, bool eatEol);

    // Individual token lexing methods
    void lexEol();                     // End of line
    void lexBlank();                   // Whitespace
    void lexSingleLineStringLiteral(); // "string"
    void lexMultiLineStringLiteral();  // """string"""
    void lexRawStringLiteral();        // #"string"#
    void lexCharacterLiteral();        // 'c'
    void lexHexNumber();               // 0xABCD
    void lexBinNumber();               // 0b1010
    void lexDecimalNumber();           // 123, 123.456, 1.23e10
    void lexNumber();                  // Dispatch to a specific number lexer
    void lexOperator();                // Operators and punctuation
    void lexIdentifier();              // Identifiers and keywords
    void lexSingleLineComment();       // // comment
    void lexMultiLineComment();        // /* comment */

public:
    // Main tokenization entry point
    Result tokenize(Context& ctx, LexerFlags flags = LexerFlags::Default);

    // Tokenize including all trivia (for comment extraction)
    Result tokenizeRaw(Context& ctx);
};

SWC_END_NAMESPACE();
