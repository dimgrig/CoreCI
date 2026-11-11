# Reads appinfo.env.in, substitutes @VERSION@ with PROJECT_VERSION (and
# any extra @KEY@ from VARS), writes appinfo.env, installs it into prefix.
#
# Usage:
#   include(cmake/AppInfo.cmake)
#   core_write_appinfo(
#       TEMPLATE    "${CMAKE_CURRENT_SOURCE_DIR}/appinfo.env.in"
#       OUTPUT      "${CMAKE_CURRENT_BINARY_DIR}/appinfo.env"
#       INSTALL_DIR ".")
function(core_write_appinfo)
    cmake_parse_arguments(ARG "" "TEMPLATE;OUTPUT;INSTALL_DIR" "VARS" ${ARGN})

    if(NOT ARG_TEMPLATE)
        set(ARG_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/appinfo.env.in")
    endif()
    if(NOT ARG_OUTPUT)
        set(ARG_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/appinfo.env")
    endif()
    if(NOT ARG_INSTALL_DIR)
        set(ARG_INSTALL_DIR ".")
    endif()

    if(NOT EXISTS "${ARG_TEMPLATE}")
        message(FATAL_ERROR "AppInfo: template not found: ${ARG_TEMPLATE}")
    endif()
    if(NOT PROJECT_VERSION)
        message(FATAL_ERROR "AppInfo: PROJECT_VERSION is empty (call project() first)")
    endif()

    file(READ "${ARG_TEMPLATE}" _content)
    string(REPLACE "@VERSION@" "${PROJECT_VERSION}" _content "${_content}")

    foreach(_kv ${ARG_VARS})
        string(FIND "${_kv}" "=" _eq)
        if(_eq GREATER -1)
            string(SUBSTRING "${_kv}" 0 ${_eq} _k)
            math(EXPR _pos "${_eq}+1")
            string(SUBSTRING "${_kv}" ${_pos} -1 _v)
            string(REPLACE "@${_k}@" "${_v}" _content "${_content}")
        endif()
    endforeach()

    file(WRITE "${ARG_OUTPUT}" "${_content}")
    install(FILES "${ARG_OUTPUT}" DESTINATION "${ARG_INSTALL_DIR}")
    message(STATUS "AppInfo: ${ARG_OUTPUT} (version ${PROJECT_VERSION})")
endfunction()