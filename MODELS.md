| Model                            | Parameters / Size   | CPU (cores / RAM)          | GPU (VRAM)   | CPU Throughput (RTF) | GPU Throughput (RTF) | WER (%) |
| -------------------------------- | ------------------- | -------------------------- | ------------ | -------------------- | -------------------- | ------- |
| **Whisper Large v3**             | ~1.55B (~3 GB FP16) | ~8-core AVX2 / 8–16 GB RAM | ≥6–8 GB      | ~0.3–0.6×            | ~3–6×                | ~5–7%   |
| **Whisper Large v3 Turbo**       | ~1.5B optimized     | ~6–8 cores / 8–16 GB RAM   | ≥6 GB        | ~0.7–1.2×            | ~6–10×               | ~6–8%   |
| **Distil-Whisper Large v3**      | ~0.75B              | ~4–8 cores / 6–12 GB RAM   | ≥4–6 GB      | ~1.2–2×              | ~8–12×               | ~6–9%   |
| **NVIDIA Parakeet TDT**          | ~1B FastConformer   | ~8 cores / 8–16 GB RAM     | ≥6–8 GB      | ~0.5–1×              | ~10–20×              | ~6–7%   |
| **Canary Qwen 2.5B**             | ~2.5B               | impractical / ≥16 GB RAM   | ≥16 GB       | ~0.1–0.2×            | ~2–4×                | ~5–6%   |
| **Moonshine**                    | 27M–61M             | 2–4 cores / 1–2 GB RAM     | not required | ~3–8×                | —                    | ~12–18% |
| **Vosk-model-en-us-0.22-lgraph** | ~130–150 MB model   | 2–4 cores / 1–2 GB RAM     | not required | ~10–30×              | —                    | ~10–15% |
