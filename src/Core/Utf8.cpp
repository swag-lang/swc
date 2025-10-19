#include "pch.h"
#include "Utf8.h"

const char* Utf8::decode(const char* pz, uint32_t& wc, unsigned& offset)
{
    const uint8_t c = *pz++;

    if ((c & 0x80) == 0)
    {
        offset = 1;
        wc     = c;
        return pz;
    }

    if ((c & 0xE0) == 0xC0)
    {
        offset = 2;
        wc     = (c & 0x1F) << 6;
        wc |= *pz++ & 0x3F;
        return pz;
    }

    if ((c & 0xF0) == 0xE0)
    {
        offset = 3;
        wc     = (c & 0xF) << 12;
        wc |= (*pz++ & 0x3F) << 6;
        wc |= *pz++ & 0x3F;
        return pz;
    }

    if ((c & 0xF8) == 0xF0)
    {
        offset = 4;
        wc     = (c & 0x7) << 18;
        wc |= (*pz++ & 0x3F) << 12;
        wc |= (*pz++ & 0x3F) << 6;
        wc |= *pz++ & 0x3F;
        return pz;
    }

    offset = 1;
    wc     = c;
    return pz;
}
