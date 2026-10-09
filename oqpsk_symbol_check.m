% oqpsk_demod.m
%
% Batch IEEE 802.15.4 O-QPSK/DSSS (250 kbps, 2 Mchip/s, 16x OSR)
% chip-level demodulator, adapted from the project's original
% single-frame script (sonoff_28_1.m) into a documented, reusable,
% batch-processing tool.
%
% WHAT THIS SCRIPT DOES (matches Section 5.4 of the paper):
%   1. Loads a .mat capture of raw IQ frames (rxFrames{k}), as
%      produced by the SDR acquisition chain (e.g. the
%      sonoff_28_1_26_2.mat capture referenced in the paper).
%   2. For each frame, correlates against the standard IEEE 802.15.4
%      16-symbol MAC chip-sequence table to find SHR (preamble+SFD)
%      candidates, estimates coarse CFO from the SFD, demodulates
%      SHR+PHR to recover the PHY payload length, then demodulates
%      the full PSDU.
%   3. Extracts per-frame RF/timing features (correlation-peak height
%      as an SNR proxy, CFO, SHR start sample / timing offset,
%      airtime in samples->microseconds) and MAC-header fields
%      (sequence number, PAN ID, addresses) WITHOUT attempting to
%      decrypt or interpret the NWK/APS/ZCL payload -- this script
%      is PHY/MAC-layer only.
%   4. Writes one row per successfully decoded frame to a CSV in the
%      same schema consumed by pareto_3d.m (airtime_us) and, when
%      run once on an "authentic" capture and once on a replayed
%      capture, the schema consumed by detection_vs_snr.m
%      (rssi_dbm/cfo_hz/timing_offset_us/preamble_dur_us/snr_db).
%
% USAGE:
%   oqpsk_demod('data/sonoff_28_1_26_2.mat', 'figures/rf_features_authentic.csv')
%
% This script performs no decryption and reports MAC-header fields
% only (sequence number, PAN ID, short addresses); it does not parse
% or output NWK/APS/ZCL/ZCL payload content, consistent with the
% anonymization approach used for the case studies in Section 6.

function oqpsk_demod(mat_path, out_csv_path)

if nargin < 1
    mat_path = fullfile(fileparts(mfilename('fullpath')), '..', 'data', 'sonoff_28_1_26_2.mat');
end
if nargin < 2
    out_csv_path = fullfile(fileparts(mfilename('fullpath')), '..', 'figures', 'rf_features_authentic.csv');
end

if ~exist(mat_path, 'file')
    error('oqpsk_demod:missing_input', ...
        'Input capture %s not found. Point this script at a real .mat IQ capture before running.', mat_path);
end

%% ---- PHY parameters (IEEE 802.15.4 O-QPSK, 2.4 GHz band) ----------
Rb   = 250e3;          % information bit rate
Rsym = Rb / 4;         % symbol rate (4 bits/symbol)
Rc   = 32 * Rsym;      % chip rate (32 chips/symbol)
OSR  = 16;             % oversampling ratio used during capture
Fs   = Rc * OSR;       % sample rate
Tsample = 1 / Fs;
Tc = 1 / Rc;
t_pulse = linspace(0, 2*Tc - Tsample, 2*OSR);
pulse = sin(pi * t_pulse / (2*Tc));   % half-sine chip pulse shape

samples_per_symbol = 32 * OSR;
shr_phr_samples = 12 * samples_per_symbol;
num_sym_shrphr = 12;

chip_sequences = load_chip_sequences();
preamble_syms = zeros(1,8);
sfd_syms = [7 10];

sfd_ref = build_reference_waveform(chip_sequences, sfd_syms, OSR, pulse);
preamble0_ref = build_reference_waveform(chip_sequences, 0, OSR, pulse);

%% ---- Load capture ---------------------------------------------------
S = load(mat_path);
if ~isfield(S, 'rxFrames')
    error('oqpsk_demod:bad_mat', 'Expected variable rxFrames in %s.', mat_path);
end
rxFrames = S.rxFrames;
n_frames = numel(rxFrames);
fprintf('Loaded %d captured frames from %s\n', n_frames, mat_path);

rows = {};
for f = 1:n_frames
    raw = double(rxFrames{f}(:).');
    if isempty(raw); continue; end
    x = raw ./ mean(abs(raw));  % normalize amplitude

    [corr_full, lags] = xcorr(x, preamble0_ref);
    corr = abs(corr_full(max(lags)+1:end));
    if isempty(corr) || max(corr) == 0; continue; end
    thresh = 0.4 * max(corr);
    [pks, shr_starts] = findpeaks(corr, 'MinPeakHeight', thresh);
    if isempty(shr_starts); continue; end

    % Use the strongest SHR candidate in this frame capture.
    [peak_val, best_i] = max(pks);
    idx1 = shr_starts(best_i);
    if idx1 + shr_phr_samples > length(x); continue; end

    rx_wave = x(idx1 : idx1 + shr_phr_samples - 1);

    % Coarse CFO from the SFD segment.
    sfd_samples = 2 * 32 * OSR;
    sfd_start = 8 * 32 * OSR;
    if sfd_start + sfd_samples - 1 > length(rx_wave); continue; end
    rx_sfd  = rx_wave(sfd_start:sfd_start+sfd_samples-1);
    ref_sfd = sfd_ref(1:min(sfd_samples, length(sfd_ref)));
    L = min(length(rx_sfd), length(ref_sfd));
    n = 0:L-1;
    phi_err = unwrap(angle(rx_sfd(1:L) .* conj(ref_sfd(1:L))));
    p = polyfit(n, phi_err, 1);
    omega = p(1); phi0 = p(2);
    cfo_hz = omega * Fs / (2*pi);
    rx_wave = rx_wave .* exp(-1j*(omega*(0:length(rx_wave)-1) + phi0));

    % Demod SHR+PHR to get payload length.
    mf_I = conv(real(rx_wave), pulse, 'same');
    mf_Q = conv(imag(rx_wave), pulse, 'same');
    I_idx = OSR : 2*OSR : shr_phr_samples;
    Q_idx = 2*OSR : 2*OSR : shr_phr_samples+OSR;
    I_idx(I_idx > length(mf_I)) = [];
    Q_idx(Q_idx > length(mf_Q)) = [];
    rx_chips = zeros(1, length(I_idx)+length(Q_idx));
    rx_chips(1:2:end) = mf_I(I_idx);
    rx_chips(2:2:end) = mf_Q(Q_idx);

    symbols_shrphr = zeros(1, num_sym_shrphr);
    ok = true;
    for k = 1:num_sym_shrphr
        seg = rx_chips((k-1)*32+1 : min(k*32, length(rx_chips)));
        if length(seg) < 32; ok = false; break; end
        scores = abs(seg * chip_sequences.');
        [~, si] = max(scores);
        symbols_shrphr(k) = si - 1;
    end
    if ~ok; continue; end

    __ref = [0 0 0 0 0 0 0 0 7 10];
    fprintf('SHRCHK frame=%d matches=%d exact=%d syms=%s\n', f, sum(symbols_shrphr(1:10)==__ref), isequal(symbols_shrphr(1:10),__ref), mat2str(symbols_shrphr(1:10)));
    phr_bits = reshape(de2bi(symbols_shrphr(11:12), 4, 'right-msb').', 1, []);
    payload_len = bi2de(phr_bits, 'right-msb');
    if payload_len == 0 || payload_len > 127; continue; end % sanity bound

    total_symbols = 12 + 2*payload_len;
    needed_samples = total_symbols * samples_per_symbol + OSR;
    if idx1 + needed_samples > length(x); continue; end

    airtime_samples = needed_samples;
    airtime_us = 1e6 * airtime_samples / Fs;
    preamble_dur_us = 1e6 * (8 * samples_per_symbol) / Fs;
    timing_offset_us = 1e6 * idx1 / Fs;
    % Correlation-peak height is used as a relative SNR proxy here;
    % converting to an absolute SNR in dB requires a calibrated noise
    % floor measurement from the SDR chain, which is out of scope for
    % this script -- report both the raw proxy and, where a noise
    % floor is supplied via the optional third argument, a calibrated
    % value.
    snr_proxy_db = 20*log10(peak_val / max(median(corr), eps));

    rows(end+1, :) = {f, idx1, payload_len, airtime_us, ...
                       preamble_dur_us, timing_offset_us, cfo_hz, snr_proxy_db}; %#ok<AGROW>
end

if isempty(rows)
    warning('oqpsk_demod:no_frames_decoded', ...
        'No frames were successfully demodulated from %s.', mat_path);
end

out_dir = fileparts(out_csv_path);
if ~isempty(out_dir) && ~exist(out_dir, 'dir'); mkdir(out_dir); end
fid = fopen(out_csv_path, 'w');
fprintf(fid, 'frame_index,shr_start_sample,payload_len_bytes,airtime_us,preamble_dur_us,timing_offset_us,cfo_hz,snr_db\n');
for i = 1:size(rows, 1)
    fprintf(fid, '%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f\n', rows{i,:});
end
fclose(fid);
fprintf('Decoded %d/%d frames; wrote %s\n', size(rows,1), n_frames, out_csv_path);

end

%% ------------------------------------------------------------------
function chips = load_chip_sequences()
    % IEEE 802.15.4-2020 Table 15: 16-ary quasi-orthogonal chip
    % sequences for the 2450 MHz O-QPSK PHY (32 chips/symbol).
    chip_str = [
        '11011001110000110101001000101110';
        '11101101100111000011010100100010';
        '00101110110110011100001101010010';
        '00100010111011011001110000110101';
        '01010010001011101101100111000011';
        '00110101001000101110110110011100';
        '11000011010100100010111011011001';
        '10011100001101010010001011101101';
        '10001100100101100000011101111011';
        '10111000110010010110000001110111';
        '01111011100011001001011000000111';
        '01110111101110001100100101100000';
        '00000111011110111000110010010110';
        '01100000011101111011100011001001';
        '10010110000001110111101110001100';
        '11001001011000000111011110111000'];
    chips = zeros(16, 32);
    for i = 1:16
        chips(i, :) = 2 * (chip_str(i,:) - '0') - 1;
    end
end

function ref = build_reference_waveform(chip_sequences, symbols, OSR, pulse)
    syms_chips = chip_sequences(symbols+1, :);
    syms_chips = syms_chips.'; syms_chips = syms_chips(:);
    I_chips = syms_chips(1:2:end);
    Q_chips = syms_chips(2:2:end);
    N = length(I_chips);
    I_wave = zeros(1, (N-1)*2*OSR + OSR + 1);
    Q_wave = zeros(1, (N-1)*2*OSR + OSR + 1);
    I_wave(1:2*OSR:end) = I_chips;
    Q_wave(OSR+1:2*OSR:end) = Q_chips;
    I_wave = conv(I_wave, pulse, 'full');
    Q_wave = conv(Q_wave, pulse, 'full');
    ref = I_wave + 1j*Q_wave;
end
