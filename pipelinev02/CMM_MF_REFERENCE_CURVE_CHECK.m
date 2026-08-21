%% ================================================================
% CMM MF REFERENCE CURVE CHECK
%
% Uses:
%   REFERENCE_FY_ALPHA_CURVE_v1_5_8.csv
%
% Reference:
%   Fz = 871.5 N
%   P  = 12.1 psi
%   IA = 0 deg
%
% This does NOT fit the model.
% It only compares the current MF model against the actual
% reference characterization curve.
% ================================================================

clear;
clc;
close all;

%% ================================================================
% 1. LOAD REFERENCE CURVE
% ================================================================

[file,path] = uigetfile('*.csv', ...
    'Select REFERENCE_FY_ALPHA_CURVE_v1_5_8.csv');

if isequal(file,0)
    error('No reference curve selected.');
end

T = readtable(fullfile(path,file));

fprintf('\n============================================\n');
fprintf(' CMM MF REFERENCE CURVE CHECK\n');
fprintf('============================================\n');

fprintf('File: %s\n',file);

%% ================================================================
% 2. EXTRACT THE 62 CURVE POINTS
% ================================================================

SA = nan(62,1);
FY = nan(62,1);
FZ = nan(62,1);

for k = 1:62

    SA(k) = T.(sprintf('AbsSA_deg_%d',k));

    FY(k) = T.(sprintf('Fy_abs_N_%d',k));

    FZ(k) = T.(sprintf('Fz_median_N_%d',k));

end

%% ================================================================
% 3. REMOVE INVALID POINTS
% ================================================================

valid = ...
    isfinite(SA) & ...
    isfinite(FY) & ...
    isfinite(FZ);

SA = SA(valid);
FY = FY(valid);
FZ = FZ(valid);

%% ================================================================
% 4. REFERENCE CONDITIONS
% ================================================================

FZ0 = 871.5;
P0  = 12.1;
IA0 = 0;

fprintf('\nReference condition:\n');
fprintf('Fz = %.1f N\n',FZ0);
fprintf('P  = %.2f psi\n',P0);
fprintf('IA = %.1f deg\n',IA0);

fprintf('\nCurve points: %d\n',length(SA));

fprintf('Measured Fz range: %.2f to %.2f N\n', ...
    min(FZ),max(FZ));

%% ================================================================
% 5. LOAD CURRENT MF MODEL
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

fprintf('\nMF model loaded.\n');

%% ================================================================
% 6. CALCULATE MF CURVE
% ================================================================

SA_model = linspace( ...
    min(SA), ...
    max(SA), ...
    2000)';

FY_model = cmmMFglobal( ...
    q, ...
    SA_model, ...
    FZ0, ...
    IA0, ...
    P0, ...
    FZ0, ...
    P0);

%% ================================================================
% 7. INTERPOLATE MF ONTO MEASURED POINTS
% ================================================================

FY_MF_at_data = interp1( ...
    SA_model, ...
    FY_model, ...
    SA, ...
    'linear', ...
    'extrap');

%% ================================================================
% 8. ERROR METRICS
% ================================================================

residual = FY - FY_MF_at_data;

RMSE = sqrt(mean(residual.^2));

MAE = mean(abs(residual));

R2 = 1 - ...
    sum(residual.^2) / ...
    sum((FY-mean(FY)).^2);

MAPE = mean( ...
    abs(residual) ./ max(abs(FY),50) ...
    ) * 100;

%% ================================================================
% 9. PEAK INFORMATION
% ================================================================

[measuredPeak,im] = max(FY);

measuredPeakSA = SA(im);

[MFpeak,ip] = max(FY_model);

MFpeakSA = SA_model(ip);

measuredMu = measuredPeak/FZ0;

MFMU = MFpeak/FZ0;

%% ================================================================
% 10. CORNERING STIFFNESS
% ================================================================

% Use only data within +/-2 degrees.

nearZero = abs(SA) <= 2;

if sum(nearZero) >= 3

    p = polyfit(SA(nearZero), ...
                FY(nearZero),1);

    CalphaMeasured = abs(p(1));

else

    CalphaMeasured = NaN;

end

h = 0.01;

FYplus = cmmMFglobal( ...
    q,h,FZ0,IA0,P0,FZ0,P0);

FYminus = cmmMFglobal( ...
    q,-h,FZ0,IA0,P0,FZ0,P0);

CalphaMF = ...
    abs((FYplus-FYminus)/(2*h));

%% ================================================================
% 11. PRINT RESULTS
% ================================================================

fprintf('\n============================================\n');
fprintf(' VALIDATION RESULTS\n');
fprintf('============================================\n');

fprintf('\nR2                 : %.6f\n',R2);
fprintf('RMSE               : %.2f N\n',RMSE);
fprintf('MAE                : %.2f N\n',MAE);
fprintf('Mean relative err  : %.2f %%\n',MAPE);

fprintf('\nMeasured max Fy    : %.2f N\n',measuredPeak);
fprintf('MF max Fy          : %.2f N\n',MFpeak);

fprintf('\nMeasured max mu    : %.4f\n',measuredMu);
fprintf('MF max mu          : %.4f\n',MFMU);

fprintf('\nMeasured peak SA   : %.3f deg\n',measuredPeakSA);
fprintf('MF peak SA         : %.3f deg\n',MFpeakSA);

fprintf('\nMeasured C-alpha   : %.2f N/deg\n', ...
    CalphaMeasured);

fprintf('MF C-alpha         : %.2f N/deg\n', ...
    CalphaMF);

%% ================================================================
% 12. PLOT
% ================================================================

figure('Color','w');

plot(SA,FY,'o', ...
    'MarkerSize',5);

hold on;

plot(SA_model,FY_model, ...
    'LineWidth',2);

grid on;
box on;

xlabel('Absolute Slip Angle |\alpha| [deg]');
ylabel('|F_y| [N]');

title( ...
    sprintf( ...
    'Reference Lateral Curve | F_z = %.1f N | P = %.1f psi | IA = %.1f deg', ...
    FZ0,P0,IA0));

legend( ...
    'Measured characterization', ...
    'MF model', ...
    'Location','best');

%% ================================================================
% 13. RESIDUAL PLOT
% ================================================================

figure('Color','w');

plot(SA,residual,'o-');

grid on;
box on;

yline(0,'--');

xlabel('Absolute Slip Angle |\alpha| [deg]');
ylabel('Measured - MF F_y [N]');

title('Reference Curve MF Residual');

%% ================================================================
% MAGIC FORMULA
% ================================================================

function Fy = cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)

a = double(alphaDeg)*pi/180;

g = double(camberDeg)*pi/180;

Fz = max(double(Fz),1);

dfz = (Fz-Fz0)./Fz0;

dP = Ppsi-P0;

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
    +mu.*Fz.*(PVY3+PVY4.*dfz).*g;

x = By.*(a+Shy);

Fy = ...
    Dy.*sin( ...
    Cy.*atan( ...
    x-Ey.*(x-atan(x)))) ...
    +Svy;

end