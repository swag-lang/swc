// ReSharper disable CppNonExplicitConvertingConstructor
#pragma once

SWC_BEGIN_NAMESPACE()

class Utf8 : public std::string
{
public:
    Utf8() = default;

    Utf8(const char* from) :
        std::string(from)
    {
    }

    Utf8(uint32_t count, char c) :
        std::string(count, c)
    {
    }

    Utf8(const Utf8& other) :
        std::string(other)
    {
    }

    Utf8(Utf8&& other) noexcept :
        std::string(other)
    {
    }

    Utf8(std::string&& other) :
        std::string(std::move(other))
    {
    }

    Utf8(const std::string_view& other) :
        std::string(other)
    {
    }

    Utf8& operator=(const Utf8& other)
    {
        if (this == &other)
            return *this;
        std::string::operator=(other);
        return *this;
    }

    Utf8& operator=(Utf8&& other) noexcept
    {
        if (this == &other)
            return *this;
        std::string::operator=(other);
        return *this;
    }

    Utf8& operator=(char c) noexcept
    {
        std::string::operator=(c);
        return *this;
    }

    // ReSharper disable once CppNonExplicitConversionOperator
    operator std::string_view() const
    {
        return {data(), size()};
    }

    void trimStart();
    void trimEnd();
    void trim();
    void clean();
    void makeLower();
    void makeUpper();
    void replaceOutsideQuotes(std::string_view from, std::string_view to, bool loopReplace = false);
};

SWC_END_NAMESPACE()
