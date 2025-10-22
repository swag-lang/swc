// ReSharper disable CppNonExplicitConvertingConstructor
#pragma once

class Utf8 : public std::string
{
public:
    Utf8() = default;

    Utf8(const char* from) :
        std::string(from)
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

    void trimStart();
    void trimEnd();
    void trim();
};
