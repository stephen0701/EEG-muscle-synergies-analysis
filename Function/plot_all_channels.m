
function plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names, band_label)
    % PLOT_ALL_CHANNELS - 對 raw_data 和 processed_data 的每個通道繪製圖表
    
    % raw_data: 原始數據 (data * channel)
    % processed_data: 處理後的數據 (data * channel)
    % ch_list: 通道名稱的 cell array
    % fs: 取樣頻率
    % legend_names: 圖例名稱的 cell array
    % 若 band_label 為空或未提供，則不在標題中加入頻段標示

    % 檢查 band_label 是否存在或為空
    if nargin < 6 || isempty(band_label)
        band_label = '';
    else
        band_label = [' [' band_label ']']; % 加上括號以便顯示
    end
    
    % 確認輸入數據維度一致
    if size(raw_data, 2) ~= size(processed_data, 2) || size(raw_data, 2) ~= length(ch_list)
        error('輸入數據的通道數量與通道名稱列表長度不一致！');
    end
    
    % 時間軸計算
    t = (0:size(raw_data, 1)-1) / fs;
    
    % 每個通道繪製（使用 subplot）
    for ch_idx = 1:size(raw_data, 2)
        figure;
    
        % 時域資料
        raw_ch = raw_data(:, ch_idx);
        proc_ch = processed_data(:, ch_idx);

        % 上半部：raw data
        subplot(2, 1, 1);
        plot(t, raw_ch, 'b', 'LineWidth', 1.5);
        title(['Raw Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{1});
        grid on;

        % 下半部：processed data
        subplot(2, 1, 2);
        plot(t, proc_ch, 'r', 'LineWidth', 1.5);
        title(['Processed Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{2});
        grid on;

    end
