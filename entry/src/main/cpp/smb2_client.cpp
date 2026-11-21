#include "smb2_client.h"
#include <ctime>

#include <algorithm>
#include <arpa/inet.h>
#include <cctype>
#include <chrono>
#include <cstring>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <random>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#ifdef __OHOS__
#include <hilog/log.h>
#define SMB_LOGI(...) OH_LOG_INFO(LOG_APP, __VA_ARGS__)
#define SMB_LOGE(...) OH_LOG_ERROR(LOG_APP, __VA_ARGS__)
#else
#define SMB_LOGI(...) ((void)0)
#define SMB_LOGE(...) ((void)0)
#endif

namespace prism {

namespace {

// --- Little Endian Helpers ---
inline void PutU16(std::vector<uint8_t>& buf, size_t off, uint16_t v) {
    buf[off] = static_cast<uint8_t>(v & 0xFF);
    buf[off + 1] = static_cast<uint8_t>((v >> 8) & 0xFF);
}

inline void PutU32(std::vector<uint8_t>& buf, size_t off, uint32_t v) {
    buf[off] = static_cast<uint8_t>(v & 0xFF);
    buf[off + 1] = static_cast<uint8_t>((v >> 8) & 0xFF);
    buf[off + 2] = static_cast<uint8_t>((v >> 16) & 0xFF);
    buf[off + 3] = static_cast<uint8_t>((v >> 24) & 0xFF);
}

inline void PutU64(std::vector<uint8_t>& buf, size_t off, uint64_t v) {
    for (int i = 0; i < 8; ++i) {
        buf[off + i] = static_cast<uint8_t>((v >> (8 * i)) & 0xFF);
    }
}

inline void AppendU16(std::vector<uint8_t>& buf, uint16_t v) {
    buf.push_back(static_cast<uint8_t>(v & 0xFF));
    buf.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
}

inline void AppendU32(std::vector<uint8_t>& buf, uint32_t v) {
    buf.push_back(static_cast<uint8_t>(v & 0xFF));
    buf.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    buf.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
    buf.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
}

inline void AppendU64(std::vector<uint8_t>& buf, uint64_t v) {
    for (int i = 0; i < 8; ++i) {
        buf.push_back(static_cast<uint8_t>((v >> (8 * i)) & 0xFF));
    }
}

inline uint16_t GetU16(const uint8_t* p) {
    return static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8);
}

inline uint32_t GetU32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) |
           (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) |
           (static_cast<uint32_t>(p[3]) << 24);
}

inline uint64_t GetU64(const uint8_t* p) {
    uint64_t v = 0;
    for (int i = 0; i < 8; ++i) {
        v |= static_cast<uint64_t>(p[i]) << (8 * i);
    }
    return v;
}

inline uint32_t RotL32(uint32_t x, uint32_t n) {
    return (x << n) | (x >> (32 - n));
}

// --- RFC 1320 MD4 (for NTOWFv2) ---
std::vector<uint8_t> ComputeMd4(const uint8_t* input, size_t len) {
    std::vector<uint8_t> msg(input, input + len);
    uint64_t bitLen = static_cast<uint64_t>(len) * 8ULL;
    msg.push_back(0x80);
    while ((msg.size() % 64) != 56) {
        msg.push_back(0x00);
    }
    AppendU64(msg, bitLen);

    uint32_t A = 0x67452301U;
    uint32_t B = 0xEFCDAB89U;
    uint32_t C = 0x98BADCFEU;
    uint32_t D = 0x10325476U;

    auto F = [](uint32_t x, uint32_t y, uint32_t z) { return (x & y) | (~x & z); };
    auto G = [](uint32_t x, uint32_t y, uint32_t z) { return (x & y) | (x & z) | (y & z); };
    auto H = [](uint32_t x, uint32_t y, uint32_t z) { return x ^ y ^ z; };

    for (size_t off = 0; off < msg.size(); off += 64) {
        uint32_t X[16];
        for (int i = 0; i < 16; ++i) {
            X[i] = GetU32(&msg[off + i * 4]);
        }
        uint32_t AA = A, BB = B, CC = C, DD = D;

        // Round 1
        static constexpr int r1s[4] = {3, 7, 11, 19};
        for (int i = 0; i < 16; ++i) {
            int k = i;
            uint32_t s = r1s[i % 4];
            if (i % 4 == 0) A = RotL32(A + F(B, C, D) + X[k], s);
            else if (i % 4 == 1) D = RotL32(D + F(A, B, C) + X[k], s);
            else if (i % 4 == 2) C = RotL32(C + F(D, A, B) + X[k], s);
            else B = RotL32(B + F(C, D, A) + X[k], s);
        }
        // Round 2
        static constexpr int r2s[4] = {3, 5, 9, 13};
        for (int i = 0; i < 16; ++i) {
            int k = (i % 4) * 4 + (i / 4);
            uint32_t s = r2s[i % 4];
            if (i % 4 == 0) A = RotL32(A + G(B, C, D) + X[k] + 0x5A827999U, s);
            else if (i % 4 == 1) D = RotL32(D + G(A, B, C) + X[k] + 0x5A827999U, s);
            else if (i % 4 == 2) C = RotL32(C + G(D, A, B) + X[k] + 0x5A827999U, s);
            else B = RotL32(B + G(C, D, A) + X[k] + 0x5A827999U, s);
        }
        // Round 3
        static constexpr int r3k[16] = {0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15};
        static constexpr int r3s[4] = {3, 9, 11, 15};
        for (int i = 0; i < 16; ++i) {
            int k = r3k[i];
            uint32_t s = r3s[i % 4];
            if (i % 4 == 0) A = RotL32(A + H(B, C, D) + X[k] + 0x6ED9EBA1U, s);
            else if (i % 4 == 1) D = RotL32(D + H(A, B, C) + X[k] + 0x6ED9EBA1U, s);
            else if (i % 4 == 2) C = RotL32(C + H(D, A, B) + X[k] + 0x6ED9EBA1U, s);
            else B = RotL32(B + H(C, D, A) + X[k] + 0x6ED9EBA1U, s);
        }

        A += AA; B += BB; C += CC; D += DD;
    }

    std::vector<uint8_t> out;
    AppendU32(out, A);
    AppendU32(out, B);
    AppendU32(out, C);
    AppendU32(out, D);
    return out;
}

// --- RFC 1321 MD5 ---
std::vector<uint8_t> ComputeMd5(const uint8_t* input, size_t len) {
    static constexpr uint32_t K[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    };
    static constexpr uint32_t S[64] = {
        7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
        5,9,14,20,  5,9,14,20,  5,9,14,20,  5,9,14,20,
        4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
        6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
    };

    std::vector<uint8_t> msg(input, input + len);
    uint64_t bitLen = static_cast<uint64_t>(len) * 8ULL;
    msg.push_back(0x80);
    while ((msg.size() % 64) != 56) {
        msg.push_back(0x00);
    }
    AppendU64(msg, bitLen);

    uint32_t a0 = 0x67452301U;
    uint32_t b0 = 0xEFCDAB89U;
    uint32_t c0 = 0x98BADCFEU;
    uint32_t d0 = 0x10325476U;

    for (size_t off = 0; off < msg.size(); off += 64) {
        uint32_t M[16];
        for (int i = 0; i < 16; ++i) M[i] = GetU32(&msg[off + i * 4]);
        uint32_t A = a0, B = b0, C = c0, D = d0;
        for (int i = 0; i < 64; ++i) {
            uint32_t F = 0, g = 0;
            if (i < 16) {
                F = (B & C) | ((~B) & D);
                g = static_cast<uint32_t>(i);
            } else if (i < 32) {
                F = (D & B) | ((~D) & C);
                g = static_cast<uint32_t>((5 * i + 1) % 16);
            } else if (i < 48) {
                F = B ^ C ^ D;
                g = static_cast<uint32_t>((3 * i + 5) % 16);
            } else {
                F = C ^ (B | (~D));
                g = static_cast<uint32_t>((7 * i) % 16);
            }
            uint32_t dTemp = D;
            D = C;
            C = B;
            B = B + RotL32(A + F + K[i] + M[g], S[i]);
            A = dTemp;
        }
        a0 += A; b0 += B; c0 += C; d0 += D;
    }

    std::vector<uint8_t> out;
    AppendU32(out, a0);
    AppendU32(out, b0);
    AppendU32(out, c0);
    AppendU32(out, d0);
    return out;
}

std::vector<uint8_t> ComputeHmacMd5(const std::vector<uint8_t>& key, const std::vector<uint8_t>& data) {
    std::vector<uint8_t> k = key;
    if (k.size() > 64) {
        k = ComputeMd5(k.data(), k.size());
    }
    k.resize(64, 0x00);

    std::vector<uint8_t> inner(64 + data.size());
    for (int i = 0; i < 64; ++i) inner[i] = k[i] ^ 0x36;
    if (!data.empty()) std::memcpy(inner.data() + 64, data.data(), data.size());
    auto innerHash = ComputeMd5(inner.data(), inner.size());

    std::vector<uint8_t> outer(64 + innerHash.size());
    for (int i = 0; i < 64; ++i) outer[i] = k[i] ^ 0x5C;
    std::memcpy(outer.data() + 64, innerHash.data(), innerHash.size());
    return ComputeMd5(outer.data(), outer.size());
}

// --- UTF-8 <-> UTF-16LE ---
std::vector<uint8_t> Utf8ToUtf16Le(const std::string& utf8) {
    std::vector<uint8_t> out;
    out.reserve(utf8.size() * 2);
    size_t i = 0;
    while (i < utf8.size()) {
        uint32_t cp = 0;
        uint8_t b = static_cast<uint8_t>(utf8[i]);
        if (b < 0x80) {
            cp = b;
            ++i;
        } else if ((b & 0xE0) == 0xC0 && i + 1 < utf8.size()) {
            cp = ((b & 0x1F) << 6) | (static_cast<uint8_t>(utf8[i + 1]) & 0x3F);
            i += 2;
        } else if ((b & 0xF0) == 0xE0 && i + 2 < utf8.size()) {
            cp = ((b & 0x0F) << 12) |
                 ((static_cast<uint8_t>(utf8[i + 1]) & 0x3F) << 6) |
                 (static_cast<uint8_t>(utf8[i + 2]) & 0x3F);
            i += 3;
        } else if ((b & 0xF8) == 0xF0 && i + 3 < utf8.size()) {
            cp = ((b & 0x07) << 18) |
                 ((static_cast<uint8_t>(utf8[i + 1]) & 0x3F) << 12) |
                 ((static_cast<uint8_t>(utf8[i + 2]) & 0x3F) << 6) |
                 (static_cast<uint8_t>(utf8[i + 3]) & 0x3F);
            i += 4;
        } else {
            cp = '?';
            ++i;
        }

        if (cp <= 0xFFFF) {
            AppendU16(out, static_cast<uint16_t>(cp));
        } else {
            cp -= 0x10000;
            uint16_t hi = static_cast<uint16_t>(0xD800 + (cp >> 10));
            uint16_t lo = static_cast<uint16_t>(0xDC00 + (cp & 0x3FF));
            AppendU16(out, hi);
            AppendU16(out, lo);
        }
    }
    return out;
}

std::string Utf16LeToUtf8(const uint8_t* data, size_t byteLen) {
    std::string out;
    size_t count = byteLen / 2;
    out.reserve(count);
    for (size_t i = 0; i < count; ++i) {
        uint32_t u = GetU16(data + i * 2);
        if (u >= 0xD800 && u <= 0xDBFF && i + 1 < count) {
            uint32_t u2 = GetU16(data + (i + 1) * 2);
            if (u2 >= 0xDC00 && u2 <= 0xDFFF) {
                u = 0x10000 + (((u - 0xD800) << 10) | (u2 - 0xDC00));
                ++i;
            }
        }
        if (u < 0x80) {
            out.push_back(static_cast<char>(u));
        } else if (u < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (u >> 6)));
            out.push_back(static_cast<char>(0x80 | (u & 0x3F)));
        } else if (u < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (u >> 12)));
            out.push_back(static_cast<char>(0x80 | ((u >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (u & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (u >> 18)));
            out.push_back(static_cast<char>(0x80 | ((u >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((u >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (u & 0x3F)));
        }
    }
    return out;
}

std::string ToUpperAscii(std::string s) {
    for (char& c : s) {
        c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
    }
    return s;
}

std::string ToWindowsRelPath(const std::string& posixPath) {
    std::string p = posixPath;
    for (char& c : p) {
        if (c == '/') c = '\\';
    }
    while (!p.empty() && p.front() == '\\') p.erase(p.begin());
    while (!p.empty() && p.back() == '\\') p.pop_back();
    return p;
}

std::string NormalizePosixDir(const std::string& dir) {
    std::string p = dir;
    for (char& c : p) {
        if (c == '\\') c = '/';
    }
    if (p.empty()) return "/";
    if (p.front() != '/') p.insert(p.begin(), '/');
    while (p.size() > 1 && p.back() == '/') p.pop_back();
    return p;
}

// --- ASN.1 DER Length Helper for SPNEGO ---
void AppendAsnLen(std::vector<uint8_t>& out, size_t len) {
    if (len < 0x80) {
        out.push_back(static_cast<uint8_t>(len));
    } else if (len < 0x100) {
        out.push_back(0x81);
        out.push_back(static_cast<uint8_t>(len));
    } else {
        out.push_back(0x82);
        out.push_back(static_cast<uint8_t>((len >> 8) & 0xFF));
        out.push_back(static_cast<uint8_t>(len & 0xFF));
    }
}

std::vector<uint8_t> WrapAsn(uint8_t tag, const std::vector<uint8_t>& content) {
    std::vector<uint8_t> out;
    out.push_back(tag);
    AppendAsnLen(out, content.size());
    out.insert(out.end(), content.begin(), content.end());
    return out;
}

// Wrap NTLMSSP Negotiate token inside GSS-API / SPNEGO NegTokenInit
std::vector<uint8_t> WrapSpnegoNegTokenInit(const std::vector<uint8_t>& ntlmToken) {
    // SPNEGO OID: 1.3.6.1.5.5.2 -> 06 06 2b 06 01 05 05 02
    const std::vector<uint8_t> spnegoOid = {0x06, 0x06, 0x2b, 0x06, 0x01, 0x05, 0x05, 0x02};
    // NTLMSSP OID: 1.3.6.1.4.1.311.2.2.10 -> 06 0a 2b 06 01 04 01 82 37 02 02 0a
    const std::vector<uint8_t> ntlmOid = {0x06, 0x0a, 0x2b, 0x06, 0x01, 0x04, 0x01, 0x82, 0x37, 0x02, 0x02, 0x0a};

    auto mechList = WrapAsn(0x30, ntlmOid);
    auto mechTypes = WrapAsn(0xA0, mechList);
    auto mechToken = WrapAsn(0xA2, WrapAsn(0x04, ntlmToken));

    std::vector<uint8_t> negSeqContent;
    negSeqContent.insert(negSeqContent.end(), mechTypes.begin(), mechTypes.end());
    negSeqContent.insert(negSeqContent.end(), mechToken.begin(), mechToken.end());
    auto negTokenInit = WrapAsn(0xA0, WrapAsn(0x30, negSeqContent));

    std::vector<uint8_t> appContent;
    appContent.insert(appContent.end(), spnegoOid.begin(), spnegoOid.end());
    appContent.insert(appContent.end(), negTokenInit.begin(), negTokenInit.end());
    return WrapAsn(0x60, appContent);
}

// Wrap NTLMSSP Authenticate token inside SPNEGO NegTokenResp
std::vector<uint8_t> WrapSpnegoNegTokenResp(const std::vector<uint8_t>& ntlmToken) {
    auto responseToken = WrapAsn(0xA2, WrapAsn(0x04, ntlmToken));
    return WrapAsn(0xA1, WrapAsn(0x30, responseToken));
}

bool RecvAll(int fd, uint8_t* buf, size_t len) {
    size_t got = 0;
    while (got < len) {
        ssize_t n = recv(fd, buf + got, len - got, 0);
        if (n <= 0) return false;
        got += static_cast<size_t>(n);
    }
    return true;
}

bool SendAll(int fd, const uint8_t* buf, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, buf + sent, len - sent, MSG_NOSIGNAL);
        if (n <= 0) return false;
        sent += static_cast<size_t>(n);
    }
    return true;
}

int ConnectWithTimeout(const std::string& host, int port, int timeoutSec, std::string& errOut) {
    struct addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo* res = nullptr;
    std::string portStr = std::to_string(port > 0 ? port : 445);
    int gai = getaddrinfo(host.c_str(), portStr.c_str(), &hints, &res);
    if (gai != 0 || !res) {
        errOut = "无法解析 SMB 主机地址: " + host;
        return -1;
    }

    int fd = -1;
    for (struct addrinfo* rp = res; rp != nullptr; rp = rp->ai_next) {
        fd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (fd < 0) continue;

        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);

        int rc = connect(fd, rp->ai_addr, rp->ai_addrlen);
        if (rc < 0 && errno != EINPROGRESS) {
            close(fd);
            fd = -1;
            continue;
        }
        if (rc != 0) {
            fd_set wfds;
            FD_ZERO(&wfds);
            FD_SET(fd, &wfds);
            struct timeval tv{timeoutSec, 0};
            if (select(fd + 1, nullptr, &wfds, nullptr, &tv) <= 0) {
                close(fd);
                fd = -1;
                continue;
            }
            int soErr = 0;
            socklen_t sl = sizeof(soErr);
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &sl);
            if (soErr != 0) {
                close(fd);
                fd = -1;
                continue;
            }
        }
        fcntl(fd, F_SETFL, flags & ~O_NONBLOCK);
        break;
    }
    freeaddrinfo(res);

    if (fd < 0) {
        errOut = "无法连接 SMB 端口 " + host + ":" + portStr;
        return -1;
    }

    struct timeval tv{12, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    int nodelay = 1;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &nodelay, sizeof(nodelay));
    return fd;
}

std::string HexStatus(uint32_t st) {
    char buf[16];
    std::snprintf(buf, sizeof(buf), "0x%08X", st);
    return std::string(buf);
}

int64_t FiletimeToUnixMs(uint64_t ft) {
    // Windows FILETIME ticks (100ns since 1601-01-01) -> Unix ms
    static constexpr uint64_t EPOCH_DIFF = 116444736000000000ULL;
    if (ft <= EPOCH_DIFF) return 0;
    return static_cast<int64_t>((ft - EPOCH_DIFF) / 10000ULL);
}

} // namespace

// --- URL Parser ---
bool ParseSmbUrl(const std::string& url,
                 std::string& outHost,
                 int& outPort,
                 std::string& outShare,
                 std::string& outRelPath,
                 std::string& outUser,
                 std::string& outPass) {
    outHost.clear();
    outPort = 445;
    outShare.clear();
    outRelPath = "/";
    outUser.clear();
    outPass.clear();

    if (url.rfind("smb://", 0) != 0 && url.rfind("SMB://", 0) != 0) {
        return false;
    }
    std::string rest = url.substr(6);
    size_t slashPos = rest.find('/');
    std::string authority = (slashPos == std::string::npos) ? rest : rest.substr(0, slashPos);
    std::string pathPart = (slashPos == std::string::npos) ? "" : rest.substr(slashPos + 1);

    size_t atPos = authority.rfind('@');
    std::string hostPort = authority;
    if (atPos != std::string::npos) {
        std::string userInfo = authority.substr(0, atPos);
        hostPort = authority.substr(atPos + 1);
        size_t colonPos = userInfo.find(':');
        if (colonPos != std::string::npos) {
            outUser = userInfo.substr(0, colonPos);
            outPass = userInfo.substr(colonPos + 1);
        } else {
            outUser = userInfo;
        }
    }

    if (!hostPort.empty() && hostPort.front() == '[') {
        size_t closeBr = hostPort.find(']');
        if (closeBr == std::string::npos) return false;
        outHost = hostPort.substr(1, closeBr - 1);
        if (closeBr + 1 < hostPort.size() && hostPort[closeBr + 1] == ':') {
            outPort = std::atoi(hostPort.substr(closeBr + 2).c_str());
        }
    } else {
        size_t colon = hostPort.rfind(':');
        if (colon != std::string::npos) {
            outHost = hostPort.substr(0, colon);
            outPort = std::atoi(hostPort.substr(colon + 1).c_str());
        } else {
            outHost = hostPort;
        }
    }
    if (outPort <= 0) outPort = 445;

    while (!pathPart.empty() && pathPart.front() == '/') pathPart.erase(pathPart.begin());
    if (!pathPart.empty()) {
        size_t nextSlash = pathPart.find('/');
        if (nextSlash == std::string::npos) {
            outShare = pathPart;
            outRelPath = "/";
        } else {
            outShare = pathPart.substr(0, nextSlash);
            outRelPath = pathPart.substr(nextSlash);
            if (outRelPath.empty()) outRelPath = "/";
        }
    }
    return !outHost.empty();
}

// --- Smb2Session ---
Smb2Session::~Smb2Session() {
    Disconnect();
}

void Smb2Session::Disconnect() {
    if (sockFd_ >= 0) {
        // 优雅关闭：先 TREE_DISCONNECT 再 LOGOFF。只 close 的话服务端会把这个会话
        // 挂到自身超时才回收；反复重连（重启、读失败重试）会堆积僵尸会话，
        // 表现为连接越来越慢，最终直接失败。
        auto bestEffort = [this](uint16_t command, uint32_t treeId) {
            std::vector<uint8_t> body(4, 0);
            PutU16(body, 0, 4);  // StructureSize
            uint32_t st = 0;
            std::vector<uint8_t> hdr, resp;
            std::string err;
            SendSmb2Packet(command, 1, treeId, body, st, hdr, resp, err);
        };
        if (treeConnected_ && treeId_ != 0) bestEffort(0x0004, treeId_);  // TREE_DISCONNECT
        if (sessionId_ != 0) bestEffort(0x0002, 0);                       // LOGOFF
        close(sockFd_);
        sockFd_ = -1;
    }
    messageId_ = 0;
    sessionId_ = 0;
    treeId_ = 0;
    treeConnected_ = false;
}

bool Smb2Session::SendSmb2Packet(uint16_t command,
                                 uint16_t creditCharge,
                                 uint32_t treeId,
                                 const std::vector<uint8_t>& body,
                                 uint32_t& outStatus,
                                 std::vector<uint8_t>& outHeader,
                                 std::vector<uint8_t>& outBody,
                                 std::string& errOut) {
    if (sockFd_ < 0) {
        errOut = "SMB TCP 未连接";
        return false;
    }

    std::vector<uint8_t> pkt(4 + 64 + body.size(), 0);
    uint32_t smbLen = static_cast<uint32_t>(64 + body.size());
    pkt[0] = 0x00;
    pkt[1] = static_cast<uint8_t>((smbLen >> 16) & 0xFF);
    pkt[2] = static_cast<uint8_t>((smbLen >> 8) & 0xFF);
    pkt[3] = static_cast<uint8_t>(smbLen & 0xFF);

    // 64-byte SMB2 Header at offset 4
    pkt[4] = 0xFE; pkt[5] = 'S'; pkt[6] = 'M'; pkt[7] = 'B';
    PutU16(pkt, 4 + 4, 64);                 // StructureSize
    PutU16(pkt, 4 + 6, creditCharge);       // CreditCharge
    PutU16(pkt, 4 + 12, command);           // Command
    PutU16(pkt, 4 + 14, 32);                // Credits requested
    PutU64(pkt, 4 + 24, messageId_++);      // MessageId
    PutU32(pkt, 4 + 36, treeId);            // TreeId
    PutU64(pkt, 4 + 40, sessionId_);        // SessionId

    if (!body.empty()) {
        std::memcpy(pkt.data() + 4 + 64, body.data(), body.size());
    }

    if (!SendAll(sockFd_, pkt.data(), pkt.size())) {
        errOut = "SMB 请求发送失败（连接中断）";
        return false;
    }

    uint8_t nb[4] = {0};
    if (!RecvAll(sockFd_, nb, 4)) {
        errOut = "SMB 响应读取超时或断开";
        return false;
    }
    uint32_t respLen = (static_cast<uint32_t>(nb[1]) << 16) |
                       (static_cast<uint32_t>(nb[2]) << 8) |
                       static_cast<uint32_t>(nb[3]);
    if (respLen < 64 || respLen > 16 * 1024 * 1024) {
        errOut = "非法 SMB2 响应帧长度";
        return false;
    }

    std::vector<uint8_t> resp(respLen);
    if (!RecvAll(sockFd_, resp.data(), respLen)) {
        errOut = "SMB 响应体接收不完整";
        return false;
    }

    if (resp[0] != 0xFE || resp[1] != 'S' || resp[2] != 'M' || resp[3] != 'B') {
        errOut = "服务端未返回标准 SMB2 协议头";
        return false;
    }

    outStatus = GetU32(resp.data() + 8);
    // Keep skipping async interim STATUS_PENDING if any
    while (outStatus == 0x00000103U && (GetU32(resp.data() + 16) & 0x00000002U) != 0) {
        if (!RecvAll(sockFd_, nb, 4)) {
            errOut = "SMB 异步响应接收失败";
            return false;
        }
        respLen = (static_cast<uint32_t>(nb[1]) << 16) |
                  (static_cast<uint32_t>(nb[2]) << 8) |
                  static_cast<uint32_t>(nb[3]);
        if (respLen < 64 || respLen > 16 * 1024 * 1024) {
            errOut = "非法 SMB2 异步响应帧";
            return false;
        }
        resp.resize(respLen);
        if (!RecvAll(sockFd_, resp.data(), respLen)) {
            errOut = "SMB 异步响应体接收不完整";
            return false;
        }
        outStatus = GetU32(resp.data() + 8);
    }

    outHeader.assign(resp.begin(), resp.begin() + 64);
    outBody.assign(resp.begin() + 64, resp.end());
    return true;
}

bool Smb2Session::Connect(const SmbConnectionConfig& config, std::string& errOut) {
    Disconnect();
    if (config.host.empty()) {
        errOut = "SMB 主机地址不能为空";
        return false;
    }
    if (config.share.empty()) {
        errOut = "请指定 SMB 共享名（如 homes / Download / Public）";
        return false;
    }

    sockFd_ = ConnectWithTimeout(config.host, config.port, 8, errOut);
    if (sockFd_ < 0) return false;

    if (!DoNegotiate(errOut)) {
        Disconnect();
        return false;
    }
    if (!DoSessionSetup(config, errOut)) {
        Disconnect();
        return false;
    }
    if (!DoTreeConnect(config, errOut)) {
        Disconnect();
        return false;
    }
    treeConnected_ = true;
    return true;
}

bool Smb2Session::DoNegotiate(std::string& errOut) {
    // SMB2 NEGOTIATE request (36 bytes fixed + dialects)
    std::vector<uint8_t> body(36 + 6, 0);
    PutU16(body, 0, 36);                 // StructureSize
    PutU16(body, 2, 3);                  // DialectCount = 3
    PutU16(body, 4, 0x01);               // SecurityMode: signing enabled
    PutU32(body, 8, 0x00000004U);        // Capabilities: LARGE_MTU
    // ClientGuid bytes 12..27
    for (int i = 0; i < 16; ++i) body[12 + i] = static_cast<uint8_t>(0x3A + i);
    PutU16(body, 36, 0x0202);
    PutU16(body, 38, 0x0210);
    PutU16(body, 40, 0x0300);

    uint32_t st = 0;
    std::vector<uint8_t> hdr, respBody;
    if (!SendSmb2Packet(0x0000, 1, 0, body, st, hdr, respBody, errOut)) return false;
    if (st != 0) {
        errOut = "SMB2 Negotiate 失败 (" + HexStatus(st) + ")";
        return false;
    }
    if (respBody.size() >= 40) {
        uint32_t serverMaxRead = GetU32(respBody.data() + 32);
        if (serverMaxRead >= 65536) {
            // 每次 READ 的固定开销远大于传输本身（实测 512KB/读 ≈300ms），
            // 上限从 512KB 提到 1MB：信用计费 16，仍在请求的 32 之内。
            maxReadSize_ = std::min<uint32_t>(serverMaxRead, 1048576U);
        }
    }
    return true;
}

bool Smb2Session::DoSessionSetup(const SmbConnectionConfig& config, std::string& errOut) {
    // Step 1: NTLMSSP Type 1 Negotiate Message
    std::vector<uint8_t> type1(32, 0);
    std::memcpy(type1.data(), "NTLMSSP\0", 8);
    PutU32(type1, 8, 1); // MessageType = NtLmNegotiate
    // Flags: UNICODE | OEM | REQUEST_TARGET | NTLM | ALWAYS_SIGN | EXTENDED_SESSIONSECURITY | 128 | 56
    PutU32(type1, 12, 0xA0088207U);

    auto secBlob1 = WrapSpnegoNegTokenInit(type1);
    std::vector<uint8_t> req1(24 + secBlob1.size(), 0);
    PutU16(req1, 0, 25);                                    // StructureSize
    req1[3] = 0x01;                                         // SecurityMode
    PutU16(req1, 12, static_cast<uint16_t>(64 + 24));       // SecurityBufferOffset
    PutU16(req1, 14, static_cast<uint16_t>(secBlob1.size()));
    std::memcpy(req1.data() + 24, secBlob1.data(), secBlob1.size());

    uint32_t st1 = 0;
    std::vector<uint8_t> hdr1, resp1;
    if (!SendSmb2Packet(0x0001, 1, 0, req1, st1, hdr1, resp1, errOut)) return false;
    sessionId_ = GetU64(hdr1.data() + 40);

    if (st1 == 0) {
        // Server accepted session immediately (anonymous/guest)
        return true;
    }
    if (st1 != 0xC0000016U) { // STATUS_MORE_PROCESSING_REQUIRED
        errOut = "SMB2 SessionSetup Step 1 失败 (" + HexStatus(st1) + ")";
        return false;
    }

    // Locate NTLMSSP\0 Challenge inside resp1
    static const uint8_t sig[8] = {'N','T','L','M','S','S','P',0};
    auto it = std::search(resp1.begin(), resp1.end(), sig, sig + 8);
    if (it == resp1.end() || static_cast<size_t>(resp1.end() - it) < 48) {
        errOut = "SMB2 未收到 NTLM Challenge 载荷";
        return false;
    }
    const uint8_t* ch = &(*it);
    size_t chLen = static_cast<size_t>(resp1.end() - it);
    if (GetU32(ch + 8) != 2) {
        errOut = "无效 NTLM Challenge 类型";
        return false;
    }

    uint8_t serverChallenge[8];
    std::memcpy(serverChallenge, ch + 24, 8);

    std::vector<uint8_t> targetInfo;
    uint16_t tiLen = GetU16(ch + 40);
    uint32_t tiOff = GetU32(ch + 44);
    if (tiLen > 0 && tiOff + tiLen <= chLen) {
        targetInfo.assign(ch + tiOff, ch + tiOff + tiLen);
    }

    // Parse domain\username if provided
    std::string user = config.username;
    std::string domain = config.domain;
    size_t bs = user.find('\\');
    if (bs != std::string::npos) {
        domain = user.substr(0, bs);
        user = user.substr(bs + 1);
    }

    std::vector<uint8_t> ntResponse;
    std::vector<uint8_t> lmResponse(24, 0);

    if (!user.empty()) {
        // Compute NTLMv2 Response
        auto passUtf16 = Utf8ToUtf16Le(config.password);
        auto ntHash = ComputeMd4(passUtf16.data(), passUtf16.size());

        std::string userDomStr = ToUpperAscii(user) + domain;
        auto userDomUtf16 = Utf8ToUtf16Le(userDomStr);
        auto responseKeyNt = ComputeHmacMd5(ntHash, userDomUtf16);

        uint64_t nowMs = static_cast<uint64_t>(
            std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()).count());
        uint64_t fileTime = nowMs * 10000ULL + 116444736000000000ULL;

        std::random_device rd;
        uint8_t clientChallenge[8];
        for (int i = 0; i < 8; ++i) clientChallenge[i] = static_cast<uint8_t>(rd() & 0xFF);

        // NTLMv2_CLIENT_CHALLENGE
        std::vector<uint8_t> temp;
        temp.push_back(0x01); // RespType
        temp.push_back(0x01); // HiRespType
        temp.resize(8, 0);    // Reserved1 + Reserved2 (6 bytes)
        AppendU64(temp, fileTime);
        temp.insert(temp.end(), clientChallenge, clientChallenge + 8);
        AppendU32(temp, 0);   // Reserved3
        if (!targetInfo.empty()) {
            temp.insert(temp.end(), targetInfo.begin(), targetInfo.end());
        } else {
            AppendU32(temp, 0); // EOL AV_PAIR
        }

        std::vector<uint8_t> proofInput;
        proofInput.insert(proofInput.end(), serverChallenge, serverChallenge + 8);
        proofInput.insert(proofInput.end(), temp.begin(), temp.end());
        auto ntProofStr = ComputeHmacMd5(responseKeyNt, proofInput);

        ntResponse.reserve(ntProofStr.size() + temp.size());
        ntResponse.insert(ntResponse.end(), ntProofStr.begin(), ntProofStr.end());
        ntResponse.insert(ntResponse.end(), temp.begin(), temp.end());
    } else {
        lmResponse.clear();
    }

    auto domUtf16 = Utf8ToUtf16Le(domain);
    auto usrUtf16 = Utf8ToUtf16Le(user);
    auto wksUtf16 = Utf8ToUtf16Le("PRISM");

    uint32_t payloadOffset = 64;
    std::vector<uint8_t> type3(64, 0);
    std::memcpy(type3.data(), "NTLMSSP\0", 8);
    PutU32(type3, 8, 3); // AUTHENTICATE_MESSAGE
    PutU32(type3, 60, 0xA0088205U); // NegotiateFlags

    auto appendField = [&](size_t fieldOff, const std::vector<uint8_t>& bytes) {
        PutU16(type3, fieldOff, static_cast<uint16_t>(bytes.size()));
        PutU16(type3, fieldOff + 2, static_cast<uint16_t>(bytes.size()));
        PutU32(type3, fieldOff + 4, payloadOffset);
        if (!bytes.empty()) {
            type3.insert(type3.end(), bytes.begin(), bytes.end());
            payloadOffset += static_cast<uint32_t>(bytes.size());
        }
    };

    appendField(12, lmResponse);
    appendField(20, ntResponse);
    appendField(28, domUtf16);
    appendField(36, usrUtf16);
    appendField(44, wksUtf16);
    // EncryptedRandomSessionKey (52) left empty
    PutU16(type3, 52, 0); PutU16(type3, 54, 0); PutU32(type3, 56, payloadOffset);

    auto secBlob2 = WrapSpnegoNegTokenResp(type3);
    std::vector<uint8_t> req2(24 + secBlob2.size(), 0);
    PutU16(req2, 0, 25);
    req2[3] = 0x01;
    PutU16(req2, 12, static_cast<uint16_t>(64 + 24));
    PutU16(req2, 14, static_cast<uint16_t>(secBlob2.size()));
    std::memcpy(req2.data() + 24, secBlob2.data(), secBlob2.size());

    uint32_t st2 = 0;
    std::vector<uint8_t> hdr2, resp2;
    if (!SendSmb2Packet(0x0001, 1, 0, req2, st2, hdr2, resp2, errOut)) return false;
    if (st2 == 0xC000006DU || st2 == 0xC000006AU || st2 == 0xC0000064U) {
        errOut = "SMB 账号或密码错误 (STATUS_LOGON_FAILURE)";
        return false;
    }
    if (st2 != 0) {
        errOut = "SMB 身份验证失败 (" + HexStatus(st2) + ")";
        return false;
    }
    sessionId_ = GetU64(hdr2.data() + 40);
    return true;
}

bool Smb2Session::DoTreeConnect(const SmbConnectionConfig& config, std::string& errOut) {
    std::string unc = "\\\\" + config.host + "\\" + config.share;
    auto uncUtf16 = Utf8ToUtf16Le(unc);

    // SMB2 TREE_CONNECT (8 bytes fixed + path)
    std::vector<uint8_t> req(8 + uncUtf16.size(), 0);
    PutU16(req, 0, 9);                                      // StructureSize
    PutU16(req, 4, static_cast<uint16_t>(64 + 8));          // PathOffset
    PutU16(req, 6, static_cast<uint16_t>(uncUtf16.size())); // PathLength
    std::memcpy(req.data() + 8, uncUtf16.data(), uncUtf16.size());

    uint32_t st = 0;
    std::vector<uint8_t> hdr, resp;
    if (!SendSmb2Packet(0x0003, 1, 0, req, st, hdr, resp, errOut)) return false;
    if (st == 0xC00000CCU) {
        errOut = "SMB 共享名「" + config.share + "」不存在";
        return false;
    }
    if (st == 0xC0000022U) {
        errOut = "当前账号无权访问共享目录「" + config.share + "」";
        return false;
    }
    if (st != 0) {
        errOut = "SMB TreeConnect 失败 (" + HexStatus(st) + ")";
        return false;
    }
    treeId_ = GetU32(hdr.data() + 36);
    return true;
}

SmbListResult Smb2Session::ListDirectory(const std::string& shareRelDir) {
    SmbListResult out;
    if (!IsConnected()) {
        out.error = "SMB 会话尚未建立";
        return out;
    }

    std::string posixDir = NormalizePosixDir(shareRelDir);
    std::string winPath = ToWindowsRelPath(posixDir);
    auto pathUtf16 = Utf8ToUtf16Le(winPath);

    // SMB2 CREATE for directory (56 bytes fixed + aligned name >= 1)
    size_t nameLen = pathUtf16.size();
    std::vector<uint8_t> createReq(56 + (nameLen > 0 ? nameLen : 2), 0);
    PutU16(createReq, 0, 57);                               // StructureSize
    createReq[3] = 0x00;                                    // OplockLevel = NONE
    PutU32(createReq, 4, 0x00000002U);                      // ImpersonationLevel = Impersonation
    PutU32(createReq, 24, 0x00100081U);                     // DesiredAccess: LIST_DIR | READ_ATTR | SYNC
    PutU32(createReq, 28, 0x00000010U);                     // FileAttributes: DIRECTORY
    PutU32(createReq, 32, 0x00000007U);                     // ShareAccess: R | W | D
    PutU32(createReq, 36, 0x00000001U);                     // CreateDisposition: FILE_OPEN
    PutU32(createReq, 40, 0x00000001U);                     // CreateOptions: FILE_DIRECTORY_FILE
    PutU16(createReq, 44, static_cast<uint16_t>(64 + 56));  // NameOffset
    PutU16(createReq, 46, static_cast<uint16_t>(nameLen));  // NameLength
    if (nameLen > 0) {
        std::memcpy(createReq.data() + 56, pathUtf16.data(), nameLen);
    }

    uint32_t stCreate = 0;
    std::vector<uint8_t> hdrC, respC;
    if (!SendSmb2Packet(0x0005, 1, treeId_, createReq, stCreate, hdrC, respC, out.error)) {
        return out;
    }
    if (stCreate == 0xC0000034U || stCreate == 0xC000003AU) {
        out.error = "SMB 目录不存在: " + posixDir;
        return out;
    }
    if (stCreate == 0xC0000022U) {
        out.error = "无权访问 SMB 目录: " + posixDir;
        return out;
    }
    if (stCreate != 0 || respC.size() < 80) {
        out.error = "打开 SMB 目录失败 (" + HexStatus(stCreate) + ")";
        return out;
    }

    uint8_t dirFileId[16];
    std::memcpy(dirFileId, respC.data() + 64, 16);

    auto starUtf16 = Utf8ToUtf16Le("*");
    bool restartScan = true;
    while (true) {
        // SMB2 QUERY_DIRECTORY (32 bytes fixed + search pattern)
        std::vector<uint8_t> qReq(32 + starUtf16.size(), 0);
        PutU16(qReq, 0, 33);                                    // StructureSize
        qReq[2] = 0x25;                                         // FileIdBothDirectoryInformation
        qReq[3] = restartScan ? 0x01 : 0x00;                    // Flags: RESTART_SCANS on first pass
        restartScan = false;
        std::memcpy(qReq.data() + 8, dirFileId, 16);
        PutU16(qReq, 24, static_cast<uint16_t>(64 + 32));       // FileNameOffset
        PutU16(qReq, 26, static_cast<uint16_t>(starUtf16.size()));
        PutU32(qReq, 28, 65536U);                               // OutputBufferLength
        std::memcpy(qReq.data() + 32, starUtf16.data(), starUtf16.size());

        uint32_t stQ = 0;
        std::vector<uint8_t> hdrQ, respQ;
        if (!SendSmb2Packet(0x000E, 1, treeId_, qReq, stQ, hdrQ, respQ, out.error)) {
            CloseFile(dirFileId);
            return out;
        }
        if (stQ == 0x80000006U) { // STATUS_NO_MORE_FILES
            break;
        }
        if (stQ != 0 || respQ.size() < 8) {
            out.error = "读取 SMB 目录失败 (" + HexStatus(stQ) + ")";
            CloseFile(dirFileId);
            return out;
        }

        uint16_t outOff = GetU16(respQ.data() + 2);
        uint32_t outLen = GetU32(respQ.data() + 4);
        size_t relOff = (outOff >= 64) ? static_cast<size_t>(outOff - 64) : 8;
        if (relOff + outLen > respQ.size()) {
            outLen = static_cast<uint32_t>(respQ.size() > relOff ? respQ.size() - relOff : 0);
        }

        size_t pos = relOff;
        while (pos + 104 <= relOff + outLen) {
            const uint8_t* e = respQ.data() + pos;
            uint32_t nextOff = GetU32(e + 0);
            uint64_t lastWrite = GetU64(e + 24);
            int64_t endOfFile = static_cast<int64_t>(GetU64(e + 40));
            uint32_t attrs = GetU32(e + 56);
            uint32_t fnLen = GetU32(e + 60);

            if (pos + 104 + fnLen <= relOff + outLen && fnLen > 0) {
                std::string name = Utf16LeToUtf8(e + 104, fnLen);
                if (name != "." && name != ".." && name != ".@__thumb" && name != ".DS_Store" && name.rfind("._", 0) != 0) {
                    SmbFileEntry entry;
                    entry.name = name;
                    entry.isDirectory = (attrs & 0x00000010U) != 0;
                    entry.size = entry.isDirectory ? 0 : endOfFile;
                    entry.lastModifiedMs = FiletimeToUnixMs(lastWrite);
                    entry.path = (posixDir == "/") ? ("/" + name) : (posixDir + "/" + name);
                    out.entries.push_back(std::move(entry));
                }
            }
            if (nextOff == 0) break;
            pos += nextOff;
        }
    }

    CloseFile(dirFileId);
    out.ok = true;
    return out;
}

bool Smb2Session::OpenFile(const std::string& shareRelPath, uint8_t outFileId[16], int64_t& outFileSize, std::string& errOut) {
    if (!IsConnected()) {
        errOut = "SMB 会话尚未建立";
        return false;
    }
    std::string winPath = ToWindowsRelPath(shareRelPath);
    auto pathUtf16 = Utf8ToUtf16Le(winPath);
    if (pathUtf16.empty()) {
        errOut = "SMB 文件路径为空";
        return false;
    }

    std::vector<uint8_t> createReq(56 + pathUtf16.size(), 0);
    PutU16(createReq, 0, 57);
    PutU32(createReq, 4, 0x00000002U);                      // Impersonation
    PutU32(createReq, 24, 0x00120089U);                     // FILE_READ_DATA | FILE_READ_ATTRIBUTES | SYNCHRONIZE
    PutU32(createReq, 28, 0x00000080U);                     // Normal file
    PutU32(createReq, 32, 0x00000007U);                     // Share R | W | D
    PutU32(createReq, 36, 0x00000001U);                     // FILE_OPEN
    PutU32(createReq, 40, 0x00000040U);                     // FILE_NON_DIRECTORY_FILE
    PutU16(createReq, 44, static_cast<uint16_t>(64 + 56));
    PutU16(createReq, 46, static_cast<uint16_t>(pathUtf16.size()));
    std::memcpy(createReq.data() + 56, pathUtf16.data(), pathUtf16.size());

    uint32_t st = 0;
    std::vector<uint8_t> hdr, resp;
    if (!SendSmb2Packet(0x0005, 1, treeId_, createReq, st, hdr, resp, errOut)) return false;
    if (st != 0 || resp.size() < 80) {
        errOut = "无法打开 SMB 文件 (" + HexStatus(st) + ")";
        return false;
    }
    outFileSize = static_cast<int64_t>(GetU64(resp.data() + 48));
    std::memcpy(outFileId, resp.data() + 64, 16);
    return true;
}

bool Smb2Session::ReadFile(const uint8_t fileId[16], int64_t offset, uint32_t length, std::vector<uint8_t>& outData, std::string& errOut) {
    outData.clear();
    if (!IsConnected()) {
        errOut = "SMB 连接已断开";
        return false;
    }

    uint32_t remaining = length;
    int64_t curOff = offset;
    outData.reserve(length);

    while (remaining > 0) {
        uint32_t reqChunk = std::min(remaining, maxReadSize_);
        uint16_t creditsNeeded = static_cast<uint16_t>((reqChunk + 65535U) / 65536U);
        if (creditsNeeded < 1) creditsNeeded = 1;

        // SMB2 READ Request (48 bytes fixed + 1 byte min Buffer)
        std::vector<uint8_t> readReq(49, 0);
        PutU16(readReq, 0, 49);                             // StructureSize
        PutU32(readReq, 4, reqChunk);                       // Length
        PutU64(readReq, 8, static_cast<uint64_t>(curOff));  // Offset
        std::memcpy(readReq.data() + 16, fileId, 16);

        uint32_t st = 0;
        std::vector<uint8_t> hdr, resp;
        if (!SendSmb2Packet(0x0008, creditsNeeded, treeId_, readReq, st, hdr, resp, errOut)) return false;
        if (st == 0xC0000011U) { // STATUS_END_OF_FILE
            break;
        }
        if (st != 0 || resp.size() < 16) {
            errOut = "SMB READ 失败 (" + HexStatus(st) + ")";
            return false;
        }
        uint8_t dataOff = resp[2];
        uint32_t dataLen = GetU32(resp.data() + 4);
        size_t rel = (dataOff >= 64) ? static_cast<size_t>(dataOff - 64) : 16;
        if (dataLen == 0 || rel >= resp.size()) break;
        size_t avail = std::min<size_t>(dataLen, resp.size() - rel);
        outData.insert(outData.end(), resp.data() + rel, resp.data() + rel + avail);
        curOff += static_cast<int64_t>(avail);
        remaining -= static_cast<uint32_t>(avail);
        if (avail < reqChunk) break;
    }
    return true;
}

void Smb2Session::CloseFile(const uint8_t fileId[16]) {
    if (sockFd_ < 0) return;
    std::vector<uint8_t> req(24, 0);
    PutU16(req, 0, 24);
    std::memcpy(req.data() + 8, fileId, 16);
    uint32_t st = 0;
    std::vector<uint8_t> hdr, resp;
    std::string dummyErr;
    SendSmb2Packet(0x0006, 1, treeId_, req, st, hdr, resp, dummyErr);
}

bool Smb2Session::ReadSmallFile(const std::string& shareRelPath, size_t maxBytes, std::vector<uint8_t>& outData, std::string& errOut) {
    uint8_t fid[16] = {0};
    int64_t fileSize = 0;
    if (!OpenFile(shareRelPath, fid, fileSize, errOut)) {
        return false;
    }
    uint32_t toRead = static_cast<uint32_t>(std::min<int64_t>(fileSize, static_cast<int64_t>(maxBytes)));
    bool ok = ReadFile(fid, 0, toRead, outData, errOut);
    CloseFile(fid);
    return ok;
}

} // namespace prism
