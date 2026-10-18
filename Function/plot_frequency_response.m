
function plot_frequency_response(raw_data, processed_data, ch_list, fs, legend_names, band_label)
    % PLOT_FREQUENCY_RESPONSE - Plot each channel's raw and processed spectra.
    % Also plot the average spectrum across channels.
    %
    % raw_data: input matrix, samples by channels.
    % processed_data: processed matrix, samples by channels.
    % ch_list: cell array of channel names.
    % fs: sampling frequency in Hz.
    % legend_names: one label for each dataset.
    % Omit the band label from titles when it is empty or absent.

    % Check whether a band label was provided.
    if nargin < 6 || isempty(band_label)
        band_label = '';
    else
        band_label = [' [' band_label ']']; % Enclose the band label in brackets.
    end

    % Validate the basic inputs.
    if size(raw_data, 2) ~= size(processed_data, 2)
        error('原始數據與處理後數據的通道數必須相同。');
    end
    if isempty(raw_data) || isempty(processed_data)
        error('原始數據或處理後數據為空。');
    end
    if length(ch_list) ~= size(raw_data, 2)
        error('通道名稱列表的長度必須與數據通道數一致。');
    end

    % Compute plotting parameters.
    time = (0:(size(raw_data, 1) - 1)) / fs;
    nfft = 2^nextpow2(size(raw_data, 1));
    frequency = (0:(nfft - 1)) * (fs / nfft);
    freq_axis = frequency(1:floor(nfft/2)+1);

    % Plot each channel.
    for ch_idx = 1:size(raw_data, 2)
        raw_channel_data = raw_data(:, ch_idx);
        processed_channel_data = processed_data(:, ch_idx);

        % Compute the FFT.
        processed_magnitude = abs(fft(processed_channel_data, nfft) / nfft);
        processed_magnitude = processed_magnitude(1:floor(nfft / 2) + 1);
        processed_magnitude(2:end-1) = 2 * processed_magnitude(2:end-1);
        processed_db = 20 * log10(processed_magnitude + eps);

        figure;

        % Time-domain plot.
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

        % Frequency-domain plot.
        subplot(2, 1, 2);
        plot(freq_axis, processed_db, 'LineWidth', 1.5, 'DisplayName', legend_names{2});
        xlabel('Frequency (Hz)');
        ylabel('Magnitude (dB)');
        title(sprintf('Channel: %s Frequency Domain%s', ch_list{ch_idx}, band_label));
        legend('show');
        grid on;
        xlim([0 100]);
    end

    % Plot the average spectrum across channels.
    % Average channel FFT results rather than averaging signals before the FFT.
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

    % Plot the result.
    figure;
    plot(freq_axis, avg_db, 'k', 'LineWidth', 2);
    xlabel('Frequency (Hz)');
    ylabel('Magnitude (dB)');
    title(sprintf('Average Frequency Spectrum%s', band_label));
    grid on;
end

