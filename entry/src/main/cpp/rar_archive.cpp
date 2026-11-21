/**
 * RAR 解包（基于 vendored UnRAR，RARDLL 接口）。
 *
 * 字幕站（射手/字幕库）常把字幕打成 RAR，而系统 zlib 只能解 ZIP。
 * 这里只做「解到指定目录并回报文件名」，字幕挑选逻辑仍留在 ArkTS 侧，
 * 与现有 ZIP 流程保持同构。
 *
 * 路径安全：交给 libunrar 的 ConvertPath 处理（会剥离绝对路径与 .. 段），
 * 调用方另外传入一个全新的专用目录，避免与已有文件冲突。
 */

#include <napi/native_api.h>
#include <hilog/log.h>

#include <memory>
#include <string>
#include <vector>

// dll.hpp 只有在 RARDLL 下才定义 UINT/LPARAM/UNRARCALLBACK 等平台 typedef
#define RARDLL 1
#define _UNIX 1
#include "third_party/unrar/dll.hpp"

#undef LOG_TAG
#define LOG_TAG "PrismRar"

namespace {

struct RarJob {
    std::string archivePath;
    std::string destDir;
    bool ok = false;
    std::string error;
    std::vector<std::string> names;
    napi_deferred deferred = nullptr;
    napi_async_work work = nullptr;
};

int ExtractAll(RarJob* job) {
    RAROpenArchiveDataEx openData = {};
    openData.ArcName = const_cast<char*>(job->archivePath.c_str());
    openData.OpenMode = RAR_OM_EXTRACT;

    HANDLE h = RAROpenArchiveEx(&openData);
    if (h == nullptr) {
        job->error = "无法打开 RAR（OpenResult=" + std::to_string(openData.OpenResult) + "）";
        return openData.OpenResult;
    }

    RARHeaderDataEx header = {};
    int rc = 0;
    while ((rc = RARReadHeaderEx(h, &header)) == 0) {
        std::string name = header.FileName;
        // 只保留文件名，目录结构由 libunrar 创建到 destDir 下
        int processRc = RARProcessFile(h, RAR_EXTRACT, const_cast<char*>(job->destDir.c_str()), nullptr);
        if (processRc != 0) {
            job->error = "解包失败（" + name + "，code=" + std::to_string(processRc) + "）";
            rc = processRc;
            break;
        }
        if (!name.empty()) {
            job->names.push_back(name);
        }
        header = {};
    }

    RARCloseArchive(h);

    if (job->names.empty() && job->error.empty()) {
        if (rc == ERAR_MISSING_PASSWORD) {
            job->error = "压缩包已加密，无法解压";
        } else if (rc == ERAR_BAD_ARCHIVE || rc == ERAR_BAD_DATA) {
            job->error = "不是有效的 RAR 文件";
        } else {
            job->error = "压缩包内没有文件";
        }
        return -1;
    }
    job->ok = true;
    return 0;
}

void ExecuteRar(napi_env /*env*/, void* data) {
    auto* job = static_cast<RarJob*>(data);
    ExtractAll(job);
    OH_LOG_INFO(LOG_APP, "rar extract ok=%{public}d entries=%{public}zu",
                job->ok ? 1 : 0, job->names.size());
}

void CompleteRar(napi_env env, napi_status /*status*/, void* data) {
    std::unique_ptr<RarJob> job(static_cast<RarJob*>(data));
    napi_value result = nullptr;
    napi_create_object(env, &result);

    napi_value okVal = nullptr;
    napi_get_boolean(env, job->ok, &okVal);
    napi_set_named_property(env, result, "ok", okVal);

    napi_value errVal = nullptr;
    napi_create_string_utf8(env, job->error.c_str(), NAPI_AUTO_LENGTH, &errVal);
    napi_set_named_property(env, result, "error", errVal);

    napi_value names = nullptr;
    napi_create_array_with_length(env, job->names.size(), &names);
    for (size_t i = 0; i < job->names.size(); ++i) {
        napi_value item = nullptr;
        napi_create_string_utf8(env, job->names[i].c_str(), NAPI_AUTO_LENGTH, &item);
        napi_set_element(env, names, static_cast<uint32_t>(i), item);
    }
    napi_set_named_property(env, result, "names", names);

    napi_resolve_deferred(env, job->deferred, result);
    if (job->work) {
        napi_delete_async_work(env, job->work);
    }
}

napi_value GetUtf8Arg(napi_env env, napi_value value) {
    return value;
}

std::string StrArg(napi_env env, napi_value value) {
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    std::string out(len, '\0');
    napi_get_value_string_utf8(env, value, out.data(), len + 1, &len);
    out.resize(len);
    return out;
}

napi_value RarExtractTo(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    auto* job = new RarJob();
    if (argc >= 1) job->archivePath = StrArg(env, args[0]);
    if (argc >= 2) job->destDir = StrArg(env, args[1]);

    napi_value promise = nullptr;
    napi_create_promise(env, &job->deferred, &promise);

    napi_value workName = nullptr;
    napi_create_string_utf8(env, "PrismRarExtract", NAPI_AUTO_LENGTH, &workName);
    if (napi_create_async_work(env, nullptr, workName, ExecuteRar, CompleteRar, job, &job->work) == napi_ok &&
        napi_queue_async_work(env, job->work) == napi_ok) {
        return promise;
    }
    delete job;
    napi_value failed = nullptr;
    napi_get_undefined(env, &failed);
    return failed;
}

} // namespace

void RegisterRarArchive(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"rarExtractTo", nullptr, RarExtractTo, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
