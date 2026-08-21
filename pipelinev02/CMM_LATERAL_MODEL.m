%% ================================================================
% CMM LATERAL TIRE MODEL
% Simple standalone predictor
%
% Inputs:
%   SA       = slip angle [deg]
%   FZ       = vertical load [N]
%   IA       = camber angle [deg]
%   P        = pressure [psi]
%
% Output:
%   FY       = lateral tire force [N]
%
% Uses the fitted CMM v1.5.1 parameters.
% ================================================================

clear;
clc;
close all;

%% ================================================================
% 1. LOAD FITTED MODEL
% ================================================================

[file,path] = uigetfile('*.mat','Select CMM_GLOBAL_MF_LATERAL_v1_5.mat');

if isequal(file,0)
    error('No model file selected.');
end

S = load(fullfile(path,file));

if ~isfield(S,'GlobalMF')
    error('Selected MAT file does not contain GlobalMF.');
end

q = S.GlobalMF.Parameters;

FZ0 = S.GlobalMF.Reference.Fz0_N;
P0  = S.GlobalMF.Reference.P0_psi;
IA0 = S.GlobalMF.Reference.IA0_deg;

fprintf('\n============================================\n');
fprintf(' CMM LATERAL TIRE MODEL\n');
fprintf('============================================\n');

fprintf('Model file : %s\n',file);
fprintf('Fz0        : %.2f N\n',FZ0);
fprintf('P0         : %.2f psi\n',P0);
fprintf('IA0        : %.2f deg\n',IA0);

fprintf('\n19 MF PARAMETERS:\n');

Names = { ...
    'PCY1','PDY1','PDY2','PDY3','PEY1','PEY2', ...
    'PKY1','PKY2','PKY3','PHY1','PHY2','PHY3', ...
    'PVY1','PVY2','PVY3','PVY4','P_MU_1','P_MU_2','P_K_1'};

for i = 1:19
    fprintf('%-8s = %.12g\n',Names{i},q(i));
end

%% ================================================================
% 2. USER INPUT
% ================================================================

FZ = input('\nEnter vertical load Fz [N] (example 875): ');
IA = input('Enter camber IA [deg] (example 0): ');
P  = input('Enter pressure [psi] (example 12.1): ');

%% ================================================================
% 3. GENERATE SLIP ANGLE RANGE
% ================================================================

SA = linspace(-12,12,481)';

%% ================================================================
% 4. CALCULATE LATERAL FORCE
% ================================================================

FY = cmmMFglobal(q,SA,FZ,IA,P,FZ0,P0);

%% ================================================================
% 5. BASIC RESULTS
% ================================================================

[peakFY,index] = max(abs(FY));

peakSA = SA(index);
muPeak = peakFY/FZ;

% Cornering stiffness around zero slip
h = 0.01;

FYplus  = cmmMFglobal(q,h,FZ,IA,P,FZ0,P0);
FYminus = cmmMFglobal(q,-h,FZ,IA,P,FZ0,P0);

Calpha = (FYplus-FYminus)/(2*h);

fprintf('\n============================================\n');
fprintf(' RESULTS\n');
fprintf('============================================\n');

fprintf('Fz              : %.2f N\n',FZ);
fprintf('Camber          : %.2f deg\n',IA);
fprintf('Pressure        : %.2f psi\n',P);

fprintf('\nPeak |Fy|       : %.2f N\n',peakFY);
fprintf('Peak mu         : %.4f\n',muPeak);
fprintf('Peak slip angle : %.3f deg\n',peakSA);
fprintf('Cornering stiff : %.2f N/deg\n',Calpha);

%% ================================================================
% 6. PLOT
% ================================================================

figure;

plot(SA,FY,'LineWidth',2);

grid on;
box on;

xlabel('Slip Angle \alpha [deg]');
ylabel('Lateral Force F_y [N]');

title(sprintf( ...
    'CMM Lateral MF | F_z = %.0f N | IA = %.1f deg | P = %.1f psi', ...
    FZ,IA,P));

%% ================================================================
% 7. TEST MULTIPLE LOADS
% ================================================================

figure;
hold on;

loads = [210 432 656 875 1096];

for i = 1:length(loads)

    FY_load = cmmMFglobal( ...
        q,SA,loads(i),IA,P,FZ0,P0);

    plot(SA,FY_load,'LineWidth',1.8);

end

grid on;
box on;

xlabel('Slip Angle \alpha [deg]');
ylabel('Lateral Force F_y [N]');

title('CMM Lateral MF - Load Sensitivity');

legend( ...
    '210 N', ...
    '432 N', ...
    '656 N', ...
    '875 N', ...
    '1096 N', ...
    'Location','best');

%% ================================================================
% 8. MODEL FUNCTION
% ================================================================

function Fy = cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)

    % Convert angles to radians
    a = double(alphaDeg)*pi/180;
    g = double(camberDeg)*pi/180;

    % Protect against invalid load
    Fz = max(double(Fz),1);

    % Pressure
    Ppsi = double(Ppsi);

    % Normalized load and pressure
    dfz = (Fz-Fz0)./Fz0;
    dP  = Ppsi-P0;

    % ------------------------------------------------------------
    % PARAMETERS
    % ------------------------------------------------------------

    PCY1 = q(1);

    PDY1 = q(2);
    PDY2 = q(3);
    PDY3 = q(4);

    PEY1 = q(5);
    PEY2 = q(6);

    PKY1 = q(7);
    PKY2 = q(8);
    PKY3 = q(9);

    PHY1 = q(10);
    PHY2 = q(11);
    PHY3 = q(12);

    PVY1 = q(13);
    PVY2 = q(14);
    PVY3 = q(15);
    PVY4 = q(16);

    Pmu1 = q(17);
    Pmu2 = q(18);

    Pk1 = q(19);

    % ------------------------------------------------------------
    % SHAPE FACTOR
    % ------------------------------------------------------------

    Cy = PCY1;

    % ------------------------------------------------------------
    % FRICTION / PEAK FACTOR
    % ------------------------------------------------------------

    mu = (PDY1 + PDY2.*dfz) ...
        .* (1 - PDY3.*g.^2);

    % Pressure dependence
    muPressure = ...
        1 + Pmu1.*dP + Pmu2.*dP.^2;

    mu = mu .* muPressure;

    % Prevent nonphysical negative friction
    mu = max(mu,0.20);

    % Peak lateral force
    Dy = mu .* Fz;

    % ------------------------------------------------------------
    % CURVATURE
    % ------------------------------------------------------------

    Ey = PEY1 + PEY2.*dfz;

    Ey = max(-1.0,min(1.0,Ey));

    % ------------------------------------------------------------
    % CORNERING STIFFNESS
    % ------------------------------------------------------------

    camberFactor = ...
        max(0.10,1-PKY3.*g.^2);

    Ky = PKY1 .* Fz0 .* ...
        sin(2.*atan(Fz./(PKY2.*Fz0))) .* ...
        camberFactor;

    % Pressure effect on stiffness
    Ky = Ky .* (1 + Pk1.*dP);

    % Prevent numerical problems
    Ky = max(Ky,100);

    % ------------------------------------------------------------
    % B FACTOR
    % ------------------------------------------------------------

    By = Ky ./ max(Cy.*Dy,1);

    % ------------------------------------------------------------
    % HORIZONTAL SHIFT
    % ------------------------------------------------------------

    Shy = PHY1 ...
        + PHY2.*dfz ...
        + PHY3.*g;

    % ------------------------------------------------------------
    % VERTICAL SHIFT
    % ------------------------------------------------------------

    Svy = ...
        Fz.*(PVY1 + PVY2.*dfz) ...
        + mu.*Fz.*(PVY3 + PVY4.*dfz).*g;

    % ------------------------------------------------------------
    % MAGIC FORMULA
    % ------------------------------------------------------------

    alphaY = a + Shy;

    x = By .* alphaY;

    Fy = Dy .* sin( ...
        Cy .* atan( ...
        x - Ey.*(x-atan(x)) ...
        )) + Svy;

end