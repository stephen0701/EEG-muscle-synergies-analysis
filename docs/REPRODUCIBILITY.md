# Reproduction guide

[README](../README.md) · [Methods](METHODS.md) · [Results](RESULTS.md) · [Reproduction](REPRODUCIBILITY.md) · [Project notes](PROJECT_NOTES.md)

## Status and requirements

This is an organized source archive, not a turnkey reproduction. Recordings, trial-level NMF outputs, ICA decisions, acquisition montage, and several dependencies are absent. Selected original figures were inspected and copied unchanged, not regenerated.

| Dependency | Use / availability |
| --- | --- |
| MATLAB R2024a+ | Interspersed local functions and script sections |
| Signal Processing Toolbox | Filters, Hilbert transform, resampling, STFT |
| Statistics and Machine Learning Toolbox | k-means, silhouette, distances, matching |
| DSP System Toolbox | Original `designNotchPeakIIR` calls |
| EEGLAB and compatible ASR functions | Import, montage, cleaning, re-reference, manual ICA; experiment versions unknown |
| `sparsenmfnnls`, `nmfnnls` | External solver files absent; exact original revision unknown |
| `readNPY` and `plot_topography` | External helpers absent |
| `ch32.ced`, `result_template.mat` | Original montage and motion template absent |

Do not substitute guessed dependencies and call the result reproduced.

## Private input contract

The EEG/EMG scripts expect flat folders of matching CSV exports. The Motion script uses per-trial subdirectories:

```text
private-data/
  path2/                       # EEG_path2_*.csv and EMG_path2_*.csv
  ICA/                         # manually reviewed Data<number>.set files
  path2_<trial>/opensim/
    sync_time_marker.npz
    Empty_project_filt_0-30.trc
    Balancing_for_IK_BODY.mot
```

This describes parser expectations, not bundled data. EEG channels occupy columns 3-34, event fields 35/38; EMG channels occupy 3-10, event fields 11/14. Both use alignment codes 130/141 and serial column 2. Check acquisition conventions and trial ordering. Synchronization arrays, marker order, positional template columns, and the extra synchronization frame must match the experiment.

Configure approved paths in MATLAB:

```matlab
setenv('RESEARCH_DATA_ROOT', '/your/private/data');
setenv('RESEARCH_TRIAL_DIR', '/your/private/data/path2');
setenv('RESEARCH_ICA_DIR', '/your/private/data/ICA');
setenv('RESEARCH_CHANNEL_LOCATIONS', '/your/private/montage/ch32.ced');
setenv('RESEARCH_MOTION_TEMPLATE', '/your/private/templates/result_template.mat');
setenv('RESEARCH_RESULTS_ROOT', '/your/private/results');
```

`research_paths.m` validates the data root. Other files are required by the relevant sections. Results default to ignored `results/` if no output root is supplied. No scientific parameters are configured here.

## Section-level workflow to inspect

1. In the MATLAB editor, run path setup and EEG/EMG import/alignment sections. Confirm matched trials and timestamp units.
2. Review EEG processing through ASR; export to EEGLAB; complete and record manual ICA; import reviewed `.set` files; z-score.
3. Review EMG detrending, notch filtering, and frequency division. Choose the intended envelope explicitly. The report describes Hilbert envelopes; verify its transform dimension before treating that route as final. Do not execute every envelope alternative sequentially.
4. In Motion, inspect synchronization and transition detection. Run final phase alignment only after `EEG_data`, `EMG_data`, `time_EEG`, `time_EMG`, and transition results share the workspace. Diagnostic heel-strike sections need external `LHS_data`/`RHS_data`.
5. Review EMG resampling/normalization, choose one NMF section, then inspect count selection, matching, and summary plots. Record the solver, criterion, and random state; the source does not fix a seed.
6. Inspect EEG phase-specific power topographies. The comparison with synergy patterns remains qualitative.

This maps dependencies and manual handoffs, not a validated execution recipe for the report. See [Methods](METHODS.md) for blockers and [Verification](PROJECT_NOTES.md#verification-record) for checks actually completed.
