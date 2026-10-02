// Minimal dependency-free test framework for host-side firmware tests.
#pragma once
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

namespace tf {
struct Case {
    const char* name;
    std::function<void()> fn;
};
inline std::vector<Case>& registry() {
    static std::vector<Case> r;
    return r;
}
inline int& failures() {
    static int f = 0;
    return f;
}
inline int& checks() {
    static int c = 0;
    return c;
}
struct Registrar {
    Registrar(const char* n, std::function<void()> f) { registry().push_back({n, f}); }
};
inline int runAll() {
    int failedCases = 0;
    for (auto& c : registry()) {
        const int before = failures();
        c.fn();
        const bool ok = failures() == before;
        if (!ok) failedCases++;
        std::printf("[%s] %s\n", ok ? " OK " : "FAIL", c.name);
    }
    std::printf("\n%zu cases, %d checks, %d failed checks, %d failed cases\n", registry().size(), checks(), failures(),
                failedCases);
    return failedCases == 0 ? 0 : 1;
}
}  // namespace tf

#define TF_CAT2(a, b) a##b
#define TF_CAT(a, b) TF_CAT2(a, b)
#define TEST(name)                                                         \
    static void TF_CAT(test_, name)();                                     \
    static tf::Registrar TF_CAT(reg_, name)(#name, TF_CAT(test_, name));   \
    static void TF_CAT(test_, name)()

#define CHECK(cond)                                                                       \
    do {                                                                                  \
        tf::checks()++;                                                                   \
        if (!(cond)) {                                                                    \
            tf::failures()++;                                                             \
            std::printf("    check failed: %s (%s:%d)\n", #cond, __FILE__, __LINE__);     \
        }                                                                                 \
    } while (0)

#define CHECK_EQ(a, b)                                                                                   \
    do {                                                                                                 \
        tf::checks()++;                                                                                  \
        auto _va = (a);                                                                                  \
        auto _vb = (b);                                                                                  \
        if (!(_va == _vb)) {                                                                             \
            tf::failures()++;                                                                            \
            std::printf("    check failed: %s == %s (%lld vs %lld) (%s:%d)\n", #a, #b, (long long)_va,   \
                        (long long)_vb, __FILE__, __LINE__);                                             \
        }                                                                                                \
    } while (0)

#define CHECK_NEAR(a, b, tol)                                                                              \
    do {                                                                                                   \
        tf::checks()++;                                                                                    \
        double _va = (a), _vb = (b);                                                                       \
        if (std::fabs(_va - _vb) > (tol)) {                                                                \
            tf::failures()++;                                                                              \
            std::printf("    check failed: %s ~= %s (%f vs %f) (%s:%d)\n", #a, #b, _va, _vb, __FILE__, __LINE__); \
        }                                                                                                  \
    } while (0)
