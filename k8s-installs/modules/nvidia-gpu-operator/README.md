# nvidia-gpu-operator

NVIDIA's [GPU operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
(chart `v26.7.1`, pinned) in `gpu-operator`. Installed whenever a request picks
a GPU type.

The AL2023 NVIDIA AMIs Karpenter launches already include the driver and the
container toolkit, so those are **off**; the operator adds the device plugin
(`nvidia.com/gpu` resources), GPU feature discovery and the **DCGM exporter**.
grafana-stack's Alloy scrapes the exporter's pods (label
`app=nvidia-dcgm-exporter`) into Mimir, so GPU utilisation, memory and
temperature show up per cluster in Grafana.

`spec`: `chart_version`, `enabled`.
