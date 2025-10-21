#pragma once

struct Color
{
    // ANSI color codes
    static constexpr std::string_view Reset = "\033[0m";
    static constexpr std::string_view Bold  = "\033[1m";
    static constexpr std::string_view Dim   = "\033[2m";

    // Foreground colors
    static constexpr std::string_view Red     = "\033[31m";
    static constexpr std::string_view Green   = "\033[32m";
    static constexpr std::string_view Yellow  = "\033[33m";
    static constexpr std::string_view Blue    = "\033[34m";
    static constexpr std::string_view Magenta = "\033[35m";
    static constexpr std::string_view Cyan    = "\033[36m";
    static constexpr std::string_view White   = "\033[37m";

    // Bright variants
    static constexpr std::string_view BrightRed     = "\033[91m";
    static constexpr std::string_view BrightGreen   = "\033[92m";
    static constexpr std::string_view BrightYellow  = "\033[93m";
    static constexpr std::string_view BrightBlue    = "\033[94m";
    static constexpr std::string_view BrightMagenta = "\033[95m";
    static constexpr std::string_view BrightCyan    = "\033[96m";
};
