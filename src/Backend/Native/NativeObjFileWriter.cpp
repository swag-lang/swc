#include "pch.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeObjFileWriterCoff.h"
#include "Backend/Native/NativeObjectFormat.h"
#include "Backend/Runtime.h"
#include "Main/Command/CommandLine.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

std::optional<NativeObjectFormat> getNativeObjFormat(const Runtime::TargetOs targetOs)
{
    switch (targetOs)
    {
        case Runtime::TargetOs::Windows:
            return NativeObjectFormat::WindowsCoff;
        default:
            return std::nullopt;
    }
}

std::unique_ptr<NativeObjFileWriter> NativeObjFileWriter::create(NativeBackendBuilder& builder)
{
    const auto format = getNativeObjFormat(builder.ctx().cmdLine().targetOs);
    SWC_ASSERT(format.has_value());

    switch (*format)
    {
        case NativeObjectFormat::WindowsCoff:
            return std::make_unique<NativeObjFileWriterCoff>(builder);
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
