win32 {
    CONFIG += PLATFORM_WIN
    message(PLATFORM_WIN)
    win32-g++ {
        CONFIG += COMPILER_GCC
        message(COMPILER_GCC)
        contains(QT_ARCH, x86_64) {
            QMAKE_TARGET.arch = x86_64
            message("Target arch: x86_64")
        } else {
            QMAKE_TARGET.arch = x86
            message("Target arch: x86")
        }
    }
    win32-msvc2017 {
        CONFIG += COMPILER_MSVC2017
        message(COMPILER_MSVC2017)
        win32-msvc2017:QMAKE_TARGET.arch = x86_64
    }
}
linux {
    CONFIG += PLATFORM_LINUX
    message(PLATFORM_LINUX)
    linux-g++{
        CONFIG += COMPILER_GCC
        message(COMPILER_GCC)
    }

    # Определяем архитектуру
    contains(QT_ARCH, x86_64) {
        QMAKE_TARGET.arch = x86_64
    } else:contains(QT_ARCH, arm64) {
        QMAKE_TARGET.arch = arm64
        CONFIG += PROCESSOR_ARM64
        message(PROCESSOR_ARM64)
    } else:contains(QT_ARCH, arm) {
        QMAKE_TARGET.arch = arm
        CONFIG += PROCESSOR_ARM
        message(PROCESSOR_ARM)
    } else {
        QMAKE_TARGET.arch = x86   # fallback
    }
}

macx {
   CONFIG += PLATFORM_OSX
   message(PLATFORM_OSX)
   macx-clang {
       CONFIG += COMPILER_CLANG
       message(COMPILER_CLANG)
       QMAKE_TARGET.arch = x86_64
   }
   macx-clang-32{
       CONFIG += COMPILER_CLANG
       message(COMPILER_CLANG)
       QMAKE_TARGET.arch = x86
   }
}

# Устанавливаем PROCESSOR_* на основе QT_ARCH
contains(QT_ARCH, x86_64) {
   CONFIG += PROCESSOR_x64
   message(PROCESSOR_x64)
} else:contains(QT_ARCH, arm64) {
   CONFIG += PROCESSOR_ARM64
   message(PROCESSOR_ARM64)
} else:contains(QT_ARCH, arm) {
   CONFIG += PROCESSOR_ARM
   message(PROCESSOR_ARM)
} else {
   CONFIG += PROCESSOR_x86
   message(PROCESSOR_x86)
}

CONFIG(debug, release|debug) {
   CONFIG += BUILD_DEBUG
   message(BUILD_DEBUG)
} else {
   CONFIG += BUILD_RELEASE
   message(BUILD_RELEASE)
}

message("Qt version: $$QT_VERSION")
message("Qt major: $$section(QT_VERSION, ., 0, 0)")
