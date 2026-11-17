#pragma once
#include "Support/Core/Utf8.h"

#include "Main/Version.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Logger.h"

SWC_BEGIN_NAMESPACE();

namespace CommandPrint
{
    inline void printCompilerHeader(const TaskContext& ctx)
    {
        Logger::print(ctx, std::format("Swag compiler {}.{}.{}\n", SWC_VERSION, SWC_REVISION, SWC_BUILD_NUM));
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, Utf8 value, const uint32_t indentLevel = 0)
    {
        if (value.empty())
            value = "<empty>";

        entries.push_back({.label = Utf8(label), .value = std::move(value), .indentLevel = indentLevel});
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const char* value, const uint32_t indentLevel = 0)
    {
        addInfoEntry(entries, label, Utf8(value), indentLevel);
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const std::string& value, const uint32_t indentLevel = 0)
    {
        addInfoEntry(entries, label, Utf8(value), indentLevel);
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const std::string_view value, const uint32_t indentLevel = 0)
    {
        addInfoEntry(entries, label, Utf8(value), indentLevel);
    }

    inline void addInfoEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const fs::path& value, const uint32_t indentLevel = 0)
    {
        addInfoEntry(entries, label, Utf8(value), indentLevel);
    }

    inline void addLinuxNativeToolchainEntries(std::vector<Logger::FieldEntry>& entries)
    {
        addInfoEntry(entries, "Object format", "ELF64 (x86-64)");
        addInfoEntry(entries, "Compiler driver", "cc (from PATH at link time)");
        addInfoEntry(entries, "Archive writer", "ar (from PATH at link time)");
    }

    inline void addNativeToolchainEntries(std::vector<Logger::FieldEntry>& entries, const Os::WindowsToolchainDiscoveryResult toolchainResult, const Os::WindowsToolchainPaths& toolchain)
    {
        switch (toolchainResult)
        {
            case Os::WindowsToolchainDiscoveryResult::Ok:
                addInfoEntry(entries, "Status", "ready");
                addInfoEntry(entries, "Linker", "integrated (swc)");
                addInfoEntry(entries, "MSVC library path", toolchain.vcLibPath);
                addInfoEntry(entries, "Windows SDK UM libs", toolchain.sdkUmLibPath);
                addInfoEntry(entries, "Windows SDK UCRT libs", toolchain.sdkUcrtLibPath);
                break;

            case Os::WindowsToolchainDiscoveryResult::MissingMsvcToolchain:
                addInfoEntry(entries, "Status", "missing MSVC toolchain");
                break;

            case Os::WindowsToolchainDiscoveryResult::MissingWindowsSdk:
                addInfoEntry(entries, "Status", "missing Windows SDK");
                break;
        }
    }

    inline void addBoolEntry(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const bool enabled)
    {
        addInfoEntry(entries, label, enabled ? "on" : "off");
    }

    template<typename T>
    inline void addSetEntries(std::vector<Logger::FieldEntry>& entries, const std::string_view label, const std::set<T>& values)
    {
        if (values.empty())
        {
            addInfoEntry(entries, label, "<empty>");
            return;
        }

        addInfoEntry(entries, label, Utf8Helper::countWithLabel(values.size(), "entry"));
        uint32_t index = 0;
        for (const T& value : values)
            addInfoEntry(entries, std::format("[{}]", index++), value, 1);
    }

}

SWC_END_NAMESPACE();
