// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#pragma once

#include <set>
#include <string>
#include "core/common/common.h"
#include "core/common/exceptions.h"
#include "core/framework/op_kernel.h"

namespace onnxruntime {
template <typename T>
class RNN : public OpKernel {
  const std::set<std::string> allowed_activations{"Relu", "Tanh", "Sigmoid", "Affine", "LeakyRelu", "ThresholdedRelu", "ScaledTanh", "HardSigmoid", "Elu", "Softsign", "Softplus"};
  const std::set<std::string> allowed_directions{"forward", "reverse", "bidirectional"};

 public:
  RNN(const OpKernelInfo& info) : OpKernel(info),
                                  clip_(info.GetAttrOrDefault("clip", -1.0f)) {
    ORT_ENFORCE(info.GetAttr("direction", &direction_).IsOK());
    ORT_ENFORCE(allowed_directions.find(direction_) != allowed_directions.end());
    const int num_directions = direction_ == "bidirectional" ? 2 : 1;

    activation_alpha_ = info.GetAttrsOrDefault("activation_alpha", std::vector<float>(num_directions, 0.0F));
    activation_beta_ = info.GetAttrsOrDefault("activation_beta", std::vector<float>(num_directions, 0.0F));
    ORT_ENFORCE(info.GetAttrs("activations", activations_).IsOK());
    //TODO: is it optional or not?
    ORT_ENFORCE(info.GetAttr("hidden_size", &hidden_size_).IsOK());

    if (activations_.size() == 2 && num_directions == 1) {
      // ONNX RNN default activations are {"Tanh", "Tanh"}
      // In this case, take the first default activation.
      activations_.resize(1);
    }

    ORT_ENFORCE(activations_.size() == num_directions);
    for (int direction = 1; direction < num_directions; direction++) {
      ORT_ENFORCE(allowed_activations.find(activations_[direction]) != allowed_activations.end());
    }
  }

  Status Compute(OpKernelContext* context) const override;

 private:
  // optional, default values tied to the activation function
  std::vector<float> activation_alpha_;

  // optional, default values tied to the activation function
  std::vector<float> activation_beta_;

  // optional, default = "Tanh"
  std::vector<std::string> activations_;

  // optional, default no clip_
  float clip_;

  // optional
  std::string direction_;

  // required
  int64_t hidden_size_;

  // const std::string default_activation = "Tanh";
};

}  // namespace onnxruntime
