%% ================================================================
% CMM LATERAL MF VALIDATOR
% PRE-MF FINAL 1.5.8 CONDITION-LEVEL VALIDATION
%
% Purpose:
%   Compare the frozen CMM lateral MF model against the measured
%   condition-level metrics stored in PRE-MF FINAL 1.5.8.
%
% IMPORTANT:
%   This is NOT a point-by-point Fy(alpha) validation.
%   FINAL 1.5.8 contains condition-level summary metrics.
%
%   The validator:
%       1) handles PeakStatus / BoundaryFraction
%       2) separates valid interior peaks from boundary peaks
%       3) compares peak Fy
%       4) compares peak mu
%       5) compares peak slip angle
%       6) compares |C-alpha| using the engineering-positive convention
%       7) reports reference-condition results
%       8) saves a detailed CSV
%
% ================================================================

clear;
clc;
close all;

%% ================================================================
% 1. SELECT PRE-MF FINAL 1.5.8
% ================================================================

[file,path] = uigetfile('*.csv', ...
    'Select PRE-MF FINAL 1.5.8 database');

if isequal(file,0)
    error('No database selected.');
end

T = readtable(fullfile(path,file));

fprintf('\n============================================================\n');
fprintf(' CMM LATERAL MF VALIDATOR\n');
fprintf('============================================================\n');

fprintf('Database : %s\n',file);
fprintf('Rows     : %d\n\n',height(T));

disp(T.Properties.VariableNames');

%% ================================================================
% 2. CHECK REQUIRED VARIABLES
% ================================================================

required = { ...
    'Pressure_psi', ...
    'Camber_deg', ...
    'Fz_N', ...
    'mu_peak', ...
    'Fy_peak_N', ...
    'ObservedSA_deg', ...
    'Calpha_N_per_deg', ...
    'Calpha_R2', ...
    'N_total', ...
    'N_peak', ...
    'BoundaryFraction', ...
    'PeakStatus'};

for k = 1:numel(required)

    if ~ismember(required{k},T.Properties.VariableNames)
        error('Required variable missing: %s',required{k});
    end

end

%% ================================================================
% 3. LOAD MF MODEL
% ================================================================

[fileMF,pathMF] = uigetfile('*.mat', ...
    'Select CMM_GLOBAL_MF_LATERAL_v1_5.mat');

if isequal(fileMF,0)
    error('No MF model selected.');
end

S = load(fullfile(pathMF,fileMF));

if ~isfield(S,'GlobalMF')
    error('Selected MAT file does not contain GlobalMF.');
end

q = S.GlobalMF.Parameters;

if numel(q) ~= 19
    error('Expected 19 lateral MF parameters.');
end

FZ0 = S.GlobalMF.Reference.Fz0_N;
P0  = S.GlobalMF.Reference.P0_psi;

fprintf('\nMF reference condition:\n');
fprintf('Fz0 = %.3f N\n',FZ0);
fprintf('P0  = %.3f psi\n',P0);

%% ================================================================
% 4. MODEL SLIP-ANGLE RANGE
% ================================================================
%
% Wider than the old +/-12 deg display range so that we can see
% whether the MF mathematical peak is being pushed toward a boundary.
%
% This does NOT claim the model is validated outside the test envelope.

SA = linspace(-15,15,3001)';

%% ================================================================
% 5. RUN MF FOR EVERY CONDITION
% ================================================================

N = height(T);

MF_Fy_peak = nan(N,1);
MF_mu_peak = nan(N,1);
MF_peak_SA = nan(N,1);
MF_Calpha  = nan(N,1);

fprintf('\nRunning MF model for %d conditions...\n',N);

for i = 1:N

    Fz = T.Fz_N(i);
    IA = T.Camber_deg(i);
    P  = T.Pressure_psi(i);

    Fy = cmmMFglobal( ...
        q,SA,Fz,IA,P,FZ0,P0);

    % Peak magnitude
    [MF_Fy_peak(i),idx] = max(abs(Fy));

    MF_peak_SA(i) = abs(SA(idx));

    MF_mu_peak(i) = MF_Fy_peak(i)/max(abs(Fz),1);

    % Engineering-positive cornering stiffness
    h = 0.01;

    Fy_plus = cmmMFglobal( ...
        q,h,Fz,IA,P,FZ0,P0);

    Fy_minus = cmmMFglobal( ...
        q,-h,Fz,IA,P,FZ0,P0);

    % Raw MF slope is normally negative.
    % C-alpha is reported as positive engineering magnitude.
    MF_Calpha(i) = ...
        abs((Fy_plus-Fy_minus)/(2*h));

end

%% ================================================================
% 6. CONVERT PEAK STATUS TO STRING
% ================================================================

if iscell(T.PeakStatus)
    PeakStatus = string(T.PeakStatus);
else
    PeakStatus = string(T.PeakStatus);
end

PeakStatus = strtrim(PeakStatus);

%% ================================================================
% 7. VALIDITY MASKS
% ================================================================

validFy = ...
    isfinite(T.Fy_peak_N) & ...
    isfinite(MF_Fy_peak) & ...
    T.Fz_N > 0;

validMu = ...
    isfinite(T.mu_peak) & ...
    isfinite(MF_mu_peak) & ...
    T.Fz_N > 0;

validSA = ...
    isfinite(T.ObservedSA_deg) & ...
    isfinite(MF_peak_SA);

validCalpha = ...
    isfinite(T.Calpha_N_per_deg) & ...
    isfinite(MF_Calpha) & ...
    T.Calpha_N_per_deg > 0;

%% ================================================================
% PEAK STATUS CLASSIFICATION
% ================================================================

% IMPORTANT:
% PeakStatus is the primary classification.
% BoundaryFraction is diagnostic information, NOT a binary flag.

boundary = ...
    contains(upper(PeakStatus),'BOUNDARY-LIMITED');

interior = ...
    contains(upper(PeakStatus),'RESOLVED');

fprintf('\nPEAK STATUS COUNTS\n');

fprintf('RESOLVED          : %d\n',sum(interior));
fprintf('BOUNDARY-LIMITED  : %d\n',sum(boundary));

otherStatus = ~(interior | boundary);

fprintf('OTHER/UNKNOWN     : %d\n',sum(otherStatus));

if any(otherStatus)
    fprintf('\nOther PeakStatus values:\n');
    disp(unique(PeakStatus(otherStatus)));
end
%% ================================================================
% VALID MASKS BY PEAK STATUS
% ================================================================

% Only RESOLVED conditions are treated as interior/usable peaks.
%
% NEAR-PLATEAU is kept separate because the exact peak location
% is inherently less certain.
%
% BOUNDARY-LIMITED is also kept separate.

validInteriorFy = validFy & interior;
validInteriorMu = validMu & interior;
validInteriorSA = validSA & interior;
validInteriorCalpha = validCalpha & interior;

validBoundaryFy = validFy & boundary;
validBoundaryMu = validMu & boundary;
validBoundarySA = validSA & boundary;
validBoundaryCalpha = validCalpha & boundary;

nearPlateau = ...
    contains(upper(PeakStatus),'NEAR-PLATEAU');

validPlateauFy = validFy & nearPlateau;
validPlateauMu = validMu & nearPlateau;
validPlateauSA = validSA & nearPlateau;
validPlateauCalpha = validCalpha & nearPlateau;
%% ================================================================
% 9. ERRORS
% ================================================================

Fy_error_pct = nan(N,1);
mu_error_pct = nan(N,1);
SA_error_deg = nan(N,1);
Calpha_error_pct = nan(N,1);

Fy_error_pct(validFy) = ...
    100*(MF_Fy_peak(validFy)-T.Fy_peak_N(validFy)) ...
    ./ max(abs(T.Fy_peak_N(validFy)),1);

mu_error_pct(validMu) = ...
    100*(MF_mu_peak(validMu)-T.mu_peak(validMu)) ...
    ./ max(abs(T.mu_peak(validMu)),0.01);

SA_error_deg(validSA) = ...
    MF_peak_SA(validSA)-T.ObservedSA_deg(validSA);

% Compare engineering-positive magnitudes.
Calpha_error_pct(validCalpha) = ...
    100*(MF_Calpha(validCalpha)-T.Calpha_N_per_deg(validCalpha)) ...
    ./ max(abs(T.Calpha_N_per_deg(validCalpha)),1);

%% ================================================================
% 10. SUMMARY FUNCTION
% ================================================================

printSummary = @(name,err,mask) localPrintSummary(name,err,mask);

fprintf('\n============================================================\n');
fprintf(' ALL CONDITIONS\n');
fprintf('============================================================\n');

printSummary('Peak Fy error [%]',Fy_error_pct,validFy);
printSummary('Peak mu error [%]',mu_error_pct,validMu);
printSummary('Peak SA error [deg]',SA_error_deg,validSA);
printSummary('C-alpha error [%]',Calpha_error_pct,validCalpha);

fprintf('\n============================================================\n');
fprintf(' INTERIOR PEAK CONDITIONS ONLY\n');
fprintf('============================================================\n');

printSummary('Peak Fy error [%]',Fy_error_pct,validInteriorFy);
printSummary('Peak mu error [%]',mu_error_pct,validInteriorMu);
printSummary('Peak SA error [deg]',SA_error_deg,validInteriorSA);
printSummary('C-alpha error [%]',Calpha_error_pct,validInteriorCalpha);

fprintf('\n============================================================\n');
fprintf(' BOUNDARY PEAK CONDITIONS ONLY\n');
fprintf('============================================================\n');

printSummary('Peak Fy error [%]',Fy_error_pct,validBoundaryFy);
printSummary('Peak mu error [%]',mu_error_pct,validBoundaryMu);
printSummary('Peak SA error [deg]',SA_error_deg,validBoundarySA);
printSummary('C-alpha error [%]',Calpha_error_pct,validBoundaryCalpha);

%% ================================================================
% 11. REFERENCE CONDITION
% ================================================================

ref = ...
    abs(T.Fz_N-FZ0) <= 50 & ...
    abs(T.Pressure_psi-P0) <= 0.5 & ...
    abs(T.Camber_deg) <= 0.5;

fprintf('\n============================================================\n');
fprintf(' REFERENCE-CONDITION RESULTS\n');
fprintf('============================================================\n');

if any(ref)

    Ref = table( ...
        T.Pressure_psi(ref), ...
        T.Camber_deg(ref), ...
        T.Fz_N(ref), ...
        T.PeakStatus(ref), ...
        T.BoundaryFraction(ref), ...
        T.Fy_peak_N(ref), ...
        MF_Fy_peak(ref), ...
        Fy_error_pct(ref), ...
        T.mu_peak(ref), ...
        MF_mu_peak(ref), ...
        mu_error_pct(ref), ...
        T.ObservedSA_deg(ref), ...
        MF_peak_SA(ref), ...
        SA_error_deg(ref), ...
        T.Calpha_N_per_deg(ref), ...
        MF_Calpha(ref), ...
        Calpha_error_pct(ref), ...
        'VariableNames',{ ...
        'Pressure_psi', ...
        'Camber_deg', ...
        'Fz_N', ...
        'PeakStatus', ...
        'BoundaryFraction', ...
        'Measured_Fy_peak_N', ...
        'MF_Fy_peak_N', ...
        'Fy_error_pct', ...
        'Measured_mu', ...
        'MF_mu', ...
        'mu_error_pct', ...
        'Measured_peak_SA_deg', ...
        'MF_peak_SA_deg', ...
        'Peak_SA_error_deg', ...
        'Measured_Calpha_N_per_deg', ...
        'MF_Calpha_N_per_deg', ...
        'Calpha_error_pct'});

    disp(Ref);

else

    fprintf('No reference conditions found.\n');

end

%% ================================================================
% 12. PLOT: PEAK FORCE
% ================================================================

figure;

plot(T.Fz_N(validInteriorFy), ...
     T.Fy_peak_N(validInteriorFy),'o');

hold on;

plot(T.Fz_N(validInteriorFy), ...
     MF_Fy_peak(validInteriorFy),'x');

grid on;
box on;

xlabel('Vertical Load F_z [N]');
ylabel('Peak |F_y| [N]');

title('Interior Conditions: Measured vs MF Peak Lateral Force');

legend('Measured','MF Model','Location','best');

%% ================================================================
% 13. PLOT: PEAK MU
% ================================================================

figure;

plot(T.Fz_N(validInteriorMu), ...
     T.mu_peak(validInteriorMu),'o');

hold on;

plot(T.Fz_N(validInteriorMu), ...
     MF_mu_peak(validInteriorMu),'x');

grid on;
box on;

xlabel('Vertical Load F_z [N]');
ylabel('Peak \mu_y');

title('Interior Conditions: Measured vs MF Peak Friction');

legend('Measured','MF Model','Location','best');

%% ================================================================
% 14. PLOT: PEAK SLIP ANGLE
% ================================================================

figure;

plot(T.Fz_N(validInteriorSA), ...
     T.ObservedSA_deg(validInteriorSA),'o');

hold on;

plot(T.Fz_N(validInteriorSA), ...
     MF_peak_SA(validInteriorSA),'x');

grid on;
box on;

xlabel('Vertical Load F_z [N]');
ylabel('Peak Slip Angle [deg]');

title('Interior Conditions: Measured vs MF Peak Slip Angle');

legend('Measured','MF Model','Location','best');

%% ================================================================
% 15. PLOT: CORNERING STIFFNESS
% ================================================================

figure;

plot(T.Fz_N(validInteriorCalpha), ...
     T.Calpha_N_per_deg(validInteriorCalpha),'o');

hold on;

plot(T.Fz_N(validInteriorCalpha), ...
     MF_Calpha(validInteriorCalpha),'x');

grid on;
box on;

xlabel('Vertical Load F_z [N]');
ylabel('C_\alpha [N/deg]');

title('Interior Conditions: Measured vs MF Cornering Stiffness');

legend('Measured','MF Model','Location','best');

%% ================================================================
% 16. SAVE COMPLETE RESULTS
% ================================================================

Results = table( ...
    T.Pressure_psi, ...
    T.Camber_deg, ...
    T.Fz_N, ...
    PeakStatus, ...
    T.BoundaryFraction, ...
    T.N_total, ...
    T.N_peak, ...
    T.Fy_peak_N, ...
    MF_Fy_peak, ...
    Fy_error_pct, ...
    T.mu_peak, ...
    MF_mu_peak, ...
    mu_error_pct, ...
    T.ObservedSA_deg, ...
    MF_peak_SA, ...
    SA_error_deg, ...
    T.Calpha_N_per_deg, ...
    MF_Calpha, ...
    Calpha_error_pct, ...
    'VariableNames',{ ...
    'Pressure_psi', ...
    'Camber_deg', ...
    'Fz_N', ...
    'PeakStatus', ...
    'BoundaryFraction', ...
    'N_total', ...
    'N_peak', ...
    'Measured_Fy_peak_N', ...
    'MF_Fy_peak_N', ...
    'Fy_error_pct', ...
    'Measured_mu', ...
    'MF_mu', ...
    'mu_error_pct', ...
    'Measured_peak_SA_deg', ...
    'MF_peak_SA_deg', ...
    'Peak_SA_error_deg', ...
    'Measured_Calpha_N_per_deg', ...
    'MF_Calpha_N_per_deg', ...
    'Calpha_error_pct'});

[outFile,outPath] = uiputfile( ...
    '*.csv', ...
    'Save detailed lateral MF validation');

if ~isequal(outFile,0)

    writetable(Results,fullfile(outPath,outFile));

    fprintf('\n============================================================\n');
    fprintf(' Results saved:\n%s\n',fullfile(outPath,outFile));
    fprintf('============================================================\n');

end

%% ================================================================
% MAGIC FORMULA
% ================================================================

function Fy = cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)

    a = double(alphaDeg)*pi/180;
    g = double(camberDeg)*pi/180;

    Fz = max(double(Fz),1);

    dfz = (Fz-Fz0)./Fz0;
    dP  = Ppsi-P0;

    PCY1=q(1);

    PDY1=q(2);
    PDY2=q(3);
    PDY3=q(4);

    PEY1=q(5);
    PEY2=q(6);

    PKY1=q(7);
    PKY2=q(8);
    PKY3=q(9);

    PHY1=q(10);
    PHY2=q(11);
    PHY3=q(12);

    PVY1=q(13);
    PVY2=q(14);
    PVY3=q(15);
    PVY4=q(16);

    Pmu1=q(17);
    Pmu2=q(18);

    Pk1=q(19);

    Cy = PCY1;

    mu = ...
        (PDY1+PDY2.*dfz) ...
        .* (1-PDY3.*g.^2);

    muPressure = ...
        1+Pmu1.*dP+Pmu2.*dP.^2;

    mu = mu.*muPressure;

    mu = max(mu,0.20);

    Dy = mu.*Fz;

    Ey = PEY1+PEY2.*dfz;

    Ey = max(-1,min(1,Ey));

    camberFactor = ...
        max(0.10,1-PKY3.*g.^2);

    Ky = ...
        PKY1.*Fz0 .* ...
        sin(2.*atan(Fz./(PKY2.*Fz0))) .* ...
        camberFactor;

    Ky = Ky.*(1+Pk1.*dP);

    Ky = max(Ky,100);

    By = Ky./max(Cy.*Dy,1);

    Shy = ...
        PHY1+PHY2.*dfz+PHY3.*g;

    Svy = ...
        Fz.*(PVY1+PVY2.*dfz) ...
        + mu.*Fz.*(PVY3+PVY4.*dfz).*g;

    x = By.*(a+Shy);

    Fy = ...
        Dy.*sin( ...
        Cy.*atan( ...
        x-Ey.*(x-atan(x)))) ...
        + Svy;

end

%% ================================================================
% LOCAL SUMMARY FUNCTION
% ================================================================

function localPrintSummary(name,err,mask)

    e = err(mask);
    e = e(isfinite(e));

    fprintf('\n%s\n',name);

    if isempty(e)
        fprintf('  No valid data.\n');
        return;
    end

    fprintf('  N             : %d\n',numel(e));
    fprintf('  Mean absolute : %.3f\n',mean(abs(e)));
    fprintf('  Median abs    : %.3f\n',median(abs(e)));
    fprintf('  Maximum abs   : %.3f\n',max(abs(e)));

end
