cmake_minimum_required(VERSION 3.16)

if(POLICY CMP0091)
    cmake_policy(SET CMP0091 NEW)
endif()

project(mininotes VERSION 1.0.5 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

set(
    MININOTES_MINGW_RUNTIME_DIR
    ""
    CACHE PATH
    "Directory containing MinGW/UCRT64 runtime DLLs for Windows packaging"
)

if(WIN32)
    set(CMAKE_INSTALL_BINDIR ".")
    set(CMAKE_INSTALL_LIBDIR ".")
    set(QT_DEPLOY_BIN_DIR ".")
    set(QT_DEPLOY_LIB_DIR ".")
    set(QT_DEPLOY_PLUGINS_DIR "plugins")
    set(QT_DEPLOY_QML_DIR "qml")
    set(QT_DEPLOY_TRANSLATIONS_DIR "translations")
endif()

if(POLICY CMP0219)
    cmake_policy(SET CMP0219 NEW)
endif()

find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core)
find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core Gui Sql Qml Quick)

set(MININOTES_SOURCES
    src/platform/qt/qt_platform_paths.cpp
    src/application/note_service.cpp
    src/data/sqlite/database.cpp
    src/data/sqlite/sqlite_note_repository.cpp
    src/presentation/note_controller.cpp
    src/presentation/note_list_model.cpp)

set(MININOTES_HEADERS
    src/platform/platform_paths.h
    src/platform/qt/qt_platform_paths.h
    src/application/note_service.h
    src/domain/note.h
    src/domain/inote_repository.h
    src/data/sqlite/database.h
    src/data/sqlite/sqlite_note_repository.h
    src/presentation/note_controller.h
    src/presentation/note_list_model.h)

add_executable(mininotes WIN32
    src/app/main.cpp
    ${MININOTES_SOURCES}
    ${MININOTES_HEADERS})

target_include_directories(mininotes PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src)

target_link_libraries(mininotes PRIVATE
    Qt${QT_VERSION_MAJOR}::Core
    Qt${QT_VERSION_MAJOR}::Gui
    Qt${QT_VERSION_MAJOR}::Sql
    Qt${QT_VERSION_MAJOR}::Qml
    Qt${QT_VERSION_MAJOR}::Quick)

include(CheckIPOSupported)

check_ipo_supported(
    RESULT MININOTES_IPO_SUPPORTED
    OUTPUT MININOTES_IPO_ERROR
    LANGUAGES CXX
)

if(MININOTES_IPO_SUPPORTED)
    set_property(
        TARGET mininotes
        PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE
    )
else()
    message(
        WARNING
        "MiniNotes: IPO/LTO is not supported: ${MININOTES_IPO_ERROR}"
    )
endif()

if(MINGW)
    target_compile_options(
        mininotes
        PRIVATE
            "$<$<CONFIG:Release>:-ffunction-sections>"
            "$<$<CONFIG:Release>:-fdata-sections>"
    )

    target_link_options(
        mininotes
        PRIVATE
            "$<$<CONFIG:Release>:-Wl,--gc-sections>"
            "$<$<CONFIG:Release>:-static-libgcc>"
            "$<$<CONFIG:Release>:-static-libstdc++>"
            "$<$<CONFIG:Release>:-s>"
    )
endif()

if(MSVC)
    set_property(
        TARGET mininotes
        PROPERTY MSVC_RUNTIME_LIBRARY
        "MultiThreaded$<$<CONFIG:Debug>:Debug>"
    )
endif()

configure_file(
    manifest.json.in
    ${CMAKE_CURRENT_BINARY_DIR}/manifest.json
)

option(
    MININOTES_PACKAGE
    "Enable standard Linux/Windows desktop installation and package layout"
    OFF
)

option(
    MININOTES_FLATPAK
    "Use Flatpak-specific desktop metadata and installation paths"
    OFF
)

if(MININOTES_PACKAGE)

    if(WIN32)

        # Windows package layout:
        # executable + Qt runtime + QML runtime + application QML
        # all live in the same portable directory tree.
        install(
            TARGETS mininotes
            RUNTIME DESTINATION .
        )

        install(
            DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/qml/
            DESTINATION qml
        )

        install(
            FILES
                ${CMAKE_CURRENT_SOURCE_DIR}/LICENSE
            DESTINATION .
        )

    else()

        install(
            TARGETS mininotes
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        )

        install(
            DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/qml/
            DESTINATION ${CMAKE_INSTALL_DATADIR}/mininotes/qml
        )

        if(MININOTES_FLATPAK)

            install(
                FILES
                    ${CMAKE_CURRENT_SOURCE_DIR}/packaging/flatpak/io.github.ahmadabdelbary2001.mininote.desktop
                DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
            )

            install(
                FILES
                    ${CMAKE_CURRENT_SOURCE_DIR}/packaging/flatpak/io.github.ahmadabdelbary2001.mininote.metainfo.xml
                DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo
            )

            install(
                FILES
                    ${CMAKE_CURRENT_SOURCE_DIR}/assets/icons/mininotes.svg
                DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
                RENAME io.github.ahmadabdelbary2001.mininote.svg
            )

            install(
                FILES
                    ${CMAKE_CURRENT_SOURCE_DIR}/LICENSE
                DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/io.github.ahmadabdelbary2001.mininote
            )

        else()

            install(
                FILES
                    ${CMAKE_CURRENT_SOURCE_DIR}/packaging/appstream/io.github.ahmadabdelbary2001.mininote.desktop
                DESTINATION ${CMAKE_INSTALL_DATADIR}/applications
            )

            install(
                FILES
                    ${CMAKE_CURRENT_SOURCE_DIR}/packaging/appstream/io.github.ahmadabdelbary2001.mininote.metainfo.xml
                DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo
            )

            install(
                FILES
                    ${CMAKE_CURRENT_SOURCE_DIR}/assets/icons/mininotes.svg
                DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps
                RENAME io.github.ahmadabdelbary2001.mininote.svg
            )

        endif()

    endif()

    # ------------------------------------------------------------------
    # Windows deployment
    # ------------------------------------------------------------------
    #
    # Qt 6 deployment uses windeployqt underneath.
    # We also ask it to:
    #   - scan our QML directory
    #   - deploy the compiler runtime
    #   - generate qt.conf
    #
    # Unused SQL plugins are excluded. SQLite remains deployed.
    #
    if(WIN32)

        if(QT_VERSION_MAJOR EQUAL 6)

        qt_generate_deploy_script(
            TARGET mininotes
            OUTPUT_SCRIPT mininotes_deploy_script
            CONTENT [=[
                set(QT_DEPLOY_BIN_DIR ".")
                set(QT_DEPLOY_LIB_DIR ".")
                set(QT_DEPLOY_PLUGINS_DIR "plugins")
                set(QT_DEPLOY_QML_DIR "qml")
                set(QT_DEPLOY_TRANSLATIONS_DIR "translations")

                qt_deploy_runtime_dependencies(
                    EXECUTABLE "${QT_DEPLOY_BIN_DIR}/$<TARGET_FILE_NAME:mininotes>"
                    GENERATE_QT_CONF
                    QML_DIR "qml"

                    DEPLOY_TOOL_OPTIONS
                        --qmldir "${CMAKE_CURRENT_SOURCE_DIR}/qml"
                        --compiler-runtime

                    EXCLUDE_PLUGIN_TYPES
                        qmltooling
                        generic
                        networkinformation
                        tls

                    EXCLUDE_PLUGINS
                        qsqlibase
                        qsqlmysql
                        qsqlodbc
                        qsqlpsql

                    NO_TRANSLATIONS
                )
            ]=]
        )

        install(SCRIPT ${mininotes_deploy_script})

        if(MININOTES_MINGW_RUNTIME_DIR)
            configure_file(
                ${CMAKE_CURRENT_SOURCE_DIR}/cmake/DeployMinGWRuntime.cmake.in
                ${CMAKE_CURRENT_BINARY_DIR}/DeployMinGWRuntime.cmake
                @ONLY
            )

            install(
                SCRIPT ${CMAKE_CURRENT_BINARY_DIR}/DeployMinGWRuntime.cmake
            )
        endif()

        else()

            message(FATAL_ERROR
                "Windows packaging requires Qt 6. MiniNotes Windows deployment is not configured for Qt 5."
            )

        endif()

    endif()

    # ------------------------------------------------------------------
    # CPack
    # ------------------------------------------------------------------

    set(CPACK_PACKAGE_NAME "MiniNotes")
    set(CPACK_PACKAGE_VENDOR "MiniNotes Developers")
    set(CPACK_PACKAGE_CONTACT "MiniNotes Developers")

    set(
        CPACK_PACKAGE_DESCRIPTION_SUMMARY
        "Offline-first notes application"
    )

    set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
    set(CPACK_PACKAGE_INSTALL_DIRECTORY "MiniNotes")

    if(WIN32)

        set(
            CPACK_PACKAGE_FILE_NAME
            "MiniNotes-${PROJECT_VERSION}-Windows-x64"
        )

        # Produce all three Windows distribution formats.
        set(
            CPACK_GENERATOR
            "ZIP;NSIS;WIX"
        )

        # -------------------------
        # NSIS Installer (.exe)
        # -------------------------

        set(CPACK_NSIS_DISPLAY_NAME "MiniNotes")
        set(CPACK_NSIS_PACKAGE_NAME "MiniNotes")
        set(CPACK_NSIS_EXECUTABLES_DIRECTORY ".")
        set(CPACK_NSIS_FINISHPAGE_RUN "mininotes.exe")

        set(
            CPACK_NSIS_MENU_LINKS
            "mininotes.exe"
            "MiniNotes"
        )

        set(
            CPACK_NSIS_URL_INFO_ABOUT
            "https://github.com/ahmadabdelbary2001/mininote"
        )

        # -------------------------
        # WiX Installer (.msi)
        # -------------------------

        set(CPACK_WIX_VERSION 4)
        set(CPACK_WIX_ARCHITECTURE x64)
        set(CPACK_WIX_INSTALL_SCOPE perMachine)

        # Stable UpgradeCode for future MiniNotes upgrades.
        set(
            CPACK_WIX_UPGRADE_GUID
            "4FABB0CD-A6D2-4D58-A31D-4C0C2DC6B37F"
        )

    else()

        set(CPACK_DEBIAN_PACKAGE_MAINTAINER "MiniNotes Developers")
        set(CPACK_DEBIAN_PACKAGE_SECTION "utils")
        set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)

        set(
            CPACK_DEBIAN_PACKAGE_DEPENDS
            "libqt6sql6-sqlite, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-window"
        )

        set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
        set(CPACK_STRIP_FILES ON)
        set(CPACK_GENERATOR DEB)

    endif()

    include(CPack)

else()

    install(
        TARGETS mininotes
        RUNTIME DESTINATION ${CMAKE_INSTALL_PREFIX}
    )

    install(
        DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/qml
        DESTINATION ${CMAKE_INSTALL_PREFIX}
    )

    install(
        FILES ${CMAKE_CURRENT_BINARY_DIR}/manifest.json
        DESTINATION ${CMAKE_INSTALL_PREFIX}
    )

    install(
        FILES ${CMAKE_CURRENT_SOURCE_DIR}/mininotes.apparmor
        DESTINATION ${CMAKE_INSTALL_PREFIX}
    )

    install(
        FILES ${CMAKE_CURRENT_SOURCE_DIR}/mininotes.desktop
        DESTINATION ${CMAKE_INSTALL_PREFIX}
    )

    install(
        FILES ${CMAKE_CURRENT_SOURCE_DIR}/assets/icons/mininotes.svg
        DESTINATION ${CMAKE_INSTALL_PREFIX}/assets/icons
    )

endif()

add_custom_command(TARGET mininotes POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_CURRENT_SOURCE_DIR}/qml
        $<TARGET_FILE_DIR:mininotes>/qml
)

option(
    MININOTES_BUILD_TESTS
    "Build backend functional tests"
    OFF
)

if(MININOTES_BUILD_TESTS)

    enable_testing()

    find_package(
        Qt${QT_VERSION_MAJOR}
        REQUIRED
        COMPONENTS Test
    )

    add_executable(
        mininotes_backend_test
        tests/tst_backend.cpp
        ${MININOTES_SOURCES}
        ${MININOTES_HEADERS}
    )

    target_include_directories(
        mininotes_backend_test
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    target_link_libraries(
        mininotes_backend_test
        PRIVATE
            Qt${QT_VERSION_MAJOR}::Core
            Qt${QT_VERSION_MAJOR}::Sql
            Qt${QT_VERSION_MAJOR}::Test
    )

    add_test(
        NAME mininotes_backend_test
        COMMAND mininotes_backend_test
    )

    add_executable(
        mininotes_service_test
        tests/tst_note_service.cpp
        src/application/note_service.cpp
        src/application/note_service.h
        src/domain/note.h
        src/domain/inote_repository.h
    )

    target_include_directories(
        mininotes_service_test
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    target_link_libraries(
        mininotes_service_test
        PRIVATE
            Qt${QT_VERSION_MAJOR}::Core
            Qt${QT_VERSION_MAJOR}::Test
    )

    add_test(
        NAME mininotes_service_test
        COMMAND mininotes_service_test
    )

    add_executable(
        mininotes_platform_test
        tests/tst_platform_paths.cpp
        src/platform/qt/qt_platform_paths.cpp
        src/platform/qt/qt_platform_paths.h
        src/platform/platform_paths.h
    )

    target_include_directories(
        mininotes_platform_test
        PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
    )

    target_link_libraries(
        mininotes_platform_test
        PRIVATE
            Qt${QT_VERSION_MAJOR}::Core
            Qt${QT_VERSION_MAJOR}::Test
    )

    add_test(
        NAME mininotes_platform_test
        COMMAND mininotes_platform_test
    )

endif()