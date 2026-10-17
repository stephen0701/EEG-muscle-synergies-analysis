# Figure provenance and interpretation

Source: owner-supplied `Research_Repo_Codex_Pack.zip`, reference figures associated with the capstone chapters summarized in the supplied brief. The owner authorized all supplied figures for these private portfolio repositories, including originals with explicit corrections or interpretation limits. Public-release permission was not established.

All original image bytes are preserved. Descriptive filenames do not alter the plotted data. Labels requiring correction are addressed immediately beside the figures; no pixels, axes, coefficients, or curves were edited or regenerated. Full code-to-figure provenance cannot be independently reconstructed without the original analysis products.

| Source figure | Repository asset | Dimensions |
| --- | --- | --- |
| fig_5_1 | [vaf_delta_vaf.jpeg](figures/vaf_delta_vaf.jpeg) | 1108 × 870 |
| fig_5_2 | [synergy_matching_distance.jpeg](figures/synergy_matching_distance.jpeg) | 1178 × 962 |
| fig_5_3a | [synergy_sts_30_45.jpeg](figures/synergy_sts_30_45.jpeg) | 1685 × 856 |
| fig_5_3b | [synergy_stw_30_45.jpeg](figures/synergy_stw_30_45.jpeg) | 1686 × 841 |
| fig_5_4a | [synergy_sts_lower_bands.jpeg](figures/synergy_sts_lower_bands.jpeg) | 1687 × 425 |
| fig_5_4b | [synergy_sts_higher_bands.jpeg](figures/synergy_sts_higher_bands.jpeg) | 1688 × 421 |
| fig_5_5a | [eeg_beta_topography.jpeg](figures/eeg_beta_topography.jpeg) | 1684 × 444 |
| fig_5_5b | [eeg_low_gamma_topography.jpeg](figures/eeg_low_gamma_topography.jpeg) | 1688 × 483 |

SHA-256, metadata inventory, and source-to-file mappings are stored in [manifest.json](figures/manifest.json). No EXIF tags were found in the supplied JPEGs. Hashes verify byte identity, not the scientific validity of the results.

## Corrections and owner clarifications

- **Fig. 5.1:** the owner confirmed the archived method uses `abs(0.75 * median(all_deltas))` after shuffling VAF vectors. The report/brief's 75th-percentile wording needs correction. The original “75% shuffled” legend must not be interpreted as a percentile threshold. No selection curve was recomputed.
- **Fig. 5.2:** “Subject Synergies” denotes trial synergies. The owner confirmed all ten trials succeeded in the displayed average. A generic skipped-trial indexing issue remains relevant to other runs, not this figure according to that clarification.
- **Figs. 5.3a/b and 5.4a/b:** “N=10 subjects” is a title error. The case study uses ten trials from one participant. Error bars are across-trial SD. Row numbers alone do not establish module identity across phases or bands.
- **Figs. 5.5a/b:** labels match Beta 13-30 Hz, Low Gamma 32-46 Hz, and STS/STW/WTS. Color scales differ between bands. No calibrated physical power unit or significance is inferred; the acquisition montage is unavailable for independent anatomical verification.

The README emphasizes STS/STW synergies and EEG topography. The [complete results gallery](RESULTS.md) presents all eight figures in method/result order.

Owner clarifications are documented statements rather than independent source-data verification. See [Methods](METHODS.md), [Verification](VERIFICATION.md), and [Data/publication](DATA_AND_PUBLICATION.md) for scope and limits.
