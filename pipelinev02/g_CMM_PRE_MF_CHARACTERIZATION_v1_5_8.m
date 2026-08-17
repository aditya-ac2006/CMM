%% CMM PRE-MF LOAD-RESOLVED CHARACTERIZATION v1.5.8
% ROBUST PRE-MF AUDIT / REFERENCE-TIRE METRICS
%
% v1.5.8 is based on the v1.5.5 reduction logic.
%
% PURPOSE
% -------
% 1) Preserve the v1.5.5 raw-data reduction and peak-status logic.
% 2) Keep load-resolved, pressure-family and camber sensitivity.
% 3) Replace the ambiguous reference "median pointwise mu" as the main
%    engineering result with explicit peak-region tire metrics.
% 4) Report:
%       - diagnostic pointwise mu statistics
%       - peak-region mu
%       - peak Fy
%       - slip angle at peak Fy
%       - C-alpha
%       - Fy at 1,2,3,4,5,6 deg
%       - mu at 1,2,3,4,5,6 deg
% 5) Generate a clean reference Fy-alpha curve.
% 6) Generate a reference-metric CSV suitable for review before MF fitting.
% 7) Fix the v1.5.5 legend warning by using explicit graphics handles.
%
% IMPORTANT
% ---------
% - Raw TTC data is never modified on disk.
% - Fz is treated as measured positive load.
% - Fy sign is normalized only in memory using the established +SA audit.
% - Pointwise |Fy|/Fz remains a diagnostic quantity.
% - Peak-region mu is NOT a vehicle-level friction coefficient.
% - This script DOES NOT fit Magic Formula coefficients.
%
% INPUT
% -----
% _PRE_MF_MATRIX_v1_3\TTC_CONDITION_ASSIGNED_DATABASE.csv
%
% OUTPUT
% ------
% _PRE_MF_FINAL_v1_5_8\
%   MASTER_CHARACTERIZATION_v1_5_8.csv
%   REFERENCE_LOAD_CHARACTERIZATION_v1_5_8.csv
%   REFERENCE_FY_ALPHA_CURVE_v1_5_8.csv
%   LOAD_SENSITIVITY_v1_5_8.csv
%   PRESSURE_SENSITIVITY_v1_5_8.csv
%   CAMBER_SENSITIVITY_v1_5_8.csv
%   AUDIT_REPORT_v1_5_8.txt
%   01_LOAD_SENSITIVITY_v1_5_8.png
%   02_PRESSURE_SENSITIVITY_v1_5_8.png
%   03_CAMBER_SENSITIVITY_v1_5_8.png
%   04_PEAK_SLIP_ANGLE_v1_5_8.png
%   05_CALPHA_VS_LOAD_v1_5_8.png
%   06_PEAK_STATUS_v1_5_8.png
%   07_REFERENCE_FY_ALPHA_v1_5_8.png
%   08_REFERENCE_MU_ALPHA_v1_5_8.png

clear; clc; close all;

fprintf('\n============================================================\n');
fprintf(' CMM PRE-MF LOAD-RESOLVED CHARACTERIZATION v1.5.8\n');
fprintf(' REFERENCE TIRE METRICS / NO SPAGHETTI PLOTS\n');
fprintf('============================================================\n\n');

%% ============================================================
% [1] USER PATHS
% =============================================================

% Select the project/data location for the input database.
projectFolder = uigetdir(pwd,'Select CMM project/data folder');
if isequal(projectFolder,0)
    error('No project folder selected.');
end

thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));

inputFile = fullfile(projectFolder, ...
    '_PRE_MF_MATRIX_v1_3', 'TTC_CONDITION_ASSIGNED_DATABASE.csv');

outputFolder = fullfile(repoRoot,'outputs','10_PRE_MF_FINAL_v1_5_8');

if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end

fprintf('[1] INPUT\n%s\n\n',inputFile);

if ~isfile(inputFile)
    error('Input database not found:\n%s',inputFile);
end

%% ============================================================
% [2] LOAD DATABASE
% =============================================================

T = readtable(inputFile,'VariableNamingRule','preserve');

fprintf('[2] LOADED DATABASE\n');
fprintf('Rows      : %d\n',height(T));
fprintf('Variables : %d\n\n',width(T));

%% ============================================================
% [3] SIGNAL MAPPING
% =============================================================

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

fprintf('[3] SIGNAL MAPPING\n');
fprintf('SA : %s\n',sa);
fprintf('FY : %s\n',fy);
fprintf('FZ : %s\n',fz);
fprintf('IA : %s\n',ia);
fprintf('P  : %s\n\n',p);

SA   = double(T.(sa));
FY   = double(T.(fy));
FZ   = double(T.(fz));
IA   = double(T.(ia));
Praw = double(T.(p));

%% ============================================================
% [4] UNIT NORMALIZATION + QC
% =============================================================

Pmed = median(Praw,'omitnan');

if Pmed > 1000
    PkPa = Praw/1000;
elseif Pmed < 30
    PkPa = Praw*6.894757293;
else
    PkPa = Praw;
end

Ppsi = PkPa/6.894757293;

% Established v1.5.x convention: positive measured Fz.
FZ = abs(FZ);

valid = isfinite(SA) & isfinite(FY) & isfinite(FZ) & ...
        isfinite(IA) & isfinite(PkPa) & FZ > 0;

SA   = SA(valid);
FY   = FY(valid);
FZ   = FZ(valid);
IA   = IA(valid);
PkPa = PkPa(valid);
Ppsi = Ppsi(valid);

fprintf('[4] SIGNAL QC\n');
fprintf('Valid samples : %d\n',numel(SA));
fprintf('SA : %.3f -> %.3f deg\n',min(SA),max(SA));
fprintf('FY : %.2f -> %.2f N\n',min(FY),max(FY));
fprintf('FZ : %.2f -> %.2f N\n',min(FZ),max(FZ));
fprintf('IA : %.3f -> %.3f deg\n',min(IA),max(IA));
fprintf('P  : %.2f -> %.2f kPa\n\n',min(PkPa),max(PkPa));

%% ============================================================
% [5] FY SIGN NORMALIZATION
% =============================================================

pos = SA > 2;
neg = SA < -2;

if nnz(pos)>50 && nnz(neg)>50
    medPos = median(FY(pos),'omitnan');
    medNeg = median(FY(neg),'omitnan');
else
    medPos = NaN;
    medNeg = NaN;
end

if isfinite(medPos) && medPos < 0
    FY = -FY;
    signMultiplier = -1;
else
    signMultiplier = 1;
end

fprintf('[5] FY SIGN NORMALIZATION\n');
fprintf('Median raw Fy @ +SA : %.3f N\n',medPos);
fprintf('Median raw Fy @ -SA : %.3f N\n',medNeg);
fprintf('Applied multiplier  : %+.0f\n\n',signMultiplier);

%% ============================================================
% [5B] VEHICLE OPERATING LOADS
% =============================================================

refPpsi = 12.10;
refPkPa = refPpsi*6.894757293;
refIA   = 0;
refFz   = 871.5;

vehicleMassKg = 320.0;
vehicleWeightN = vehicleMassKg*9.80665;

frontWeightFraction = 0.60;
rearWeightFraction  = 0.40;

frontAxleStaticN = vehicleWeightN*frontWeightFraction;
rearAxleStaticN  = vehicleWeightN*rearWeightFraction;

frontTireStaticN = frontAxleStaticN/2;
rearTireStaticN  = rearAxleStaticN/2;

fprintf('[5B] VEHICLE OPERATING LOADS\n');
fprintf('Vehicle mass          : %.1f kg\n',vehicleMassKg);
fprintf('Vehicle weight        : %.1f N\n',vehicleWeightN);
fprintf('Static distribution   : %.0f / %.0f %% front/rear\n', ...
    100*frontWeightFraction,100*rearWeightFraction);
fprintf('Front axle / tire     : %.1f / %.1f N\n', ...
    frontAxleStaticN,frontTireStaticN);
fprintf('Rear axle / tire      : %.1f / %.1f N\n\n', ...
    rearAxleStaticN,rearTireStaticN);

%% ============================================================
% [6] REDUCTION CONSTANTS
% =============================================================

refLoadHalfWidth = 75;
refLoadMin = refFz-refLoadHalfWidth;
refLoadMax = refFz+refLoadHalfWidth;

refPHalfWidthPsi = 0.20;
refPMin = refPpsi-refPHalfWidthPsi;
refPMax = refPpsi+refPHalfWidthPsi;

camTol = 0.20;

alphaBin = 0.20;
minSamplesPeak = 25;
boundaryMargin = 0.60;
plateauSlopeFrac = 0.03;
peakWindow = 1.0;

minSamplesReduction = 100;
lowLoadCutoffN = 350;

pressureFamilyCentersPsi = [8 10 12 14];
pressureFamilyHalfWidthPsi = 0.45;

% Explicit engineering angles for reference characterization.
metricAnglesDeg = (1:12)';

fprintf('[6] CONDITION MATRIX\n');
fprintf('Pressure states : %d\n',numel(unique(round(PkPa/0.25)*0.25)));
fprintf('Camber states   : %d\n',numel(unique(round(IA/2)*2)));
fprintf('Reference load  : %.1f +/- %.1f N\n',refFz,refLoadHalfWidth);
fprintf('Reference P     : %.2f +/- %.2f psi\n\n',refPpsi,refPHalfWidthPsi);

%% ============================================================
% [7] MASTER CHARACTERIZATION
% =============================================================

Pstate  = round(PkPa/0.25)*0.25;
IAstate = round(IA/2)*2;

states = unique([Pstate IAstate],'rows');
nStates = size(states,1);

R = nan(nStates,12);
statusText = strings(nStates,1);

for k = 1:nStates

    pk = states(k,1);
    ik = states(k,2);

    idx = Pstate == pk & abs(IAstate-ik) < 0.5;

    if nnz(idx) < minSamplesPeak
        continue;
    end

    m = analyzeSubset(SA(idx),FY(idx),FZ(idx), ...
        alphaBin,minSamplesPeak,boundaryMargin, ...
        plateauSlopeFrac,peakWindow);

    R(k,:) = [ ...
        pk/6.894757293, ...
        ik, ...
        m.fzMedian, ...
        m.muPeak, ...
        m.fyPeak, ...
        m.peakSA, ...
        m.Calpha, ...
        m.R2, ...
        double(m.n), ...
        m.nPeak, ...
        m.boundaryFraction, ...
        double(m.valid)];

    statusText(k) = m.status;
end

Master = table( ...
    R(:,1),R(:,2),R(:,3),R(:,4),R(:,5),R(:,6), ...
    R(:,7),R(:,8),R(:,9),R(:,10),R(:,11),statusText, ...
    'VariableNames', ...
    {'Pressure_psi','Camber_deg','Fz_N','mu_peak', ...
     'Fy_peak_N','ObservedSA_deg','Calpha_N_per_deg','Calpha_R2', ...
     'N_total','N_peak','BoundaryFraction','PeakStatus'});

Master = Master(isfinite(Master.Pressure_psi) & ...
                strlength(Master.PeakStatus)>0,:);

writetable(Master,fullfile(outputFolder, ...
    'MASTER_CHARACTERIZATION_v1_5_8.csv'));

fprintf('[7] MASTER CHARACTERIZATION\n');
fprintf('Rows : %d\n\n',height(Master));

%% ============================================================
% [8] REFERENCE OPERATING WINDOW
% =============================================================

refMask = Ppsi >= refPMin & Ppsi <= refPMax & ...
          abs(IA-refIA) <= camTol & ...
          FZ >= refLoadMin & FZ <= refLoadMax;

refSA = SA(refMask);
refFY = FY(refMask);
refFZ = FZ(refMask);

if isempty(refSA)
    error('Reference operating window contains no valid samples.');
end

muPoint = abs(refFY)./refFZ;

% Peak-region metric from the aggregate reference curve.
refMetric = analyzeSubset(refSA,refFY,refFZ, ...
    alphaBin,minSamplesPeak,boundaryMargin, ...
    plateauSlopeFrac,peakWindow);

% Explicit Fy and mu at engineering slip angles.
FyAtAngle = nan(numel(metricAnglesDeg),1);
MuAtAngle = nan(numel(metricAnglesDeg),1);
NAtAngle  = zeros(numel(metricAnglesDeg),1);

for j = 1:numel(metricAnglesDeg)

    a0 = metricAnglesDeg(j);

    % +/- angle band. Width is deliberately small but not infinitesimal.
    band = abs(abs(refSA)-a0) <= max(alphaBin,0.10);

    if nnz(band) >= 10
        FyAtAngle(j) = median(abs(refFY(band)),'omitnan');
        MuAtAngle(j) = median(abs(refFY(band))./refFZ(band),'omitnan');
        NAtAngle(j)  = nnz(band);
    end
end

fprintf('[8] REFERENCE OPERATING WINDOW\n');
fprintf('Pressure : %.2f +/- %.2f psi\n',refPpsi,refPHalfWidthPsi);
fprintf('Camber   : %.1f deg\n',refIA);
fprintf('Fz       : %.1f +/- %.1f N\n',refFz,refLoadHalfWidth);
fprintf('Samples  : %d\n',numel(refSA));

fprintf('\nDIAGNOSTIC POINTWISE mu = |Fy|/Fz\n');
fprintf('Median : %.4f\n',median(muPoint,'omitnan'));
fprintf('P10/P90 : %.4f / %.4f\n', ...
    prctile(muPoint,10),prctile(muPoint,90));

fprintf('\nENGINEERING REFERENCE METRICS\n');
fprintf('Observed Fy         : %.2f N\n',refMetric.fyPeak);
fprintf('Observed mu         : %.4f\n',refMetric.muPeak);
fprintf('Observed SA         : %.3f deg\n',refMetric.peakSA);
fprintf('C-alpha             : %.3f N/deg\n',refMetric.Calpha);
fprintf('C-alpha R2          : %.5f\n',refMetric.R2);
fprintf('Peak status         : %s\n',refMetric.status);
if refMetric.status == "BOUNDARY-LIMITED"
    fprintf('Peak identification : NOT POSSIBLE within measured SA range\n');
    fprintf('Interpretation      : observed Fy/mu at maximum usable SA, not true peak\n');
elseif refMetric.status == "NEAR-PLATEAU"
    fprintf('Peak identification : NEAR-PLATEAU within measured SA range\n');
else
    fprintf('Peak identification : RESOLVED within measured SA range\n');
end
fprintf('\n');

%% SAVE REFERENCE CHARACTERIZATION TABLE

Reference = table( ...
    refPpsi,refIA,refFz,refLoadHalfWidth, ...
    numel(refSA), ...
    median(muPoint,'omitnan'), ...
    prctile(muPoint,10), ...
    prctile(muPoint,90), ...
    refMetric.fyPeak, ...
    refMetric.muPeak, ...
    refMetric.peakSA, ...
    refMetric.Calpha, ...
    refMetric.R2, ...
    string(refMetric.status), ...
    string(referencePeakLabel(refMetric.status)), ...
    'VariableNames', ...
    {'Pressure_psi','Camber_deg','TargetFz_N','FzHalfWidth_N', ...
     'N_samples','PointwiseMu_Median','PointwiseMu_P10', ...
     'PointwiseMu_P90','ObservedFy_N','ObservedMu', ...
     'ObservedSA_deg','Calpha_N_per_deg','Calpha_R2','PeakStatus','PeakInterpretation'});

writetable(Reference,fullfile(outputFolder, ...
    'REFERENCE_LOAD_CHARACTERIZATION_v1_5_8.csv'));

%% SAVE REFERENCE ANGLE METRICS

ReferenceAngles = table( ...
    metricAnglesDeg,FyAtAngle,MuAtAngle,NAtAngle, ...
    'VariableNames', ...
    {'SlipAngle_deg','Fy_abs_N','Mu_abs','N_samples'});

writetable(ReferenceAngles,fullfile(outputFolder, ...
    'REFERENCE_FY_ALPHA_METRICS_v1_5_8.csv'));

%% BUILD CLEAN REFERENCE CURVE

[curveA,curveFy,curveFz,curveN] = buildReferenceCurve( ...
    refSA,refFY,refFZ,alphaBin);

curveMu = curveFy ./ max(curveFz,eps);

ReferenceCurve = table( ...
    curveA,curveFy,curveFz,curveMu,curveN, ...
    'VariableNames', ...
    {'AbsSA_deg','Fy_abs_N','Fz_median_N','Mu_y','N_samples'});

writetable(ReferenceCurve,fullfile(outputFolder, ...
    'REFERENCE_FY_ALPHA_CURVE_v1_5_8.csv'));

%% ============================================================
% REFERENCE PEAK ASSESSMENT
% =============================================================

maxMeasuredSA = max(abs(refSA));
maxSA_band = abs(refSA) >= maxMeasuredSA - 0.15;
maxMeasuredFy = median(abs(refFY(maxSA_band)),'omitnan');
maxMeasuredMu = median(abs(refFY(maxSA_band))./refFZ(maxSA_band),'omitnan');

PeakAssessment = table( ...
    refPpsi,refIA,refFz,maxMeasuredSA,maxMeasuredFy,maxMeasuredMu, ...
    refMetric.fyPeak,refMetric.muPeak,refMetric.peakSA, ...
    string(refMetric.status),string(referencePeakLabel(refMetric.status)), ...
    'VariableNames', ...
    {'Pressure_psi','Camber_deg','TargetFz_N','MaxMeasuredSA_deg', ...
     'ObservedFyAtMaxSA_N','ObservedMuAtMaxSA','DetectedFy_N', ...
     'DetectedMu','DetectedSA_deg','Status','Interpretation'});

writetable(PeakAssessment,fullfile(outputFolder, ...
    'REFERENCE_PEAK_ASSESSMENT_v1_5_8.csv'));

%% ============================================================
% [9] LOAD SENSITIVITY
% =============================================================

loadEdges = [150 250 350 450 550 650 750 825 925 1025 1125 1210];
loadCenters = (loadEdges(1:end-1)+loadEdges(2:end))/2;

loadMu = nan(numel(loadCenters),1);
loadFy = nan(numel(loadCenters),1);
loadFz = nan(numel(loadCenters),1);
loadSA = nan(numel(loadCenters),1);
loadN = zeros(numel(loadCenters),1);
loadStatus = strings(numel(loadCenters),1);
loadCa = nan(numel(loadCenters),1);
loadFitEligible = false(numel(loadCenters),1);
loadPeakUsable = false(numel(loadCenters),1);
loadBoundaryLimited = false(numel(loadCenters),1);
loadAuditFlag = strings(numel(loadCenters),1);

idxBase = Ppsi >= refPMin & Ppsi <= refPMax & ...
          abs(IA-refIA) <= camTol;

for b = 1:numel(loadCenters)

    idx = idxBase & FZ >= loadEdges(b) & FZ < loadEdges(b+1);

    if nnz(idx) < minSamplesReduction
        loadStatus(b) = "UNRESOLVED";
        loadAuditFlag(b) = "INSUFFICIENT-SAMPLES";
        continue;
    end

    m = analyzeSubset(SA(idx),FY(idx),FZ(idx), ...
        alphaBin,minSamplesPeak,boundaryMargin, ...
        plateauSlopeFrac,peakWindow);

    loadFz(b) = median(FZ(idx),'omitnan');
    loadFy(b) = m.fyPeak;
    loadSA(b) = m.peakSA;
    loadCa(b) = m.Calpha;
    loadN(b) = nnz(idx);
    loadStatus(b) = m.status;

    mu = abs(FY(idx))./FZ(idx);
    a = abs(SA(idx));

    if isfinite(m.peakSA)
        pk = a >= max(0,m.peakSA-peakWindow) & ...
             a <= m.peakSA+peakWindow;

        if nnz(pk)>=10
            loadMu(b) = median(mu(pk),'omitnan');
        end
    end

    if loadFz(b) < lowLoadCutoffN
        loadAuditFlag(b) = "LOW-LOAD-REVIEW";
    elseif loadStatus(b)=="RESOLVED" && isfinite(loadMu(b))
        loadFitEligible(b) = true;
        loadPeakUsable(b) = true;
        loadAuditFlag(b) = "CONFIRMED-PEAK";
    elseif loadStatus(b)=="NEAR-PLATEAU" && isfinite(loadMu(b))
        loadPeakUsable(b) = true;
        loadAuditFlag(b) = "NEAR-PLATEAU";
    elseif loadStatus(b)=="BOUNDARY-LIMITED" && isfinite(loadMu(b))
        loadBoundaryLimited(b) = true;
        loadAuditFlag(b) = "BOUNDARY-LIMITED";
    else
        loadAuditFlag(b) = "REVIEW";
    end
end

LoadSens = table( ...
    loadFz,loadMu,loadFy,loadSA,loadCa,loadN, ...
    loadStatus,loadFitEligible,loadPeakUsable,loadBoundaryLimited,loadAuditFlag, ...
    'VariableNames', ...
    {'Fz_N','mu_observed_peak_region','Fy_observed_N', ...
     'ObservedSA_deg','Calpha_N_per_deg','N','Status', ...
     'ConfirmedPeakFitEligible','PeakUsable','BoundaryLimited','AuditFlag'});

writetable(LoadSens,fullfile(outputFolder, ...
    'LOAD_SENSITIVITY_v1_5_8.csv'));

%% ============================================================
% [10] PRESSURE FAMILY SENSITIVITY
% =============================================================

pCenters = pressureFamilyCentersPsi(:);

pmu = nan(size(pCenters));
pFz = nan(size(pCenters));
pSA = nan(size(pCenters));
pCa = nan(size(pCenters));
pN = zeros(size(pCenters));
pStatus = strings(size(pCenters));
pAudit = strings(size(pCenters));

for j = 1:numel(pCenters)

    idx = abs(Ppsi-pCenters(j)) <= pressureFamilyHalfWidthPsi & ...
          abs(IA-refIA) <= camTol & ...
          FZ >= refLoadMin & FZ <= refLoadMax;

    if nnz(idx)<minSamplesReduction
        pStatus(j)="UNRESOLVED";
        pAudit(j)="INSUFFICIENT-SAMPLES";
        continue;
    end

    m = analyzeSubset(SA(idx),FY(idx),FZ(idx), ...
        alphaBin,minSamplesPeak,boundaryMargin, ...
        plateauSlopeFrac,peakWindow);

    pFz(j)=median(FZ(idx),'omitnan');
    pSA(j)=m.peakSA;
    pCa(j)=m.Calpha;
    pN(j)=nnz(idx);
    pStatus(j)=m.status;

    mu = abs(FY(idx))./FZ(idx);
    a = abs(SA(idx));

    if isfinite(m.peakSA)

        pk = a >= max(0,m.peakSA-peakWindow) & ...
             a <= m.peakSA+peakWindow;

        if nnz(pk)>=10
            pmu(j)=median(mu(pk),'omitnan');
        end
    end

    if m.status=="RESOLVED"
        pAudit(j)="FIT-ELIGIBLE";
    elseif m.status=="NEAR-PLATEAU"
        pAudit(j)="NEAR-PLATEAU-RETAINED";
    elseif m.status=="BOUNDARY-LIMITED"
        pAudit(j)="BOUNDARY-LIMITED";
    else
        pAudit(j)="REVIEW";
    end
end

PressureSens = table( ...
    pCenters,pFz,pmu,pSA,pCa,pN,pStatus,pAudit, ...
    'VariableNames', ...
    {'Pressure_psi','Fz_N','mu_observed_peak_region', ...
     'ObservedSA_deg','Calpha_N_per_deg','N','PeakStatus','AuditFlag'});

writetable(PressureSens,fullfile(outputFolder, ...
    'PRESSURE_SENSITIVITY_v1_5_8.csv'));

%% ============================================================
% [11] CAMBER SENSITIVITY
% =============================================================

iStates = unique(IAstate);

imu = nan(size(iStates));
iFz = nan(size(iStates));
iSA = nan(size(iStates));
iCa = nan(size(iStates));
iN = zeros(size(iStates));
iStatus = strings(size(iStates));

for j = 1:numel(iStates)

    idx = Ppsi >= refPMin & Ppsi <= refPMax & ...
          abs(IAstate-iStates(j)) < 0.5 & ...
          FZ >= refLoadMin & FZ <= refLoadMax;

    if nnz(idx)<minSamplesPeak
        iStatus(j)="UNRESOLVED";
        continue;
    end

    m = analyzeSubset(SA(idx),FY(idx),FZ(idx), ...
        alphaBin,minSamplesPeak,boundaryMargin, ...
        plateauSlopeFrac,peakWindow);

    iFz(j)=median(FZ(idx),'omitnan');
    iSA(j)=m.peakSA;
    iCa(j)=m.Calpha;
    iN(j)=nnz(idx);
    iStatus(j)=m.status;

    mu = abs(FY(idx))./FZ(idx);
    a = abs(SA(idx));

    if isfinite(m.peakSA)

        pk = a >= max(0,m.peakSA-peakWindow) & ...
             a <= m.peakSA+peakWindow;

        if nnz(pk)>=10
            imu(j)=median(mu(pk),'omitnan');
        end
    end
end

CamberSens = table( ...
    iStates,iFz,imu,iSA,iCa,iN,iStatus, ...
    'VariableNames', ...
    {'Camber_deg','Fz_N','mu_observed_peak_region', ...
     'ObservedSA_deg','Calpha_N_per_deg','N','PeakStatus'});

writetable(CamberSens,fullfile(outputFolder, ...
    'CAMBER_SENSITIVITY_v1_5_8.csv'));

%% ============================================================
% [12] ENGINEERING PLOTS
% =============================================================

fprintf('[12] GENERATING ENGINEERING PLOTS\n');

% ------------------------------------------------------------
% A. Load sensitivity
% ------------------------------------------------------------

f = figure('Color','w','Name','v1.5.8 Load Sensitivity');
set(f,'Toolbar','none');
hold on;

ok = LoadSens.ConfirmedPeakFitEligible & ...
     isfinite(LoadSens.Fz_N) & ...
     isfinite(LoadSens.mu_observed_peak_region);

h1 = plot(LoadSens.Fz_N(ok), ...
          LoadSens.mu_observed_peak_region(ok), ...
          'o-','LineWidth',1.7,'MarkerSize',7);

rej = ~ok & isfinite(LoadSens.Fz_N) & ...
            isfinite(LoadSens.mu_observed_peak_region);

h2 = scatter(LoadSens.Fz_N(rej), ...
             LoadSens.mu_observed_peak_region(rej), ...
             45,'x');

h3 = xline(frontTireStaticN,'--','Front static tire load','LineWidth',1.2);
h4 = xline(rearTireStaticN,'--','Rear static tire load','LineWidth',1.2);

grid on;
xlabel('F_z [N]');
ylabel('\mu_y, observed peak-region');
title(sprintf('v1.5.8 — Load Sensitivity | %.2f psi / %.1f deg camber', ...
    refPpsi,refIA));

legHandles = [h1 h2 h3 h4];
legLabels = {'Confirmed-peak trend','Retained boundary/review points', ...
             'Front static tire load','Rear static tire load'};
validLeg = isgraphics(legHandles);
legend(legHandles(validLeg),legLabels(validLeg),'Location','best');

exportgraphics(f,fullfile(outputFolder, ...
    '01_LOAD_SENSITIVITY_v1_5_8.png'),'Resolution',180);
close(f);

% ------------------------------------------------------------
% B. Pressure sensitivity
% ------------------------------------------------------------

f = figure('Color','w','Name','v1.5.8 Pressure Sensitivity');
set(f,'Toolbar','none');

ok = isfinite(PressureSens.Pressure_psi) & ...
     isfinite(PressureSens.mu_observed_peak_region);

scatter(PressureSens.Pressure_psi(ok), ...
        PressureSens.mu_observed_peak_region(ok), ...
        65,'o','LineWidth',1.5);
% Discrete measured pressure families; no connecting line.

grid on;
xlabel('Pressure [psi]');
ylabel('\mu_y, observed peak-region');
title(sprintf('v1.5.8 — Pressure Family Sensitivity | F_z %.0f\\pm%.0f N / %.1f deg camber', ...
    refFz,refLoadHalfWidth,refIA));

exportgraphics(f,fullfile(outputFolder, ...
    '02_PRESSURE_SENSITIVITY_v1_5_8.png'),'Resolution',180);
close(f);

% ------------------------------------------------------------
% C. Camber sensitivity
% ------------------------------------------------------------

f = figure('Color','w','Name','v1.5.8 Camber Sensitivity');
set(f,'Toolbar','none');

ok = isfinite(CamberSens.Camber_deg) & ...
     isfinite(CamberSens.mu_observed_peak_region);

scatter(CamberSens.Camber_deg(ok), ...
        CamberSens.mu_observed_peak_region(ok), ...
        65,'o','LineWidth',1.5);
% Discrete measured camber states; no connecting line.

grid on;
xlabel('Camber [deg]');
ylabel('\mu_y, observed peak-region');
title(sprintf('v1.5.8 — Camber Sensitivity | %.2f psi / F_z %.0f\\pm%.0f N', ...
    refPpsi,refFz,refLoadHalfWidth));

exportgraphics(f,fullfile(outputFolder, ...
    '03_CAMBER_SENSITIVITY_v1_5_8.png'),'Resolution',180);
close(f);

% ------------------------------------------------------------
% D. Peak slip angle vs load
% ------------------------------------------------------------

f = figure('Color','w','Name','v1.5.8 Peak Slip Angle');
set(f,'Toolbar','none');

ok = isfinite(LoadSens.Fz_N) & ...
     isfinite(LoadSens.ObservedSA_deg);

hold on;

% Independent load bins are not a continuous load sweep.
% Status-coded scatter prevents false interpolation between bins.
st = string(LoadSens.Status);

hResolved = scatter(LoadSens.Fz_N(ok & st=="RESOLVED"), ...
    LoadSens.ObservedSA_deg(ok & st=="RESOLVED"), ...
    60,'o','LineWidth',1.2);

hNear = scatter(LoadSens.Fz_N(ok & st=="NEAR-PLATEAU"), ...
    LoadSens.ObservedSA_deg(ok & st=="NEAR-PLATEAU"), ...
    70,'s','LineWidth',1.2);

hBoundary = scatter(LoadSens.Fz_N(ok & st=="BOUNDARY-LIMITED"), ...
    LoadSens.ObservedSA_deg(ok & st=="BOUNDARY-LIMITED"), ...
    75,'^','LineWidth',1.2);

h = yline(max(abs(SA))*0.95,'--', ...
    'Near test-window boundary','LineWidth',1.0);

grid on;
xlabel('F_z [N]');
ylabel('Observed high-slip |\alpha| [deg]');
title(sprintf('v1.5.8 — Observed High-Slip Angle vs Load | %.2f psi / %.1f deg', ...
    refPpsi,refIA));

legH = [hResolved hNear hBoundary h];
legL = {'RESOLVED','NEAR-PLATEAU','BOUNDARY-LIMITED', ...
        'Near test-window boundary'};
goodL = isgraphics(legH);
legend(legH(goodL),legL(goodL),'Location','best');

exportgraphics(f,fullfile(outputFolder, ...
    '04_PEAK_SLIP_ANGLE_v1_5_8.png'),'Resolution',180);
close(f);

% ------------------------------------------------------------
% E. C-alpha vs load
% ------------------------------------------------------------

f = figure('Color','w','Name','v1.5.8 C Alpha');
set(f,'Toolbar','none');

ok = isfinite(LoadSens.Fz_N) & ...
     isfinite(LoadSens.Calpha_N_per_deg);

h1 = scatter(LoadSens.Fz_N(ok), ...
             LoadSens.Calpha_N_per_deg(ok), ...
             65,'o','LineWidth',1.3);

hold on;

h2 = xline(frontTireStaticN,'--', ...
    'Front static load','LineWidth',1.0);

h3 = xline(rearTireStaticN,'--', ...
    'Rear static load','LineWidth',1.0);

grid on;
xlabel('F_z [N]');
ylabel('C_\alpha [N/deg]');
title(sprintf('v1.5.8 — Reference-Window C_\alpha vs Load | %.2f psi / %.1f deg', ...
    refPpsi,refIA));

legend([h1 h2 h3], ...
    {'Reference-window load bins','Front static load','Rear static load'}, ...
    'Location','best');

exportgraphics(f,fullfile(outputFolder, ...
    '05_CALPHA_VS_LOAD_v1_5_8.png'),'Resolution',180);
close(f);

% ------------------------------------------------------------
% F. Peak status scatter
% ------------------------------------------------------------

f = figure('Color','w','Name','v1.5.8 Peak Status');
set(f,'Toolbar','none');
hold on;

statusList = ["RESOLVED","NEAR-PLATEAU", ...
              "BOUNDARY-LIMITED","REVIEW","UNRESOLVED"];

markers = {'o','s','^','d','x'};
handles = gobjects(numel(statusList),1);
labels = strings(numel(statusList),1);

for ss = 1:numel(statusList)

    ok = Master.PeakStatus == statusList(ss);

    if any(ok)
        handles(ss) = scatter( ...
            Master.Pressure_psi(ok), ...
            Master.Camber_deg(ok), ...
            45,markers{ss},'LineWidth',1.0);
        labels(ss) = statusList(ss);
    else
        handles(ss) = gobjects(1);
        labels(ss) = "";
    end
end

grid on;
xlabel('Pressure [psi]');
ylabel('Camber [deg]');
title('v1.5.8 — Peak Resolution Status');

goodLegend = isgraphics(handles);
legend(handles(goodLegend),labels(goodLegend), ...
    'Location','best');

exportgraphics(f,fullfile(outputFolder, ...
    '06_PEAK_STATUS_v1_5_8.png'),'Resolution',180);
close(f);

% ------------------------------------------------------------
% G. Reference Fy-alpha curve
% ------------------------------------------------------------

f = figure('Color','w','Name','v1.5.8 Reference Fy Alpha');
set(f,'Toolbar','none');

plot(curveA,curveFy,'o-','LineWidth',1.8,'MarkerSize',5);
hold on;

for j=1:numel(metricAnglesDeg)
    if isfinite(FyAtAngle(j))
        plot(metricAnglesDeg(j),FyAtAngle(j),'s','MarkerSize',6);
    end
end

if isfinite(refMetric.peakSA) && isfinite(refMetric.fyPeak)
    plot(refMetric.peakSA,refMetric.fyPeak,'d','MarkerSize',8);
end

grid on;
xlabel('|\alpha| [deg]');
ylabel('|F_y| [N]');
title(sprintf('v1.5.8 — Reference Tire | %.2f psi / %.1f deg camber / F_z %.0f\\pm%.0f N', ...
    refPpsi,refIA,refFz,refLoadHalfWidth));

exportgraphics(f,fullfile(outputFolder, ...
    '07_REFERENCE_FY_ALPHA_v1_5_8.png'),'Resolution',180);
close(f);

% ------------------------------------------------------------
% H. Reference mu-alpha curve
% ------------------------------------------------------------

f = figure('Color','w','Name','v1.5.8 Reference Mu Alpha');
set(f,'Toolbar','none');

plot(curveA,curveMu,'o-','LineWidth',1.8,'MarkerSize',5);
hold on;

if isfinite(refMetric.peakSA) && isfinite(refMetric.muPeak)
    plot(refMetric.peakSA,refMetric.muPeak,'d','MarkerSize',8);
end

grid on;
xlabel('|\alpha| [deg]');
ylabel('\mu_y = |F_y|/F_z');
title(sprintf('v1.5.8 — Reference Tire Normalized Curve | %.2f psi / %.1f deg', ...
    refPpsi,refIA));

exportgraphics(f,fullfile(outputFolder, ...
    '08_REFERENCE_MU_ALPHA_v1_5_8.png'),'Resolution',180);
close(f);

%% ============================================================
% [13] QUALITY SUMMARY
% =============================================================

resolved = sum(Master.PeakStatus=="RESOLVED");
nearplat = sum(Master.PeakStatus=="NEAR-PLATEAU");
boundary = sum(Master.PeakStatus=="BOUNDARY-LIMITED");
review   = sum(Master.PeakStatus=="REVIEW");
unres    = sum(Master.PeakStatus=="UNRESOLVED");

ca = Master.Calpha_N_per_deg(isfinite(Master.Calpha_N_per_deg));
mu = Master.mu_peak(isfinite(Master.mu_peak));

fitLoadCount = sum(LoadSens.ConfirmedPeakFitEligible & ...
    isfinite(LoadSens.mu_observed_peak_region));
peakUsableLoadCount = sum(LoadSens.PeakUsable & ...
    isfinite(LoadSens.mu_observed_peak_region));
boundaryLoadCount = sum(LoadSens.BoundaryLimited & ...
    isfinite(LoadSens.mu_observed_peak_region));

frontMask = idxBase & ...
    abs(FZ-frontTireStaticN)<=75;

rearMask = idxBase & ...
    abs(FZ-rearTireStaticN)<=75;

frontSamples = nnz(frontMask);
rearSamples = nnz(rearMask);

fprintf('\n============================================================\n');
fprintf('[13] QUALITY SUMMARY\n');
fprintf('============================================================\n');

fprintf('Master characterization rows : %d\n',height(Master));
fprintf('Resolved peaks               : %d\n',resolved);
fprintf('Near-plateau peaks           : %d\n',nearplat);
fprintf('Boundary-limited peaks       : %d\n',boundary);
fprintf('Review peaks                 : %d\n',review);
fprintf('Unresolved peaks             : %d\n',unres);

if ~isempty(ca)
    fprintf('\nC-alpha MASTER (all pressure/camber states)\n');
    fprintf('Median                       : %.3f N/deg\n',median(ca));
    fprintf('Range                        : %.3f -> %.3f N/deg\n',min(ca),max(ca));
end

caRef = LoadSens.Calpha_N_per_deg(isfinite(LoadSens.Calpha_N_per_deg));
if ~isempty(caRef)
    fprintf('\nC-alpha REFERENCE-WINDOW load sweep\n');
    fprintf('Median                       : %.3f N/deg\n',median(caRef));
    fprintf('Range                        : %.3f -> %.3f N/deg\n',min(caRef),max(caRef));
end

if ~isempty(mu)
    fprintf('\nMaster peak mu median        : %.4f\n',median(mu));
    fprintf('Master peak mu P90           : %.4f\n',prctile(mu,90));
    fprintf('Master peak mu max           : %.4f\n',max(mu));
end

fprintf('\nREFERENCE METRICS\n');
fprintf('Diagnostic pointwise mu med  : %.4f\n',median(muPoint,'omitnan'));
fprintf('Diagnostic pointwise P10/P90 : %.4f / %.4f\n', ...
    prctile(muPoint,10),prctile(muPoint,90));
fprintf('Observed Fy                 : %.2f N\n',refMetric.fyPeak);
fprintf('Observed mu                 : %.4f\n',refMetric.muPeak);
fprintf('Observed high-slip SA       : %.3f deg\n',refMetric.peakSA);
fprintf('C-alpha                      : %.3f N/deg\n',refMetric.Calpha);
fprintf('C-alpha R2                   : %.5f\n',refMetric.R2);
fprintf('Peak status                  : %s\n',refMetric.status);

fprintf('\nVEHICLE LOAD COVERAGE\n');
fprintf('Front static tire load       : %.1f N | samples +/-75 N: %d\n', ...
    frontTireStaticN,frontSamples);
fprintf('Rear static tire load        : %.1f N | samples +/-75 N: %d\n', ...
    rearTireStaticN,rearSamples);

fprintf('\nCONFIRMED peak load bins    : %d\n',fitLoadCount);
fprintf('Peak-usable load bins       : %d\n',peakUsableLoadCount);
fprintf('Boundary-limited load bins  : %d\n',boundaryLoadCount);

%% ============================================================
% [14] AUDIT REPORT
% =============================================================

reportFile = fullfile(outputFolder,'AUDIT_REPORT_v1_5_8.txt');

fid = fopen(reportFile,'w');

if fid < 0
    warning('Could not create audit report: %s',reportFile);
else

    fprintf(fid,'============================================================\n');
    fprintf(fid,' CMM PRE-MF LOAD-RESOLVED CHARACTERIZATION v1.5.8\n');
    fprintf(fid,' REFERENCE TIRE METRICS / PRE-MF AUDIT\n');
    fprintf(fid,'============================================================\n\n');

    fprintf(fid,'INPUT\n%s\n\n',inputFile);

    fprintf(fid,'DATA\n');
    fprintf(fid,'Valid raw samples : %d\n',numel(SA));
    fprintf(fid,'SA range          : %.3f -> %.3f deg\n',min(SA),max(SA));
    fprintf(fid,'Fy range          : %.2f -> %.2f N\n',min(FY),max(FY));
    fprintf(fid,'Fz range          : %.2f -> %.2f N\n',min(FZ),max(FZ));
    fprintf(fid,'IA range          : %.3f -> %.3f deg\n',min(IA),max(IA));
    fprintf(fid,'Pressure range    : %.2f -> %.2f kPa\n\n',min(PkPa),max(PkPa));

    fprintf(fid,'FY SIGN NORMALIZATION\n');
    fprintf(fid,'Median raw Fy @ +SA : %.3f N\n',medPos);
    fprintf(fid,'Median raw Fy @ -SA : %.3f N\n',medNeg);
    fprintf(fid,'Applied multiplier  : %+.0f\n\n',signMultiplier);

    fprintf(fid,'VEHICLE OPERATING LOADS\n');
    fprintf(fid,'Vehicle mass        : %.1f kg\n',vehicleMassKg);
    fprintf(fid,'Vehicle weight      : %.1f N\n',vehicleWeightN);
    fprintf(fid,'Front tire static   : %.1f N\n',frontTireStaticN);
    fprintf(fid,'Rear tire static    : %.1f N\n\n',rearTireStaticN);

    fprintf(fid,'REFERENCE WINDOW\n');
    fprintf(fid,'Pressure           : %.2f +/- %.2f psi\n',refPpsi,refPHalfWidthPsi);
    fprintf(fid,'Camber             : %.1f deg\n',refIA);
    fprintf(fid,'Fz                 : %.1f +/- %.1f N\n',refFz,refLoadHalfWidth);
    fprintf(fid,'Samples            : %d\n\n',numel(refSA));

    fprintf(fid,'REFERENCE DIAGNOSTIC POINTWISE MU\n');
    fprintf(fid,'Median             : %.4f\n',median(muPoint,'omitnan'));
    fprintf(fid,'P10 / P90          : %.4f / %.4f\n', ...
        prctile(muPoint,10),prctile(muPoint,90));
    fprintf(fid,'NOTE: pointwise |Fy|/Fz is diagnostic and is NOT used as a\n');
    fprintf(fid,'vehicle-level friction coefficient.\n\n');

    fprintf(fid,'C-ALPHA POPULATION DEFINITIONS\n');
    fprintf(fid,'MASTER C-alpha statistics use all valid pressure/camber master states.\n');
    fprintf(fid,'Reference-window C-alpha statistics use the 12.10 psi / 0 deg / load-window sweep.\n');
    if ~isempty(ca)
        fprintf(fid,'Master C-alpha median       : %.4f N/deg\n',median(ca));
        fprintf(fid,'Master C-alpha range        : %.4f -> %.4f N/deg\n',min(ca),max(ca));
    end
    if ~isempty(caRef)
        fprintf(fid,'Reference-window median     : %.4f N/deg\n',median(caRef));
        fprintf(fid,'Reference-window range      : %.4f -> %.4f N/deg\n',min(caRef),max(caRef));
    end
    fprintf(fid,'\n');

    fprintf(fid,'REFERENCE ENGINEERING METRICS\n');
    fprintf(fid,'Observed Fy        : %.3f N\n',refMetric.fyPeak);
    fprintf(fid,'Observed mu        : %.5f\n',refMetric.muPeak);
    fprintf(fid,'Observed high-slip SA : %.4f deg\n',refMetric.peakSA);
    fprintf(fid,'C-alpha            : %.4f N/deg\n',refMetric.Calpha);
    fprintf(fid,'C-alpha R2         : %.6f\n',refMetric.R2);
    fprintf(fid,'Peak status        : %s\n\n',refMetric.status);

    fprintf(fid,'REFERENCE PEAK ASSESSMENT\n');
    fprintf(fid,'Maximum measured |SA|     : %.3f deg\n',maxMeasuredSA);
    fprintf(fid,'Observed Fy near max SA   : %.3f N\n',maxMeasuredFy);
    fprintf(fid,'Observed mu near max SA   : %.5f\n',maxMeasuredMu);
    if refMetric.status == "BOUNDARY-LIMITED"
        fprintf(fid,'Peak identification       : NOT POSSIBLE within measured SA range.\n');
        fprintf(fid,'The reported observed Fy/mu are NOT a true tire peak.\n');
        fprintf(fid,'Force had not plateaued before the available SA boundary.\n');
    elseif refMetric.status == "NEAR-PLATEAU"
        fprintf(fid,'Peak identification       : NEAR-PLATEAU within measured SA range.\n');
    elseif refMetric.status == "RESOLVED"
        fprintf(fid,'Peak identification       : RESOLVED within measured SA range.\n');
    else
        fprintf(fid,'Peak identification       : NOT RELIABLY IDENTIFIED.\n');
    end
    fprintf(fid,'\n');

    fprintf(fid,'REFERENCE Fy / MU BY SLIP ANGLE\n');
    fprintf(fid,'Angle [deg] | Fy [N] | mu [-] | N\n');
    fprintf(fid,'----------------------------------\n');

    for j=1:numel(metricAnglesDeg)
        fprintf(fid,'%10.1f | %7.2f | %6.4f | %d\n', ...
            metricAnglesDeg(j),FyAtAngle(j),MuAtAngle(j),NAtAngle(j));
    end

    fprintf(fid,'\nPEAK STATUS COUNTS\n');
    fprintf(fid,'Resolved         : %d\n',resolved);
    fprintf(fid,'Near plateau     : %d\n',nearplat);
    fprintf(fid,'Boundary limited : %d\n',boundary);
    fprintf(fid,'Review           : %d\n',review);
    fprintf(fid,'Unresolved       : %d\n\n',unres);

    fprintf(fid,'VEHICLE LOAD COVERAGE\n');
    fprintf(fid,'Front tire static load : %.2f N\n',frontTireStaticN);
    fprintf(fid,'Front +/-75 N samples  : %d\n',frontSamples);
    fprintf(fid,'Rear tire static load  : %.2f N\n',rearTireStaticN);
    fprintf(fid,'Rear +/-75 N samples   : %d\n\n',rearSamples);

    fprintf(fid,'PLOTTING RULES\n');
    fprintf(fid,'1. No unrelated load/condition points are connected.\n');
    fprintf(fid,'2. Pressure sensitivity uses four physical pressure families.\n');
    fprintf(fid,'3. Camber sensitivity uses one point per camber state.\n');
    fprintf(fid,'4. Load sensitivity uses one point per load bin.\n');
    fprintf(fid,'5. Peak mu is calculated from a +/-%.1f deg peak region.\n',peakWindow);
    fprintf(fid,'6. Pointwise mu remains diagnostic only.\n');
    fprintf(fid,'7. Low-load bins below %.0f N are retained for audit but excluded\n',lowLoadCutoffN);
    fprintf(fid,'   from the main load trend.\n');
    fprintf(fid,'8. Boundary-limited peaks remain explicitly flagged.\n');
    fprintf(fid,'9. Vehicle static loads are analysis markers only.\n');
    fprintf(fid,'10. v1.5.8 does not fit Magic Formula coefficients.\n\n');

    fprintf(fid,'PRE-MF DECISION\n');

    if resolved+nearplat == 0
        fprintf(fid,'REVIEW REQUIRED — NO RESOLVED/NEAR-PLATEAU PEAKS.\n');
    elseif boundary+review+unres > resolved+nearplat
        fprintf(fid,'PRE-MF REVIEW REQUIRED — DO NOT FIT PACEJKA YET.\n');
    else
        fprintf(fid,'ENGINEERING CHARACTERIZATION ACCEPTABLE FOR NEXT REVIEW STAGE.\n');
    end

    fprintf(fid,'\nIMPORTANT INTERPRETATION\n');
    fprintf(fid,'The isolated-tire peak mu may exceed practical vehicle-level mu.\n');
    fprintf(fid,'This script does not force the measured tire data toward a chosen\n');
    fprintf(fid,'vehicle mu. Vehicle-level utilization must be evaluated later with\n');
    fprintf(fid,'load transfer, combined slip, camber, suspension and vehicle dynamics.\n');

    fprintf(fid,'\nNEXT STAGE GATE\n');
    fprintf(fid,'Magic Formula fitting remains a separate stage.\n');
    fprintf(fid,'Review the reference curve, load sensitivity and peak-resolution audit\n');
    fprintf(fid,'before enabling the MF fitter.\n');

    fclose(fid);
end

%% ============================================================
% [15] FINAL OUTPUT
% =============================================================

fprintf('\n[15] OUTPUT\n');
fprintf('%s\n',outputFolder);
fprintf('Audit report : %s\n',reportFile);

fprintf('\n============================================================\n');
fprintf(' v1.5.8 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Reference observed mu : %.4f\n',refMetric.muPeak);
fprintf('Reference observed Fy : %.2f N\n',refMetric.fyPeak);
fprintf('Reference observed SA : %.3f deg\n',refMetric.peakSA);
fprintf('Peak interpretation   : %s\n',referencePeakLabel(refMetric.status));
fprintf('Reference C-alpha    : %.3f N/deg\n',refMetric.Calpha);
fprintf('Pointwise mu median  : %.4f (DIAGNOSTIC ONLY)\n', ...
    median(muPoint,'omitnan'));
fprintf('============================================================\n');


%% ============================================================
% LOCAL FUNCTION: ANALYZE SUBSET
% =============================================================

function out = analyzeSubset(SA,FY,FZ,alphaBin,minSamples, ...
    boundaryMargin,plateauFrac,peakWindow)

out = struct( ...
    'fzMedian',NaN, ...
    'muPeak',NaN, ...
    'fyPeak',NaN, ...
    'peakSA',NaN, ...
    'Calpha',NaN, ...
    'R2',NaN, ...
    'n',0, ...
    'nPeak',0, ...
    'boundaryFraction',NaN, ...
    'status',"UNRESOLVED", ...
    'valid',false);

good = isfinite(SA)&isfinite(FY)&isfinite(FZ)&FZ>0;

if nnz(good)<minSamples
    return;
end

a = abs(SA(good));
y = abs(FY(good));
fz = FZ(good);

out.n = nnz(good);
out.fzMedian = median(fz,'omitnan');

% Bin by absolute slip angle so positive/negative sweeps are combined
% without allowing one direction to dominate the result.
centers = (0:alphaBin:max(a))';

medY = nan(size(centers));
medFz = nan(size(centers));
nBin = zeros(size(centers));

for k=1:numel(centers)

    z = a >= centers(k)-alphaBin/2 & ...
        a <  centers(k)+alphaBin/2;

    if nnz(z)>0
        medY(k) = median(y(z),'omitnan');
        medFz(k) = median(fz(z),'omitnan');
        nBin(k) = nnz(z);
    end
end

ok = isfinite(medY) & nBin>=2;

centers = centers(ok);
medY = medY(ok);
medFz = medFz(ok);
nBin = nBin(ok);

if numel(centers)<5
    return;
end

% Do not let the zero-slip bin become the peak.
peakCandidates = centers >= max(alphaBin,0.5);

if ~any(peakCandidates)
    return;
end

idxCandidate = find(peakCandidates);
[peakY,ii] = max(medY(peakCandidates));
peakIndex = idxCandidate(ii);
peakA = centers(peakIndex);

out.fyPeak = peakY;
out.peakSA = peakA;

% Peak-region pointwise mu.
pk = a >= max(0,peakA-peakWindow) & ...
     a <= peakA+peakWindow;

out.nPeak = nnz(pk);

if out.nPeak>=10
    out.muPeak = median(y(pk)./fz(pk),'omitnan');
end

% Peak boundary assessment.
amax = max(a);

out.boundaryFraction = peakA/max(amax,eps);

finalMask = centers >= max(0,amax-1);

if nnz(finalMask)>=2
    pf = polyfit(centers(finalMask),medY(finalMask),1);
    finalSlope = pf(1);
else
    finalSlope = NaN;
end

if peakA >= amax-boundaryMargin
    out.status = "BOUNDARY-LIMITED";
elseif isfinite(finalSlope) && ...
       abs(finalSlope) <= plateauFrac*max(peakY,eps)
    out.status = "NEAR-PLATEAU";
elseif peakA < amax-boundaryMargin
    out.status = "RESOLVED";
else
    out.status = "REVIEW";
end

% C-alpha: robust family of low-alpha fits.
ranges = [ ...
    0.25 1.00;
    0.25 1.50;
    0.25 2.00;
    0.50 2.00;
    0.50 2.50];

ca = [];
r2 = [];

for q=1:size(ranges,1)

    z = a>=ranges(q,1) & a<=ranges(q,2);

    if nnz(z)<20
        continue;
    end

    x = a(z);
    yy = y(z);

    pp = polyfit(x,yy,1);
    pred = polyval(pp,x);

    ssres = sum((yy-pred).^2);
    sstot = sum((yy-mean(yy)).^2);

    if sstot<=0
        rr = NaN;
    else
        rr = 1-ssres/sstot;
    end

    if isfinite(rr) && rr>=0.90 && pp(1)>0
        ca(end+1) = pp(1); %#ok<AGROW>
        r2(end+1) = rr; %#ok<AGROW>
    end
end

if ~isempty(ca)
    out.Calpha = median(ca,'omitnan');
    out.R2 = median(r2,'omitnan');
end

out.valid = true;

end


%% ============================================================
% LOCAL FUNCTION: REFERENCE CURVE
% =============================================================

function [aOut,fyOut,fzOut,nOut] = buildReferenceCurve(SA,FY,FZ,alphaBin)

good = isfinite(SA)&isfinite(FY)&isfinite(FZ)&FZ>0;

a = abs(SA(good));
fy = abs(FY(good));
fz = FZ(good);

if isempty(a)
    aOut=[]; fyOut=[]; fzOut=[]; nOut=[];
    return;
end

edges = 0:alphaBin:(max(a)+alphaBin);
centers = edges(1:end-1)+alphaBin/2;

aOut = nan(size(centers));
fyOut = nan(size(centers));
fzOut = nan(size(centers));
nOut = zeros(size(centers));

for k=1:numel(centers)

    z = a>=edges(k) & a<edges(k+1);

    if nnz(z)>=5
        aOut(k) = centers(k);
        fyOut(k) = median(fy(z),'omitnan');
        fzOut(k) = median(fz(z),'omitnan');
        nOut(k) = nnz(z);
    end
end

ok = isfinite(aOut)&isfinite(fyOut)&isfinite(fzOut);

aOut = aOut(ok);
fyOut = fyOut(ok);
fzOut = fzOut(ok);
nOut = nOut(ok);

end


%% ============================================================
% LOCAL FUNCTION: VARIABLE DETECTION
% =============================================================

function chosen = pickVar(names,normNames,candidates)

chosen = "";

for c=1:numel(candidates)

    target = lower(regexprep( ...
        candidates{c},'[^a-zA-Z0-9]',''));

    k = find(normNames==target,1);

    if ~isempty(k)
        chosen = names(k);
        return;
    end
end

for c=1:numel(candidates)

    target = lower(regexprep( ...
        candidates{c},'[^a-zA-Z0-9]',''));

    k = find(contains(normNames,target),1);

    if ~isempty(k)
        chosen = names(k);
        return;
    end
end

error('Required signal could not be auto-detected. Candidates: %s', ...
    strjoin(candidates,', '));

end


%% ============================================================
% LOCAL FUNCTION: REFERENCE PEAK LABEL
% =============================================================

function label = referencePeakLabel(status)

switch string(status)
    case "RESOLVED"
        label = "TRUE PEAK RESOLVED WITHIN MEASURED SA RANGE";
    case "NEAR-PLATEAU"
        label = "NEAR-PLATEAU; PEAK APPROXIMATELY RESOLVED";
    case "BOUNDARY-LIMITED"
        label = "NOT A TRUE PEAK; OBSERVED VALUE AT SA WINDOW LIMIT";
    otherwise
        label = "PEAK NOT RELIABLY IDENTIFIED";
end

end
