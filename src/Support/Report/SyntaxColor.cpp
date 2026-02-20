#include "pch.h"
#include "Support/Report/SyntaxColor.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Token.h"
#include "Main/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/LogColor.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint32_t getSyntaxColorRgb(SyntaxColor color, uint32_t lum)
    {
        RgbColor rgb;
        switch (color)
        {
            case SyntaxColor::Code:
                rgb = {.r = 0xCC, .g = 0xCC, .b = 0xCC};
                break;
            case SyntaxColor::InstructionIndex:
                rgb = {.r = 0x00, .g = 0xE6, .b = 0xFF};
                break;
            case SyntaxColor::MicroInstruction:
                rgb = {.r = 0xFF, .g = 0xA5, .b = 0x00};
                break;
            case SyntaxColor::Comment:
                rgb = {.r = 0x6A, .g = 0x99, .b = 0x55};
                break;
            case SyntaxColor::Compiler:
                rgb = {.r = 0xAA, .g = 0xAA, .b = 0xAA};
                break;
            case SyntaxColor::Function:
                rgb = {.r = 0xFF, .g = 0x74, .b = 0x11};
                break;
            case SyntaxColor::Constant:
                rgb = {.r = 0x4E, .g = 0xC9, .b = 0xB0};
                break;
            case SyntaxColor::Intrinsic:
                rgb = {.r = 0xdc, .g = 0xdc, .b = 0xaa};
                break;
            case SyntaxColor::Type:
                rgb = {.r = 0xf6, .g = 0xcc, .b = 0x86};
                break;
            case SyntaxColor::Keyword:
                rgb = {.r = 0x56, .g = 0x9c, .b = 0xd6};
                break;
            case SyntaxColor::Logic:
                rgb = {.r = 0xd8, .g = 0xa0, .b = 0xdf};
                break;
            case SyntaxColor::Number:
                rgb = {.r = 0xb5, .g = 0xce, .b = 0xa8};
                break;
            case SyntaxColor::String:
                rgb = {.r = 0xce, .g = 0x91, .b = 0x78};
                break;
            case SyntaxColor::Attribute:
                rgb = {.r = 0xaa, .g = 0xaa, .b = 0xaa};
                break;
            case SyntaxColor::Register:
                rgb = {.r = 0xBC, .g = 0xB6, .b = 0x58};
                break;
            case SyntaxColor::RegisterVirtual:
                rgb = {.r = 0x5A, .g = 0xB4, .b = 0xFF};
                break;
            case SyntaxColor::Relocation:
                rgb = {.r = 0xE5, .g = 0xC0, .b = 0x7B};
                break;

            case SyntaxColor::Invalid:
                rgb = {.r = 0xFF, .g = 0x47, .b = 0x47};
                break;
            default:
                SWC_UNREACHABLE();
        }

        if (lum != 0)
        {
            float h, s, l;
            LogColorHelper::rgbToHsl(rgb, &h, &s, &l);
            rgb = LogColorHelper::hslToRgb(h, s, static_cast<float>(lum) / 100.0f);
        }

        return rgb.r << 16 | rgb.g << 8 | rgb.b;
    }

    Utf8 syntaxColorToAnsi(const TaskContext& ctx, SyntaxColor color, SyntaxColorMode mode)
    {
        switch (mode)
        {
            case SyntaxColorMode::ForLog:
            {
                if (color == SyntaxColor::Default)
                    return LogColorHelper::toAnsi(ctx, LogColor::Reset);
                const uint32_t rgb = getSyntaxColorRgb(color, ctx.cmdLine().syntaxColorLum);
                return LogColorHelper::colorToAnsi((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
            }

            case SyntaxColorMode::ForDoc:
            {
                std::string_view colorName;
                switch (color)
                {
                    case SyntaxColor::Default:
                        return "</span>";
                    case SyntaxColor::Code:
                        colorName = SYN_CODE;
                        break;
                    case SyntaxColor::InstructionIndex:
                        colorName = SYN_INST_INDEX;
                        break;
                    case SyntaxColor::MicroInstruction:
                        colorName = SYN_MICRO_INST;
                        break;
                    case SyntaxColor::Comment:
                        colorName = SYN_COMMENT;
                        break;
                    case SyntaxColor::Compiler:
                        colorName = SYN_COMPILER;
                        break;
                    case SyntaxColor::Function:
                        colorName = SYN_FUNCTION;
                        break;
                    case SyntaxColor::Constant:
                        colorName = SYN_CONSTANT;
                        break;
                    case SyntaxColor::Intrinsic:
                        colorName = SYN_INTRINSIC;
                        break;
                    case SyntaxColor::Type:
                        colorName = SYN_TYPE;
                        break;
                    case SyntaxColor::Keyword:
                        colorName = SYN_KEYWORD;
                        break;
                    case SyntaxColor::Logic:
                        colorName = SYN_LOGIC;
                        break;
                    case SyntaxColor::Number:
                        colorName = SYN_NUMBER;
                        break;
                    case SyntaxColor::Register:
                        colorName = SYN_REGISTER;
                        break;
                    case SyntaxColor::RegisterVirtual:
                        colorName = SYN_REGISTER_V;
                        break;
                    case SyntaxColor::Relocation:
                        colorName = SYN_RELOCATION;
                        break;
                    case SyntaxColor::String:
                        colorName = SYN_STRING;
                        break;
                    case SyntaxColor::Attribute:
                        colorName = SYN_ATTRIBUTE;
                        break;
                    case SyntaxColor::Invalid:
                        colorName = SYN_INVALID;
                        break;
                }

                if (!colorName.empty())
                    return std::format("<span class=\"{}\">", colorName);
                break;
            }
        }

        SWC_UNREACHABLE();
    }
}

Utf8 SyntaxColorHelper::colorize(const TaskContext& ctx, SyntaxColorMode mode, const std::string_view& line, bool force)
{
    const CommandLine& cmdLine = ctx.cmdLine();

    if (!force)
    {
        if (!cmdLine.syntaxColor)
            return line;
        if (!cmdLine.logColor)
            return line;
    }

    const LangSpec& langSpec = ctx.global().langSpec();
    auto            cur      = reinterpret_cast<const char8_t*>(line.data());
    auto            end      = reinterpret_cast<const char8_t*>(line.data() + line.size());
    Utf8            result;
    char32_t        c;
    uint32_t        offset;
    uint32_t        multiLineCommentLevel = 0;

    bool hasCode = false;
    cur          = Utf8Helper::decodeOneChar(cur, end, c, offset);
    while (c)
    {
        // Multi-line comment
        if (multiLineCommentLevel || (c == '/' && (cur < end && cur[0] == '*')))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::Comment, mode);

            result += c;
            if (!multiLineCommentLevel)
            {
                if (cur < end)
                {
                    result += *cur++;
                    multiLineCommentLevel++;
                }
            }

            while (cur < end)
            {
                if ((cur + 1) < end && cur[0] == '/' && cur[1] == '*')
                {
                    multiLineCommentLevel++;
                    result += "/*"; // fixed: was "*/"
                    cur += 2;
                    continue;
                }

                if ((cur + 1) < end && cur[0] == '*' && cur[1] == '/')
                {
                    result += "*/";
                    cur += 2;
                    multiLineCommentLevel--;
                    if (multiLineCommentLevel == 0)
                        break;
                    continue;
                }

                result += *cur++;
            }

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
            continue;
        }

        // Line comment
        if (c == '/' && (cur < end && cur[0] == '/'))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::Comment, mode);
            result += c;
            while (cur < end && !langSpec.isEol(*cur))
                result += *cur++;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
            continue;
        }

        // Attribute
        if (c == '#' && (cur < end && *cur == '['))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::Attribute, mode);
            result += c;
            result += *cur++;

            int cpt = 1;
            while (cpt && cur < end)
            {
                if (*cur == '"')
                {
                    result += *cur++;
                    while (cur < end && *cur != '"')
                    {
                        if (*cur == '\\' && (cur + 1) < end)
                        {
                            result += *cur++;
                            result += *cur++;
                        }
                        else
                        {
                            result += *cur++;
                        }
                    }
                    if (cur < end)
                        result += *cur++;
                    continue;
                }
                if (*cur == '[')
                    cpt++;
                else if (*cur == ']')
                    cpt--;
                result += *cur++;
            }

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
            continue;
        }

        // Raw string  #"... "#
        if (c == '#' && (cur < end && *cur == '"'))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::String, mode);
            result += c;
            while (cur < end && !(cur[0] == '"' && (cur + 1) < end && cur[1] == '#'))
                result += *cur++;

            if ((cur + 1) < end)
            {
                result += *cur++;
                result += *cur++;
            }

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
            continue;
        }

        // String
        if (c == '"')
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::String, mode);
            result += c;
            while (cur < end && *cur != '"')
            {
                if (*cur == '\\' && (cur + 1) < end)
                    result += *cur++;
                if (cur < end)
                    result += *cur++;
            }

            if (cur < end && *cur == '"')
                result += *cur++;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
            continue;
        }

        // Character
        if (c == '\'')
        {
            Utf8 word;
            word += c;
            const char8_t* pz1 = cur;
            while (pz1 < end && (langSpec.isAscii(*pz1) || langSpec.isDigit(*pz1)))
                word += *pz1++;
            if (pz1 < end && *pz1 == '\'')
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::String, mode);
                result += c;
                while (cur < end && *cur != '\'')
                {
                    if (*cur == '\\' && (cur + 1) < end)
                        result += *cur++;
                    if (cur < end)
                        result += *cur++;
                }

                if (cur < end && *cur == '\'')
                    result += *cur++;
                cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
                result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
                continue;
            }
        }

        // Binary literal
        if (c == '0' && (cur < end && (*cur == 'b' || *cur == 'B')))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::Number, mode);
            result += c;
            result += *cur++;
            while (cur < end && (*cur == '0' || *cur == '1' || *cur == '_'))
                result += *cur++;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
            continue;
        }

        // Hexadecimal literal
        if (c == '0' && (cur < end && (*cur == 'x' || *cur == 'X')))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::Number, mode);
            result += c;
            result += *cur++;
            while (cur < end && (langSpec.isHexNumber(*cur) || *cur == '_'))
                result += *cur++;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
            continue;
        }

        // Number
        if (langSpec.isDigit(c))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::Number, mode);
            result += c;

            while (cur < end && (langSpec.isDigit(*cur) || *cur == '_'))
                result += *cur++;

            if (cur < end && *cur == '.')
            {
                result += *cur++;
                while (cur < end && (langSpec.isDigit(*cur) || *cur == '_'))
                    result += *cur++;
            }

            if (cur < end && (*cur == 'e' || *cur == 'E'))
            {
                result += *cur++;
                if (cur < end && (*cur == '-' || *cur == '+'))
                    result += *cur++;
                while (cur < end && (langSpec.isDigit(*cur) || *cur == '_'))
                    result += *cur++;
            }

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
            continue;
        }

        // Word
        if (langSpec.isIdentifierStart(c))
        {
            Utf8 identifier;
            identifier += c;

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            while (langSpec.isIdentifierPart(c))
            {
                identifier += c;
                cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            }

            const TokenId tokenId = langSpec.keyword(identifier);
            if (tokenId != TokenId::Identifier)
            {
                auto tokColor = SyntaxColor::Code;
                if (Token::isModifier(tokenId))
                    tokColor = SyntaxColor::Intrinsic;
                else if (Token::isCompilerIntrinsic(tokenId))
                    tokColor = SyntaxColor::Intrinsic;
                else if (Token::isCompilerAlias(tokenId))
                    tokColor = SyntaxColor::Intrinsic;
                else if (Token::isCompilerUniq(tokenId))
                    tokColor = SyntaxColor::Intrinsic;
                else if (Token::isReserved(tokenId))
                    tokColor = SyntaxColor::Invalid;
                else if (Token::isKeywordLogic(tokenId))
                    tokColor = SyntaxColor::Logic;
                else if (Token::isType(tokenId))
                    tokColor = SyntaxColor::Type;
                else if (tokenId == TokenId::KwdMe)
                    tokColor = SyntaxColor::Type;
                else if (Token::isIntrinsic(tokenId))
                    tokColor = SyntaxColor::Intrinsic;
                else if (Token::isKeyword(tokenId))
                    tokColor = SyntaxColor::Keyword;
                else if (Token::isCompilerFunc(tokenId))
                    tokColor = SyntaxColor::Function;
                else if (Token::isCompiler(tokenId))
                    tokColor = SyntaxColor::Compiler;

                if (tokColor != SyntaxColor::Code)
                {
                    result += syntaxColorToAnsi(ctx, tokColor, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
                }
                else
                {
                    result += identifier;
                }

                continue;
            }

            if (identifier[0] == '@' || identifier[0] == '#')
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::Invalid, mode);
                result += identifier;
                result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
                continue;
            }

            if (langSpec.isLetter(identifier[0]) && (c == '(' || c == '\''))
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::Function, mode);
                result += identifier;
                result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
                continue;
            }

            if (identifier[0] >= 'A' and identifier[0] <= 'Z')
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::Constant, mode);
                result += identifier;
                result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
                continue;
            }

            hasCode = true;
            result += identifier;
            continue;
        }

        hasCode = true;
        result += c;
        cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
    }

    if (hasCode)
    {
        result.insert(0, syntaxColorToAnsi(ctx, SyntaxColor::Code, mode));
        result += syntaxColorToAnsi(ctx, SyntaxColor::Default, mode);
    }

    return result;
}

Utf8 SyntaxColorHelper::toAnsi(const TaskContext& ctx, SyntaxColor color, SyntaxColorMode mode)
{
    if (mode == SyntaxColorMode::ForLog && !ctx.cmdLine().logColor)
        return "";

    return syntaxColorToAnsi(ctx, color, mode);
}

SWC_END_NAMESPACE();
