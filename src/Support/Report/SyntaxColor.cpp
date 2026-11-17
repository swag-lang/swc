#include "pch.h"
#include "Support/Report/SyntaxColor.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Lexer/Token.h"
#include "Main/Command/CommandLine.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 syntaxColorSpan(const SyntaxColor color)
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
            case SyntaxColor::Namespace:
                colorName = SYN_NAMESPACE;
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

        SWC_UNREACHABLE();
    }
}

Utf8 SyntaxColorHelper::colorize(const TaskContext& ctx, const std::string_view& line)
{
    const LangSpec& langSpec = ctx.global().langSpec();
    const auto*     cur      = reinterpret_cast<const char8_t*>(line.data());
    const auto*     end      = reinterpret_cast<const char8_t*>(line.data() + line.size());

    Utf8     result;
    char32_t c;
    uint32_t offset;
    uint32_t multiLineCommentLevel = 0;

    bool hasCode = false;
    cur          = Utf8Helper::decodeOneChar(cur, end, c, offset);

    while (c)
    {
        // Multi-line comment
        if (multiLineCommentLevel || (c == '/' && (cur < end && cur[0] == '*')))
        {
            result += syntaxColorSpan(SyntaxColor::Comment);

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
                    result += "/*";
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
            result += syntaxColorSpan(SyntaxColor::Default);
            continue;
        }

        // Line comment
        if (c == '/' && (cur < end && cur[0] == '/'))
        {
            result += syntaxColorSpan(SyntaxColor::Comment);
            result += c;
            while (cur < end && !langSpec.isEol(*cur))
                result += *cur++;

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorSpan(SyntaxColor::Default);
            continue;
        }

        // Attribute
        if (c == '#' && (cur < end && *cur == '['))
        {
            result += syntaxColorSpan(SyntaxColor::Attribute);
            result += c;
            result += *cur++;

            const char8_t* const attributeBegin = cur;

            int cpt = 1;
            while (cpt && cur < end)
            {
                if ((end - cur) >= 5 && cur[0] == 'S' && cur[1] == 'w' && cur[2] == 'a' && cur[3] == 'g' && cur[4] == '.' &&
                    (cur == attributeBegin || !langSpec.isIdentifierPart(cur[-1])))
                {
                    result += syntaxColorSpan(SyntaxColor::Default);
                    result += syntaxColorSpan(SyntaxColor::Namespace);
                    result += "Swag";
                    cur += 4;
                    result += syntaxColorSpan(SyntaxColor::Default);
                    result += *cur++;
                    result += syntaxColorSpan(SyntaxColor::Attribute);
                    continue;
                }

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
            result += syntaxColorSpan(SyntaxColor::Default);
            continue;
        }

        // Raw string  #"... "#
        if (c == '#' && (cur < end && *cur == '"'))
        {
            result += syntaxColorSpan(SyntaxColor::String);
            result += c;
            while (cur < end && !(cur[0] == '"' && (cur + 1) < end && cur[1] == '#'))
                result += *cur++;

            if ((cur + 1) < end)
            {
                result += *cur++;
                result += *cur++;
            }

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorSpan(SyntaxColor::Default);
            continue;
        }

        // String
        if (c == '"')
        {
            result += syntaxColorSpan(SyntaxColor::String);
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
            result += syntaxColorSpan(SyntaxColor::Default);
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
                result += syntaxColorSpan(SyntaxColor::String);
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
                result += syntaxColorSpan(SyntaxColor::Default);
                continue;
            }
        }

        // Binary literal
        if (c == '0' && (cur < end && (*cur == 'b' || *cur == 'B')))
        {
            result += syntaxColorSpan(SyntaxColor::Number);
            result += c;
            result += *cur++;
            while (cur < end && (*cur == '0' || *cur == '1' || *cur == '_'))
                result += *cur++;

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorSpan(SyntaxColor::Default);
            continue;
        }

        // Hexadecimal literal
        if (c == '0' && (cur < end && (*cur == 'x' || *cur == 'X')))
        {
            result += syntaxColorSpan(SyntaxColor::Number);
            result += c;
            result += *cur++;
            while (cur < end && (langSpec.isHexNumber(*cur) || *cur == '_'))
                result += *cur++;

            cur = Utf8Helper::decodeOneChar(cur, end, c, offset);
            result += syntaxColorSpan(SyntaxColor::Default);
            continue;
        }

        // Number
        if (langSpec.isDigit(c))
        {
            result += syntaxColorSpan(SyntaxColor::Number);
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
            result += syntaxColorSpan(SyntaxColor::Default);
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
                    result += syntaxColorSpan(tokColor);
                    result += identifier;
                    result += syntaxColorSpan(SyntaxColor::Default);
                }
                else
                {
                    result += identifier;
                }

                continue;
            }

            if (identifier[0] == '@' || identifier[0] == '#')
            {
                result += syntaxColorSpan(SyntaxColor::Invalid);
                result += identifier;
                result += syntaxColorSpan(SyntaxColor::Default);
                continue;
            }

            if (identifier == "Swag" && c == '.')
            {
                result += syntaxColorSpan(SyntaxColor::Namespace);
                result += identifier;
                result += syntaxColorSpan(SyntaxColor::Default);
                continue;
            }

            if (langSpec.isLetter(identifier[0]) && (c == '(' || c == '\''))
            {
                result += syntaxColorSpan(SyntaxColor::Function);
                result += identifier;
                result += syntaxColorSpan(SyntaxColor::Default);
                continue;
            }

            if (identifier[0] >= 'A' and identifier[0] <= 'Z')
            {
                result += syntaxColorSpan(SyntaxColor::Constant);
                result += identifier;
                result += syntaxColorSpan(SyntaxColor::Default);
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
        result.insert(0, syntaxColorSpan(SyntaxColor::Code));
        result += syntaxColorSpan(SyntaxColor::Default);
    }

    return result;
}

SWC_END_NAMESPACE();
