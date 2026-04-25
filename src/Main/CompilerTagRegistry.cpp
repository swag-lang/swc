#include "pch.h"
#include "Main/CompilerTagRegistry.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/Command/CommandLine.h"
#include "Main/TaskContext.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/ApFloat.h"
#include "Support/Math/ApsInt.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ParsedIntegerLiteral
    {
        bool     negative  = false;
        uint64_t magnitude = 0;
    };

    struct CompilerTagError
    {
        DiagnosticId id = DiagnosticId::None;
        Utf8         type;
    };

    Result reportCompilerTagError(TaskContext& ctx, std::string_view rawTag, const CompilerTagError& error)
    {
        SWC_ASSERT(error.id != DiagnosticId::None);

        Diagnostic diag = Diagnostic::get(error.id);
        diag.addArgument(Diagnostic::ARG_ARG, rawTag);
        if (!error.type.empty())
            diag.addArgument(Diagnostic::ARG_TYPE, error.type);
        diag.report(ctx);
        return Result::Error;
    }

    bool tryParseIntegerLiteral(std::string_view rawValue, ParsedIntegerLiteral& outValue, CompilerTagError& outError)
    {
        outValue = {};
        outError = {};
        rawValue = Utf8Helper::trim(rawValue);
        if (rawValue.empty())
        {
            outError.id = DiagnosticId::cmdline_err_tag_int_missing_value;
            return false;
        }

        if (rawValue.front() == '+' || rawValue.front() == '-')
        {
            outValue.negative = rawValue.front() == '-';
            rawValue.remove_prefix(1);
        }

        if (rawValue.empty())
        {
            outError.id = DiagnosticId::cmdline_err_tag_int_missing_digits;
            return false;
        }

        uint32_t base = 10;
        if (rawValue.size() > 2 && rawValue[0] == '0' && (rawValue[1] == 'x' || rawValue[1] == 'X'))
        {
            base = 16;
            rawValue.remove_prefix(2);
        }
        else if (rawValue.size() > 2 && rawValue[0] == '0' && (rawValue[1] == 'b' || rawValue[1] == 'B'))
        {
            base = 2;
            rawValue.remove_prefix(2);
        }

        if (rawValue.empty())
        {
            outError.id = DiagnosticId::cmdline_err_tag_int_missing_digits;
            return false;
        }

        bool     hasDigit = false;
        uint64_t value    = 0;
        for (const char c : rawValue)
        {
            if (c == '_')
                continue;

            uint32_t digit = 0;
            if (c >= '0' && c <= '9')
                digit = static_cast<uint32_t>(c - '0');
            else if (c >= 'a' && c <= 'f')
                digit = 10u + static_cast<uint32_t>(c - 'a');
            else if (c >= 'A' && c <= 'F')
                digit = 10u + static_cast<uint32_t>(c - 'A');
            else
            {
                outError.id = DiagnosticId::cmdline_err_tag_int_invalid_literal;
                return false;
            }

            if (digit >= base)
            {
                outError.id = DiagnosticId::cmdline_err_tag_int_invalid_digit_base;
                return false;
            }

            hasDigit = true;
            if (value > (std::numeric_limits<uint64_t>::max() - digit) / base)
            {
                outError.id = DiagnosticId::cmdline_err_tag_int_too_large;
                return false;
            }

            value = value * base + digit;
        }

        if (!hasDigit)
        {
            outError.id = DiagnosticId::cmdline_err_tag_int_missing_digits;
            return false;
        }

        outValue.magnitude = value;
        return true;
    }

    Result makeCompilerTagInteger(TaskContext& ctx, TypeRef typeRef, std::string_view rawValue, ConstantRef& outCstRef, CompilerTagError& outError)
    {
        outCstRef = ConstantRef::invalid();
        outError  = {};

        ParsedIntegerLiteral literal;
        if (!tryParseIntegerLiteral(rawValue, literal, outError))
            return Result::Error;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        SWC_ASSERT(type.isInt());

        const uint32_t bits = type.payloadIntBits();
        if (type.isIntUnsigned())
        {
            if (literal.negative)
            {
                outError.id   = DiagnosticId::cmdline_err_tag_int_negative_unsigned;
                outError.type = type.toName(ctx);
                return Result::Error;
            }

            if (bits && bits < 64 && literal.magnitude > ((uint64_t{1} << bits) - 1))
            {
                outError.id   = DiagnosticId::cmdline_err_tag_int_out_of_range;
                outError.type = type.toName(ctx);
                return Result::Error;
            }

            const ApsInt value = bits ? ApsInt(literal.magnitude, bits) : ApsInt::makeUnsigned(literal.magnitude);
            outCstRef          = ctx.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, bits, TypeInfo::Sign::Unsigned));
            return Result::Continue;
        }

        int64_t signedValue = 0;
        if (literal.negative)
        {
            constexpr uint64_t minMagnitude = uint64_t{1} << 63;
            if (literal.magnitude > minMagnitude)
            {
                outError.id = DiagnosticId::cmdline_err_tag_int_too_large;
                return Result::Error;
            }

            signedValue = literal.magnitude == minMagnitude ? std::numeric_limits<int64_t>::min() : -static_cast<int64_t>(literal.magnitude);
        }
        else
        {
            if (literal.magnitude > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()))
            {
                outError.id = DiagnosticId::cmdline_err_tag_int_too_large;
                return Result::Error;
            }

            signedValue = static_cast<int64_t>(literal.magnitude);
        }

        if (bits && bits < 64)
        {
            const int64_t minValue = -(int64_t{1} << (bits - 1));
            const int64_t maxValue = (int64_t{1} << (bits - 1)) - 1;
            if (signedValue < minValue || signedValue > maxValue)
            {
                outError.id   = DiagnosticId::cmdline_err_tag_int_out_of_range;
                outError.type = type.toName(ctx);
                return Result::Error;
            }
        }

        const ApsInt value = bits ? ApsInt(signedValue, bits, false) : ApsInt::makeSigned(signedValue);
        outCstRef          = ctx.cstMgr().addConstant(ctx, ConstantValue::makeInt(ctx, value, bits, TypeInfo::Sign::Signed));
        return Result::Continue;
    }

    Result makeCompilerTagFloat(TaskContext& ctx, TypeRef typeRef, std::string_view rawValue, ConstantRef& outCstRef, CompilerTagError& outError)
    {
        outCstRef = ConstantRef::invalid();
        outError  = {};

        rawValue = Utf8Helper::trim(rawValue);
        if (rawValue.empty())
        {
            outError.id = DiagnosticId::cmdline_err_tag_float_missing_value;
            return Result::Error;
        }

        std::string normalized;
        normalized.reserve(rawValue.size());
        for (const char c : rawValue)
        {
            if (c != '_')
                normalized.push_back(c);
        }

        if (normalized.empty())
        {
            outError.id = DiagnosticId::cmdline_err_tag_float_missing_value;
            return Result::Error;
        }

        char* endPtr = nullptr;
        errno        = 0;
        if (typeRef == ctx.typeMgr().typeF32())
        {
            const float value = std::strtof(normalized.c_str(), &endPtr);
            if (endPtr != normalized.data() + normalized.size() || errno == ERANGE)
            {
                outError.id = DiagnosticId::cmdline_err_tag_float_invalid_literal;
                return Result::Error;
            }

            if (!std::isfinite(value))
            {
                outError.id = DiagnosticId::cmdline_err_tag_float_non_finite;
                return Result::Error;
            }

            outCstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, ApFloat(value), 32));
            return Result::Continue;
        }

        const double value = std::strtod(normalized.c_str(), &endPtr);
        if (endPtr != normalized.data() + normalized.size() || errno == ERANGE)
        {
            outError.id = DiagnosticId::cmdline_err_tag_float_invalid_literal;
            return Result::Error;
        }

        if (!std::isfinite(value))
        {
            outError.id = DiagnosticId::cmdline_err_tag_float_non_finite;
            return Result::Error;
        }

        outCstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeFloat(ctx, ApFloat(value), 64));
        return Result::Continue;
    }

    Result makeCompilerTagValue(TaskContext& ctx, TypeRef typeRef, std::string_view rawValue, ConstantRef& outCstRef, CompilerTagError& outError)
    {
        outCstRef = ConstantRef::invalid();
        outError  = {};

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isBool())
        {
            rawValue = Utf8Helper::trim(rawValue);
            if (rawValue == "true")
            {
                outCstRef = ctx.cstMgr().cstTrue();
                return Result::Continue;
            }

            if (rawValue == "false")
            {
                outCstRef = ctx.cstMgr().cstFalse();
                return Result::Continue;
            }

            outError.id = DiagnosticId::cmdline_err_tag_bool_invalid;
            return Result::Error;
        }

        if (type.isString())
        {
            outCstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, Utf8Helper::trim(rawValue)));
            return Result::Continue;
        }

        if (type.isInt())
            return makeCompilerTagInteger(ctx, typeRef, rawValue, outCstRef, outError);
        if (type.isFloat())
            return makeCompilerTagFloat(ctx, typeRef, rawValue, outCstRef, outError);

        outError.id   = DiagnosticId::cmdline_err_tag_type_unsupported;
        outError.type = type.toName(ctx);
        return Result::Error;
    }

    Result parseOneCompilerTag(TaskContext& ctx, std::string_view rawTag, CompilerTag& outTag)
    {
        rawTag = Utf8Helper::trim(rawTag);
        if (rawTag.empty())
        {
            CompilerTagError error;
            error.id = DiagnosticId::cmdline_err_tag_missing_name;
            return reportCompilerTagError(ctx, rawTag, error);
        }

        outTag        = {};
        outTag.source = rawTag;

        const size_t equalPos = rawTag.find('=');
        if (equalPos == std::string_view::npos)
        {
            const std::string_view name = Utf8Helper::trim(rawTag);
            if (name.empty())
            {
                CompilerTagError error;
                error.id = DiagnosticId::cmdline_err_tag_missing_name;
                return reportCompilerTagError(ctx, rawTag, error);
            }

            outTag.name   = name;
            outTag.cstRef = ctx.cstMgr().cstTrue();
            return Result::Continue;
        }

        const std::string_view leftPart  = Utf8Helper::trim(rawTag.substr(0, equalPos));
        const std::string_view rightPart = Utf8Helper::trim(rawTag.substr(equalPos + 1));
        if (leftPart.empty())
        {
            CompilerTagError error;
            error.id = DiagnosticId::cmdline_err_tag_missing_name;
            return reportCompilerTagError(ctx, rawTag, error);
        }

        if (rightPart.empty())
        {
            CompilerTagError error;
            error.id = DiagnosticId::cmdline_err_tag_missing_value;
            return reportCompilerTagError(ctx, rawTag, error);
        }

        std::string_view namePart = leftPart;
        std::string_view typePart;
        const size_t colonPos = leftPart.find(':');
        if (colonPos != std::string_view::npos)
        {
            namePart = Utf8Helper::trim(leftPart.substr(0, colonPos));
            typePart = Utf8Helper::trim(leftPart.substr(colonPos + 1));
        }

        if (namePart.empty())
        {
            CompilerTagError error;
            error.id = DiagnosticId::cmdline_err_tag_missing_name;
            return reportCompilerTagError(ctx, rawTag, error);
        }

        outTag.name = namePart;

        if (typePart.empty())
        {
            if (rightPart == "true")
            {
                outTag.cstRef = ctx.cstMgr().cstTrue();
                return Result::Continue;
            }

            if (rightPart == "false")
            {
                outTag.cstRef = ctx.cstMgr().cstFalse();
                return Result::Continue;
            }

            CompilerTagError error;
            ConstantRef      cstRef = ConstantRef::invalid();
            if (makeCompilerTagInteger(ctx, ctx.typeMgr().typeS32(), rightPart, cstRef, error) != Result::Continue)
            {
                if (error.id == DiagnosticId::cmdline_err_tag_int_missing_value ||
                    error.id == DiagnosticId::cmdline_err_tag_int_missing_digits ||
                    error.id == DiagnosticId::cmdline_err_tag_int_invalid_literal ||
                    error.id == DiagnosticId::cmdline_err_tag_int_invalid_digit_base)
                {
                    error.id = DiagnosticId::cmdline_err_tag_untyped_value_invalid;
                }
                return reportCompilerTagError(ctx, rawTag, error);
            }

            outTag.cstRef = cstRef;
            return Result::Continue;
        }

        TypeRef typeRef = TypeRef::invalid();
        if (typePart == "bool")
            typeRef = ctx.typeMgr().typeBool();
        else if (typePart == "string")
            typeRef = ctx.typeMgr().typeString();
        else if (typePart == "int")
            typeRef = ctx.typeMgr().typeIntSigned();
        else if (typePart == "uint")
            typeRef = ctx.typeMgr().typeIntUnsigned();
        else if (typePart == "s8")
            typeRef = ctx.typeMgr().typeS8();
        else if (typePart == "u8")
            typeRef = ctx.typeMgr().typeU8();
        else if (typePart == "s16")
            typeRef = ctx.typeMgr().typeS16();
        else if (typePart == "u16")
            typeRef = ctx.typeMgr().typeU16();
        else if (typePart == "s32")
            typeRef = ctx.typeMgr().typeS32();
        else if (typePart == "u32")
            typeRef = ctx.typeMgr().typeU32();
        else if (typePart == "s64")
            typeRef = ctx.typeMgr().typeS64();
        else if (typePart == "u64")
            typeRef = ctx.typeMgr().typeU64();
        else if (typePart == "f32")
            typeRef = ctx.typeMgr().typeF32();
        else if (typePart == "f64")
            typeRef = ctx.typeMgr().typeF64();

        if (typeRef.isInvalid())
        {
            CompilerTagError error;
            error.id   = DiagnosticId::cmdline_err_tag_type_unsupported;
            error.type = typePart;
            return reportCompilerTagError(ctx, rawTag, error);
        }

        CompilerTagError error;
        ConstantRef      cstRef = ConstantRef::invalid();
        if (makeCompilerTagValue(ctx, typeRef, rightPart, cstRef, error) != Result::Continue)
            return reportCompilerTagError(ctx, rawTag, error);

        outTag.cstRef = cstRef;
        return Result::Continue;
    }

    void addInternalCompilerTags(TaskContext& ctx, std::vector<CompilerTag>& outTags)
    {
        CompilerTag tag;
        tag.name   = "Swag.Endian";
        tag.source = "<internal>";

        switch (ctx.cmdLine().targetArch)
        {
            case Runtime::TargetArch::X86_64:
                tag.cstRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, "little"));
                outTags.push_back(std::move(tag));
                return;
        }

        SWC_UNREACHABLE();
    }
}

Result CompilerTagRegistry::setup(TaskContext& ctx)
{
    tags_.clear();
    tags_.reserve(1 + ctx.cmdLine().tags.size());
    addInternalCompilerTags(ctx, tags_);

    for (const Utf8& rawTag : ctx.cmdLine().tags)
    {
        CompilerTag tag;
        SWC_RESULT(parseOneCompilerTag(ctx, rawTag.view(), tag));
        tags_.push_back(std::move(tag));
    }

    return Result::Continue;
}

const CompilerTag* CompilerTagRegistry::find(const std::string_view name) const
{
    for (const CompilerTag& tag : tags_)
    {
        if (std::string_view{tag.name} == name)
            return &tag;
    }

    return nullptr;
}

SWC_END_NAMESPACE();
