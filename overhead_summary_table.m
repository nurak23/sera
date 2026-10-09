% overhead_summary_table.m
%
% Produces: cross-protocol SOD/SED/SAD summary table (Section 8.2 of
% the paper) as both a printed table and a CSV for LaTeX import via
% pandas/csvsimple, split by transaction type (commissioning vs.
% steady-state).
%
% INPUT (you supply): data/<protocol>.csv with columns
%   transaction_type   ('commissioning' | 'steady_state')
%   payload_bytes, security_bytes, protocol_bytes, total_bytes
%   airtime_us          (optional; enables SAD)
%   energy_proxy_nJ      (optional; enables SED, from Eq. 7 in the paper)
%
% Missing optional columns simply leave the corresponding metric
% blank in the output rather than being estimated or invented.

clear; clc;

protocols = {'zigbee_green_power', 'zigbee_pro', 'thread_matter', ...
             'wisun_fan', 'zwave_s2'};
labels    = {'Zigbee Green Power', 'Zigbee PRO', 'Thread/Matter', ...
             'Wi-SUN FAN', 'Z-Wave S2'};
tx_types  = {'commissioning', 'steady_state'};

data_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'data');
out_dir  = fullfile(fileparts(mfilename('fullpath')), '..', 'figures');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

fid = fopen(fullfile(out_dir, 'overhead_summary_table.csv'), 'w');
fprintf(fid, 'protocol,transaction_type,n,SOD_mean,SOD_ci95,SAD_mean_ns_per_bit,SAD_ci95,SED_mean_nJ_per_bit,SED_ci95\n');

for i = 1:numel(protocols)
    csv_path = fullfile(data_dir, [protocols{i}, '.csv']);
    if ~exist(csv_path, 'file')
        fprintf('No data for %s -- writing empty rows.\n', labels{i});
        for t = 1:numel(tx_types)
            fprintf(fid, '%s,%s,0,,,,,,\n', protocols{i}, tx_types{t});
        end
        continue;
    end

    T = readtable(csv_path);
    has_airtime = ismember('airtime_us', T.Properties.VariableNames);
    has_energy  = ismember('energy_proxy_nJ', T.Properties.VariableNames);

    for t = 1:numel(tx_types)
        rows = strcmp(T.transaction_type, tx_types{t});
        Tsub = T(rows, :);
        n = height(Tsub);
        if n == 0
            fprintf(fid, '%s,%s,0,,,,,,\n', protocols{i}, tx_types{t});
            continue;
        end

        sod = Tsub.security_bytes ./ max(Tsub.payload_bytes, 1); % Eq. (4)
        [sod_mean, sod_ci] = mean_ci95(sod);

        if has_airtime
            bits = max(Tsub.payload_bytes, 1) * 8;
            sad = (Tsub.airtime_us * 1000) ./ bits; % ns per useful bit, Eq. (6)
            [sad_mean, sad_ci] = mean_ci95(sad);
        else
            sad_mean = NaN; sad_ci = NaN;
        end

        if has_energy
            bits = max(Tsub.payload_bytes, 1) * 8;
            sed = Tsub.energy_proxy_nJ ./ bits; % Eq. (5)
            [sed_mean, sed_ci] = mean_ci95(sed);
        else
            sed_mean = NaN; sed_ci = NaN;
        end

        fprintf(fid, '%s,%s,%d,%.3f,%.3f,%s,%s,%s,%s\n', ...
            protocols{i}, tx_types{t}, n, sod_mean, sod_ci, ...
            fmt_or_blank(sad_mean), fmt_or_blank(sad_ci), ...
            fmt_or_blank(sed_mean), fmt_or_blank(sed_ci));
    end
end
fclose(fid);
fprintf('Wrote %s\n', fullfile(out_dir, 'overhead_summary_table.csv'));

function [m, ci] = mean_ci95(x)
    x = x(~isnan(x));
    if isempty(x)
        m = NaN; ci = NaN; return;
    end
    m = mean(x);
    if numel(x) > 1
        ci = 1.96 * std(x) / sqrt(numel(x));
    else
        ci = 0;
    end
end

function s = fmt_or_blank(v)
    if isnan(v)
        s = '';
    else
        s = sprintf('%.3f', v);
    end
end
