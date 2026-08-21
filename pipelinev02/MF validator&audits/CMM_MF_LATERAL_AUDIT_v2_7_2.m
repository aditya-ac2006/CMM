function Result = CMM_MF_LATERAL_AUDIT_v2_7_2()
% ================================================================
% CMM MF LATERAL AUDIT v2.7 UPLOAD
% FROZEN MODEL / NO REFIT / NO OPTIMIZATION
%
% This version is intentionally self-contained and uses the two files
% selected by the user:
%   1) CMM_GLOBAL_MF_LATERAL_v1_5.mat
%   2) TTC_CONDITION_ASSIGNED_DATABASE.csv
%
% IMPORTANT:
%   - It audits the supplied frozen model.
%   - It does NOT refit anything.
%   - It does NOT require hasVariable().
%   - It explicitly handles Pressure_kPa.
%   - It applies the frozen v1.5 FY = -FY convention.
%   - It accepts both v1.5 and v1.5.1 model MAT files.
%
% ================================================================

clc;
close all;

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL AUDIT v2.7\n');
fprintf(' FROZEN MODEL / NO REFIT / ENGINEERING AUDIT\n');
fprintf('============================================================\n\n');

%% ================================================================
% CONFIGURATION
% ================================================================

CFG.Fz0 = 871.5;
CFG.P0 = 12.10;
CFG.IA0 = 0.0;

CFG.FzTol = 75.0;
CFG.PTol = 0.20;
CFG.IATol = 0.20;
CFG.AlphaMax = 12.0;

CFG.R2Pass = 0.95;
CFG.R2Review = 0.90;

CFG.RefRMSEPass = 150;
CFG.RefRMSEReview = 225;

CFG.PeakMuErrPass = 0.08;
CFG.PeakMuErrReview = 0.15;

CFG.PeakSAErrPass = 1.0;
CFG.PeakSAErrReview = 2.0;

CFG.CAlphaSpreadPass = 0.10;
CFG.CAlphaSpreadReview = 0.20;

CFG.MinConditionSamples = 100;
CFG.SensitivityFraction = 0.05;

%% ================================================================
% [1] SELECT MODEL
% ================================================================

fprintf('[1] SELECT FROZEN GLOBAL MF MODEL\n');

[modelName,modelPath] = uigetfile( ...
    {'*.mat','MAT files (*.mat)'}, ...
    'SELECT CMM_GLOBAL_MF_LATERAL_v1_5.mat');

if isequal(modelName,0)
    error('No model selected.');
end

modelFile = fullfile(modelPath,modelName);

fprintf('Model:\n%s\n\n',modelFile);

%% ================================================================
% [2] SELECT DATABASE
% ================================================================

fprintf('[2] SELECT CONDITION-ASSIGNED DATABASE\n');

[csvName,csvPath] = uigetfile( ...
    {'*.csv','CSV files (*.csv)'}, ...
    'SELECT TTC_CONDITION_ASSIGNED_DATABASE.csv');

if isequal(csvName,0)
    error('No database selected.');
end

dbFile = fullfile(csvPath,csvName);

fprintf('Database:\n%s\n\n',dbFile);

%% ================================================================
% [3] LOAD MODEL
% ================================================================

fprintf('[3] LOAD MODEL CONTRACT\n');

S = load(modelFile);

if ~isfield(S,'GlobalMF')
    error('MAT file does not contain GlobalMF.');
end

M = S.GlobalMF;

q = double(M.Parameters(:));
Names = string(M.ParameterNames(:));

fprintf('Model version : %s\n',string(M.Version));
fprintf('Parameters    : %d\n',numel(q));

if isfield(M,'Reference')
    fprintf('Reference Fz  : %.3f N\n',M.Reference.Fz0_N);
    fprintf('Reference P   : %.3f psi\n',M.Reference.P0_psi);
    fprintf('Reference IA  : %.3f deg\n',M.Reference.IA0_deg);
else
    error('GlobalMF.Reference missing.');
end

if numel(q) ~= 19
    error('Expected 19 parameters. Found %d.',numel(q));
end

fprintf('\n');

%% ================================================================
% [4] LOAD DATABASE
% ================================================================

fprintf('[4] LOAD DATABASE\n');

T = readtable(dbFile,'VariableNamingRule','preserve');

fprintf('Rows : %d\n',height(T));
fprintf('Vars : %d\n',width(T));

% Actual supplied database fields are:
% ET, SA_deg, FY_N, FZ_N, IA_deg, Pressure_kPa, Speed_kph,
% RUN, PressureState, CamberState, Camber_deg, ConditionID.

SA = requiredNumeric(T,{'SA_deg','SA','SlipAngle_deg','SlipAngle'});
FY = requiredNumeric(T,{'FY_N','FY','Fy','LateralForce'});
FZ = requiredNumeric(T,{'FZ_N','FZ','Fz','VerticalLoad_N'});
IA = requiredNumeric(T,{'IA_deg','IA','Camber_deg','Camber'});

P = [];
[idxP,nameP] = findColumn(T, ...
    {'Pressure_psi','P_psi','InflationPressure_psi'});

if ~isempty(idxP)

    P = numericColumn(T,idxP);
    fprintf('Pressure : %s [psi]\n',nameP);

else

    [idxP,nameP] = findColumn(T, ...
        {'Pressure_kPa','P_kPa','Pressure','P','InflationPressure'});

    if isempty(idxP)
        error('Pressure column not found.');
    end

    P = numericColumn(T,idxP);

    % Supplied CMM database uses Pressure_kPa.
    if median(P,'omitnan') > 40
        P = P / 6.894757293;
        fprintf('Pressure : %s [kPa] -> converted to psi\n',nameP);
    else
        fprintf('Pressure : %s interpreted as psi\n',nameP);
    end
end

RUN = optionalNumeric(T,{'RUN','Run','RunNumber','RunID'});
SWEEP = optionalNumeric(T,{'SweepID','Sweep_ID','Sweep'});
SPEED = optionalNumeric(T,{'Speed_kph','Speed','V_kph'});

if isempty(RUN), RUN = nan(size(SA)); end
if isempty(SWEEP), SWEEP = nan(size(SA)); end
if isempty(SPEED), SPEED = nan(size(SA)); end

% ------------------------------------------------
% Frozen v1.5 TTC/CMM lateral-force convention.
% The original v1.5 code explicitly applies FY = -FY.
% ------------------------------------------------
FY = -FY;

good = isfinite(SA) & isfinite(FY) & isfinite(FZ) & ...
       isfinite(IA) & isfinite(P) & FZ > 0;

SA = SA(good);
FY = FY(good);
FZ = FZ(good);
IA = IA(good);
P = P(good);
RUN = RUN(good);
SWEEP = SWEEP(good);
SPEED = SPEED(good);

fprintf('Fy multiplier : -1 (frozen v1.5 convention)\n');
fprintf('Samples       : %d\n',numel(SA));
fprintf('SA            : %.3f -> %.3f deg\n',min(SA),max(SA));
fprintf('FY            : %.2f -> %.2f N\n',min(FY),max(FY));
fprintf('FZ            : %.2f -> %.2f N\n',min(FZ),max(FZ));
fprintf('IA            : %.3f -> %.3f deg\n',min(IA),max(IA));
fprintf('Pressure      : %.3f -> %.3f psi\n\n',min(P),max(P));

%% ================================================================
% [5] MODEL CONTRACT CHECK
% ================================================================

fprintf('[5] MODEL CONTRACT AUDIT\n');

Checks = {};
Statuses = {};
Details = {};

addCheck(strcmp(string(M.Version), ...
    "CMM MF LATERAL GLOBAL v1.5 ROBUST") || ...
    strcmp(string(M.Version), ...
    "CMM MF LATERAL GLOBAL v1.5.1"), ...
    'MODEL_VERSION', ...
    ['Accepted frozen model version: ' string(M.Version)]);

expectedNames = [ ...
    "PCY1","PDY1","PDY2","PDY3","PEY1","PEY2", ...
    "PKY1","PKY2","PKY3","PHY1","PHY2","PHY3", ...
    "PVY1","PVY2","PVY3","PVY4","P_MU_1","P_MU_2","P_K_1"];

addCheck(isequal(Names(:),expectedNames(:)), ...
    'PARAMETER_ORDER', ...
    '19-parameter ordering checked.');

addCheck(abs(M.Reference.Fz0_N-CFG.Fz0)<1e-9, ...
    'REFERENCE_FZ', ...
    sprintf('%.3f N',M.Reference.Fz0_N));

addCheck(abs(M.Reference.P0_psi-CFG.P0)<1e-9, ...
    'REFERENCE_PRESSURE', ...
    sprintf('%.3f psi',M.Reference.P0_psi));

addCheck(abs(M.Reference.IA0_deg-CFG.IA0)<1e-9, ...
    'REFERENCE_CAMBER', ...
    sprintf('%.3f deg',M.Reference.IA0_deg));

if isfield(M,'FixedCoefficients')
    fixedOK = isfield(M.FixedCoefficients,'PEY3') && ...
              isfield(M.FixedCoefficients,'PEY4') && ...
              M.FixedCoefficients.PEY3 == 0 && ...
              M.FixedCoefficients.PEY4 == 0;
else
    fixedOK = false;
end

addCheck(fixedOK,'FIXED_COEFFICIENTS','PEY3=0 and PEY4=0.');

%% ================================================================
% [6] DATABASE ROUTING
% ================================================================

fprintf('[6] DATABASE ROUTING AUDIT\n');

if any(isfinite(RUN))

    uRun = unique(RUN(isfinite(RUN)));

    fprintf('Runs represented : %s\n', ...
        strjoin(string(uRun(:).'),', '));

    if all(ismember(uRun,[2 4]))
        addCheck(true,'PRIMARY_7IN_ROUTING', ...
            'Selected database contains only Runs 2 and/or 4.');
    elseif any(ismember(uRun,[2 4]))
        addCheck(false,'PRIMARY_7IN_ROUTING', ...
            'Runs 2/4 are present, but other runs are also present. Review routing.');
        Statuses{end} = 'REVIEW';
    else
        addCheck(false,'PRIMARY_7IN_ROUTING', ...
            'No Run 2/4 data found in selected database.');
        Statuses{end} = 'FAIL';
    end

else

    fprintf('RUN metadata unavailable.\n');

    addCheck(false,'PRIMARY_7IN_ROUTING', ...
        'RUN field unavailable; routing cannot be independently verified.');
end

fprintf('\n');

%% ================================================================
% [7] FROZEN MODEL PREDICTION
% ================================================================

fprintf('[7] FROZEN MODEL PREDICTION\n');

FYhat = cmmMFglobal(q,SA,FZ,IA,P,CFG.Fz0,CFG.P0);

resid = FYhat-FY;

R2raw = calcR2(FY,FYhat);
RMSEraw = sqrt(mean(resid.^2));
MAEraw = mean(abs(resid));

fprintf('Raw database R2   : %.6f\n',R2raw);
fprintf('Raw database RMSE : %.3f N\n',RMSEraw);
fprintf('Raw database MAE  : %.3f N\n\n',MAEraw);

% IMPORTANT:
% The stored v1.5 Global R2/RMSE are fit-data metrics, not necessarily
% raw-row metrics. We therefore report both instead of falsely comparing
% them as identical quantities.

if isfield(M,'Metrics') && isfield(M.Metrics,'Global')
    fprintf('Stored v1.5 Global R2   : %.6f\n',M.Metrics.Global.R2);
    fprintf('Stored v1.5 Global RMSE : %.3f N\n',M.Metrics.Global.RMSE_N);
    fprintf('Stored v1.5 Global MAE  : %.3f N\n\n',M.Metrics.Global.MAE_N);
end

if R2raw >= CFG.R2Pass
    addCheck(true,'RAW_GLOBAL_R2',sprintf('R2 = %.6f',R2raw));
elseif R2raw >= CFG.R2Review
    addCheck(false,'RAW_GLOBAL_R2',sprintf('R2 = %.6f',R2raw));
else
    addCheck(false,'RAW_GLOBAL_R2',sprintf('R2 = %.6f',R2raw));
    Statuses{end}='FAIL';
end

%% ================================================================
% [8] REFERENCE CONDITION
% ================================================================

fprintf('[8] REFERENCE CONDITION AUDIT\n');

ref = abs(FZ-CFG.Fz0)<=CFG.FzTol & ...
      abs(P-CFG.P0)<=CFG.PTol & ...
      abs(IA-CFG.IA0)<=CFG.IATol & ...
      abs(SA)<=CFG.AlphaMax;

if nnz(ref)<100
    error('Reference condition has only %d samples.',nnz(ref));
end

refSA = SA(ref);
refFY = FY(ref);
refFZ = FZ(ref);
refP = P(ref);
refIA = IA(ref);
refPred = FYhat(ref);

R2ref = calcR2(refFY,refPred);
RMSEref = sqrt(mean((refPred-refFY).^2));
MAEref = mean(abs(refPred-refFY));

fprintf('Reference samples : %d\n',nnz(ref));
fprintf('Reference R2      : %.6f\n',R2ref);
fprintf('Reference RMSE    : %.3f N\n',RMSEref);
fprintf('Reference MAE     : %.3f N\n',MAEref);

% Reference curve
alphaGrid = linspace(-12,12,2401)';

refMF = cmmMFglobal(q, ...
    alphaGrid, ...
    CFG.Fz0*ones(size(alphaGrid)), ...
    CFG.IA0*ones(size(alphaGrid)), ...
    CFG.P0*ones(size(alphaGrid)), ...
    CFG.Fz0,CFG.P0);

% Model peak
[peakMF,ip] = max(abs(refMF));
peakMuMF = peakMF/CFG.Fz0;
peakSAMF = alphaGrid(ip);

% Measured peak: use median absolute force in 0.05 deg bins,
% matching the frozen v1.5 reference-validation logic.
measGrid = linspace(0,12,241)';
refCurve = nan(size(measGrid));

for k=1:numel(measGrid)

    z = abs(abs(refSA)-measGrid(k))<=0.05;

    if nnz(z)>=5
        refCurve(k) = median(abs(refFY(z)),'omitnan');
    end
end

valid = isfinite(refCurve);

if any(valid)

    [peakMeasured,im] = max(refCurve(valid));
    validGrid = measGrid(valid);
    peakSAMeasured = validGrid(im);
    peakMuMeasured = peakMeasured/CFG.Fz0;

else

    peakMeasured = NaN;
    peakSAMeasured = NaN;
    peakMuMeasured = NaN;

end

% C-alpha using the exact v1.5 convention:
% h is radians, but cmmMFglobal expects degrees.
hRad = 1e-5;

fPlus = cmmMFglobal(q,hRad*180/pi, ...
    CFG.Fz0,CFG.IA0,CFG.P0,CFG.Fz0,CFG.P0);

fMinus = cmmMFglobal(q,-hRad*180/pi, ...
    CFG.Fz0,CFG.IA0,CFG.P0,CFG.Fz0,CFG.P0);

CAlpha_N_per_rad = (fPlus-fMinus)/(2*hRad);
CAlpha_N_per_deg = CAlpha_N_per_rad*pi/180;

fprintf('Measured peak mu  : %.6f\n',peakMuMeasured);
fprintf('MF peak mu        : %.6f\n',peakMuMF);
fprintf('Measured peak SA  : %.3f deg\n',peakSAMeasured);
fprintf('MF peak SA        : %.3f deg\n',peakSAMF);
fprintf('MF C-alpha        : %.3f N/rad\n',CAlpha_N_per_rad);
fprintf('MF C-alpha        : %.3f N/deg\n\n',CAlpha_N_per_deg);

peakMuErr = abs(peakMuMF-peakMuMeasured)/max(peakMuMeasured,eps);
peakSAErr = abs(abs(peakSAMF)-abs(peakSAMeasured));

addMetricCheck(R2ref,CFG.R2Pass,CFG.R2Review, ...
    'REFERENCE_R2',sprintf('R2 = %.6f',R2ref),false);

addMetricCheck(RMSEref,CFG.RefRMSEPass,CFG.RefRMSEReview, ...
    'REFERENCE_RMSE',sprintf('RMSE = %.3f N',RMSEref),true);

addMetricCheck(peakMuErr,CFG.PeakMuErrPass,CFG.PeakMuErrReview, ...
    'REFERENCE_PEAK_MU',sprintf('Relative error = %.2f %%',100*peakMuErr),true);

addMetricCheck(peakSAErr,CFG.PeakSAErrPass,CFG.PeakSAErrReview, ...
    'REFERENCE_PEAK_SA',sprintf('Error = %.3f deg',peakSAErr),true);

%% ================================================================
% [9] LOAD / PRESSURE / CAMBER CONDITION AUDIT
% ================================================================

fprintf('[9] CONDITION-WISE AUDIT\n');

ConditionRows = struct( ...
    'Axis',{},'Band',{},'N',{}, ...
    'MedianFz_N',{},'MedianP_psi',{},'MedianIA_deg',{}, ...
    'R2',{},'RMSE_N',{},'MAE_N',{},'MeanResidual_N',{});

% Load groups
loadEdges = [150 300 450 600 750 900 1050 1200];

for k=1:numel(loadEdges)-1

    z = FZ>=loadEdges(k) & FZ<loadEdges(k+1);

    if nnz(z)>=CFG.MinConditionSamples

        row = makeCondition( ...
            'LOAD', ...
            sprintf('%.0f-%.0f N',loadEdges(k),loadEdges(k+1)), ...
            z,FZ,P,IA,FY,FYhat);

        ConditionRows(end+1)=row; %#ok<AGROW>
    end
end

% Pressure groups
pressureEdges = [0 9 11 13 15 20];

for k=1:numel(pressureEdges)-1

    z = P>=pressureEdges(k) & P<pressureEdges(k+1);

    if nnz(z)>=CFG.MinConditionSamples

        row = makeCondition( ...
            'PRESSURE', ...
            sprintf('%.1f-%.1f psi',pressureEdges(k),pressureEdges(k+1)), ...
            z,FZ,P,IA,FY,FYhat);

        ConditionRows(end+1)=row; %#ok<AGROW>
    end
end

% Camber groups
camberEdges = [-1 1 3 5];

for k=1:numel(camberEdges)-1

    z = IA>=camberEdges(k) & IA<camberEdges(k+1);

    if nnz(z)>=CFG.MinConditionSamples

        row = makeCondition( ...
            'CAMBER', ...
            sprintf('%.1f-%.1f deg',camberEdges(k),camberEdges(k+1)), ...
            z,FZ,P,IA,FY,FYhat);

        ConditionRows(end+1)=row; %#ok<AGROW>
    end
end

if isempty(ConditionRows)

    ConditionAudit = table();
    fprintf('No condition groups reached minimum sample count.\n');

else

    ConditionAudit = struct2table(ConditionRows);

    fprintf('Condition groups : %d\n',height(ConditionAudit));

    worstR2 = min(ConditionAudit.R2);
    worstRMSE = max(ConditionAudit.RMSE_N);

    fprintf('Worst condition R2   : %.6f\n',worstR2);
    fprintf('Worst condition RMSE : %.3f N\n\n',worstRMSE);

    if worstR2 < CFG.R2Review
        addCheck(false,'CONDITION_R2',sprintf('Worst R2 = %.6f',worstR2));
        Statuses{end}='FAIL';
    elseif worstR2 < CFG.R2Pass
        addCheck(false,'CONDITION_R2',sprintf('Worst R2 = %.6f',worstR2));
    else
        addCheck(true,'CONDITION_R2',sprintf('Worst R2 = %.6f',worstR2));
    end
end

%% ================================================================
% [10] RUN AUDIT
% ================================================================

fprintf('[10] RUN-WISE AUDIT\n');

RunAudit = table();

if any(isfinite(RUN))

    uRun = unique(RUN(isfinite(RUN)));

    RunRows = struct( ...
        'Run',{},'N',{},'R2',{},'RMSE_N',{}, ...
        'MAE_N',{},'MeanResidual_N',{},'MedianFz_N',{}, ...
        'MedianP_psi',{},'MedianIA_deg',{});

    for k=1:numel(uRun)

        z = RUN==uRun(k);

        if nnz(z)>=CFG.MinConditionSamples

            e = FYhat(z)-FY(z);

            rr.Run = uRun(k);
            rr.N = nnz(z);
            rr.R2 = calcR2(FY(z),FYhat(z));
            rr.RMSE_N = sqrt(mean(e.^2));
            rr.MAE_N = mean(abs(e));
            rr.MeanResidual_N = mean(e);
            rr.MedianFz_N = median(FZ(z),'omitnan');
            rr.MedianP_psi = median(P(z),'omitnan');
            rr.MedianIA_deg = median(IA(z),'omitnan');

            RunRows(end+1)=rr; %#ok<AGROW>
        end
    end

    if ~isempty(RunRows)
        RunAudit = struct2table(RunRows);
        fprintf('Runs audited : %d\n',height(RunAudit));
    end
end

fprintf('\n');

%% ================================================================
% [11] SWEEP AUDIT
% ================================================================

fprintf('[11] SWEEP-WISE AUDIT\n');

SweepAudit = table();

if any(isfinite(SWEEP))

    uSweep = unique(SWEEP(isfinite(SWEEP)));

    SweepRows = struct( ...
        'SweepID',{},'N',{},'PositivePeak_N',{}, ...
        'NegativePeak_N',{},'PeakRatio',{},'RatioError',{});

    for k=1:numel(uSweep)

        z = SWEEP==uSweep(k);

        pos = abs(FY(z & SA>1));
        neg = abs(FY(z & SA<-1));

        if nnz(pos)>=5 && nnz(neg)>=5

            pp=max(pos);
            pn=max(neg);
            ratio=pp/max(pn,eps);

            sr.SweepID=uSweep(k);
            sr.N=nnz(z);
            sr.PositivePeak_N=pp;
            sr.NegativePeak_N=pn;
            sr.PeakRatio=ratio;
            sr.RatioError=abs(ratio-1);

            SweepRows(end+1)=sr; %#ok<AGROW>
        end
    end

    if ~isempty(SweepRows)
        SweepAudit=struct2table(SweepRows);
        fprintf('Sweeps audited : %d\n',height(SweepAudit));
    else
        fprintf('No complete positive/negative sweep pairs found.\n');
    end

else
    fprintf('SweepID unavailable.\n');
end

fprintf('\n');

%% ================================================================
% [12] TARGETED 4-PARAMETER SENSITIVITY
% ================================================================

fprintf('[12] TARGETED 4-PARAMETER SENSITIVITY\n');

targetNames = ["PCY1","PDY1","PDY2","PKY1"];

SensitivityRows = struct( ...
    'Parameter',{},'BaseValue',{},'Perturbation_pct',{}, ...
    'PredictionChangeMinus_N',{},'PredictionChangePlus_N',{}, ...
    'ReferencePeakMuChangeMinus',{},'ReferencePeakMuChangePlus',{});

for k=1:numel(targetNames)

    idx=find(Names==targetNames(k),1);

    if isempty(idx)
        continue;
    end

    delta=CFG.SensitivityFraction*max(abs(q(idx)),0.01);

    qm=q;
    qp=q;

    qm(idx)=q(idx)-delta;
    qp(idx)=q(idx)+delta;

    ym=cmmMFglobal(qm,SA,FZ,IA,P,CFG.Fz0,CFG.P0);
    yp=cmmMFglobal(qp,SA,FZ,IA,P,CFG.Fz0,CFG.P0);

    refm=cmmMFglobal(qm,alphaGrid, ...
        CFG.Fz0*ones(size(alphaGrid)), ...
        CFG.IA0*ones(size(alphaGrid)), ...
        CFG.P0*ones(size(alphaGrid)), ...
        CFG.Fz0,CFG.P0);

    refp=cmmMFglobal(qp,alphaGrid, ...
        CFG.Fz0*ones(size(alphaGrid)), ...
        CFG.IA0*ones(size(alphaGrid)), ...
        CFG.P0*ones(size(alphaGrid)), ...
        CFG.Fz0,CFG.P0);

    [pm,~]=max(abs(refm));
    [pp,~]=max(abs(refp));

    sr.Parameter=targetNames(k);
    sr.BaseValue=q(idx);
    sr.Perturbation_pct=100*delta/max(abs(q(idx)),0.01);
    sr.PredictionChangeMinus_N=sqrt(mean((ym-FYhat).^2));
    sr.PredictionChangePlus_N=sqrt(mean((yp-FYhat).^2));
    sr.ReferencePeakMuChangeMinus=pm/CFG.Fz0-peakMuMF;
    sr.ReferencePeakMuChangePlus=pp/CFG.Fz0-peakMuMF;

    SensitivityRows(end+1)=sr; %#ok<AGROW>
end

SensitivityAudit=struct2table(SensitivityRows);

disp(SensitivityAudit);

%% ================================================================
% [13] PHYSICAL GRID
% ================================================================

fprintf('[13] BOUNDED PHYSICAL GRID AUDIT\n');

fzGrid=linspace(max(180,min(FZ)-50),min(1250,max(FZ)+50),8);
pGrid=linspace(max(7,min(P)-1),min(16,max(P)+1),6);
iaGrid=linspace(max(-1,min(IA)-0.5),min(5,max(IA)+0.5),5);
aGrid=linspace(-12,12,481);

maxGridMu=0;
nonFinite=0;

for i=1:numel(fzGrid)
    for j=1:numel(pGrid)
        for k=1:numel(iaGrid)

            yy=cmmMFglobal(q,aGrid, ...
                fzGrid(i)*ones(size(aGrid)), ...
                iaGrid(k)*ones(size(aGrid)), ...
                pGrid(j)*ones(size(aGrid)), ...
                CFG.Fz0,CFG.P0);

            if any(~isfinite(yy))
                nonFinite=nonFinite+1;
            end

            maxGridMu=max(maxGridMu,max(abs(yy))/fzGrid(i));
        end
    end
end

fprintf('Maximum bounded-grid mu : %.5f\n',maxGridMu);
fprintf('Non-finite cases        : %d\n\n',nonFinite);

if nonFinite>0
    addCheck(false,'NONFINITE_GRID',sprintf('%d non-finite grid cases',nonFinite));
    Statuses{end}='FAIL';
else
    addCheck(true,'NONFINITE_GRID','No non-finite predictions.');
end

if maxGridMu>3.5
    addCheck(false,'GRID_MU_BOUND',sprintf('Maximum mu = %.4f',maxGridMu));
    Statuses{end}='FAIL';
elseif maxGridMu>3.0
    addCheck(false,'GRID_MU_BOUND',sprintf('Maximum mu = %.4f',maxGridMu));
else
    addCheck(true,'GRID_MU_BOUND',sprintf('Maximum mu = %.4f',maxGridMu));
end

%% ================================================================
% [14] PLOTS / OUTPUT
% ================================================================

fprintf('[14] WRITE AUDIT OUTPUTS\n');

outFolder = fullfile(modelPath,'_MF_LATERAL_AUDIT_v2_7_UPLOAD');

if ~exist(outFolder,'dir')
    mkdir(outFolder);
end

plotFolder=fullfile(outFolder,'plots');

if ~exist(plotFolder,'dir')
    mkdir(plotFolder);
end

% Checks table
detailStrings = strings(numel(Details),1);
for ii = 1:numel(Details)
    try
        tmp = string(Details{ii});
        tmp = tmp(:);
        if isempty(tmp)
            detailStrings(ii) = "";
        elseif numel(tmp) == 1
            detailStrings(ii) = tmp;
        else
            detailStrings(ii) = strjoin(tmp," ");
        end
    catch
        detailStrings(ii) = "<unprintable detail>";
    end
end

AuditChecks = table( ...
    string(Checks(:)), ...
    string(Statuses(:)), ...
    detailStrings, ...
    'VariableNames',{'Check','Status','Detail'});

writetable(AuditChecks, ...
    fullfile(outFolder,'AUDIT_CHECKS_v2_7.csv'));

if ~isempty(ConditionAudit)
    writetable(ConditionAudit, ...
        fullfile(outFolder,'CONDITION_AUDIT_v2_7.csv'));
end

if ~isempty(RunAudit)
    writetable(RunAudit, ...
        fullfile(outFolder,'RUN_AUDIT_v2_7.csv'));
end

if ~isempty(SweepAudit)
    writetable(SweepAudit, ...
        fullfile(outFolder,'SWEEP_AUDIT_v2_7.csv'));
end

writetable(SensitivityAudit, ...
    fullfile(outFolder,'PARAMETER_SENSITIVITY_v2_7.csv'));

% ------------------------------------------------
% Plot 1: reference
% ------------------------------------------------
fig=figure('Color','w');
plot(abs(refSA),abs(refFY),'.','MarkerSize',4);
hold on;
plot(abs(alphaGrid),abs(refMF),'LineWidth',2);
grid on; box on;
xlabel('|\alpha| [deg]');
ylabel('|F_y| [N]');
title(sprintf('Reference | R^2 %.4f | RMSE %.1f N',R2ref,RMSEref));
legend('Measured','Frozen MF','Location','southeast');

exportgraphics(fig,fullfile(plotFolder,'01_REFERENCE_AUDIT.png'), ...
    'Resolution',180);
close(fig);

% ------------------------------------------------
% Plot 2: measured vs predicted
% ------------------------------------------------
fig=figure('Color','w');
scatter(FY,FYhat,4,'.');
hold on;
lo=min([FY;FYhat]);
hi=max([FY;FYhat]);
plot([lo hi],[lo hi],'--','LineWidth',1.5);
grid on; box on; axis equal;
xlabel('Measured F_y [N]');
ylabel('Frozen MF F_y [N]');
title(sprintf('Raw Database | R^2 %.4f',R2raw));

exportgraphics(fig,fullfile(plotFolder,'02_MEASURED_VS_PREDICTED.png'), ...
    'Resolution',180);
close(fig);

% ------------------------------------------------
% Plot 3: residual vs alpha
% ------------------------------------------------
fig=figure('Color','w');
scatter(SA,resid,4,'.');
hold on; yline(0,'--');
grid on; box on;
xlabel('\alpha [deg]');
ylabel('F_y^{MF}-F_y^{meas} [N]');
title('Residual vs Slip Angle');

exportgraphics(fig,fullfile(plotFolder,'03_RESIDUAL_VS_SA.png'), ...
    'Resolution',180);
close(fig);

% ------------------------------------------------
% Plot 4: residual vs Fz
% ------------------------------------------------
fig=figure('Color','w');
scatter(FZ,resid,4,'.');
hold on; yline(0,'--');
grid on; box on;
xlabel('F_z [N]');
ylabel('Residual [N]');
title('Residual vs Vertical Load');

exportgraphics(fig,fullfile(plotFolder,'04_RESIDUAL_VS_FZ.png'), ...
    'Resolution',180);
close(fig);

% ------------------------------------------------
% Plot 5: residual vs pressure
% ------------------------------------------------
fig=figure('Color','w');
scatter(P,resid,4,'.');
hold on; yline(0,'--');
grid on; box on;
xlabel('Pressure [psi]');
ylabel('Residual [N]');
title('Residual vs Pressure');

exportgraphics(fig,fullfile(plotFolder,'05_RESIDUAL_VS_PRESSURE.png'), ...
    'Resolution',180);
close(fig);

% ------------------------------------------------
% Plot 6: residual vs camber
% ------------------------------------------------
fig=figure('Color','w');
scatter(IA,resid,4,'.');
hold on; yline(0,'--');
grid on; box on;
xlabel('Camber [deg]');
ylabel('Residual [N]');
title('Residual vs Camber');

exportgraphics(fig,fullfile(plotFolder,'06_RESIDUAL_VS_CAMBER.png'), ...
    'Resolution',180);
close(fig);

%% ================================================================
% FINAL VERDICT
% ================================================================

fprintf('[15] FINAL VERDICT\n');

finalStatus='PASS';

for k=1:numel(Statuses)

    if strcmp(Statuses{k},'FAIL')
        finalStatus='FAIL';
        break;
    elseif strcmp(Statuses{k},'REVIEW')
        finalStatus='REVIEW';
    end
end

% Explicit hard gates.
if R2ref < CFG.R2Review || ...
   R2raw < CFG.R2Review || ...
   RMSEref > CFG.RefRMSEReview || ...
   peakMuErr > CFG.PeakMuErrReview || ...
   peakSAErr > CFG.PeakSAErrReview

    finalStatus='FAIL';

elseif finalStatus=="PASS" && ...
       (R2ref < CFG.R2Pass || ...
        R2raw < CFG.R2Pass || ...
        RMSEref > CFG.RefRMSEPass || ...
        peakMuErr > CFG.PeakMuErrPass || ...
        peakSAErr > CFG.PeakSAErrPass)

    finalStatus='REVIEW';
end

fprintf('\n');
fprintf('============================================================\n');
fprintf(' FINAL AUDIT STATUS : %s\n',finalStatus);
fprintf('============================================================\n\n');

%% ================================================================
% REPORT
% ================================================================

reportFile=fullfile(outFolder,'AUDIT_REPORT_v2_7.txt');

fid=fopen(reportFile,'w');

fprintf(fid,'CMM MF LATERAL AUDIT v2.7\n');
fprintf(fid,'============================================================\n\n');
fprintf(fid,'FINAL STATUS: %s\n\n',finalStatus);

fprintf(fid,'MODEL\n');
fprintf(fid,'------------------------------------------------------------\n');
fprintf(fid,'File: %s\n',modelFile);
fprintf(fid,'Version: %s\n',string(M.Version));
fprintf(fid,'Parameters: %d\n\n',numel(q));

fprintf(fid,'DATABASE\n');
fprintf(fid,'------------------------------------------------------------\n');
fprintf(fid,'File: %s\n',dbFile);
fprintf(fid,'Samples: %d\n',numel(SA));
fprintf(fid,'Fz: %.2f -> %.2f N\n',min(FZ),max(FZ));
fprintf(fid,'Pressure: %.3f -> %.3f psi\n',min(P),max(P));
fprintf(fid,'IA: %.3f -> %.3f deg\n',min(IA),max(IA));
fprintf(fid,'SA: %.3f -> %.3f deg\n\n',min(SA),max(SA));

fprintf(fid,'GLOBAL RAW AUDIT\n');
fprintf(fid,'------------------------------------------------------------\n');
fprintf(fid,'R2: %.8f\n',R2raw);
fprintf(fid,'RMSE: %.6f N\n',RMSEraw);
fprintf(fid,'MAE: %.6f N\n\n',MAEraw);

if isfield(M,'Metrics') && isfield(M.Metrics,'Global')
    fprintf(fid,'STORED MODEL METRICS\n');
    fprintf(fid,'------------------------------------------------------------\n');
    fprintf(fid,'R2: %.8f\n',M.Metrics.Global.R2);
    fprintf(fid,'RMSE: %.6f N\n',M.Metrics.Global.RMSE_N);
    fprintf(fid,'MAE: %.6f N\n\n',M.Metrics.Global.MAE_N);
end

fprintf(fid,'REFERENCE AUDIT\n');
fprintf(fid,'------------------------------------------------------------\n');
fprintf(fid,'N: %d\n',nnz(ref));
fprintf(fid,'R2: %.8f\n',R2ref);
fprintf(fid,'RMSE: %.6f N\n',RMSEref);
fprintf(fid,'MAE: %.6f N\n',MAEref);
fprintf(fid,'Measured peak mu: %.8f\n',peakMuMeasured);
fprintf(fid,'MF peak mu: %.8f\n',peakMuMF);
fprintf(fid,'Peak mu error: %.3f %%\n',100*peakMuErr);
fprintf(fid,'Measured peak SA: %.6f deg\n',peakSAMeasured);
fprintf(fid,'MF peak SA: %.6f deg\n',peakSAMF);
fprintf(fid,'Peak SA error: %.6f deg\n',peakSAErr);
fprintf(fid,'C-alpha: %.6f N/rad\n',CAlpha_N_per_rad);
fprintf(fid,'C-alpha: %.6f N/deg\n\n',CAlpha_N_per_deg);

fprintf(fid,'AUDIT CHECKS\n');
fprintf(fid,'------------------------------------------------------------\n');

for k=1:height(AuditChecks)
    fprintf(fid,'%-28s | %-7s | %s\n', ...
        AuditChecks.Check(k), ...
        AuditChecks.Status(k), ...
        AuditChecks.Detail(k));
end

fprintf(fid,'\nSCOPE\n');
fprintf(fid,'------------------------------------------------------------\n');
fprintf(fid,'Pure lateral only.\n');
fprintf(fid,'No Fx/slip-ratio/combined-slip model.\n');
fprintf(fid,'No fitting or optimization.\n');
fprintf(fid,'No coefficients modified.\n');
fprintf(fid,'No source rows deleted.\n');
fprintf(fid,'Pressure_kPa converted to psi for model evaluation.\n');
fprintf(fid,'FY sign is inverted exactly as in frozen v1.5 preprocessing.\n');

fclose(fid);

%% ================================================================
% SAVE MAT SUMMARY
% ================================================================

Summary=struct();

Summary.Status=finalStatus;
Summary.ModelFile=modelFile;
Summary.DatabaseFile=dbFile;
Summary.ModelVersion=string(M.Version);

Summary.Global.Raw.R2=R2raw;
Summary.Global.Raw.RMSE_N=RMSEraw;
Summary.Global.Raw.MAE_N=MAEraw;

Summary.Reference.N=nnz(ref);
Summary.Reference.R2=R2ref;
Summary.Reference.RMSE_N=RMSEref;
Summary.Reference.MAE_N=MAEref;
Summary.Reference.MeasuredPeakMu=peakMuMeasured;
Summary.Reference.ModelPeakMu=peakMuMF;
Summary.Reference.PeakMuRelativeError=peakMuErr;
Summary.Reference.MeasuredPeakSA_deg=peakSAMeasured;
Summary.Reference.ModelPeakSA_deg=peakSAMF;
Summary.Reference.PeakSAError_deg=peakSAErr;
Summary.Reference.CAlpha_N_per_rad=CAlpha_N_per_rad;
Summary.Reference.CAlpha_N_per_deg=CAlpha_N_per_deg;

Summary.Database.FzRange_N=[min(FZ) max(FZ)];
Summary.Database.PressureRange_psi=[min(P) max(P)];
Summary.Database.IARange_deg=[min(IA) max(IA)];
Summary.Database.SARange_deg=[min(SA) max(SA)];

save(fullfile(outFolder,'CMM_MF_LATERAL_AUDIT_v2_7.mat'), ...
    'Summary','AuditChecks','ConditionAudit','RunAudit', ...
    'SweepAudit','SensitivityAudit');

fprintf('Audit output folder:\n%s\n\n',outFolder);

Result=Summary;

fprintf('============================================================\n');
fprintf(' CMM MF LATERAL AUDIT v2.7 COMPLETE\n');
fprintf(' STATUS : %s\n',finalStatus);
fprintf('============================================================\n');

%% ================================================================
% NESTED HELPERS
% ================================================================

function addCheck(pass,name,detail)

    Checks{end+1}=name;
    Details{end+1}=detail;

    if pass
        Statuses{end+1}='PASS';
    else
        Statuses{end+1}='REVIEW';
    end
end

function addMetricCheck(value,passLimit,reviewLimit,name,detail,invert)

    Checks{end+1}=name;
    Details{end+1}=detail;

    if invert

        if value<=passLimit
            Statuses{end+1}='PASS';
        elseif value<=reviewLimit
            Statuses{end+1}='REVIEW';
        else
            Statuses{end+1}='FAIL';
        end

    else

        if value>=passLimit
            Statuses{end+1}='PASS';
        elseif value>=reviewLimit
            Statuses{end+1}='REVIEW';
        else
            Statuses{end+1}='FAIL';
        end
    end
end

end

%% ================================================================
% FROZEN v1.5 MODEL EQUATION
% ================================================================

function y=cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)

a=double(alphaDeg)*pi/180;
g=double(camberDeg)*pi/180;
Fz=max(double(Fz),1);
Ppsi=double(Ppsi);

dfz=(Fz-Fz0)./Fz0;
dP=Ppsi-P0;

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

Cy=PCY1;

mu=(PDY1+PDY2.*dfz).*(1-PDY3.*g.^2);

muP=1+Pmu1.*dP+Pmu2.*dP.^2;

mu=mu.*muP;
mu=max(mu,0.20);

Dy=mu.*Fz;

Ey=PEY1+PEY2.*dfz;
Ey=max(-1.0,min(1.0,Ey));

stiffCamber=max(0.10,1-PKY3.*g.^2);

Ky=PKY1.*Fz0.* ...
    sin(2.*atan(Fz./(PKY2.*Fz0))).* ...
    stiffCamber;

Ky=Ky.*(1+Pk1.*dP);
Ky=max(Ky,100);

By=Ky./max(Cy.*Dy,1);

Shy=PHY1+PHY2.*dfz+PHY3.*g;

Svy=Fz.*(PVY1+PVY2.*dfz)+ ...
    mu.*Fz.*(PVY3+PVY4.*dfz).*g;

alphaY=a+Shy;

x=By.*alphaY;

Fy=Dy.*sin( ...
    Cy.*atan(x-Ey.*(x-atan(x))) )+Svy;

y=Fy;

end

%% ================================================================
% DATA HELPERS
% ================================================================

function [idx,name]=findColumn(T,candidates)

names=string(T.Properties.VariableNames);
normNames=lower(regexprep(names,'[^a-zA-Z0-9]',''));

idx=[];
name="";

for k=1:numel(candidates)

    target=lower(regexprep(candidates{k},'[^a-zA-Z0-9]',''));

    j=find(normNames==target,1);

    if ~isempty(j)

        idx=j;
        name=names(j);
        return;

    end
end
end

function x=requiredNumeric(T,candidates)

[idx,name]=findColumn(T,candidates);

if isempty(idx)

    fprintf('\nAvailable columns:\n');
    disp(string(T.Properties.VariableNames(:)));

    error('Required variable not found. Candidates: %s', ...
        strjoin(string(candidates),', '));
end

x=numericColumn(T,idx);

fprintf('Mapped %-12s -> %s\n',string(candidates{1}),name);
end

function x=optionalNumeric(T,candidates)

[idx,~]=findColumn(T,candidates);

if isempty(idx)
    x=[];
else
    x=numericColumn(T,idx);
end
end

function x=numericColumn(T,idx)

v=T{:,idx};

if iscell(v) || isstring(v) || ischar(v) || iscategorical(v)
    v=str2double(string(v));
end

x=double(v(:));
end

%% ================================================================
% METRICS
% ================================================================

function r2=calcR2(y,yp)

y=y(:);
yp=yp(:);

ok=isfinite(y)&isfinite(yp);

y=y(ok);
yp=yp(ok);

if isempty(y)
    r2=NaN;
    return;
end

den=sum((y-mean(y)).^2);

if den<=0
    r2=NaN;
else
    r2=1-sum((y-yp).^2)/den;
end
end

function row=makeCondition(axisName,band,z,FZ,P,IA,FY,FYhat)

e=FYhat(z)-FY(z);

row.Axis=string(axisName);
row.Band=string(band);
row.N=nnz(z);
row.MedianFz_N=median(FZ(z),'omitnan');
row.MedianP_psi=median(P(z),'omitnan');
row.MedianIA_deg=median(IA(z),'omitnan');
row.R2=calcR2(FY(z),FYhat(z));
row.RMSE_N=sqrt(mean(e.^2));
row.MAE_N=mean(abs(e));
row.MeanResidual_N=mean(e);

end
