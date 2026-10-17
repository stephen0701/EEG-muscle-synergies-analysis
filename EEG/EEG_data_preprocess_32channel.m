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
files = dir(fullfile(folder_path, 'EEG_path2_*.csv'));

% 預先分配 cell array 來儲存每個檔案的數據
EEG_data = cell(1, numel(files));

% 讀取每個檔案的數據並儲存至 cell array 中
for i = 1:numel(files)
    try
        % 組合完整檔案路徑
        file_path = fullfile(files(i).folder, files(i).name);
        
        % 初始化為結構體
        EEG_data{i} = struct();  

        % 使用 readtable 函數讀取 CSV 檔案
        EEG_data_table = readtable(file_path, 'VariableNamingRule', 'preserve');
        
        % table 轉成 array 並儲存到 cell array 中
        EEG_data{i}.original = table2array(EEG_data_table);
        
        % 預設其他欄位為空
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
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error reading file %s: %s', files(i).name, ME.message);
    end
end

% 顯示已成功讀取的檔案數量
num_files_read = sum(cellfun(@(x) ~isempty(x.original), EEG_data));
disp(['已成功讀取 ', num2str(num_files_read), ' 個檔案。']);

%% data alignment (linear interpolate for missing data)

% 記得更改 end_idx - start_idx 的範圍（先查看資料長度）

n1 = 35; % event id column
n2 = 38; % software id column
serial_number = 2; % serial number column
start_event = 130; % 紅燈亮
end_event = 141; % 綠燈暗
columns_to_process = 3:34; % 指定要處理的列(只要channel)

% 保存不連續數據的 cell array
non_continuous_data = {};

% 初始化 start_indices 和 end_indices
num_files = numel(EEG_data);
start_indices = nan(1, num_files); % 使用 NaN 預分配
end_indices = nan(1, num_files);   % 使用 NaN 預分配

% 對每個檔案進行數據對齊
for i = 1:num_files
    try
        EEG_data_array = EEG_data{i}.original;  % 從 cell array 中提取數據

        % 確保數據存在
        if isempty(EEG_data_array)
            disp(['檔案無效或未讀取成功: ', files(i).name]);
            continue;  % 跳過此檔案，繼續處理下一個
        end

        % 使用 n1 尋找 start 和 end index
        logical_start = EEG_data_array(:, n1) == start_event;
        logical_end = EEG_data_array(:, n1) == end_event;

        % 找到第一個和最後一個符合條件的索引
        start_idx = find(logical_start, 1);
        end_idx = find(logical_end, 1, 'last');

        % 如果 n1 找不到 start 或 end，使用 n2 再試一次
        if isempty(start_idx) || isempty(end_idx) %|| ...
           %(end_idx - start_idx < 11000) || (end_idx - start_idx > 13000)
            disp(['event id 找不到有效的索引，使用 software marker: ', files(i).name]);
            logical_start = EEG_data_array(:, n2) == start_event;
            logical_end = EEG_data_array(:, n2) == end_event;
            start_idx = find(logical_start, 1);
            end_idx = find(logical_end, 1, 'last');
        end

        % 確保找到 start 和 end index
        if isempty(start_idx) || isempty(end_idx) %|| ...
           %(end_idx - start_idx < 11000) || (end_idx - start_idx > 13000)
            disp(['無法找到有效的開始或結束索引: ', files(i).name]);
            continue;  % 跳過此檔案，繼續處理下一個
        end

        % 保存 start_idx 和 end_idx 到相應位置
        start_indices(i) = start_idx;
        end_indices(i) = end_idx;

        % 提取從第一個130到最後一個141之間的數據
        aligned_data = EEG_data_array(start_idx:end_idx, :);
        EEG_data{i}.alignment = aligned_data;

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

                % 對第 1 列到第 34 列數據進行線性插值
                for col = 1:34  % 只處理第 1 列到第 34 列
                    valid_idx = ~isnan(complete_data(:, col));
                    if sum(valid_idx) < 2
                        disp(['警告: 檔案 ', files(i).name, ' 的列 ', num2str(col), ' 沒有足夠的有效數據進行插值。']);
                        continue;
                    end

                    complete_data(:, col) = interp1(full_range(valid_idx), complete_data(valid_idx, col), full_range, 'linear');
                end

                EEG_data{i}.alignment = complete_data;
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
    time_EEG{i} = cell(1, numel(files));
    time_EEG{i} = EEG_data{i}.alignment(:,1);

    % 只留下channel的部分    
    EEG_data{i}.alignment = EEG_data{i}.alignment(:,columns_to_process);

    catch ME
        warning('對齊檔案 %s 時發生錯誤: %s', files(i).name, ME.message);
    end
end

% 顯示已成功對齊的檔案數量
num_files_aligned = sum(~isnan(start_indices));
disp(['已成功對齊 ', num2str(num_files_aligned), ' 個檔案。']);

% 顯示每個 EEG_data.alignment 的 array 
for i = 1:num_files
    if isfield(EEG_data{i}, 'alignment') && ~isempty(EEG_data{i}.alignment)
        [rows, cols] = size(EEG_data{i}.alignment);
        disp(['EEG_data', num2str(i), '.alignment', num2str(rows), ' x ', num2str(cols)]);
    else
        disp(['檔案 ', num2str(i), ' 的 alignment 未對齊或為空。']);
    end
end

%% reduce mean

% 定義電極名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% 取樣頻率
fs = 500;

% 設定圖例名稱
legend_names = {'Alignment data', 'Reduce mean data'};

% 對每個檔案進行 reduce mean 操作
for i = 1:numel(EEG_data)

    try
        % 檢查對齊數據是否存在
        if isempty(EEG_data{i}.alignment)
            disp(['無法處理檔案: ', files(i).name, ' (alignment 為空)']);
            continue;  % 跳過此檔案，繼續處理下一個
        end
    
        % 計算並減去每列的平均值
        EEG_data{i}.reducemean = EEG_data{i}.alignment - mean(EEG_data{i}.alignment, 1);
   
    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error reducing mean in file %s: %s', files(i).name, ME.message);
    end
end

% 顯示已成功處理 reduce mean 的檔案數量
num_files_reducemean = sum(cellfun(@(x) ~isempty(x.reducemean), EEG_data));
disp(['已成功對 ', num2str(num_files_reducemean), ' 個檔案進行 reducemean 處理。']);

% 畫圖檢查結果
raw_data = EEG_data{1, 1}.alignment;
processed_data = EEG_data{1, 1}.reducemean;
plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names);

%% detrend

% 定義電極名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% 取樣頻率
fs = 500;

% 設定圖例名稱
legend_names = {'Reduce mean data', 'Detrend data'};

% 對每個檔案進行 detrend 操作
for i = 1:numel(EEG_data)

    try
        % 確保文件包含 reducemean 且不為空
        if isfield(EEG_data{i}, 'reducemean') && ~isempty(EEG_data{i}.reducemean)

        % 進行 detrend
        EEG_data{i}.detrend = detrend(EEG_data{i}.reducemean);

        else
            warning('reducemean field is empty or missing for file %d.', i);
        end

    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error detrend in file %s: %s', files(i).name, ME.message);
    end

end

% 顯示已成功進行 detrend 處理的檔案數量
num_files_detrended = sum(cellfun(@(x) isfield(x, 'detrend') && ~isempty(x.detrend), EEG_data));
disp(['已成功對 ', num2str(num_files_detrended), ' 個檔案進行 detrend 處理。']);

% 畫圖檢查結果
raw_data = EEG_data{1, 1}.reducemean;
processed_data = EEG_data{1, 1}.detrend;
plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names);

%% notch filter

% 定義電極名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% 取樣頻率
fs = 500;

% 設定圖例名稱
legend_names = {'Detrend data', 'Notch filter data'};

% 設計 notch 濾波器
fc = 60; % 濾波器中心頻率 60Hz (範圍 59-61)
[b, a] = designNotchPeakIIR('CenterFrequency', fc/(fs/2), 'Bandwidth', 2/(fs/2), 'Response', 'notch');

% 對每個檔案進行 notch 濾波器操作
for i = 1:numel(EEG_data)
    try
        % 檢查 detrend 數據是否存在
        if isfield(EEG_data{i}, 'detrend') && ~isempty(EEG_data{i}.detrend)
                   
        % 對指定列用 notch 濾波器，並將結果存入 EEG_data.notchfilter 對應的列
        EEG_data{i}.notchfilter = filtfilt(b, a, EEG_data{i}.detrend);
            
        else
            warning('detrend field is empty or missing for file %d.', i);
        end
        
    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error applying notch filter to file %d: %s', i, ME.message);
    end
end

% 顯示已成功進行 notch filter 處理的檔案數量
num_files_notchfiltered = sum(cellfun(@(x) isfield(x, 'notchfilter') && ~isempty(x.notchfilter), EEG_data));
disp(['已成功對 ', num2str(num_files_notchfiltered), ' 個檔案進行 notch filter 處理。']);

% 畫圖檢查結果
raw_data = EEG_data{1, 1}.detrend;
processed_data = EEG_data{1, 1}.notchfilter;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

%% butterworth filter

% 定義電極名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% 取樣頻率
fs = 500;

% 設定圖例名稱
legend_names = {'Notch filter data', 'Butterworth filter data'};

% 設計 Butterworth 濾波器
order = 4; % 濾波器階數  
fc_low = 0.5; % 低截止頻率
fc_high = 70; % 高截止頻率
Wn = [fc_low/(fs/2), fc_high/(fs/2)]; % 歸一化截止頻率
[b, a] = butter(order, Wn, 'bandpass'); % 設計帶通濾波器

% 對每個檔案進行 butterworth  濾波器操作
for i = 1:numel(EEG_data)
    try
        % 檢查 notchfilter 數據是否存在
        if isfield(EEG_data{i}, 'notchfilter') && ~isempty(EEG_data{i}.notchfilter)

        % 使用 butterworth 濾波器，並將結果存入 EEG_data.butterworthfilter
        EEG_data{i}.butterworthfilter = filtfilt(b, a, EEG_data{i}.notchfilter);

        else
            warning('notchfilter field is empty or missing for file %d.', i);
        end
        
    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error applying butterworth filter to file %d: %s', i, ME.message);
    end
end

% 顯示已成功進行 butterworth filter 處理的檔案數量
num_files_butterworthfiltered = sum(cellfun(@(x) isfield(x, 'butterworthfilter') && ~isempty(x.butterworthfilter), EEG_data));
disp(['已成功對 ', num2str(num_files_butterworthfiltered), ' 個檔案進行 butterworth filter 處理。']);

% 畫圖檢查結果
raw_data = EEG_data{1, 2}.notchfilter;
processed_data = EEG_data{1, 2}.butterworthfilter;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

%% ASR & re-reference 

% 載入eeglab
eeglab;

% 設定圖例名稱
legend_names = {'Butterworth filter data', 'ASR data'};

for i = 1:numel(EEG_data)
    try
        % 確保 butterworthfilter 數據存在
        if ~isempty(EEG_data{i}.butterworthfilter)

            % 提取數據並轉置 (eeglab 的資料需要轉置)
            data = EEG_data{i}.butterworthfilter'; 
            sample_rate = 500; % 取樣率
            threshold = 10; % ASR 的閾值 (可以設置 10 或 20)

            % 呼叫 ASR 函數並接收返回的 ASRbase 和 ASRmove
            [EEG, ASRbase, ASRmove] = ASR(data, sample_rate, threshold, paths.channel_locations);
            
            % 將 ASRbase 和 ASRmove 的資料分別存入 EEG_data
            EEG_data{i}.asr = EEG.data';
            
            EEG_data{i}.asrbase = ASRbase.data;
            EEG_data{i}.asrmove = ASRmove.data;

        else
            disp(['File ', num2str(i), ' has no butterworthfiltered data']);
        end
        
    catch ME
        % 捕捉錯誤並顯示錯誤訊息
        warning('Error processing ASR for file %d: %s', i, ME.message);
    end
end

% 顯示已成功進行 ASR 處理的檔案數量
num_files_asrprocessed = sum(cellfun(@(x) isfield(x, 'asr') && ~isempty(x.asr), EEG_data));
disp(['已成功對 ', num2str(num_files_asrprocessed), ' 個檔案進行 ASR 處理。']);

% 畫圖檢查結果
raw_data = EEG_data{1, 1}.butterworthfilter;
processed_data = EEG_data{1, 1}.asr;
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

% ASR 函數定義

function [EEG, ASRbase, ASRmove] = ASR(data, sample_rate, threshold, channel_locations)
    % 導入數據
    EEG = pop_importdata('dataformat', 'array', 'nbchan', 0, 'data', data, 'srate', sample_rate, 'pnts', 0, 'xmin', 0);
    EEG = eeg_checkset(EEG);

    % 載入通道位置
    EEG = pop_chanedit(EEG, 'load', {channel_locations, 'filetype', 'autodetect'});
    EEG = eeg_checkset(EEG);

    % ASR校正
    basetimpoint = 10*sample_rate;
    %basetimpoint = min(10 * sample_rate, size(EEG.data, 2)); % 基線長度為 10 秒，或數據長度不足時取數據的總長度
    baselinedata = EEG.data(:, 1:basetimpoint); % 提取基線數據

    % 計算 ASR 狀態
    state = asr_calibrate(baselinedata, sample_rate, threshold);
    [EEG.data, state] = asr_process(EEG.data, sample_rate, state, 0.5, 0);
    EEG = eeg_checkset(EEG);

    % 重新參考
    EEG = pop_reref(EEG, []); % 自動重新參考
    EEG = eeg_checkset(EEG);

    % 分離基準資料和動作資料
    ASRbase = EEG;
    ASRbase.data = EEG.data(:, 1:basetimpoint);
    ASRbase.pnts = size(ASRbase.data, 2);
    ASRbase = eeg_checkset(ASRbase);

    ASRmove = EEG;
    ASRmove.data = EEG.data(:, basetimpoint + 1:end);
    ASRmove.pnts = size(ASRmove.data, 2);
    ASRmove = eeg_checkset(ASRmove);
end

%% import data to eeglab (準備做ICA)

% 創建一個 cell array 來存儲提取的數據
extracted_data = cell(length(EEG_data), 1);

% 遍歷所有的 EEG_data
for i = 1:length(EEG_data)

    % 確保 EEG_data{i} 有 'asr' 字段
    if isfield(EEG_data{i}, 'asr')
        
        % 獲取 'asr' 的列數
        num_columns = size(EEG_data{i}.asr, 2);

        % 提取需要處理的數據並轉置
        data = EEG_data{i}.asr';

        % 將提取的數據存儲到 cell array 中
        extracted_data{i} = data;

    else
        % 如果 'asr' 字段不存在，顯示警告
        warning('EEG_data{%d} does not contain ''asr'' field.', i);
        
        % 存儲空數據
        extracted_data{i} = [];
    end
end

% 遍歷所有的 extracted_data
for i = 1:length(extracted_data)
    
    % 生成變數名稱， 'Data1', 'Data2', ...
    var_name = sprintf('Data%d', i);
    
    % 使用 eval 動態創建變數
    eval([var_name ' = extracted_data{i};']);
end

% 檢查創建的變數
disp('Extracted data variables:');
whos('Data*');

%% Import .set files after manual ICA in EEGLAB

% 定義電極名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% 取樣頻率
fs = 500;

% 設定圖例名稱
legend_names = {'ASR data', 'ICA data'};

% 文件夾路徑
folder_path = paths.ica_dir;

% 搜索所有 .set 文件
set_files = dir(fullfile(folder_path, '*.set'));

% 迴圈讀取每一個 .set 文件，使用實際的文件數量
for i = 1:length(set_files)
    try
        % 取得當前文件名
        current_file_name = set_files(i).name;
        
        % 提取文件名中的數字部分（如 "Data1" 中的 1）
        file_num_str = regexp(current_file_name, '\d+', 'match');
        
        if ~isempty(file_num_str)
            % 將文件名中的數字轉換為數值
            file_num = str2double(file_num_str{1});
            
            % 加載 .set 文件
            set_file_path = fullfile(set_files(i).folder, current_file_name);
            EEG = pop_loadset('filename', set_file_path);
                        
            % 將數據存儲到對應的 .ica 欄位，不覆蓋其他欄位
            EEG_data{file_num}.ica = EEG;  
            
            fprintf('已加載: %s 並存儲到 EEG_data{%d}.ica\n', current_file_name, file_num);
        else
            fprintf('文件名 %s 中未提取到數字，跳過該文件。\n', current_file_name);
        end
    
    catch ME
        % 如果有錯誤，顯示錯誤信息並繼續執行
        fprintf('加載 %s 時發生錯誤: %s\n', current_file_name, ME.message);
    end
end

% 顯示已成功進行 ICA 處理的檔案數量
num_files_asrprocessed = sum(cellfun(@(x) isfield(x, 'ica') && ~isempty(x.ica), EEG_data));
disp(['已成功對 ', num2str(num_files_asrprocessed), ' 個檔案進行 ICA 處理。']);

% 畫圖檢查結果
raw_data = EEG_data{1, 1}.asr;
processed_data = EEG_data{1, 1}.ica.data';
plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names);

%% Zcore 

% 定義電極名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};
% 取樣頻率
fs = 500;

% 設定圖例名稱
legend_names = {'ICA data', 'Zcore data'};

for i = 1:length(EEG_data)
    try
        % 檢查 EEG_data{i} 是否包含 'ica' 和 'asr' 字段
        if isfield(EEG_data{i}, 'ica') && isfield(EEG_data{i}.ica, 'data') && isfield(EEG_data{i}, 'asr')
            data = EEG_data{i}.ica.data;  % 取出每筆資料
            zcore_data = zscore(data, 0, 2); % 對每一行進行 Z-score
            
            EEG_data{i}.zcore = zcore_data';  % 將結果存入 zcore
        else
            warning('EEG_data{%d} 不包含必要的字段', i);
        end
    catch ME
        % 捕捉到錯誤，顯示錯誤訊息但繼續處理下一筆資料
        warning('處理 EEG_data{%d} 時發生錯誤：%s', i, ME.message);
        continue;
    end
end

% 顯示已成功進行 Zcore 處理的檔案數量
num_files_asrprocessed = sum(cellfun(@(x) isfield(x, 'zcore') && ~isempty(x.zcore), EEG_data));
disp(['已成功對 ', num2str(num_files_asrprocessed), ' 個檔案進行 Zcore 處理。']);

% 畫圖檢查結果
raw_data = EEG_data{1, 1}.ica.data';
processed_data = EEG_data{1, 1}.zcore;
plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names);

%% plotting data at each processing stage

% 檔案資料夾路徑
folder_path = paths.data_root;

% 取得 eeg_path1_*.csv 檔案
files = dir(fullfile(folder_path, 'EEG_path1_*.csv'));

% sample rate
fs = 500; 

% 定義處理階段及對應字段
stages = {'alignment', 'reducemean', 'detrend', 'notchfilter', 'butterworthfilter', 'asr'};

for i = 1:numel(EEG_data)
    
    % 檢查所有處理階段數據是否存在
    missing_stage = false;
    for stage = stages
        if isempty(EEG_data{i}.(stage{1}))
            disp(['檔案: ', files(i).name, ' 缺少 ', stage{1}, ' 的數據']);
            missing_stage = true; 
            break;  % 如果有一個階段缺失，跳過此檔案
        end
    end
    
    % 檢查 EEG_data.ica 是否存在，並檢查其 data 是否存在
    if ~isfield(EEG_data{i}, 'ica') || isempty(EEG_data{i}.ica) || isempty(EEG_data{i}.ica.data)
        disp(['檔案: ', files(i).name, ' 缺少 ICA 的數據']);
        continue;
    end
    
    if missing_stage
        continue;
    end
    
    % 建立新圖表
    figure;
    
    % 使用迴圈繪製各處理階段
    for j = 1:length(stages)
        subplot(8, 1, j);  % 8張圖
        time_axis = (0:size(EEG_data{i}.(stages{j}), 1)-1) / fs;  % 計算時間軸
        
        % 合併 channel 資料 (取平均值)
        merged_data = mean(EEG_data{i}.(stages{j}), 2);  % 每行取平均值
        
        % 繪製合併後的數據
        plot(time_axis, merged_data);
        title([upper(stages{j}(1)), stages{j}(2:end) ' Data'], 'Interpreter', 'none');
        xlabel('Time (s)');  % 更改 x 軸標籤為時間
        ylabel('Voltage (µV)');
    end
    
    % 繪製 EEG_data.ica.data 的數據
    subplot(8, 1, 7);  % 在第 7 行繪製 ICA 數據
    time_axis_ica = (0:size(EEG_data{i}.ica.data, 2)-1) / fs;  % 計算 ICA 的時間軸
    
    % 合併 ICA 資料
    ica_merged = mean(EEG_data{i}.ica.data, 1);  % 取每列的平均值
    
    % 繪製合併後的 ICA 數據
    plot(time_axis_ica, ica_merged);
    title(['Ica Data'], 'Interpreter', 'none');
    xlabel('Time (s)');  % x 軸標籤為時間
    ylabel('Voltage (µV)');
    
    % 繪製 Zcore 的數據
    subplot(8, 1, 8);  % 在第 8 行繪製 Zcore 數據
    time_axis_zcore = (0:size(EEG_data{i}.zcore, 1)-1) / fs;  % 計算 Zcore 的時間軸
    
    % 合併 Zcore 資料
    zcore_merged = mean(EEG_data{i}.zcore, 2);  % 每行取平均值
    
    % 繪製合併後的 Zcore 數據
    plot(time_axis_zcore, zcore_merged);
    title(['Zcore Data'], 'Interpreter', 'none');
    xlabel('Time (s)');
    ylabel('Voltage (µV)');
    
    % 調整圖表布局
    sgtitle(['EEG Data Processing Stages for file: ', files(i).name], 'Interpreter', 'none');
end

%% EEG band-power topographies (qualitative comparison only)

% ====== 參數設定 ======
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

% STFT 設定
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

% ====== 初始化結果儲存 ======
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

% ====== STFT 計算 band power ======
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

% ====== 設定儲存路徑與 colorbar 模式 ======
base_path = fullfile(paths.results_root, 'topology_map_colorbar_compare');
colorbar_modes = {'global', 'stage', 'band'};

for m = 1:length(colorbar_modes)
    mode_path = fullfile(base_path, colorbar_modes{m});
    if ~exist(mode_path, 'dir')
        mkdir(mode_path);
    end
end

% ====== 計算各種 colorbar 範圍 ======
% global colorbar 範圍
all_power_values = [];
for c = 1:num_clips
    for b = 1:num_bands
        mat = avg_power_all{c, b};
        if isempty(mat), continue; end
        all_power_values = [all_power_values; mean(mat,2)];
    end
end
global_clim = [min(all_power_values), max(all_power_values)];

% 每個 stage 的 colorbar 範圍
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

% 每個 band 的 colorbar 範圍
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

% ====== 畫圖並儲存至對應資料夾 ======
for mode = colorbar_modes
    mode = char(mode);
    save_mode_path = fullfile(base_path, mode);

    for c = 1:num_clips
        for b = 1:num_bands
            mat = avg_power_all{c, b};
            if isempty(mat), continue; end
            avg_power = mean(mat, 2);

            % 設定 colorbar 範圍
            switch mode
                case 'global'
                    clim_val = global_clim;
                case 'stage'
                    clim_val = stage_clims(c,:);
                case 'band'
                    clim_val = band_clims(b,:);
            end

            % 畫 topography
            fig = figure('Visible', 'off');
            plot_topography(ch_list, avg_power);
            title(sprintf('%s - %s (%s colorbar)', ...
                band_params{b,1}, transient_stages{c}, mode), ...
                'Interpreter', 'none');
            colorbar;
            clim(clim_val);

            % 儲存圖片
            stage_name = strrep(transient_stages{c}, ' ', '_');
            fname = sprintf('%s_%s_%s.png', stage_name, band_params{b,1}, mode);
            saveas(fig, fullfile(save_mode_path, fname));
            close(fig);
        end
    end
end

%% Fast Fourier transform (spectrum)

% channel 名稱
channels = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
            'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
            'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
            'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

% 設置保存圖片的路徑
save_path = fullfile(paths.results_root, 'fast_fourier_transform');

% 初始化頻率和能量的數組
for i = 1:length(EEG_data)

    for j = 1:length(EEG_data{i}.clip)
        
        % 獲取數據
        signal = EEG_data{i}.clip{j};
        
        % 確定信號長度
        N = size(signal, 1); % 行數（樣本數）
        
        % 初始化頻譜圖
        figure;
        
        % 逐列進行FFT處理
        for k = 1:size(signal, 2)
            
            % 取出第k列信號
            single_channel = signal(:, k);
            
            % 進行FFT
            Y = fft(single_channel);
            
            % 計算頻率軸
            fs = 500; 
            f = fs*(0:(floor(N/2)))/N;
            
            % 計算能量 (dB)
            P2 = abs(Y/N); % 雙邊頻譜
            P1 = P2(1:floor(N/2)+1); % 單邊頻譜
            P1(2:end-1) = 2*P1(2:end-1); % 調整振幅
            energy_dB = 10*log10(P1); % 能量轉換為 dB

            % 繪圖
            subplot(4, 8, k); % 每次繪製 4x8 的子圖
            plot(f(1:floor(N/2)+1), energy_dB);
            title(['Channel ' channels{k}]); % 使用 channel 名稱
            xlabel('Frequency (Hz)');
            ylabel('Power (dB)');
            xlim([0 100]);
            grid on;
        end
        
        % 設置圖像標題
        sgtitle(['FFT for path1\_', sprintf('%02d', i), ' clip ', num2str(j)]);
    
        % 保存圖形到指定路徑
        saveas(gcf, fullfile(save_path, ['FFT for path1_', sprintf('%02d', i), ' clip', num2str(j), '.png']));

        % 關閉圖形以節省資源
        close(gcf);
    end
end

%% Spectrogram with Frequency Bands 

% 設置保存圖片的路徑
save_path = fullfile(paths.results_root, 'spectrogram_new');

% 頻帶參數設定：{'名稱', [頻率範圍], window_size, overlap, nfft}
band_params = {
    'Delta',       [1 3],       1000, 967, 1024;
    'Theta',       [4 8],       250,  217, 512;
    'Alpha',       [9 12],      111,  78,  256;
    'Beta',        [13 30],     77,   44,  256;
    'Low Gamma',   [32 46],     66,   33,  256;
};


% 定義電極名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

% 採樣頻率
fs = 500;

% 處理每組數據
for i =1
%for i = 1:length(EEG_data)

    signal = EEG_data{i}.zcore;
    channel_count = size(signal, 2);
    
    % 每個通道繪製頻帶圖
    for ch = 1:channel_count
        figure;
        sgtitle(['Time-Frequency Analysis for path1\_', sprintf('%02d', i), ' Channel ', ch_list{ch}]);

        for b = 1:size(band_params, 1)
            band_name = band_params{b, 1};
            band_range = band_params{b, 2};
            window_size = band_params{b, 3};
            overlap = band_params{b, 4};
            nfft = band_params{b, 5};

            % 計算 STFT
            [s, f, t] = stft(signal(:, ch), fs, ...
                'Window', hann(window_size), ...
                'OverlapLength', overlap, ...
                'FFTLength', nfft);

            % 擷取該頻帶的資料
            band_idx = f >= band_range(1) & f <= band_range(2);
            if ~any(band_idx)
                warning(['Frequency band ', band_name, ' is out of range for channel ', ch_list{ch}]);
                continue;
            end

            s_band = s(band_idx, :);
            f_band = f(band_idx);
            power = abs(s_band).^2;

            % 繪圖
            subplot(3, 2, b);
            imagesc(t, f_band, 10 * log10(power));
            axis xy;
            xlabel('Time (s)');
            ylabel('Frequency (Hz)');
            title([band_name ' Band']);
            colormap jet;
            colorbar;
        end

        % 儲存圖形
        %saveas(gcf, fullfile(save_path, ...
        %sprintf('path1_%02d channel %s.png', i, ch_list{ch})));

        %close(gcf); % 關閉以節省記憶體
    end
end

%% Exploratory EEG-only PAC (not EEG-synergy coherence)

% 設置圖片存儲路徑
save_path = fullfile(paths.results_root, 'PAC');

if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% 設定頻率範圍
phase_freqs = 8:1:12;  % Alpha 頻帶 (8-12 Hz)
amp_freqs = 30:1:80;   % Gamma 頻帶 (30-80 Hz)
fs = 500;  % 取樣頻率 (Hz)

% 定義 32 通道名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

transient_stages = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'};

% 呼叫 PAC 計算函數
pac_results = PAC(EEG_data, phase_freqs, amp_freqs, fs, ch_list, save_path, transient_stages);

% 函數區塊
function pac_results = PAC(EEG_data, phase_freqs, amp_freqs, fs, ch_list, save_path, transient_stages)
    num_data = length(EEG_data);
    num_stages = length(transient_stages);
    pac_results = cell(1, num_stages);

    max_mi_global = -inf;  % << 新增：統一 MI-PAC 的 colorbar

    % ===== 第一次：找出最大 MI 值，並儲存 PAC 結果 =====
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

        % << 找最大 MI >>
        mi_max = max(pac_matrix.mi(:));
        if mi_max > max_mi_global
            max_mi_global = mi_max;
        end
    end

    % ===== 第二次：統一 clim 畫圖 =====
    for stage_idx = 1:num_stages
        result = pac_results{stage_idx};
        plot_pac_results(result.pac_matrix, phase_freqs, amp_freqs, ...
            result.subject, transient_stages{stage_idx}, result.channel, ...
            save_path, max_mi_global);
    end
end

% 計算 PAC
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

% 繪圖函數
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

% 設置圖片存儲路徑
save_path = fullfile(paths.results_root, 'bicoherence');
if ~exist(save_path, 'dir')
    mkdir(save_path);
end

% 定義 32 通道名稱
ch_list = {'Fp1', 'Fp2', 'AF3', 'AF4', 'F7', 'F3', 'Fz', 'F4', 'F8', ...
           'FT7', 'FC3', 'FCz', 'FC4', 'FT8', 'T7', 'C3', 'Cz', ...
           'C4', 'T8', 'TP7', 'CP3', 'CPz', 'CP4', 'TP8', ...
           'P7', 'P3', 'Pz', 'P4', 'P8', 'O1', 'Oz', 'O2'};

transient_stages = {'Sit_to_Stand', 'Stand_to_Walk', 'Walk_to_Stop'}; % 用於檔名不含空格
transient_stages_title = {'Sit to Stand', 'Stand to Walk', 'Walk to Stop'}; % 用於圖標題

num_stage = length(pac_results);

for stage_idx = 1:num_stage
    % 提取 PAC 結果資訊
    subject_idx = pac_results{stage_idx}.subject;
    trial_idx = pac_results{stage_idx}.trial;
    ch_name = pac_results{stage_idx}.channel;
    ch_idx = find(strcmp(ch_list, ch_name));

    % 擷取對應通道資料
    data = EEG_data{1, subject_idx}.clip{1, trial_idx}(:, ch_idx);

    % 設定參數
    fs = 500;
    segleng = 250;
    segshift = 125;
    epleng = size(data, 1);
    maxfreqbins = floor(segleng / 2);

    % 計算 bispectrum
    opt = struct;
    [cs, csnr, ~] = data2bs_univar(data, segleng, segshift, epleng, maxfreqbins, opt);

    % 頻率範圍設定
    df = fs / segleng;
    nf = maxfreqbins;
    alpha_idx = round(8 / df) + 1 : round(12 / df) + 1;
    gamma_idx = round(30 / df) + 1 : round(80 / df) + 1;
    alpha_idx(alpha_idx > nf) = [];
    gamma_idx(gamma_idx > nf) = [];

    % 計算 bicoherence
    bicoherence = abs(cs(:, alpha_idx, gamma_idx)) ./ (csnr(:, alpha_idx, gamma_idx) + eps);
    bicoherence_2d = squeeze(bicoherence);

    % 頻率標籤
    alpha_freqs = (alpha_idx - 1) * df;
    gamma_freqs = (gamma_idx - 1) * df;

    % 繪圖
    figure;
    imagesc(alpha_freqs, gamma_freqs, bicoherence_2d');  % gamma 為 y 軸
    set(gca, 'YDir', 'normal');
    xlabel('f1 (Hz)');
    ylabel('f2 (Hz)');
    title(sprintf('Bicoherence - Trial %d - %s (%s)', ...
        subject_idx,transient_stages_title{stage_idx} , ch_name));
    colorbar;
    clim([0 1]);  % 統一 colorbar 範圍為 [0, 1]
    xlim([min(alpha_freqs), max(alpha_freqs)])
    ylim([min(gamma_freqs), max(gamma_freqs)])

    % 儲存圖片（檔名不含空格）
    filename = sprintf('Bicoherence_trial%d_%s.png', ...
         subject_idx,transient_stages{stage_idx});
    saveas(gcf, fullfile(save_path, filename));
    close(gcf);
end

%%
