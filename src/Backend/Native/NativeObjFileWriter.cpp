#include "pch.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeObjFileWriterCoff.h"
#include "Backend/Native/NativeObjFileWriter.elf.h"
#include "Main/FileSystem.h"
#include "Backend/Native/NativeObjectFormat.h"
#include "Backend/Runtime.h"
#include "Main/Command/CommandLine.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

std::optional<NativeObjectFormat> getNativeObjFormat(const Runtime::TargetOs targetOs)
{
    switch (targetOs)
    {
        case Runtime::TargetOs::Linux:
            return NativeObjectFormat::LinuxElf;
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
        case NativeObjectFormat::LinuxElf:
            return std::make_unique<NativeObjFileWriterElf>(builder);
        case NativeObjectFormat::WindowsCoff:
            return std::make_unique<NativeObjFileWriterCoff>(builder);
    }

    SWC_UNREACHABLE();
}

Result NativeObjFileWriter::writeObjectFile(const NativeObjDescription& description)
{
    ByteArray fileData;
    SWC_RESULT(buildObjectFile(fileData, description));

    FileSystem::IoErrorInfo ioError;
    if (FileSystem::writeBinaryFile(description.objPath, fileData.data(), fileData.size(), ioError) == Result::Continue)
        return Result::Continue;

    if (ioError.problem == FileSystem::IoProblem::OpenWrite)
        return builder_->reportError(DiagnosticId::cmd_err_native_obj_open_failed, Diagnostic::ARG_PATH, Utf8(description.objPath));

    return builder_->reportError(DiagnosticId::cmd_err_native_obj_write_failed, Diagnostic::ARG_PATH, Utf8(description.objPath));
}

SWC_END_NAMESPACE();
