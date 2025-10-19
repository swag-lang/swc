#pragma once

class Utf8
{
public:
    static const char* decode(const char* pz, uint32_t& wc, unsigned& offset);
};
