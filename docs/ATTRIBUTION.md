# Attribution and references

**Sing-Hao Wang:** primary code implementation, workflow integration, analysis, and research presentation, confirmed by the project owner during portfolio preparation. These contributions do not imply invention or sole ownership of external scientific algorithms.

**Project report:** [*Digital Signal Processing of Cortical and Muscular Dynamics*](reports/digital-signal-processing-of-cortical-and-muscular-dynamics.pdf), identified by the repository owner as the report for this project. The original PDF content is preserved; its full bibliographic metadata and contents have not been independently reviewed.

**Broader capstone source:** Sing-Hao Wang, *Toward Digital Twin-Centered Human-Exoskeleton Collaboration: From Multi-Resolution Corticomuscular Coupling Analyses to an Incremental Mixture-of-Experts Locomotion Controller*, undergraduate capstone report, June 2026, Chapter 5, pp. 45-52. Scope and reported findings in the English documentation were taken from the supplied `RESEARCH_BRIEF.md`, not independently extracted from either PDF.

**External methods and software:**

- [EEGLAB](https://eeglab.org/) provides EEG processing and the manual ICA environment.
- [clean_rawdata / ASR documentation](https://eeglab.org/plugins/clean_rawdata/) credits the ASR methods and implementation. The archived code calls `asr_calibrate` and `asr_process`; exact experiment revisions are unknown.
- [`nmfnnls` and sparse NMF toolbox context](https://pmc.ncbi.nlm.nih.gov/articles/PMC3736608/) is a relevant original toolbox publication. Function-name correspondence alone does not establish the exact provenance or version used here; recover the original solver files and notices before redistributing them.
- MathWorks supplies the MATLAB filtering, STFT, clustering, distance, and matching functions used by the scripts.

No toolbox source was copied into the repositories during cleanup. Missing helpers and their original authors/versions remain to be recovered. No new software or figure license was assigned: repository access and private-portfolio permission do not establish unrestricted redistribution rights.
