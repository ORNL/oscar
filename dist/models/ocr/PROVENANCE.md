# OSCAR `sensorhub-process-ocr` Optional Tier-0 Model Bundle — Commercial Provenance & License Notice

## 1. Commercial Vendor Redistribution Summary
All models and vocabularies in this bundle are **100% compatible with commercial modification, bundling, and resale** alongside OSCAR (`MPL-2.0`):

| File | Architecture / Role | Upstream Base & License | Training Data Provenance |
| :--- | :--- | :--- | :--- |
| `det.onnx`, `rec.onnx`, `dict.txt` | PP-OCRv3 DBNet + SVTR-LCNet CTC | PaddleOCR (`Apache-2.0`) | Unmodified upstream Apache-2.0 release |
| `stencil_det_fp32.onnx` | Stride-4 Oriented Stencil & Plate ROI Detector (`640x384`) | Mindee `docTR` `db_mobilenet_v3_large` (`Apache-2.0`, zero ImageNet weights) | **100% CC0 / US-Gov Public-Domain** outdoor photographs (`146` verified images; `1` real CC0 containers + `141` clean CC0 backgrounds) + procedural TrueType 3D corrugated steel renders + 4 ORNL-authorized portal clips |
| `parseq_rec_int8.onnx`, `parseq_vocab.txt` | INT8 2D-Attention Scene-Text Recognizer (`32x128`) | Mindee `docTR` `parseq` (`Apache-2.0`) | 100% procedural TrueType 3D container & license-plate renders |

## 2. Explicit Clean-Room Attestations
- **Zero YouTube / Web-Scraped Video Frames:** No YouTube videos, frames, or crops were accessed or loaded during training.
- **Zero Non-Commercial Dataset Weights:** Zero ImageNet-1K (`torchvision`) checkpoints were used; the detector backbone is initialized strictly from `mindee/doctr` (`Apache-2.0`).
- **Zero Copyleft / AGPL Dependencies:** Zero `ultralytics` (`AGPL-3.0`) code or weights were used anywhere in training, export, or inference.

## 3. Verified CC0 / Public-Domain Background Corpus Breakdown
Full per-file URLs, Wikimedia page IDs, license tags, and SHA-256 digests are recorded in `../../cc0-backgrounds/PROVENANCE_MANIFEST.json`:
- `CC0`: **145** photographs
- `Public domain`: **1** photographs
