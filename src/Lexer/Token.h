#pragma once
#include "Keyword.h"

SWC_BEGIN_NAMESPACE();

class SourceFile;

enum class TokenId : uint8_t
{
    Invalid,
    Blank,
    Eol,
    Comment,

    StringLine,
    StringRaw,
    StringMultiLine,

    NumberHexadecimal,
    NumberBinary,
    NumberInteger,
    NumberFloat,

    Character,
    Identifier,
    Keyword,
    Intrinsic,
    Compiler,
    Operator,
    EndOfFile,
};

enum class SubTokenCommentId : uint16_t
{
    Line,
    MultiLine,
};

enum class SubTokenOperatorId : uint16_t
{
    Quote,
    BackSlash,
    LeftParen,
    RightParen,
    LeftSquare,
    RightSquare,
    LeftCurly,
    RightCurly,
    SemiColon,
    Comma,
    At,
    Question,
    Tilde,
    Equal,
    EqualEqual,
    EqualGreater,
    Colon,
    Exclamation,
    ExclamationEqual,
    Minus,
    MinusEqual,
    MinusGreater,
    MinusMinus,
    Plus,
    PlusEqual,
    PlusPlus,
    Asterisk,
    AsteriskEqual,
    Slash,
    SlashEqual,
    Ampersand,
    AmpersandEqual,
    AmpersandAmpersand,
    Vertical,
    VerticalEqual,
    VerticalVertical,
    Circumflex,
    CircumflexEqual,
    Percent,
    PercentEqual,
    Dot,
    DotDot,
    DotDotDot,
    Lower,
    LowerEqual,
    LowerEqualGreater,
    LowerLower,
    LowerLowerEqual,
    Greater,
    GreaterEqual,
    GreaterGreater,
    GreaterGreaterEqual
};

struct Token
{
    uint32_t start = 0;
    uint32_t len   = 0;

    TokenId id      = TokenId::Invalid;
    uint8_t padding = 0;
    union
    {
        SubTokenCommentId    subTokenCommentId;    // Valid if id is Comment
        SubTokenOperatorId   subTokenOperatorId;   // Valid if id is Operator
        SubTokenIdentifierId subTokenIdentifierId; // Valid if id is Identifier
    };

    std::string_view toString(const SourceFile* file) const;
};

SWC_END_NAMESPACE();
