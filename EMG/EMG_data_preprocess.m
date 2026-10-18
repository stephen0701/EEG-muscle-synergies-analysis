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
files = dir(fullfile(folder_path, 'EMG_path2_*.csv'));

% Preallocate a cell array for the imported files.
EMG_data = cell(1, numel(files));

% Read each file into the cell array.
for i = 1:numel(files)
    try
        % Construct the full file path.
        file_path = fullfile(files(i).folder, files(i).name);
        
        % Read the CSV file with readtable.
        EMG_data_table = readtable(file_path, 'VariableNamingRule', 'preserve');
        
        % Convert the table to an array and store it.
        EMG_data{i}.original = table2array(EMG_data_table);
        
        % Initialize the remaining fields as empty.
        EMG_data{i}.alignment = [];
        EMG_data{i}.detrend = [];
        EMG_data{i}.notchfilter = [];
        EMG_data{i}.frequencydivision = [];
        EMG_data{i}.envelope = [];
        EMG_data{i}.clip = [];
        EMG_data{i}.resampled = [];
        EMG_data{i}.normalize  = [];     
        
    catch ME
        % Report the error and continue.
        warning('Error reading file %s: %s', files(i).name, ME.message);
    end
end

% Report the number of imported files.
num_files_read = sum(cellfun(@(x) ~isempty(x.original), EMG_data));
disp(['已成功讀取 ', num2str(num_files_read), ' 個檔案。']);

%% Align recordings and interpolate missing samples
% Check the recording length before changing the start/end index range.

n1 = 11; % event id column
n2 = 14; % software id column
serial_number = 2; % serial number column
start_event = 130; % Red-light onset.
end_event = 141; % Green-light offset.
columns_to_process = 3:10; % Select columns to process.

% Store discontinuous portions for inspection.
non_continuous_data = {};

% Initialize the start and end indices.
num_files = numel(EMG_data);
start_indices = nan(1, num_files); % Preallocate with NaN.
end_indices = nan(1, num_files);   % Preallocate with NaN.

% Align each recording.
for i = 1:num_files
    try
        EMG_data_array = EMG_data{i}.original;  % Extract the array from the cell.

        % Check that the data are available.
        if isempty(EMG_data_array)
            disp(['檔案無效或未讀取成功: ', files(i).name]);
            continue;  % Skip this file and continue.
        end

        % Find start and end indices using n1.
        logical_start = EMG_data_array(:, n1) == start_event;
        logical_end = EMG_data_array(:, n1) == end_event;

        % Locate the first and last matching indices.
        start_idx = find(logical_start, 1);
        end_idx = find(logical_end, 1, 'last');

        % Retry with n2 when n1 has no start or end match.
        if isempty(start_idx) || isempty(end_idx)
            %(end_idx - start_idx < 11000) || (end_idx - start_idx > 13000)
            disp(['event id 找不到有效的索引，使用 software marker: ', files(i).name]);
            logical_start = EMG_data_array(:, n2) == start_event;
            logical_end = EMG_data_array(:, n2) == end_event;
            start_idx = find(logical_start, 1);
            end_idx = find(logical_end, 1, 'last');
        end

        % Check that both boundary indices were found.
        if isempty(start_idx) || isempty(end_idx)
            %(end_idx - start_idx < 11000) || (end_idx - start_idx > 13000)
            disp(['無法找到有效的開始或結束索引: ', files(i).name]);
            continue;  % Skip this file and continue.
        end

        % Store the start and end indices.
        start_indices(i) = start_idx;
        end_indices(i) = end_idx;

        % Extract data from the first event 130 to the last event 141.
        aligned_data = EMG_data_array(start_idx:end_idx, :);
        EMG_data{i}.alignment = aligned_data;

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

                % Linearly interpolate columns 1 through 8.
                for col = 1:8  % Process columns 1 through 8 only.
                    valid_idx = ~isnan(complete_data(:, col));
                    if sum(valid_idx) < 2
                        disp(['警告: 檔案 ', files(i).name, ' 的列 ', num2str(col), ' 沒有足夠的有效數據進行插值。']);
                        continue;
                    end

                    complete_data(:, col) = interp1(full_range(valid_idx), complete_data(valid_idx, col), full_range, 'linear');
                end

                EMG_data{i}.alignment = complete_data;
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
    time_EMG{i} = cell(1, numel(files));
    time_EMG{i} = EMG_data{i}.alignment(:,1);

    % Retain channel columns only.
    EMG_data{i}.alignment = EMG_data{i}.alignment(:,columns_to_process);
    
    catch ME
        warning('對齊檔案 %s 時發生錯誤: %s', files(i).name, ME.message);
    end
end

% Report the number of aligned files.
num_files_aligned = sum(~isnan(start_indices));
disp(['已成功對齊 ', num2str(num_files_aligned), ' 個檔案。']);

% Report each EMG alignment array's dimensions.
for i = 1:num_files
    if isfield(EMG_data{i}, 'alignment') && ~isempty(EMG_data{i}.alignment)
        [rows, cols] = size(EMG_data{i}.alignment);
        disp(['EMG_data', num2str(i), '.alignment', num2str(rows), ' x ', num2str(cols)]);
    else
        disp(['檔案 ', num2str(i), ' 的 alignment 未對齊或為空。']);
    end
end

%% Detrend signals

% Define electrode names.
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Sampling frequency.
fs = 1000;

% Define legend labels.
legend_names = {'Alignment data', 'Detrend data'};

% Detrend each recording.
for i = 1:numel(EMG_data)

    try
        % Check for nonempty aligned data.
        if isfield(EMG_data{i}, 'alignment') && ~isempty(EMG_data{i}.alignment)

        % Apply detrending.
        EMG_data{i}.detrend = detrend(EMG_data{i}.alignment);
            
        else
            warning('alignment field is empty or missing for file %d.', i);
        end

    catch ME
        % Report the error and continue.
        warning('Error detrend in file %s: %s', files(i).name, ME.message);
    end

end

% Report the number of detrended files.
num_files_detrended = sum(cellfun(@(x) isfield(x, 'detrend') && ~isempty(x.detrend), EMG_data));
disp(['已成功對 ', num2str(num_files_detrended), ' 個檔案進行 detrend 處理。']);

% Inspect the processing results.
raw_data = EMG_data{1, 1}.alignment;
processed_data = EMG_data{1, 1}.detrend;
plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names);

%% Apply notch filtering

% Define electrode names.
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Sampling frequency.
fs = 1000;

% Define legend labels.
legend_names = {'Detrend data', 'Notch filter data'};

% Design the notch filter.
fs = 1000; % sample rate
fc = 60; % 60 Hz notch center frequency; 59-61 Hz interval.
[b, a] = designNotchPeakIIR('CenterFrequency', fc/(fs/2), 'Bandwidth', 2/(fs/2), 'Response', 'notch');

% Apply notch filtering to each recording.
for i = 1:numel(EMG_data)
    try
        % Check that detrended data are available.
        if isfield(EMG_data{i}, 'detrend') && ~isempty(EMG_data{i}.detrend)
                   
        % Filter selected columns and store the EMG notch-filtered data.
        EMG_data{i}.notchfilter = filtfilt(b, a, EMG_data{i}.detrend);
                   
        else
            warning('detrend field is empty or missing for file %d.', i);
        end
        
    catch ME
        % Report the error and continue.
        warning('Error applying notch filter to file %d: %s', i, ME.message);
    end
end

% Report the number of notch-filtered files.
num_files_notchfiltered = sum(cellfun(@(x) isfield(x, 'notchfilter') && ~isempty(x.notchfilter), EMG_data));
disp(['已成功對 ', num2str(num_files_notchfiltered), ' 個檔案進行 notch filter 處理。']);

% Inspect the processing results.
raw_data = EMG_data{1, 1}.detrend;
processed_data = EMG_data{1, 1}.notchfilter;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

%{
%% Apply Butterworth bandpass filtering

% Define electrode names.
ch_list =  {'LGL', 'RGL', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Sampling frequency.
fs = 1000;

% Define legend labels.
legend_names = {'Notch filter data', 'Butterworth filter data'};

% Configure the filter.
filter_type = 'Butterworth filter';

% Design the Butterworth filter.
order = 4; % Filter order.
fs = 1000; % sample rate
fc_low = 40; % Lower cutoff frequency.
fc_high = 450; % Upper cutoff frequency.
Wn = [fc_low/(fs/2), fc_high/(fs/2)]; % Normalized cutoff frequencies.
[b, a] = butter(order, Wn, 'bandpass'); % Design the bandpass filter.

% Apply Butterworth filtering to each recording.
for i = 1:numel(EMG_data)
    try
        % Check that notch-filtered data are available.
        if isfield(EMG_data{i}, 'notchfilter') && ~isempty(EMG_data{i}.notchfilter)

        % Store the Butterworth-filtered data in the specified field.
        EMG_data{i}.butterworthfilter = filtfilt(b, a, EMG_data{i}.notchfilter);
        
        else
            warning('notchfilter field is empty or missing for file %d.', i);
        end
        
    catch ME
        % Report the error and continue.
        warning('Error applying butterworth filter to file %d: %s', i, ME.message);
    end
end

% Report the number of Butterworth-filtered files.
num_files_butterworthfiltered = sum(cellfun(@(x) isfield(x, 'butterworthfilter') && ~isempty(x.butterworthfilter), EMG_data));
disp(['已成功對 ', num2str(num_files_butterworthfiltered), ' 個檔案進行 butterworth filter 處理。']);

% Inspect the processing results.
raw_data = EMG_data{1, 1}.notchfilter;
processed_data = EMG_data{1, 1}.butterworthfilter;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);
%}

%% Separate EMG frequency bands

% Define electrode names.
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Sampling frequency.
fs = 1000;

% Define legend labels.
legend_names = {'Notch filter data', 'frequency division data'};

% Frequency bands in Hz.
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

% Filter configuration.
order = 4;     % Butterworth filter order.
fs = 1000;     % Sampling rate.

% Process each EMG recording.
for i = 1:numel(EMG_data)
    try
        % Check that notch-filtered data are available.
        if isfield(EMG_data{i}, 'notchfilter') && ~isempty(EMG_data{i}.notchfilter)
            raw_data = EMG_data{i}.notchfilter;

            % Initialize storage.
            EMG_data{i}.frequencydivision = cell(1, numel(freq_bands));

            for b = 1:numel(freq_bands)
                % Compute normalized cutoff frequencies.
                fc_low = freq_bands{b}(1);
                fc_high = freq_bands{b}(2);
                Wn = [fc_low, fc_high] / (fs / 2);

                % Design the Butterworth filter.
                [b_butter, a_butter] = butter(order, Wn, 'bandpass');

                % Apply the filter.
                EMG_data{i}.frequencydivision{b} = filtfilt(b_butter, a_butter, raw_data);
            end

        else
            warning('File %d 的 notchfilter 欄位為空或缺失。', i);
        end
    catch ME
        warning('處理檔案 %d 時發生錯誤：%s', i, ME.message);
    end
end

% Report the number of processed files.
num_band_filtered = sum(cellfun(@(x) isfield(x, 'frequencydivision') && ~isempty(x.frequencydivision), EMG_data));
disp(['已成功對 ', num2str(num_band_filtered), ' 個檔案進行 frequency division 處理。']);

% Inspect the processing results.
raw_data = EMG_data{1,1}.notchfilter;% Extract the first recording's Butterworth-filtered data.
% Compare the original signal with the four frequency bands.
for band_idx = 1:4
    processed_data = EMG_data{1,1}.frequencydivision{band_idx};
    % Format the frequency-band label, for example 10-30 Hz.
    band_label = sprintf('%d–%d Hz', freq_bands{band_idx}(1), freq_bands{band_idx}(2));

    % Plot with the band label appended to the title.
    plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names, band_label);
end

%% Exploratory envelope: squared rectification and low-pass filtering

% Define electrode names.
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Sampling frequency.
fs = 1000;

% Define legend labels.
legend_names = {'frequency division data', 'Lowpass envelope'};

fc_low = 9; % Low-pass cutoff frequency (Hz).
[b_env, a_env] = butter(4, fc_low / (fs/2), 'low');

for i = 1:numel(EMG_data)
    try
        if isfield(EMG_data{i}, 'frequencydivision') && ~isempty(EMG_data{i}.frequencydivision)
            EMG_data{i}.envelope_rms = cell(1, numel(EMG_data{i}.frequencydivision));
            for band_idx = 1:numel(EMG_data{i}.frequencydivision)
                % Extract the band-filtered data.
                band_data = EMG_data{i}.frequencydivision{band_idx};

                % Compute the envelope: absolute value, square, then low-pass filter.
                abs_data = abs(band_data);
                squared_data = abs_data .^ 2;
                filtered_data = filtfilt(b_env, a_env, squared_data);

                % Store the result.
                EMG_data{i}.envelope_rms{band_idx} = filtered_data;
            end
        else
            warning('File %d 的 frequencydivision 欄位為空或缺失。', i);
        end
    catch ME
        warning('Error in RMS envelope at file %d: %s', i, ME.message);
    end
end

% Report the number of envelope-processed files.
num_files_enveloped = sum(cellfun(@(x) isfield(x, 'envelope') && ~isempty(x.envelope), EMG_data));
disp(['已成功對 ', num2str(num_files_enveloped), ' 個檔案進行 lowpass envelope 處理。']);

% Inspect the processing results.
for band_idx = 1:4
    raw_data = EMG_data{1,1}.frequencydivision{band_idx};
    processed_data = EMG_data{1,1}.envelope{band_idx};
    % Format the frequency-band label, for example 10-30 Hz.
    band_label = sprintf('%d–%d Hz', freq_bands{band_idx}(1), freq_bands{band_idx}(2));

    % Plot with the band label appended to the title.
    plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names, band_label);
end

%% Report-described Hilbert envelope (review transform dimension before reproduction)

% Define electrode names.
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Sampling frequency.
fs = 1000;

% Define legend labels.
legend_names = {'frequency division data', 'Hilbert envelope'};

for i = 1:numel(EMG_data)
    try
        if isfield(EMG_data{i}, 'frequencydivision') && ~isempty(EMG_data{i}.frequencydivision)
            EMG_data{i}.envelope = cell(1, numel(EMG_data{i}.frequencydivision));
            for band_idx = 1:numel(EMG_data{i}.frequencydivision)
                band_data = EMG_data{i}.frequencydivision{band_idx};

                % Apply the archived Hilbert transform expression; see docs/METHODS.md for the dimension caveat.
                analytic_signal = hilbert(band_data')';  % Operate along the specified array dimension.
                envelope_data = abs(analytic_signal);

                EMG_data{i}.envelope{band_idx} = envelope_data;
            end
        else
            warning('File %d 的 frequencydivision 欄位為空或缺失。', i);
        end
    catch ME
        warning('Error in Hilbert envelope at file %d: %s', i, ME.message);
    end
end

% Report the number of processed files.
num_files_enveloped = sum(cellfun(@(x) isfield(x, 'envelope') && ~isempty(x.envelope), EMG_data));
disp(['已成功對 ', num2str(num_files_enveloped), ' 個檔案進行 hilbert envelope 處理。']);

% Inspect the processing results.
for band_idx = 1:4
    raw_data = EMG_data{1,1}.frequencydivision{band_idx};
    processed_data = EMG_data{1,1}.envelope{band_idx};
    % Format the frequency-band label, for example 10-30 Hz.
    band_label = sprintf('%d–%d Hz', freq_bands{band_idx}(1), freq_bands{band_idx}(2));

    % Plot with the band label appended to the title.
    plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names, band_label);
end

%% Alternative RMS envelope (overwrites the Hilbert envelope if executed)

% Define electrode names.
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Sampling frequency.
fs = 1000;

% Define legend labels.
legend_names = {'frequency division data', 'RMS envelope'};

% RMS window size in samples.
window_size = 50; 

for i = 1:numel(EMG_data)
    try
        if isfield(EMG_data{i}, 'frequencydivision') && ~isempty(EMG_data{i}.frequencydivision)
            EMG_data{i}.envelope_rms = cell(1, numel(EMG_data{i}.frequencydivision));

            for band_idx = 1:numel(EMG_data{i}.frequencydivision)
                band_data = EMG_data{i}.frequencydivision{band_idx};  % (samples x channels)
                rms_data = zeros(size(band_data));

                % Compute the RMS envelope for each channel.
                for ch = 1:size(band_data, 2)
                    rms_data(:, ch) = sqrt(movmean(band_data(:, ch).^2, window_size));
                end

                EMG_data{i}.envelope{band_idx} = rms_data;
            end
        else
            warning('File %d 的 frequencydivision 欄位為空或缺失。', i);
        end
    catch ME
        warning('Error in RMS envelope at file %d: %s', i, ME.message);
    end
end

% Report the number of processed files.
num_files_enveloped = sum(cellfun(@(x) isfield(x, 'envelope') && ~isempty(x.envelope), EMG_data));
disp(['已成功對 ', num2str(num_files_enveloped), ' 個檔案進行 RMS envelope 處理。']);

% Inspect the processing results.
for band_idx = 1:4
    raw_data = EMG_data{1,1}.frequencydivision{band_idx};
    processed_data = EMG_data{1,1}.envelope{band_idx};
    % Format the frequency-band label, for example 10-30 Hz.
    band_label = sprintf('%d–%d Hz', freq_bands{band_idx}(1), freq_bands{band_idx}(2));

    % Plot with the band label appended to the title.
    plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names, band_label);
end

%% Inspect signals at each processing stage

% sample rate
fs = 1000; 

% Define processing stages and their fields.
stages = {'alignment', 'detrend', 'notchfilter', 'butterworthfilter', 'envelope'};

for i = 1:numel(EMG_data)

    % Check that all processing stages are available.
    missing_stage = false;
    for stage = stages
        if isempty(EMG_data{i}.(stage{1}))
            disp(['檔案: ', files(i).name, ' 缺少 ', stage{1}, ' 的數據']);
            missing_stage = true;
            break;  % Skip this file if any required stage is missing.
        end
    end

    if missing_stage
        continue;
    end
    
    % Create a figure.
    figure;
    
    % Plot each processing stage.
    for j = 1:length(stages)
        subplot(5, 1, j);
        time_axis = (0:size(EMG_data{i}.(stages{j}), 1)-1) / fs;  % Compute the time axis.
        
        % Average across channels.
        merged_data = mean(EMG_data{i}.(stages{j}), 2);  % Average each sample row across channels.
        
        % Plot the channel-averaged data.
        plot(time_axis, merged_data);  
        title([upper(stages{j}(1)), stages{j}(2:end), ' Data for file: ', files(i).name], 'Interpreter', 'none');
        xlabel('Time (s)');  % Label the x-axis with time.
        
        % Select the y-axis label for the processing stage.
        if strcmp(stages{j}, 'envelope')
            ylabel('Voltage² (µV²)');  % Use the archived squared-voltage label for the envelope.
        else
            ylabel('Voltage (µV)');  % Use the voltage label for other processing stages.
        end
    end
    
    % Adjust the figure layout.
    sgtitle(['EMG Data Processing Stages for file: ', files(i).name], 'Interpreter', 'none');
end

%% Mark left and right heel strikes on EMG envelopes

% sample rate
fs = 1000; 

% Store channel names.
channel_names = {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Set the figure output path.
save_path = fullfile(paths.results_root, 'envelope');

% Define the left and right heel-strike record counts.
numLHSdata = numel(LHS_data);  % Check that LHS_data is a cell array.
numRHSdata = numel(RHS_data);  % Check that RHS_data is a cell array.

% Plot squared voltage against time.
for i = 1:numel(EMG_data)
    try
        % Check that the EMG trial is valid.
        if isempty(EMG_data{i}) || ~isfield(EMG_data{i}, 'envelope') || isempty(EMG_data{i}.envelope)
            warning('EMG_data %d: alignment 或 envelope 欄位為空或缺失', i);
            continue;
        end

        % Check left and right heel-strike data.
        if i > numLHSdata || i > numRHSdata || isempty(LHS_data{i}) || isempty(RHS_data{i})
            warning('檔案 %d 的 LHS_data 或 RHS_data 無效或為空', i);
            continue;
        end

        % Compute the time vector from the sampling rate.
        time_vector = (0:size(EMG_data{i}.envelope, 1) - 1) / fs;
        
        % Create a new figure.
        figure;
        num_channels = size(EMG_data{i}.envelope, 2); % Get the number of channels.
        
        for j = 1:num_channels
            subplot(num_channels, 1, j); % Create a subplot.
            
            % Plot squared voltage against time.
            plot(time_vector, EMG_data{i}.envelope(:, j));
            
            % Set the title using the channel name.
            title(channel_names{j}); 
            xlabel('時間 (s)'); % X-axis label.
            ylabel('Voltage² (µV²)'); % Y-axis label.
            % xlim([15 20]); % Set the x-axis limits.
            grid on; % Add a grid.
            
            % Mark left and right heel-strike times.
            hold on;
            if ~isempty(LHS_data{i})
                LHS_points = LHS_data{i};
                LHS_indices = round(LHS_points * fs);
                LHS_indices(LHS_indices < 1 | LHS_indices > size(EMG_data{i}.envelope, 1)) = [];
                plot(LHS_points, EMG_data{i}.envelope(LHS_indices, j), 'ro', 'MarkerFaceColor', 'r', 'DisplayName', 'LHS');
            end
            
            if ~isempty(RHS_data{i})
                RHS_points = RHS_data{i};
                RHS_indices = round(RHS_points * fs);
                RHS_indices(RHS_indices < 1 | RHS_indices > size(EMG_data{i}.envelope, 1)) = [];
                plot(RHS_points, EMG_data{i}.envelope(RHS_indices, j), 'go', 'MarkerFaceColor', 'g', 'DisplayName', 'RHS');
            end
            
            legend({channel_names{j}, 'LHS', 'RHS'}, 'Location', 'northeast');
            hold off;
        end
        
        % Add an overall title with sgtitle.
        sgtitle(['EMG envelope for path1\_', sprintf('%02d', i)]);
        
        % Save the figure.
        %saveas(gcf, fullfile(save_path, ['EMG envelope for ', 'path1_', sprintf('%02d', i), '.png']));
        % close(gcf); % Close the figure to release resources.

    catch ME
        % Report the error and continue.
        warning('繪製檔案 %d 的 envelope 時出現錯誤: %s', i, ME.message);
    end
end

%% Resample EMG to the EEG sampling rate

% Define electrode names.
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Define legend labels.
legend_names = {'cliped data', 'resampled data'};

% Frequency bands in Hz.
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

fs_new = 500;  % Resample to the EEG rate of 500 Hz.
fs_old = 1000; % Original EMG sampling rate: 1000 Hz.

for i = 1:length(EMG_data)

    [num_bands, num_clips] = size(EMG_data{i}.clip); % Frequency-band count by clip count.

    for j = 1:num_clips
        for band = 1:num_bands

            % Extract the normalized data.
            clipData = EMG_data{i}.clip{band, j};  % (M x N)

            % Downsample each channel.
            clipData_resampled = resample(clipData, fs_new, fs_old);  % (M' x N)

            % Store the result.
            EMG_data{i}.resampled{band, j} = clipData_resampled;

        end
    end
end

% Report the number of processed files.
num_files_resampled = sum(cellfun(@(x) isfield(x, 'resampled') && ~isempty(x.resampled), EMG_data));
disp(['已成功對 ', num2str(num_files_resampled), ' 個檔案進行 resampled 處理。']);

% Inspect the processing results.
raw_data = EMG_data{1, 1}.clip{1, 1};
processed_data = EMG_data{1, 1}.resampled{1, 1};
fs_old = 1000;
fs_new =500;
% Format the frequency-band label, for example 10-30 Hz.
band_label = sprintf('%d–%d Hz', freq_bands{1}(1), freq_bands{1}(2));

    % Compute the time axis.
    t_old = (0:size(raw_data, 1)-1) / fs_old;
    t_new = (0:size(processed_data, 1)-1) / fs_new;
    
    % Use one subplot for each channel.
    for ch_idx = 1:size(raw_data, 2)
        figure;
    
        % Time-domain data.
        raw_ch = raw_data(:, ch_idx);
        proc_ch = processed_data(:, ch_idx);

        % Upper panel: raw data.
        subplot(2, 1, 1);
        plot(t_old, raw_ch, 'b', 'LineWidth', 1.5);
        title(['Raw Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{1});
        grid on;

        % Lower panel: processed data.
        subplot(2, 1, 2);
        plot(t_new, proc_ch, 'r', 'LineWidth', 1.5);
        title(['Processed Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{2});
        grid on;
    end

%% Normalize phase-segmented EMG

% Define electrode names.
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Define legend labels.
legend_names = {'resampled data', 'normalize data'};

% Frequency bands in Hz.
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

% Choose max, mean, mvc, std, or zscore normalization.
method = 'max'; 

for i = 1:length(EMG_data) % Iterate over EMG recordings.

    [num_bands, num_clips] = size(EMG_data{i}.resampled); % Frequency-band count by clip count.

    for j = 1:num_clips % transient stage

        for band = 1:num_bands % Frequency bands 1 through 4.
            clipData = EMG_data{i}.resampled{band, j}; % Extract the current phase segment.
            
            % Apply normalization and store the result.
            EMG_data{i}.normalize{band, j} = normalizeClipData(clipData, method);
        end

    end
end

% Report the number of processed files.
num_files_normalize = sum(cellfun(@(x) isfield(x, 'normalize') && ~isempty(x.normalize), EMG_data));
disp(['已成功對 ', num2str(num_files_normalize), ' 個檔案進行 normalize 處理。']);

function normalizedData = normalizeClipData(data, method)
    % Normalize each channel of the input matrix.
    % data: input matrix with samples in rows and channels in columns.
    % method: max, mean, mvc, std, or zscore.

    normalizedData = data; % Initialize storage.

    % Iterate over channel columns.
    for k = 1:size(data, 2)
        switch method
            case 'max'
                maxVal = max(data(:, k));
                minVal = min(data(:, k));
                range = maxVal - minVal;
                if range ~= 0
                    normalizedData(:, k) = (data(:, k) - minVal) / range; % Scale to [0, 1].
                else
                    normalizedData(:, k) = data(:, k); % Retain the original data when normalization is undefined.
                end

            case 'mean'
                meanVal = mean(data(:, k));
                range = max(data(:, k)) - min(data(:, k));
                if range ~= 0
                    normalizedData(:, k) = (data(:, k) - meanVal) / range; % Center by the mean and scale by the observed range.
                else
                    normalizedData(:, k) = data(:, k);
                end

            case 'mvc' % Legacy mvc option: normalize by the observed absolute peak.
                maxVal = max(abs(data(:, k))); % Compute the channel's absolute peak.
                if maxVal ~= 0
                    normalizedData(:, k) = data(:, k) / maxVal; % Scale by the observed absolute peak.
                else
                    normalizedData(:, k) = data(:, k); % Retain the original data when the peak is zero.
                end

            case 'std'
                stdVal = std(data(:, k));
                if stdVal ~= 0
                    normalizedData(:, k) = data(:, k) / stdVal; % Scale by the channel standard deviation.
                else
                    normalizedData(:, k) = data(:, k);
                end

            case 'zscore'
                normalizedData(:, k) = zscore(data(:, k)); % Apply zscore.

            otherwise
                error('無效的標準化方法。請選擇 "max", "mean", "mvc", "std", "zscore"');
        end
    end
end

% Inspect the processing results.
raw_data = EMG_data{1, 1}.clip{1, 1};
processed_data = EMG_data{1, 1}.normalize{1, 1};
fs_old = 1000;
fs_new =500;
% Format the frequency-band label, for example 10-30 Hz.
band_label = sprintf('%d–%d Hz', freq_bands{1}(1), freq_bands{1}(2));

    % Compute the time axis.
    t_old = (0:size(raw_data, 1)-1) / fs_old;
    t_new = (0:size(processed_data, 1)-1) / fs_new;
    
    % Use one subplot for each channel.
    for ch_idx = 1:size(raw_data, 2)
        figure;
    
        % Time-domain data.
        raw_ch = raw_data(:, ch_idx);
        proc_ch = processed_data(:, ch_idx);

        % Upper panel: raw data.
        subplot(2, 1, 1);
        plot(t_old, raw_ch, 'b', 'LineWidth', 1.5);
        title(['Raw Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{1});
        grid on;

        % Lower panel: processed data.
        subplot(2, 1, 2);
        plot(t_new, proc_ch, 'r', 'LineWidth', 1.5);
        title(['Processed Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{2});
        grid on;
    end

%% NMF alternative A: sparsenmfnnls (choose one NMF section)

% Set the candidate K range.
k_range = 1:8; % Evaluate the archived candidate range.

% Configure sparsenmfnnls.
option.beta = 0.2;      % Regularization parameter for Y sparsity.
option.eta = 0.05;      % Regularization parameter for A.
option.iter = 1000;     % Iteration limit.
option.dis = false;     % Suppress solver messages.
option.residual = 1e-6; % Residual convergence tolerance.
option.tof = 1e-6;      % Objective-difference tolerance.

% Initialize the result structure.
nmf_results = cell(length(EMG_data), 1);
VAF_results = cell(length(EMG_data), 1);

for i = 1:length(EMG_data)
    [num_bands, num_clips] = size(EMG_data{i}.normalize);
    
    nmf_results{i} = cell(num_bands, num_clips);
    VAF_results{i} = cell(num_bands, num_clips);
    
    for band = 1:num_bands
        for clip = 1:num_clips
            data = EMG_data{i}.normalize{band, clip}';

            if isempty(data) || any(data(:) < 0)
                fprintf('跳過空或含負值數據: EMG_data{%d}.normalize{%d, %d}\n', i, band, clip);
                continue;
            end

            VAF_per_k = zeros(1, length(k_range));
            nmf_per_k = cell(1, length(k_range));

            for k_idx = 1:length(k_range)
                k = k_range(k_idx);

                try
                    % Call the sparse NMF solver.
                    [A, Y, numIter, tElapsed, finalResidual] = sparsenmfnnls(data, k, option);
                catch ME
                    fprintf('sparsenmfnnls 失敗: EMG_data{%d}.normalize{%d, %d}, K=%d\n', i, band, clip, k);
                    disp(ME.message);
                    continue;
                end

                reconstructed = A * Y;

                % Compute VAF.
                SST = sum(sum((data - mean(data, 'all')).^2));  % Total sum of squares.
                SSE = sum(sum((data - reconstructed).^2));      % Residual sum of squares.
                VAF_per_k(k_idx) = 1 - (SSE / SST);

                % Compute the relative residual.
                data_norm = norm(data, 'fro');  % Frobenius norm of the input.
                relative_residual = finalResidual / data_norm;

                % Store the results.
                nmf_per_k{k_idx}.A = A;
                nmf_per_k{k_idx}.Y = Y;
                nmf_per_k{k_idx}.numIter = numIter;
                nmf_per_k{k_idx}.tElapsed = tElapsed;
                nmf_per_k{k_idx}.finalResidual = finalResidual;
                nmf_per_k{k_idx}.relativeResidual = relative_residual;  
            end

            nmf_results{i}{band, clip} = nmf_per_k;
            VAF_results{i}{band, clip}.VAF = VAF_per_k;
            VAF_results{i}{band, clip}.deltaVAF = diff(VAF_per_k);
        end
    end
end

%% NMF alternative B: nmfnnls (overwrites alternative A if executed)

% Set the candidate K range.
k_range = 1:8; % Evaluate the archived candidate range.

% Configure nmfnnls.
option.iter = 1000;     % Maximum iteration count.
option.dis = false;     % Suppress intermediate messages.
option.residual = 1e-6; % Residual convergence tolerance.
option.tof = 1e-6;      % Objective-difference tolerance.

% Initialize the result structure.
nmf_results = cell(length(EMG_data), 1);
VAF_results = cell(length(EMG_data), 1);

for i = 1:length(EMG_data)
    [num_bands, num_clips] = size(EMG_data{i}.normalize);
    
    nmf_results{i} = cell(num_bands, num_clips);
    VAF_results{i} = cell(num_bands, num_clips);
    
    for band = 1:num_bands
        for clip = 1:num_clips
            data = EMG_data{i}.normalize{band, clip}';

            if isempty(data) || any(data(:) < 0)
                fprintf('跳過空或含負值數據: EMG_data{%d}.normalize{%d, %d}\n', i, band, clip);
                continue;
            end

            VAF_per_k = zeros(1, length(k_range));
            nmf_per_k = cell(1, length(k_range));

            for k_idx = 1:length(k_range)
                k = k_range(k_idx);

                try
                    % Use nmfnnls without the sparsity constraint.
                    [A, Y, numIter, tElapsed, finalResidual] = nmfnnls(data, k, option);
                catch ME
                    fprintf('nmfnnls 失敗: EMG_data{%d}.normalize{%d, %d}, K=%d\n', i, band, clip, k);
                    disp(ME.message);
                    continue;
                end

                reconstructed = A * Y;

                % Compute VAF.
                SST = sum(sum((data - mean(data, 'all')).^2));  % Total sum of squares.
                SSE = sum(sum((data - reconstructed).^2));      % Residual sum of squares.
                VAF_per_k(k_idx) = 1 - (SSE / SST);

                % Compute the relative residual.
                data_norm = norm(data, 'fro');
                relative_residual = finalResidual / data_norm;

                % Store the results.
                nmf_per_k{k_idx}.A = A;
                nmf_per_k{k_idx}.Y = Y;
                nmf_per_k{k_idx}.numIter = numIter;
                nmf_per_k{k_idx}.tElapsed = tElapsed;
                nmf_per_k{k_idx}.finalResidual = finalResidual;
                nmf_per_k{k_idx}.relativeResidual = relative_residual;
            end

            nmf_results{i}{band, clip} = nmf_per_k;
            VAF_results{i}{band, clip}.VAF = VAF_per_k;
            VAF_results{i}{band, clip}.deltaVAF = diff(VAF_per_k);
        end
    end
end

%% Select the synergy count for each movement phase

% Set analysis parameters.
k_range = 1:8;
threshold_vaf = 0.9;
num_shuffle = 100;
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};
num_stages = length(transient_stages);

% Initialize storage.
K_candidates_by_stage = cell(1, num_stages);
threshold_deltaVAF_all = cell(length(EMG_data), 1);

% First pass: collect valid candidate K values.
for i = 1:length(EMG_data)
    [row_n, col_n] = size(EMG_data{i}.normalize);
    threshold_deltaVAF_all{i} = NaN(row_n, col_n);

    for j = 1:row_n
        for k = 1:col_n
            if isempty(VAF_results{i}{j, k})
                continue;
            end

            VAF_per_k = VAF_results{i}{j, k}.VAF;
            deltaVAF = VAF_results{i}{j, k}.deltaVAF;

            % Compute the shuffle-based threshold.
            all_deltas = [];
            for s = 1:num_shuffle
                shuffled = VAF_per_k(randperm(length(VAF_per_k)));
                all_deltas = [all_deltas, diff(shuffled)];
            end
            % Original heuristic retained. This is NOT a 75th percentile.
            % The report/code discrepancy is documented in docs/METHODS.md.
            threshold_deltaVAF = abs(0.75 * median(all_deltas));
            threshold_deltaVAF_all{i}(j, k) = threshold_deltaVAF;

            % Select K values satisfying both criteria.
            valid_Ks = k_range((VAF_per_k >= threshold_vaf) & ([0, deltaVAF] >= threshold_deltaVAF));

            % Store the result for the corresponding phase.
            if k <= num_stages && ~isempty(valid_Ks)
                K_candidates_by_stage{k} = [K_candidates_by_stage{k}, valid_Ks(1)]; % Use the smallest valid K.
            end
        end
    end
end

% Second pass: compute the modal K for each phase.
mode_K_by_stage = NaN(1, num_stages);
fprintf('\n==== 每個 transient stage 的最佳 K 值統計 ====\n');
for s = 1:num_stages
    k_vals = K_candidates_by_stage{s};
    if isempty(k_vals)
        fprintf('Transient Stage: %s -> 沒有有效的 K 值\n', transient_stages{s});
    else
        mode_K = mode(k_vals);
        fprintf('Transient Stage: %s\n', transient_stages{s});
        fprintf('  - 最小 K 值: %d\n', min(k_vals));
        fprintf('  - 最大 K 值: %d\n', max(k_vals));
        fprintf('  - 平均 K 值: %.2f\n', mean(k_vals));
        fprintf('  - 眾數 K 值: %d\n', mode_K);
        mode_K_by_stage(s) = mode_K;
    end
end

% Third pass: select NMF results using the phase-specific modal K.
best_nmf = cell(length(EMG_data), 1);

for i = 1:length(EMG_data)
    [row_n, col_n] = size(EMG_data{i}.normalize);
    best_nmf{i} = cell(row_n, col_n);

    for j = 1:row_n
        for k = 1:col_n
            if k <= num_stages && ~isempty(nmf_results{i}{j, k}) && ~isnan(mode_K_by_stage(k))
                best_K = mode_K_by_stage(k);
                best_K_idx = find(k_range == best_K, 1);

                if best_K_idx <= length(nmf_results{i}{j, k})
                    best_nmf{i}{j, k}.K = best_K;
                    best_nmf{i}{j, k}.A = nmf_results{i}{j, k}{best_K_idx}.A;
                    best_nmf{i}{j, k}.Y = nmf_results{i}{j, k}{best_K_idx}.Y;
                    best_nmf{i}{j, k}.finalResidual = nmf_results{i}{j, k}{best_K_idx}.finalResidual;
                    best_nmf{i}{j, k}.relativeResidual = nmf_results{i}{j, k}{best_K_idx}.relativeResidual;  
                else
                    fprintf('找不到 nmf_results{%d}{%d,%d} 的 K = %d 結果\n', i, j, k, best_K);
                    best_nmf{i}{j, k} = [];
                end
            else
                best_nmf{i}{j, k} = [];
            end
        end
    end
end


% Aggregate relative residuals.
all_relative_residuals = [];

for i = 1:length(best_nmf)
    for j = 1:size(best_nmf{i}, 1)
        for k = 1:size(best_nmf{i}, 2)
            if ~isempty(best_nmf{i}{j, k}) && isfield(best_nmf{i}{j, k}, 'relativeResidual')
                rr = best_nmf{i}{j, k}.relativeResidual;
                if ~isempty(rr) && ~isnan(rr)
                    all_relative_residuals(end+1) = rr; 
                end
            end
        end
    end
end

% Compute the mean.
if ~isempty(all_relative_residuals)
    mean_relative_residual = mean(all_relative_residuals);
    fprintf('平均 relative residual：%.6f\n', mean_relative_residual);
else
    warning('沒有找到任何 relativeResidual 資料可以計算平均。');
end

%% Plot synergy-count selection diagnostics

% Set analysis parameters.
k_range = 1:8;

% Set the figure output path.
save_path = fullfile(paths.results_root, 'EMG_synergy_vs_VAF');

% Create the output directory if needed.
if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% Frequency-band and movement-phase labels.
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

for subj = 1:length(VAF_results)

    % Check that the nested cell array is nonempty.
    if isempty(VAF_results{subj}) || ~iscell(VAF_results{subj})
        fprintf('跳過無效 subject：VAF_results{%d}\n', subj);
        continue;
    end

    % Get the nested cell dimensions: frequency rows by phase columns.
    [num_freq, num_stage] = size(VAF_results{subj});

    for i = 1:num_freq  % freq band
        for j = 1:num_stage  % transient stage

            % Check for empty results.
            if isempty(VAF_results{subj}{i, j})
                fprintf('跳過無效 VAF 結果: VAF_results{%d}{%d,%d}\n', subj, i, j);
                continue;
            end

            % Get the current phase name.
            stage_name = transient_stages{j};
            % Remove spaces from the phase name for filenames.
            stage_name_clean = regexprep(stage_name, '\s+', '_');

            % Extract the result data.
            VAF = VAF_results{subj}{i, j}.VAF;  
            deltaVAF = VAF_results{subj}{i, j}.deltaVAF;
            threshold_deltaVAF = threshold_deltaVAF_all{subj}(i, j);

            % Plot the results.
            figure;

            % First panel: VAF.
            subplot(2, 1, 1);
            plot(k_range, VAF, '-o', 'LineWidth', 1.5, 'MarkerSize', 6);
            hold on;
            hline1 = yline(0.9, '--r', 'LineWidth', 1.5); 
            hold off;
            title('Synergy Count vs VAF', 'FontSize', 14);
            xlabel('Synergy Count (K)', 'FontSize', 12);
            ylabel('VAF', 'FontSize', 12);
            xticks(k_range);
            grid on;
            legend(hline1, 'VAF = 0.9', 'Location', 'southeast');
            
            % Label successive K transitions for delta-VAF.
            delta_labels = arrayfun(@(k) sprintf('%d→%d', k, k+1), k_range(1:end-1), 'UniformOutput', false);

            % Second panel: delta-VAF.
            subplot(2, 1, 2);
            plot(k_range(2:end), deltaVAF, '-o', 'LineWidth', 1.5, 'MarkerSize', 6, 'Color', 'b');
            hold on;
            hline2 = yline(threshold_deltaVAF, '--r', 'LineWidth', 1.5);
            hold off;
            title('Synergy Count vs ΔVAF', 'FontSize', 14);
            xlabel('Synergy Pair (K → K+1)', 'FontSize', 12);
            ylabel('ΔVAF', 'FontSize', 12);
            xticks(k_range(2:end));
            xticklabels(delta_labels);  % Label the x-axis with K-to-K+1 transitions.
            grid on;
            legend(hline2, sprintf('Shuffle heuristic (%.4f)', threshold_deltaVAF), 'Location', 'northeast');

            % Overall title.
            sgtitle(sprintf('path2_%02d - %s - %d-%d Hz' ,  ...
                subj, stage_name, freq_bands{i}(1), freq_bands{i}(2)), ...
                'Interpreter', 'none');

            % Replace spaces with underscores in the output filename.
            save_filename = sprintf('path2_%02d_%s_frequency_%d-%dHz.png', ...
                subj, stage_name_clean, freq_bands{i}(1), freq_bands{i}(2));

            % Construct the full output path.
            save_fullpath = fullfile(save_path, save_filename);

            % Save the figure file.
            saveas(gcf, save_fullpath);
            close(gcf);

        end
    end
end

%% Match repeated-trial synergies: cosine k-means and one-to-one matching

% Set the figure output path.
save_path = fullfile(paths.results_root, 'EMG_synergy_distance_matrix_path2');

% Create the output directory if needed.
if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% Frequency bands.
freq_bands = {
    [10, 30],
    [30, 45],
    [45, 120],
    [135, 280]
};

% Movement phases.
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

synergy_matching = cell(length(freq_bands), length(transient_stages), length(best_nmf));
consensus_synergies = cell(length(freq_bands), length(transient_stages));
avg_silhouette_scores = nan(length(freq_bands), length(transient_stages));

% Initialize storage.
for i = 1:length(best_nmf)
    for band = 1:length(freq_bands)
        for clip = 1:length(transient_stages)
            EMG_data{i}.reordered.A{band, clip} = [];
            EMG_data{i}.reordered.Y{band, clip} = [];
        end
    end
end

for clip = 1:length(transient_stages)
    common_K = mode_K_by_stage(clip);  % Selected synergy count for this clip.

    for band = 1:length(freq_bands)
        all_synergies = [];
        subject_synergies = {};
        subject_activations = {};

        % Pool synergy vectors across trials.
        for i = 1:length(best_nmf)
            if isempty(best_nmf{i}) || isempty(best_nmf{i}{band, clip}) || ...
               ~isfield(best_nmf{i}{band, clip}, 'A') || ~isfield(best_nmf{i}{band, clip}, 'Y')
                fprintf('Trial %d 無 band=%d clip=%d 的 best_nmf 資料，跳過。\n', ...
                    i, band, clip);
                continue;
            end

            A = best_nmf{i}{band, clip}.A;
            Y = best_nmf{i}{band, clip}.Y;

            if isempty(A) || size(A, 2) ~= common_K
                fprintf('Trial %d 的 A 大小不符合 common_K，跳過。\n', i);
                continue;
            end

            A = A ./ vecnorm(A);  % L2 normalization
            subject_synergies{i} = A;
            subject_activations{i} = Y;
            all_synergies = [all_synergies; A'];
        end

        if size(all_synergies, 1) < common_K
            warning('Band %d Clip %d synergy 數不足以建立共識，跳過。\n', band, clip);
            continue;
        end

        % Find consensus synergies with k-means clustering.
        [cluster_idx, cluster_centers] = kmeans(all_synergies, common_K, ...
            'Distance', 'cosine', 'Replicates', 20, 'MaxIter', 10000);

        consensus_synergies{band, clip} = cluster_centers;

        silhouette_scores = silhouette(all_synergies, cluster_idx, 'cosine');
        avg_silhouette = mean(silhouette_scores);
        avg_silhouette_scores(band, clip) = avg_silhouette;

        % Compute trial distance matrices using reordered A.
        dist_mats = zeros(common_K, common_K, length(subject_synergies));
        valid_subjects = 0;

        for i = 1:length(subject_synergies)
            A = subject_synergies{i};
            Y = subject_activations{i};
            if isempty(A)
                continue;
            end

            % Match trial synergies to consensus centers.
            A_t = A';  % K × muscles
            dist_tmp = pdist2(A_t, cluster_centers, 'cosine');  % K × K
            matching = matchpairs(dist_tmp, 1);  % K x 2

            % Reorder A and Y to the consensus order.
            reordered_A = zeros(size(A,1), common_K);  % muscles × K
            reordered_Y = zeros(common_K, size(Y,2));  % K × time

            for m = 1:common_K
                idx = find(matching(:, 2) == m);
                if ~isempty(idx)
                    reordered_A(:, m) = A(:, matching(idx, 1));
                    reordered_Y(m, :) = Y(matching(idx, 1), :);
                end
            end

            % Store the reordered data.
            EMG_data{i}.reordered.A{band, clip} = reordered_A;
            EMG_data{i}.reordered.Y{band, clip} = reordered_Y;
            synergy_matching{band, clip, i} = matching;

            % Compute distances from reordered_A.
            reordered_A_t = reordered_A';  % K × muscles
            dist_mat = pdist2(reordered_A_t, cluster_centers, 'cosine');  % K × K

            dist_mats(:, :, i) = dist_mat;
            valid_subjects = valid_subjects + 1;
        end

        if valid_subjects == 0
            warning('Band %d Clip %d 沒有有效 subject 進行平均距離矩陣。\n', band, clip);
            continue;
        end

        % Average the distance matrices.
        mean_dist_mat = mean(dist_mats(:, :, 1:valid_subjects), 3);

        % Plot the mean distance matrix.
        figure;
        imagesc(mean_dist_mat);
        colorbar;
        clim([0 1]);  

        band_range = freq_bands{band};
        stage_name = transient_stages{clip};
        title_str = sprintf('Mean Distance Matrix - %s - %d-%d Hz', ...
            stage_name, band_range(1), band_range(2));
        title(title_str, 'FontSize', 12);

        xlabel('Consensus Synergies');
        ylabel('Trial Synergies');
        set(gca, 'XTick', 1:common_K, 'YTick', 1:common_K);

        % Save the figure file.
        stage_str = strrep(stage_name, ' ', '_');
        filename = sprintf('mean_distance_matrix_%d-%dHz_%s.png', ...
            band_range(1), band_range(2), stage_str);
        saveas(gcf, fullfile(save_path, filename));
        close(gcf);
    end
end

%% Plot trial synergy coefficients and activations

% Figure output directory.
save_folder = fullfile(paths.results_root, 'EMG_synergy_individual');
if ~exist(save_folder, 'dir')
    mkdir(save_folder);
end

% Muscle labels.
muscle_labels = {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Frequency bands.
freq_bands = {
    [10, 30];
    [30, 45];
    [45, 120];
    [135, 280];
};

% Movement-phase names.
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% Interpolation length.
resample_len = 1000;
x_target = linspace(0, 1, resample_len);

for stage_idx = 1:length(transient_stages)
    stage_name = transient_stages{stage_idx};
    clip = stage_idx;
    common_K = mode_K_by_stage(stage_idx);  % Phase-specific synergy count.

    for band_idx = 1:length(freq_bands)
        freq_range = freq_bands{band_idx};

        for subj_idx = 1:length(EMG_data)
            A = EMG_data{subj_idx}.reordered.A{band_idx, clip};
            Y = EMG_data{subj_idx}.reordered.Y{band_idx, clip};

            % Check data validity.
            if isempty(A) || isempty(Y)
                fprintf('Trial %d 無資料，跳過。\n', subj_idx);
                continue;
            end

            if size(A, 1) ~= length(muscle_labels) || size(A, 2) ~= common_K || size(Y, 1) ~= common_K
                fprintf('Trial %d A 或 Y 維度與 K=%d 不符，跳過。\n', subj_idx, common_K);
                continue;
            end

            % Interpolate Y.
            x_orig = linspace(0, 1, size(Y, 2));
            Y_interp = zeros(common_K, resample_len);
            for k = 1:common_K
                Y_interp(k, :) = interp1(x_orig, Y(k, :), x_target, 'linear');
            end

            % Plot the result.
            time_percentage = linspace(0, 100, resample_len);
            colors = lines(common_K);
            figure('Position', [100, 100, 1200, 180 * common_K]);

            for k = 1:common_K
                subplot(common_K, 2, (k - 1) * 2 + 1);
                b = bar(A(:, k), 'FaceColor', 'flat');
                b.CData = repmat(colors(k, :), length(muscle_labels), 1);
                title(sprintf('Synergy %d Coefficients', k));
                xlabel('Muscle');
                ylabel('Value');
                xticks(1:length(muscle_labels));
                xticklabels(muscle_labels);
                ylim([0, max(A(:)) * 1.2]);
                grid on;

                subplot(common_K, 2, (k - 1) * 2 + 2);
                plot(time_percentage, Y_interp(k, :), 'LineWidth', 1.5, 'Color', colors(k, :));
                title(sprintf('Synergy %d Activation', k));
                xlabel('Movement Time (%)');
                ylabel('Activation');
                xlim([0, 100]);
                ylim([0, max(Y_interp(:)) * 1.2]);
                grid on;
            end

            sgtitle(sprintf('Trial %02d - %s - %d-%d Hz - K=%d', ...
                subj_idx, stage_name, freq_range(1), freq_range(2), common_K), ...
                'Interpreter', 'none');

            % Save the image.
            save_filename = sprintf('Trial%02d_%s_%d-%dHz.png', ...
                subj_idx, strrep(stage_name, ' ', '_'), freq_range(1), freq_range(2));
            save_path = fullfile(save_folder, save_filename);
            saveas(gcf, save_path);
            close(gcf);
        end
    end
end

%% Plot mean synergy coefficients and activations

% Figure output directory.
save_folder = fullfile(paths.results_root, 'EMG_synergy_A_Y_path2');
if ~exist(save_folder, 'dir')
    mkdir(save_folder);
end

% Muscle labels.
muscle_labels = {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% Frequency bands.
freq_bands = {
    [10, 30];
    [30, 45];
    [45, 120];
    [135, 280];
};

% Movement-phase names.
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% Initialize results by frequency band and movement phase.
Y_avg_all = cell(length(freq_bands), length(transient_stages));
A_avg_all = cell(length(freq_bands), length(transient_stages));

for stage_idx = 1:length(transient_stages)
    stage_name = transient_stages{stage_idx};
    clip = stage_idx;
    common_K = mode_K_by_stage(stage_idx);  % Common synergy count for this phase.

    for band_idx = 1:length(freq_bands)
        freq_range = freq_bands{band_idx};
        A_all = {};
        Y_all = {};
        subject_indices = [];

        for i = 1:length(EMG_data)
            A = EMG_data{i}.reordered.A{band_idx, clip};
            Y = EMG_data{i}.reordered.Y{band_idx, clip};

            if isempty(A) || isempty(Y)
                fprintf('Trial %d 無資料，跳過。\n', i);
                continue;
            end

            if size(A, 1) ~= length(muscle_labels) || size(A, 2) ~= common_K || size(Y, 1) ~= common_K
                fprintf('Trial %d A 或 Y 維度與 K=%d 不符，跳過。\n', i, common_K);
                continue;
            end

            A_all{end+1} = A;
            Y_all{end+1} = Y;
            subject_indices(end+1) = i;
        end

        if isempty(A_all)
            fprintf('Stage: %s, Band: %d-%dHz 無有效資料，跳過。\n', ...
                stage_name, freq_range(1), freq_range(2));
            continue;
        end

        % Interpolate and average Y over 500 normalized time points.
        resample_len = 500;
        Y_interp_all = zeros(common_K, resample_len, length(Y_all));

        for j = 1:length(Y_all)
            Y = Y_all{j};
            x_orig = linspace(0, 1, size(Y, 2));
            x_target = linspace(0, 1, resample_len);
            for k = 1:common_K
                Y_interp_all(k, :, j) = interp1(x_orig, Y(k, :), x_target, 'linear');
            end
        end

        Y_avg = mean(Y_interp_all, 3);  % Mean activation matrix.
        Y_avg_all{band_idx, stage_idx} = Y_avg;

        % Compute the mean and standard deviation of A.
        A_stack = cat(3, A_all{:});
        A_avg = mean(A_stack, 3);
        A_std = std(A_stack, 0, 3);

        A_avg_all{band_idx, stage_idx} = struct( ...
            'A_avg', A_avg, ...
            'A_std', A_std, ...
            'subject_indices', subject_indices ...
        );

        % Plot the results.
        time_percentage = linspace(0, 100, size(Y_avg, 2));
        colors = lines(common_K);
        figure('Position', [100, 100, 1200, 180 * common_K]);

        for k = 1:common_K
            subplot(common_K, 2, (k - 1) * 2 + 1);
            b = bar(A_avg(:, k), 'FaceColor', 'flat');
            b.CData = repmat(colors(k, :), length(muscle_labels), 1);
            hold on;
            errorbar(1:length(muscle_labels), A_avg(:, k), A_std(:, k), 'k.', 'LineWidth', 1);
            hold off;
            title(sprintf('Synergy %d Coefficients (Avg ± SD)', k));
            xlabel('Muscle');
            ylabel('Value');
            xticks(1:length(muscle_labels));
            xticklabels(muscle_labels);
            ylim([0, 1]);
            grid on;

            subplot(common_K, 2, (k - 1) * 2 + 2);
            plot(time_percentage, Y_avg(k, :), 'LineWidth', 1.5, 'Color', colors(k, :));
            title(sprintf('Synergy %d Activation (Average)', k));
            xlabel('Movement Time (%)');
            ylabel('Activation');
            xlim([0, 100]);
            ylim([0, max(Y_avg(:)) * 1.2]);
            grid on;
        end

        sgtitle(sprintf('Average - %s - %d-%d Hz - K=%d - N=%d trials (one participant)', ...
            stage_name, freq_range(1), freq_range(2), common_K, length(subject_indices)), ...
            'Interpreter', 'none');

        save_filename = sprintf('Average_%s_%d-%dHz.png', ...
            strrep(stage_name, ' ', '_'), freq_range(1), freq_range(2));
        save_path = fullfile(save_folder, save_filename);
        saveas(gcf, save_path);
        close(gcf);
    end
end

% Store A_avg_all and Y_avg_all.
save(fullfile(save_folder, 'EMG_synergy_summary.mat'), 'A_avg_all', 'Y_avg_all');

%% Inspect muscle-synergy spectrograms

% Movement-phase names.
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% EMG frequency bands.
freq_bands = {
    [10, 30];
    [30, 45];
    [45, 120];
    [135, 280];
};

% Sampling frequency.
fs = 1000;

% Output path.
output_folder = fullfile(paths.results_root, 'spectrogram');
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
end

% Configure windows from each band's center frequency.
stft_config = containers.Map;
for s = 1:length(transient_stages)
    for b = 1:size(freq_bands,1)
        key = sprintf('%d_%d', s, b);
        center_freq = mean(freq_bands{b});
        ideal_win = round((1 / center_freq) * fs * 4); % Four cycles.
        stft_config(key) = struct( ...
            'win_len', ideal_win, ...
            'overlap', floor(ideal_win * 0.5));
    end
end

% Compute global color-scale limits.
global_min = inf;
global_max = -inf;

for band = 1:size(freq_bands, 1)
    for stage = 1:size(Y_avg_all, 2)
        Y_avg = Y_avg_all{band, stage};
        [K, ~] = size(Y_avg);
        key = sprintf('%d_%d', stage, band);
        cfg = stft_config(key);
        win_len = cfg.win_len;
        overlap = cfg.overlap;
        nfft = max(256, 2^nextpow2(win_len));
        window = hamming(win_len);

        for k = 1:K
            signal = Y_avg(k, :);
            [~, F, ~, P] = spectrogram(signal, window, overlap, nfft, fs);
            P_dB = 10 * log10(abs(P) + eps);
            global_min = min(global_min, min(P_dB(:)));
            global_max = max(global_max, max(P_dB(:)));
        end
    end
end

% Plot the results.
for band = 1:size(freq_bands, 1)
    band_range = freq_bands{band};

    for stage = 1:size(Y_avg_all, 2)
        Y_avg = Y_avg_all{band, stage};
        [K, ~] = size(Y_avg);

        key = sprintf('%d_%d', stage, band);
        cfg = stft_config(key);
        win_len = cfg.win_len;
        overlap = cfg.overlap;
        nfft = max(256, 2^nextpow2(win_len));
        window = hamming(win_len);

        % Use tiledlayout to avoid overlapping panels.
        fig = figure('Name', sprintf('Stage: %s | Band: %d–%dHz', ...
            transient_stages{stage}, band_range(1), band_range(2)), ...
            'NumberTitle', 'off', 'Visible', 'off', ...
            'Position', [100, 100, 1000, 200 + 200*K]);  % Adjust the figure height for the channel count.

        t = tiledlayout(K, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
        title(t, sprintf('Spectrogram - %s | %d–%d Hz', ...
            transient_stages{stage}, band_range(1), band_range(2)), ...
            'FontWeight', 'bold', 'FontSize', 14);

        for k = 1:K
            signal = Y_avg(k, :);
            [~, F, T, P] = spectrogram(signal, window, overlap, nfft, fs);
            P_dB = 10 * log10(abs(P) + eps);

            % Retain frequencies within the band.
            freq_mask = (F >= band_range(1)) & (F <= band_range(2));
            F_band = F(freq_mask);
            P_band = P_dB(freq_mask, :);

            nexttile;
            imagesc(T, F_band, P_band, [global_min, global_max]);
            axis xy;
            xlabel('Time (s)', 'FontSize', 10);
            ylabel('Frequency (Hz)', 'FontSize', 10);
            title(sprintf('Synergy %d', k), 'FontSize', 10);
            colormap jet;
        end

        % Place a color bar on the right of the figure.
        cb = colorbar('Position', [0.93 0.1 0.02 0.8]); % Use a custom color-bar position.
        cb.Label.String = 'Power (dB)';
        cb.FontSize = 10;

        filename = sprintf('Spectrogram_Stage%d_%s_Band_%d-%dHz.png', ...
            stage, strrep(transient_stages{stage}, ' ', '_'), ...
            band_range(1), band_range(2));
        exportgraphics(fig, fullfile(output_folder, filename), 'Resolution', 300);
        close(fig);
    end
end

%% Inspect short-time Fourier transforms

% Output directory.
output_folder_stft = fullfile(paths.results_root, 'stft');
if ~exist(output_folder_stft, 'dir')
    mkdir(output_folder_stft);
end

% Compute global color limits.
global_min = inf;
global_max = -inf;

for band = 1:size(freq_bands, 1)
    for stage = 1:size(Y_avg_all, 2)
        Y_avg = Y_avg_all{band, stage};
        [K, ~] = size(Y_avg);

        win_len = round(win_times(band) * fs);
        window = hann(win_len);
        nfft = max(256, 2^nextpow2(win_len));
        overlap = round(0.9 * win_len);

        for k = 1:K
            signal = Y_avg(k, :);
            [S, F, T] = stft(signal, fs, ...
                'Window', window, ...
                'OverlapLength', overlap, ...
                'FFTLength', nfft);

            P_dB = 10 * log10(abs(S).^2 + eps);
            global_min = min(global_min, min(P_dB(:)));
            global_max = max(global_max, max(P_dB(:)));
        end
    end
end

% Plot the results.
for band = 1:size(freq_bands, 1)
    band_range = freq_bands{band};
    win_len = round(win_times(band) * fs);
    window = hann(win_len);
    nfft = max(256, 2^nextpow2(win_len));
    overlap = round(0.9 * win_len);

    for stage = 1:size(Y_avg_all, 2)
        Y_avg = Y_avg_all{band, stage};
        [K, ~] = size(Y_avg);

        figure('Name', sprintf('STFT: %s | Band: %d–%dHz', ...
            transient_stages{stage}, band_range(1), band_range(2)), ...
            'NumberTitle', 'off', 'Visible', 'off');

        for k = 1:K
            signal = Y_avg(k, :);
            [S, F, T] = stft(signal, fs, ...
                'Window', window, ...
                'OverlapLength', overlap, ...
                'FFTLength', nfft);

            P_dB = 10 * log10(abs(S).^2 + eps);

            % Restrict the frequency range.
            freq_mask = (F >= band_range(1)) & (F <= band_range(2));
            F_band = F(freq_mask);
            P_band = P_dB(freq_mask, :);

            subplot(K, 1, k);
            imagesc(T, F_band, P_band, [global_min, global_max]);
            axis xy;
            xlabel('Time (s)');
            ylabel('Frequency (Hz)');
            title(sprintf('Synergy %d', k));
            colormap jet;
        end

        sgtitle(sprintf('STFT - %s | %d–%d Hz', ...
            transient_stages{stage}, band_range(1), band_range(2)));
        
        % Use a shared color bar.
        h = colorbar;
        h.Label.String = 'Power (dB)';

        filename = sprintf('STFT_Stage%d_%s_Band_%d-%dHz.png', ...
            stage, strrep(transient_stages{stage}, ' ', '_'), ...
            band_range(1), band_range(2));
        saveas(gcf, fullfile(output_folder_stft, filename));
        close(gcf);
    end
end

%%



