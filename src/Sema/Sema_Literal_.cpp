#include "pch.h"

#include "Lexer/LangSpec.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Sema/ConstantManager.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBoolLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok = job.token(srcViewRef(), tokRef());
    if (tok.is(TokenId::KwdTrue))
        setConstant(job.constMgr().boolTrue());
    else if (tok.is(TokenId::KwdFalse))
        setConstant(job.constMgr().boolFalse());
    else
        SWC_UNREACHABLE();

    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstStringLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok     = job.token(srcViewRef(), tokRef());
    const auto& srcView = job.compiler().srcView(srcViewRef());
    const auto  str     = tok.string(srcView);

    if (!tok.hasFlag(TokenFlagsE::Escaped))
    {
        const auto val = ConstantValue::makeString(job.ctx(), str);
        setConstant(job.constMgr().addConstant(val));
        return AstVisitStepResult::SkipChildren;
    }

    Utf8 result;
    result.reserve(str.size());

    auto parseHexEscape = [&](size_t& index, size_t maxDigits, uint32_t& valueOut) {
        uint32_t    value    = 0;
        size_t      digits   = 0;
        const auto& langSpec = job.compiler().global().langSpec();
        do
        {
            SWC_ASSERT(index + 1 < str.size());
            const char h = str[++index];
            SWC_ASSERT(langSpec.isHexNumber(h));

            value <<= 4;

            if (langSpec.isDigit(h))
                value += static_cast<uint32_t>(h - '0');
            else if (h >= 'a' && h <= 'f')
                value += 10u + static_cast<uint32_t>(h - 'a');
            else if (h >= 'A' && h <= 'F')
                value += 10u + static_cast<uint32_t>(h - 'A');

            ++digits;
        } while (digits < maxDigits && index + 1 < str.size() && langSpec.isHexNumber(str[index + 1]));
        valueOut = value;
    };

    // decode escape sequences
    for (size_t i = 0; i < str.size(); ++i)
    {
        const char ch = str[i];

        if (ch != '\\')
        {
            result += ch;
            continue;
        }

        SWC_ASSERT(i + 1 < str.size());

        const char esc = str[++i];
        switch (esc)
        {
            case '0':
                result += '\0';
                break;
            case 'a':
                result += '\a';
                break;
            case 'b':
                result += '\b';
                break;
            case '\\':
                result += '\\';
                break;
            case 't':
                result += '\t';
                break;
            case 'n':
                result += '\n';
                break;
            case 'f':
                result += '\f';
                break;
            case 'r':
                result += '\r';
                break;
            case 'v':
                result += '\v';
                break;
            case '\'':
                result += '\'';
                break;
            case '\"':
                result += '\"';
                break;

            case 'x':
            {
                uint32_t cp = 0;
                parseHexEscape(i, 2, cp);
                result += cp;
                break;
            }

            case 'u':
            {
                uint32_t cp = 0;
                parseHexEscape(i, 4, cp);
                result += cp;
                break;
            }

            case 'U':
            {
                uint32_t cp = 0;
                parseHexEscape(i, 8, cp);
                result += cp;
                break;
            }

            default:
                SWC_UNREACHABLE();
        }
    }

    const auto val = ConstantValue::makeString(job.ctx(), result);
    setConstant(job.constMgr().addConstant(val));
    return AstVisitStepResult::SkipChildren;
}

SWC_END_NAMESPACE()
