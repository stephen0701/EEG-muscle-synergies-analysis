# Verification record

Prepared 2026-10-17 against main commit `a537d37200ec084340002c0a6e9f285e6c44f0b7`.

Source inspection covered all six original text files, including the NMF and matching sections in the long EMG script. A source map, dependency/input contract, and known scientific discrepancies are documented. Changes are limited to path configuration, English guidance, presentation labels, and documentation; existing numerical computations were retained.

MATLAB R2024a was installed, but initial startup failed with `failed to load settings errors_warnings plugin`; retrying with a workspace preference directory failed to communicate with required MathWorks services (5201). Consequently MATLAB Code Analyzer, the new path helper's runtime check, and end-to-end MATLAB execution were **not completed**. No MATLAB pass is implied by source inspection.

Local Markdown links, original machine-path removal, selected image hashes, and diff whitespace are checked during handoff. The two included images were visually inspected for band/phase labels and copied without editing; they were not regenerated. The missing montage prevents independent anatomical orientation verification.

No source recordings, saved NMF results, or original random/ICA logs were available. Report findings are faithful transcriptions from the supplied brief, not independently reproduced results. The pre-existing PDF remains unreviewed. See [Methods](METHODS.md) and [Data/publication](DATA_AND_PUBLICATION.md).
