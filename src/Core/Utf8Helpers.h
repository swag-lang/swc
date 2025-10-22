#pragma once

namespace Utf8Helpers
{
    std::tuple<const uint8_t*, uint32_t, uint32_t> decodeOneChar(const uint8_t* p, const uint8_t* end);
    uint32_t                                       countChars(std::string_view str);
};
