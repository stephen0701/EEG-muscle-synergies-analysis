# Figure provenance and selection

Source: owner-supplied `Research_Repo_Codex_Pack.zip`, reference figures from the capstone chapters summarized in the supplied brief. The owner authorized inclusion in these private repositories on 2026-10-17. Public-release permission was not established.

Selected originals are copied byte-for-byte. Filenames are descriptive; no pixels, axes, or underlying values were edited. No source measurements were available for regeneration. Visual checking validates visible text, not the full analysis provenance.

| Included file | Original | Dimensions | SHA-256 |
| --- | --- | --- | --- |
| `eeg_beta_topography.jpeg` | `fig_5_5a.jpeg` | 1684 × 444 | `64fcc4fe60f9dc22d15fbc89806c00436d3d8f445e122b1154804dc5ed964192` |
| `eeg_low_gamma_topography.jpeg` | `fig_5_5b.jpeg` | 1688 × 483 | `7714bc74167a1ca6f35c887359ed9f8965d9ee4624bef9ef07b2f6df4c77956d` |

## Label checks and exclusions

- Fig. 5.5a/b: Beta / Low Gamma and STS/STW/WTS labels agree with the EEG topography section (13-30 and 32-46 Hz). Band color scales differ. No calibrated power units or significance are asserted. Electrode orientation remains unverified without the acquisition montage.
- Fig. 5.1: excluded because “75% shuffled” does not accurately describe the implemented median-based heuristic; the plot also contains a recording/trial code. Source plotting legend is corrected for future regeneration.
- Fig. 5.2: excluded because “Subject Synergies” misstates the repeated-trial unit. Source axis label now says “Trial Synergies.”
- Fig. 5.3a/b and Fig. 5.4a/b: excluded because titles say “N=10 subjects.” They represent ten trials from one participant. Source titles now state trials; originals were not raster-edited.

Recommended later addition: regenerate one STS/STW synergy comparison from release-approved original analysis products with correct trial labels and a documented solver/criterion. The current portfolio does not imply those products were available.

Checksums identify supplied image bytes; they do not prove that the figures came from a specific code commit. See [Methods](METHODS.md) for interpretation and [Data/publication](DATA_AND_PUBLICATION.md) for release limits.
