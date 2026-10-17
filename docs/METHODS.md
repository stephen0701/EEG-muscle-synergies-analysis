# Methods and source correspondence

The supplied research brief establishes reported experimental context. Source inspection establishes implemented calculations, not reproduction of the findings.

## EMG and NMF

Each `EMG_data` entry is a trial from one participant. The script splits eight channels (LGA, RGA, LTA, RTA, LBF, RBF, LRF, RRF) into 10-30, 30-45, 45-120, and 135-280 Hz using fourth-order Butterworth bandpass filters. Phase clips are resampled from 1000 to 500 Hz. The `method = 'max'` normalization is actually per-channel min-max scaling; constant channels are retained.

NMF receives muscle-by-time data. `A` contains muscle weights, and `Y` contains activation, corresponding to `W` and `H` in `V ≈ WH`. Both sparse `sparsenmfnnls` and non-sparse `nmfnnls` sections try k = 1:8 and compute:

```text
VAF(k) = 1 - SSE(k) / SST
SSE(k) = sum((V - A_k * Y_k).^2, all elements)
SST = sum((V - mean(V, all elements)).^2, all elements)
deltaVAF = diff(VAF)
```

For each trial/band/phase, the selection section shuffles the VAF vector 100 times, concatenates successive differences, and uses:

```text
threshold_deltaVAF = abs(0.75 * median(all_deltas))
valid_Ks = k_range((VAF >= 0.9) & ([0, deltaVAF] >= threshold_deltaVAF))
```

It selects the first valid k, then the modal k by phase. **This is not a 75th-percentile criterion, and it does not shuffle/refit the raw EMG matrix.** The owner confirmed that the current implementation is authoritative for the documented method and that the report/brief's 75th-percentile wording needs correction. The code was retained and its plotting legend says “Shuffle heuristic.” The original Fig. 5.1 is included with this clarification beside it; no threshold or curve was recomputed.

Classification L2-normalizes columns of A, pools the vectors, and runs cosine-distance k-means (`Replicates=20`, `MaxIter=10000`). `pdist2` and `matchpairs(dist_tmp, 1)` assign trial synergies to consensus centers and reorder A/Y. Y is not rescaled when A is normalized, so subsequent activation magnitudes should not be interpreted as a reconstruction-preserving factorization. Average activations are linearly interpolated to 500 normalized time points; coefficient error bars are across-trial SD.

## EEG and phases

The EEG source includes event alignment, mean removal, detrending, notch/bandpass filtering, ASR, average re-reference, manual ICA export/import, and z-scoring. The Motion script uses `transient_results`, `time_EEG`, and `time_EMG` to create shared-workspace phase clips. EEG topography uses STFT-based band power averaged over valid trials, with global, phase-specific, or band-specific color limits.

EEG bands are Delta 1-3, Theta 4-8, Alpha 9-12, Beta 13-30, and Low Gamma 32-46 Hz. These differ from MUAP defaults. Physical power calibration and scalp geometry cannot be verified without the original montage and preprocessing record. Exploratory FFT, spectrogram, PAC, and bicoherence sections are EEG-only; they do not establish EEG-synergy coherence.

## Unresolved issues preserved for review

| Issue | Consequence |
| --- | --- |
| The RMS envelope section overwrites the Hilbert envelope | Running the whole script does not select a unique report route. |
| `hilbert(band_data')'` transposes earlier sample-by-channel arrays | The transform dimension needs verification against the experiment; it was not silently corrected. |
| The later non-sparse NMF section overwrites sparse results | The final experiment solver cannot be inferred from source order. |
| Report/brief calls the median-based shuffle heuristic a 75th-percentile rule | Owner clarified the archived code is the intended method; the report wording needs correction. Reported k values still have not been independently recomputed. |
| WTS k = 4 conflicts with a later three-synergy statement | README quotes Section 5.3.1 as reported and leaves the inconsistency open. |
| Distance matrices are stored by trial index but averaged over the first `valid_subjects` slices | Skipped trials can introduce unfilled slices in other runs. The owner confirmed all ten trials succeeded for Fig. 5.2, so this skipped-trial case does not apply to that figure according to the clarification. |
| Original data, montage, manual ICA record, template, and helpers are absent | Exact reproduction is unavailable. |

Legacy `subject`/`subj` variable names and saved fields such as `subject_indices` are retained for compatibility. In this study they identify trials, not independent participants. New plot titles say so explicitly.
