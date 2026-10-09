% pareto_3d.m
%
% Produces: the central 3-D Pareto figure of the paper --
%   security overhead (%) x RF airtime (us) x useful payload (bytes)
% with one trajectory per protocol (Figure "pareto-placeholder" /
% Section 8.3).
%
% INPUT (you supply): data/<protocol>.csv with columns
%   payload_bytes, security_bytes, protocol_bytes, total_bytes,
%   airtime_us
% one row per captured/decoded/simulated transaction. Rows are
% aggregated into payload-size bins so the trajectory is readable.
%
% This script deliberately does not fabricate a trajectory for any
% protocol lacking data: that protocol is simply absent from the
% plot, and the legend lists only protocols actually plotted.

clear; clc; close all;

protocols = {'zigbee_green_power', 'zigbee_pro', 'thread_matter', ...
             'wisun_fan', 'zwave_s2'};
labels    = {'Zigbee Green Power', 'Zigbee PRO', 'Thread/Matter', ...
             'Wi-SUN FAN', 'Z-Wave S2'};
colors    = {[0.85 0.33 0.10], [0.00 0.45 0.74], [0.47 0.67 0.19], ...
             [0.49 0.18 0.56], [0.30 0.30 0.30]};
markers   = {'o', 's', '^', 'd', 'v'};

data_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'data');
out_dir  = fullfile(fileparts(mfilename('fullpath')), '..', 'figures');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

figure('Color', 'w');
hold on; grid on; box on; view(45, 25);
plotted_any = false;
legend_entries = {};

for i = 1:numel(protocols)
    csv_path = fullfile(data_dir, [protocols{i}, '.csv']);
    if ~exist(csv_path, 'file')
        warning('pareto_3d:missing_data', 'No data for %s -- skipping.', labels{i});
        continue;
    end
    T = readtable(csv_path);
    required = {'payload_bytes', 'security_bytes', 'protocol_bytes', ...
                'total_bytes', 'airtime_us'};
    if ~all(ismember(required, T.Properties.VariableNames))
        warning('pareto_3d:bad_columns', '%s missing required columns -- skipping.', csv_path);
        continue;
    end

    overhead_pct = 100 * (T.security_bytes + T.protocol_bytes) ./ T.total_bytes;
    [payload_u, ~, ic] = unique(T.payload_bytes);
    mean_overhead = accumarray(ic, overhead_pct, [], @mean);
    mean_airtime  = accumarray(ic, T.airtime_us, [], @mean);

    [payload_sorted, order] = sort(payload_u);
    plot3(mean_overhead(order), mean_airtime(order), payload_sorted, ...
          '-', 'Marker', markers{i}, 'Color', colors{i}, ...
          'MarkerFaceColor', colors{i}, 'LineWidth', 1.6, 'MarkerSize', 5);
    legend_entries{end+1} = labels{i}; %#ok<SAGROW>
    plotted_any = true;
end

xlabel('Security overhead (%)');
ylabel('RF airtime (\mus)');
zlabel('Useful payload (bytes)');
title('Security overhead \times RF airtime \times useful payload');
if plotted_any
    legend(legend_entries, 'Location', 'northeast');
else
    text(0.5, 0.5, 0.5, 'No data supplied yet -- see data/*.csv', ...
         'HorizontalAlignment', 'center');
end

print(fullfile(out_dir, 'pareto_3d.pdf'), '-dpdf');
fprintf('Wrote %s\n', fullfile(out_dir, 'pareto_3d.pdf'));
