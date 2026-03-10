#include "pch.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeObjFileWriterCoff.h"

SWC_BEGIN_NAMESPACE();

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
