#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>
#include <multimedia/player_framework/native_avcapability.h>
#include <napi/native_api.h>
#include <dirent.h>
#include <unistd.h>
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "metadata_probe.h"
#include "player_engine.h"
#include "smb2_client.h"
#include "stream_proxy.h"
#include "xcomponent_bridge.h"

// 定义在 rar_archive.cpp
void RegisterRarArchive(napi_env env, napi_value exports);

#undef LOG_TAG
#define LOG_TAG "PrismNapi"

namespace {

std::mutex g_playersMutex;
std::atomic<int32_t> g_nextPlayerId{1};
std::unordered_map<int32_t, std::unique_ptr<prism::NativePlayerEngine>> g_players;
std::unordered_map<int32_t, napi_threadsafe_function> g_playerCallbacks;

std::mutex g_httpsTsfnMutex;
napi_threadsafe_function g_httpsFetchTsfn = nullptr;

std::string GetStringArg(napi_env env, napi_value val) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, val, nullptr, 0, &len) != napi_ok) {
        return "";
    }
    std::string out(len, '\0');
    if (len > 0) {
        napi_get_value_string_utf8(env, val, &out[0], len + 1, &len);
    }
    return out;
}

std::string GetPropString(napi_env env, napi_value obj, const char* key, const std::string& defVal = "") {
    bool has = false;
    if (napi_has_named_property(env, obj, key, &has) != napi_ok || !has) return defVal;
    napi_value v;
    if (napi_get_named_property(env, obj, key, &v) != napi_ok) return defVal;
    napi_valuetype t = napi_undefined;
    napi_typeof(env, v, &t);
    if (t != napi_string) return defVal;
    return GetStringArg(env, v);
}

bool GetPropBool(napi_env env, napi_value obj, const char* key, bool defVal = false) {
    bool has = false;
    if (napi_has_named_property(env, obj, key, &has) != napi_ok || !has) return defVal;
    napi_value v;
    if (napi_get_named_property(env, obj, key, &v) != napi_ok) return defVal;
    bool b = defVal;
    if (napi_get_value_bool(env, v, &b) != napi_ok) return defVal;
    return b;
}

int32_t GetPropInt(napi_env env, napi_value obj, const char* key, int32_t defVal = 0) {
    bool has = false;
    if (napi_has_named_property(env, obj, key, &has) != napi_ok || !has) return defVal;
    napi_value v;
    if (napi_get_named_property(env, obj, key, &v) != napi_ok) return defVal;
    int32_t val = defVal;
    if (napi_get_value_int32(env, v, &val) != napi_ok) return defVal;
    return val;
}

void SetBoolProp(napi_env env, napi_value obj, const char* key, bool val) {
    napi_value v;
    napi_get_boolean(env, val, &v);
    napi_set_named_property(env, obj, key, v);
}

void SetIntProp(napi_env env, napi_value obj, const char* key, int32_t val) {
    napi_value v;
    napi_create_int32(env, val, &v);
    napi_set_named_property(env, obj, key, v);
}

void SetInt64Prop(napi_env env, napi_value obj, const char* key, int64_t val) {
    napi_value v;
    napi_create_int64(env, val, &v);
    napi_set_named_property(env, obj, key, v);
}

void SetDoubleProp(napi_env env, napi_value obj, const char* key, double val) {
    napi_value v;
    napi_create_double(env, val, &v);
    napi_set_named_property(env, obj, key, v);
}

void SetStrProp(napi_env env, napi_value obj, const char* key, const std::string& val) {
    napi_value v;
    napi_create_string_utf8(env, val.c_str(), val.size(), &v);
    napi_set_named_property(env, obj, key, v);
}

struct HttpsFetchCallData {
    int64_t reqId;
    std::string url;
    std::string authHeader;
    int64_t rangeStart;
    int64_t rangeEnd;
    bool allowInsecure;
};

void CallJsHttpsFetch(napi_env env, napi_value jsCallback, void* /*context*/, void* data) {
    std::unique_ptr<HttpsFetchCallData> req(static_cast<HttpsFetchCallData*>(data));
    if (!env || !jsCallback || !req) return;

    napi_value argv[6];
    napi_create_int64(env, req->reqId, &argv[0]);
    napi_create_string_utf8(env, req->url.c_str(), req->url.size(), &argv[1]);
    napi_create_string_utf8(env, req->authHeader.c_str(), req->authHeader.size(), &argv[2]);
    napi_create_int64(env, req->rangeStart, &argv[3]);
    napi_create_int64(env, req->rangeEnd, &argv[4]);
    napi_get_boolean(env, req->allowInsecure, &argv[5]);

    napi_value undef;
    napi_get_undefined(env, &undef);
    napi_call_function(env, undef, jsCallback, 6, argv, nullptr);
}

void CallJsPlayerEvent(napi_env env, napi_value jsCallback, void* /*context*/, void* data) {
    std::unique_ptr<prism::PlayerEvent> ev(static_cast<prism::PlayerEvent*>(data));
    if (!env || !jsCallback || !ev) return;

    napi_value obj;
    napi_create_object(env, &obj);
    SetStrProp(env, obj, "type", ev->type);
    if (ev->type == "state") SetIntProp(env, obj, "state", ev->state);
    else if (ev->type == "position" || ev->type == "seekDone") SetIntProp(env, obj, "positionMs", ev->positionMs);
    else if (ev->type == "duration") SetInt64Prop(env, obj, "durationMs", ev->durationMs);
    else if (ev->type == "resolution") {
        SetIntProp(env, obj, "width", ev->width);
        SetIntProp(env, obj, "height", ev->height);
    } else if (ev->type == "buffering") {
        SetIntProp(env, obj, "bufferingType", ev->bufferingType);
        SetIntProp(env, obj, "bufferingValue", ev->bufferingValue);
    } else if (ev->type == "rateDone") {
        SetDoubleProp(env, obj, "rate", static_cast<double>(ev->rate));
    } else if (ev->type == "error") {
        SetIntProp(env, obj, "errorCode", ev->errorCode);
        SetStrProp(env, obj, "errorMsg", ev->errorMsg);
    }

    napi_value undef;
    napi_get_undefined(env, &undef);
    napi_call_function(env, undef, jsCallback, 1, &obj, nullptr);
}

// --- Stream Proxy NAPI ---
napi_value StartStreamProxy(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t mb = 64;
    if (argc >= 1) napi_get_value_int32(env, args[0], &mb);
    int port = prism::StreamRangeProxy::Instance().Start(mb);
    napi_value ret;
    napi_create_int32(env, port, &ret);
    return ret;
}

napi_value StopStreamProxy(napi_env env, napi_callback_info /*info*/) {
    prism::StreamRangeProxy::Instance().Stop();
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value RegisterProxyStream(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) return nullptr;

    std::string id = GetStringArg(env, args[0]);
    prism::StreamConfig cfg;
    cfg.url = GetPropString(env, args[1], "url");
    cfg.authHeader = GetPropString(env, args[1], "authHeader");
    cfg.userAgent = GetPropString(env, args[1], "userAgent", "PrismPlayer/1.0");
    cfg.allowInsecureTls = GetPropBool(env, args[1], "allowInsecureTls", false);
    cfg.cacheAlist302 = GetPropBool(env, args[1], "cacheAlist302", true);
    cfg.smbHost = GetPropString(env, args[1], "smbHost");
    cfg.smbPort = GetPropInt(env, args[1], "smbPort", 445);
    cfg.smbShare = GetPropString(env, args[1], "smbShare");
    cfg.smbPath = GetPropString(env, args[1], "smbPath");
    cfg.smbUser = GetPropString(env, args[1], "smbUser");
    cfg.smbPass = GetPropString(env, args[1], "smbPass");

    std::string localUrl = prism::StreamRangeProxy::Instance().RegisterStream(id, cfg);
    napi_value ret;
    napi_create_string_utf8(env, localUrl.c_str(), localUrl.size(), &ret);
    return ret;
}

napi_value UnregisterProxyStream(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc >= 1) {
        prism::StreamRangeProxy::Instance().UnregisterStream(GetStringArg(env, args[0]));
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value GetProxyStats(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    prism::StreamStats st;
    if (argc >= 1) {
        st = prism::StreamRangeProxy::Instance().GetStats(GetStringArg(env, args[0]));
    }
    napi_value obj;
    napi_create_object(env, &obj);
    SetInt64Prop(env, obj, "bytesServed", st.bytesServed);
    SetInt64Prop(env, obj, "cacheHits", st.cacheHits);
    SetInt64Prop(env, obj, "cacheMisses", st.cacheMisses);
    SetInt64Prop(env, obj, "cachedBytes", st.cachedBytes);
    SetInt64Prop(env, obj, "totalSize", st.totalSize);
    SetStrProp(env, obj, "resolvedUrl", st.resolvedUrl);
    return obj;
}

napi_value SetHttpsFetchHandler(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) return nullptr;

    napi_value workName;
    napi_create_string_utf8(env, "PrismHttpsFetch", NAPI_AUTO_LENGTH, &workName);
    napi_threadsafe_function tsfn = nullptr;
    napi_create_threadsafe_function(env, args[0], nullptr, workName, 0, 1, nullptr, nullptr, nullptr, CallJsHttpsFetch, &tsfn);

    {
        std::lock_guard<std::mutex> lock(g_httpsTsfnMutex);
        if (g_httpsFetchTsfn) {
            napi_release_threadsafe_function(g_httpsFetchTsfn, napi_tsfn_abort);
        }
        g_httpsFetchTsfn = tsfn;
    }

    prism::StreamRangeProxy::Instance().SetHttpsDispatcher(
        [](int64_t reqId, const std::string& url, const std::string& auth, int64_t start, int64_t end, bool insecure) {
            std::lock_guard<std::mutex> lock(g_httpsTsfnMutex);
            if (!g_httpsFetchTsfn) return;
            auto* payload = new HttpsFetchCallData{reqId, url, auth, start, end, insecure};
            if (napi_call_threadsafe_function(g_httpsFetchTsfn, payload, napi_tsfn_nonblocking) != napi_ok) {
                delete payload;
            }
        });

    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value ResolveHttpsChunk(napi_env env, napi_callback_info info) {
    size_t argc = 6;
    napi_value args[6];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 6) return nullptr;

    int64_t reqId = 0;
    int32_t statusCode = 0;
    int64_t totalSize = -1;
    napi_get_value_int64(env, args[0], &reqId);
    napi_get_value_int32(env, args[1], &statusCode);
    napi_get_value_int64(env, args[2], &totalSize);
    std::string contentType = GetStringArg(env, args[3]);
    std::string redirectUrl = GetStringArg(env, args[4]);

    void* bufData = nullptr;
    size_t bufLen = 0;
    std::vector<uint8_t> bytes;
    if (napi_get_arraybuffer_info(env, args[5], &bufData, &bufLen) == napi_ok && bufData && bufLen > 0) {
        auto* p = static_cast<uint8_t*>(bufData);
        bytes.assign(p, p + bufLen);
    }

    prism::StreamRangeProxy::Instance().CompleteHttpsRequest(reqId, statusCode, totalSize, contentType, redirectUrl, std::move(bytes));
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

// --- Native AVPlayer NAPI ---
prism::NativePlayerEngine* FindPlayer(int32_t id) {
    auto it = g_players.find(id);
    return (it != g_players.end()) ? it->second.get() : nullptr;
}

napi_value CreatePlayer(napi_env env, napi_callback_info /*info*/) {
    int32_t id = g_nextPlayerId.fetch_add(1);
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        g_players[id] = std::make_unique<prism::NativePlayerEngine>(id);
    }
    napi_value ret;
    napi_create_int32(env, id, &ret);
    return ret;
}

napi_value DestroyPlayer(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0;
    if (argc >= 1) napi_get_value_int32(env, args[0], &id);

    std::lock_guard<std::mutex> lock(g_playersMutex);
    g_players.erase(id);
    auto cit = g_playerCallbacks.find(id);
    if (cit != g_playerCallbacks.end()) {
        napi_release_threadsafe_function(cit->second, napi_tsfn_abort);
        g_playerCallbacks.erase(cit);
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value BindSurface(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0;
    napi_get_value_int32(env, args[0], &id);
    std::string surfaceId = GetStringArg(env, args[1]);
    bool ok = false;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) ok = p->BindSurface(surfaceId);
    }
    napi_value ret;
    napi_get_boolean(env, ok, &ret);
    return ret;
}

napi_value SetUrlSource(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0;
    napi_get_value_int32(env, args[0], &id);
    std::string url = GetStringArg(env, args[1]);
    int32_t rc = -1;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) rc = p->SetUrlSource(url);
    }
    napi_value ret;
    napi_create_int32(env, rc, &ret);
    return ret;
}

napi_value SetFdSource(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0, fd = -1;
    int64_t offset = 0, size = 0;
    napi_get_value_int32(env, args[0], &id);
    napi_get_value_int32(env, args[1], &fd);
    napi_get_value_int64(env, args[2], &offset);
    napi_get_value_int64(env, args[3], &size);
    int32_t rc = -1;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) rc = p->SetFdSource(fd, offset, size);
    }
    napi_value ret;
    napi_create_int32(env, rc, &ret);
    return ret;
}

#define PLAYER_SIMPLE_OP(FnName, MethodCall) \
napi_value FnName(napi_env env, napi_callback_info info) { \
    size_t argc = 1; \
    napi_value args[1]; \
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr); \
    int32_t id = 0; \
    napi_get_value_int32(env, args[0], &id); \
    int32_t rc = -1; \
    { \
        std::lock_guard<std::mutex> lock(g_playersMutex); \
        if (auto* p = FindPlayer(id)) rc = p->MethodCall(); \
    } \
    napi_value ret; \
    napi_create_int32(env, rc, &ret); \
    return ret; \
}

PLAYER_SIMPLE_OP(PreparePlayer, Prepare)
PLAYER_SIMPLE_OP(PlayPlayer, Play)
PLAYER_SIMPLE_OP(PausePlayer, Pause)
PLAYER_SIMPLE_OP(StopPlayer, Stop)
PLAYER_SIMPLE_OP(ResetPlayer, Reset)

napi_value SeekPlayer(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0, pos = 0, mode = 2;
    napi_get_value_int32(env, args[0], &id);
    napi_get_value_int32(env, args[1], &pos);
    if (argc >= 3) napi_get_value_int32(env, args[2], &mode);
    int32_t rc = -1;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) rc = p->Seek(pos, mode);
    }
    napi_value ret;
    napi_create_int32(env, rc, &ret);
    return ret;
}

napi_value SetPlayerRate(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0;
    double rate = 1.0;
    napi_get_value_int32(env, args[0], &id);
    napi_get_value_double(env, args[1], &rate);
    int32_t rc = -1;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) rc = p->SetRate(static_cast<float>(rate));
    }
    napi_value ret;
    napi_create_int32(env, rc, &ret);
    return ret;
}

napi_value SetPlayerVolume(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0;
    double vol = 1.0;
    napi_get_value_int32(env, args[0], &id);
    napi_get_value_double(env, args[1], &vol);
    int32_t rc = -1;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) rc = p->SetVolume(static_cast<float>(vol));
    }
    napi_value ret;
    napi_create_int32(env, rc, &ret);
    return ret;
}

napi_value SelectPlayerTrack(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0, idx = 0;
    napi_get_value_int32(env, args[0], &id);
    napi_get_value_int32(env, args[1], &idx);
    int32_t rc = -1;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) rc = p->SelectTrack(idx);
    }
    napi_value ret;
    napi_create_int32(env, rc, &ret);
    return ret;
}

napi_value DeselectPlayerTrack(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0, idx = 0;
    napi_get_value_int32(env, args[0], &id);
    napi_get_value_int32(env, args[1], &idx);
    int32_t rc = -1;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) rc = p->DeselectTrack(idx);
    }
    napi_value ret;
    napi_create_int32(env, rc, &ret);
    return ret;
}

napi_value GetPlayerTracks(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0;
    napi_get_value_int32(env, args[0], &id);
    std::vector<prism::TrackInfo> tracks;
    {
        std::lock_guard<std::mutex> lock(g_playersMutex);
        if (auto* p = FindPlayer(id)) tracks = p->GetTracks();
    }
    napi_value arr;
    napi_create_array_with_length(env, tracks.size(), &arr);
    for (size_t i = 0; i < tracks.size(); ++i) {
        napi_value obj;
        napi_create_object(env, &obj);
        SetIntProp(env, obj, "index", tracks[i].index);
        SetIntProp(env, obj, "trackType", tracks[i].trackType);
        SetStrProp(env, obj, "mimeType", tracks[i].mimeType);
        SetStrProp(env, obj, "language", tracks[i].language);
        SetStrProp(env, obj, "title", tracks[i].title);
        SetIntProp(env, obj, "sampleRate", tracks[i].sampleRate);
        SetIntProp(env, obj, "channels", tracks[i].channels);
        SetIntProp(env, obj, "width", tracks[i].width);
        SetIntProp(env, obj, "height", tracks[i].height);
        napi_set_element(env, arr, static_cast<uint32_t>(i), obj);
    }
    return arr;
}

napi_value SetPlayerEventCallback(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t id = 0;
    napi_get_value_int32(env, args[0], &id);

    napi_value workName;
    napi_create_string_utf8(env, "PrismPlayerEvent", NAPI_AUTO_LENGTH, &workName);
    napi_threadsafe_function tsfn = nullptr;
    napi_create_threadsafe_function(env, args[1], nullptr, workName, 0, 1, nullptr, nullptr, nullptr, CallJsPlayerEvent, &tsfn);

    std::lock_guard<std::mutex> lock(g_playersMutex);
    auto old = g_playerCallbacks.find(id);
    if (old != g_playerCallbacks.end()) {
        napi_release_threadsafe_function(old->second, napi_tsfn_abort);
    }
    g_playerCallbacks[id] = tsfn;
    if (auto* p = FindPlayer(id)) {
        p->SetEventCallback([tsfn](const prism::PlayerEvent& ev) {
            auto* copy = new prism::PlayerEvent(ev);
            if (napi_call_threadsafe_function(tsfn, copy, napi_tsfn_nonblocking) != napi_ok) {
                delete copy;
            }
        });
    }

    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value ProbeLocalMedia(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t fd = -1;
    int64_t offset = 0, size = 0;
    napi_get_value_int32(env, args[0], &fd);
    napi_get_value_int64(env, args[1], &offset);
    napi_get_value_int64(env, args[2], &size);

    prism::LocalMediaMeta meta = prism::ProbeLocalMediaFd(fd, offset, size);
    napi_value obj;
    napi_create_object(env, &obj);
    SetInt64Prop(env, obj, "durationMs", meta.durationMs);
    SetIntProp(env, obj, "width", meta.width);
    SetIntProp(env, obj, "height", meta.height);
    SetStrProp(env, obj, "title", meta.title);
    SetStrProp(env, obj, "mimeType", meta.mimeType);
    SetStrProp(env, obj, "artist", meta.artist);
    SetStrProp(env, obj, "album", meta.album);
    return obj;
}

/**
 * 通过已打开目录的 fd 列举文件名。
 *
 * 用户经 Picker 授权的目录是 `file://docs/...` URI，而 fileIo.listFile 只接受沙箱路径，
 * 直接把 URI 传给它会 ENOENT（13900002）。先用 fs.open(uri) 在授权范围内拿到目录 fd，
 * 再在 native 侧 fdopendir/readdir，即可枚举；失败返回 null，调用方走原有回退。
 */
napi_value ListDirectoryFd(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t fd = -1;
    if (argc < 1 || napi_get_value_int32(env, args[0], &fd) != napi_ok || fd < 0) {
        napi_value nullValue;
        napi_get_null(env, &nullValue);
        return nullValue;
    }

    std::vector<std::string> names;
    int dupFd = dup(fd);
    if (dupFd < 0) {
        napi_value nullValue;
        napi_get_null(env, &nullValue);
        return nullValue;
    }
    DIR* dir = fdopendir(dupFd);
    if (dir == nullptr) {
        close(dupFd);
        napi_value nullValue;
        napi_get_null(env, &nullValue);
        return nullValue;
    }
    struct dirent* ent = nullptr;
    while ((ent = readdir(dir)) != nullptr) {
        const char* name = ent->d_name;
        if (name == nullptr) continue;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) continue;
        names.emplace_back(name);
    }
    closedir(dir);

    napi_value arr;
    napi_create_array_with_length(env, names.size(), &arr);
    for (size_t i = 0; i < names.size(); i++) {
        napi_value item;
        napi_create_string_utf8(env, names[i].c_str(), NAPI_AUTO_LENGTH, &item);
        napi_set_element(env, arr, static_cast<uint32_t>(i), item);
    }
    return arr;
}

// --- Async SMB2 NAPI Helpers ---
prism::SmbConnectionConfig ReadSmbConfigArg(napi_env env, napi_value obj) {
    prism::SmbConnectionConfig cfg;
    cfg.host = GetPropString(env, obj, "host");
    cfg.port = GetPropInt(env, obj, "port", 445);
    if (cfg.port <= 0) cfg.port = 445;
    cfg.share = GetPropString(env, obj, "share");
    cfg.domain = GetPropString(env, obj, "domain");
    cfg.username = GetPropString(env, obj, "username");
    cfg.password = GetPropString(env, obj, "password");
    return cfg;
}

struct SmbAsyncWork {
    enum Kind { TEST, LIST, READ_TEXT, READ_BYTES };
    Kind kind;
    prism::SmbConnectionConfig cfg;
    std::string targetPath;
    size_t maxBytes = 2 * 1024 * 1024;
    int64_t startMs = 0;

    // Results
    bool ok = false;
    int64_t latencyMs = 0;
    std::string error;
    std::vector<prism::SmbFileEntry> entries;
    std::string textContent;
    std::vector<uint8_t> fileBytes;

    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

void ExecuteSmbAsync(napi_env /*env*/, void* data) {
    auto* job = static_cast<SmbAsyncWork*>(data);
    auto t0 = std::chrono::steady_clock::now();

    prism::Smb2Session sess;
    if (!sess.Connect(job->cfg, job->error)) {
        job->ok = false;
        return;
    }

    if (job->kind == SmbAsyncWork::TEST) {
        auto res = sess.ListDirectory(job->targetPath.empty() ? "/" : job->targetPath);
        job->ok = res.ok;
        job->error = res.error;
        job->entries = std::move(res.entries);
    } else if (job->kind == SmbAsyncWork::LIST) {
        auto res = sess.ListDirectory(job->targetPath.empty() ? "/" : job->targetPath);
        job->ok = res.ok;
        job->error = res.error;
        job->entries = std::move(res.entries);
    } else if (job->kind == SmbAsyncWork::READ_TEXT || job->kind == SmbAsyncWork::READ_BYTES) {
        std::vector<uint8_t> bytes;
        if (sess.ReadSmallFile(job->targetPath, job->maxBytes, bytes, job->error)) {
            job->ok = true;
            if (job->kind == SmbAsyncWork::READ_TEXT) {
                job->textContent.assign(reinterpret_cast<const char*>(bytes.data()), bytes.size());
            } else {
                job->fileBytes = std::move(bytes);
            }
        } else {
            job->ok = false;
        }
    }

    auto t1 = std::chrono::steady_clock::now();
    job->latencyMs = std::chrono::duration_cast<std::chrono::milliseconds>(t1 - t0).count();
}

void CompleteSmbAsync(napi_env env, napi_status /*status*/, void* data) {
    std::unique_ptr<SmbAsyncWork> job(static_cast<SmbAsyncWork*>(data));
    napi_value result = nullptr;

    if (job->kind == SmbAsyncWork::READ_BYTES) {
        void* raw = nullptr;
        napi_value buf = nullptr;
        if (napi_create_arraybuffer(env, job->fileBytes.size(), &raw, &buf) == napi_ok) {
            if (!job->fileBytes.empty() && raw != nullptr) {
                std::memcpy(raw, job->fileBytes.data(), job->fileBytes.size());
            }
            result = buf;
        } else {
            napi_create_arraybuffer(env, 0, &raw, &result);
        }
    } else if (job->kind == SmbAsyncWork::READ_TEXT) {
        napi_create_string_utf8(env, job->textContent.c_str(), job->textContent.size(), &result);
    } else if (job->kind == SmbAsyncWork::TEST) {
        napi_create_object(env, &result);
        SetBoolProp(env, result, "ok", job->ok);
        SetInt64Prop(env, result, "latencyMs", job->latencyMs);
        SetIntProp(env, result, "entryCount", static_cast<int32_t>(job->entries.size()));
        std::string msg = job->ok
            ? ("SMB2 连接成功 · 发现 " + std::to_string(job->entries.size()) + " 个目录项")
            : job->error;
        SetStrProp(env, result, "message", msg);
    } else {
        napi_create_object(env, &result);
        SetBoolProp(env, result, "ok", job->ok);
        SetStrProp(env, result, "error", job->error);
        napi_value arr;
        napi_create_array_with_length(env, job->entries.size(), &arr);
        for (size_t i = 0; i < job->entries.size(); ++i) {
            const auto& e = job->entries[i];
            napi_value item;
            napi_create_object(env, &item);
            SetStrProp(env, item, "name", e.name);
            SetStrProp(env, item, "path", e.path);
            SetBoolProp(env, item, "isDirectory", e.isDirectory);
            SetInt64Prop(env, item, "size", e.size);
            SetInt64Prop(env, item, "lastModifiedMs", e.lastModifiedMs);
            napi_set_element(env, arr, static_cast<uint32_t>(i), item);
        }
        napi_set_named_property(env, result, "entries", arr);
    }

    napi_resolve_deferred(env, job->deferred, result);
    if (job->work) {
        napi_delete_async_work(env, job->work);
    }
}

napi_value LaunchSmbWork(napi_env env, SmbAsyncWork* rawJob, const char* nameStr) {
    std::unique_ptr<SmbAsyncWork> job(rawJob);
    napi_value promise;
    napi_create_promise(env, &job->deferred, &promise);
    napi_value workName;
    napi_create_string_utf8(env, nameStr, NAPI_AUTO_LENGTH, &workName);
    if (napi_create_async_work(env, nullptr, workName, ExecuteSmbAsync, CompleteSmbAsync, job.get(), &job->work) == napi_ok &&
        napi_queue_async_work(env, job->work) == napi_ok) {
        job.release();
        return promise;
    }
    return promise;
}

napi_value SmbTestConnection(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto* job = new SmbAsyncWork();
    job->kind = SmbAsyncWork::TEST;
    if (argc >= 1) job->cfg = ReadSmbConfigArg(env, args[0]);
    if (argc >= 2) job->targetPath = GetStringArg(env, args[1]);
    return LaunchSmbWork(env, job, "PrismSmbTest");
}

napi_value SmbListDirectory(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto* job = new SmbAsyncWork();
    job->kind = SmbAsyncWork::LIST;
    if (argc >= 1) job->cfg = ReadSmbConfigArg(env, args[0]);
    if (argc >= 2) job->targetPath = GetStringArg(env, args[1]);
    return LaunchSmbWork(env, job, "PrismSmbList");
}

/**
 * 按字节读取 SMB 上的小文件（海报、封面等二进制资源）。
 * 与 smbReadTextFile 的区别只在返回类型：这里是 ArrayBuffer，不经 UTF-8 解码。
 */
napi_value SmbReadFileBytes(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto* job = new SmbAsyncWork();
    job->kind = SmbAsyncWork::READ_BYTES;
    job->maxBytes = 16 * 1024 * 1024;
    if (argc >= 1) job->cfg = ReadSmbConfigArg(env, args[0]);
    if (argc >= 2) job->targetPath = GetStringArg(env, args[1]);
    if (argc >= 3) {
        int32_t maxB = 0;
        if (napi_get_value_int32(env, args[2], &maxB) == napi_ok && maxB > 0) {
            job->maxBytes = static_cast<size_t>(maxB);
        }
    }
    return LaunchSmbWork(env, job, "PrismSmbReadBytes");
}

napi_value SmbReadTextFile(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto* job = new SmbAsyncWork();
    job->kind = SmbAsyncWork::READ_TEXT;
    if (argc >= 1) job->cfg = ReadSmbConfigArg(env, args[0]);
    if (argc >= 2) job->targetPath = GetStringArg(env, args[1]);
    if (argc >= 3) {
        int32_t maxB = 0;
        if (napi_get_value_int32(env, args[2], &maxB) == napi_ok && maxB > 0) {
            job->maxBytes = static_cast<size_t>(maxB);
        }
    }
    return LaunchSmbWork(env, job, "PrismSmbReadText");
}

/**
 * 查询本机是否存在该 mime 的**硬件**视频解码器。
 *
 * 走 OH_AVCodec_GetCapabilityByCategory(mime, false, HARDWARE)：只有存在硬解实现时才返回非空，
 * 因此不需要再调 OH_AVCapability_IsHardware 二次判断。
 * 返回 { supported, name }；查不到能力时 supported=false，调用方据此降级软解。
 */
napi_value QueryVideoDecoderCapability(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value obj;
    napi_create_object(env, &obj);
    SetBoolProp(env, obj, "supported", false);
    SetStrProp(env, obj, "name", "");

    if (argc < 1) return obj;
    std::string mime = GetStringArg(env, args[0]);
    if (mime.empty()) return obj;

    OH_AVCapability* cap = OH_AVCodec_GetCapabilityByCategory(mime.c_str(), false, HARDWARE);
    if (cap == nullptr) return obj;

    const char* name = OH_AVCapability_GetName(cap);
    SetBoolProp(env, obj, "supported", true);
    SetStrProp(env, obj, "name", name != nullptr ? std::string(name) : std::string(mime));
    return obj;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    // Check if ArkUI passed XComponent handle on module exports
    napi_value exportInstance = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) == napi_ok && exportInstance) {
        OH_NativeXComponent* xcomp = nullptr;
        if (napi_unwrap(env, exportInstance, reinterpret_cast<void**>(&xcomp)) == napi_ok && xcomp) {
            char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {0};
            uint64_t idLen = OH_XCOMPONENT_ID_LEN_MAX + 1;
            if (OH_NativeXComponent_GetXComponentId(xcomp, idStr, &idLen) == OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
                prism::XComponentBridge::Instance().RegisterXComponent(xcomp, std::string(idStr));
            }
        }
    }

    napi_property_descriptor desc[] = {
        {"startStreamProxy", nullptr, StartStreamProxy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopStreamProxy", nullptr, StopStreamProxy, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"registerProxyStream", nullptr, RegisterProxyStream, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"unregisterProxyStream", nullptr, UnregisterProxyStream, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getProxyStats", nullptr, GetProxyStats, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setHttpsFetchHandler", nullptr, SetHttpsFetchHandler, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resolveHttpsChunk", nullptr, ResolveHttpsChunk, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createPlayer", nullptr, CreatePlayer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"destroyPlayer", nullptr, DestroyPlayer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"bindSurface", nullptr, BindSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setUrlSource", nullptr, SetUrlSource, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setFdSource", nullptr, SetFdSource, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"preparePlayer", nullptr, PreparePlayer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"playPlayer", nullptr, PlayPlayer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pausePlayer", nullptr, PausePlayer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopPlayer", nullptr, StopPlayer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resetPlayer", nullptr, ResetPlayer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"seekPlayer", nullptr, SeekPlayer, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPlayerRate", nullptr, SetPlayerRate, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPlayerVolume", nullptr, SetPlayerVolume, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"selectPlayerTrack", nullptr, SelectPlayerTrack, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"deselectPlayerTrack", nullptr, DeselectPlayerTrack, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getPlayerTracks", nullptr, GetPlayerTracks, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPlayerEventCallback", nullptr, SetPlayerEventCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"probeLocalMedia", nullptr, ProbeLocalMedia, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"listDirectoryFd", nullptr, ListDirectoryFd, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"queryVideoDecoderCapability", nullptr, QueryVideoDecoderCapability, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"smbTestConnection", nullptr, SmbTestConnection, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"smbListDirectory", nullptr, SmbListDirectory, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"smbReadTextFile", nullptr, SmbReadTextFile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"smbReadFileBytes", nullptr, SmbReadFileBytes, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    RegisterRarArchive(env, exports);
    return exports;
}
EXTERN_C_END

static napi_module prismModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "prismplayer",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterPrismPlayerModule(void) {
    napi_module_register(&prismModule);
}
