#pragma once

class SourceFile;

enum class TokenId : uint32_t
{
    Invalid,
    Blank,
    Eol,
    Comment,
    StringLiteral,
    NumberLiteral,
    CharacterLiteral,
    Identifier,
    Operator,
};

enum class SubTokenStringId : uint32_t
{
    Line,
    Raw,
    MultiLine,
};

enum class SubTokenNumberId : uint32_t
{
    Hexadecimal,
    Binary,
    Integer,
    Float,
};

enum class SubTokenCommentId : uint32_t
{
    Line,
    MultiLine,
};

enum class SubTokenOperatorId : uint32_t
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
    TokenId  id    = TokenId::Invalid;
    uint32_t start = 0;
    uint32_t len   = 0;
    union
    {
        SubTokenStringId   subTokenStringId;   // Valid if id is StringLiteral
        SubTokenNumberId   subTokenNumberId;   // Valid if id is NumberLiteral
        SubTokenCommentId  subTokenCommentId;  // Valid if id is Comment
        SubTokenOperatorId subTokenOperatorId; // Valid if id is Operator
    };

    std::string_view toString(const SourceFile* file) const;
};
