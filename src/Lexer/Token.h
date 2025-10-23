#pragma once
#include "Keyword.h"

class SourceFile;

enum class TokenId : uint8_t
{
    Invalid,
    Blank,
    Eol,
    Comment,
    StringLiteral,
    NumberLiteral,
    CharacterLiteral,
    Identifier,
    Keyword,
    Intrinsic,
    Compiler,
    Operator,
};

enum class SubTokenStringId : uint16_t
{
    Line,
    Raw,
    MultiLine,
};

enum class SubTokenNumberId : uint16_t
{
    Hexadecimal,
    Binary,
    Integer,
    Float,
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
    Exclam,
    ExclamEqual,
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
        SubTokenStringId     subTokenStringId;     // Valid if id is StringLiteral
        SubTokenNumberId     subTokenNumberId;     // Valid if id is NumberLiteral
        SubTokenCommentId    subTokenCommentId;    // Valid if id is Comment
        SubTokenOperatorId   subTokenOperatorId;   // Valid if id is Operator
        SubTokenIdentifierId subTokenIdentifierId; // Valid if id is Identifier
    };

    std::string_view toString(const SourceFile* file) const;
};
