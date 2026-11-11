# cmake/FetchCoreSDK.cmake
#
# Скачивает и распаковывает Core SDK из публичных GitHub-релизов
# https://github.com/dimgrig/Core/releases
#
# Кэширует: повторный cmake -B build ничего не качает, если файлы на месте.
# Проверяет SHA256 через SHA256SUMS.
#
# Публикует в Cache:
#   CORE_SDK_ROOT

if(NOT CORE_SDK_REPO)
    set(CORE_SDK_REPO "dimgrig/Core" CACHE STRING
        "GitHub repo (owner/name) publishing Core releases")
endif()
if(NOT CORE_SDK_VERSION)
    message(FATAL_ERROR "CORE_SDK_VERSION must be set (e.g. -DCORE_SDK_VERSION=1.1.0)")
endif()

# ── Платформа / расширение ──────────────────────────────────────
if(CORE_SDK_PLATFORM)
    set(_plat "${CORE_SDK_PLATFORM}")
elseif(WIN32)
    set(_plat "win32")
elseif(UNIX AND NOT APPLE)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64|arm")
        message(FATAL_ERROR
            "Core SDK is not published for ${CMAKE_SYSTEM_PROCESSOR}. "
            "Only linux-amd64 and win32 are available.")
    endif()
    set(_plat "linux-amd64")
else()
    message(FATAL_ERROR "Unsupported host platform: ${CMAKE_SYSTEM_NAME}")
endif()

if(CORE_SDK_EXT)
    set(_ext "${CORE_SDK_EXT}")
elseif(_plat STREQUAL "win32")
    set(_ext "zip")
else()
    set(_ext "tar.gz")
endif()

# ── Имена артефактов ────────────────────────────────────────────
set(_artifact "Core-Releases-${CORE_SDK_VERSION}-${_plat}-qt5.${_ext}")
set(_base_url "https://github.com/${CORE_SDK_REPO}/releases/download/v${CORE_SDK_VERSION}")
set(_url      "${_base_url}/${_artifact}")
set(_sha_url  "${_base_url}/SHA256SUMS")

# ── Кэш ─────────────────────────────────────────────────────────
set(_cache_dir "${CMAKE_BINARY_DIR}/_deps/core-sdk-${CORE_SDK_VERSION}-${_plat}")
set(_archive   "${_cache_dir}/${_artifact}")
set(_sha_sums  "${_cache_dir}/SHA256SUMS")
set(_extract   "${_cache_dir}/extracted")
set(_stamp     "${_cache_dir}/.extracted.ok")

file(MAKE_DIRECTORY "${_cache_dir}")

# ── Шаг 1. SHA256SUMS (маленький, качаем один раз) ──────────────
if(NOT EXISTS "${_sha_sums}")
    message(STATUS "Core SDK ${CORE_SDK_VERSION}: fetching SHA256SUMS")
    file(DOWNLOAD "${_sha_url}" "${_sha_sums}"
         TLS_VERIFY ON STATUS _sha_dl)
    list(GET _sha_dl 0 _sha_code)
    if(NOT _sha_code EQUAL 0)
        message(WARNING "Could not download ${_sha_url} — hash check will be skipped")
        file(REMOVE "${_sha_sums}")
    endif()
endif()

# ── Шаг 2. Парсинг SHA256SUMS (без regex-квантификаторов подряд) ─
# Строка: "<hash>  <file>" (text) или "<hash> *<file>" (binary).
# Устойчивый парсер: split по whitespace, потом strip "*".
set(_expected_hash "")
if(EXISTS "${_sha_sums}")
    file(STRINGS "${_sha_sums}" _lines)
    foreach(_line IN LISTS _lines)
        string(REGEX MATCHALL "[^ \t]+" _tok "${_line}")
        list(LENGTH _tok _ntok)
        if(_ntok GREATER_EQUAL 2)
            list(GET _tok 0 _h)
            list(GET _tok 1 _f)
            string(REGEX REPLACE "^\\*" "" _f "${_f}")
            if(_f STREQUAL _artifact)
                set(_expected_hash "${_h}")
                break()
            endif()
        endif()
    endforeach()
    if(_expected_hash STREQUAL "")
        message(WARNING "SHA256SUMS has no entry for ${_artifact} — hash check skipped")
    endif()
endif()

# ── Шаг 3. Скачивание архива (с кэшем через EXPECTED_HASH) ──────
# file(DOWNLOAD EXPECTED_HASH ...) не скачивает, если файл уже есть
# и совпадает по хэшу. И перекачивает, если файл битый.
if(_expected_hash)
    set(_cached FALSE)
    if(EXISTS "${_archive}")
        file(SHA256 "${_archive}" _actual_hash)
        if(_actual_hash STREQUAL _expected_hash)
            set(_cached TRUE)
        endif()
    endif()

    if(_cached)
        message(STATUS "Core SDK ${CORE_SDK_VERSION} (${_plat}): using cached ${_archive}")
    else()
        message(STATUS "Core SDK ${CORE_SDK_VERSION} (${_plat}): download ${_url} (sha256=${_expected_hash})")
    endif()

    file(DOWNLOAD "${_url}" "${_archive}"
         EXPECTED_HASH "SHA256=${_expected_hash}"
         SHOW_PROGRESS TLS_VERIFY ON STATUS _dl)
else()
    if(NOT EXISTS "${_archive}")
        message(STATUS "Core SDK ${CORE_SDK_VERSION} (${_plat}): download ${_url}")
        file(DOWNLOAD "${_url}" "${_archive}"
             SHOW_PROGRESS TLS_VERIFY ON STATUS _dl)
    else()
        message(STATUS "Core SDK ${CORE_SDK_VERSION}: using cached ${_archive} (no hash)")
    endif()
endif()

list(GET _dl 0 _code)
if(NOT _code EQUAL 0)
    list(GET _dl 1 _msg)
    message(FATAL_ERROR "Core SDK download failed: ${_msg}\n  URL: ${_url}")
endif()

# ── Шаг 4. Распаковка (один раз) ────────────────────────────────
if(NOT EXISTS "${_stamp}")
    message(STATUS "Core SDK ${CORE_SDK_VERSION}: extracting ${_archive}")
    file(REMOVE_RECURSE "${_extract}")
    file(MAKE_DIRECTORY "${_extract}")
    file(ARCHIVE_EXTRACT INPUT "${_archive}" DESTINATION "${_extract}")
    file(WRITE "${_stamp}" "ok")
endif()

# ── Шаг 5. Поиск корня SDK ──────────────────────────────────────
set(_sdk_root "")
if(EXISTS "${_extract}/lib/cmake/Core/CoreConfig.cmake")
    set(_sdk_root "${_extract}")
else()
    file(GLOB _cands LIST_DIRECTORIES true "${_extract}/*")
    foreach(_c IN LISTS _cands)
        if(IS_DIRECTORY "${_c}" AND EXISTS "${_c}/lib/cmake/Core/CoreConfig.cmake")
            set(_sdk_root "${_c}")
            break()
        endif()
    endforeach()
endif()
if(NOT _sdk_root)
    message(FATAL_ERROR "CoreConfig.cmake not found in extracted archive: ${_archive}")
endif()

set(CORE_SDK_ROOT "${_sdk_root}" CACHE PATH "Core SDK root (fetched)" FORCE)
list(PREPEND CMAKE_PREFIX_PATH "${CORE_SDK_ROOT}")
message(STATUS "Core SDK root: ${CORE_SDK_ROOT}")