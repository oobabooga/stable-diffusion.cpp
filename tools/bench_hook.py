import sys
p = sys.argv[1]
s = open(p).read()
anchor = "            if (!generate_video(sd_ctx.get(), &vid_gen_params, &generated_video, &num_results, &generated_audio, &cli_params.preview_fps)) {"
assert s.count(anchor) == 1
hook = r'''            if (const char* rep = getenv("SD_BENCH_REPEAT")) {
                const char* dump = getenv("SD_BENCH_DUMP");
                for (int r = 0; r < atoi(rep); ++r) {
                    sd_image_t* v = nullptr; int n = 0; sd_audio_t* a = nullptr; int fps = 0;
                    auto t0 = std::chrono::steady_clock::now();
                    bool ok = generate_video(sd_ctx.get(), &vid_gen_params, &v, &n, &a, &fps);
                    LOG_INFO("BENCH render %d ok=%d total %.3f s", r, ok ? 1 : 0, std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count());
                    if (ok && dump) {
                        std::string base = std::string(dump) + "_r" + std::to_string(r);
                        FILE* f = fopen((base + ".rgb").c_str(), "wb");
                        for (int i = 0; i < n; ++i) fwrite(v[i].data, 1, (size_t)v[i].width * v[i].height * v[i].channel, f);
                        fclose(f);
                        if (a) { f = fopen((base + ".f32").c_str(), "wb"); fwrite(a->data, sizeof(float), a->sample_count * a->channels, f); fclose(f); }
                    }
                    if (v) free_sd_images(v, n);
                    if (a) free_sd_audio(a);
                }
                return 0;
            }
'''
s = s.replace(anchor, hook + anchor).replace("#include <stdio.h>", "#include <stdio.h>\n#include <chrono>", 1)
open(p, "w").write(s)
print("hooked", p)
