% RESEARCH NOTE: This archive contains section-based research scripts.
% See docs/REPRODUCIBILITY.md before executing sections. Alternatives overwrite
% shared variables; running the entire file is not a verified report pipeline.
% Each legacy subject/subj index denotes a trial from ONE participant.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root, fullfile(repo_root, 'Function'));
paths = research_paths();

%% Import synchronization markers

% Define the base path.
base_path = paths.data_root;

% Find trial folders matching the configured prefix.
folders_info = dir(fullfile(base_path, 'path2_*'));
folders = {folders_info([folders_info.isdir]).name};

% Initialize a cell array for imported data.
sync_time_marker = cell(1, numel(folders));

% Read each .npz file.
for i = 1:numel(folders)
    % Full file path.
    file_path = fullfile(base_path, folders{i}, 'opensim', 'sync_time_marker.npz');
    
    % Check that the file exists.
    if exist(file_path, 'file')
        
        % Extract the .npz archive to a temporary directory.
        temp_dir = fullfile(base_path, 'temp_extract');
        if ~exist(temp_dir, 'dir')
            mkdir(temp_dir);
        end
        unzip(file_path, temp_dir);
        
        % Read .npy files from the temporary directory.
        npy_files = dir(fullfile(temp_dir, '*.npy'));
        data = cell(1, numel(npy_files));
        for j = 1:numel(npy_files)
            npy_file_path = fullfile(temp_dir, npy_files(j).name);
            data{j} = readNPY(npy_file_path);
        end
        
        % Store the synchronization markers.
        sync_time_marker{i} = data;
        
        % Remove temporary files.
        delete(fullfile(temp_dir, '*.npy'));
    else
        warning('File %s not found.', file_path);
    end
end

% Remove the temporary directory.
if exist(temp_dir, 'dir')
    rmdir(temp_dir, 's');
end

% Add one frame to align synchronization markers with template{count,34}.
for i = 1:numel(sync_time_marker)
    
    if ~isempty(sync_time_marker{1, i})
        
        % Extract sync_time_marker{1, i}{1, 2}.
        current_data = sync_time_marker{1, i}{1, 2};
        
        if ~isempty(current_data)
            
            % Add one frame to align synchronization markers with template{count,34}.
            new_value = current_data(end) + 0.0333;
            
            % Match new_value to the orientation of current_data.
            if isrow(current_data)
                new_value = [new_value];  % Keep new_value as a row vector.
            else
                new_value = [new_value]';  % Keep new_value as a column vector.
            end
            
            % Append the new value.
            sync_time_marker{1, i}{1, 2} = [current_data; new_value];  % Concatenate vertically.
        end
    end
end

%% Segment STS, STW, and WTS movement phases

% Load template
load(paths.motion_template);

% Trial-directory prefix.
prefix = 'path2_';

% Root directory.
rootFolder = paths.data_root;

% List all subdirectories.
subdirs = dir(fullfile(rootFolder, [prefix '*']));
subdirs = subdirs([subdirs.isdir] & ~startsWith({subdirs.name}, '.'));
numFiles = length(subdirs);

% Initialize result storage.
transient_results = cell(numFiles, 1); 
timeOfvideo = cell(numFiles, 1); 

output_folder = fullfile(paths.results_root, 'transitional_stages_path2');
if ~exist(output_folder, 'dir')
   mkdir(output_folder);
end

% Process each subdirectory.
for i = 1:numFiles
    
    % Construct the trial folder path.
    folder_name = subdirs(i).name;
    folder_path = fullfile(rootFolder, folder_name, 'opensim');
    
    % Configure IK and TRC file paths.
    IK_dir = fullfile(folder_path, 'Balancing_for_IK_BODY.mot');
    trc_dir = fullfile(folder_path, 'Empty_project_filt_0-30.trc');
    
    try
        % Check that the required files exist.
        if exist(IK_dir, 'file') && exist(trc_dir, 'file')
            
            count = i+1; 
            data = trc_read(trc_dir);
            angle = importdata(IK_dir);
            [vr30, vl30] = heel_v_xy_plane(trc_dir, 30);
            vcm30 = gaitspeedcm(trc_dir, 30);
            vCHip30 = gaitspeedCHip(trc_dir, 30);
            vCHip6 = gaitspeedCHip(trc_dir, 6);
            label = folder_name;

            % Store acquisition fields in the template.
            template{count, 9} = angle.data(:,11);
            template{count,10} = angle.data(:,19);
            template{count,16} = angle.data(:,13);
            template{count,17} = angle.data(:,21);
            template{count,25} = vCHip6;
            template{count,29} = angle.data(:,8);
            template{count,30} = angle.data(:,16);
            template{count,33} = vr30;
            template{count,34} = vl30;
            template{count,35} = [data(:,19), data(:,21), data(:,20)];
            template{count,36} = [data(:,37), data(:,39), data(:,38)];
            template{count,39} = vCHip30;
            template{count,40} = data;
            template{count,41} = vcm30;
            template{count,42} = angle;

            % Run transition analysis.
            timeOfvideo{i} = count_videotime(sync_time_marker, i);
            transient_results{i} = analyze_transient_segments_v1(vcm30, timeOfvideo{i}, label, output_folder);
        else
            warning(['在資料夾中找不到檔案: ', folder_path]);
        end
    catch ME
        fprintf('處理資料夾時發生錯誤: %s\n', ME.message);
    end
end

% Store transient_results.
%save(fullfile(paths.results_root, 'transitional_results_path2.mat'), 'transient_results', '-v7.3');
disp('Segmentation remains in transient_results; the optional save command is disabled.');
%% Local helper functions

function data = trc_read(trc_dir)
    fid = fopen(trc_dir);
    Rows = textscan(fid, '%s', 'delimiter', '\n'); % Create temporary storage for input lines.
    fclose(fid);
    
    % Find the start of each trace.
    TraceStarts = strfind(Rows{1,1}, 'Scan'); 
    TracesIdx = find(~cellfun('isempty', TraceStarts)); % Store the indices.
    
    % Parse numeric values and discard VOID entries.
    Columns = cellfun(@(x) textscan(x, '%f', 'delimiter', '\t', 'CollectOutput', 1, 'treatAsEmpty', {'VOID'}), Rows{1,1});
    Columns = cellfun(@transpose, Columns, 'UniformOutput', 0);
    
    % Store each trace.
    for k = 1:size(TracesIdx) - 1
        traces{k, 1} = cell2mat(Columns(TracesIdx(k) + 4:TracesIdx(k + 1) - 1));
    end
    
    data = [];
    for i = 6:length(Columns)
        data = [data; Columns{i}(1, 3:end)];
    end
end

function [vr, vl] = heel_v_xy_plane(trc_dir, SRd)
    data = trc_read(trc_dir);
    Rheel = 19;
    Lheel = 37;
    down_index = 30 / SRd; % Downsampling factor.
    
    R_heel = data(:, Rheel:Rheel + 2);
    R_heel_d = downsample(R_heel, down_index);
    L_heel = data(:, Lheel:Lheel + 2);
    L_heel_d = downsample(L_heel, down_index);
    
    % Compute right-heel velocity.
    x = R_heel(:, 1);
    y = R_heel(:, 3);
    vx = [x(1); x(1:end - 1)] - x;
    vy = [y(1); y(1:end - 1)] - y;
    vr = sqrt(vx.^2 + vy.^2) * 30; % Compute velocity.
    
    % Compute left-heel velocity.
    x = L_heel(:, 1);
    y = L_heel(:, 3);
    vx = [x(1); x(1:end - 1)] - x;
    vy = [y(1); y(1:end - 1)] - y;
    vl = sqrt(vx.^2 + vy.^2) * 30; % Compute velocity.
end

function v = gaitspeedCHip(trc_dir, SRd)
    % Read TRC data.
    data = trc_read(trc_dir);
    
    % Set analysis parameters.
    CHip = 1; % Hip marker index.
    SR = 30; % Original sampling rate.
    down_index = SR / SRd; % Downsampling factor.
    
    % Extract and downsample hip-marker data.
    C_Hip = data(:, CHip:CHip + 2);
    C_Hip_d = downsample(C_Hip, down_index);
    
    % Compute velocity.
    x = C_Hip_d(:, 1);
    y = C_Hip_d(:, 3);
   
    % Compute velocity components.
    vx = x - [x(1); x(1:end-1)];
    vy = y - [y(1); y(1:end-1)];
    
    % Compute velocity magnitude.
    v = sqrt(vx.^2 + vy.^2) * SRd;
    
    % Return the maximum velocity.
    max_speed = max(v);
end

function v = gaitspeedcm(trc_dir, SRd)
    % Read TRC data.
    data = trc_read(trc_dir);
    
    % Set analysis parameters.
    SR = 30; % Original sampling rate.
    
    % Extract body landmarks and average their positions.
    CHip = 1; % Hip marker.
    RHip = 4; % Right hip.
    LHip = 22; % Left hip.
    RShoulder = 49; % Right shoulder.
    LShoulder = 58; % Left shoulder.
    Neck = 40; % Neck marker.
    
    cm = (data(:, CHip:CHip + 2) + ...
           data(:, RHip:RHip + 2) + ...
           data(:, LHip:LHip + 2) + ...
           data(:, RShoulder:RShoulder + 2) + ...
           data(:, LShoulder:LShoulder + 2) + ...
           data(:, Neck:Neck + 2)) ./ 6; % Compute the archived body-center proxy.
    
    down_index = SR / SRd; % Downsampling factor.
    C_Hip = cm;
    C_Hip_d = downsample(C_Hip, down_index); % Downsample the data.
    
    % Compute velocity.
    x = C_Hip_d(:, 1);
    y = C_Hip_d(:, 3);
    
    vx = [0; diff(x)] * SRd;   % m/s
    vy = [0; diff(y)] * SRd;   % m/s
    v = sqrt(vx.^2 + vy.^2);  % m/s
    % Compute velocity components.
    %vx = x - [x(1); x(1:end-1)];
    %vy = y - [y(1); y(1:end-1)];
    
    % Compute velocity magnitude.
    %v = sqrt(vx.^2 + vy.^2) * SRd;
    
    % Return the maximum velocity.
    max_speed = max(v);
end    

% Compute the x-axis.
function timeOfvideo = count_videotime(sync_time_marker, nowset)
    
    % Get each frame's time in seconds.
    frame_time_data = sync_time_marker{1, nowset}{1, 2}; 
    
    % Use the first red-light frame as the starting reference.
    start_time = sync_time_marker{1, nowset}{1, 1}(1);
    
    % Compute time relative to the starting reference; timeOfvideo is a row vector.
    timeOfvideo = (frame_time_data - start_time)';
end

% Segment body-center velocity into STS, STW, and WTS transitions.
function transient_time_struct = analyze_transient_segments_v1(vcm_data, timeOfvideo, data_label, output_folder)

transient_time_struct = struct(); % Initialize the output structure.
vcm_data = vcm_data(:);           % Ensure a column-vector layout.
timeOfvideo = timeOfvideo(:);     % Ensure the time axis is a column vector.
fs = 30;                          % Video sampling rate in frames per second.

% Plot the original body-center velocity.
figure;
plot(timeOfvideo, vcm_data, 'k'); hold on;
xlabel('Time (s)');
ylabel('vcm');

% Add the data label to the figure title.
if nargin < 3 || isempty(data_label)
    data_label = 'unknown';
end
title(['Segmentation of transitional stages (', data_label, ')'], 'Interpreter', 'none');

% Use a difference filter to emphasize velocity changes.
h1 = [-1 -2 0 2 1]; 
y = conv(vcm_data, h1, 'same');  % Compute the difference signal.

% Square the derivative signal to remove its sign.
y2 = y.^2 / max(y.^2); % Normalize to a maximum of one.

% Smooth with a 31-sample moving average, approximately one second.
h2 = ones(1, 31) / 31;           
y3 = conv(y2, h2, 'same') / max(conv(y2, h2, 'same')); % Normalize the smoothed energy curve.

% Mark energy values above the mean as active.
MWI_set = y3 > mean(y3);

% Find active-interval boundaries from differences.
diff_set = diff([false; MWI_set; false]);
left = find(diff_set == 1);           % Activity start.
right = find(diff_set == -1) - 1;     % Activity end.

% Find a local minimum within one second before each active interval.
vally_loc = [];
for i = 1:length(left)
    idx = max(1, left(i) - fs);       % Inspect the one-second interval preceding activity.
    [~, min_idx] = min(vcm_data(idx:left(i)));  % Find the interval's minimum.
    vally_loc(i) = idx + min_idx - 1; % Store the minimum's global index.
end

% Add the final local minimum when an activity end is available.
if ~isempty(right)
    idx = max(1, right(end) - fs);
    [~, min_idx] = min(vcm_data(idx:right(end)));
    vally_loc(end+1) = idx + min_idx - 1;
end

% Use at least three minima to identify three transition intervals.
if length(vally_loc) >= 3
    X1 = vally_loc(2); 
    X2 = vally_loc(3);
    
    % Search for peaks between the second and third minima.
    sub_vcm = vcm_data(X1:X2);
    th = mean(sub_vcm) + 0.3 * std(sub_vcm); % Set the adaptive threshold.
    [~, peak_loc] = findpeaks(sub_vcm, 'MinPeakHeight', th, 'MinPeakDistance', round(0.3*fs));
   % [~, peak_loc] = findpeaks(sub_vcm, 'MinPeakHeight', th); % Find peaks in the walking interval.

    if length(peak_loc) >= 2
        % Convert peak positions to global indices.
        X1_peak = X1 + peak_loc(1) - 1;
        X2_peak = X1 + peak_loc(end) - 1;

        % Define the start and end indices of the three transitions.
        T1_start = vally_loc(1);  T1_end = vally_loc(2);        % Sit to stand.
        T2_start = vally_loc(2);  T2_end = X1_peak;             % Stand to walk.
        T3_start = X2_peak;       T3_end = vally_loc(end);      % Walk to stop.

        % Mark the boundaries of all three transitions.
        plot(timeOfvideo([T1_start T1_end]), vcm_data([T1_start T1_end]), 'bo', 'MarkerFaceColor', 'b');
        plot(timeOfvideo([T2_start T2_end]), vcm_data([T2_start T2_end]), 'go', 'MarkerFaceColor', 'g');
        plot(timeOfvideo([T3_start T3_end]), vcm_data([T3_start T3_end]), 'mo', 'MarkerFaceColor', 'm');

        % Print transition times.
        fprintf('暫態 1（坐→站）: %.2f 到 %.2f 秒\n', timeOfvideo(T1_start), timeOfvideo(T1_end));
        fprintf('暫態 2（站→走）: %.2f 到 %.2f 秒\n', timeOfvideo(T2_start), timeOfvideo(T2_end));
        fprintf('暫態 3（走→停）: %.2f 到 %.2f 秒\n', timeOfvideo(T3_start), timeOfvideo(T3_end));

        % Store the results in a structure.
        transient_time_struct.T1 = [timeOfvideo(T1_start), timeOfvideo(T1_end)];
        transient_time_struct.T2 = [timeOfvideo(T2_start), timeOfvideo(T2_end)];
        transient_time_struct.T3 = [timeOfvideo(T3_start), timeOfvideo(T3_end)];

        % Save the image to the configured directory.
        saveas(gcf, fullfile(output_folder, ['transitional_stages' data_label '.png']));
        close(gcf);
    else
        warning('穩態區段內未找到足夠 peaks。');
    end
else
    warning('vally_loc 少於 3 組，無法定位三段暫態區段。');
end
end

% Alternative protocol: segment sit-to-walk and walk-to-stop transitions.
function transient_time_struct = analyze_transient_segments_v2(vcm_data, timeOfvideo, data_label, output_folder)

transient_time_struct = struct(); % Initialize the output structure.
vcm_data = vcm_data(:);           % Ensure a column-vector layout.
timeOfvideo = timeOfvideo(:);     % Ensure the time axis is a column vector.
fs = 30;                          % Video sampling rate in frames per second.

% Plot the original body-center velocity.
figure;
plot(timeOfvideo, vcm_data, 'k'); hold on;
xlabel('Time (s)');
ylabel('vcm');

% Add the data label to the figure title.
if nargin < 3 || isempty(data_label)
    data_label = 'unknown';
end
title(['differentiate transient stage (', data_label, ')'], 'Interpreter', 'none');

% Use a difference filter to emphasize velocity changes.
h1 = [-1 -2 0 2 1]; 
y = conv(vcm_data, h1, 'same');

% Square and normalize.
y2 = y.^2 / max(y.^2);

% Smooth the energy curve with a moving average.
h2 = ones(1, 31) / 31;
y3 = conv(y2, h2, 'same') / max(conv(y2, h2, 'same'));

% Detect active intervals using the energy threshold.
MWI_set = y3 > mean(y3);
diff_set = diff([false; MWI_set; false]);
left = find(diff_set == 1);         % Activity start.
right = find(diff_set == -1) - 1;   % Activity end.

% Find the minimum within one second before each activity interval.
vally_loc = [];
for i = 1:length(left)
    idx = max(1, left(i) - fs);
    [~, min_idx] = min(vcm_data(idx:left(i)));
    vally_loc(i) = idx + min_idx - 1;
end

% Add the final minimum for walk to stop.
if ~isempty(right)
    idx = max(1, right(end) - fs);
    [~, min_idx] = min(vcm_data(idx:right(end)));
    vally_loc(end+1) = idx + min_idx - 1;
end

% Check that two transition intervals can be identified.
if length(vally_loc) >= 2
    % Locate the pair of minima with the widest separation.
    [~, max_idx] = max(diff(vally_loc));
    X1 = vally_loc(max_idx); % First minimum: start of sit to walk.
    X2 = vally_loc(max_idx + 1);  % Second minimum: start of walk to stop.

    % Search the sit-to-walk interval for walking-related peaks.
    sub_vcm = vcm_data(X1:X2);
    th = mean(sub_vcm) + 0.3 * std(sub_vcm); % Adaptive threshold.
    [~, peak_loc] = findpeaks(sub_vcm, 'MinPeakHeight', th, 'MinPeakDistance', round(0.3*fs));

    if ~isempty(peak_loc)
        X1_peak = X1 + peak_loc(1) - 1;
        X2_peak = X1 + peak_loc(end) - 1;

        % Define the transition intervals.
        T1_start = vally_loc(1);  T1_end = X1_peak;          % Sit to walk.
        T2_start = X2_peak;       T2_end = vally_loc(end);   % Walk to stop.
        
        % Mark both transition intervals.
        plot(timeOfvideo([T1_start T1_end]), vcm_data([T1_start T1_end]), 'bo', 'MarkerFaceColor', 'b');
        plot(timeOfvideo([T2_start T2_end]), vcm_data([T2_start T2_end]), 'mo', 'MarkerFaceColor', 'm');

        % Display the results.
        fprintf('暫態 1（坐→走）: %.2f 到 %.2f 秒\n', timeOfvideo(T1_start), timeOfvideo(T1_end));
        fprintf('暫態 2（走→停）: %.2f 到 %.2f 秒\n', timeOfvideo(T2_start), timeOfvideo(T2_end));

        % Store the results.
        transient_time_struct.T1 = [timeOfvideo(T1_start), timeOfvideo(T1_end)];
        transient_time_struct.T2 = [timeOfvideo(T2_start), timeOfvideo(T2_end)];

        % Save the figure.
        saveas(gcf, fullfile(output_folder, ['transient_plot_' data_label '.png']));
        close(gcf);

    else
        warning('未偵測到足夠的 peaks 來判斷走路特徵。');
    end
else
    warning('vally_loc 少於兩個，無法定位兩段暫態區段。');
end
end

%% Align EEG and EMG movement phases

% Frequency bands in Hz.
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

numFiles = length(EMG_data);

for i = 1:numFiles
    try
        if ~isempty(EMG_data{i}) && ~isempty(EEG_data{i}) && ~isempty(transient_results{i})

            % Add the starting offset to obtain aligned times.
            eeg_times = [transient_results{i}.T1; transient_results{i}.T2; transient_results{i}.T3] + time_EEG{i}(1);
            emg_times = [transient_results{i}.T1; transient_results{i}.T2; transient_results{i}.T3] + time_EMG{i}(1);

            eeg_data = EEG_data{i}.zcore;
            eeg_time = time_EEG{i};
            emg_time = time_EMG{i};

            % Process EEG.
            for j = 1:size(eeg_times, 1)
                eeg_start = eeg_times(j, 1);
                eeg_end   = eeg_times(j, 2);
                eeg_idx   = find(eeg_time >= eeg_start & eeg_time <= eeg_end);

                if ~isempty(eeg_idx)
                    EEG_data{i}.clip{j} = eeg_data(eeg_idx, :);
                    fprintf('File %d - EEG segment %d clipped (%.2f - %.2f sec)\n', i, j, eeg_start, eeg_end);
                else
                    warning('File %d - EEG segment %d 無法對齊 (%.2f - %.2f)', i, j, eeg_start, eeg_end);
                end
            end

            % Process each EMG frequency band.
            for band_idx = 1:length(EMG_data{i}.envelope)
                emg_band_data = EMG_data{i}.envelope{band_idx};
                band_range = freq_bands{band_idx};

                for j = 1:size(emg_times, 1)
                    emg_start = emg_times(j, 1);
                    emg_end   = emg_times(j, 2);
                    emg_idx   = find(emg_time >= emg_start & emg_time <= emg_end);

                    if ~isempty(emg_idx)
                        EMG_data{i}.clip{band_idx, j} = emg_band_data(emg_idx, :);
                        fprintf('File %d - EMG band [%d–%d Hz] segment %d clipped (%.2f - %.2f sec)\n', ...
                            i, band_range(1), band_range(2), j, emg_start, emg_end);
                    else
                        warning('File %d - EMG band [%d–%d Hz] segment %d 無法對齊 (%.2f - %.2f)', ...
                            i, band_range(1), band_range(2), j, emg_start, emg_end);
                    end
                end
            end
        else
            warning('File %d: 資料缺失或 transient_results{i} 為空。', i);
        end
    catch ME
        warning('File %d 發生錯誤：%s', i, ME.message);
    end
end

%%

