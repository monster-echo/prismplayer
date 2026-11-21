#include "player_engine.h"
#include "xcomponent_bridge.h"
#include <dlfcn.h>
#include <vector>
#include <hilog/log.h>
#include <multimedia/player_framework/native_avcodec_base.h>
#include <multimedia/player_framework/native_avformat.h>

#undef LOG_TAG
#define LOG_TAG "PrismAVPlayer"

namespace prism {

namespace {
using FnGetTrackCount = uint32_t (*)(OH_AVPlayer*);
using FnGetTrackFormat = OH_AVFormat* (*)(OH_AVPlayer*, uint32_t);
using FnGetTrackDesc = OH_AVFormat* (*)(OH_AVPlayer*, uint32_t);

FnGetTrackCount ResolveGetTrackCount() {
    static FnGetTrackCount fn = reinterpret_cast<FnGetTrackCount>(dlsym(RTLD_DEFAULT, "OH_AVPlayer_GetTrackCount"));
    return fn;
}

FnGetTrackFormat ResolveGetTrackFormat() {
    static FnGetTrackFormat fn = reinterpret_cast<FnGetTrackFormat>(dlsym(RTLD_DEFAULT, "OH_AVPlayer_GetTrackFormat"));
    return fn;
}

FnGetTrackDesc ResolveGetTrackDesc() {
    static FnGetTrackDesc fn = reinterpret_cast<FnGetTrackDesc>(dlsym(RTLD_DEFAULT, "OH_AVPlayer_GetTrackDescription"));
    return fn;
}

// 缓冲策略是 API 23 才有的能力：低版本设备没有这些符号，直接链接会导致 .so 加载失败，
// 因此运行时 dlsym 探测，缺失则静默跳过（行为等同旧版）。
// 实测 SMB 单次读抖动在 0.2~1.9 秒之间，加深缓冲是吸收这种抖动最直接的手段。
void ApplyBufferStrategy(OH_AVPlayer* p) {
    using FnCreate = OH_AVPlaybackStrategy* (*)();
    using FnSetMs = OH_AVErrCode (*)(OH_AVPlaybackStrategy*, int32_t);
    using FnApply = OH_AVErrCode (*)(OH_AVPlayer*, OH_AVPlaybackStrategy*);

    auto create = reinterpret_cast<FnCreate>(dlsym(RTLD_DEFAULT, "OH_AVPlaybackStrategy_Create"));
    auto setBuf = reinterpret_cast<FnSetMs>(dlsym(RTLD_DEFAULT, "OH_AVPlaybackStrategy_SetPreferredBufferDuration"));
    auto setStart = reinterpret_cast<FnSetMs>(dlsym(RTLD_DEFAULT, "OH_AVPlaybackStrategy_SetPreferredBufferDurationForPlaying"));
    auto apply = reinterpret_cast<FnApply>(dlsym(RTLD_DEFAULT, "OH_AVPlayer_SetPlaybackStrategy"));
    if (!create || !setBuf || !apply) {
        OH_LOG_INFO(LOG_APP, "buffer strategy unsupported on this API level, skipped");
        return;
    }

    OH_AVPlaybackStrategy* st = create();
    if (!st) return;
    setBuf(st, 15000);                                  // 目标缓冲 15s
    if (setStart) setStart(st, 2000);                    // 攒够 2s 起播，避免开场久等
    int32_t rc = apply(p, st);
    OH_LOG_INFO(LOG_APP, "buffer strategy applied rc=%{public}d", rc);
    // 不销毁：文档未明确 player 是否持有该指针，宁可有界保留也不冒悬空风险
    static std::vector<OH_AVPlaybackStrategy*> kept;
    kept.push_back(st);
}
} // namespace

NativePlayerEngine::NativePlayerEngine(int32_t id) : id_(id) {
    player_ = OH_AVPlayer_Create();
    if (player_) {
        OH_AVPlayer_SetOnInfoCallback(player_, &NativePlayerEngine::OnPlayerInfo, this);
        OH_AVPlayer_SetOnErrorCallback(player_, &NativePlayerEngine::OnPlayerError, this);
        OH_AVPlayer_SetAudioRendererInfo(player_, AUDIOSTREAM_USAGE_MOVIE);
        OH_AVPlayer_SetAudioInterruptMode(player_, AUDIOSTREAM_INTERRUPT_MODE_SHARE);
        ApplyBufferStrategy(player_);
    }
}

NativePlayerEngine::~NativePlayerEngine() {
    if (!surfaceId_.empty()) {
        XComponentBridge::Instance().RemoveSurfaceListener(surfaceId_);
    }
    if (player_) {
        OH_AVPlayer_SetOnInfoCallback(player_, nullptr, nullptr);
        OH_AVPlayer_SetOnErrorCallback(player_, nullptr, nullptr);
        OH_AVPlayer_ReleaseSync(player_);
        player_ = nullptr;
    }
}

void NativePlayerEngine::ApplySurfaceIfReady(OHNativeWindow* window) {
    if (!player_ || !window) {
        return;
    }
    OH_AVErrCode code = OH_AVPlayer_SetVideoSurface(player_, window);
    OH_LOG_INFO(LOG_APP, "SetVideoSurface player=%{public}d code=%{public}d", id_, code);
}

bool NativePlayerEngine::BindSurface(const std::string& surfaceId) {
    if (surfaceId.empty()) {
        return false;
    }
    if (!surfaceId_.empty() && surfaceId_ != surfaceId) {
        XComponentBridge::Instance().RemoveSurfaceListener(surfaceId_);
    }
    surfaceId_ = surfaceId;
    OHNativeWindow* window = XComponentBridge::Instance().GetWindow(surfaceId);
    if (window) {
        ApplySurfaceIfReady(window);
    }
    XComponentBridge::Instance().AddSurfaceListener(surfaceId, [this](const std::string&, OHNativeWindow* win) {
        ApplySurfaceIfReady(win);
    });
    return true;
}

int32_t NativePlayerEngine::SetUrlSource(const std::string& url) {
    if (!player_ || url.empty()) {
        return AV_ERR_INVALID_VAL;
    }
    OH_AVErrCode err = OH_AVPlayer_SetURLSource(player_, url.c_str());
    if (err == AV_ERR_OK && !surfaceId_.empty()) {
        OHNativeWindow* win = XComponentBridge::Instance().GetWindow(surfaceId_);
        if (win) {
            ApplySurfaceIfReady(win);
        }
    }
    return err;
}

int32_t NativePlayerEngine::SetFdSource(int32_t fd, int64_t offset, int64_t size) {
    if (!player_ || fd < 0) {
        return AV_ERR_INVALID_VAL;
    }
    OH_AVErrCode err = OH_AVPlayer_SetFDSource(player_, fd, offset, size);
    if (err == AV_ERR_OK && !surfaceId_.empty()) {
        OHNativeWindow* win = XComponentBridge::Instance().GetWindow(surfaceId_);
        if (win) {
            ApplySurfaceIfReady(win);
        }
    }
    return err;
}

int32_t NativePlayerEngine::Prepare() {
    if (!player_) return AV_ERR_INVALID_VAL;
    if (!surfaceId_.empty()) {
        OHNativeWindow* win = XComponentBridge::Instance().GetWindow(surfaceId_);
        if (win) {
            ApplySurfaceIfReady(win);
        }
    }
    return OH_AVPlayer_Prepare(player_);
}

int32_t NativePlayerEngine::Play() {
    return player_ ? OH_AVPlayer_Play(player_) : AV_ERR_INVALID_VAL;
}

int32_t NativePlayerEngine::Pause() {
    return player_ ? OH_AVPlayer_Pause(player_) : AV_ERR_INVALID_VAL;
}

int32_t NativePlayerEngine::Stop() {
    return player_ ? OH_AVPlayer_Stop(player_) : AV_ERR_INVALID_VAL;
}

int32_t NativePlayerEngine::Reset() {
    return player_ ? OH_AVPlayer_Reset(player_) : AV_ERR_INVALID_VAL;
}

int32_t NativePlayerEngine::Seek(int32_t positionMs, int32_t mode) {
    if (!player_) return AV_ERR_INVALID_VAL;
    AVPlayerSeekMode seekMode = AV_SEEK_CLOSEST;
    if (mode == 0) seekMode = AV_SEEK_NEXT_SYNC;
    else if (mode == 1) seekMode = AV_SEEK_PREVIOUS_SYNC;
    return OH_AVPlayer_Seek(player_, positionMs, seekMode);
}

int32_t NativePlayerEngine::SetRate(float rate) {
    if (!player_) return AV_ERR_INVALID_VAL;
    if (rate < 0.125f) rate = 0.125f;
    if (rate > 4.0f) rate = 4.0f;
    return OH_AVPlayer_SetPlaybackRate(player_, rate);
}

int32_t NativePlayerEngine::SetVolume(float volume) {
    if (!player_) return AV_ERR_INVALID_VAL;
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    return OH_AVPlayer_SetVolume(player_, volume, volume);
}

int32_t NativePlayerEngine::SelectTrack(int32_t trackIndex) {
    return player_ ? OH_AVPlayer_SelectTrack(player_, trackIndex) : AV_ERR_INVALID_VAL;
}

int32_t NativePlayerEngine::DeselectTrack(int32_t trackIndex) {
    return player_ ? OH_AVPlayer_DeselectTrack(player_, trackIndex) : AV_ERR_INVALID_VAL;
}

std::vector<TrackInfo> NativePlayerEngine::GetTracks() {
    std::vector<TrackInfo> tracks;
    if (!player_) return tracks;

    FnGetTrackCount getCount = ResolveGetTrackCount();
    FnGetTrackFormat getFmt = ResolveGetTrackFormat();
    FnGetTrackDesc getDesc = ResolveGetTrackDesc();

    if (getCount && getFmt) {
        uint32_t count = getCount(player_);
        for (uint32_t i = 0; i < count && i < 64; ++i) {
            OH_AVFormat* fmt = getFmt(player_, i);
            if (!fmt) continue;
            TrackInfo info;
            info.index = static_cast<int32_t>(i);
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_TRACK_TYPE, &info.trackType);
            const char* mime = nullptr;
            if (OH_AVFormat_GetStringValue(fmt, OH_MD_KEY_CODEC_MIME, &mime) && mime) {
                info.mimeType = mime;
            }
            const char* lang = nullptr;
            if (OH_AVFormat_GetStringValue(fmt, OH_MD_KEY_LANGUAGE, &lang) && lang) {
                info.language = lang;
            }
            const char* title = nullptr;
            if (OH_AVFormat_GetStringValue(fmt, OH_MD_KEY_TITLE, &title) && title) {
                info.title = title;
            }
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_AUD_SAMPLE_RATE, &info.sampleRate);
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_AUD_CHANNEL_COUNT, &info.channels);
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_WIDTH, &info.width);
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_HEIGHT, &info.height);
            tracks.push_back(std::move(info));
            OH_AVFormat_Destroy(fmt);
        }
    } else if (getDesc) {
        for (uint32_t i = 0; i < 16; ++i) {
            OH_AVFormat* fmt = getDesc(player_, i);
            if (!fmt) break;
            TrackInfo info;
            info.index = static_cast<int32_t>(i);
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_TRACK_TYPE, &info.trackType);
            const char* mime = nullptr;
            if (OH_AVFormat_GetStringValue(fmt, OH_MD_KEY_CODEC_MIME, &mime) && mime) {
                info.mimeType = mime;
            }
            const char* lang = nullptr;
            if (OH_AVFormat_GetStringValue(fmt, OH_MD_KEY_LANGUAGE, &lang) && lang) {
                info.language = lang;
            }
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_AUD_SAMPLE_RATE, &info.sampleRate);
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_AUD_CHANNEL_COUNT, &info.channels);
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_WIDTH, &info.width);
            OH_AVFormat_GetIntValue(fmt, OH_MD_KEY_HEIGHT, &info.height);
            tracks.push_back(std::move(info));
            OH_AVFormat_Destroy(fmt);
        }
    }
    return tracks;
}

void NativePlayerEngine::SetEventCallback(PlayerEventCallback callback) {
    std::lock_guard<std::mutex> lock(mutex_);
    eventCallback_ = std::move(callback);
}

void NativePlayerEngine::EmitEvent(const PlayerEvent& event) {
    PlayerEventCallback cbCopy;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        cbCopy = eventCallback_;
    }
    if (cbCopy) {
        cbCopy(event);
    }
}

void NativePlayerEngine::OnPlayerInfo(OH_AVPlayer* /*player*/, AVPlayerOnInfoType type, OH_AVFormat* infoBody, void* userData) {
    auto* self = static_cast<NativePlayerEngine*>(userData);
    if (!self) return;

    PlayerEvent ev;
    switch (type) {
        case AV_INFO_TYPE_STATE_CHANGE: {
            ev.type = "state";
            if (infoBody) OH_AVFormat_GetIntValue(infoBody, OH_PLAYER_STATE, &ev.state);
            self->EmitEvent(ev);
            break;
        }
        case AV_INFO_TYPE_POSITION_UPDATE: {
            ev.type = "position";
            if (infoBody) OH_AVFormat_GetIntValue(infoBody, OH_PLAYER_CURRENT_POSITION, &ev.positionMs);
            self->EmitEvent(ev);
            break;
        }
        case AV_INFO_TYPE_DURATION_UPDATE: {
            ev.type = "duration";
            if (infoBody) OH_AVFormat_GetLongValue(infoBody, OH_PLAYER_DURATION, &ev.durationMs);
            self->EmitEvent(ev);
            break;
        }
        case AV_INFO_TYPE_RESOLUTION_CHANGE: {
            ev.type = "resolution";
            if (infoBody) {
                OH_AVFormat_GetIntValue(infoBody, OH_PLAYER_VIDEO_WIDTH, &ev.width);
                OH_AVFormat_GetIntValue(infoBody, OH_PLAYER_VIDEO_HEIGHT, &ev.height);
            }
            self->EmitEvent(ev);
            break;
        }
        case AV_INFO_TYPE_BUFFERING_UPDATE: {
            ev.type = "buffering";
            if (infoBody) {
                OH_AVFormat_GetIntValue(infoBody, OH_PLAYER_BUFFERING_TYPE, &ev.bufferingType);
                OH_AVFormat_GetIntValue(infoBody, OH_PLAYER_BUFFERING_VALUE, &ev.bufferingValue);
            }
            self->EmitEvent(ev);
            break;
        }
        case AV_INFO_TYPE_EOS: {
            ev.type = "eos";
            self->EmitEvent(ev);
            break;
        }
        case AV_INFO_TYPE_SEEKDONE: {
            ev.type = "seekDone";
            if (infoBody) OH_AVFormat_GetIntValue(infoBody, OH_PLAYER_SEEK_POSITION, &ev.positionMs);
            self->EmitEvent(ev);
            break;
        }
        case AV_INFO_TYPE_PLAYBACK_RATE_DONE: {
            ev.type = "rateDone";
            if (infoBody) OH_AVFormat_GetFloatValue(infoBody, OH_PLAYER_PLAYBACK_RATE, &ev.rate);
            self->EmitEvent(ev);
            break;
        }
        case AV_INFO_TYPE_TRACK_INFO_UPDATE: {
            ev.type = "tracksReady";
            self->EmitEvent(ev);
            break;
        }
        default:
            break;
    }
}

void NativePlayerEngine::OnPlayerError(OH_AVPlayer* /*player*/, int32_t errorCode, const char* errorMsg, void* userData) {
    auto* self = static_cast<NativePlayerEngine*>(userData);
    if (!self) return;
    PlayerEvent ev;
    ev.type = "error";
    ev.errorCode = errorCode;
    ev.errorMsg = errorMsg ? errorMsg : "Unknown native player error";
    OH_LOG_ERROR(LOG_APP, "OH_AVPlayer Error code=%{public}d msg=%{public}s", errorCode, ev.errorMsg.c_str());
    self->EmitEvent(ev);
}

} // namespace prism
