#include "xcomponent_bridge.h"
#include <hilog/log.h>

#undef LOG_TAG
#define LOG_TAG "PrismXComponent"

namespace prism {

namespace {
void OnSurfaceCreatedCB(OH_NativeXComponent* component, void* window) {
    XComponentBridge::Instance().HandleSurfaceCreated(component, window);
}
void OnSurfaceChangedCB(OH_NativeXComponent* component, void* window) {
    XComponentBridge::Instance().HandleSurfaceChanged(component, window);
}
void OnSurfaceDestroyedCB(OH_NativeXComponent* component, void* window) {
    XComponentBridge::Instance().HandleSurfaceDestroyed(component, window);
}
void DispatchTouchEventCB(OH_NativeXComponent* /*component*/, void* /*window*/) {}
} // namespace

XComponentBridge& XComponentBridge::Instance() {
    static XComponentBridge instance;
    return instance;
}

std::string XComponentBridge::GetComponentId(OH_NativeXComponent* component) {
    if (!component) {
        return "";
    }
    char idStr[OH_XCOMPONENT_ID_LEN_MAX + 1] = {0};
    uint64_t idSize = OH_XCOMPONENT_ID_LEN_MAX + 1;
    if (OH_NativeXComponent_GetXComponentId(component, idStr, &idSize) != OH_NATIVEXCOMPONENT_RESULT_SUCCESS) {
        return "";
    }
    return std::string(idStr);
}

void XComponentBridge::RegisterXComponent(OH_NativeXComponent* xcomponent, const std::string& surfaceId) {
    if (!xcomponent || surfaceId.empty()) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        componentIds_[xcomponent] = surfaceId;
    }
    callback_.OnSurfaceCreated = OnSurfaceCreatedCB;
    callback_.OnSurfaceChanged = OnSurfaceChangedCB;
    callback_.OnSurfaceDestroyed = OnSurfaceDestroyedCB;
    callback_.DispatchTouchEvent = DispatchTouchEventCB;
    OH_NativeXComponent_RegisterCallback(xcomponent, &callback_);
    OH_LOG_INFO(LOG_APP, "Registered XComponent surfaceId=%{public}s", surfaceId.c_str());
}

OHNativeWindow* XComponentBridge::GetWindow(const std::string& surfaceId) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = surfaces_.find(surfaceId);
    if (it != surfaces_.end()) {
        return it->second.window;
    }
    return nullptr;
}

void XComponentBridge::AddSurfaceListener(const std::string& surfaceId, SurfaceReadyCallback cb) {
    OHNativeWindow* existing = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        listeners_[surfaceId] = std::move(cb);
        auto it = surfaces_.find(surfaceId);
        if (it != surfaces_.end()) {
            existing = it->second.window;
        }
    }
    if (existing) {
        SurfaceReadyCallback listenerCopy;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto lit = listeners_.find(surfaceId);
            if (lit != listeners_.end()) {
                listenerCopy = lit->second;
            }
        }
        if (listenerCopy) {
            listenerCopy(surfaceId, existing);
        }
    }
}

void XComponentBridge::RemoveSurfaceListener(const std::string& surfaceId) {
    std::lock_guard<std::mutex> lock(mutex_);
    listeners_.erase(surfaceId);
}

void XComponentBridge::HandleSurfaceCreated(OH_NativeXComponent* component, void* window) {
    std::string id = GetComponentId(component);
    uint64_t w = 0;
    uint64_t h = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &w, &h);

    SurfaceReadyCallback listenerCopy;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (id.empty()) {
            auto cit = componentIds_.find(component);
            if (cit != componentIds_.end()) {
                id = cit->second;
            }
        }
        if (id.empty()) {
            return;
        }
        surfaces_[id] = {static_cast<OHNativeWindow*>(window), w, h};
        auto lit = listeners_.find(id);
        if (lit != listeners_.end()) {
            listenerCopy = lit->second;
        }
    }
    OH_LOG_INFO(LOG_APP, "SurfaceCreated id=%{public}s size=%{public}llu x %{public}llu",
                id.c_str(), static_cast<unsigned long long>(w), static_cast<unsigned long long>(h));
    if (listenerCopy) {
        listenerCopy(id, static_cast<OHNativeWindow*>(window));
    }
}

void XComponentBridge::HandleSurfaceChanged(OH_NativeXComponent* component, void* window) {
    std::string id = GetComponentId(component);
    uint64_t w = 0;
    uint64_t h = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &w, &h);
    std::lock_guard<std::mutex> lock(mutex_);
    if (id.empty()) {
        auto cit = componentIds_.find(component);
        if (cit != componentIds_.end()) {
            id = cit->second;
        }
    }
    if (!id.empty()) {
        surfaces_[id] = {static_cast<OHNativeWindow*>(window), w, h};
    }
}

void XComponentBridge::HandleSurfaceDestroyed(OH_NativeXComponent* component, void* /*window*/) {
    std::string id = GetComponentId(component);
    std::lock_guard<std::mutex> lock(mutex_);
    if (id.empty()) {
        auto cit = componentIds_.find(component);
        if (cit != componentIds_.end()) {
            id = cit->second;
        }
    }
    if (!id.empty()) {
        surfaces_.erase(id);
    }
    componentIds_.erase(component);
}

} // namespace prism
