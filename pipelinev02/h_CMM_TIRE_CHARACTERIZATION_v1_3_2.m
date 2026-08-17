%% CMM TIRE CHARACTERIZATION v1.3.2
% PROPER ENGINEERING CHARACTERIZATION / PRE-MF FREEZE
%
% Purpose:
%   Convert the validated v1.5.8 TTC reduction into engineering
%   characterization quantities before any Magic Formula fitting.
%
% This stage DOES NOT fit Magic Formula coefficients.
%
% Characterized effects:
%   1) Fy vs |SA| at the reference operating window
%   2) mu_y vs |SA| at the reference operating window
%   3) Load sensitivity at fixed slip angles
%   4) Cornering stiffness vs load
%   5) Pressure sensitivity at fixed slip angles
%   6) Camber sensitivity at fixed slip angles
%   7) Reference operating-point summary
%
% Important:
%   - True peak mu is not required for the main load-sensitivity
%     characterization because many TTC sweeps are boundary-limited.
%   - Fixed-slip-angle characterization is therefore used as the primary
%     engineering trend tool.
%   - Absolute Fy is used for symmetric pure-cornering magnitude curves.
%   - Signed Fy near zero slip is retained for camber-thrust analysis.
%
% INPUT:
%   _PRE_MF_MATRIX_v1_3_2\TTC_CONDITION_ASSIGNED_DATABASE.csv
%
% OUTPUT:
%   _TIRE_CHARACTERIZATION_v1_3_2\
%
% Based on the validated v1.5.8 reduction contract.
% No raw TTC file is modified.

clear; clc; close all;

fprintf('\n============================================================\n');
fprintf(' CMM TIRE CHARACTERIZATION v1.3.2\n');
fprintf(' ENGINEERING CHARACTERIZATION / NO MF FITTING\n');
fprintf('============================================================\n\n');

%% ============================================================
% [1] PATHS
% =============================================================

projectFolder = uigetdir(pwd,'Select CMM project/data folder');
if isequal(projectFolder,0)
    error('No project folder selected.');
end

thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));

% Use the frozen v1.5.8 PRE-MF database as the input contract.
% Do NOT require a new _PRE_MF_MATRIX_v1_3_2 folder.
inputCandidates = {
    fullfile(projectFolder,'_PRE_MF_MATRIX_v1_3', ...
        'TTC_CONDITION_ASSIGNED_DATABASE.csv')
    fullfile(projectFolder,'_PRE_MF_MATRIX_v1_3_2', ...
        'TTC_CONDITION_ASSIGNED_DATABASE.csv')
    fullfile(projectFolder,'_PRE_MF_FINAL_v1_5_8', ...
        'TTC_CONDITION_ASSIGNED_DATABASE.csv')
    };

inputFile = '';
for k = 1:numel(inputCandidates)
    if isfile(inputCandidates{k})
        inputFile = inputCandidates{k};
        break;
    end
end

outputFolder = fullfile(repoRoot,'outputs','11_TIRE_CHARACTERIZATION_v1_3_2');

if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end

fprintf('[1] INPUT (FROZEN PRE-MF DATABASE)\n%s\n\n',inputFile);

if isempty(inputFile)
    error(['Frozen PRE-MF database not found. Checked:\n' ...
        '  %s\n  %s\n  %s'], ...
        inputCandidates{1},inputCandidates{2},inputCandidates{3});
end

%% ============================================================
% [2] LOAD + SIGNAL MAPPING
% =============================================================

T = readtable(inputFile,'VariableNamingRule','preserve');
names = string(T.Properties.VariableNames);
normNames = lower(regexprep(names,'[^a-zA-Z0-9]',''));

ia = pickVar(names,normNames, ...
    {'ia','inclination','camber','inclinationangle'});
sa = pickVar(names,normNames, ...
    {'sa','slipangle','slipangledeg','alpha'});
fz = pickVar(names,normNames, ...
    {'fz','fznew','verticalload','verticalforce','normalforce'});
fy = pickVar(names,normNames, ...
    {'fy','lateralforce','lateralforcey'});
p = pickVar(names,normNames, ...
    {'p','pressure','inflationpressure','pressurekpa','pressurepa'});

SA = double(T.(sa));
FY = double(T.(fy));
FZ = abs(double(T.(fz)));
IA = double(T.(ia));
Praw = double(T.(p));

Pmed = median(Praw,'omitnan');

if Pmed > 1000
    PkPa = Praw/1000;
elseif Pmed < 30
    PkPa = Praw*6.894757293;
else
    PkPa = Praw;
end

Ppsi = PkPa/6.894757293;

valid = isfinite(SA) & isfinite(FY) & isfinite(FZ) & ...
        isfinite(IA) & isfinite(Ppsi) & FZ>0;

SA=SA(valid); FY=FY(valid); FZ=FZ(valid);
IA=IA(valid); Ppsi=Ppsi(valid);

% Established TTC Fy sign normalization.
posSA = SA > 2 & SA < 8;
negSA = SA < -2 & SA > -8;

medPos = median(FY(posSA),'omitnan');
medNeg = median(FY(negSA),'omitnan');

fyMultiplier = 1;
if isfinite(medPos) && isfinite(medNeg) && medPos < 0 && medNeg > 0
    fyMultiplier = -1;
end

FY = FY*fyMultiplier;

fprintf('[2] DATABASE\n');
fprintf('Rows             : %d\n',numel(SA));
fprintf('SA               : %.3f -> %.3f deg\n',min(SA),max(SA));
fprintf('FY               : %.2f -> %.2f N\n',min(FY),max(FY));
fprintf('FZ               : %.2f -> %.2f N\n',min(FZ),max(FZ));
fprintf('IA               : %.3f -> %.3f deg\n',min(IA),max(IA));
fprintf('Pressure         : %.2f -> %.2f psi\n',min(Ppsi),max(Ppsi));
fprintf('Fy multiplier    : %.0f\n\n',fyMultiplier);

%% ============================================================
% [3] VEHICLE / REFERENCE OPERATING POINT
% =============================================================

vehicleMassKg = 320;
g = 9.80665;
frontFrac = 0.60;
rearFrac = 0.40;

vehicleWeightN = vehicleMassKg*g;
frontTireLoad = vehicleWeightN*frontFrac/2;
rearTireLoad = vehicleWeightN*rearFrac/2;

refFz = 871.5;  % Frozen v1.5.8 reference characterization load
refPpsi = 12.10;
refCamber = 0.0;

refLoadHalfWidth = 75;
refPressureHalfWidth = 0.20;
camberTolerance = 0.20;

% Engineering slip-angle stations.
alphaStations = (0:1:12)';

% Load bins are deliberately centered around useful TTC ranges.
loadEdges = [150 250 350 450 550 650 750 825 925 1025 1125 1210];
loadCenters = (loadEdges(1:end-1)+loadEdges(2:end))/2;

pressureCenters = [8 10 12 14];
pressureHalfWidth = 0.45;

camberCenters = unique(round(IA/2)*2);
camberCenters = camberCenters(camberCenters>=-0.5 & camberCenters<=4.5);

fprintf('[3] REFERENCE OPERATING POINT\n');
fprintf('Front static tire load : %.1f N\n',frontTireLoad);
fprintf('Rear static tire load  : %.1f N\n',rearTireLoad);
fprintf('Reference load         : %.1f N\n',refFz);
fprintf('Reference pressure     : %.2f psi\n',refPpsi);
fprintf('Reference camber       : %.1f deg\n',refCamber);
fprintf('Reference selection    : FROZEN CMM CONTRACT (not auto-selected from file)\n');
fprintf('Pressure source        : explicit project reference 12.10 +/- 0.20 psi\n');
fprintf('Load source            : explicit project reference 871.5 +/- 75 N\n\n');

%% ============================================================
% [4] REFERENCE Fy-alpha / mu-alpha CHARACTERIZATION
% =============================================================

refMask = Ppsi >= refPpsi-refPressureHalfWidth & ...
          Ppsi <= refPpsi+refPressureHalfWidth & ...
          abs(IA-refCamber)<=camberTolerance & ...
          FZ>=refFz-refLoadHalfWidth & ...
          FZ<=refFz+refLoadHalfWidth;

aRef = abs(SA(refMask));
fyRef = abs(FY(refMask));
fzRef = FZ(refMask);

if nnz(refMask)<100
    error('Reference operating window has insufficient samples.');
end

refRows = nan(numel(alphaStations),8);

for k=1:numel(alphaStations)

    a0 = alphaStations(k);
    band = abs(aRef-a0)<=0.20;

    if nnz(band)>=10
        yy = fyRef(band);
        zz = fzRef(band);

        refRows(k,:) = [ ...
            a0, ...
            median(yy,'omitnan'), ...
            prctile(yy,10), ...
            prctile(yy,90), ...
            median(yy./zz,'omitnan'), ...
            prctile(yy./zz,10), ...
            prctile(yy./zz,90), ...
            nnz(band)];
    end
end

ReferenceCurve = array2table(refRows, ...
    'VariableNames',{ ...
    'SA_deg','Fy_median_N','Fy_P10_N','Fy_P90_N', ...
    'Mu_median','Mu_P10','Mu_P90','N'});

writetable(ReferenceCurve,fullfile(outputFolder, ...
    'REFERENCE_FY_MU_CHARACTERIZATION_v1_3_2.csv'));

% Dense reference characterization table: every measured integer SA bin
% represented by median/P10/P90 force and normalized force.

%% ============================================================
% [5] CORNERING STIFFNESS DIAGNOSTIC — THREE DEFINITIONS
% =============================================================
%
% C-alpha is defined locally at alpha = 0.  We therefore report three
% windows rather than silently selecting one broad fit:
%
%   A: |SA| <= 0.50 deg       local slope
%   B: |SA| <= 1.00 deg       near-linear slope
%   C: 0.25 <= |SA| <= 2 deg   legacy/broad comparison
%
% The fits use SIGNED SA and SIGNED Fy.  This is important: taking
% abs(SA) and abs(Fy) can distort the local slope when the two sides are
% not perfectly symmetric.
%
% Each method is calculated both at the reference window and for each
% load bin below.  No value is forced toward an expected tire range.

alphaWinA = [0.00 0.50];
alphaWinB = [0.00 1.00];
alphaWinC = [0.25 2.00];

calphaWindows = [alphaWinA; alphaWinB; alphaWinC];
calphaNames = {'LOCAL_0_0p5','LOCAL_0_1p0','BROAD_0p25_2p0'};

caRefRows = nan(3,7);

for m=1:3
    w = calphaWindows(m,:);
    z = refMask & abs(SA)>=w(1) & abs(SA)<=w(2);

    xx = SA(z);
    yy = FY(z);

    good = isfinite(xx) & isfinite(yy);
    xx = xx(good); yy = yy(good);

    if numel(xx) >= 30 && numel(unique(xx)) >= 3
        pp = polyfit(xx,yy,1);
        pred = polyval(pp,xx);
        sse = sum((yy-pred).^2);
        sst = sum((yy-mean(yy)).^2);
        if sst>0
            r2 = 1-sse/sst;
        else
            r2 = NaN;
        end
        caRefRows(m,:) = [m,w(1),w(2),pp(1),pp(2),r2,numel(xx)];
    end
end

CAlphaReference = array2table(caRefRows, ...
    'VariableNames',{'MethodID','SA_min_deg','SA_max_deg', ...
    'Calpha_N_per_deg','Fy_intercept_N','R2','N'});
CAlphaReference.Method = string(calphaNames(:));
CAlphaReference = movevars(CAlphaReference,'Method','Before','MethodID');

writetable(CAlphaReference,fullfile(outputFolder, ...
    'CALPHA_REFERENCE_METHODS_v1_3_2.csv'));

% Keep the broad value only as a comparison quantity.  The primary
% reference C-alpha is the local 0-0.5 deg estimate.
calphaRef = CAlphaReference.Calpha_N_per_deg(1);
calphaR2 = CAlphaReference.R2(1);

fprintf('[4] REFERENCE CORNERING STIFFNESS — THREE METHODS\n');
for m=1:3
    fprintf('%-18s : %9.3f N/deg | R2 %.5f | N %d\n', ...
        CAlphaReference.Method(m), ...
        CAlphaReference.Calpha_N_per_deg(m), ...
        CAlphaReference.R2(m), ...
        CAlphaReference.N(m));
end
fprintf('Primary definition : LOCAL 0 -> 0.50 deg\n');
fprintf('NOTE                : broad 0.25 -> 2.00 deg retained for comparison\n\n');

%% ============================================================
% [6] LOAD SENSITIVITY AT FIXED SLIP ANGLES
% =============================================================
%
% Primary load-sensitivity characterization uses fixed |SA|
% stations. This avoids interpreting boundary-limited peak
% values as true peaks.

nL = numel(loadCenters);
nA = numel(alphaStations);

LoadRows = [];

for b=1:nL

    idxLoad = Ppsi>=refPpsi-refPressureHalfWidth & ...
              Ppsi<=refPpsi+refPressureHalfWidth & ...
              abs(IA-refCamber)<=camberTolerance & ...
              FZ>=loadEdges(b) & FZ<loadEdges(b+1);

    if nnz(idxLoad)<50
        continue;
    end

    for k=1:nA

        a0 = alphaStations(k);
        band = idxLoad & abs(abs(SA)-a0)<=0.20;

        if nnz(band)<10
            continue;
        end

        fyMed = median(abs(FY(band)),'omitnan');
        fzMed = median(FZ(band),'omitnan');
        muMed = median(abs(FY(band))./FZ(band),'omitnan');

        LoadRows(end+1,:) = [ ...
            fzMed,a0,fyMed,muMed,nnz(band)]; %#ok<AGROW>
    end
end

LoadFixedSA = array2table(LoadRows, ...
    'VariableNames',{'Fz_N','SA_deg','Fy_median_N','Mu_median','N'});

writetable(LoadFixedSA,fullfile(outputFolder, ...
    'LOAD_SENSITIVITY_FIXED_SA_v1_3_2.csv'));

%% ============================================================
% [7] C-alpha VS LOAD — THREE WINDOWS
% =============================================================

caRows = [];

for b=1:nL

    idxLoad = Ppsi>=refPpsi-refPressureHalfWidth & ...
              Ppsi<=refPpsi+refPressureHalfWidth & ...
              abs(IA-refCamber)<=camberTolerance & ...
              FZ>=loadEdges(b) & FZ<loadEdges(b+1);

    if nnz(idxLoad)<100
        continue;
    end

    for m=1:3
        w = calphaWindows(m,:);
        low = idxLoad & abs(SA)>=w(1) & abs(SA)<=w(2);

        xx=SA(low);
        yy=FY(low);
        good=isfinite(xx)&isfinite(yy);
        xx=xx(good); yy=yy(good);

        if numel(xx)<30 || numel(unique(xx))<3
            continue;
        end

        pp=polyfit(xx,yy,1);
        pred=polyval(pp,xx);
        sse=sum((yy-pred).^2);
        sst=sum((yy-mean(yy)).^2);
        if sst>0
            r2=1-sse/sst;
        else
            r2=NaN;
        end

        caRows(end+1,:)=[ ...
            median(FZ(idxLoad),'omitnan'), ...
            m, pp(1), pp(2), r2, numel(xx)]; %#ok<AGROW>
    end
end

CAlphaLoad=array2table(caRows, ...
    'VariableNames',{'Fz_N','MethodID','Calpha_N_per_deg', ...
    'Fy_intercept_N','R2','N_low_alpha'});
methodIDs = round(CAlphaLoad.MethodID);
methodLabels = strings(height(CAlphaLoad),1);
for ii=1:height(CAlphaLoad)
    if methodIDs(ii)>=1 && methodIDs(ii)<=numel(calphaNames)
        methodLabels(ii)=string(calphaNames{methodIDs(ii)});
    else
        methodLabels(ii)="UNKNOWN";
    end
end
CAlphaLoad.Method=methodLabels;
CAlphaLoad=movevars(CAlphaLoad,'Method','Before','Fz_N');

writetable(CAlphaLoad,fullfile(outputFolder, ...
    'CALPHA_VS_LOAD_ALL_METHODS_v1_3_2.csv'));

% Backward-compatible primary table for downstream use.
primaryMask = CAlphaLoad.MethodID==1;
CAlphaLoadPrimary = CAlphaLoad(primaryMask,:);
writetable(CAlphaLoadPrimary,fullfile(outputFolder, ...
    'CALPHA_VS_LOAD_v1_3_2.csv'));

%% ============================================================
% [8] LOAD SENSITIVITY FITS
% =============================================================
%
% Characterize mu(Fz) at fixed alpha stations.
% A power law is reported only as a descriptive engineering fit:
%
%   mu = A*(Fz/Fz_ref)^B
%
% It is NOT yet an MF parameterization.

fitAngles = [2 4 6 8 10 12];
fitRows = [];

for k=1:numel(fitAngles)

    a0=fitAngles(k);
    z=LoadFixedSA.SA_deg==a0 & ...
      isfinite(LoadFixedSA.Fz_N) & ...
      isfinite(LoadFixedSA.Mu_median) & ...
      LoadFixedSA.Mu_median>0;

    if nnz(z)<4
        continue;
    end

    F=LoadFixedSA.Fz_N(z);
    M=LoadFixedSA.Mu_median(z);

    q=polyfit(log(F/refFz),log(M),1);
    B=q(1);
    A=exp(q(2));

    pred=A*(F/refFz).^B;

    ssres=sum((M-pred).^2);
    sstot=sum((M-mean(M)).^2);

    if sstot>0
        r2=1-ssres/sstot;
    else
        r2=NaN;
    end

    fitRows(end+1,:)=[a0,A,B,r2,nnz(z)]; %#ok<AGROW>
end

LoadFit = array2table(fitRows, ...
    'VariableNames',{'SA_deg','MuRef','LoadExponent_B','R2','N_bins'});

writetable(LoadFit,fullfile(outputFolder, ...
    'LOAD_SENSITIVITY_FITS_v1_3_2.csv'));

%% ============================================================
% [9] PRESSURE CHARACTERIZATION
% =============================================================

pressureRows=[];

for j=1:numel(pressureCenters)

    idxBase=Ppsi>=pressureCenters(j)-pressureHalfWidth & ...
            Ppsi<=pressureCenters(j)+pressureHalfWidth & ...
            abs(IA-refCamber)<=camberTolerance & ...
            FZ>=refFz-refLoadHalfWidth & ...
            FZ<=refFz+refLoadHalfWidth;

    if nnz(idxBase)<50
        continue;
    end

    for k=1:numel(alphaStations)

        a0=alphaStations(k);
        band=idxBase & abs(abs(SA)-a0)<=0.20;

        if nnz(band)<10
            continue;
        end

        pressureRows(end+1,:)=[ ...
            pressureCenters(j),a0, ...
            median(abs(FY(band)),'omitnan'), ...
            median(abs(FY(band))./FZ(band),'omitnan'), ...
            nnz(band)]; %#ok<AGROW>
    end
end

PressureCharacterization=array2table(pressureRows, ...
    'VariableNames',{'Pressure_psi','SA_deg','Fy_median_N','Mu_median','N'});

writetable(PressureCharacterization,fullfile(outputFolder, ...
    'PRESSURE_CHARACTERIZATION_v1_3_2.csv'));

%% ============================================================
% [10] CAMBER CHARACTERIZATION
% =============================================================

camberRows=[];

for j=1:numel(camberCenters)

    idxBase=abs(IA-camberCenters(j))<=camberTolerance & ...
            Ppsi>=refPpsi-refPressureHalfWidth & ...
            Ppsi<=refPpsi+refPressureHalfWidth & ...
            FZ>=refFz-refLoadHalfWidth & ...
            FZ<=refFz+refLoadHalfWidth;

    if nnz(idxBase)<50
        continue;
    end

    for k=1:numel(alphaStations)

        a0=alphaStations(k);

        band=idxBase & abs(abs(SA)-a0)<=0.20;

        if nnz(band)<10
            continue;
        end

        % Preserve signed Fy here so camber thrust is not erased.
        camberRows(end+1,:)=[ ...
            camberCenters(j),a0, ...
            median(FY(band),'omitnan'), ...
            median(abs(FY(band)),'omitnan'), ...
            median(abs(FY(band))./FZ(band),'omitnan'), ...
            nnz(band)]; %#ok<AGROW>
    end
end

CamberCharacterization=array2table(camberRows, ...
    'VariableNames',{'Camber_deg','SA_deg','Fy_signed_median_N', ...
    'Fy_magnitude_median_N','Mu_median','N'});

writetable(CamberCharacterization,fullfile(outputFolder, ...
    'CAMBER_CHARACTERIZATION_v1_3_2.csv'));

%% ============================================================
% [11] REFERENCE SUMMARY
% =============================================================

ref8 = ReferenceCurve.Mu_median(ReferenceCurve.SA_deg==8);
ref10 = ReferenceCurve.Mu_median(ReferenceCurve.SA_deg==10);
ref12 = ReferenceCurve.Mu_median(ReferenceCurve.SA_deg==12);

summary = table( ...
    refPpsi,refCamber,refFz, ...
    CAlphaReference.Calpha_N_per_deg(1), ...
    CAlphaReference.Calpha_N_per_deg(2), ...
    CAlphaReference.Calpha_N_per_deg(3), ...
    CAlphaReference.R2(1), ...
    getScalar(ref8),getScalar(ref10),getScalar(ref12), ...
    'VariableNames',{ ...
    'ReferencePressure_psi','ReferenceCamber_deg','ReferenceFz_N', ...
    'Calpha_Local_0_0p5_N_per_deg','Calpha_Local_0_1p0_N_per_deg', ...
    'Calpha_Broad_0p25_2p0_N_per_deg','Calpha_Local_R2', ...
    'Mu_at_8deg','Mu_at_10deg','Mu_at_12deg'});

writetable(summary,fullfile(outputFolder, ...
    'CHARACTERIZATION_SUMMARY_v1_3_2.csv'));

%% ============================================================
% [13] ENGINEERING PLOTS
% =============================================================
%
% v1.3.2 display architecture:
%   - One MATLAB UI figure
%   - One tab per engineering plot
%   - Black figure + BLACK AXES
%   - White labels/grid
%   - PNG export retained
%
% This avoids six separate MATLAB windows while keeping every plot
% independently inspectable.

fprintf('[12] CHARACTERIZATION DATA COUNTS\n');
fprintf('Reference curve rows      : %d\n',height(ReferenceCurve));
fprintf('Load fixed-SA rows        : %d\n',height(LoadFixedSA));
fprintf('C-alpha method rows       : %d\n',height(CAlphaLoad));
fprintf('Pressure rows             : %d\n',height(PressureCharacterization));
fprintf('Camber rows               : %d\n\n',height(CamberCharacterization));

fprintf('[13] GENERATING CHARACTERIZATION PLOTS\n');

mainFig = figure( ...
    'Name','CMM Tire Characterization v1.3.2', ...
    'Color','k', ...
    'WindowState','maximized', ...
    'NumberTitle','off', ...
    'Toolbar','figure');

tabGroup = uitabgroup(mainFig, ...
    'Position',[0 0 1 1]);

% ------------------------------------------------------------
% 1. Reference Fy-alpha
% ------------------------------------------------------------
tab1 = uitab(tabGroup,'Title','01 — Fy vs Slip Angle');
ax1 = axes('Parent',tab1,'Position',[0.08 0.10 0.88 0.84]);
styleBlackAxes(ax1);
set(tab1,'BackgroundColor',[0 0 0]);

errorbar(ax1,ReferenceCurve.SA_deg, ...
         ReferenceCurve.Fy_median_N, ...
         ReferenceCurve.Fy_median_N-ReferenceCurve.Fy_P10_N, ...
         ReferenceCurve.Fy_P90_N-ReferenceCurve.Fy_median_N, ...
         'o-','LineWidth',1.3,'MarkerSize',5);

styleBlackAxes(ax1);
grid(ax1,'on');
xlabel(ax1,'|SA| [deg]');
ylabel(ax1,'|F_y| [N]');
title(ax1,'CMM Characterization — Reference Lateral Force');
exportgraphics(ax1,fullfile(outputFolder, ...
    '01_REFERENCE_FY_ALPHA.png'),'Resolution',180);

% ------------------------------------------------------------
% 2. Reference mu-alpha
% ------------------------------------------------------------
tab2 = uitab(tabGroup,'Title','02 — Mu vs Slip Angle');
ax2 = axes('Parent',tab2,'Position',[0.08 0.10 0.88 0.84]);
styleBlackAxes(ax2);
set(tab2,'BackgroundColor',[0 0 0]);

errorbar(ax2,ReferenceCurve.SA_deg, ...
         ReferenceCurve.Mu_median, ...
         ReferenceCurve.Mu_median-ReferenceCurve.Mu_P10, ...
         ReferenceCurve.Mu_P90-ReferenceCurve.Mu_median, ...
         'o-','LineWidth',1.3,'MarkerSize',5);

styleBlackAxes(ax2);
grid(ax2,'on');
xlabel(ax2,'|SA| [deg]');
ylabel(ax2,'\mu_y = |F_y|/F_z');
title(ax2,'CMM Characterization — Reference Normalized Lateral Force');
exportgraphics(ax2,fullfile(outputFolder, ...
    '02_REFERENCE_MU_ALPHA.png'),'Resolution',180);

% ------------------------------------------------------------
% 3. Load sensitivity at fixed alpha
% ------------------------------------------------------------
tab3 = uitab(tabGroup,'Title','03 — Load Sensitivity');
ax3 = axes('Parent',tab3,'Position',[0.08 0.10 0.88 0.84]);
styleBlackAxes(ax3);
set(tab3,'BackgroundColor',[0 0 0]);
hold(ax3,'on');

for k=1:numel(fitAngles)
    z=LoadFixedSA.SA_deg==fitAngles(k);
    scatter(ax3,LoadFixedSA.Fz_N(z),LoadFixedSA.Mu_median(z), ...
        45,'DisplayName',sprintf('%d deg',fitAngles(k)));
end

xline(ax3,frontTireLoad,'--','Front static load');
xline(ax3,rearTireLoad,'--','Rear static load');

styleBlackAxes(ax3);
grid(ax3,'on');
xlabel(ax3,'F_z [N]');
ylabel(ax3,'\mu_y');
title(ax3,'CMM Characterization — Load Sensitivity at Fixed Slip Angles');
lg3=legend(ax3,'Location','best');
styleBlackLegend(lg3);
exportgraphics(ax3,fullfile(outputFolder, ...
    '03_LOAD_SENSITIVITY_FIXED_SA.png'),'Resolution',180);

% ------------------------------------------------------------
% 4. C-alpha vs load — compare definitions
% ------------------------------------------------------------
tab4 = uitab(tabGroup,'Title','04 — C-alpha vs Load');
ax4 = axes('Parent',tab4,'Position',[0.08 0.10 0.88 0.84]);
styleBlackAxes(ax4);
set(tab4,'BackgroundColor',[0 0 0]);
hold(ax4,'on');

for m=1:3
    z=CAlphaLoad.MethodID==m;
    plot(ax4,CAlphaLoad.Fz_N(z),CAlphaLoad.Calpha_N_per_deg(z), ...
        'o-','LineWidth',1.2,'MarkerSize',5, ...
        'DisplayName',char(calphaNames(m)));
end

xline(ax4,frontTireLoad,'--','Front static load');
xline(ax4,rearTireLoad,'--','Rear static load');

styleBlackAxes(ax4);
grid(ax4,'on');
xlabel(ax4,'F_z [N]');
ylabel(ax4,'C_\alpha [N/deg]');
title(ax4,'CMM Characterization — Cornering Stiffness vs Load');
lg4=legend(ax4,'Location','best');
styleBlackLegend(lg4);
exportgraphics(ax4,fullfile(outputFolder, ...
    '04_CALPHA_VS_LOAD_ALL_METHODS.png'),'Resolution',180);

% ------------------------------------------------------------
% 5. Pressure sensitivity
% ------------------------------------------------------------
tab5 = uitab(tabGroup,'Title','05 — Pressure Sensitivity');
ax5 = axes('Parent',tab5,'Position',[0.08 0.10 0.88 0.84]);
styleBlackAxes(ax5);
set(tab5,'BackgroundColor',[0 0 0]);
hold(ax5,'on');

for k=1:numel(fitAngles)
    z=PressureCharacterization.SA_deg==fitAngles(k);
    scatter(ax5,PressureCharacterization.Pressure_psi(z), ...
            PressureCharacterization.Mu_median(z), ...
            45,'DisplayName',sprintf('%d deg',fitAngles(k)));
end

styleBlackAxes(ax5);
grid(ax5,'on');
xlabel(ax5,'Pressure [psi]');
ylabel(ax5,'\mu_y');
title(ax5,'CMM Characterization — Pressure Sensitivity');
lg5=legend(ax5,'Location','best');
styleBlackLegend(lg5);
exportgraphics(ax5,fullfile(outputFolder, ...
    '05_PRESSURE_SENSITIVITY.png'),'Resolution',180);

% ------------------------------------------------------------
% 6. Camber sensitivity
% ------------------------------------------------------------
tab6 = uitab(tabGroup,'Title','06 — Camber Sensitivity');
ax6 = axes('Parent',tab6,'Position',[0.08 0.10 0.88 0.84]);
styleBlackAxes(ax6);
set(tab6,'BackgroundColor',[0 0 0]);
hold(ax6,'on');

for k=1:numel(fitAngles)
    z=CamberCharacterization.SA_deg==fitAngles(k);
    scatter(ax6,CamberCharacterization.Camber_deg(z), ...
            CamberCharacterization.Mu_median(z), ...
            45,'DisplayName',sprintf('%d deg',fitAngles(k)));
end

styleBlackAxes(ax6);
grid(ax6,'on');
xlabel(ax6,'Camber / IA [deg]');
ylabel(ax6,'\mu_y');
title(ax6,'CMM Characterization — Camber Sensitivity');
lg6=legend(ax6,'Location','best');
styleBlackLegend(lg6);
exportgraphics(ax6,fullfile(outputFolder, ...
    '06_CAMBER_SENSITIVITY.png'),'Resolution',180);

% ------------------------------------------------------------
% 7. C-alpha method diagnostic — reference low-slip region
% ------------------------------------------------------------
tab7 = uitab(tabGroup,'Title','07 — C-alpha Diagnostic');
ax7 = axes('Parent',tab7,'Position',[0.08 0.10 0.88 0.84]);
styleBlackAxes(ax7);
set(tab7,'BackgroundColor',[0 0 0]);
hold(ax7,'on');

% Plot signed reference data only in the low-slip region.
zref = refMask & abs(SA)<=2.2;
scatter(ax7,SA(zref),FY(zref),12,'filled', ...
    'DisplayName','Reference samples');

xxfit = linspace(-2.2,2.2,200);
lineSpecs = {'--','-.',':'};
for m=1:3
    pp = polyfit(SA(refMask & abs(SA)>=calphaWindows(m,1) & ...
                    abs(SA)<=calphaWindows(m,2)), ...
                 FY(refMask & abs(SA)>=calphaWindows(m,1) & ...
                    abs(SA)<=calphaWindows(m,2)),1);
    yyfit = polyval(pp,xxfit);
    plot(ax7,xxfit,yyfit,lineSpecs{m},'LineWidth',1.5, ...
        'DisplayName',sprintf('%s: %.1f N/deg', ...
        calphaNames{m},CAlphaReference.Calpha_N_per_deg(m)));
end

styleBlackAxes(ax7);
grid(ax7,'on');
xlabel(ax7,'Signed slip angle, SA [deg]');
ylabel(ax7,'Signed lateral force, F_y [N]');
title(ax7,'CMM Characterization — Cornering Stiffness Window Diagnostic');
lg7=legend(ax7,'Location','best');
styleBlackLegend(lg7);
exportgraphics(ax7,fullfile(outputFolder, ...
    '07_CALPHA_METHOD_DIAGNOSTIC.png'),'Resolution',180);

drawnow;

%% ============================================================
% [14] AUDIT / SUMMARY
% =============================================================

fid=fopen(fullfile(outputFolder,'CHARACTERIZATION_REPORT_v1_3_2.txt'),'w');

fprintf(fid,'CMM TIRE CHARACTERIZATION v1.3.2\n');
fprintf(fid,'==============================================\n\n');

fprintf(fid,'INPUT\n');
fprintf(fid,'%s\n\n',inputFile);

fprintf(fid,'REFERENCE OPERATING POINT\n');
fprintf(fid,'Reference selection : FROZEN CMM CONTRACT; not auto-selected from data\n');
fprintf(fid,'Pressure : %.2f psi +/- %.2f psi\n', ...
    refPpsi,refPressureHalfWidth);
fprintf(fid,'Camber   : %.2f deg\n',refCamber);
fprintf(fid,'Fz       : %.1f +/- %.1f N\n\n', ...
    refFz,refLoadHalfWidth);

fprintf(fid,'REFERENCE CORNERING STIFFNESS\n');
fprintf(fid,'C-alpha  : %.4f N/deg\n',calphaRef);
fprintf(fid,'R2       : %.5f\n\n',calphaR2);

fprintf(fid,'REFERENCE MU AT FIXED SLIP ANGLES\n');
fprintf(fid,'8 deg    : %.5f\n',getScalar(ref8));
fprintf(fid,'10 deg   : %.5f\n',getScalar(ref10));
fprintf(fid,'12 deg   : %.5f\n\n',getScalar(ref12));

fprintf(fid,'IMPORTANT INTERPRETATION\n');
fprintf(fid,'Fixed-slip-angle characterization is the primary load-sensitivity\n');
fprintf(fid,'method because many TTC conditions are boundary-limited at high SA.\n');
fprintf(fid,'Observed values at the SA boundary are not treated as true tire peaks.\n');
fprintf(fid,'No Magic Formula coefficients are fitted in this stage.\n');

fclose(fid);

fprintf('\n============================================================\n');
fprintf(' CHARACTERIZATION v1.2 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Output: %s\n',outputFolder);
fprintf('C-alpha local 0-0.5 : %.3f N/deg (R2 %.4f)\n',calphaRef,calphaR2);
fprintf('C-alpha local 0-1.0 : %.3f N/deg (R2 %.4f)\n', ...
    CAlphaReference.Calpha_N_per_deg(2),CAlphaReference.R2(2));
fprintf('C-alpha broad 0.25-2 : %.3f N/deg (R2 %.4f)\n', ...
    CAlphaReference.Calpha_N_per_deg(3),CAlphaReference.R2(3));
fprintf('Reference mu @ 8  : %.4f\n',getScalar(ref8));
fprintf('Reference mu @ 10 : %.4f\n',getScalar(ref10));
fprintf('Reference mu @ 12 : %.4f\n',getScalar(ref12));
fprintf('MF fitting        : NOT PERFORMED\n');
fprintf('============================================================\n');

%% ============================================================
% LOCAL FUNCTIONS — MUST REMAIN AT END OF SCRIPT
% ============================================================

function chosen=pickVar(names,normNames,candidates)

chosen="";

for c=1:numel(candidates)

    target=lower(regexprep(candidates{c},'[^a-zA-Z0-9]',''));
    k=find(normNames==target,1);

    if ~isempty(k)
        chosen=names(k);
        return;
    end
end

for c=1:numel(candidates)

    target=lower(regexprep(candidates{c},'[^a-zA-Z0-9]',''));
    k=find(contains(normNames,target),1);

    if ~isempty(k)
        chosen=names(k);
        return;
    end
end

error('Required signal could not be auto-detected.');

end

function v=getScalar(x)

if isempty(x)
    v=NaN;
else
    v=x(1);
end

end



%% ============================================================

function styleBlackAxes(ax)

% Explicitly style the AXES, not only the surrounding figure.
% Works with uiaxes used inside the single-tabbed MATLAB window.
% This is the correction for the v1.2 white plotting-area issue.

ax.Color = [0 0 0];
ax.XColor = [1 1 1];
ax.YColor = [1 1 1];
ax.GridColor = [0.45 0.45 0.45];
ax.MinorGridColor = [0.30 0.30 0.30];
ax.GridAlpha = 0.35;
ax.MinorGridAlpha = 0.20;
ax.Box = 'on';

ax.Title.Color = [1 1 1];
ax.XLabel.Color = [1 1 1];
ax.YLabel.Color = [1 1 1];

end

function styleBlackLegend(lg)

if isempty(lg) || ~isvalid(lg)
    return;
end

try
    lg.Color = [0 0 0];
    lg.TextColor = [1 1 1];
    lg.EdgeColor = [0.45 0.45 0.45];
end

end
