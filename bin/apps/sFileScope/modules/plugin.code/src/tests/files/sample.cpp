#include <cstdint>

// Generic C++ lexer verification fixture.
std::uint32_t answer(std::uint32_t value)
{
    const auto doubled = value * 2;
    return doubled > 40 ? doubled + 2 : 0;
}

