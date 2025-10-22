#pragma once

struct Stats
{
    std::atomic<uint32_t> memMaxAllocated = 0;
};
