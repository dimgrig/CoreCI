if(NOT DEFINED LATEST OR NOT DEFINED TARGET)
    message(FATAL_ERROR "CreateLatestLink: LATEST and TARGET must be set")
endif()

if(WIN32)
    # mklink не принимает forward slashes ("C:/Users/..." → switch "/Users" →
    # "Invalid argument: Users"). Нужны нативные пути с \. file(TO_NATIVE_PATH)
    # даёт именно их. rmdir тоже переводим для единообразия.
    file(TO_NATIVE_PATH "${LATEST}" _latest_native)
    file(TO_NATIVE_PATH "${TARGET}" _target_native)

    execute_process(COMMAND cmd /c rmdir /S /Q "${_latest_native}"
                    RESULT_VARIABLE _rc_rm OUTPUT_QUIET ERROR_QUIET)
    # _rc_rm != 0 если latest ещё не было — норма.

    execute_process(COMMAND cmd /c mklink /J "${_latest_native}" "${_target_native}"
                    RESULT_VARIABLE _rc OUTPUT_VARIABLE _out ERROR_VARIABLE _err)
    if(NOT _rc EQUAL 0)
        # Race-safe: параллельные .pro могут гоняться, но результат один.
        if(NOT (EXISTS "${LATEST}" AND EXISTS "${TARGET}"))
            message(WARNING
                "CreateLatestLink: mklink failed for ${LATEST} -> ${TARGET} "
                "(rc=${_rc}): ${_err}")
        endif()
    endif()
else()
    execute_process(COMMAND rm -f "${LATEST}" OUTPUT_QUIET ERROR_QUIET)
    execute_process(COMMAND ln -sfn "${TARGET}" "${LATEST}"
                    RESULT_VARIABLE _rc OUTPUT_QUIET ERROR_QUIET)
    if(NOT _rc EQUAL 0)
        message(WARNING "CreateLatestLink: ln failed for ${LATEST} (rc=${_rc})")
    endif()
endif()