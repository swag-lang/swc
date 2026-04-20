#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();
namespace
{
    Result checkLiteralRewrite(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FormatLiteral_PreserveLeavesNumericLiteralsUntouched)
{
    static constexpr std::string_view SOURCE =
        "#assert(0xAbCd == 0xAbCd)\n"
        "#assert(0x8000_0000 == 0x8000_0000)\n"
        "#assert(1_000_000 == 1_000_000)\n"
        "#assert(3.14e10 == 3.14e10)\n"
        "#assert(42'U32 == 42'U32)\n";

    const FormatOptions options;
    return checkLiteralRewrite(ctx, SOURCE, SOURCE, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatLiteral_HexDigitCaseUpperAndLower)
{
    static constexpr std::string_view SOURCE =
        "#assert(0xAbCd == 0xAbCd)\n"
        "#assert(0xdead_beef == 0xdead_beef)\n";

    {
        FormatOptions options;
        options.hexLiteralCase = FormatLiteralCase::Upper;
        static constexpr std::string_view EXPECTED =
            "#assert(0xABCD == 0xABCD)\n"
            "#assert(0xDEAD_BEEF == 0xDEAD_BEEF)\n";
        SWC_RESULT(checkLiteralRewrite(ctx, SOURCE, EXPECTED, options));
    }

    {
        FormatOptions options;
        options.hexLiteralCase = FormatLiteralCase::Lower;
        static constexpr std::string_view EXPECTED =
            "#assert(0xabcd == 0xabcd)\n"
            "#assert(0xdead_beef == 0xdead_beef)\n";
        SWC_RESULT(checkLiteralRewrite(ctx, SOURCE, EXPECTED, options));
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatLiteral_HexPrefixCaseUpperAndLower)
{
    static constexpr std::string_view SOURCE = "#assert(0xFF == 0XFF)\n";

    {
        FormatOptions options;
        options.hexLiteralPrefixCase               = FormatLiteralCase::Upper;
        static constexpr std::string_view EXPECTED = "#assert(0XFF == 0XFF)\n";
        SWC_RESULT(checkLiteralRewrite(ctx, SOURCE, EXPECTED, options));
    }

    {
        FormatOptions options;
        options.hexLiteralPrefixCase               = FormatLiteralCase::Lower;
        static constexpr std::string_view EXPECTED = "#assert(0xFF == 0xFF)\n";
        SWC_RESULT(checkLiteralRewrite(ctx, SOURCE, EXPECTED, options));
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatLiteral_FloatExponentCaseUpperAndLower)
{
    static constexpr std::string_view SOURCE = "#assert(1.5e10 == 1.5E-3)\n";

    {
        FormatOptions options;
        options.floatExponentCase                  = FormatLiteralCase::Upper;
        static constexpr std::string_view EXPECTED = "#assert(1.5E10 == 1.5E-3)\n";
        SWC_RESULT(checkLiteralRewrite(ctx, SOURCE, EXPECTED, options));
    }

    {
        FormatOptions options;
        options.floatExponentCase                  = FormatLiteralCase::Lower;
        static constexpr std::string_view EXPECTED = "#assert(1.5e10 == 1.5e-3)\n";
        SWC_RESULT(checkLiteralRewrite(ctx, SOURCE, EXPECTED, options));
    }
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatLiteral_NormalizeHexDigitSeparators)
{
    static constexpr std::string_view SOURCE = "#assert(0xDEADBEEFCAFE == 0x1_2345678)\n";

    FormatOptions options;
    options.normalizeDigitSeparators   = true;
    options.hexDigitSeparatorGroupSize = 4;

    static constexpr std::string_view EXPECTED = "#assert(0xDEAD_BEEF_CAFE == 0x1234_5678)\n";
    return checkLiteralRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatLiteral_NormalizeBinaryDigitSeparators)
{
    static constexpr std::string_view SOURCE = "#assert(0b1010101010 == 0b11110000_11110000)\n";

    FormatOptions options;
    options.normalizeDigitSeparators   = true;
    options.hexDigitSeparatorGroupSize = 4;

    static constexpr std::string_view EXPECTED = "#assert(0b10_1010_1010 == 0b1111_0000_1111_0000)\n";
    return checkLiteralRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatLiteral_NormalizeDecimalDigitSeparators)
{
    static constexpr std::string_view SOURCE = "#assert(1234567 == 12345)\n";

    FormatOptions options;
    options.normalizeDigitSeparators       = true;
    options.decimalDigitSeparatorGroupSize = 3;

    static constexpr std::string_view EXPECTED = "#assert(1_234_567 == 12_345)\n";
    return checkLiteralRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatLiteral_NormalizeFloatDigitSeparators)
{
    static constexpr std::string_view SOURCE = "#assert(12345.67890e12345 == 1.0)\n";

    FormatOptions options;
    options.normalizeDigitSeparators       = true;
    options.decimalDigitSeparatorGroupSize = 3;

    static constexpr std::string_view EXPECTED = "#assert(12_345.678_90e12_345 == 1.0)\n";
    return checkLiteralRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_TEST_BEGIN(FormatLiteral_CombinedHexCaseAndNormalization)
{
    static constexpr std::string_view SOURCE = "#assert(0XdeadBEEFcafe == 0Xff)\n";

    FormatOptions options;
    options.hexLiteralCase             = FormatLiteralCase::Upper;
    options.hexLiteralPrefixCase       = FormatLiteralCase::Lower;
    options.normalizeDigitSeparators   = true;
    options.hexDigitSeparatorGroupSize = 4;

    static constexpr std::string_view EXPECTED = "#assert(0xDEAD_BEEF_CAFE == 0xFF)\n";
    return checkLiteralRewrite(ctx, SOURCE, EXPECTED, options);
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
