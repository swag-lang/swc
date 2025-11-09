#include "pch.h"

#include "Core/Hash.h"
#include "Core/Utf8Helper.h"
#include "Lexer/LangSpec.h"
#include "Lexer/Token.h"
#include "Main/CommandLine.h"
#include "Main/Context.h"
#include "Main/Global.h"
#include "Parser/SyntaxColor.h"
#include "Report/LogColor.h"

SWC_BEGIN_NAMESPACE()

namespace
{
    uint32_t getSyntaxColorRgb(SyntaxColor color, uint32_t lum)
    {
        RgbColor rgb;
        switch (color)
        {
        case SyntaxColor::SyntaxCode:
            rgb = {.r = 0xCC, .g = 0xCC, .b = 0xCC};
            break;
        case SyntaxColor::SyntaxComment:
            rgb = {.r = 0x6A, .g = 0x99, .b = 0x55};
            break;
        case SyntaxColor::SyntaxCompiler:
            rgb = {.r = 0xAA, .g = 0xAA, .b = 0xAA};
            break;
        case SyntaxColor::SyntaxFunction:
            rgb = {.r = 0xFF, .g = 0x74, .b = 0x11};
            break;
        case SyntaxColor::SyntaxConstant:
            rgb = {.r = 0x4E, .g = 0xC9, .b = 0xB0};
            break;
        case SyntaxColor::SyntaxIntrinsic:
            rgb = {.r = 0xdc, .g = 0xdc, .b = 0xaa};
            break;
        case SyntaxColor::SyntaxType:
            rgb = {.r = 0xf6, .g = 0xcc, .b = 0x86};
            break;
        case SyntaxColor::SyntaxKeyword:
            rgb = {.r = 0x56, .g = 0x9c, .b = 0xd6};
            break;
        case SyntaxColor::SyntaxLogic:
            rgb = {.r = 0xd8, .g = 0xa0, .b = 0xdf};
            break;
        case SyntaxColor::SyntaxNumber:
            rgb = {.r = 0xb5, .g = 0xce, .b = 0xa8};
            break;
        case SyntaxColor::SyntaxString:
            rgb = {.r = 0xce, .g = 0x91, .b = 0x78};
            break;
        case SyntaxColor::SyntaxAttribute:
            rgb = {.r = 0xaa, .g = 0xaa, .b = 0xaa};
            break;
        case SyntaxColor::SyntaxRegister:
            rgb = {.r = 0xBC, .g = 0xB6, .b = 0x58};
            break;

        case SyntaxColor::SyntaxInvalid:
            rgb = {.r = 0xFF, .g = 0x47, .b = 0x47};
            break;
        default:
            std::unreachable();
        }

        if (lum != 0)
        {
            float h, s, l;
            LogColorHelper::rgbToHsl(rgb, &h, &s, &l);
            rgb = LogColorHelper::hslToRgb(h, s, static_cast<float>(lum) / 100.0f);
        }

        return rgb.r << 16 | rgb.g << 8 | rgb.b;
    }

    Utf8 syntaxColorToAnsi(const Context& ctx, SyntaxColor color, SyntaxColorMode mode)
    {
        switch (mode)
        {
        case SyntaxColorMode::ForLog:
        {
            if (color == SyntaxColor::SyntaxDefault)
                color = SyntaxColor::SyntaxCode;
            const auto rgb = getSyntaxColorRgb(color, ctx.cmdLine().syntaxColorLum);
            return LogColorHelper::colorToAnsi((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
        }

        case SyntaxColorMode::ForDoc:
        {
            const char* colorName = nullptr;
            switch (color)
            {
            case SyntaxColor::SyntaxDefault:
                return "</span>";
            case SyntaxColor::SyntaxCode:
                colorName = SYN_CODE;
                break;
            case SyntaxColor::SyntaxComment:
                colorName = SYN_COMMENT;
                break;
            case SyntaxColor::SyntaxCompiler:
                colorName = SYN_COMPILER;
                break;
            case SyntaxColor::SyntaxFunction:
                colorName = SYN_FUNCTION;
                break;
            case SyntaxColor::SyntaxConstant:
                colorName = SYN_CONSTANT;
                break;
            case SyntaxColor::SyntaxIntrinsic:
                colorName = SYN_INTRINSIC;
                break;
            case SyntaxColor::SyntaxType:
                colorName = SYN_TYPE;
                break;
            case SyntaxColor::SyntaxKeyword:
                colorName = SYN_KEYWORD;
                break;
            case SyntaxColor::SyntaxLogic:
                colorName = SYN_LOGIC;
                break;
            case SyntaxColor::SyntaxNumber:
                colorName = SYN_NUMBER;
                break;
            case SyntaxColor::SyntaxRegister:
                colorName = SYN_REGISTER;
                break;
            case SyntaxColor::SyntaxString:
                colorName = SYN_STRING;
                break;
            case SyntaxColor::SyntaxAttribute:
                colorName = SYN_ATTRIBUTE;
                break;
            case SyntaxColor::SyntaxInvalid:
                colorName = SYN_INVALID;
                break;
            }

            if (colorName)
                return std::format("<span class=\"{}\">", colorName);
            break;
        }
        }

        std::unreachable();
    }
}

Utf8 SyntaxColorHelper::colorize(const Context& ctx, SyntaxColorMode mode, const std::string_view& line, bool force)
{
    const auto& cmdLine  = ctx.cmdLine();
    const auto& langSpec = ctx.global().langSpec();

    if (!force)
    {
        if (!cmdLine.syntaxColor)
            return line;
        if (!cmdLine.logColor)
            return line;
    }

    auto       cur = reinterpret_cast<const uint8_t*>(line.data());
    const auto end = reinterpret_cast<const uint8_t*>(line.data() + line.size());
    Utf8       result;
    uint32_t   c, offset;
    uint32_t   multiLineCommentLevel = 0;

    bool hasCode = false;
    cur          = Utf8Helper::decodeOneChar(cur, end, c, offset);
    while (c)
    {
        // Multi-line comment
        if (multiLineCommentLevel || (c == '/' && cur[0] == '*'))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxComment, mode);

            result += c;
            if (!multiLineCommentLevel)
            {
                result += *cur++;
                multiLineCommentLevel++;
            }

            while (*cur)
            {
                if (cur[0] == '/' && cur[1] == '*')
                {
                    multiLineCommentLevel++;
                    result += "*/";
                    cur += 2;
                    continue;
                }

                if (cur[0] == '*' && cur[1] == '/')
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
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
            continue;
        }

        // Line comment
        if (c == '/' && cur[0] == '/')
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxComment, mode);
            result += c;
            while (*cur && !langSpec.isEol(*cur))
                result += *cur++;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
            continue;
        }

        // Attribute
        if (c == '#' && *cur == '[')
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxAttribute, mode);
            result += c;
            result += *cur++;

            int cpt = 1;
            while (cpt && *cur)
            {
                if (*cur == '"')
                {
                    result += *cur++;
                    while (*cur && *cur != '"')
                    {
                        if (*cur == '\\')
                        {
                            result += *cur++;
                            result += *cur++;
                        }
                        else
                            result += *cur++;
                    }
                    if (*cur)
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
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
            continue;
        }

        // Raw string
        if (c == '#' && *cur == '"')
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxString, mode);
            result += c;
            while (*cur && (cur[0] != '"' || cur[1] != '#'))
                result += *cur++;

            if (*cur)
            {
                result += *cur++;
                result += *cur++;
            }

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
            continue;
        }

        // String
        if (c == '"')
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxString, mode);
            result += c;
            while (*cur && *cur != '"')
            {
                if (*cur == '\\')
                    result += *cur++;
                if (*cur)
                    result += *cur++;
            }

            if (*cur == '"')
                result += *cur++;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
            continue;
        }

        // Character
        if (c == '\'')
        {
            Utf8 word;
            word += c;
            auto pz1 = cur;
            while (langSpec.isAscii(*pz1) || langSpec.isDigit(*pz1))
                word += *pz1++;
            if (*pz1 == '\'')
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxString, mode);
                result += c;
                while (*cur && *cur != '\'')
                {
                    if (*cur == '\\')
                        result += *cur++;
                    if (*cur)
                        result += *cur++;
                }

                if (*cur == '\'')
                    result += *cur++;
                cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                continue;
            }
        }

        // Binary literal
        if (c == '0' && (*cur == 'b' || *cur == 'B'))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxNumber, mode);
            result += c;
            result += *cur++;
            while (*cur && (langSpec.isDigit(*cur) || *cur == '_'))
                result += *cur++;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
            continue;
        }

        // Hexadecimal literal
        if (c == '0' && (*cur == 'x' || *cur == 'X'))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxNumber, mode);
            result += c;
            result += *cur++;
            while (*cur && (langSpec.isHexNumber(*cur) || *cur == '_'))
                result += *cur++;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
            continue;
        }

        // Number
        if (langSpec.isDigit(c))
        {
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxNumber, mode);
            result += c;

            while (*cur && (langSpec.isDigit(*cur) || *cur == '_'))
                result += *cur++;

            if (*cur == '.')
            {
                result += *cur++;
                while (*cur && (langSpec.isDigit(*cur) || *cur == '_'))
                    result += *cur++;
            }

            if (*cur == 'e' || *cur == 'E')
            {
                result += *cur++;
                if (*cur == '-' || *cur == '+')
                    result += *cur++;
                while (*cur && (langSpec.isDigit(*cur) || *cur == '_'))
                    result += *cur++;
            }

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
            continue;
        }

        // Word
        if (langSpec.isLetter(c) || c == '_' || c == '#' || c == '@')
        {
            Utf8 identifier;
            identifier += c;
            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            while (langSpec.isLetter(c) || c == '_' || langSpec.isDigit(c))
            {
                identifier += c;
                cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            }

            const uint64_t hash64  = hash(identifier);
            auto           tokenId = langSpec.keyword(identifier, hash64);
            if (tokenId != TokenId::Identifier)
            {
                if (Token::isModifier(tokenId))
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxIntrinsic, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else if (Token::isCompiler(tokenId))
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxIntrinsic, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else if (Token::isKeyword(tokenId))
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxLogic, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else if (Token::isType(tokenId))
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxType, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else if (Token::isKeyword(tokenId))
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxKeyword, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else if (Token::isCompiler(tokenId))
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxFunction, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else if (Token::isReserved(tokenId))
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxInvalid, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else if (identifier[0] == '@')
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxIntrinsic, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else if (identifier[0] == '#')
                {
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxCompiler, mode);
                    result += identifier;
                    result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                }
                else
                {
                    result += identifier;
                }

                continue;
            }

            if (identifier[0] == '@')
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxIntrinsic, mode);
                result += identifier;
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                continue;
            }

            if (identifier[0] == '#')
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxCompiler, mode);
                result += identifier;
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                continue;
            }

            if (langSpec.isLetter(identifier[0]) && (c == '(' || c == '\''))
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxFunction, mode);
                result += identifier;
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
                continue;
            }

            if (identifier[0] >= 'A' and identifier[0] <= 'Z')
            {
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxConstant, mode);
                result += identifier;
                result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
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
        result.insert(0, syntaxColorToAnsi(ctx, SyntaxColor::SyntaxCode, mode));
        result += syntaxColorToAnsi(ctx, SyntaxColor::SyntaxDefault, mode);
    }

    return result;
}

SWC_END_NAMESPACE()
