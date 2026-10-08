import sys
p = sys.argv[1]
s = open(p).read()
struct = r'''
// H3 audio anti-alias depthwise conv, exactly as LTXV::depthwise_conv1d_direct builds it.
struct test_conv_dw_h3 : public test_case {
    const int64_t W, C; const int K, stride, pad;
    std::string vars() override { return VARS_TO_STR5(W, C, K, stride, pad); }
    test_conv_dw_h3(int64_t W, int64_t C, int K, int stride, int pad) : W(W), C(C), K(K), stride(stride), pad(pad) {}
    ggml_tensor * build_graph(ggml_context * ctx) override {
        ggml_tensor * input  = ggml_new_tensor_4d(ctx, GGML_TYPE_F32, W, 1, C, 1);
        ggml_tensor * kernel = ggml_new_tensor_4d(ctx, GGML_TYPE_F32, K, 1, 1, C);
        ggml_set_name(input, "input"); ggml_set_name(kernel, "kernel");
        ggml_tensor * out = ggml_conv_2d_dw_direct(ctx, kernel, input, stride, 1, pad, 0, 1, 1);
        ggml_set_name(out, "out");
        return out;
    }
};

'''
anchor = "static std::vector<std::unique_ptr<test_case>> make_test_cases_eval() {"
assert s.count(anchor) == 1
body = "\n    std::vector<std::unique_ptr<test_case>> test_cases;\n"
i = s.index(anchor)
j = s.index(body, i)
cases = "".join(
    f"    test_cases.emplace_back(new test_conv_dw_h3({w}, {c}, 12, 1, 11));\n"
    f"    test_cases.emplace_back(new test_conv_dw_h3({w}, {c}, 12, 2, 0));\n"
    for w, c in [(2100, 512), (10420, 256), (20830, 128), (41630, 64), (83230, 32), (166430, 16), (332830, 8), (1331230, 8)])
s = s[:i] + struct + s[i:j + len(body)] + cases + s[j + len(body):]
open(p, "w").write(s)
print("added h3 dw cases")
