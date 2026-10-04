#ifndef __SD_BACKEND_FIT_H__
#define __SD_BACKEND_FIT_H__

#include <string>

#include "core/ggml_graph_cut.h"
#include "model_loader.h"
#include "stable-diffusion.h"

namespace sd::backend_fit {

    bool derive_backend_specs(ModelLoader& loader,
                              ggml_type override_wtype,
                              sd::ggml_graph_cut::MaxVramAssignment& budgets,
                              std::string& runtime_spec,
                              std::string& params_spec);

    bool prepare_vae_decode_retry_tiling(sd_tiling_params_t& tiling_params,
                                         bool prefer_temporal_tiling);

    // Turns on (or tightens) VAE tiling after an encode/decode failed, most likely out of memory.
    // Returns false once there is nothing left to try.
    bool prepare_vae_retry_tiling(sd_tiling_params_t& tiling_params,
                                  bool prefer_temporal_tiling,
                                  bool encode);

}  // namespace sd::backend_fit

#endif  // __SD_BACKEND_FIT_H__
