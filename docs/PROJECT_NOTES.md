# Project notes

[README](../README.md) · [Methods](METHODS.md) · [Results](RESULTS.md) · [Reproduction](REPRODUCIBILITY.md) · [Figure provenance](FIGURES.md)

## Attribution and sources

**Sing-Hao Wang** primarily implemented the code, integrated the workflow, analyzed the results, and prepared the research presentation, as recorded in the project contribution statement. External scientific methods are not claimed as newly invented algorithms.

**Research source:** Sing-Hao Wang, *Toward Digital Twin-Centered Human-Exoskeleton Collaboration: From Multi-Resolution Corticomuscular Coupling Analyses to an Incremental Mixture-of-Experts Locomotion Controller*, undergraduate capstone report, June 2026, Chapter 5, pp. 45–52. Study scope and reported observations in the English documentation were taken from the project research summary (`RESEARCH_BRIEF.md`); participant data were not reanalyzed.

**Official project report:** [*Digital Signal Processing of Cortical and Muscular Dynamics*](reports/digital-signal-processing-of-cortical-and-muscular-dynamics.pdf). Its cover and PDF metadata were inspected during release preparation; this does not independently reproduce its scientific results. The [report index](reports/README.md) records the unchanged file's provenance.

External methods and software:

- [EEGLAB](https://eeglab.org/) supplies EEG processing and the manual ICA environment.
- [clean_rawdata / ASR](https://eeglab.org/plugins/clean_rawdata/) supplies the EEG cleaning context. The source calls `asr_calibrate` and `asr_process`; the experiment revisions are unknown.
- The [NMF toolbox publication](https://pmc.ncbi.nlm.nih.gov/articles/PMC3736608/) provides relevant `nmfnnls` / sparse-NMF context. Function-name correspondence does not establish the exact solver revision used here; the original solver files and notices are absent.
- MathWorks provides the filtering, STFT, clustering, distance, and matching functions used by the scripts.

No external toolbox source or new license was added during cleanup. Exact authorship/version records for missing helpers remain unavailable.

## Data and release status

Public release of both research repositories was approved on **October 18, 2026**. Participant recordings remain outside the repositories.

All eight authorized Chapter 5 figures remain byte-for-byte unchanged in `figures/`. Captions retain the corrections for trial counts, the shuffle heuristic, matching, and EEG scale interpretation. The existing project PDF is preserved without content changes. No participant recordings, participant identifiers, or new metadata tables were added; the project research summary remains outside the repository.

Keep authorized recordings and generated products outside the checkout. `.gitignore` covers common recording formats, spreadsheets, pickles, NumPy arrays, motion files, videos, local settings, and result directories. Ignore rules do not remove already-tracked content or rewrite history. No history rewrite was performed.

## Citation and reuse

Use the root [`CITATION.cff`](../CITATION.cff) for academic citation metadata. Sing-Hao Wang is listed as the verified primary software author; other research contributions remain credited above. No DOI, publication venue, software version, or additional author is inferred.

The original project code is provided **without a license**. Public visibility does not grant a general license to reuse, modify, or redistribute it; applicable law and GitHub's platform terms still apply. Academic citation guidance is separate from legal permission, and `CITATION.cff` does not impose a universally enforceable citation condition. See [GitHub's licensing guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).

Third-party software, figures, and the project report retain their respective ownership and applicable terms. Citation metadata does not alter those rights or grant permission on another contributor's behalf.

## Verification record

### Final cleanup — October 18, 2026

Baseline: main commit `06fb589cb6209fc15793def370e88de86f5ce7b7`.

- Source edits are limited to English comments and section headings. File paths, execution order, algorithms, constants, strings, and saved-field names are preserved.
- Across both repositories, all nine Python modules retain identical complete syntax trees, and all eight MATLAB files retain identical text after removing comments. The MATLAB comparison also retains the code inside disabled block-comment sections.
- Figure checksums match the preceding main branch. The report remains the same Git blob; it was not rewritten during cleanup.
- Documentation links and retained report/figure paths are checked against the final repository tree. Detailed results, method formulas, and necessary figure caveats remain in their dedicated guides.

These are source-preservation and documentation checks, not a new participant analysis or report reproduction.

### Earlier portfolio verification — October 17, 2026

The earlier review compared source with commit `a537d37200ec084340002c0a6e9f285e6c44f0b7`, inspected the six original MATLAB files, documented input/dependency contracts, and checked path cleanup, figure hashes, links, and whitespace. MATLAB R2024a startup and MathWorks-service errors prevented Code Analyzer and runtime checks; no successful MATLAB execution is claimed.

All eight figures were visually inspected and copied unchanged. The author confirmed the median-based shuffle method and that all ten trials contributed to Fig. 5.2. These statements clarify documentation but do not replace source-data verification. Original recordings, saved NMF outputs, montage, ICA decisions, random-state logs, and missing dependencies remain unavailable. The WTS count discrepancy and other reproduction issues are retained in [Methods](METHODS.md).
