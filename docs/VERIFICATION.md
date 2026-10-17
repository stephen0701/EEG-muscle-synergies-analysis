# Verification record

Prepared 2026-10-17 against main commit `a537d37200ec084340002c0a6e9f285e6c44f0b7`.

Source inspection covered all six original text files, including the NMF and matching sections in the long EMG script. A source map, dependency/input contract, and known scientific discrepancies are documented. Changes are limited to path configuration, English guidance, presentation labels, and documentation; existing numerical computations were retained.

MATLAB R2024a was installed, but initial startup failed with `failed to load settings errors_warnings plugin`; retrying with a workspace preference directory failed to communicate with required MathWorks services (5201). Consequently MATLAB Code Analyzer, the new path helper's runtime check, and end-to-end MATLAB execution were **not completed**. No MATLAB pass is implied by source inspection.

Local Markdown links, original machine-path removal, image hashes, and diff whitespace are checked during handoff. All eight supplied Chapter 5 figures are now included, copied without editing or regeneration. Their visible labels were inspected; adjacent captions correct subjects/trials and the shuffle-threshold description. The missing montage prevents independent anatomical orientation verification.

## Figure-restoration clarification

The owner confirmed that the archived median-based shuffle heuristic is the intended method and the report's 75th-percentile wording needs correction. The owner also confirmed that all ten trials contributed to Fig. 5.2. These statements resolve the documentation questions; they do not substitute for an independent data reanalysis. STS/STW synergy examples are shown on the README, with all eight figures in [Results](RESULTS.md).

The restoration revision changes documentation and figure assets only. Analysis source files, numerical parameters, and original image bytes are unchanged from the preceding portfolio revision. Existing software-check results were not represented as newly rerun analyses.

## Project-report organization

The owner identified the existing repository PDF as this project's report. It was moved from the repository root to `docs/reports/digital-signal-processing-of-cortical-and-muscular-dynamics.pdf` by reusing the original Git blob `9571721addd6e27d29333a53b3b204f650191a32` (9,057,204 bytes). The move preserves the file contents; README, report-index, and attribution links were updated. Analysis code and figures are unchanged by this organization step.

No source recordings, saved NMF results, or original random/ICA logs were available. Report findings are faithful transcriptions from the supplied brief, not independently reproduced results. The project PDF remains unreviewed. See [Methods](METHODS.md) and [Data/publication](DATA_AND_PUBLICATION.md).
