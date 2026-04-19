cmake_minimum_required(VERSION 3.20)
project(QDragToGrant LANGUAGES CXX OBJCXX)

if(NOT APPLE)
    message(FATAL_ERROR "QDragToGrant is macOS-only")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET "14.0" CACHE STRING "Minimum macOS deployment target" FORCE)

if(NOT DEFINED CMAKE_PREFIX_PATH AND EXISTS "$ENV{HOME}/Qt/6.9.3/macos")
    set(CMAKE_PREFIX_PATH "$ENV{HOME}/Qt/6.9.3/macos")
endif()

find_package(Qt6 REQUIRED COMPONENTS Widgets)

set(QDRAGTOGRANT_SOURCES
    src/qdragtogrant/QDragToGrant.h
    src/qdragtogrant/QDragToGrantPanel.cpp
    src/qdragtogrant/QDragToGrantHostApp.mm
    src/qdragtogrant/SettingsWindowLocator.h
    src/qdragtogrant/SettingsWindowLocator.mm
    src/qdragtogrant/AppDragSourceView.h
    src/qdragtogrant/AppDragSourceView.mm
    src/qdragtogrant/OverlayWindowController.h
    src/qdragtogrant/OverlayWindowController.mm
    src/qdragtogrant/TrustChecker.h
    src/qdragtogrant/TrustChecker.mm
    src/qdragtogrant/QDragToGrantAssistant.mm
)

add_library(qdragtogrant STATIC ${QDRAGTOGRANT_SOURCES})
target_include_directories(qdragtogrant PUBLIC src)
target_compile_options(qdragtogrant PRIVATE
    "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>"
)
target_link_libraries(qdragtogrant PUBLIC
    Qt6::Widgets
    "-framework AppKit"
    "-framework Foundation"
    "-framework CoreGraphics"
    "-framework QuartzCore"
    "-framework Security"
    "-framework ApplicationServices"
)

add_executable(QDragToGrantSample MACOSX_BUNDLE
    src/main.cpp
    src/MainWindow.h
    src/MainWindow.cpp
)
target_link_libraries(QDragToGrantSample PRIVATE qdragtogrant)
set_target_properties(QDragToGrantSample PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "QDragToGrant Sample"
    MACOSX_BUNDLE_GUI_IDENTIFIER "org.lostdomain.QDragToGrantSample"
    MACOSX_BUNDLE_BUNDLE_VERSION "1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
)
