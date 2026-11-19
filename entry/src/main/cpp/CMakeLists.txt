cmake_minimum_required(VERSION 3.5.0)
project(PrismPlayerNative)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
)

add_library(prismplayer SHARED
    napi_init.cpp
    xcomponent_bridge.cpp
    smb2_client.cpp
    stream_proxy.cpp
    player_engine.cpp
    metadata_probe.cpp
)

target_link_libraries(prismplayer PUBLIC
    libace_napi.z.so
    libace_ndk.z.so
    libnative_window.so
    libavplayer.so
    libavmetadata_extractor.so
    libnative_media_codecbase.so
    libnative_media_core.so
    libhilog_ndk.z.so
    dl
    pthread
)
