// CPU-only checks for the existing vendored chat-template C interface.
#include "jinja_wrapper.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>

static bool rendered(const char* source, const char* messages, const char* tools,
                     const char* extra, int prompt, const std::string& expected) {
    size_t length = 999;
    char* result = jinja_render_chat(source, messages, tools, extra, prompt, &length);
    const bool ok = result && length == expected.size() &&
        std::memcmp(result, expected.data(), length) == 0 && jinja_last_error() == nullptr;
    jinja_str_free(result);
    return ok;
}

static bool invalid_json() {
    size_t length = 999;
    char* result = jinja_render_chat("{{ messages }}", "{", nullptr, nullptr, 0, &length);
    const bool ok = result == nullptr && length == 0 &&
        jinja_last_error() != nullptr && std::strlen(jinja_last_error()) != 0;
    jinja_str_free(result);
    return ok;
}

extern "C" int fios_jinja_control() {
    const char* messages = "[{\"role\":\"user\",\"content\":\"hello\"}]";
    if (!rendered("{% for m in messages %}{{m.role}}:{{m.content}}|{% endfor %}"
                  "{% if add_generation_prompt %}assistant:{% endif %}",
                  messages, nullptr, nullptr, 1, "user:hello|assistant:")) return 1;
    if (!rendered("{{bos_token}}{{messages[0].content}}{{eos_token}}", messages,
                  nullptr, "{\"bos_token\":\"<b>\",\"eos_token\":\"<e>\"}", 0,
                  "<b>hello<e>")) return 2;
    if (!rendered("{{tools[0].function.name}}", messages,
                  "[{\"function\":{\"name\":\"lookup\"}}]", nullptr, 0, "lookup")) return 3;
    if (!rendered("{{messages[0].content}}",
                  "[{\"role\":\"user\",\"content\":\"left\\u0000right\"}]",
                  nullptr, nullptr, 0, std::string("left\0right", 10))) return 4;
    if (!invalid_json()) return 5;
    bool child_ok = false;
    std::thread child([&] {
        child_ok = jinja_last_error() == nullptr &&
            rendered("{{messages[0].content}}", messages, nullptr, nullptr, 0, "hello") &&
            invalid_json() &&
            rendered("{{messages[0].content}}", messages, nullptr, nullptr, 0, "hello");
    });
    child.join();
    if (!child_ok || jinja_last_error() == nullptr) return 6;
    if (!rendered("{{messages[0].content}}", messages, nullptr, nullptr, 0, "hello")) return 7;
    std::puts("PASS: byte-exact Jinja render, structured context, NUL, errors and thread-local reset");
    return 0;
}

#ifdef FIOS_JINJA_STANDALONE
int main() { return fios_jinja_control(); }
#endif
