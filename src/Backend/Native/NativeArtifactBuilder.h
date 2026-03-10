#pragma once

#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

struct NativeArtifactPaths
{
    Utf8                  name;
    Utf8                  artifactExtension;
    fs::path              workDir;
    fs::path              buildDir;
    fs::path              outDir;
    fs::path              artifactPath;
    fs::path              pdbPath;
    std::vector<fs::path> objectPaths;
};

class NativeArtifactBuilder
{
public:
    explicit NativeArtifactBuilder(NativeBackendBuilder& builder);

    Result build() const;
    void   queryPaths(NativeArtifactPaths& outPaths, std::optional<uint32_t> workDirIndex = std::nullopt, uint32_t numObjects = 0) const;

private:
    Result          validateNativeData() const;
    bool            isNativeStaticType(TypeRef typeRef) const;
    Result          validateRelocations(const SymbolFunction& owner, const MachineCode& code) const;
    bool            validateConstantRelocation(const MicroRelocation& relocation) const;
    bool            validateNativeStaticPayload(TypeRef typeRef, uint32_t shardIndex, Ref baseOffset, ByteSpan bytes) const;
    bool            findDataSegmentRelocation(uint32_t shardIndex, uint32_t offset, uint32_t& outTargetOffset) const;
    Result          prepareDataSections() const;
    Result          buildStartup() const;
    Result          partitionObjects() const;
    Utf8            configuredName() const;
    Utf8            artifactName() const;
    Utf8            artifactExtension() const;
    fs::path        configuredOutDir(const fs::path& defaultOutDir) const;
    Result          createOutDir(const fs::path& outDir) const;
    fs::path        configuredWorkDir() const;
    Utf8            automaticWorkDirName(const Utf8& name) const;
    static fs::path buildDirectory(const fs::path& workDir, uint32_t buildIndex);
    Result          createBuildDirectory(const fs::path& buildDir) const;

    NativeBackendBuilder& builder_;
};

SWC_END_NAMESPACE();
