// ReSharper disable CppNonExplicitConvertingConstructor
// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE()

class Utf8 : public std::string
{
public:
    // clang-format off
    Utf8() = default;
    Utf8(const char* from) : std::string(from){}
    Utf8(const char* from, size_t count) : std::string(from, count){}
    Utf8(uint32_t count, char c) : std::string(count, c) {}
    Utf8(const Utf8& other) : std::string(other) {}
    Utf8(Utf8&& other) noexcept : std::string(other) {}
    Utf8(std::string&& other) : std::string(std::move(other)) {}
    Utf8(const std::string_view& other) : std::string(other) {}
    Utf8(char32_t c) { push_back_uni(c); }
    // clang-format on

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

    Utf8& operator=(char32_t c) noexcept
    {
        push_back_uni(c);
        return *this;
    }

    void operator+=(const Utf8& txt) { this->append(txt); }
    void operator+=(const char* txt) { this->append(txt); }
    void operator+=(char32_t c) { push_back_uni(c); }
    void operator+=(char8_t c) { push_back_uni(c); }
    void operator+=(char c) { this->push_back(c); }
    void push_back_uni(char32_t cp);

    void trim_start();
    void trim_end();
    void trim();
    void clean();
    void make_lower();
    void make_upper();
    void replace_loop(std::string_view from, std::string_view to, bool loopReplace = false);
};

SWC_END_NAMESPACE()

template<>
struct std::formatter<swc::Utf8> : std::formatter<std::string>
{
};
