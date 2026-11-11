# qmake-appinfo.pri — сгенерировать appinfo.env из appinfo.env.in
# для qmake-сборки (паритет с CMake configure_file в CMakeLists.txt).
#
# Include в конец .pro:
#   include(.ci/qmake/qmake-appinfo.pri)
#
# Опциональные переопределения (до include):
#   APPINFO_TEMPLATE — путь к appinfo.env.in (default: $$PWD/appinfo.env.in)
#   APPINFO_OUTPUT   — куда писать .env       (default: $$DESTDIR/appinfo.env)

isEmpty(APPINFO_TEMPLATE): APPINFO_TEMPLATE = $$_PRO_FILE_PWD_/appinfo.env.in
!exists($$APPINFO_TEMPLATE): error("qmake-appinfo.pri: $$APPINFO_TEMPLATE not found")

isEmpty(APPINFO_VERSION) {
    _APPINFO_VER_FILE = $$_PRO_FILE_PWD_/VERSION
    !exists($$_APPINFO_VER_FILE): error("qmake-appinfo.pri: VERSION not found at $$_APPINFO_VER_FILE")
    APPINFO_VERSION = $$system(cat $$shell_path($$_APPINFO_VER_FILE))
    APPINFO_VERSION = $$replace(APPINFO_VERSION, "\\s", "")
}

isEmpty(APPINFO_OUTPUT): APPINFO_OUTPUT = $$DESTDIR/appinfo.env

APPINFO_CMD  = sed -e "s%@PROJECT_VERSION@%$$APPINFO_VERSION%g"
APPINFO_CMD += $$shell_path($$APPINFO_TEMPLATE) > $$shell_path($$APPINFO_OUTPUT)

QMAKE_POST_LINK += $$escape_expand(\\n\\t) mkdir -p $$shell_path($$DESTDIR) && $$APPINFO_CMD


