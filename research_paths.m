function paths = research_paths()
%RESEARCH_PATHS Configure private inputs without embedding machine paths.
% No study parameters or numerical methods are changed here.
% See docs/REPRODUCIBILITY.md for expected files and section order.
    paths.data_root = getenv('RESEARCH_DATA_ROOT');
    assert(isfolder(paths.data_root), ...
        'Set RESEARCH_DATA_ROOT to an existing, authorized local data folder.');
    paths.trial_folder = getenv('RESEARCH_TRIAL_DIR');
    if isempty(paths.trial_folder)
        paths.trial_folder = fullfile(paths.data_root, 'path2');
    end
    paths.ica_dir = getenv('RESEARCH_ICA_DIR');
    if isempty(paths.ica_dir)
        paths.ica_dir = fullfile(paths.data_root, 'ICA');
    end
    paths.channel_locations = getenv('RESEARCH_CHANNEL_LOCATIONS');
    paths.motion_template = getenv('RESEARCH_MOTION_TEMPLATE');
    paths.results_root = getenv('RESEARCH_RESULTS_ROOT');
    if isempty(paths.results_root)
        paths.results_root = fullfile(fileparts(mfilename('fullpath')), 'results');
    end
end
