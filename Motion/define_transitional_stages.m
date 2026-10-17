% RESEARCH NOTE: This archive contains section-based research scripts.
% See docs/REPRODUCIBILITY.md before executing sections. Alternatives overwrite
% shared variables; running the entire file is not a verified report pipeline.
% Each legacy subject/subj index denotes a trial from ONE participant.
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(repo_root, fullfile(repo_root, 'Function'));
paths = research_paths();

%% read sync_time_marker.npz 

% 定義基礎路徑
base_path = paths.data_root;

% 獲取所有符合 "path1_*" 格式的文件夾
folders_info = dir(fullfile(base_path, 'path2_*'));
folders = {folders_info([folders_info.isdir]).name};

% 初始化 cell 來存儲所有讀取的數據
sync_time_marker = cell(1, numel(folders));

% 讀取每個 .npz 文件
for i = 1:numel(folders)
    % 完整文件路徑
    file_path = fullfile(base_path, folders{i}, 'opensim', 'sync_time_marker.npz');
    
    % 檢查文件是否存在
    if exist(file_path, 'file')
        
        % 解壓 .npz 文件到臨時目錄
        temp_dir = fullfile(base_path, 'temp_extract');
        if ~exist(temp_dir, 'dir')
            mkdir(temp_dir);
        end
        unzip(file_path, temp_dir);
        
        % 讀取臨時目錄中的 .npy 文件
        npy_files = dir(fullfile(temp_dir, '*.npy'));
        data = cell(1, numel(npy_files));
        for j = 1:numel(npy_files)
            npy_file_path = fullfile(temp_dir, npy_files(j).name);
            data{j} = readNPY(npy_file_path);
        end
        
        % 存儲到 sync_time_marker 中
        sync_time_marker{i} = data;
        
        % 刪除臨時目錄中的文件
        delete(fullfile(temp_dir, '*.npy'));
    else
        warning('File %s not found.', file_path);
    end
end

% 刪除臨時目錄
if exist(temp_dir, 'dir')
    rmdir(temp_dir, 's');
end

% 多加一個 frame 讓 sync time marker 可以和 template{count,34} 做矩正運算
for i = 1:numel(sync_time_marker)
    
    if ~isempty(sync_time_marker{1, i})
        
        % 獲取 sync_time_marker{1, i}{1, 2} 中的數據
        current_data = sync_time_marker{1, i}{1, 2};
        
        if ~isempty(current_data)
            
            % 多加一個frame讓sync time marker 可以和 template{count,34} 做矩正運算
            new_value = current_data(end) + 0.0333;
            
            % 檢查 current_data 是行向量還是列向量，並調整 new_value
            if isrow(current_data)
                new_value = [new_value];  % 確保 new_value 是行向量
            else
                new_value = [new_value]';  % 確保 new_value 是列向量
            end
            
            % 將新值添加到數據中
            sync_time_marker{1, i}{1, 2} = [current_data; new_value];  % 使用 ';' 進行垂直合併
        end
    end
end

%% Segmentation of transitional stages (sit to stand, stand to walk, walk to stop)

% Load template
load(paths.motion_template);

% 資料子目錄的前綴
prefix = 'path2_';

% 根目錄
rootFolder = paths.data_root;

% 獲取所有子目錄的列表
subdirs = dir(fullfile(rootFolder, [prefix '*']));
subdirs = subdirs([subdirs.isdir] & ~startsWith({subdirs.name}, '.'));
numFiles = length(subdirs);

% 初始化儲存結果
transient_results = cell(numFiles, 1); 
timeOfvideo = cell(numFiles, 1); 

output_folder = fullfile(paths.results_root, 'transitional_stages_path2');
if ~exist(output_folder, 'dir')
   mkdir(output_folder);
end

% 循環處理每個子目錄
for i = 1:numFiles
    
    % 構建資料夾路徑
    folder_name = subdirs(i).name;
    folder_path = fullfile(rootFolder, folder_name, 'opensim');
    
    % 設置 IK 和 TRC 檔案路徑
    IK_dir = fullfile(folder_path, 'Balancing_for_IK_BODY.mot');
    trc_dir = fullfile(folder_path, 'Empty_project_filt_0-30.trc');
    
    try
        % 確保檔案存在
        if exist(IK_dir, 'file') && exist(trc_dir, 'file')
            
            count = i+1; 
            data = trc_read(trc_dir);
            angle = importdata(IK_dir);
            [vr30, vl30] = heel_v_xy_plane(trc_dir, 30);
            vcm30 = gaitspeedcm(trc_dir, 30);
            vCHip30 = gaitspeedCHip(trc_dir, 30);
            vCHip6 = gaitspeedCHip(trc_dir, 6);
            label = folder_name;

            % 儲存各種資料到 template
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

            % 執行暫態分析
            timeOfvideo{i} = count_videotime(sync_time_marker, i);
            transient_results{i} = analyze_transient_segments_v1(vcm30, timeOfvideo{i}, label, output_folder);
        else
            warning(['在資料夾中找不到檔案: ', folder_path]);
        end
    catch ME
        fprintf('處理資料夾時發生錯誤: %s\n', ME.message);
    end
end

% 儲存 transient_results 結果
%save(fullfile(paths.results_root, 'transitional_results_path2.mat'), 'transient_results', '-v7.3');
disp('Segmentation remains in transient_results; the optional save command is disabled.');
%% Funciton list

function data = trc_read(trc_dir)
    fid = fopen(trc_dir);
    Rows = textscan(fid, '%s', 'delimiter', '\n'); % 創建一個臨時數組來存儲行
    fclose(fid);
    
    % 找到每個追蹤的開始
    TraceStarts = strfind(Rows{1,1}, 'Scan'); 
    TracesIdx = find(~cellfun('isempty', TraceStarts)); % 儲存索引
    
    % 偵測行中的數字，並丟棄 'VOID' 元素
    Columns = cellfun(@(x) textscan(x, '%f', 'delimiter', '\t', 'CollectOutput', 1, 'treatAsEmpty', {'VOID'}), Rows{1,1});
    Columns = cellfun(@transpose, Columns, 'UniformOutput', 0);
    
    % 儲存各個追蹤到的數據
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
    down_index = 30 / SRd; % 降採樣因子
    
    R_heel = data(:, Rheel:Rheel + 2);
    R_heel_d = downsample(R_heel, down_index);
    L_heel = data(:, Lheel:Lheel + 2);
    L_heel_d = downsample(L_heel, down_index);
    
    % 計算右腳跟速度
    x = R_heel(:, 1);
    y = R_heel(:, 3);
    vx = [x(1); x(1:end - 1)] - x;
    vy = [y(1); y(1:end - 1)] - y;
    vr = sqrt(vx.^2 + vy.^2) * 30; % 計算速度
    
    % 計算左腳跟速度
    x = L_heel(:, 1);
    y = L_heel(:, 3);
    vx = [x(1); x(1:end - 1)] - x;
    vy = [y(1); y(1:end - 1)] - y;
    vl = sqrt(vx.^2 + vy.^2) * 30; % 計算速度
end

function v = gaitspeedCHip(trc_dir, SRd)
    % 讀取TRC檔案中的數據
    data = trc_read(trc_dir);
    
    % 設定參數
    CHip = 1; % 髖部索引
    SR = 30; % 原始取樣率
    down_index = SR / SRd; % 降採樣因子
    
    % 提取髖部數據並降採樣
    C_Hip = data(:, CHip:CHip + 2);
    C_Hip_d = downsample(C_Hip, down_index);
    
    % 計算速度
    x = C_Hip_d(:, 1);
    y = C_Hip_d(:, 3);
   
    % 計算速度分量
    vx = x - [x(1); x(1:end-1)];
    vy = y - [y(1); y(1:end-1)];
    
    % 計算總速度
    v = sqrt(vx.^2 + vy.^2) * SRd;
    
    % 返回最大速度
    max_speed = max(v);
end

function v = gaitspeedcm(trc_dir, SRd)
    % 讀取TRC檔案中的數據
    data = trc_read(trc_dir);
    
    % 設定參數
    SR = 30; % 原始取樣率
    
    % 提取人體關鍵點數據並計算平均位置
    CHip = 1; % 髖部
    RHip = 4; % 右髖
    LHip = 22; % 左髖
    RShoulder = 49; % 右肩
    LShoulder = 58; % 左肩
    Neck = 40; % 項部
    
    cm = (data(:, CHip:CHip + 2) + ...
           data(:, RHip:RHip + 2) + ...
           data(:, LHip:LHip + 2) + ...
           data(:, RShoulder:RShoulder + 2) + ...
           data(:, LShoulder:LShoulder + 2) + ...
           data(:, Neck:Neck + 2)) ./ 6; % 計算人體質心
    
    down_index = SR / SRd; % 降採樣因子
    C_Hip = cm;
    C_Hip_d = downsample(C_Hip, down_index); % 降採樣
    
    % 計算速度
    x = C_Hip_d(:, 1);
    y = C_Hip_d(:, 3);
    
    vx = [0; diff(x)] * SRd;   % m/s
    vy = [0; diff(y)] * SRd;   % m/s
    v = sqrt(vx.^2 + vy.^2);  % m/s
    % 計算速度分量
    %vx = x - [x(1); x(1:end-1)];
    %vy = y - [y(1); y(1:end-1)];
    
    % 計算總速度
    %v = sqrt(vx.^2 + vy.^2) * SRd;
    
    % 返回最大速度
    max_speed = max(v);
end    

% 計算 x 軸 
function timeOfvideo = count_videotime(sync_time_marker, nowset)
    
    % 獲取每一 frame 的時間（秒數）
    frame_time_data = sync_time_marker{1, nowset}{1, 2}; 
    
    % 獲取 First Red Frames 作為起始值
    start_time = sync_time_marker{1, nowset}{1, 1}(1);
    
    % 計算時間相對於起始時間(timeOvideo 為 row vector)
    timeOfvideo = (frame_time_data - start_time)';
end

% 分析質心速度的暫態區段：坐→站、站→走、走→停
function transient_time_struct = analyze_transient_segments_v1(vcm_data, timeOfvideo, data_label, output_folder)

transient_time_struct = struct(); % 初始化輸出結構
vcm_data = vcm_data(:);           % 確保為 column vector
timeOfvideo = timeOfvideo(:);     % 確保時間軸為 column vector
fs = 30;                          % 影片的取樣頻率（frame per second）

% 畫圖顯示原始 vcm 資料
figure;
plot(timeOfvideo, vcm_data, 'k'); hold on;
xlabel('Time (s)');
ylabel('vcm');

% 加入資料標籤到圖的標題
if nargin < 3 || isempty(data_label)
    data_label = 'unknown';
end
title(['Segmentation of transitional stages (', data_label, ')'], 'Interpreter', 'none');

% 差分濾波器（近似一階導數）：用來強調速度的變化（斜率變化）
h1 = [-1 -2 0 2 1]; 
y = conv(vcm_data, h1, 'same');  % 計算差分訊號，突顯出變動點

% 將導數訊號平方，代表能量大小（避免正負號互相抵銷）
y2 = y.^2 / max(y.^2); % 並正規化（使最大值為 1）

% 使用滑動平均濾波器（窗口寬度 31 ≈ 1 秒）來平滑能量曲線
h2 = ones(1, 31) / 31;           
y3 = conv(y2, h2, 'same') / max(conv(y2, h2, 'same')); % 再次正規化，得到平滑的能量曲線

% 使用能量曲線門檻偵測活動區：高於平均值的區段視為「活動區」
MWI_set = y3 > mean(y3);

% 利用差分方式找出活動區的起點與終點索引（left/right）
diff_set = diff([false; MWI_set; false]);
left = find(diff_set == 1);           % 活動開始點
right = find(diff_set == -1) - 1;     % 活動結束點

% 尋找每段活動區前一秒（約30幀）內的極小值（valley）：推測為變化的開始
vally_loc = [];
for i = 1:length(left)
    idx = max(1, left(i) - fs);       % 取活動點前一秒區間
    [~, min_idx] = min(vcm_data(idx:left(i)));  % 找出該段最小值的位置
    vally_loc(i) = idx + min_idx - 1; % 記錄 valley 的實際索引
end

% 若有活動結束段，也補上最後一個 valley
if ~isempty(right)
    idx = max(1, right(end) - fs);
    [~, min_idx] = min(vcm_data(idx:right(end)));
    vally_loc(end+1) = idx + min_idx - 1;
end

% 若成功找到三個以上 valley，代表可分出三段暫態區間
if length(vally_loc) >= 3
    X1 = vally_loc(2); 
    X2 = vally_loc(3);
    
    % 取第二與第三個 valley 間的訊號區段，準備找 peak
    sub_vcm = vcm_data(X1:X2);
    th = mean(sub_vcm) + 0.3 * std(sub_vcm); % 調整為動態的門檻
    [~, peak_loc] = findpeaks(sub_vcm, 'MinPeakHeight', th, 'MinPeakDistance', round(0.3*fs));
   % [~, peak_loc] = findpeaks(sub_vcm, 'MinPeakHeight', th); % 尋找峰值（代表走路過程中上下擺動）

    if length(peak_loc) >= 2
        % 計算 peak 的全域索引位置
        X1_peak = X1 + peak_loc(1) - 1;
        X2_peak = X1 + peak_loc(end) - 1;

        % 定義三段暫態區段的開始與結束時間點（索引）
        T1_start = vally_loc(1);  T1_end = vally_loc(2);        % 坐→站
        T2_start = vally_loc(2);  T2_end = X1_peak;             % 站→走
        T3_start = X2_peak;       T3_end = vally_loc(end);      % 走→停

        % 圖上標記三段區間的起訖點
        plot(timeOfvideo([T1_start T1_end]), vcm_data([T1_start T1_end]), 'bo', 'MarkerFaceColor', 'b');
        plot(timeOfvideo([T2_start T2_end]), vcm_data([T2_start T2_end]), 'go', 'MarkerFaceColor', 'g');
        plot(timeOfvideo([T3_start T3_end]), vcm_data([T3_start T3_end]), 'mo', 'MarkerFaceColor', 'm');

        % 顯示文字訊息
        fprintf('暫態 1（坐→站）: %.2f 到 %.2f 秒\n', timeOfvideo(T1_start), timeOfvideo(T1_end));
        fprintf('暫態 2（站→走）: %.2f 到 %.2f 秒\n', timeOfvideo(T2_start), timeOfvideo(T2_end));
        fprintf('暫態 3（走→停）: %.2f 到 %.2f 秒\n', timeOfvideo(T3_start), timeOfvideo(T3_end));

        % 儲存結果到結構中
        transient_time_struct.T1 = [timeOfvideo(T1_start), timeOfvideo(T1_end)];
        transient_time_struct.T2 = [timeOfvideo(T2_start), timeOfvideo(T2_end)];
        transient_time_struct.T3 = [timeOfvideo(T3_start), timeOfvideo(T3_end)];

        % 儲存圖片至指定資料夾
        saveas(gcf, fullfile(output_folder, ['transitional_stages' data_label '.png']));
        close(gcf);
    else
        warning('穩態區段內未找到足夠 peaks。');
    end
else
    warning('vally_loc 少於 3 組，無法定位三段暫態區段。');
end
end

% 分析質心速度的暫態區段（第二種實驗：只有 坐→走、走→停 兩段）
function transient_time_struct = analyze_transient_segments_v2(vcm_data, timeOfvideo, data_label, output_folder)

transient_time_struct = struct(); % 初始化輸出結構
vcm_data = vcm_data(:);           % 確保為 column vector
timeOfvideo = timeOfvideo(:);     % 確保時間軸為 column vector
fs = 30;                          % 影片的取樣頻率（frame per second）

% 畫圖顯示原始 vcm 資料
figure;
plot(timeOfvideo, vcm_data, 'k'); hold on;
xlabel('Time (s)');
ylabel('vcm');

% 加入資料標籤到圖的標題
if nargin < 3 || isempty(data_label)
    data_label = 'unknown';
end
title(['differentiate transient stage (', data_label, ')'], 'Interpreter', 'none');

% 差分濾波器（近似一階導數）：用來強調速度的變化（斜率變化）
h1 = [-1 -2 0 2 1]; 
y = conv(vcm_data, h1, 'same');

% 平方 + 正規化
y2 = y.^2 / max(y.^2);

% 使用滑動平均平滑能量曲線
h2 = ones(1, 31) / 31;
y3 = conv(y2, h2, 'same') / max(conv(y2, h2, 'same'));

% 能量門檻，偵測活動區段
MWI_set = y3 > mean(y3);
diff_set = diff([false; MWI_set; false]);
left = find(diff_set == 1);         % 活動開始
right = find(diff_set == -1) - 1;   % 活動結束

% 找每段活動前一秒的 valley
vally_loc = [];
for i = 1:length(left)
    idx = max(1, left(i) - fs);
    [~, min_idx] = min(vcm_data(idx:left(i)));
    vally_loc(i) = idx + min_idx - 1;
end

% 加上最後一個 valley（對應走→停）
if ~isempty(right)
    idx = max(1, right(end) - fs);
    [~, min_idx] = min(vcm_data(idx:right(end)));
    vally_loc(end+1) = idx + min_idx - 1;
end

% 若成功找到兩段暫態
if length(vally_loc) >= 2
    % 嘗試找出分布最寬的兩個 valley
    [~, max_idx] = max(diff(vally_loc));
    X1 = vally_loc(max_idx); % 第1個 valley：坐→走 開始
    X2 = vally_loc(max_idx + 1);  % 第2個 valley：走→停 開始

    % 分析坐→走區段中是否有走路特徵的 peaks
    sub_vcm = vcm_data(X1:X2);
    th = mean(sub_vcm) + 0.3 * std(sub_vcm); % 動態門檻
    [~, peak_loc] = findpeaks(sub_vcm, 'MinPeakHeight', th, 'MinPeakDistance', round(0.3*fs));

    if ~isempty(peak_loc)
        X1_peak = X1 + peak_loc(1) - 1;
        X2_peak = X1 + peak_loc(end) - 1;

        % 定義暫態區間
        T1_start = vally_loc(1);  T1_end = X1_peak;          % 坐→走
        T2_start = X2_peak;       T2_end = vally_loc(end);   % 走→停
        
        % 圖上標記兩段區間
        plot(timeOfvideo([T1_start T1_end]), vcm_data([T1_start T1_end]), 'bo', 'MarkerFaceColor', 'b');
        plot(timeOfvideo([T2_start T2_end]), vcm_data([T2_start T2_end]), 'mo', 'MarkerFaceColor', 'm');

        % 顯示結果
        fprintf('暫態 1（坐→走）: %.2f 到 %.2f 秒\n', timeOfvideo(T1_start), timeOfvideo(T1_end));
        fprintf('暫態 2（走→停）: %.2f 到 %.2f 秒\n', timeOfvideo(T2_start), timeOfvideo(T2_end));

        % 儲存結果
        transient_time_struct.T1 = [timeOfvideo(T1_start), timeOfvideo(T1_end)];
        transient_time_struct.T2 = [timeOfvideo(T2_start), timeOfvideo(T2_end)];

        % 存圖
        saveas(gcf, fullfile(output_folder, ['transient_plot_' data_label '.png']));
        close(gcf);

    else
        warning('未偵測到足夠的 peaks 來判斷走路特徵。');
    end
else
    warning('vally_loc 少於兩個，無法定位兩段暫態區段。');
end
end

%% transient stage alignment (EEG & EMG)

% 頻段定義（單位：Hz）
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

            % 產生對齊時間（加上起始時間）
            eeg_times = [transient_results{i}.T1; transient_results{i}.T2; transient_results{i}.T3] + time_EEG{i}(1);
            emg_times = [transient_results{i}.T1; transient_results{i}.T2; transient_results{i}.T3] + time_EMG{i}(1);

            eeg_data = EEG_data{i}.zcore;
            eeg_time = time_EEG{i};
            emg_time = time_EMG{i};

            % ==== 處理 EEG ====
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

            % ==== 處理 EMG 的每個頻段 ====
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

