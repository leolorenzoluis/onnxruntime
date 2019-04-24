// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#include "core/providers/cuda/cu_inc/common.cuh"
#include "rnn_impl.h"

namespace onnxruntime {
namespace cuda {

template <typename T>
__global__ void _ReverseBySequenceKernel(const int32_t seq_length,
                                         const int32_t block_size,
                                         const fast_divmod div_batch_block,
                                         const T* data,
                                         T* reversed_data,
                                         const CUDA_LONG N) {
  CALCULATE_ELEMENTWISE_INDEX_OR_EXIT(id, N);
  int seq_id, offset;
  div_batch_block.divmod(id, seq_id, offset);
  int org_id = (seq_length - seq_id - 1) * block_size + offset;
  reversed_data[id] = data[org_id];
}

template <typename T>
void ReverseBySequence(const int32_t seq_length,
                       const int32_t batch_size,
                       const int32_t input_or_hidden_size,
                       const T* data,
                       T* reversed_data,
                       const size_t N) {
  // kerneral
  int32_t block_size = batch_size * input_or_hidden_size;
  fast_divmod div_batch_block(block_size);
  int blocksPerGrid = (int)(ceil(static_cast<float>(N) / GridDim::maxThreadsPerBlock));
  _ReverseBySequenceKernel<T><<<blocksPerGrid, GridDim::maxThreadsPerBlock, 0>>>(
      seq_length, block_size, div_batch_block, data, reversed_data, (CUDA_LONG)N);
}

template <typename T>
__global__ void _BidirectionalDataKernel(const int32_t seq_length,
                                         const int32_t batch_size,
                                         const int32_t hidden_size,
                                         const int32_t seq_block_size,
                                         const fast_divmod div_seq_block,
                                         const fast_divmod div_output_block,
                                         const T* data,
                                         T* reordered_data,
                                         const CUDA_LONG N) {
  CALCULATE_ELEMENTWISE_INDEX_OR_EXIT(id, N);
  int seq_id, seq_offset, output_id, offset;
  div_seq_block.divmod(id, seq_id, seq_offset);
  div_output_block.divmod(seq_offset, output_id, offset);
  int org_output_id = 0;
  if (output_id < batch_size) {
    org_output_id = 2 * output_id;
  } else {
    org_output_id = (output_id - batch_size) * 2 + 1;
  }
  int org_id = seq_id * seq_block_size + org_output_id * hidden_size + offset;
  reordered_data[id] = data[org_id];
}

template <typename T>
void ReorderBidirectionalDataInSequence(const int32_t seq_length,
                                        const int32_t batch_size,
                                        const int32_t hidden_size,
                                        const T* data,
                                        T* reordered_data,
                                        const size_t N) {
  // The cudnn Y output is organize like [Y1, YB1] [Y2, YB2] ... 
  // need to reorganize it to [Y1, Y2, ...] [YB1, YB2, ...]
  int32_t seq_block_size = 2 * batch_size * hidden_size;
  fast_divmod div_seq_block(seq_block_size);
  fast_divmod div_output_block(hidden_size);
  int blocksPerGrid = (int)(ceil(static_cast<float>(N) / GridDim::maxThreadsPerBlock));

  _BidirectionalDataKernel<T><<<blocksPerGrid, GridDim::maxThreadsPerBlock, 0>>>(
      seq_length, batch_size, hidden_size, seq_block_size,
      div_seq_block, div_output_block,
      data, reordered_data, (CUDA_LONG)N);
}

#define SPECIALIZED_RNN_IMPL(T)                                                 \
  template void ReverseBySequence<T>(const int32_t seq_length,                  \
                                     const int32_t batch_size,                  \
                                     const int32_t hidden_size,                 \
                                     const T* data,                             \
                                     T* reversed_data,                          \
                                     const size_t N);                           \
  template void ReorderBidirectionalDataInSequence<T>(const int32_t seq_length, \
                                                      const int32_t batch_size, \
                                                      const int32_t hidden_size,\
                                                      const T* data,            \
                                                      T* reordered_data,        \
                                                     const size_t N);

SPECIALIZED_RNN_IMPL(half)
SPECIALIZED_RNN_IMPL(float)
SPECIALIZED_RNN_IMPL(double)

}  // namespace cuda
}  // namespace onnxruntime
