# Shared workspace launchers keep the Windows .bat names and argument order in Bash.
#
# This file is sourced by the WSL session; it does not replace Windows launchers.

swag_workspace_tool() {
    local tool=$1
    shift
    python3 "$SWAG_SOURCE/tools/tool.py" "$tool" "$@"
}

std.bat()       { swag_workspace_tool std "$@"; }
examples.bat()  { swag_workspace_tool examples "$@"; }
apps.bat()      { swag_workspace_tool apps "$@"; }
reference.bat() { swag_workspace_tool reference "$@"; }
tests.bat()     { swag_workspace_tool tests "$@"; }
unittests.bat() { swag_workspace_tool unittests "$@"; }
release.bat() {
    python3 "$SWAG_SOURCE/tools/linux-build.py" \
        --build-dir "$SWC_BUILD_DIR" \
        --configuration release \
        --cxx "${SWC_LINUX_CXX:-g++-14}" \
        --jobs 3 "$@" || return $?

    mkdir -p "$SWC_BUILD_DIR/release/runtime" &&
        cp -a "$SWAG_SOURCE/bin/runtime/." "$SWC_BUILD_DIR/release/runtime/"
}
export -f swag_workspace_tool std.bat examples.bat apps.bat reference.bat
export -f tests.bat unittests.bat
export -f release.bat
