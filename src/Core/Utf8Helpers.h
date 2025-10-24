#pragma once

SWC_BEGIN_NAMESPACE()

namespace Utf8Helpers
{
    std::tuple<const uint8_t*, uint32_t, uint32_t> decodeOneChar(const uint8_t* p, const uint8_t* end);
    uint32_t                                       countChars(std::string_view str);
    Utf8                                           toNiceSize(size_t size);
    Utf8                                           toNiceBigNumber(std::size_t number);
    Utf8                                           toNiceTime(double seconds);
};

SWC_END_NAMESPACE()
