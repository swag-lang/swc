#pragma once

class SourceFile;

struct SourceCodeLocation
{
    const SourceFile* file   = nullptr;
    uint32_t          line   = 0;
    uint32_t          column = 0;
    uint32_t          offset = 0;
    uint32_t          len    = 0;

    void fromOffset(const SourceFile* file, uint32_t offset, uint32_t len = 1);
};
