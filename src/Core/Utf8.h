#pragma once

class Utf8
{
    static const char* decode(const char* pz, uint32_t& wc, unsigned& offset);
};
