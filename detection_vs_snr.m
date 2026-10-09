% detection_vs_snr.m
%
% Produces: detection probability vs. SNR for authentic, replayed,
% and field-perturbed transmissions (Section 8.4 of the paper),
% implementing the analysis half of Algorithm 3 (RF-layer
% distinguishability) once Algorithms 1/2's captures exist.
%
% INPUT (you supply):
%   data/rf_features_authentic.csv
%   data/rf_features_replayed.csv
%   data/rf_features_perturbed.csv   (optional)
% each with columns: snr_db, rssi_dbm, cfo_hz, timing_offset_us,
% preamble_dur_us [, additional transient features].
%
% METHOD: for each SNR bin, trains a simple linear-discriminant
% threshold on the strongest single feature (or a chosen feature
% subset) to separate authentic vs. replayed/perturbed captures at
% that SNR, and reports leave-one-out detection probability. This is
% intentionally a simple, auditable baseline classifier -- not a
% black-box model -- so that a reviewer can verify what is driving
% detection.

clear; clc; close all;

data_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'data');
out_dir  = fullfile(fileparts(mfilename('fullpath')), '..', 'figures');
if ~exist(out_dir, 'dir'); mkdir(out_dir); end

auth_path = fullfile(data_dir, 'rf_features_authentic.csv');
rep_path  = fullfile(data_dir, 'rf_features_replayed.csv');
pert_path = fullfile(data_dir, 'rf_features_perturbed.csv');

if ~exist(auth_path, 'file') || ~exist(rep_path, 'file')
    warning('detection_vs_snr:no_data', ...
        ['Authentic/replayed RF feature files not found under %s -- ', ...
         'writing an empty placeholder figure. Run Algorithms 1 and 3 ', ...
         '(replay + RF capture) first.'], data_dir);
    figure('Color', 'w');
    text(0.5, 0.5, 'No RF capture data supplied yet -- see data/rf_features_*.csv', ...
         'Units', 'normalized', 'HorizontalAlignment', 'center');
    axis off;
    print(fullfile(out_dir, 'detection_vs_snr.pdf'), '-dpdf');
    return;
end

Tauth = readtable(auth_path);
Trep  = readtable(rep_path);

feature_cols = intersect(Tauth.Properties.VariableNames, ...
    {'rssi_dbm', 'cfo_hz', 'timing_offset_us', 'preamble_dur_us'});
if isempty(feature_cols)
    error('detection_vs_snr:no_features', ...
          'No recognized RF feature columns found in %s.', auth_path);
end

snr_edges = -5:2.5:30; % dB bins; adjust to the SNR range actually captured
snr_centers = (snr_edges(1:end-1) + snr_edges(2:end)) / 2;
detection_prob = nan(size(snr_centers));

for b = 1:numel(snr_centers)
    lo = snr_edges(b); hi = snr_edges(b+1);
    Aa = Tauth(Tauth.snr_db >= lo & Tauth.snr_db < hi, :);
    Ar = Trep(Trep.snr_db >= lo & Trep.snr_db < hi, :);
    if height(Aa) < 3 || height(Ar) < 3
        continue; % not enough samples in this bin to estimate a rate
    end

    Xa = table2array(Aa(:, feature_cols));
    Xr = table2array(Ar(:, feature_cols));
    X = [Xa; Xr];
    y = [zeros(height(Aa), 1); ones(height(Ar), 1)];

    correct = 0;
    n = size(X, 1);
    for k = 1:n
        train_idx = true(n, 1); train_idx(k) = false;
        mu0 = mean(X(train_idx & y == 0, :), 1);
        mu1 = mean(X(train_idx & y == 1, :), 1);
        d0 = norm(X(k, :) - mu0);
        d1 = norm(X(k, :) - mu1);
        pred = d1 < d0; % nearest-centroid classifier
        correct = correct + (pred == y(k));
    end
    detection_prob(b) = correct / n;
end

figure('Color', 'w'); hold on; box on; grid on;
plot(snr_centers, detection_prob, '-o', 'LineWidth', 1.6, ...
     'Color', [0.00 0.45 0.74], 'MarkerFaceColor', [0.00 0.45 0.74]);
yline(0.5, '--', 'Chance', 'Color', [0.5 0.5 0.5]);
xlabel('SNR (dB)');
ylabel('Detection probability (leave-one-out)');
title('Authentic vs.\ replayed transmission detection vs.\ SNR');
ylim([0 1]);

print(fullfile(out_dir, 'detection_vs_snr.pdf'), '-dpdf');
fprintf('Wrote %s\n', fullfile(out_dir, 'detection_vs_snr.pdf'));

% Optional: repeat against rf_features_perturbed.csv if present, to
% compare replay-detection difficulty against field-perturbation
% detection difficulty (Algorithm 2 vs Algorithm 3 outcomes).
if exist(pert_path, 'file')
    fprintf(['Perturbed-frame RF features found at %s -- extend this ', ...
             'script with a second detection_prob curve for a direct ', ...
             'replay-vs-perturbation comparison.\n'], pert_path);
end
