#pragma once

enum class Result : bool
{
    Error   = false,
    Success = true,
};

#define SWAG_CHECK(__result)           \
    if ((__result) != Result::Success) \
    {                                  \
        do                             \
        {                              \
            return Result::Error;      \
        } while (0);                   \
    }
