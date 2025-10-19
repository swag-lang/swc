#include "pch.h"

#include "Report/DiagReporter.h"

#define SWAG_DIAG(__n, __msg)                         \
    do                                                \
    {                                                 \
        diagMsgs_[(int) (DiagnosticId::__n)] = __msg; \
    } while (0)

void DiagReporter::initErrors()
{
    SWAG_DIAG(CannotOpenFile, "failed to open file %0");
    SWAG_DIAG(CannotReadFile, "failed to read file %0");
    SWAG_DIAG(FileNotUtf8, "source file %0 is not utf8");
    SWAG_DIAG(UnclosedComment, "unclose multi-line comment");
}
