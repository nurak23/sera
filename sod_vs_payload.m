% sod_vs_payload.m
%
% Produces: "Security overhead (%) vs application payload size"
% (Section 8.1 of the paper).
%
% INPUT (you supply): a CSV per protocol with columns
%   payload_bytes, security_bytes, protocol_bytes, total_bytes
% one row per captured/decoded transaction, e.g.
%   data/zigbee_green_power.csv
%   data/zigbee_pro.csv
%   data/thread_matter.csv
%   data/wisun_fan.csv
%   data/zwave_s2.csv
%
% This script does NOT invent data: if a CSV is missing it is
% skipped with a warning, and protocols with no data simply do not
% appear on the plot.

clear; clc; close all;

protocols = {'zigbee_green_power', 'zigbee_pro', 'thread_matter', ...
             'wisun_fan', 'zwave_s2'};
labels    = {'Zigbee Green Power', 'Zigbee PRO', 'Thread/Matter', ...
             'Wi-SUN FAN', 'Z-Wave S2'};
colors    = {[0.85 0.33 0.10], [0.00 0.45 0.74], [0.47 0.67 0.19], ...
             [0.49 0.18 0.56], [0.30 0.30 0.30]};

data_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'data');

figure('Color', 'w'); hold on; box on; grid on;
legend_entries = {};

for i = 1:numel(protocols)
    csv_path = fullfile(data_dir, [protocols{i}, '.csv']);
    if ~exist(csv_path, 'file')
        warning('sod_vs_payload:missing_data', ...
                'No data file for %s (%s) -- skipping.', ...
                labels{i}, csv_path);
        continue;
    end

    T = readtable(csv_path);
    required_cols = {'payload_bytes', 'security_bytes', ...
                      'protocol_bytes', 'total_bytes'};
    if ~all(ismember(required_cols, T.Properties.VariableNames))
        warning('sod_vs_payload:bad_columns', ...
                '%s is missing required columns -- skipping.', csv_path);
        continue;
    end

    overhead_bytes = T.security_bytes + T.protocol_bytes;
    r_overhead_pct = 100 * overhead_bytes ./ T.total_bytes;

    % Bin by payload size and take the mean overhead % per bin so the
    % curve is readable even with many samples at the same payload size.
    [payload_sorted, order] = sort(T.payload_bytes);
    overhead_sorted = r_overhead_pct(order);
    [unique_payload, ~, ic] = unique(payload_sorted);
    mean_overhead = accumarray(ic, overhead_sorted, [], @mean);

    plot(unique_payload, mean_overhead, '-o', ...
         'Color', colors{i}, 'LineWidth', 1.6, 'MarkerSize', 4, ...
         'MarkerFaceColor', colors{i});
    legend_entries{end+1} = labels{i}; %#ok<SAGROW>
end

xlabel('Application payload size (bytes)');
ylabel('Security + protocol overhead, R_{overhead} (%)');
title('Security overhead vs. application payload size');
if ~isempty(legend_entries)
    legend(legend_entries, 'Location', 'northeast');
else
    text(0.5, 0.5, 'No data supplied yet -- see data/*.csv', ...
         'Units', 'normalized', 'HorizontalAlignment', 'center');
end

out_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'figures');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end
print(fullfile(out_dir, 'sod_vs_payload.pdf'), '-dpdf');
fprintf('Wrote %s\n', fullfile(out_dir, 'sod_vs_payload.pdf'));
