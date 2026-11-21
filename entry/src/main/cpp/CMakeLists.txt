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

# UnRAR（RARDLL 模式）：字幕站常用 RAR 打包，系统 zlib 只能解 ZIP
# 只编译官方 makefile 的 OBJECTS + LIB_OBJ 清单：
# 7.x 源码里有 `#include "xxx.cpp"` 的写法，整目录 glob 会重复定义。
set(UNRAR_DIR ${NATIVERENDER_ROOT_PATH}/third_party/unrar)
set(UNRAR_SOURCES
    ${UNRAR_DIR}/rar.cpp ${UNRAR_DIR}/strlist.cpp ${UNRAR_DIR}/strfn.cpp
    ${UNRAR_DIR}/pathfn.cpp ${UNRAR_DIR}/smallfn.cpp ${UNRAR_DIR}/global.cpp
    ${UNRAR_DIR}/file.cpp ${UNRAR_DIR}/filefn.cpp ${UNRAR_DIR}/filcreat.cpp
    ${UNRAR_DIR}/archive.cpp ${UNRAR_DIR}/arcread.cpp ${UNRAR_DIR}/unicode.cpp
    ${UNRAR_DIR}/system.cpp ${UNRAR_DIR}/crypt.cpp ${UNRAR_DIR}/crc.cpp
    ${UNRAR_DIR}/rawread.cpp ${UNRAR_DIR}/encname.cpp ${UNRAR_DIR}/resource.cpp
    ${UNRAR_DIR}/match.cpp ${UNRAR_DIR}/timefn.cpp ${UNRAR_DIR}/rdwrfn.cpp
    ${UNRAR_DIR}/consio.cpp ${UNRAR_DIR}/options.cpp ${UNRAR_DIR}/errhnd.cpp
    ${UNRAR_DIR}/rarvm.cpp ${UNRAR_DIR}/secpassword.cpp ${UNRAR_DIR}/rijndael.cpp
    ${UNRAR_DIR}/getbits.cpp ${UNRAR_DIR}/sha1.cpp ${UNRAR_DIR}/sha256.cpp
    ${UNRAR_DIR}/blake2s.cpp ${UNRAR_DIR}/hash.cpp ${UNRAR_DIR}/extinfo.cpp
    ${UNRAR_DIR}/extract.cpp ${UNRAR_DIR}/volume.cpp ${UNRAR_DIR}/list.cpp
    ${UNRAR_DIR}/find.cpp ${UNRAR_DIR}/unpack.cpp ${UNRAR_DIR}/headers.cpp
    ${UNRAR_DIR}/threadpool.cpp ${UNRAR_DIR}/rs16.cpp ${UNRAR_DIR}/cmddata.cpp
    ${UNRAR_DIR}/ui.cpp ${UNRAR_DIR}/largepage.cpp ${UNRAR_DIR}/filestr.cpp
    ${UNRAR_DIR}/scantree.cpp ${UNRAR_DIR}/dll.cpp ${UNRAR_DIR}/qopen.cpp)
add_library(unrar STATIC ${UNRAR_SOURCES})
target_compile_definitions(unrar PRIVATE RARDLL _UNIX _FILE_OFFSET_BITS=64 _LARGEFILE_SOURCE)
target_include_directories(unrar PRIVATE ${NATIVERENDER_ROOT_PATH}/third_party/unrar)

add_library(prismplayer SHARED
    napi_init.cpp
    rar_archive.cpp
    xcomponent_bridge.cpp
    smb2_client.cpp
    stream_proxy.cpp
    player_engine.cpp
    metadata_probe.cpp
)

target_link_libraries(prismplayer PUBLIC
    unrar
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
