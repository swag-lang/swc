#pragma once

class Utf8
{
public:
    static std::tuple<const char*, uint32_t, unsigned> decode(const char* p, const char* end);
};
