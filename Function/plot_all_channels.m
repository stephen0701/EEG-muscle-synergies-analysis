
function plot_all_channels(raw_data, processed_data, ch_list, fs, legend_names, band_label)
    % PLOT_ALL_CHANNELS - Plot raw and processed signals for each channel.
    
    % raw_data: input matrix, samples by channels.
    % processed_data: processed matrix, samples by channels.
    % ch_list: cell array of channel names.
    % fs: sampling frequency.
    % legend_names: cell array of legend labels.
    % Omit the band label from titles when it is empty or absent.

    % Check whether a band label was provided.
    if nargin < 6 || isempty(band_label)
        band_label = '';
    else
        band_label = [' [' band_label ']']; % Enclose the band label in brackets.
    end
    
    % Check that input dimensions agree.
    if size(raw_data, 2) ~= size(processed_data, 2) || size(raw_data, 2) ~= length(ch_list)
        error('輸入數據的通道數量與通道名稱列表長度不一致！');
    end
    
    % Compute the time axis.
    t = (0:size(raw_data, 1)-1) / fs;
    
    % Use one subplot for each channel.
    for ch_idx = 1:size(raw_data, 2)
        figure;
    
        % Time-domain data.
        raw_ch = raw_data(:, ch_idx);
        proc_ch = processed_data(:, ch_idx);

        % Upper panel: raw data.
        subplot(2, 1, 1);
        plot(t, raw_ch, 'b', 'LineWidth', 1.5);
        title(['Raw Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{1});
        grid on;

        % Lower panel: processed data.
        subplot(2, 1, 2);
        plot(t, proc_ch, 'r', 'LineWidth', 1.5);
        title(['Processed Data - Channel: ', ch_list{ch_idx}, band_label]);
        xlabel('Time (s)');
        ylabel('Amplitude');
        legend(legend_names{2});
        grid on;

    end
