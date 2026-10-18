# Project notes

[README](../README.md) · [Methods](METHODS.md) · [Results](RESULTS.md) · [Reproduction](REPRODUCIBILITY.md) · [Figure provenance](FIGURES.md)

## Attribution and sources

**Sing-Hao Wang** primarily implemented the code, integrated the workflow, analyzed the results, and prepared the research presentation, as confirmed by the project owner. External scientific methods are not claimed as newly invented algorithms.

**Research source:** Sing-Hao Wang, *Toward Digital Twin-Centered Human-Exoskeleton Collaboration: From Multi-Resolution Corticomuscular Coupling Analyses to an Incremental Mixture-of-Experts Locomotion Controller*, undergraduate capstone report, June 2026, Chapter 5, pp. 45–52. Study scope and reported observations in the English documentation were taken from the owner-supplied `RESEARCH_BRIEF.md`; participant data were not reanalyzed.

**Project report:** the owner identified [*Digital Signal Processing of Cortical and Muscular Dynamics*](reports/digital-signal-processing-of-cortical-and-muscular-dynamics.pdf) as this project's report. Its PDF contents and full bibliographic metadata were not independently reviewed. The [report index](reports/README.md) records the unchanged file's provenance. The report link does not establish independent reproduction of its findings.

External methods and software:

- [EEGLAB](https://eeglab.org/) supplies EEG processing and the manual ICA environment.
- [clean_rawdata / ASR](https://eeglab.org/plugins/clean_rawdata/) supplies the EEG cleaning context. The source calls `asr_calibrate` and `asr_process`; the experiment revisions are unknown.
- The [NMF toolbox publication](https://pmc.ncbi.nlm.nih.gov/articles/PMC3736608/) provides relevant `nmfnnls` / sparse-NMF context. Function-name correspondence does not establish the exact solver revision used here; the original solver files and notices are absent.
- MathWorks provides the filtering, STFT, clustering, distance, and matching functions used by the scripts.

No external toolbox source or new license was added during cleanup. Exact authorship/version records for missing helpers remain unavailable.

## Data and release status

The owner confirmed on **October 18, 2026** that both research repositories are approved for public release. **Repository visibility remains unchanged pending the owner's review of this cleanup.** This confirmation supersedes the earlier private-portfolio-only wording; it does not initiate a visibility change.

All eight authorized Chapter 5 figures remain byte-for-byte unchanged in `figures/`. Captions retain the corrections for trial counts, the shuffle heuristic, matching, and EEG scale interpretation. The existing project PDF is preserved without content changes. No participant recordings, participant identifiers, or new metadata tables were added; the supplied brief remains outside the repository.

Keep authorized recordings and generated products outside the checkout. `.gitignore` covers common recording formats, spreadsheets, pickles, NumPy arrays, motion files, videos, local settings, and result directories. Ignore rules do not remove already-tracked content or rewrite history. No history rewrite was performed.

Public-release approval does not select a software or figure license. No new license is inferred or assigned, and upstream software retains its own terms.

## Verification record

### Final cleanup — October 18, 2026

Baseline: main commit `06fb589cb6209fc15793def370e88de86f5ce7b7`.

- Source edits are limited to English comments and section headings. File paths, execution order, algorithms, constants, strings, and saved-field names are preserved.
- Across both repositories, all nine Python modules retain identical complete syntax trees, and all eight MATLAB files retain identical text after removing comments. The MATLAB comparison also retains the code inside disabled block-comment sections.
- Figure checksums match the preceding main branch. The report remains the same Git blob; it was not downloaded or rewritten for this cleanup.
- Documentation links and retained report/figure paths are checked against the final repository tree. Detailed results, method formulas, and necessary figure caveats remain in their dedicated guides.

These are source-preservation and documentation checks, not a new participant analysis or report reproduction.

### Earlier portfolio verification — October 17, 2026

The earlier review compared source with commit `a537d37200ec084340002c0a6e9f285e6c44f0b7`, inspected the six original MATLAB files, documented input/dependency contracts, and checked path cleanup, figure hashes, links, and whitespace. MATLAB R2024a startup and MathWorks-service errors prevented Code Analyzer and runtime checks; no successful MATLAB execution is claimed.

All eight figures were visually inspected and copied unchanged. The owner confirmed the median-based shuffle method and that all ten trials contributed to Fig. 5.2. These statements clarify documentation but do not replace source-data verification. Original recordings, saved NMF outputs, montage, ICA decisions, random-state logs, and missing dependencies remain unavailable. The WTS count discrepancy and other reproduction issues are retained in [Methods](METHODS.md).
