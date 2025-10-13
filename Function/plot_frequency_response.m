
function plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names, band_label)
    % PLOT_FREQUENCY_RESPONSE - 對 raw_data 和 processed_data 的每個通道繪製頻率響應圖，
    % 並在最後繪製平均頻譜圖
    %
    % raw_data : 原始數據 (data * channel)
    % processed_data : 處理後數據 (data * channel)
    % ch_list : 通道名稱的 cell array
    % fs : 取樣頻率 (Hz)
    % legend_names : 用來標註圖例的名稱，長度應與數據集數量一致
    % 若 band_label 為空或未提供，則不在標題中加入頻段標示

    % 檢查 band_label 是否存在或為空
    if nargin < 6 || isempty(band_label)
        band_label = '';
    else
        band_label = [' [' band_label ']']; % 加上括號以便顯示
    end

    % 基本檢查
    if size(raw_data, 2) ~= size(processed_data, 2)
        error('原始數據與處理後數據的通道數必須相同。');
    end
    if isempty(raw_data) || isempty(processed_data)
        error('原始數據或處理後數據為空。');
    end
    if length(ch_list) ~= size(raw_data, 2)
        error('通道名稱列表的長度必須與數據通道數一致。');
    end

    % 計算參數
    time = (0:(size(raw_data, 1) - 1)) / fs;
    nfft = 2^nextpow2(size(raw_data, 1));
    frequency = (0:(nfft - 1)) * (fs / nfft);
    freq_axis = frequency(1:floor(nfft/2)+1);

    % 單通道繪圖
    for ch_idx = 1:size(raw_data, 2)
        raw_channel_data = raw_data(:, ch_idx);
        processed_channel_data = processed_data(:, ch_idx);

        % FFT 處理
        processed_magnitude = abs(fft(processed_channel_data, nfft) / nfft);
        processed_magnitude = processed_magnitude(1:floor(nfft / 2) + 1);
        processed_magnitude(2:end-1) = 2 * processed_magnitude(2:end-1);
        processed_db = 20 * log10(processed_magnitude + eps);

        figure;

        % 時域圖
        subplot(2, 1, 1);
        plot(time, raw_channel_data, 'b', 'LineWidth', 1.5, 'DisplayName', legend_names{1});
        hold on;
        plot(time, processed_channel_data, 'r--', 'LineWidth', 1.5, 'DisplayName', legend_names{2});
        hold off;
        xlabel('Time (s)');
        ylabel('Amplitude');
        title(sprintf('Channel: %s Time Domain%s', ch_list{ch_idx}, band_label));
        legend('show');
        grid on;

        % 頻域圖
        subplot(2, 1, 2);
        plot(freq_axis, processed_db, 'LineWidth', 1.5, 'DisplayName', legend_names{2});
        xlabel('Frequency (Hz)');
        ylabel('Magnitude (dB)');
        title(sprintf('Channel: %s Frequency Domain%s', ch_list{ch_idx}, band_label));
        legend('show');
        grid on;
        xlim([0 100]);
    end

    % 所有通道的平均頻譜圖
    % 平均處理後數據的 FFT 結果（頻譜平均，不是先平均訊號）
    magnitude_matrix = zeros(length(freq_axis), size(processed_data, 2));

    for ch = 1:size(processed_data, 2)
        ch_data = processed_data(:, ch);
        mag = abs(fft(ch_data, nfft) / nfft);
        mag = mag(1:floor(nfft / 2) + 1);
        mag(2:end-1) = 2 * mag(2:end-1);
        magnitude_matrix(:, ch) = mag;
    end

    avg_mag = mean(magnitude_matrix, 2);
    avg_db = 20 * log10(avg_mag + eps);

    % 繪圖
    figure;
    plot(freq_axis, avg_db, 'k', 'LineWidth', 2);
    xlabel('Frequency (Hz)');
    ylabel('Magnitude (dB)');
    title(sprintf('Average Frequency Spectrum%s', band_label));
    grid on;
end

