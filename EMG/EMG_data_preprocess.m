% RESEARCH NOTE: This archive contains section-based research scripts.
% See docs/REPRODUCIBILITY.md before executing sections. Alternatives overwrite
% shared variables; running the entire file is not a verified report pipeline.
% Each legacy subject/subj index denotes a trial from ONE participant.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root, fullfile(repo_root, 'Function'));
paths = research_paths();

%% read data

% 檔案資料夾路徑
folder_path = paths.trial_folder;

% 取得 eeg_path1_*.csv 檔案
files = dir(fullfile(folder_path, 'EMG_path2_*.csv'));

% 預先分配 cell array 來儲存每個檔案的數據
EMG_data = cell(1, numel(files));

% 讀取每個檔案的數據並儲存至 cell array 中
for i = 1:numel(files)
    try
        % 組合完整檔案路徑
        file_path = fullfile(files(i).folder, files(i).name);
        
        % 使用 readtable 函數讀取 CSV 檔案
        EMG_data_table = readtable(file_path, 'VariableNamingRule', 'preserve');
        
        % table 轉成 array 並儲存到 cell array 中
        EMG_data{i}.original = table2array(EMG_data_table);
        
        % 預設其他欄位為空
        EMG_data{i}.alignment = [];
        EMG_data{i}.detrend = [];
        EMG_data{i}.notchfilter = [];
        EMG_data{i}.frequencydivision = [];
        EMG_data{i}.envelope = [];
        EMG_data{i}.clip = [];
        EMG_data{i}.resampled = [];
        EMG_data{i}.normalize  = [];     
        
    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error reading file %s: %s', files(i).name, ME.message);
    end
end

% 顯示已成功讀取的檔案數量
num_files_read = sum(cellfun(@(x) ~isempty(x.original), EMG_data));
disp(['已成功讀取 ', num2str(num_files_read), ' 個檔案。']);

%% data alignment (linear interpolate for missing data)
% 記得更改 end_idx - start_idx 的範圍（先查看資料長度）

n1 = 11; % event id column
n2 = 14; % software id column
serial_number = 2; % serial number column
start_event = 130; % 紅燈亮
end_event = 141; % 綠燈暗
columns_to_process = 3:10; % 指定要處理的列

% 保存不連續數據的 cell array
non_continuous_data = {};

% 初始化 start_indices 和 end_indices
num_files = numel(EMG_data);
start_indices = nan(1, num_files); % 使用 NaN 預分配
end_indices = nan(1, num_files);   % 使用 NaN 預分配

% 對每個檔案進行數據對齊
for i = 1:num_files
    try
        EMG_data_array = EMG_data{i}.original;  % 從 cell array 中提取數據

        % 確保數據存在
        if isempty(EMG_data_array)
            disp(['檔案無效或未讀取成功: ', files(i).name]);
            continue;  % 跳過此檔案，繼續處理下一個
        end

        % 使用 n1 尋找 start 和 end index
        logical_start = EMG_data_array(:, n1) == start_event;
        logical_end = EMG_data_array(:, n1) == end_event;

        % 找到第一個和最後一個符合條件的索引
        start_idx = find(logical_start, 1);
        end_idx = find(logical_end, 1, 'last');

        % 如果 n1 找不到 start 或 end，使用 n2 再試一次
        if isempty(start_idx) || isempty(end_idx)
            %(end_idx - start_idx < 11000) || (end_idx - start_idx > 13000)
            disp(['event id 找不到有效的索引，使用 software marker: ', files(i).name]);
            logical_start = EMG_data_array(:, n2) == start_event;
            logical_end = EMG_data_array(:, n2) == end_event;
            start_idx = find(logical_start, 1);
            end_idx = find(logical_end, 1, 'last');
        end

        % 確保找到 start 和 end index
        if isempty(start_idx) || isempty(end_idx)
            %(end_idx - start_idx < 11000) || (end_idx - start_idx > 13000)
            disp(['無法找到有效的開始或結束索引: ', files(i).name]);
            continue;  % 跳過此檔案，繼續處理下一個
        end

        % 保存 start_idx 和 end_idx 到相應位置
        start_indices(i) = start_idx;
        end_indices(i) = end_idx;

        % 提取從第一個130到最後一個141之間的數據
        aligned_data = EMG_data_array(start_idx:end_idx, :);
        EMG_data{i}.alignment = aligned_data;

        % 檢查第二列（serial_number）的連續性
        serial_col = aligned_data(:, serial_number);
        discontinuities = find(diff(serial_col) ~= 1); % 找到不連續點

        if ~isempty(discontinuities)
            % 保存不連續部分的數據
            non_continuous_data{i} = aligned_data(discontinuities + 1, :); % 提取不連續的行
            disp(['發現不連續數據: ', files(i).name]);

            % 插值補齊不連續點
            full_range = (min(serial_col):max(serial_col))';  % 應該有的完整範圍
            missing_points = setdiff(full_range, serial_col);  % 找到缺失的點

            % 打印缺失點
            if ~isempty(missing_points)
                disp(['缺少: ', num2str(missing_points')]);
            end

            if ~isempty(missing_points)
                % 建立包含完整範圍的表格
                complete_data = nan(numel(full_range), size(aligned_data, 2));
                complete_data(ismember(full_range, serial_col), :) = aligned_data;

                % 對第 1 列到第 8列數據進行線性插值
                for col = 1:8  % 只處理第 1 列到第 8列
                    valid_idx = ~isnan(complete_data(:, col));
                    if sum(valid_idx) < 2
                        disp(['警告: 檔案 ', files(i).name, ' 的列 ', num2str(col), ' 沒有足夠的有效數據進行插值。']);
                        continue;
                    end

                    complete_data(:, col) = interp1(full_range(valid_idx), complete_data(valid_idx, col), full_range, 'linear');
                end

                EMG_data{i}.alignment = complete_data;
                disp(['已對檔案插值補齊缺失數據: ', files(i).name]);
                
                % 設定容忍度（此處設定為 1，允許約 ±1 的差異）
                tolerance = 1;

                % 檢查插值是否成功（僅檢查 serial_number 列的連續性，允許容忍度）
                serial_col_interpolated = complete_data(:, serial_number);
                discontinuities = find(abs(diff(serial_col_interpolated) - 1) > tolerance);  % 找到超出容忍範圍的不連續點

                if isempty(discontinuities)
                    disp(['檔案 ', files(i).name, ' 插值成功，缺失點已補上。']);
                else
                    disp(['檔案 ', files(i).name, ' 插值失敗，以下為不連續點的索引位置:']);
                    disp(discontinuities + 1);  % 顯示不連續點的位置（+1 表示實際行數）
                end

            end
        end
    
    % 儲存時間數據
    time_EMG{i} = cell(1, numel(files));
    time_EMG{i} = EMG_data{i}.alignment(:,1);

    % 只留下channel的部分    
    EMG_data{i}.alignment = EMG_data{i}.alignment(:,columns_to_process);
    
    catch ME
        warning('對齊檔案 %s 時發生錯誤: %s', files(i).name, ME.message);
    end
end

% 顯示已成功對齊的檔案數量
num_files_aligned = sum(~isnan(start_indices));
disp(['已成功對齊 ', num2str(num_files_aligned), ' 個檔案。']);

% 顯示每個 EMG_data.alignment 的 array 
for i = 1:num_files
    if isfield(EMG_data{i}, 'alignment') && ~isempty(EMG_data{i}.alignment)
        [rows, cols] = size(EMG_data{i}.alignment);
        disp(['EMG_data', num2str(i), '.alignment', num2str(rows), ' x ', num2str(cols)]);
    else
        disp(['檔案 ', num2str(i), ' 的 alignment 未對齊或為空。']);
    end
end

%% detrend

% 定義電極名稱
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 取樣頻率
fs = 1000;

% 設定圖例名稱
legend_names = {'Alignment data', 'Detrend data'};

% 對每個檔案進行 detrend 操作
for i = 1:numel(EMG_data)

    try
        % 確保文件包含 alignment 且不為空
        if isfield(EMG_data{i}, 'alignment') && ~isempty(EMG_data{i}.alignment)

        % 進行 detrend 
        EMG_data{i}.detrend = detrend(EMG_data{i}.alignment);
            
        else
            warning('alignment field is empty or missing for file %d.', i);
        end

    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error detrend in file %s: %s', files(i).name, ME.message);
    end

end

% 顯示已成功進行 detrend 處理的檔案數量
num_files_detrended = sum(cellfun(@(x) isfield(x, 'detrend') && ~isempty(x.detrend), EMG_data));
disp(['已成功對 ', num2str(num_files_detrended), ' 個檔案進行 detrend 處理。']);

% 畫圖檢查結果
raw_data = EMG_data{1, 1}.alignment;
processed_data = EMG_data{1, 1}.detrend;
plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names);

%% notch filter

% 定義電極名稱
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 取樣頻率
fs = 1000;

% 設定圖例名稱
legend_names = {'Detrend data', 'Notch filter data'};

% 設計 notch 濾波器
fs = 1000; % sample rate
fc = 60; % 濾波器中心頻率 60Hz (範圍 59-61)
[b, a] = designNotchPeakIIR('CenterFrequency', fc/(fs/2), 'Bandwidth', 2/(fs/2), 'Response', 'notch');

% 對每個檔案進行 notch 濾波器操作
for i = 1:numel(EMG_data)
    try
        % 檢查 detrend 數據是否存在
        if isfield(EMG_data{i}, 'detrend') && ~isempty(EMG_data{i}.detrend)
                   
        % 對指定列用 notch 濾波器，並將結果存入 EMG_data.notchfilter 
        EMG_data{i}.notchfilter = filtfilt(b, a, EMG_data{i}.detrend);
                   
        else
            warning('detrend field is empty or missing for file %d.', i);
        end
        
    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error applying notch filter to file %d: %s', i, ME.message);
    end
end

% 顯示已成功進行 notch filter 處理的檔案數量
num_files_notchfiltered = sum(cellfun(@(x) isfield(x, 'notchfilter') && ~isempty(x.notchfilter), EMG_data));
disp(['已成功對 ', num2str(num_files_notchfiltered), ' 個檔案進行 notch filter 處理。']);

% 畫圖檢查結果
raw_data = EMG_data{1, 1}.detrend;
processed_data = EMG_data{1, 1}.notchfilter;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

%{
%% butterworth filter

% 定義電極名稱
ch_list =  {'LGL', 'RGL', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 取樣頻率
fs = 1000;

% 設定圖例名稱
legend_names = {'Notch filter data', 'Butterworth filter data'};

% 設定濾波器
filter_type = 'Butterworth filter';

% 設計 Butterworth 濾波器
order = 4; % 濾波器階數  
fs = 1000; % sample rate
fc_low = 40; % 低截止頻率
fc_high = 450; % 高截止頻率
Wn = [fc_low/(fs/2), fc_high/(fs/2)]; % 歸一化截止頻率
[b, a] = butter(order, Wn, 'bandpass'); % 設計帶通濾波器

% 對每個檔案進行 butterworth  濾波器操作
for i = 1:numel(EMG_data)
    try
        % 檢查 notchfilter 數據是否存在
        if isfield(EMG_data{i}, 'notchfilter') && ~isempty(EMG_data{i}.notchfilter)

        % 對指定列用 butterworth 濾波器，並將結果存入 EEG_data.butterworthfilter 對應的列
        EMG_data{i}.butterworthfilter = filtfilt(b, a, EMG_data{i}.notchfilter);
        
        else
            warning('notchfilter field is empty or missing for file %d.', i);
        end
        
    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error applying butterworth filter to file %d: %s', i, ME.message);
    end
end

% 顯示已成功進行 butterworth filter 處理的檔案數量
num_files_butterworthfiltered = sum(cellfun(@(x) isfield(x, 'butterworthfilter') && ~isempty(x.butterworthfilter), EMG_data));
disp(['已成功對 ', num2str(num_files_butterworthfiltered), ' 個檔案進行 butterworth filter 處理。']);

% 畫圖檢查結果
raw_data = EMG_data{1, 1}.notchfilter;
processed_data = EMG_data{1, 1}.butterworthfilter;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);
%}

%% frequency division

% 定義電極名稱
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 取樣頻率
fs = 1000;

% 設定圖例名稱
legend_names = {'Notch filter data', 'frequency division data'};

% 頻段定義（單位：Hz）
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

% 濾波器設定
order = 4;     % Butterworth 濾波器階數
fs = 1000;     % 取樣率

% 對每筆 EMG_data 進行處理
for i = 1:numel(EMG_data)
    try
        % 檢查 notchfilter 數據是否存在
        if isfield(EMG_data{i}, 'notchfilter') && ~isempty(EMG_data{i}.notchfilter)
            raw_data = EMG_data{i}.notchfilter;

            % 初始化儲存空間
            EMG_data{i}.frequencydivision = cell(1, numel(freq_bands));

            for b = 1:numel(freq_bands)
                % 計算歸一化截止頻率
                fc_low = freq_bands{b}(1);
                fc_high = freq_bands{b}(2);
                Wn = [fc_low, fc_high] / (fs / 2);

                % 設計 Butterworth 濾波器
                [b_butter, a_butter] = butter(order, Wn, 'bandpass');

                % 套用濾波器
                EMG_data{i}.frequencydivision{b} = filtfilt(b_butter, a_butter, raw_data);
            end

        else
            warning('File %d 的 notchfilter 欄位為空或缺失。', i);
        end
    catch ME
        warning('處理檔案 %d 時發生錯誤：%s', i, ME.message);
    end
end

% 顯示成功處理的檔案數量
num_band_filtered = sum(cellfun(@(x) isfield(x, 'frequencydivision') && ~isempty(x.frequencydivision), EMG_data));
disp(['已成功對 ', num2str(num_band_filtered), ' 個檔案進行 frequency division 處理。']);

% 畫圖檢查結果
raw_data = EMG_data{1,1}.notchfilter;% 取出第1筆的原始 Butterworth 資料
% 繪圖：與四個頻帶比較
for band_idx = 1:4
    processed_data = EMG_data{1,1}.frequencydivision{band_idx};
    % 建立頻帶範圍文字（e.g., "10–30 Hz"）
    band_label = sprintf('%d–%d Hz', freq_bands{band_idx}(1), freq_bands{band_idx}(2));

    % 呼叫自訂函數畫圖，並加上頻帶資訊作為附加標題
    plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names, band_label);
end

%% Exploratory envelope: squared rectification and low-pass filtering

% 定義電極名稱
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 取樣頻率
fs = 1000;

% 設定圖例名稱
legend_names = {'frequency division data', 'Lowpass envelope'};

fc_low = 9; % 低通濾波器截止頻率 (Hz)
[b_env, a_env] = butter(4, fc_low / (fs/2), 'low');

for i = 1:numel(EMG_data)
    try
        if isfield(EMG_data{i}, 'frequencydivision') && ~isempty(EMG_data{i}.frequencydivision)
            EMG_data{i}.envelope_rms = cell(1, numel(EMG_data{i}.frequencydivision));
            for band_idx = 1:numel(EMG_data{i}.frequencydivision)
                % 取得分頻後資料
                band_data = EMG_data{i}.frequencydivision{band_idx};

                % 計算 envelope（abs -> square -> lowpass）
                abs_data = abs(band_data);
                squared_data = abs_data .^ 2;
                filtered_data = filtfilt(b_env, a_env, squared_data);

                % 儲存
                EMG_data{i}.envelope_rms{band_idx} = filtered_data;
            end
        else
            warning('File %d 的 frequencydivision 欄位為空或缺失。', i);
        end
    catch ME
        warning('Error in RMS envelope at file %d: %s', i, ME.message);
    end
end

% 顯示已成功進行 envelope 處理的檔案數量
num_files_enveloped = sum(cellfun(@(x) isfield(x, 'envelope') && ~isempty(x.envelope), EMG_data));
disp(['已成功對 ', num2str(num_files_enveloped), ' 個檔案進行 lowpass envelope 處理。']);

% 畫圖檢查結果
for band_idx = 1:4
    raw_data = EMG_data{1,1}.frequencydivision{band_idx};
    processed_data = EMG_data{1,1}.envelope{band_idx};
    % 建立頻帶範圍文字（e.g., "10–30 Hz"）
    band_label = sprintf('%d–%d Hz', freq_bands{band_idx}(1), freq_bands{band_idx}(2));

    % 呼叫自訂函數畫圖，並加上頻帶資訊作為附加標題
    plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names, band_label);
end

%% Report-described Hilbert envelope (review transform dimension before reproduction)

% 定義電極名稱
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 取樣頻率
fs = 1000;

% 設定圖例名稱
legend_names = {'frequency division data', 'Hilbert envelope'};

for i = 1:numel(EMG_data)
    try
        if isfield(EMG_data{i}, 'frequencydivision') && ~isempty(EMG_data{i}.frequencydivision)
            EMG_data{i}.envelope = cell(1, numel(EMG_data{i}.frequencydivision));
            for band_idx = 1:numel(EMG_data{i}.frequencydivision)
                band_data = EMG_data{i}.frequencydivision{band_idx};

                % Hilbert transform（針對每個 channel）
                analytic_signal = hilbert(band_data')';  % 對 column 運算
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

% 顯示成功處理的檔案數量
num_files_enveloped = sum(cellfun(@(x) isfield(x, 'envelope') && ~isempty(x.envelope), EMG_data));
disp(['已成功對 ', num2str(num_files_enveloped), ' 個檔案進行 hilbert envelope 處理。']);

% 畫圖檢查結果
for band_idx = 1:4
    raw_data = EMG_data{1,1}.frequencydivision{band_idx};
    processed_data = EMG_data{1,1}.envelope{band_idx};
    % 建立頻帶範圍文字（e.g., "10–30 Hz"）
    band_label = sprintf('%d–%d Hz', freq_bands{band_idx}(1), freq_bands{band_idx}(2));

    % 呼叫自訂函數畫圖，並加上頻帶資訊作為附加標題
    plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names, band_label);
end

%% Alternative RMS envelope (overwrites the Hilbert envelope if executed)

% 定義電極名稱
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 取樣頻率
fs = 1000;

% 設定圖例名稱
legend_names = {'frequency division data', 'RMS envelope'};

% RMS 視窗大小（樣本點數）
window_size = 50; 

for i = 1:numel(EMG_data)
    try
        if isfield(EMG_data{i}, 'frequencydivision') && ~isempty(EMG_data{i}.frequencydivision)
            EMG_data{i}.envelope_rms = cell(1, numel(EMG_data{i}.frequencydivision));

            for band_idx = 1:numel(EMG_data{i}.frequencydivision)
                band_data = EMG_data{i}.frequencydivision{band_idx};  % (samples x channels)
                rms_data = zeros(size(band_data));

                % 對每個通道執行 RMS 包絡線
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

% 顯示成功處理的檔案數量
num_files_enveloped = sum(cellfun(@(x) isfield(x, 'envelope') && ~isempty(x.envelope), EMG_data));
disp(['已成功對 ', num2str(num_files_enveloped), ' 個檔案進行 RMS envelope 處理。']);

% 畫圖檢查結果
for band_idx = 1:4
    raw_data = EMG_data{1,1}.frequencydivision{band_idx};
    processed_data = EMG_data{1,1}.envelope{band_idx};
    % 建立頻帶範圍文字（e.g., "10–30 Hz"）
    band_label = sprintf('%d–%d Hz', freq_bands{band_idx}(1), freq_bands{band_idx}(2));

    % 呼叫自訂函數畫圖，並加上頻帶資訊作為附加標題
    plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names, band_label);
end

%% plotting data at each processing stage

% sample rate
fs = 1000; 

% 定義處理階段及對應字段
stages = {'alignment', 'detrend', 'notchfilter', 'butterworthfilter', 'envelope'};

for i = 1:numel(EMG_data)

    % 檢查所有處理階段數據是否存在
    missing_stage = false;
    for stage = stages
        if isempty(EMG_data{i}.(stage{1}))
            disp(['檔案: ', files(i).name, ' 缺少 ', stage{1}, ' 的數據']);
            missing_stage = true;
            break;  % 如果有一個階段缺失，跳過此檔案
        end
    end

    if missing_stage
        continue;
    end
    
    % 建立新圖表
    figure;
    
    % 使用迴圈繪製各處理階段
    for j = 1:length(stages)
        subplot(5, 1, j);
        time_axis = (0:size(EMG_data{i}.(stages{j}), 1)-1) / fs;  % 計算時間軸
        
        % 將多個 channel 的資料取平均值
        merged_data = mean(EMG_data{i}.(stages{j}), 2);  % 每行取平均值
        
        % 繪製合併後的數據
        plot(time_axis, merged_data);  
        title([upper(stages{j}(1)), stages{j}(2:end), ' Data for file: ', files(i).name], 'Interpreter', 'none');
        xlabel('Time (s)');  % 更改 x 軸標籤為時間
        
        % 根據處理階段決定 y 軸單位
        if strcmp(stages{j}, 'envelope')
            ylabel('Voltage² (µV²)');  % envelope的y軸標籤為 µV²
        else
            ylabel('Voltage (µV)');  % 其他處理階段的y軸標籤為 µV
        end
    end
    
    % 調整圖表布局
    sgtitle(['EMG Data Processing Stages for file: ', files(i).name], 'Interpreter', 'none');
end

%% mark LHS & RHS on EMG_data.envelope 

% sample rate
fs = 1000; 

% 儲存channel名稱
channel_names = {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 設置保存圖片的路徑
save_path = fullfile(paths.results_root, 'envelope');

% 定義 numLHSdata 和 numRHSdata
numLHSdata = numel(LHS_data);  % 確認 LHS_data 是 cell 
numRHSdata = numel(RHS_data);  % 確認 RHS_data 是 cell

% 繪製時間對 Voltage²(µV²) 的圖
for i = 1:numel(EMG_data)
    try
        % 檢查 EMG_data{i} 是否有效
        if isempty(EMG_data{i}) || ~isfield(EMG_data{i}, 'envelope') || isempty(EMG_data{i}.envelope)
            warning('EMG_data %d: alignment 或 envelope 欄位為空或缺失', i);
            continue;
        end

        % 檢查 LHS_data 和 RHS_data 是否有效
        if i > numLHSdata || i > numRHSdata || isempty(LHS_data{i}) || isempty(RHS_data{i})
            warning('檔案 %d 的 LHS_data 或 RHS_data 無效或為空', i);
            continue;
        end

        % 根據採樣頻率計算時間向量
        time_vector = (0:size(EMG_data{i}.envelope, 1) - 1) / fs;
        
        % 創建新圖形窗口
        figure;
        num_channels = size(EMG_data{i}.envelope, 2); % 獲取通道數
        
        for j = 1:num_channels
            subplot(num_channels, 1, j); % 創建子圖
            
            % 繪製時間對 Voltage² 的圖
            plot(time_vector, EMG_data{i}.envelope(:, j));
            
            % 使用通道名稱更新標題
            title(channel_names{j}); 
            xlabel('時間 (s)'); % x 軸標籤
            ylabel('Voltage² (µV²)'); % y 軸標籤
            %xlim([15 20]); % 設定 x 軸範圍
            grid on; % 添加網格
            
            % 標示 LHS_data 和 RHS_data 的點
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
        
        % 使用 sgtitle 添加總標題
        sgtitle(['EMG envelope for path1\_', sprintf('%02d', i)]);
        
        % 保存圖形
        %saveas(gcf, fullfile(save_path, ['EMG envelope for ', 'path1_', sprintf('%02d', i), '.png']));
        %close(gcf); % 關閉圖形窗口，節省資源

    catch ME
        % 捕獲錯誤並顯示錯誤信息
        warning('繪製檔案 %d 的 envelope 時出現錯誤: %s', i, ME.message);
    end
end

%% resample EMG (fs = 500 same as EEG)

% 定義電極名稱
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 設定圖例名稱
legend_names = {'cliped data', 'resampled data'};

% 頻段定義（單位：Hz）
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

fs_new = 500;  % 統一成 500 Hz
fs_old = 1000; % 原始 EMG 是 1000 Hz

for i = 1:length(EMG_data)

    [num_bands, num_clips] = size(EMG_data{i}.clip); % 頻段數量 x clip 數量

    for j = 1:num_clips
        for band = 1:num_bands

            % 取得 normalize 後的資料
            clipData = EMG_data{i}.clip{band, j};  % (M x N)

            % 對每一個通道做降採樣
            clipData_resampled = resample(clipData, fs_new, fs_old);  % (M' x N)

            % 儲存
            EMG_data{i}.resampled{band, j} = clipData_resampled;

        end
    end
end

% 顯示成功處理的檔案數量
num_files_resampled = sum(cellfun(@(x) isfield(x, 'resampled') && ~isempty(x.resampled), EMG_data));
disp(['已成功對 ', num2str(num_files_resampled), ' 個檔案進行 resampled 處理。']);

% 畫圖檢查結果
raw_data = EMG_data{1, 1}.clip{1, 1};
processed_data = EMG_data{1, 1}.resampled{1, 1};
fs_old = 1000;
fs_new =500;
% 建立頻帶範圍文字（e.g., "10–30 Hz"）
band_label = sprintf('%d–%d Hz', freq_bands{1}(1), freq_bands{1}(2));

    % 時間軸計算
    t_old = (0:size(raw_data, 1)-1) / fs_old;
    t_new = (0:size(processed_data, 1)-1) / fs_new;
    
    % 每個通道繪製（使用 subplot）
    for ch_idx = 1:size(raw_data, 2)
        figure;
    
        % 時域資料
        raw_ch = raw_data(:, ch_idx);
        proc_ch = processed_data(:, ch_idx);

        % 上半部：raw data
        subplot(2, 1, 1);
        plot(t_old, raw_ch, 'b', 'LineWidth', 1.5);
        title(['Raw Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{1});
        grid on;

        % 下半部：processed data
        subplot(2, 1, 2);
        plot(t_new, proc_ch, 'r', 'LineWidth', 1.5);
        title(['Processed Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{2});
        grid on;
    end

%% normalize

% 定義電極名稱
ch_list =  {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 設定圖例名稱
legend_names = {'resampled data', 'normalize data'};

% 頻段定義（單位：Hz）
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

% 選擇 'max', 'mean', 'mvc', 'std', 'zscore' 其中一種方法
method = 'max'; 

for i = 1:length(EMG_data) % 遍歷每一組 EMG 資料

    [num_bands, num_clips] = size(EMG_data{i}.resampled); % 頻段數量 x clip 數量

    for j = 1:num_clips % transient stage

        for band = 1:num_bands % 頻段 (1~4)
            clipData = EMG_data{i}.resampled{band, j}; % 正確取得每段資料
            
            % 呼叫標準化函數並儲存
            EMG_data{i}.normalize{band, j} = normalizeClipData(clipData, method);
        end

    end
end

% 顯示成功處理的檔案數量
num_files_normalize = sum(cellfun(@(x) isfield(x, 'normalize') && ~isempty(x.normalize), EMG_data));
disp(['已成功對 ', num2str(num_files_normalize), ' 個檔案進行 normalize 處理。']);

function normalizedData = normalizeClipData(data, method)
    % normalizeClipData 對整個數據矩陣進行標準化
    %   data   : 輸入的數據矩陣（行: 數據點，列: 通道）
    %   method : 標準化方法 ('max', 'mean', 'mvc', 'std', 'zscore')

    normalizedData = data; % 初始化

    % 遍歷所有列
    for k = 1:size(data, 2)
        switch method
            case 'max'
                maxVal = max(data(:, k));
                minVal = min(data(:, k));
                range = maxVal - minVal;
                if range ~= 0
                    normalizedData(:, k) = (data(:, k) - minVal) / range; % [0, 1] 範圍
                else
                    normalizedData(:, k) = data(:, k); % 無法標準化則原樣輸出
                end

            case 'mean'
                meanVal = mean(data(:, k));
                range = max(data(:, k)) - min(data(:, k));
                if range ~= 0
                    normalizedData(:, k) = (data(:, k) - meanVal) / range; % 偏移至[-0.5, 0.5]
                else
                    normalizedData(:, k) = data(:, k);
                end

            case 'mvc' % 最大隨意收縮 (Maximal Voluntary Contraction) 
                maxVal = max(abs(data(:, k))); % 計算該通道的最大值
                if maxVal ~= 0
                    normalizedData(:, k) = data(:, k) / maxVal; % 正規化至 [0, 1]
                else
                    normalizedData(:, k) = data(:, k); % 若最大值為 0，則保持原數據
                end

            case 'std'
                stdVal = std(data(:, k));
                if stdVal ~= 0
                    normalizedData(:, k) = data(:, k) / stdVal; % 單位化
                else
                    normalizedData(:, k) = data(:, k);
                end

            case 'zscore'
                normalizedData(:, k) = zscore(data(:, k)); % 使用 zscore 函數

            otherwise
                error('無效的標準化方法。請選擇 "max", "mean", "mvc", "std", "zscore"');
        end
    end
end

% 畫圖檢查結果
raw_data = EMG_data{1, 1}.clip{1, 1};
processed_data = EMG_data{1, 1}.normalize{1, 1};
fs_old = 1000;
fs_new =500;
% 建立頻帶範圍文字（e.g., "10–30 Hz"）
band_label = sprintf('%d–%d Hz', freq_bands{1}(1), freq_bands{1}(2));

    % 時間軸計算
    t_old = (0:size(raw_data, 1)-1) / fs_old;
    t_new = (0:size(processed_data, 1)-1) / fs_new;
    
    % 每個通道繪製（使用 subplot）
    for ch_idx = 1:size(raw_data, 2)
        figure;
    
        % 時域資料
        raw_ch = raw_data(:, ch_idx);
        proc_ch = processed_data(:, ch_idx);

        % 上半部：raw data
        subplot(2, 1, 1);
        plot(t_old, raw_ch, 'b', 'LineWidth', 1.5);
        title(['Raw Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{1});
        grid on;

        % 下半部：processed data
        subplot(2, 1, 2);
        plot(t_new, proc_ch, 'r', 'LineWidth', 1.5);
        title(['Processed Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{2});
        grid on;
    end

%% NMF alternative A: sparsenmfnnls (choose one NMF section)

% 設定 K 值範圍
k_range = 1:8; % 肌肉通常 synergy 是 2-6

% 設定 sparsenmfnnls 的參數
option.beta = 0.2;      % 提高 Y 的稀疏性（讓協同作用向量更集中）
option.eta = 0.05;      % 適度壓縮 A，讓肌肉貢獻分布更具生理意義
option.iter = 1000;     % 增加迭代次數，有助於更收斂
option.dis = false;     % 保持不顯示訊息
option.residual = 1e-6; % 更嚴格的收斂條件（殘差差異閾值）
option.tof = 1e-6;      % 更嚴格的目標函數差異閾值

% 初始化儲存結構
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
                    % 呼叫 Sparse NNMF
                    [A, Y, numIter, tElapsed, finalResidual] = sparsenmfnnls(data, k, option);
                catch ME
                    fprintf('sparsenmfnnls 失敗: EMG_data{%d}.normalize{%d, %d}, K=%d\n', i, band, clip, k);
                    disp(ME.message);
                    continue;
                end

                reconstructed = A * Y;

                % 計算 VAF
                SST = sum(sum((data - mean(data, 'all')).^2));  % 總變異
                SSE = sum(sum((data - reconstructed).^2));      % 殘差平方和
                VAF_per_k(k_idx) = 1 - (SSE / SST);

                % 計算 relative residual
                data_norm = norm(data, 'fro');  % 原始資料的 Frobenius norm
                relative_residual = finalResidual / data_norm;

                % 儲存結果
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

% 設定 K 值範圍
k_range = 1:8; % 肌肉通常 synergy 是 2-6

% 設定 nmfnnls 的參數
option.iter = 1000;     % 最大迭代次數
option.dis = false;     % 不顯示中間訊息
option.residual = 1e-6; % 更嚴格的收斂條件（殘差）
option.tof = 1e-6;      % 更嚴格的目標函數差異閾值

% 初始化儲存結構
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
                    % 改為使用 nmfnnls（無 sparsity 約束）
                    [A, Y, numIter, tElapsed, finalResidual] = nmfnnls(data, k, option);
                catch ME
                    fprintf('nmfnnls 失敗: EMG_data{%d}.normalize{%d, %d}, K=%d\n', i, band, clip, k);
                    disp(ME.message);
                    continue;
                end

                reconstructed = A * Y;

                % 計算 VAF
                SST = sum(sum((data - mean(data, 'all')).^2));  % 總變異
                SSE = sum(sum((data - reconstructed).^2));      % 殘差平方和
                VAF_per_k(k_idx) = 1 - (SSE / SST);

                % 計算 relative residual
                data_norm = norm(data, 'fro');
                relative_residual = finalResidual / data_norm;

                % 儲存結果
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

%% select the best K (by transitional stages)

% 設定參數
k_range = 1:8;
threshold_vaf = 0.9;
num_shuffle = 100;
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};
num_stages = length(transient_stages);

% 初始化
K_candidates_by_stage = cell(1, num_stages);
threshold_deltaVAF_all = cell(length(EMG_data), 1);

% 第一階段：收集所有符合條件的 K
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

            % Shuffle 計算 threshold
            all_deltas = [];
            for s = 1:num_shuffle
                shuffled = VAF_per_k(randperm(length(VAF_per_k)));
                all_deltas = [all_deltas, diff(shuffled)];
            end
            % Original heuristic retained. This is NOT a 75th percentile.
            % The report/code discrepancy is documented in docs/METHODS.md.
            threshold_deltaVAF = abs(0.75 * median(all_deltas));
            threshold_deltaVAF_all{i}(j, k) = threshold_deltaVAF;

            % 篩選符合條件的 K 值
            valid_Ks = k_range((VAF_per_k >= threshold_vaf) & ([0, deltaVAF] >= threshold_deltaVAF));

            % 儲存至對應 stage
            if k <= num_stages && ~isempty(valid_Ks)
                K_candidates_by_stage{k} = [K_candidates_by_stage{k}, valid_Ks(1)]; % 取最小有效 K
            end
        end
    end
end

% 第二階段：統計每個 stage 的眾數 K
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

% 第三階段：根據統一的 mode_K_by_stage 選擇 NMF 結果
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


% 平均計算所有 relative Residual 
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

% 計算平均
if ~isempty(all_relative_residuals)
    mean_relative_residual = mean(all_relative_residuals);
    fprintf('平均 relative residual：%.6f\n', mean_relative_residual);
else
    warning('沒有找到任何 relativeResidual 資料可以計算平均。');
end

%% Plot Synergy Count vs VAF & Synergy Count vs ΔVAF

% 設定參數
k_range = 1:8;

% 設置保存圖片的路徑
save_path = fullfile(paths.results_root, 'EMG_synergy_vs_VAF');

% 確保資料夾存在
if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% 頻段與階段標籤
freq_bands = {
    [10, 30],       
    [30, 45], 
    [45, 120], 
    [135, 280]
};

transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

for subj = 1:length(VAF_results)

    % 確保子層為 cell array 且非空
    if isempty(VAF_results{subj}) || ~iscell(VAF_results{subj})
        fprintf('跳過無效 subject：VAF_results{%d}\n', subj);
        continue;
    end

    % 自動取得子 cell 的大小（row: freq, col: stage）
    [num_freq, num_stage] = size(VAF_results{subj});

    for i = 1:num_freq  % freq band
        for j = 1:num_stage  % transient stage

            % 檢查是否為空
            if isempty(VAF_results{subj}{i, j})
                fprintf('跳過無效 VAF 結果: VAF_results{%d}{%d,%d}\n', subj, i, j);
                continue;
            end

            % 定義當前階段名稱
            stage_name = transient_stages{j};
            % 將階段名稱轉為檔名可用格式（去除空格）
            stage_name_clean = regexprep(stage_name, '\s+', '_');

            % 資料取得
            VAF = VAF_results{subj}{i, j}.VAF;  
            deltaVAF = VAF_results{subj}{i, j}.deltaVAF;
            threshold_deltaVAF = threshold_deltaVAF_all{subj}(i, j);

            % 畫圖
            figure;

            % 第一張圖：VAF
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
            
            % 計算 deltaVAF 對應的 K 組合（例如 K=1→2, 2→3, ..., 7→8）
            delta_labels = arrayfun(@(k) sprintf('%d→%d', k, k+1), k_range(1:end-1), 'UniformOutput', false);

            % 第二張圖：ΔVAF
            subplot(2, 1, 2);
            plot(k_range(2:end), deltaVAF, '-o', 'LineWidth', 1.5, 'MarkerSize', 6, 'Color', 'b');
            hold on;
            hline2 = yline(threshold_deltaVAF, '--r', 'LineWidth', 1.5);
            hold off;
            title('Synergy Count vs ΔVAF', 'FontSize', 14);
            xlabel('Synergy Pair (K → K+1)', 'FontSize', 12);
            ylabel('ΔVAF', 'FontSize', 12);
            xticks(k_range(2:end));
            xticklabels(delta_labels);  % 用 K→K+1 的文字作為 x 軸
            grid on;
            legend(hline2, sprintf('Shuffle heuristic (%.4f)', threshold_deltaVAF), 'Location', 'northeast');

            % 主標題
            sgtitle(sprintf('path2_%02d - %s - %d-%d Hz' ,  ...
                subj, stage_name, freq_bands{i}(1), freq_bands{i}(2)), ...
                'Interpreter', 'none');

            % 建立儲存檔名（將空格換成底線以避免路徑問題）
            save_filename = sprintf('path2_%02d_%s_frequency_%d-%dHz.png', ...
                subj, stage_name_clean, freq_bands{i}(1), freq_bands{i}(2));

            % 組合完整儲存路徑
            save_fullpath = fullfile(save_path, save_filename);

            % 儲存圖檔
            saveas(gcf, save_fullpath);
            close(gcf);

        end
    end
end

%% Match repeated-trial synergies: cosine k-means and one-to-one matching

% 設置保存圖片的路徑
save_path = fullfile(paths.results_root, 'EMG_synergy_distance_matrix_path2');

% 確保資料夾存在
if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% 頻率區段
freq_bands = {
    [10, 30],
    [30, 45],
    [45, 120],
    [135, 280]
};

% 動作階段
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

synergy_matching = cell(length(freq_bands), length(transient_stages), length(best_nmf));
consensus_synergies = cell(length(freq_bands), length(transient_stages));
avg_silhouette_scores = nan(length(freq_bands), length(transient_stages));

% 初始化儲存空間
for i = 1:length(best_nmf)
    for band = 1:length(freq_bands)
        for clip = 1:length(transient_stages)
            EMG_data{i}.reordered.A{band, clip} = [];
            EMG_data{i}.reordered.Y{band, clip} = [];
        end
    end
end

for clip = 1:length(transient_stages)
    common_K = mode_K_by_stage(clip);  % 每個 clip 的最佳 synergy 數量

    for band = 1:length(freq_bands)
        all_synergies = [];
        subject_synergies = {};
        subject_activations = {};

        % 收集所有 subject 的 synergy
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

        % 執行 k-means clustering 找共識 synergy
        [cluster_idx, cluster_centers] = kmeans(all_synergies, common_K, ...
            'Distance', 'cosine', 'Replicates', 20, 'MaxIter', 10000);

        consensus_synergies{band, clip} = cluster_centers;

        silhouette_scores = silhouette(all_synergies, cluster_idx, 'cosine');
        avg_silhouette = mean(silhouette_scores);
        avg_silhouette_scores(band, clip) = avg_silhouette;

        % 計算所有 subject 的距離矩陣並平均（使用 reorder 後的 A）
        dist_mats = zeros(common_K, common_K, length(subject_synergies));
        valid_subjects = 0;

        for i = 1:length(subject_synergies)
            A = subject_synergies{i};
            Y = subject_activations{i};
            if isempty(A)
                continue;
            end

            % 配對
            A_t = A';  % K × muscles
            dist_tmp = pdist2(A_t, cluster_centers, 'cosine');  % K × K
            matching = matchpairs(dist_tmp, 1);  % K x 2

            % 依據共識順序重排 A 與 Y
            reordered_A = zeros(size(A,1), common_K);  % muscles × K
            reordered_Y = zeros(common_K, size(Y,2));  % K × time

            for m = 1:common_K
                idx = find(matching(:, 2) == m);
                if ~isempty(idx)
                    reordered_A(:, m) = A(:, matching(idx, 1));
                    reordered_Y(m, :) = Y(matching(idx, 1), :);
                end
            end

            % 儲存重排後的資料
            EMG_data{i}.reordered.A{band, clip} = reordered_A;
            EMG_data{i}.reordered.Y{band, clip} = reordered_Y;
            synergy_matching{band, clip, i} = matching;

            % 使用 reordered_A 計算 distance matrix
            reordered_A_t = reordered_A';  % K × muscles
            dist_mat = pdist2(reordered_A_t, cluster_centers, 'cosine');  % K × K

            dist_mats(:, :, i) = dist_mat;
            valid_subjects = valid_subjects + 1;
        end

        if valid_subjects == 0
            warning('Band %d Clip %d 沒有有效 subject 進行平均距離矩陣。\n', band, clip);
            continue;
        end

        % 平均距離矩陣
        mean_dist_mat = mean(dist_mats(:, :, 1:valid_subjects), 3);

        % --- 繪製平均距離矩陣 ---
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

        % 儲存圖檔
        stage_str = strrep(stage_name, ' ', '_');
        filename = sprintf('mean_distance_matrix_%d-%dHz_%s.png', ...
            band_range(1), band_range(2), stage_str);
        saveas(gcf, fullfile(save_path, filename));
        close(gcf);
    end
end

%% Plot Synergy Coefficient（A） & Synergy Activation Pattern（Y） 

% 儲存圖檔的資料夾路徑
save_folder = fullfile(paths.results_root, 'EMG_synergy_individual');
if ~exist(save_folder, 'dir')
    mkdir(save_folder);
end

% 肌肉標籤
muscle_labels = {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 頻率區段
freq_bands = {
    [10, 30];
    [30, 45];
    [45, 120];
    [135, 280];
};

% 動作階段名稱
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% 插值長度
resample_len = 1000;
x_target = linspace(0, 1, resample_len);

for stage_idx = 1:length(transient_stages)
    stage_name = transient_stages{stage_idx};
    clip = stage_idx;
    common_K = mode_K_by_stage(stage_idx);  % 各階段 Synergy 數

    for band_idx = 1:length(freq_bands)
        freq_range = freq_bands{band_idx};

        for subj_idx = 1:length(EMG_data)
            A = EMG_data{subj_idx}.reordered.A{band_idx, clip};
            Y = EMG_data{subj_idx}.reordered.Y{band_idx, clip};

            % 檢查資料有效性
            if isempty(A) || isempty(Y)
                fprintf('Trial %d 無資料，跳過。\n', subj_idx);
                continue;
            end

            if size(A, 1) ~= length(muscle_labels) || size(A, 2) ~= common_K || size(Y, 1) ~= common_K
                fprintf('Trial %d A 或 Y 維度與 K=%d 不符，跳過。\n', subj_idx, common_K);
                continue;
            end

            % 插值 Y
            x_orig = linspace(0, 1, size(Y, 2));
            Y_interp = zeros(common_K, resample_len);
            for k = 1:common_K
                Y_interp(k, :) = interp1(x_orig, Y(k, :), x_target, 'linear');
            end

            % 繪圖
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

            % 儲存圖片
            save_filename = sprintf('Trial%02d_%s_%d-%dHz.png', ...
                subj_idx, strrep(stage_name, ' ', '_'), freq_range(1), freq_range(2));
            save_path = fullfile(save_folder, save_filename);
            saveas(gcf, save_path);
            close(gcf);
        end
    end
end

%% Plot Average Synergy Coefficient（A） &  Average Synergy Activation Pattern（Y） 

% 儲存圖檔的資料夾路徑
save_folder = fullfile(paths.results_root, 'EMG_synergy_A_Y_path2');
if ~exist(save_folder, 'dir')
    mkdir(save_folder);
end

% 肌肉標籤
muscle_labels = {'LGA', 'RGA', 'LTA', 'RTA', 'LBF', 'RBF', 'LRF', 'RRF'};

% 頻率區段
freq_bands = {
    [10, 30];
    [30, 45];
    [45, 120];
    [135, 280];
};

% 動作階段名稱
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% 初始化儲存結構（freq_band × stage）
Y_avg_all = cell(length(freq_bands), length(transient_stages));
A_avg_all = cell(length(freq_bands), length(transient_stages));

for stage_idx = 1:length(transient_stages)
    stage_name = transient_stages{stage_idx};
    clip = stage_idx;
    common_K = mode_K_by_stage(stage_idx);  % 各階段共有的 Synergy 數

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

        % ------- 插值並平均 Y（500 個時間點） -------
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

        Y_avg = mean(Y_interp_all, 3);  % 平均後的 Y
        Y_avg_all{band_idx, stage_idx} = Y_avg;

        % ------- 平均 A 與標準差 -------
        A_stack = cat(3, A_all{:});
        A_avg = mean(A_stack, 3);
        A_std = std(A_stack, 0, 3);

        A_avg_all{band_idx, stage_idx} = struct( ...
            'A_avg', A_avg, ...
            'A_std', A_std, ...
            'subject_indices', subject_indices ...
        );

        % ------- 繪圖 -------
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

% 儲存 A_avg_all 和 Y_avg_all
save(fullfile(save_folder, 'EMG_synergy_summary.mat'), 'A_avg_all', 'Y_avg_all');

%% spectrogram for muscle syngery

% 動作階段名稱
transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% 頻率區段（肌肉用）
freq_bands = {
    [10, 30];
    [30, 45];
    [45, 120];
    [135, 280];
};

% 取樣頻率
fs = 1000;

% 儲存路徑
output_folder = fullfile(paths.results_root, 'spectrogram');
if ~exist(output_folder, 'dir')
    mkdir(output_folder);
end

% ========== 建立 window 設定（根據頻段中心頻率） ==========
stft_config = containers.Map;
for s = 1:length(transient_stages)
    for b = 1:size(freq_bands,1)
        key = sprintf('%d_%d', s, b);
        center_freq = mean(freq_bands{b});
        ideal_win = round((1 / center_freq) * fs * 4); % 四個週期
        stft_config(key) = struct( ...
            'win_len', ideal_win, ...
            'overlap', floor(ideal_win * 0.5));
    end
end

% ========== 計算全域色階範圍 ========== 
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

% ========== 畫圖 ========== 
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

        % 用 tiledlayout 來避免重疊
        fig = figure('Name', sprintf('Stage: %s | Band: %d–%dHz', ...
            transient_stages{stage}, band_range(1), band_range(2)), ...
            'NumberTitle', 'off', 'Visible', 'off', ...
            'Position', [100, 100, 1000, 200 + 200*K]);  % 根據通道數調整高度

        t = tiledlayout(K, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
        title(t, sprintf('Spectrogram - %s | %d–%d Hz', ...
            transient_stages{stage}, band_range(1), band_range(2)), ...
            'FontWeight', 'bold', 'FontSize', 14);

        for k = 1:K
            signal = Y_avg(k, :);
            [~, F, T, P] = spectrogram(signal, window, overlap, nfft, fs);
            P_dB = 10 * log10(abs(P) + eps);

            % 只保留頻段範圍
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

        % 建立 colorbar 在整張圖右側
        cb = colorbar('Position', [0.93 0.1 0.02 0.8]); % 自訂位置（視圖大小調整）
        cb.Label.String = 'Power (dB)';
        cb.FontSize = 10;

        filename = sprintf('Spectrogram_Stage%d_%s_Band_%d-%dHz.png', ...
            stage, strrep(transient_stages{stage}, ' ', '_'), ...
            band_range(1), band_range(2));
        exportgraphics(fig, fullfile(output_folder, filename), 'Resolution', 300);
        close(fig);
    end
end

%% stft

% 輸出資料夾
output_folder_stft = fullfile(paths.results_root, 'stft');
if ~exist(output_folder_stft, 'dir')
    mkdir(output_folder_stft);
end

% ========== 計算全域色階 ==========
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

% ========== 畫圖 ==========
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

            % 裁切頻率
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
        
        % 統一 colorbar
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



