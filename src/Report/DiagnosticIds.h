#pragma once

enum class DiagnosticId
{
    CannotOpenFile,
    CannotReadFile,
    FileNotUtf8,
    UnclosedComment,
    EolInStringLiteral,
    UnclosedStringLiteral,
};
