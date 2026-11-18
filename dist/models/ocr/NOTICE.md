# OCR Model Provenance

These files are consumed by the `sensorhub-process-ocr` module (`OnnxOcrEngine`).
All are licensed **Apache-2.0** (see LICENSE in this directory). No AGPL or other
copyleft model artifacts may be added here.

| file | upstream | source / provenance | sha256 |
|---|---|---|---|
| `det.onnx` | PaddleOCR `en_PP-OCRv3_det_infer` (DBNet text detection), ONNX conversion distributed by RapidOCR (RapidAI) | https://huggingface.co/SWHL/RapidOCR/resolve/main/PP-OCRv4/en_PP-OCRv3_det_infer.onnx | `f139598bc2af4e4b6fe98dec11574e30edfdd91fc94ac1425c18ace3bd5a866b` |
| `rec.onnx` | PaddleOCR `en_PP-OCRv3_rec_infer` (SVTR-LCNet CTC recognition, input height 48), ONNX conversion distributed by RapidOCR (RapidAI) | https://huggingface.co/SWHL/RapidOCR/resolve/main/PP-OCRv3/en_PP-OCRv3_rec_infer.onnx | `ef7abd8bd3629ae57ea2c28b425c1bd258a871b93fd2fe7c433946ade9b5d9ea` |
| `dict.txt` | PaddleOCR `en_dict.txt` recognition charset (95 entries; CTC blank is class 0, space is the class after the last dict entry) | https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/en_dict.txt | `5662df9d2d03f0e8ca0d3b0649d6acbab904b6a14b3d3521463c71c37c668ce3` |
| `stencil_det_fp32.onnx` | Mindee `docTR` `db_mobilenet_v3_large` (`Apache-2.0`) stride-4 oriented stencil & plate ROI detector (`640x384`) | Clean-room `CC0` / US-Gov Public-Domain + procedural TrueType 3D training ([PROVENANCE.md](PROVENANCE.md)) | `84327ce9a7ee903af29b66da811cfef8d35bdb529c1d82835677e2a2f2c13b0b` |
| `parseq_rec_int8.onnx` | Mindee `docTR` `parseq` (`Apache-2.0`) INT8 2D-attention scene-text recognizer (`32x128`) | Procedural TrueType 3D container & license-plate training ([PROVENANCE.md](PROVENANCE.md)) | `9e5fde1c39914dc347dbfb6770c33aa9664530e1dbdf1e73fdc66955b72b1bff` |
| `parseq_vocab.txt` | PARSeq character vocabulary | [PROVENANCE.md](PROVENANCE.md) | `2ba2a5f8c8937aa0e3a3cecaf6095879b7dbe4b345b4f3146d5f6e637f2a9437` |

Retrieved 2026-07-11.

- PaddleOCR: https://github.com/PaddlePaddle/PaddleOCR (Apache-2.0)
- RapidOCR ONNX conversions: https://github.com/RapidAI/RapidOCR (Apache-2.0)

To swap models (e.g. a fine-tuned container/plate recognizer), replace the files,
keep the same names, update this table, and re-run the `OnnxOcrEngineTest` golden
tests. The engine reads the recognition input height from the model, so 32-px
(v2) and 48-px (v3/v4) rec models both work.
