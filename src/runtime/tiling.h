#ifndef __SD_RUNTIME_TILING_H__
#define __SD_RUNTIME_TILING_H__

#include <functional>

#include "core/tensor.hpp"

using TileProcessCallback = std::function<sd::Tensor<float>(const sd::Tensor<float>&)>;

sd::Tensor<float> process_tiles_2d(const sd::Tensor<float>& input,
                                   int output_width,
                                   int output_height,
                                   int scale,
                                   int p_tile_size_x,
                                   int p_tile_size_y,
                                   float tile_overlap_factor,
                                   bool circular_x,
                                   bool circular_y,
                                   const TileProcessCallback& on_processing,
                                   bool silent = false);

// Returns tile_size, adjusted if needed so a non-circular axis of small_dim is never split into tiles that
// barely overlap (see the definition for why that shows as a seam).
int sd_tiling_seam_safe_tile_size(int small_dim, int tile_size, float tile_overlap_factor);

#endif  // __SD_RUNTIME_TILING_H__
