# STT benchmark report (#195) - fill in and paste into the issue

## Environment
- Chip / RAM:
- macOS version:
- Power mode (battery / adapter / low power):
- Ollama loaded during run (model, params): yes/no -
- whisper.cpp revision:
- WhisperKit version:
- mlx-whisper version:

## Models tested
| Backend | Model | Quant | Notes |
|---|---|---|---|
| whisper.cpp | large-v3-turbo | q5_0 | stock multilingual |
| whisper.cpp | ivrit-ai large-v3-turbo GGML | | `he` forced |
| whisper.cpp | large-v3 | | quality baseline (if RAM allows) |
| WhisperKit | | | Core ML encoder variant measured separately |
| mlx-whisper | large-v3-turbo | | |

## Results
| Backend / model | Clips | WER (he) | CER (he) | Slot acc | Cold load s | p50 ms | p95 ms | Peak RSS MB |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

## Observations
- Failure modes (hallucination on silence, numbers, code switching):
- Unsupported combinations found:
- Core ML encoder: cold compilation time, extra assets, verdict:

## Proposed budgets and default
- Latency budget: p95 <=
- Accuracy budget: WER <=
- Recommended default backend/model:
- Rationale:
