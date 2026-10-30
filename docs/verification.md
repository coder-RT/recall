# Verification log

Answers to the checklist in `CLAUDE.md` section 10. Each row gives its source. "✅" means verified from the source;
"⏳" means still to do. Anything not listed here is still unverified.

## 8. MapAnything ✅ (docs, and one real room on the M5 Pro)

Source: `facebookresearch/map-anything` at commit `3d10cf7` (v1.1.4, 2026-08-07), read locally on 2026-10-29.

| Question | Answer | Source | Status |
|---|---|---|---|
| Repo | https://github.com/facebookresearch/map-anything | `git remote -v` | ✅ |
| Code licence | Apache-2.0 | `LICENSE`; README "Code License" | ✅ |
| Weights | `facebook/map-anything` is CC-BY-NC 4.0; **`facebook/map-anything-apache` is Apache 2.0**, same API. **We use `map-anything-apache`.** | README "Models › Hugging Face Hub Models" | ✅ |
| Python and dependencies | `requires-python >=3.10` (README sets up 3.12). torch is **not** pinned: install it for your system. Pinned: `uniception==0.1.7`, `opencv-python-headless==4.10.0.84`, `rerun-sdk~=0.24.1` | `pyproject.toml`; README "Installation" | ✅ |
| Apple GPU (MPS) | `mapanything.utils.device.get_device()` picks CUDA, then MPS, then CPU. On MPS, bf16 is reported unsupported, so AMP falls back to another dtype. Memory-based minibatch sizing is CUDA-only, so a conservative default is used. xformers is an optional, guarded import. The README snippets pick only `cuda`/`cpu`, so our adapter calls `get_device()`. | `mapanything/utils/device.py`; `mapanything/models/mapanything/model.py` (~L1320); `mapanything/models/external/dinov2/layers/attention.py` | ✅ (code read); runtime ⏳ |
| Input size | `load_images(..., resolution_set=518)` resizes to the 518 px set (`"fixed_mapping"` mode). Our 1024 px frames are fine. | `mapanything/utils/image.py:147`; README resolution table | ✅ |
| Metric output | Per view: `pts3d` (world), `pts3d_cam`, `depth_z`, `intrinsics`, `camera_poses` (OpenCV cam2world), `conf`, `mask`, `metric_scaling_factor` | README "Image-Only Inference" (output list) | ✅ |
| Metric inputs | Optional per view: `intrinsics` or `ray_directions`, `depth_z` (needs calibration), `camera_poses` (OpenCV cam2world, +X right, +Y down, +Z forward), `is_metric_scale`. If any view has poses, the first must too. | README "Multi-Modal Inference" | ✅ |
| Memory-efficient mode | `model.infer(..., memory_efficient_inference=True, minibatch_size=None)` | README "Image-Only Inference" | ✅ |
| Time and memory per room on the M5 Pro | One room, 21 s iPhone video → 63 JPG frames (3 fps, 576×1024). M5 Pro, 48 GB, MPS, Apache weights at revision `00f9c24`, `memory_efficient_inference=True, minibatch_size=1`. **Inference 19.6 s**, model load 11.3 s, image load 0.3 s; whole demo script incl. 357 MB GLB export 72 s. **Peak memory footprint 14.8 GB** (MPS driver 12.8 GB). No MPS op fallback needed. Room extent (2–98 % of points) 3.6 × 2.4 × 4.2 m, camera path 12.3 m: plausible metric scale. Tape check (images only, no ARKit inputs): laptop desk real 0.78 m → 0.95–0.97 m; orchid desk real 0.61 m → 0.74–0.82 m. **Fails the ~20 cm go/no-go on absolute scale (+13 to +21 cm)**, but both are off by the same factor (≈1.23): the room is reconstructed about 23 % too large. Divided by 1.23, both desks are within ~6 cm, so the geometry is right and the metric scale from images alone is not. Expected fix: ARKit poses + LiDAR depth as metric inputs (CLAUDE.md §4), with the Umeyama scale as the check. Go/no-go stays open until a run with ARKit inputs. Whiteboard (1.84 m) not checked: its top is out of frame in every view; the same flat board fits a plane with 13.6 cm RMS across views. | `/usr/bin/time -l` + a split-timing script, run 2026-10-29 | ✅ |
| Hidden download | Model init fetches the DINOv2 **code** from `torch.hub` (`facebookresearch/dinov2`, branch `main`, unpinned) into `~/.cache/torch/hub`. Weights come from the HF checkpoint. Pipeline setup should warm this cache; pinning is `TODO(verify)`. | run log | ⚠️ noted |

**Consequence (ADR to write):** feed ARKit intrinsics, poses (`T_arkit @ diag(1, -1, -1, 1)`) and LiDAR depth as metric
inputs. Umeyama alignment becomes a drift check and an images-only fallback.

## 9. Modal ✅

Rachit has Modal credits (2026-10-29). Order for MapAnything: Mac (MPS) first, Modal if too slow, then a Baseten custom
deployment. With 19.6 s inference per room on the Mac, Modal is not needed now. Modal API details stay `TODO(verify)` until used.

## 18. Licences (MapAnything part ✅)

| Component | Licence | Source | Status |
|---|---|---|---|
| MapAnything code | Apache-2.0 | `LICENSE` | ✅ |
| MapAnything weights `facebook/map-anything-apache` | Apache 2.0: the model card front matter says `license: apache-2.0` and "This is the Apache 2.0 variant of the model"; not gated, public. Card revision `00f9c245bbcb60522d1ed7f9e9d88462c6e3f38a` (last modified 2026-02-04), checked 2026-10-29. Pin this revision when downloading. | README "Models › Hugging Face Hub Models"; https://huggingface.co/facebook/map-anything-apache ; https://huggingface.co/api/models/facebook/map-anything-apache | ✅ |
| Glimmer, SAM 3.1, VGGT, Atkinson Hyperlegible, Unsplash photo | not checked yet | — | ⏳ |
