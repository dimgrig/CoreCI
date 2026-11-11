platform_path = unknown-platform
compiler_path = unknown-compiler
processor_path = unknown-processor
build_path = unknown-build
PLATFORM_WIN {
    platform_path = windows
}
PLATFORM_OSX {
    platform_path = osx
}
PLATFORM_LINUX {
    platform_path = linux
}
COMPILER_GCC {
    compiler_path = gcc
}
COMPILER_MSVC2017 {
    compiler_path = msvc2017
}
COMPILER_CLANG {
    compiler_path = clang
}
PROCESSOR_x64 {
    processor_path = x64
}
PROCESSOR_x86 {
    processor_path = x86
}
PROCESSOR_ARM64 {
    processor_path = arm64
}
PROCESSOR_ARM {
    processor_path = arm
}
BUILD_DEBUG {
    build_path = debug
} else {
    build_path = release
}
wasm {
    CONFIG += PLATFORM_WASM
    platform_path = wasm
    message(PLATFORM_WASM)
}
wasm {
    CONFIG += COMPILER_EMSCRIPTEN
    compiler_path = emscripten
}
contains(QT_ARCH, wasm)|contains(QT_ARCH, wasm32) {
    CONFIG += PROCESSOR_WASM
    processor_path = wasm32
}

DESTINATION_PATH = $$platform_path/$$compiler_path/$$processor_path/$$build_path
message(Dest path: $${DESTINATION_PATH})
