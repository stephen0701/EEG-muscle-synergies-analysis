% RESEARCH NOTE: This archive contains section-based research scripts.
% See docs/REPRODUCIBILITY.md before executing sections. Alternatives overwrite
% shared variables; running the entire file is not a verified report pipeline.
% Each legacy subject/subj index denotes a trial from ONE participant.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root, fullfile(repo_root, 'Function'));
paths = research_paths();

%% Import recording data

% Input data directory.
folder_path = paths.trial_folder;

% Find matching EEG CSV exports.
files = dir(fullfile(folder_path, 'EEG_path2_*.csv'));

% Preallocate a cell array for the imported files.
EEG_data = cell(1, numel(files));

% Read each file into the cell array.
for i = 1:numel(files)
    try
        % Construct the full file path.
        file_path = fullfile(files(i).folder, files(i).name);
        
        % Initialize the trial structure.
        EEG_data{i} = struct();  

        % Read the CSV file with readtable.
        EEG_data_table = readtable(file_path, 'VariableNamingRule', 'preserve');
        
        % Convert the table to an array and store it.
        EEG_data{i}.original = table2array(EEG_data_table);
        
        % Initialize the remaining fields as empty.
        EEG_data{i}.alignment = [];
        EEG_data{i}.reducemean = [];
        EEG_data{i}.detrend = [];
        EEG_data{i}.notchfilter = [];
        EEG_data{i}.butterworthfilter = [];
        EEG_data{i}.asr = [];
        EEG_data{i}.asrbase = [];
        EEG_data{i}.asrmove = [];
        EEG_data{i}.ica = [];
        EEG_data{i}.zcore = [];
        EEG_data{i}.clip = [];
       
    catch ME
        % Report the error and continue.
        warning('Error reading file %s: %s', files(i).name, ME.message);
    end
end

% Report the number of imported files.
num_files_read = sum(cellfun(@(x) ~isempty(x.original), EEG_data));
disp(['已成功讀取 ', num2str(num_files_read), ' 個檔案。']);

%% Align recordings and interpolate missing samples

% Check the recording length before changing the start/end index range.

n1 = 35; % event id column
n2 = 38; % software id column
serial_number = 2; % serial number column
start_event = 130; % Red-light onset.
end_event = 141; % Green-light offset.
columns_to_process = 3:34; % Select channel columns only.

% Store discontinuous portions for inspection.
non_continuous_data = {};

% Initialize the start and end indices.
num_files = numel(EEG_data);
start_indices = nan(1, num_files); % Preallocate with NaN.
end_indices = nan(1, num_files);   % Preallocate with NaN.

% Align each recording.
for i = 1:num_files
    try
        EEG_data_array = EEG_data{i}.original;  % Extract the array from the cell.

        % Check that the data are available.
        if isempty(EEG_data_array)
            disp(['檔案無效或未讀取成功: ', files(i).name]);
            continue;  % Skip this file and continue.
        end

        % Find start and end indices using n1.
        logical_start = EEG_data_array(:, n1) == start_event;
        logical_end = EEG_data_array(:, n1) == end_event;

        % Locate the first and last matching indices.
        start_idx = find(logical_start, 1);
        end_idx = find(logical_end, 1, 'last');

        % Retry with n2 when n1 has no start or end match.
        if isempty(start_idx) || isempty(end_idx) %|| ...
           %(end_idx - start_idx < 11000) || (end_idx - start_idx > 13000)
            disp(['event id 找不到有效的索引，使用 software marker: ', files(i).name]);
            logical_start = EEG_data_array(:, n2) == start_event;
            logical_end = EEG_data_array(:, n2) == end_event;
            start_idx = find(logical_start, 1);
            end_idx = find(logical_end, 1, 'last');
        end

        % Check that both boundary indices were found.
        if isempty(start_idx) || isempty(end_idx) %|| ...
           %(end_idx - start_idx < 11000) || (end_idx - start_idx > 13000)
            disp(['無法找到有效的開始或結束索引: ', files(i).name]);
            continue;  % Skip this file and continue.
        end

        % Store the start and end indices.
        start_indices(i) = start_idx;
        end_indices(i) = end_idx;

        % Extract data from the first event 130 to the last event 141.
        aligned_data = EEG_data_array(start_idx:end_idx, :);
        EEG_data{i}.alignment = aligned_data;

        % Check continuity in column 2 (serial_number).
        serial_col = aligned_data(:, serial_number);
        discontinuities = find(diff(serial_col) ~= 1); % Locate discontinuities.

        if ~isempty(discontinuities)
            % Store the discontinuous data.
            non_continuous_data{i} = aligned_data(discontinuities + 1, :); % Extract the rows at discontinuities.
            disp(['發現不連續數據: ', files(i).name]);

            % Interpolate missing samples.
            full_range = (min(serial_col):max(serial_col))';  % Construct the expected complete index range.
            missing_points = setdiff(full_range, serial_col);  % Find missing indices.

            % Print the missing indices.
            if ~isempty(missing_points)
                disp(['缺少: ', num2str(missing_points')]);
            end

            if ~isempty(missing_points)
                % Create a table spanning the complete index range.
                complete_data = nan(numel(full_range), size(aligned_data, 2));
                complete_data(ismember(full_range, serial_col), :) = aligned_data;

                % Linearly interpolate columns 1 through 34.
                for col = 1:34  % Process columns 1 through 34 only.
                    valid_idx = ~isnan(complete_data(:, col));
                    if sum(valid_idx) < 2
                        disp(['警告: 檔案 ', files(i).name, ' 的列 ', num2str(col), ' 沒有足夠的有效數據進行插值。']);
                        continue;
                    end

                    complete_data(:, col) = interp1(full_range(valid_idx), complete_data(valid_idx, col), full_range, 'linear');
                end

                EEG_data{i}.alignment = complete_data;
                disp(['已對檔案插值補齊缺失數據: ', files(i).name]);
                
                % Set the continuity tolerance to approximately one index step.
                tolerance = 1;

                % Check interpolated serial-number continuity within the tolerance.
                serial_col_interpolated = complete_data(:, serial_number);
                discontinuities = find(abs(diff(serial_col_interpolated) - 1) > tolerance);  % Find discontinuities exceeding the tolerance.

                if isempty(discontinuities)
                    disp(['檔案 ', files(i).name, ' 插值成功，缺失點已補上。']);
                else
                    disp(['檔案 ', files(i).name, ' 插值失敗，以下為不連續點的索引位置:']);
                    disp(discontinuities + 1);  % Report discontinuity positions using the corresponding row indices.
                end

            end
        end
    % Store the time vector.
    time_EEG{i} = cell(1, numel(files));
    time_EEG{i} = EEG_data{i}.alignment(:,1);

    % Retain channel columns only.
    EEG_data{i}.alignment = EEG_data{i}.alignment(:,columns_to_process);

    catch ME
        warning('對齊檔案 %s 時發生錯誤: %s', files(i).name, ME.message);
    end
end

% Report the number of aligned files.
num_files_aligned = sum(~isnan(start_indices));
disp(['已成功對齊 ', num2str(num_files_aligned), ' 個檔案。']);

% Report each EEG alignment array's dimensions.
for i = 1:num_files
    if isfield(EEG_data{i}, 'alignment') && ~isempty(EEG_data{i}.alignment)
        [rows, cols] = size(EEG_data{i}.alignment);
        disp(['EEG_data', num2str(i), '.alignment', num2str(rows), ' x ', num2str(cols)]);
    else
        disp(['檔案 ', num2str(i), ' 的 alignment 未對齊或為空。']);
    end
end

%% Remove channel means

% Define electrode names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% Sampling frequency.
fs = 500;

% Define legend labels.
legend_names = {'Alignment data', 'Reduce mean data'};

% Remove the mean from each recording.
for i = 1:numel(EEG_data)

    try
        % Check that aligned data are available.
        if isempty(EEG_data{i}.alignment)
            disp(['無法處理檔案: ', files(i).name, ' (alignment 為空)']);
            continue;  % Skip this file and continue.
        end
    
        % Subtract the column means.
        EEG_data{i}.reducemean = EEG_data{i}.alignment - mean(EEG_data{i}.alignment, 1);
   
    catch ME
        % Report the error and continue.
        warning('Error reducing mean in file %s: %s', files(i).name, ME.message);
    end
end

% Report the number of mean-centered files.
num_files_reducemean = sum(cellfun(@(x) ~isempty(x.reducemean), EEG_data));
disp(['已成功對 ', num2str(num_files_reducemean), ' 個檔案進行 reducemean 處理。']);

% Inspect the processing results.
raw_data = EEG_data{1, 1}.alignment;
processed_data = EEG_data{1, 1}.reducemean;
plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names);

%% Detrend signals

% Define electrode names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% Sampling frequency.
fs = 500;

% Define legend labels.
legend_names = {'Reduce mean data', 'Detrend data'};

% Detrend each recording.
for i = 1:numel(EEG_data)

    try
        % Check for nonempty mean-centered data.
        if isfield(EEG_data{i}, 'reducemean') && ~isempty(EEG_data{i}.reducemean)

        % Apply detrending.
        EEG_data{i}.detrend = detrend(EEG_data{i}.reducemean);

        else
            warning('reducemean field is empty or missing for file %d.', i);
        end

    catch ME
        % Report the error and continue.
        warning('Error detrend in file %s: %s', files(i).name, ME.message);
    end

end

% Report the number of detrended files.
num_files_detrended = sum(cellfun(@(x) isfield(x, 'detrend') && ~isempty(x.detrend), EEG_data));
disp(['已成功對 ', num2str(num_files_detrended), ' 個檔案進行 detrend 處理。']);

% Inspect the processing results.
raw_data = EEG_data{1, 1}.reducemean;
processed_data = EEG_data{1, 1}.detrend;
plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names);

%% Apply notch filtering

% Define electrode names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% Sampling frequency.
fs = 500;

% Define legend labels.
legend_names = {'Detrend data', 'Notch filter data'};

% Design the notch filter.
fc = 60; % 60 Hz notch center frequency; 59-61 Hz interval.
[b, a] = designNotchPeakIIR('CenterFrequency', fc/(fs/2), 'Bandwidth', 2/(fs/2), 'Response', 'notch');

% Apply notch filtering to each recording.
for i = 1:numel(EEG_data)
    try
        % Check that detrended data are available.
        if isfield(EEG_data{i}, 'detrend') && ~isempty(EEG_data{i}.detrend)
                   
        % Filter the selected columns and store the EEG notch-filtered data.
        EEG_data{i}.notchfilter = filtfilt(b, a, EEG_data{i}.detrend);
            
        else
            warning('detrend field is empty or missing for file %d.', i);
        end
        
    catch ME
        % Report the error and continue.
        warning('Error applying notch filter to file %d: %s', i, ME.message);
    end
end

% Report the number of notch-filtered files.
num_files_notchfiltered = sum(cellfun(@(x) isfield(x, 'notchfilter') && ~isempty(x.notchfilter), EEG_data));
disp(['已成功對 ', num2str(num_files_notchfiltered), ' 個檔案進行 notch filter 處理。']);

% Inspect the processing results.
raw_data = EEG_data{1, 1}.detrend;
processed_data = EEG_data{1, 1}.notchfilter;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

%% Apply Butterworth bandpass filtering

% Define electrode names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% Sampling frequency.
fs = 500;

% Define legend labels.
legend_names = {'Notch filter data', 'Butterworth filter data'};

% Design the Butterworth filter.
order = 4; % Filter order.
fc_low = 0.5; % Lower cutoff frequency.
fc_high = 70; % Upper cutoff frequency.
Wn = [fc_low/(fs/2), fc_high/(fs/2)]; % Normalized cutoff frequencies.
[b, a] = butter(order, Wn, 'bandpass'); % Design the bandpass filter.

% Apply Butterworth filtering to each recording.
for i = 1:numel(EEG_data)
    try
        % Check that notch-filtered data are available.
        if isfield(EEG_data{i}, 'notchfilter') && ~isempty(EEG_data{i}.notchfilter)

        % Store the Butterworth-filtered EEG data.
        EEG_data{i}.butterworthfilter = filtfilt(b, a, EEG_data{i}.notchfilter);

        else
            warning('notchfilter field is empty or missing for file %d.', i);
        end
        
    catch ME
        % Report the error and continue.
        warning('Error applying butterworth filter to file %d: %s', i, ME.message);
    end
end

% Report the number of Butterworth-filtered files.
num_files_butterworthfiltered = sum(cellfun(@(x) isfield(x, 'butterworthfilter') && ~isempty(x.butterworthfilter), EEG_data));
disp(['已成功對 ', num2str(num_files_butterworthfiltered), ' 個檔案進行 butterworth filter 處理。']);

% Inspect the processing results.
raw_data = EEG_data{1, 2}.notchfilter;
processed_data = EEG_data{1, 2}.butterworthfilter;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

%% Apply ASR and re-referencing

% Load EEGLAB.
eeglab;

% Define legend labels.
legend_names = {'Butterworth filter data', 'ASR data'};

for i = 1:numel(EEG_data)
    try
        % Check that Butterworth-filtered data are available.
        if ~isempty(EEG_data{i}.butterworthfilter)

            % Transpose the data to the EEGLAB channel-by-sample layout.
            data = EEG_data{i}.butterworthfilter'; 
            sample_rate = 500; % Sampling rate.
            threshold = 10; % ASR threshold; the archived notes list 10 and 20 as alternatives.

            % Run ASR and obtain the baseline and movement outputs.
            [EEG, ASRbase, ASRmove] = ASR(data, sample_rate, threshold, paths.channel_locations);
            
            % Store the ASR baseline and movement data.
            EEG_data{i}.asr = EEG.data';
            
            EEG_data{i}.asrbase = ASRbase.data;
            EEG_data{i}.asrmove = ASRmove.data;

        else
            disp(['File ', num2str(i), ' has no butterworthfiltered data']);
        end
        
    catch ME
        % Report the error and continue.
        warning('Error processing ASR for file %d: %s', i, ME.message);
    end
end

% Report the number of ASR-processed files.
num_files_asrprocessed = sum(cellfun(@(x) isfield(x, 'asr') && ~isempty(x.asr), EEG_data));
disp(['已成功對 ', num2str(num_files_asrprocessed), ' 個檔案進行 ASR 處理。']);

% Inspect the processing results.
raw_data = EEG_data{1, 1}.butterworthfilter;
processed_data = EEG_data{1, 1}.asr;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

% ASR helper function.

function [EEG, ASRbase, ASRmove] = ASR(data, sample_rate, threshold, channel_locations)
    % Import the data.
    EEG = pop_importdata('dataformat', 'array', 'nbchan', 0, 'data', data, 'srate', sample_rate, 'pnts', 0, 'xmin', 0);
    EEG = eeg_checkset(EEG);

    % Load acquisition channel locations.
    EEG = pop_chanedit(EEG, 'load', {channel_locations, 'filetype', 'autodetect'});
    EEG = eeg_checkset(EEG);

    % Calibrate ASR.
    basetimpoint = 10*sample_rate;
    % basetimpoint = min(10 * sample_rate, size(EEG.data, 2)); % Use up to 10 seconds of baseline.
    baselinedata = EEG.data(:, 1:basetimpoint); % Extract baseline data.

    % Compute the ASR state.
    state = asr_calibrate(baselinedata, sample_rate, threshold);
    [EEG.data, state] = asr_process(EEG.data, sample_rate, state, 0.5, 0);
    EEG = eeg_checkset(EEG);

    % Re-reference the data.
    EEG = pop_reref(EEG, []); % Apply automatic re-referencing.
    EEG = eeg_checkset(EEG);

    % Separate baseline and movement data.
    ASRbase = EEG;
    ASRbase.data = EEG.data(:, 1:basetimpoint);
    ASRbase.pnts = size(ASRbase.data, 2);
    ASRbase = eeg_checkset(ASRbase);

    ASRmove = EEG;
    ASRmove.data = EEG.data(:, basetimpoint + 1:end);
    ASRmove.pnts = size(ASRmove.data, 2);
    ASRmove = eeg_checkset(ASRmove);
end

%% Export data to EEGLAB for manual ICA.

% Create a cell array for extracted data.
extracted_data = cell(length(EEG_data), 1);

% Iterate over EEG recordings.
for i = 1:length(EEG_data)

    % Check for the asr field.
    if isfield(EEG_data{i}, 'asr')
        
        % Get the number of ASR data columns.
        num_columns = size(EEG_data{i}.asr, 2);

        % Extract and transpose the selected data.
        data = EEG_data{i}.asr';

        % Store the extracted data in a cell array.
        extracted_data{i} = data;

    else
        % Warn when the asr field is unavailable.
        warning('EEG_data{%d} does not contain ''asr'' field.', i);
        
        % Store an empty array.
        extracted_data{i} = [];
    end
end

% Iterate over the extracted data.
for i = 1:length(extracted_data)
    
    % Generate workspace names such as Data1 and Data2.
    var_name = sprintf('Data%d', i);
    
    % Create workspace variables using eval.
    eval([var_name ' = extracted_data{i};']);
end

% Inspect the created variables.
disp('Extracted data variables:');
whos('Data*');

%% Import .set files after manual ICA in EEGLAB

% Define electrode names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% Sampling frequency.
fs = 500;

% Define legend labels.
legend_names = {'ASR data', 'ICA data'};

% Directory path.
folder_path = paths.ica_dir;

% Find all .set files.
set_files = dir(fullfile(folder_path, '*.set'));

% Read each available .set file.
for i = 1:length(set_files)
    try
        % Get the current filename.
        current_file_name = set_files(i).name;
        
        % Extract the numeric identifier from the filename.
        file_num_str = regexp(current_file_name, '\d+', 'match');
        
        if ~isempty(file_num_str)
            % Convert the file identifier to a number.
            file_num = str2double(file_num_str{1});
            
            % Load the .set file.
            set_file_path = fullfile(set_files(i).folder, current_file_name);
            EEG = pop_loadset('filename', set_file_path);
                        
            % Store the ICA data without overwriting other fields.
            EEG_data{file_num}.ica = EEG;  
            
            fprintf('已加載: %s 並存儲到 EEG_data{%d}.ica\n', current_file_name, file_num);
        else
            fprintf('文件名 %s 中未提取到數字，跳過該文件。\n', current_file_name);
        end
    
    catch ME
        % Report the error and continue.
        fprintf('加載 %s 時發生錯誤: %s\n', current_file_name, ME.message);
    end
end

% Report the number of ICA-processed files.
num_files_asrprocessed = sum(cellfun(@(x) isfield(x, 'ica') && ~isempty(x.ica), EEG_data));
disp(['已成功對 ', num2str(num_files_asrprocessed), ' 個檔案進行 ICA 處理。']);

% Inspect the processing results.
raw_data = EEG_data{1, 1}.asr;
processed_data = EEG_data{1, 1}.ica.data';
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

%% Apply z-score normalization

% Define electrode names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% Sampling frequency.
fs = 500;

% Define legend labels.
legend_names = {'ICA data', 'Zcore data'};

for i = 1:length(EEG_data)
    try
        % Check for the ica and asr fields.
        if isfield(EEG_data{i}, 'ica') && isfield(EEG_data{i}.ica, 'data') && isfield(EEG_data{i}, 'asr')
            data = EEG_data{i}.ica.data;  % Extract the recording.
            zcore_data = zscore(data, 0, 2); % Apply z-scoring along the specified dimension.
            
            EEG_data{i}.zcore = zcore_data';  % Store the result in the legacy zcore field.
        else
            warning('EEG_data{%d} 不包含必要的字段', i);
        end
    catch ME
        % Report the error and continue with the next recording.
        warning('處理 EEG_data{%d} 時發生錯誤：%s', i, ME.message);
        continue;
    end
end

% Report the number of z-scored files.
num_files_asrprocessed = sum(cellfun(@(x) isfield(x, 'zcore') && ~isempty(x.zcore), EEG_data));
disp(['已成功對 ', num2str(num_files_asrprocessed), ' 個檔案進行 Zcore 處理。']);

% Inspect the processing results.
raw_data = EEG_data{1, 1}.ica.data';
processed_data = EEG_data{1, 1}.zcore;
plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names);

%% Inspect signals at each processing stage

% Input data directory.
folder_path = paths.data_root;

% Find matching EEG CSV exports.
files = dir(fullfile(folder_path, 'EEG_path1_*.csv'));

% sample rate
fs = 500; 

% Define processing stages and their fields.
stages = {'alignment', 'reducemean', 'detrend', 'notchfilter', 'butterworthfilter', 'asr'};

for i = 1:numel(EEG_data)
    
    % Check that all processing stages are available.
    missing_stage = false;
    for stage = stages
        if isempty(EEG_data{i}.(stage{1}))
            disp(['檔案: ', files(i).name, ' 缺少 ', stage{1}, ' 的數據']);
            missing_stage = true; 
            break;  % Skip this file if any required stage is missing.
        end
    end
    
    % Check for the ICA field and its data.
    if ~isfield(EEG_data{i}, 'ica') || isempty(EEG_data{i}.ica) || isempty(EEG_data{i}.ica.data)
        disp(['檔案: ', files(i).name, ' 缺少 ICA 的數據']);
        continue;
    end
    
    if missing_stage
        continue;
    end
    
    % Create a figure.
    figure;
    
    % Plot each processing stage.
    for j = 1:length(stages)
        subplot(8, 1, j);  % Eight subplots.
        time_axis = (0:size(EEG_data{i}.(stages{j}), 1)-1) / fs;  % Compute the time axis.
        
        % Average across channels.
        merged_data = mean(EEG_data{i}.(stages{j}), 2);  % Average each sample row across channels.
        
        % Plot the channel-averaged data.
        plot(time_axis, merged_data);
        title([upper(stages{j}(1)), stages{j}(2:end) ' Data'], 'Interpreter', 'none');
        xlabel('Time (s)');  % Label the x-axis with time.
        ylabel('Voltage (µV)');
    end
    
    % Plot the ICA data.
    subplot(8, 1, 7);  % Plot ICA data in subplot 7.
    time_axis_ica = (0:size(EEG_data{i}.ica.data, 2)-1) / fs;  % Compute the ICA time axis.
    
    % Average the ICA channels.
    ica_merged = mean(EEG_data{i}.ica.data, 1);  % Average each sample column across channels.
    
    % Plot the channel-averaged ICA data.
    plot(time_axis_ica, ica_merged);
    title(['Ica Data'], 'Interpreter', 'none');
    xlabel('Time (s)');  % Time-axis label.
    ylabel('Voltage (µV)');
    
    % Plot the z-scored data.
    subplot(8, 1, 8);  % Plot z-scored data in subplot 8.
    time_axis_zcore = (0:size(EEG_data{i}.zcore, 1)-1) / fs;  % Compute the z-scored data's time axis.
    
    % Average the z-scored channels.
    zcore_merged = mean(EEG_data{i}.zcore, 2);  % Average each sample row across channels.
    
    % Plot the channel-averaged z-scored data.
    plot(time_axis_zcore, zcore_merged);
    title(['Zcore Data'], 'Interpreter', 'none');
    xlabel('Time (s)');
    ylabel('Voltage (µV)');
    
    % Adjust the figure layout.
    sgtitle(['EEG Data Processing Stages for file: ', files(i).name], 'Interpreter', 'none');
end

%% EEG band-power topographies (qualitative comparison only)

% Analysis parameters.
fs = 500;
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

band_params = {
    'Delta',     [1 3];
    'Theta',     [4 8];
    'Alpha',     [9 12];
    'Beta',      [13 30];
    'Low Gamma', [32 46];
};

transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% STFT configuration.
stft_config = containers.Map;
for s = 1:length(transient_stages)
    for b = 1:size(band_params,1)
        key = sprintf('%d_%d', s, b);
        center_freq = mean(band_params{b,2});
        ideal_win = round((1 / center_freq) * fs * 4);
        stft_config(key) = struct( ...
            'win_len', ideal_win, ...
            'overlap', floor(ideal_win * 0.5));
    end
end

% Initialize result storage.
num_bands = size(band_params, 1);
num_channels = length(ch_list);
num_subjects = length(EEG_data);
num_clips = length(transient_stages);

avg_power_all = cell(num_clips, num_bands);
for c = 1:num_clips
    for b = 1:num_bands
        avg_power_all{c, b} = [];
    end
end

% Compute STFT band power.
for subj = 1:num_subjects
    clip_cells = EEG_data{subj}.clip;
    if isempty(clip_cells), continue; end
    if length(clip_cells) ~= num_clips
        warning('Trial %d has an unexpected number of phase clips; skipped.', subj);
        continue;
    end

    for clip_idx = 1:num_clips
        segment = clip_cells{clip_idx};
        if isempty(segment) || size(segment,2) < num_channels, continue; end
        [num_samples, ~] = size(segment);

        for band_idx = 1:num_bands
            config_key = sprintf('%d_%d', clip_idx, band_idx);
            stft_params = stft_config(config_key);
            win_len = min(max(stft_params.win_len, 32), num_samples);
            overlap = min(floor(win_len * 0.5), win_len - 1);
            nfft = 2^nextpow2(win_len);

            band_range = band_params{band_idx,2};
            band_power = zeros(num_channels,1);

            for ch = 1:num_channels
                [s, f, ~] = stft(segment(:, ch), fs, ...
                    'Window', hann(win_len), ...
                    'OverlapLength', overlap, ...
                    'FFTLength', nfft);

                band_idx_range = f >= band_range(1) & f <= band_range(2);
                s_power = abs(s(band_idx_range, :)).^2;
                band_power(ch) = mean(sum(s_power,1));
            end

            avg_power_all{clip_idx, band_idx}(:, end+1) = band_power;
        end
    end
end

% Configure output paths and color-scale modes.
base_path = fullfile(paths.results_root, 'topology_map_colorbar_compare');
colorbar_modes = {'global', 'stage', 'band'};

for m = 1:length(colorbar_modes)
    mode_path = fullfile(base_path, colorbar_modes{m});
    if ~exist(mode_path, 'dir')
        mkdir(mode_path);
    end
end

% Compute color-scale limits.
% Global color-scale limits.
all_power_values = [];
for c = 1:num_clips
    for b = 1:num_bands
        mat = avg_power_all{c, b};
        if isempty(mat), continue; end
        all_power_values = [all_power_values; mean(mat,2)];
    end
end
global_clim = [min(all_power_values), max(all_power_values)];

% Color-scale limits for each movement phase.
stage_clims = zeros(num_clips, 2);
for c = 1:num_clips
    all_stage_vals = [];
    for b = 1:num_bands
        mat = avg_power_all{c, b};
        if isempty(mat), continue; end
        all_stage_vals = [all_stage_vals; mean(mat,2)];
    end
    stage_clims(c,:) = [min(all_stage_vals), max(all_stage_vals)];
end

% Color-scale limits for each frequency band.
band_clims = zeros(num_bands, 2);
for b = 1:num_bands
    all_band_vals = [];
    for c = 1:num_clips
        mat = avg_power_all{c, b};
        if isempty(mat), continue; end
        all_band_vals = [all_band_vals; mean(mat,2)];
    end
    band_clims(b,:) = [min(all_band_vals), max(all_band_vals)];
end

% Plot and save figures to the corresponding directories.
for mode = colorbar_modes
    mode = char(mode);
    save_mode_path = fullfile(base_path, mode);

    for c = 1:num_clips
        for b = 1:num_bands
            mat = avg_power_all{c, b};
            if isempty(mat), continue; end
            avg_power = mean(mat, 2);

            % Set the color-scale limits.
            switch mode
                case 'global'
                    clim_val = global_clim;
                case 'stage'
                    clim_val = stage_clims(c,:);
                case 'band'
                    clim_val = band_clims(b,:);
            end

            % Plot the scalp topography.
            fig = figure('Visible', 'off');
            plot_topography(ch_list, avg_power);
            title(sprintf('%s - %s (%s colorbar)', ...
                band_params{b,1}, transient_stages{c}, mode), ...
                'Interpreter', 'none');
            colorbar;
            clim(clim_val);

            % Save the image.
            stage_name = strrep(transient_stages{c}, ' ', '_');
            fname = sprintf('%s_%s_%s.png', stage_name, band_params{b,1}, mode);
            saveas(fig, fullfile(save_mode_path, fname));
            close(fig);
        end
    end
end

%% Fast Fourier transform (spectrum)

% Channel names.
channels = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
            'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
            'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
            'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

% Set the figure output path.
save_path = fullfile(paths.results_root, 'fast_fourier_transform');

% Initialize frequency and power arrays.
for i = 1:length(EEG_data)

    for j = 1:length(EEG_data{i}.clip)
        
        % Extract the data.
        signal = EEG_data{i}.clip{j};
        
        % Determine the signal length.
        N = size(signal, 1); % Number of rows (samples).
        
        % Initialize the spectrum figure.
        figure;
        
        % Compute an FFT for each column.
        for k = 1:size(signal, 2)
            
            % Extract channel k.
            single_channel = signal(:, k);
            
            % Compute the FFT.
            Y = fft(single_channel);
            
            % Compute the frequency axis.
            fs = 500; 
            f = fs*(0:(floor(N/2)))/N;
            
            % Compute power in dB.
            P2 = abs(Y/N); % Two-sided spectrum.
            P1 = P2(1:floor(N/2)+1); % One-sided spectrum.
            P1(2:end-1) = 2*P1(2:end-1); % Scale the amplitude.
            energy_dB = 10*log10(P1); % Convert power to dB.

            % Plot the result.
            subplot(4, 8, k); % Use a 4-by-8 subplot layout.
            plot(f(1:floor(N/2)+1), energy_dB);
            title(['Channel ' channels{k}]); % Label channels by name.
            xlabel('Frequency (Hz)');
            ylabel('Power (dB)');
            xlim([0 100]);
            grid on;
        end
        
        % Set the figure title.
        sgtitle(['FFT for path1\_', sprintf('%02d', i), ' clip ', num2str(j)]);
    
        % Save the figure to the configured path.
        saveas(gcf, fullfile(save_path, ['FFT for path1_', sprintf('%02d', i), ' clip', num2str(j), '.png']));

        % Close the figure to release resources.
        close(gcf);
    end
end

%% Inspect frequency-band spectrograms

% Set the figure output path.
save_path = fullfile(paths.results_root, 'spectrogram_new');

% Band configuration: name, frequency range, window size, overlap, and nfft.
band_params = {
    'Delta',       [1 3],       1000, 967, 1024;
    'Theta',       [4 8],       250,  217, 512;
    'Alpha',       [9 12],      111,  78,  256;
    'Beta',        [13 30],     77,   44,  256;
    'Low Gamma',   [32 46],     66,   33,  256;
};


% Define electrode names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

% Sampling frequency.
fs = 500;

% Process each recording.
for i =1
%for i = 1:length(EEG_data)

    signal = EEG_data{i}.zcore;
    channel_count = size(signal, 2);
    
    % Plot a band spectrogram for each channel.
    for ch = 1:channel_count
        figure;
        sgtitle(['Time-Frequency Analysis for path1\_', sprintf('%02d', i), ' Channel ', ch_list{ch}]);

        for b = 1:size(band_params, 1)
            band_name = band_params{b, 1};
            band_range = band_params{b, 2};
            window_size = band_params{b, 3};
            overlap = band_params{b, 4};
            nfft = band_params{b, 5};

            % Compute the STFT.
            [s, f, t] = stft(signal(:, ch), fs, ...
                'Window', hann(window_size), ...
                'OverlapLength', overlap, ...
                'FFTLength', nfft);

            % Select data within this frequency band.
            band_idx = f >= band_range(1) & f <= band_range(2);
            if ~any(band_idx)
                warning(['Frequency band ', band_name, ' is out of range for channel ', ch_list{ch}]);
                continue;
            end

            s_band = s(band_idx, :);
            f_band = f(band_idx);
            power = abs(s_band).^2;

            % Plot the result.
            subplot(3, 2, b);
            imagesc(t, f_band, 10 * log10(power));
            axis xy;
            xlabel('Time (s)');
            ylabel('Frequency (Hz)');
            title([band_name ' Band']);
            colormap jet;
            colorbar;
        end

        % Save the figure.
        %saveas(gcf, fullfile(save_path, ...
        %sprintf('path1_%02d channel %s.png', i, ch_list{ch})));

        % close(gcf); % Close the figure to release memory.
    end
end

%% Exploratory EEG-only PAC (not EEG-synergy coherence)

% Set the image output directory.
save_path = fullfile(paths.results_root, 'PAC');

if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% Set the frequency range.
phase_freqs = 8:1:12;  % Alpha band (8-12 Hz).
amp_freqs = 30:1:80;   % Gamma band (30-80 Hz).
fs = 500;  % Sampling frequency (Hz).

% Define the 32 channel names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% Call the PAC calculation function.
pac_results = PAC(EEG_data, phase_freqs, amp_freqs, fs, ch_list, save_path, transient_stages);

% Local helper functions.
function pac_results = PAC(EEG_data, phase_freqs, amp_freqs, fs, ch_list, save_path, transient_stages)
    num_data = length(EEG_data);
    num_stages = length(transient_stages);
    pac_results = cell(1, num_stages);

    max_mi_global = -inf;  % Use a shared MI-PAC color scale.

    % First pass: collect PAC results and the maximum MI.
    for stage_idx = 1:num_stages
        max_alpha_power = -inf;
        max_subject_idx = 0;
        max_channel_idx = 0;

        for i = 1:num_data
            num_trials = size(EEG_data{1, i}.clip, 2);
            if stage_idx > num_trials
                continue;
            end

            data = EEG_data{1, i}.clip{1, stage_idx};
            num_channels = size(data, 2);

            for ch = 1:num_channels
                [Pxx, f] = pwelch(data(:, ch), [], [], [], fs);
                alpha_idx = (f >= min(phase_freqs)) & (f <= max(phase_freqs));
                alpha_power = sum(Pxx(alpha_idx));

                if alpha_power > max_alpha_power
                    max_alpha_power = alpha_power;
                    max_subject_idx = i;
                    max_channel_idx = ch;
                end
            end
        end

        fprintf('[%s] Maximum Alpha power: Trial %d, Channel %s\n', ...
            transient_stages{stage_idx}, max_subject_idx, ch_list{max_channel_idx});

        data = EEG_data{1, max_subject_idx}.clip{1, stage_idx};
        signal = data(:, max_channel_idx);
        pac_matrix = compute_pac(signal, phase_freqs, amp_freqs, fs);

        pac_results{stage_idx}.pac_matrix = pac_matrix;
        pac_results{stage_idx}.subject = max_subject_idx;
        pac_results{stage_idx}.trial = stage_idx;
        pac_results{stage_idx}.channel = ch_list{max_channel_idx};

        % Update the maximum MI.
        mi_max = max(pac_matrix.mi(:));
        if mi_max > max_mi_global
            max_mi_global = mi_max;
        end
    end

    % Second pass: plot with shared color limits.
    for stage_idx = 1:num_stages
        result = pac_results{stage_idx};
        plot_pac_results(result.pac_matrix, phase_freqs, amp_freqs, ...
            result.subject, transient_stages{stage_idx}, result.channel, ...
            save_path, max_mi_global);
    end
end

% Compute PAC.
function pac_matrix = compute_pac(signal, phase_freqs, amp_freqs, fs)
    pac_coherence = zeros(length(phase_freqs), length(amp_freqs));
    pac_mi = zeros(length(phase_freqs), length(amp_freqs));

    for p = 1:length(phase_freqs)
        lf = phase_freqs(p);
        lf_signal = bandpass(signal, [max(1, lf - 2), lf + 2], fs);
        phase_signal = angle(hilbert(lf_signal));

        for a = 1:length(amp_freqs)
            hf = amp_freqs(a);
            hf_filtered = bandpass(signal, [hf - lf/2, hf + lf/2], fs);
            hf_amplitude = abs(hilbert(hf_filtered));

            % Coherence
            [Cxy, f] = mscohere(signal, hf_amplitude, [], [], [], fs);
            idx = interp1(f, 1:length(f), lf, 'nearest', 'extrap');

            if ~isnan(idx)
                pac_coherence(p, a) = Cxy(idx);
                pac_mi(p, a) = abs(mean(hf_amplitude .* exp(1i * phase_signal)));
            end
        end
    end

    pac_matrix.coherence = pac_coherence;
    pac_matrix.mi = pac_mi;
end

% Plotting helper.
function plot_pac_results(pac_matrix, phase_freqs, amp_freqs, i, stage_name, channel_name, save_path, max_mi)
    % Coherence-PAC
    figure;
    imagesc(phase_freqs, amp_freqs, pac_matrix.coherence');
    axis xy;
    xlabel('Phase Frequency (Hz)');
    ylabel('Amplitude Frequency (Hz)');
    title(['Coherence-PAC - Subject ', num2str(i), ' ', stage_name, ' (', channel_name, ')']);
    colorbar;
    clim([0, 1]);
    xlim([min(phase_freqs), max(phase_freqs)]);
    ylim([min(amp_freqs), max(amp_freqs)]);
    filename_CO = sprintf('Coherence-PAC_trial%02d_%s.png', i, strrep(stage_name, ' ', '_'));
    saveas(gcf, fullfile(save_path, filename_CO));
    close(gcf);

    % MI-PAC
    figure;
    imagesc(phase_freqs, amp_freqs, pac_matrix.mi');
    axis xy;
    xlabel('Phase Frequency (Hz)');
    ylabel('Amplitude Frequency (Hz)');
    title(['MI-PAC - Subject ', num2str(i), ' ', stage_name, ' (', channel_name, ')']);
    colorbar;
    clim([0, max_mi]);
    xlim([min(phase_freqs), max(phase_freqs)]);
    ylim([min(amp_freqs), max(amp_freqs)]);
    filename_MI = sprintf('MI-PAC_trial%02d_%s.png', i, strrep(stage_name, ' ', '_'));
    saveas(gcf, fullfile(save_path, filename_MI));
    close(gcf);
end

%% Exploratory EEG-only bicoherence

% Set the image output directory.
save_path = fullfile(paths.results_root, 'bicoherence');
if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% Define the 32 channel names.
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

transient_stages = {'Sit_to_Stand', 'Stand_to_Walk', 'Walk_to_Stop'}; % Filename label without spaces.
transient_stages_title = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'}; % Figure title label.

num_stage = length(pac_results);

for stage_idx = 1:num_stage
    % Extract the PAC result fields.
    subject_idx = pac_results{stage_idx}.subject;
    trial_idx = pac_results{stage_idx}.trial;
    ch_name = pac_results{stage_idx}.channel;
    ch_idx = find(strcmp(ch_list, ch_name));

    % Extract data for the selected channel.
    data = EEG_data{1, subject_idx}.clip{1, trial_idx}(:, ch_idx);

    % Set analysis parameters.
    fs = 500;
    segleng = 250;
    segshift = 125;
    epleng = size(data, 1);
    maxfreqbins = floor(segleng / 2);

    % Compute the bispectrum.
    opt = struct;
    [cs, csnr, ~] = data2bs_univar(data, segleng, segshift, epleng, maxfreqbins, opt);

    % Set the frequency limits.
    df = fs / segleng;
    nf = maxfreqbins;
    alpha_idx = round(8 / df) + 1 : round(12 / df) + 1;
    gamma_idx = round(30 / df) + 1 : round(80 / df) + 1;
    alpha_idx(alpha_idx > nf) = [];
    gamma_idx(gamma_idx > nf) = [];

    % Compute bicoherence.
    bicoherence = abs(cs(:, alpha_idx, gamma_idx)) ./ (csnr(:, alpha_idx, gamma_idx) + eps);
    bicoherence_2d = squeeze(bicoherence);

    % Frequency labels.
    alpha_freqs = (alpha_idx - 1) * df;
    gamma_freqs = (gamma_idx - 1) * df;

    % Plot the result.
    figure;
    imagesc(alpha_freqs, gamma_freqs, bicoherence_2d');  % Use gamma frequency on the y-axis.
    set(gca, 'YDir', 'normal');
    xlabel('f1 (Hz)');
    ylabel('f2 (Hz)');
    title(sprintf('Bicoherence - Trial %d - %s (%s)', ...
        subject_idx,transient_stages_title{stage_idx} , ch_name));
    colorbar;
    clim([0 1]);  % Use a shared color range of [0, 1].
    xlim([min(alpha_freqs), max(alpha_freqs)])
    ylim([min(gamma_freqs), max(gamma_freqs)])

    % Save the image using a filename without spaces.
    filename = sprintf('Bicoherence_trial%d_%s.png', ...
         subject_idx,transient_stages{stage_idx});
    saveas(gcf, fullfile(save_path, filename));
    close(gcf);
end

%%
