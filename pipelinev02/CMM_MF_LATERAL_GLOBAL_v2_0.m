function CMM_MF_LATERAL_GLOBAL_v2_0
% ================================================================
% CMM MF LATERAL GLOBAL v2.0
% CLEAN PURE-LATERAL MF / 7-IN RIM / RUNS 2+4
% ================================================================
%
% PURPOSE
%   Canonical CMM pure-lateral Magic Formula model.
%
%   v2.0 keeps the validated v1.5 MF formulation, but fixes the
%   workflow around it:
%     1) No hard-coded input path.
%     2) Explicit 7-inch / Runs 2+4 database contract.
%     3) Explicit FY sign convention with a sanity check.
%     4) Run 2 is development-fit data; Run 4 is holdout validation.
%     5) Final global model is refit on Runs 2+4 only after holdout pass.
%     6) Fit and validation metrics are reported separately.
%     7) Model .mat, parameter CSV, validation CSV and audit report saved.
%     8) .tir generation remains BLOCKED.
%
% MODEL
%   19-parameter CMM pure-lateral MF wrapper:
%   PCY1 PDY1 PDY2 PDY3 PEY1 PEY2 PKY1 PKY2 PKY3
%   PHY1 PHY2 PHY3 PVY1 PVY2 PVY3 PVY4 P_MU_1 P_MU_2 P_K_1
%
%   PEY3 = 0, PEY4 = 0 remain fixed.
%   Pressure terms are CMM wrapper terms, NOT direct MF-Tyre .tir terms.
%
% ================================================================

clc;
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL GLOBAL v2.0\n');
fprintf(' CLEAN PURE-LATERAL MF / 7-IN RIM / RUNS 2+4\n');
fprintf('============================================================\n\n');

%% ---------------- USER CONTRACT ----------------
[fn,fp] = uigetfile({'*.csv','CSV files (*.csv)'}, ...
    'Select TTC_CONDITION_ASSIGNED_DATABASE.csv');
if isequal(fn,0)
    error('No database selected.');
end
INPUT_CSV = fullfile(fp,fn);

OUTDIR = fullfile(fp,'_MF_LATERAL_GLOBAL_v2_0');
if ~exist(OUTDIR,'dir'), mkdir(OUTDIR); end

% Frozen CMM reference condition
FZ0 = 871.5;       % N
P0  = 12.10;       % psi
IA0 = 0.0;         % deg

FZ_TOL = 75.0;
P_TOL  = 0.20;
IA_TOL = 0.20;

ALPHA_MAX_FIT = 12.0;
MIN_FZ_FIT = 180;
MAX_FZ_FIT = 1150;

ALPHA_BIN = 0.05;  % deg
FZ_BIN    = 25;    % N
IA_BIN    = 0.25;  % deg
P_BIN     = 0.50;  % psi

MAX_GLOBAL_POINTS = 30000;
N_STARTS = 16;
USE_PARALLEL = true;

% Explicit CMM force convention.
% Do NOT change this casually. The sign check below must pass.
FY_SIGN_MULTIPLIER = -1;

% Strict current model contract.
REQUIRED_RUNS = [2 4];
FIT_RUNS      = 2;
VALID_RUNS    = 4;

% Holdout acceptance gate.
MIN_REF_SAMPLES = 300;
MIN_HOLDOUT_SAMPLES = 300;
MIN_HOLDOUT_R2 = 0.90;

%% ---------------- LOAD DATABASE ----------------
fprintf('[1] INPUT\n%s\n\n',INPUT_CSV);
T = readtable(INPUT_CSV);

fprintf('[2] DATABASE\n');
fprintf('Rows : %d\n',height(T));
fprintf('Vars : %d\n\n',width(T));

SA = getNumeric(T, {'SA_deg','SA','SlipAngle_deg','SlipAngle','Slip_Angle','Alpha'});
FYraw = getNumeric(T, {'FY_N','FY','Fy','LateralForce','Lateral_Force'});
FZ = getNumeric(T, {'FZ_N','FZ','Fz','VerticalLoad_N','VerticalLoad','Vertical_Load'});
IA = getNumeric(T, {'IA_deg','IA','Camber_deg','Camber','Inclination','CamberAngle'});

if hasVariable(T, {'P_psi','Pressure_psi','InflationPressure_psi'})
    P = getNumeric(T, {'P_psi','Pressure_psi','InflationPressure_psi'});
    fprintf('Pressure mapping : canonical psi\n');
else
    P = getNumeric(T, {'P_kPa','P','Pressure_kPa','Pressure','InflationPressure','Inflation_Pressure'});
    if median(P,'omitnan') > 40
        P = P * 0.1450377377;
        fprintf('Pressure mapping : detected kPa -> psi\n');
    else
        fprintf('Pressure mapping : interpreted as psi\n');
    end
end

% Run identity is required for the v2.0 fit/holdout contract.
if ~hasVariable(T, {'Run','RunID','Run_Id','RunNumber','Run_Number','TestRun'})
    error(['v2.0 requires a run identifier so that Run 2 can be used for ' ...
           'development fitting and Run 4 can be held out for validation.']);
end
RUN = getNumeric(T, {'Run','RunID','Run_Id','RunNumber','Run_Number','TestRun'});

% Rim width is strongly preferred. If absent, the run contract still
% protects the current 7-inch dataset by requiring Runs 2 and 4.
HAS_RIM_WIDTH = hasVariable(T, {'RimWidth_in','RimWidth','Rim_Width_in','WheelWidth_in'});
if HAS_RIM_WIDTH
    RIMW = getNumeric(T, {'RimWidth_in','RimWidth','Rim_Width_in','WheelWidth_in'});
else
    RIMW = nan(height(T),1);
end

% Optional rim diameter for audit only.
RIMD = nan(height(T),1);
if hasVariable(T, {'RimDiameter_in','RimDiameter','Rim_Diameter_in','WheelDiameter_in'})
    RIMD = getNumeric(T, {'RimDiameter_in','RimDiameter','Rim_Diameter_in','WheelDiameter_in'});
end

%% ---------------- CLEAN + CONTRACT ----------------
FY = FYraw * FY_SIGN_MULTIPLIER;

good = isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)&isfinite(P)& ...
       isfinite(RUN)&(FZ>0);

SA=SA(good); FY=FY(good); FZ=FZ(good); IA=IA(good); P=P(good);
RUN=RUN(good); RIMW=RIMW(good); RIMD=RIMD(good);

fprintf('[3] DATABASE CONTRACT\n');
fprintf('FY multiplier      : %+g\n',FY_SIGN_MULTIPLIER);
fprintf('Required runs      : %s\n',mat2str(REQUIRED_RUNS));
fprintf('Rows after cleaning: %d\n',numel(FY));

runMask = ismember(round(RUN),REQUIRED_RUNS);
if nnz(runMask) < 2*MIN_HOLDOUT_SAMPLES
    error('Runs 2 and 4 are not both sufficiently populated.');
end

% If rim width exists, enforce 7-inch data.
if HAS_RIM_WIDTH
    rimMask = abs(RIMW-7.0) <= 0.05;
    if nnz(runMask & ~rimMask) > 0
        fprintf('7-inch rim filter: excluding %d non-7-inch rows from candidate runs.\n', ...
            nnz(runMask & ~rimMask));
    end
else
    rimMask = true(size(runMask));
    fprintf('Rim width column not found; 7-inch status is inherited from the run contract.\n');
end

contractMask = runMask & rimMask;
if nnz(contractMask) < 2*MIN_HOLDOUT_SAMPLES
    error('7-inch Runs 2+4 contract leaves too few rows.');
end

SA=SA(contractMask); FY=FY(contractMask); FZ=FZ(contractMask);
IA=IA(contractMask); P=P(contractMask); RUN=RUN(contractMask);
RIMW=RIMW(contractMask); RIMD=RIMD(contractMask);

fprintf('Contract rows      : %d\n',numel(FY));
fprintf('Run 2 rows         : %d\n',nnz(round(RUN)==2));
fprintf('Run 4 rows         : %d\n',nnz(round(RUN)==4));
if HAS_RIM_WIDTH
    fprintf('Rim width range    : %.3f -> %.3f in\n',min(RIMW),max(RIMW));
end
if any(isfinite(RIMD))
    fprintf('Rim diameter range : %.3f -> %.3f in\n',min(RIMD),max(RIMD));
end
fprintf('SA range           : %.3f -> %.3f deg\n',min(SA),max(SA));
fprintf('FY range           : %.2f -> %.2f N\n',min(FY),max(FY));
fprintf('FZ range           : %.2f -> %.2f N\n',min(FZ),max(FZ));
fprintf('IA range           : %.3f -> %.3f deg\n',min(IA),max(IA));
fprintf('P range            : %.2f -> %.2f psi\n\n',min(P),max(P));

%% ---------------- SIGN SANITY CHECK ----------------
% In the CMM internal convention used by v1.5, positive SA should produce
% positive Fy near the origin after the explicit multiplier above.
near0 = abs(SA)<=1.0 & FZ>=300 & FZ<=1100 & abs(IA)<=0.5 & abs(P-P0)<=1.0;
if nnz(near0) < 50
    warning('Few near-zero points available for FY sign sanity check.');
    signSlope = NaN;
else
    signSlope = polyfit(SA(near0),FY(near0),1);
    signSlope = signSlope(1);
    fprintf('[4] FY SIGN SANITY CHECK\n');
    fprintf('Near-zero dFy/dSA : %.3f N/deg\n',signSlope);
    if ~isfinite(signSlope) || signSlope <= 0
        error(['FY sign sanity check failed. The explicit multiplier is %g, ' ...
               'but the corrected data still has non-positive local slope.'], ...
               FY_SIGN_MULTIPLIER);
    end
    fprintf('Result             : PASS\n\n');
end

%% ---------------- REFERENCE CONTRACT ----------------
ref = abs(FZ-FZ0)<=FZ_TOL & abs(P-P0)<=P_TOL & abs(IA-IA0)<=IA_TOL & ...
      abs(SA)<=ALPHA_MAX_FIT;

fprintf('[5] REFERENCE CONTRACT\n');
fprintf('Fz0 : %.1f N +/- %.1f N\n',FZ0,FZ_TOL);
fprintf('P0  : %.2f psi +/- %.2f psi\n',P0,P_TOL);
fprintf('IA0 : %.1f deg +/- %.1f deg\n',IA0,IA_TOL);
fprintf('Reference samples : %d\n\n',nnz(ref));

if nnz(ref)<MIN_REF_SAMPLES
    error('Reference condition has too few samples.');
end

%% ---------------- DEVELOPMENT FIT / HOLDOUT VALIDATION ----------------
fitMask = RUN==FIT_RUNS & FZ>=MIN_FZ_FIT & FZ<=MAX_FZ_FIT & ...
          abs(SA)<=ALPHA_MAX_FIT;

valMask = RUN==VALID_RUNS & FZ>=MIN_FZ_FIT & FZ<=MAX_FZ_FIT & ...
          abs(SA)<=ALPHA_MAX_FIT;

if nnz(fitMask)<MIN_HOLDOUT_SAMPLES
    error('Run 2 has too few fitting samples.');
end
if nnz(valMask)<MIN_HOLDOUT_SAMPLES
    error('Run 4 has too few holdout validation samples.');
end

Xfit = binMedianData([SA(fitMask),FZ(fitMask),IA(fitMask),P(fitMask),FY(fitMask)], ...
                     ALPHA_BIN,FZ_BIN,IA_BIN,P_BIN);
Xval = binMedianData([SA(valMask),FZ(valMask),IA(valMask),P(valMask),FY(valMask)], ...
                     ALPHA_BIN,FZ_BIN,IA_BIN,P_BIN);

if size(Xfit,1)>MAX_GLOBAL_POINTS
    rng(42);
    Xfit = Xfit(randperm(size(Xfit,1),MAX_GLOBAL_POINTS),:);
end

fprintf('[6] DEVELOPMENT FIT / HOLDOUT\n');
fprintf('Run 2 raw points   : %d\n',nnz(fitMask));
fprintf('Run 2 binned       : %d\n',size(Xfit,1));
fprintf('Run 4 raw points   : %d\n',nnz(valMask));
fprintf('Run 4 binned       : %d\n\n',size(Xval,1));

%% ---------------- MODEL INITIALIZATION ----------------
B0 = 10.925835;
C0 = 1.4562862;
D0 = 2023.049;
E0 = 0.35435126;
Sh0_deg = 0.025991;

K0 = B0*C0*D0;
PKY2_0 = 1.60;
PKY1_0 = K0/(FZ0*sin(2*atan(1/PKY2_0)));

p0 = [ ...
    C0, D0/FZ0, -0.20, 1.0, E0, 0.0, ...
    PKY1_0, PKY2_0, 0.0, Sh0_deg*pi/180, 0, 0, ...
    0,0,0,0, 0,0,0];

lb = [ ...
    1.15, 1.70,-1.50,0.0,0.05,-1.00, ...
    20.0,0.30,-20.0,-0.020,-0.020,-0.50, ...
    -0.15,-0.15,-1.00,-1.00,-0.030,-0.005,-0.030];

ub = [ ...
    1.80,3.00,0.50,40.0,0.90,1.00, ...
    80.0,5.00,20.0,0.020,0.020,0.50, ...
    0.15,0.15,1.00,1.00,0.030,0.005,0.030];

typicalX = max(abs(p0), ...
    [1 2 0.5 8 0.35 0.2 40 1.6 1 0.001 0.001 0.05 ...
     0.02 0.02 0.2 0.2 0.01 0.001 0.01]);

fprintf('[7] DEVELOPMENT MULTI-START FIT\n');
obj = @(q) globalResidual(q,Xfit(:,1),Xfit(:,2),Xfit(:,3),Xfit(:,4),Xfit(:,5),FZ0,P0);

pool=[];
if USE_PARALLEL && license('test','Distrib_Computing_Toolbox')
    try
        pool=gcp('nocreate');
        if isempty(pool), pool=parpool('local'); end
        fprintf('Parallel workers   : %d\n',pool.NumWorkers);
    catch ME
        fprintf('Parallel unavailable: %s\n',ME.message);
    end
end

rng(2026);
starts=zeros(N_STARTS,numel(p0));
starts(1,:)=p0;
for s=2:N_STARTS
    q0=p0 + 0.10*(ub-lb).*randn(size(p0));
    starts(s,:)=max(lb,min(ub,q0));
end

results=cell(N_STARTS,1);
if ~isempty(pool) && pool.NumWorkers>1
    parfor s=1:N_STARTS
        results{s}=runOneStart(starts(s,:),lb,ub,typicalX,obj);
    end
else
    for s=1:N_STARTS
        results{s}=runOneStart(starts(s,:),lb,ub,typicalX,obj);
    end
end

costs=inf(N_STARTS,1); flags=nan(N_STARTS,1); iters=nan(N_STARTS,1);
for s=1:N_STARTS
    if ~isempty(results{s})
        costs(s)=results{s}.cost;
        flags(s)=results{s}.exitflag;
        iters(s)=results{s}.iterations;
    end
end

[bestCost,bestIdx]=min(costs);
if ~isfinite(bestCost), error('All development multi-start fits failed.'); end
qDev=results{bestIdx}.q;

fprintf('Selected start      : %02d\n',bestIdx);
fprintf('Best normalized cost: %.8g\n',bestCost);
fprintf('Exit flag           : %g\n\n',results{bestIdx}.exitflag);

%% ---------------- DEVELOPMENT FIT METRICS ----------------
devPred=cmmMFglobal(qDev,Xfit(:,1),Xfit(:,2),Xfit(:,3),Xfit(:,4),FZ0,P0);
devErr=Xfit(:,5)-devPred;
devR2=calcR2(Xfit(:,5),devPred);
devRMSE=sqrt(mean(devErr.^2));
devMAE=mean(abs(devErr));

%% ---------------- HOLDOUT VALIDATION ----------------
valPred=cmmMFglobal(qDev,Xval(:,1),Xval(:,2),Xval(:,3),Xval(:,4),FZ0,P0);
valErr=Xval(:,5)-valPred;
valR2=calcR2(Xval(:,5),valPred);
valRMSE=sqrt(mean(valErr.^2));
valMAE=mean(abs(valErr));

fprintf('[8] HOLDOUT VALIDATION -- RUN 4\n');
fprintf('Holdout R2         : %.6f\n',valR2);
fprintf('Holdout RMSE       : %.3f N\n',valRMSE);
fprintf('Holdout MAE        : %.3f N\n',valMAE);

if valR2 < MIN_HOLDOUT_R2
    error('HOLDOUT FAILED: Run 4 R2 %.4f is below %.2f. Final global refit blocked.', ...
        valR2,MIN_HOLDOUT_R2);
end
fprintf('Holdout result     : PASS\n\n');

%% ---------------- FINAL GLOBAL REFIT ----------------
fprintf('[9] FINAL GLOBAL REFIT -- RUNS 2+4\n');

mask2 = RUN==2 & FZ>=MIN_FZ_FIT & FZ<=MAX_FZ_FIT & abs(SA)<=ALPHA_MAX_FIT;
mask4 = RUN==4 & FZ>=MIN_FZ_FIT & FZ<=MAX_FZ_FIT & abs(SA)<=ALPHA_MAX_FIT;

X2=binMedianData([SA(mask2),FZ(mask2),IA(mask2),P(mask2),FY(mask2)], ...
                 ALPHA_BIN,FZ_BIN,IA_BIN,P_BIN);
X4=binMedianData([SA(mask4),FZ(mask4),IA(mask4),P(mask4),FY(mask4)], ...
                 ALPHA_BIN,FZ_BIN,IA_BIN,P_BIN);
Xglobal=[X2;X4];

if size(Xglobal,1)>MAX_GLOBAL_POINTS
    rng(43);
    Xglobal=Xglobal(randperm(size(Xglobal,1),MAX_GLOBAL_POINTS),:);
end

globalObj=@(q) globalResidual(q,Xglobal(:,1),Xglobal(:,2),Xglobal(:,3), ...
    Xglobal(:,4),Xglobal(:,5),FZ0,P0);

globalResult=runOneStart(qDev,lb,ub,typicalX,globalObj);
if isempty(globalResult)
    error('Final global refit failed.');
end
q=globalResult.q;

globalPred=cmmMFglobal(q,Xglobal(:,1),Xglobal(:,2),Xglobal(:,3),Xglobal(:,4),FZ0,P0);
globalErr=Xglobal(:,5)-globalPred;
globalR2=calcR2(Xglobal(:,5),globalPred);
globalRMSE=sqrt(mean(globalErr.^2));
globalMAE=mean(abs(globalErr));

%% ---------------- INDEPENDENT REFERENCE CHARACTERIZATION ----------------
refA=SA(ref);
refFY=FY(ref);
refMF=cmmMFglobal(q,refA,FZ(ref),IA(ref),P(ref),FZ0,P0);

refR2=calcR2(refFY,refMF);
refRMSE=sqrt(mean((refFY-refMF).^2));
refMAE=mean(abs(refFY-refMF));

alphaGrid=linspace(-12,12,481)';
refCurve=cmmMFglobal(q,alphaGrid,FZ0*ones(size(alphaGrid)), ...
                     IA0*ones(size(alphaGrid)),P0*ones(size(alphaGrid)),FZ0,P0);

h=0.01;
ca=(cmmMFglobal(q,h*180/pi,FZ0,0,P0,FZ0,P0)- ...
    cmmMFglobal(q,-h*180/pi,FZ0,0,P0,FZ0,P0))/(2*h);

peakMeasured=max(abs(refFY));
peakMF=max(abs(refCurve));
peakMuMeasured=peakMeasured/FZ0;
peakMuMF=peakMF/FZ0;

fprintf('[10] FINAL MODEL VALIDATION\n');
fprintf('Global R2         : %.6f\n',globalR2);
fprintf('Global RMSE       : %.3f N\n',globalRMSE);
fprintf('Global MAE        : %.3f N\n',globalMAE);
fprintf('Reference R2      : %.6f\n',refR2);
fprintf('Reference RMSE    : %.3f N\n',refRMSE);
fprintf('Reference C-alpha : %.3f N/deg\n',ca);
fprintf('Reference peak mu : measured %.4f / MF %.4f\n\n',peakMuMeasured,peakMuMF);

%% ---------------- CONDITION CHARACTERIZATION ----------------
measGrid=linspace(-12,12,481)';

loadGrid=[210 432 656 875 1096]';
muLoad=zeros(size(loadGrid)); caLoad=zeros(size(loadGrid));
for k=1:numel(loadGrid)
    fz=loadGrid(k);
    yy=cmmMFglobal(q,measGrid,fz,IA0,P0,FZ0,P0);
    muLoad(k)=max(abs(yy))/fz;
    caLoad(k)=(cmmMFglobal(q,h*180/pi,fz,0,P0,FZ0,P0)- ...
               cmmMFglobal(q,-h*180/pi,fz,0,P0,FZ0,P0))/(2*h);
end

pressureGrid=[8.1 10.1 12.1 14.1]';
muPressure=zeros(size(pressureGrid)); caPressure=zeros(size(pressureGrid));
for k=1:numel(pressureGrid)
    pp=pressureGrid(k);
    yy=cmmMFglobal(q,measGrid,FZ0,IA0,pp,FZ0,P0);
    muPressure(k)=max(abs(yy))/FZ0;
    caPressure(k)=(cmmMFglobal(q,h*180/pi,FZ0,0,pp,FZ0,P0)- ...
                   cmmMFglobal(q,-h*180/pi,FZ0,0,pp,FZ0,P0))/(2*h);
end

camberGrid=[0 2 4]';
muCamber=zeros(size(camberGrid)); caCamber=zeros(size(camberGrid));
for k=1:numel(camberGrid)
    gg=camberGrid(k);
    yy=cmmMFglobal(q,measGrid,FZ0,gg,P0,FZ0,P0);
    muCamber(k)=max(abs(yy))/FZ0;
    caCamber(k)=(cmmMFglobal(q,h*180/pi,FZ0,gg,P0,FZ0,P0)- ...
                 cmmMFglobal(q,-h*180/pi,FZ0,gg,P0,FZ0,P0))/(2*h);
end

%% ---------------- SAVE MODEL ----------------
Names={ ...
 'PCY1','PDY1','PDY2','PDY3','PEY1','PEY2', ...
 'PKY1','PKY2','PKY3','PHY1','PHY2','PHY3', ...
 'PVY1','PVY2','PVY3','PVY4','P_MU_1','P_MU_2','P_K_1'};

GlobalMF=struct();
GlobalMF.Version='CMM MF LATERAL GLOBAL v2.0';
GlobalMF.ModelType='Pure lateral / load + camber + pressure';
GlobalMF.InputCSV=INPUT_CSV;
GlobalMF.Contract.RequiredRuns=REQUIRED_RUNS;
GlobalMF.Contract.DevelopmentRun=FIT_RUNS;
GlobalMF.Contract.ValidationRun=VALID_RUNS;
GlobalMF.Contract.RimWidth_in=7.0;
GlobalMF.Contract.FYMultiplier=FY_SIGN_MULTIPLIER;
GlobalMF.Reference.Fz0_N=FZ0;
GlobalMF.Reference.P0_psi=P0;
GlobalMF.Reference.IA0_deg=IA0;
GlobalMF.Parameters=q;
GlobalMF.ParameterNames=Names;
GlobalMF.FixedCoefficients.PEY3=0;
GlobalMF.FixedCoefficients.PEY4=0;
GlobalMF.Metrics.Development.R2=devR2;
GlobalMF.Metrics.Development.RMSE_N=devRMSE;
GlobalMF.Metrics.Development.MAE_N=devMAE;
GlobalMF.Metrics.Holdout.Run4.R2=valR2;
GlobalMF.Metrics.Holdout.Run4.RMSE_N=valRMSE;
GlobalMF.Metrics.Holdout.Run4.MAE_N=valMAE;
GlobalMF.Metrics.Global.R2=globalR2;
GlobalMF.Metrics.Global.RMSE_N=globalRMSE;
GlobalMF.Metrics.Global.MAE_N=globalMAE;
GlobalMF.Metrics.Reference.R2=refR2;
GlobalMF.Metrics.Reference.RMSE_N=refRMSE;
GlobalMF.Metrics.Reference.MAE_N=refMAE;
GlobalMF.Metrics.Reference.Calpha_N_per_deg=ca;
GlobalMF.Metrics.Reference.PeakMu_MF=peakMuMF;
GlobalMF.Metrics.Reference.PeakMuMeasured=peakMuMeasured;
GlobalMF.MultiStart.SelectedStart=bestIdx;
GlobalMF.MultiStart.DevelopmentCosts=costs;
GlobalMF.MultiStart.DevelopmentExitFlags=flags;
GlobalMF.Envelope.Fz_N=[min(FZ) max(FZ)];
GlobalMF.Envelope.P_psi=[min(P) max(P)];
GlobalMF.Envelope.IA_deg=[min(IA) max(IA)];
GlobalMF.Envelope.SA_deg=[min(SA) max(SA)];
GlobalMF.Notes={'Pure lateral only'; ...
    'Runs 2+4, 7-inch rim contract'; ...
    'Run 2 development fit, Run 4 holdout validation'; ...
    'Final model refit on Runs 2+4 only after holdout pass'; ...
    'Pressure terms are CMM wrappers, not standard MF-Tyre .tir coefficients'; ...
    '.tir generation intentionally blocked in v2.0'};

save(fullfile(OUTDIR,'CMM_GLOBAL_MF_LATERAL_v2_0.mat'),'GlobalMF');

ParamTable=table(string(Names(:)),q(:),'VariableNames',{'Parameter','Value'});
writetable(ParamTable,fullfile(OUTDIR,'GLOBAL_MF_PARAMETERS_v2_0.csv'));

ValidationTable=table( ...
    ["Development_Run2";"Holdout_Run4";"Final_Global";"Reference"], ...
    [devR2;valR2;globalR2;refR2], ...
    [devRMSE;valRMSE;globalRMSE;refRMSE], ...
    [devMAE;valMAE;globalMAE;refMAE], ...
    'VariableNames',{'Set','R2','RMSE_N','MAE_N'});
writetable(ValidationTable,fullfile(OUTDIR,'VALIDATION_METRICS_v2_0.csv'));

%% ---------------- PLOTS ----------------
fprintf('[11] FIGURES\n');

fig=figure('Color','w','Name','CMM v2.0 Reference MF');
plot(abs(refA),abs(refFY),'.'); hold on;
plot(abs(alphaGrid),abs(refCurve),'LineWidth',2);
xlabel('|\alpha| [deg]'); ylabel('|F_y| [N]');
title(sprintf('Reference condition | R^2 = %.4f | RMSE = %.1f N',refR2,refRMSE));
legend('Measured','Final MF','Location','southeast'); grid on;
exportgraphics(fig,fullfile(OUTDIR,'01_REFERENCE_FINAL_MF.png'),'Resolution',180);
close(fig);

fig=figure('Color','w','Name','CMM v2.0 Holdout');
scatter(Xval(:,1),valErr,8,'filled'); hold on; yline(0,'--');
xlabel('\alpha [deg]'); ylabel('Run 4 measured - MF [N]');
title(sprintf('Run 4 Holdout Residual | R^2 = %.4f',valR2)); grid on;
exportgraphics(fig,fullfile(OUTDIR,'02_RUN4_HOLDOUT_RESIDUAL.png'),'Resolution',180);
close(fig);

fig=figure('Color','w','Name','CMM v2.0 Global');
scatter(Xglobal(:,1),Xglobal(:,5),8,'o'); hold on;
plot(measGrid,cmmMFglobal(q,measGrid,FZ0,IA0,P0,FZ0,P0),'LineWidth',2);
xlabel('\alpha [deg]'); ylabel('F_y [N]');
title(sprintf('Final Global Model | R^2 = %.4f',globalR2)); grid on;
legend('Binned Run 2+4 data','Reference-condition MF','Location','southeast');
exportgraphics(fig,fullfile(OUTDIR,'03_GLOBAL_DATA_FINAL_MF.png'),'Resolution',180);
close(fig);

fig=figure('Color','w','Name','CMM v2.0 Load');
yyaxis left; plot(loadGrid,muLoad,'-o','LineWidth',2); ylabel('\mu_{peak}');
yyaxis right; plot(loadGrid,caLoad,'-s','LineWidth',2); ylabel('C_\alpha [N/deg]');
xlabel('F_z [N]'); title('Final MF Load Sensitivity'); grid on;
exportgraphics(fig,fullfile(OUTDIR,'04_LOAD_SENSITIVITY_v2_0.png'),'Resolution',180);
close(fig);

fig=figure('Color','w','Name','CMM v2.0 Pressure');
yyaxis left; plot(pressureGrid,muPressure,'-o','LineWidth',2); ylabel('\mu_{peak}');
yyaxis right; plot(pressureGrid,caPressure,'-s','LineWidth',2); ylabel('C_\alpha [N/deg]');
xlabel('Pressure [psi]'); title('Final MF Pressure Sensitivity'); grid on;
exportgraphics(fig,fullfile(OUTDIR,'05_PRESSURE_SENSITIVITY_v2_0.png'),'Resolution',180);
close(fig);

fig=figure('Color','w','Name','CMM v2.0 Camber');
yyaxis left; plot(camberGrid,muCamber,'-o','LineWidth',2); ylabel('\mu_{peak}');
yyaxis right; plot(camberGrid,caCamber,'-s','LineWidth',2); ylabel('C_\alpha [N/deg]');
xlabel('Camber / IA [deg]'); title('Final MF Camber Sensitivity'); grid on;
exportgraphics(fig,fullfile(OUTDIR,'06_CAMBER_SENSITIVITY_v2_0.png'),'Resolution',180);
close(fig);

%% ---------------- AUDIT ----------------
fid=fopen(fullfile(OUTDIR,'GLOBAL_MF_AUDIT_REPORT_v2_0.txt'),'w');
fprintf(fid,'CMM MF LATERAL GLOBAL v2.0 AUDIT\n');
fprintf(fid,'================================\n');
fprintf(fid,'Input: %s\n',INPUT_CSV);
fprintf(fid,'Contract: 7-inch rim, Runs 2+4\n');
fprintf(fid,'Development: Run 2\n');
fprintf(fid,'Holdout validation: Run 4\n');
fprintf(fid,'FY multiplier: %+g\n',FY_SIGN_MULTIPLIER);
fprintf(fid,'Reference: Fz0=%.3f N, P0=%.3f psi, IA0=%.3f deg\n',FZ0,P0,IA0);
fprintf(fid,'\nDevelopment R2: %.8f\nDevelopment RMSE: %.6f N\nDevelopment MAE: %.6f N\n',devR2,devRMSE,devMAE);
fprintf(fid,'Holdout Run 4 R2: %.8f\nHoldout Run 4 RMSE: %.6f N\nHoldout Run 4 MAE: %.6f N\n',valR2,valRMSE,valMAE);
fprintf(fid,'Final Global R2: %.8f\nFinal Global RMSE: %.6f N\nFinal Global MAE: %.6f N\n',globalR2,globalRMSE,globalMAE);
fprintf(fid,'Reference R2: %.8f\nReference RMSE: %.6f N\nReference MAE: %.6f N\n',refR2,refRMSE,refMAE);
fprintf(fid,'Reference C-alpha: %.6f N/deg\n',ca);
fprintf(fid,'Reference measured peak mu: %.8f\nReference MF peak mu: %.8f\n',peakMuMeasured,peakMuMF);
fprintf(fid,'\nParameter list:\n');
for k=1:numel(q)
    fprintf(fid,'%s = %.12g\n',Names{k},q(k));
end
fprintf(fid,'\nFixed: PEY3=0, PEY4=0\n');
fprintf(fid,'Pressure terms are CMM wrappers and are not standard MF-Tyre .tir coefficients.\n');
fprintf(fid,'.tir generation: BLOCKED.\n');
fclose(fid);

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL GLOBAL v2.0 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Development R2     : %.6f\n',devR2);
fprintf('Run 4 holdout R2   : %.6f  [PASS]\n',valR2);
fprintf('Final global R2    : %.6f\n',globalR2);
fprintf('Reference R2       : %.6f\n',refR2);
fprintf('Reference C-alpha  : %.2f N/deg\n',ca);
fprintf('Reference peak mu  : %.4f\n',peakMuMF);
fprintf('Output             : %s\n',OUTDIR);
fprintf('.tir generation    : BLOCKED\n');
fprintf('============================================================\n');

end

%% ========================================================================
function result=runOneStart(q0,lb,ub,typicalX,obj)
result=[];
try
    opts=optimoptions('lsqnonlin', ...
        'Display','off', ...
        'MaxIterations',800, ...
        'MaxFunctionEvaluations',30000, ...
        'FunctionTolerance',1e-10, ...
        'StepTolerance',1e-10, ...
        'OptimalityTolerance',1e-8, ...
        'TypicalX',typicalX, ...
        'FiniteDifferenceType','forward');
    [q,resnorm,residual,exitflag,output]=lsqnonlin(obj,q0,lb,ub,opts);
    result.q=q;
    result.cost=resnorm;
    result.residual=residual;
    result.exitflag=exitflag;
    result.output=output;
    result.iterations=output.iterations;
catch
end
end

%% ========================================================================
function y=cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)
a=double(alphaDeg)*pi/180;
g=double(camberDeg)*pi/180;
Fz=max(double(Fz),1);
Ppsi=double(Ppsi);

dfz=(Fz-Fz0)./Fz0;
dP=Ppsi-P0;

PCY1=q(1);
PDY1=q(2); PDY2=q(3); PDY3=q(4);
PEY1=q(5); PEY2=q(6);
PKY1=q(7); PKY2=q(8); PKY3=q(9);
PHY1=q(10); PHY2=q(11); PHY3=q(12);
PVY1=q(13); PVY2=q(14); PVY3=q(15); PVY4=q(16);
Pmu1=q(17); Pmu2=q(18); Pk1=q(19);

Cy=PCY1;

mu=(PDY1+PDY2.*dfz).*(1-PDY3.*g.^2);
muP=1+Pmu1.*dP+Pmu2.*dP.^2;
mu=max(mu.*muP,0.20);
Dy=mu.*Fz;

Ey=max(-1.0,min(1.0,PEY1+PEY2.*dfz));

stiffCamber=max(0.10,1-PKY3.*g.^2);
Ky=PKY1.*Fz0.*sin(2.*atan(Fz./(PKY2.*Fz0))).*stiffCamber;
Ky=Ky.*(1+Pk1.*dP);
Ky=max(Ky,100);

By=Ky./max(Cy.*Dy,1);

Shy=PHY1+PHY2.*dfz+PHY3.*g;
Svy=Fz.*(PVY1+PVY2.*dfz)+mu.*Fz.*(PVY3+PVY4.*dfz).*g;

alphaY=a+Shy;
x=By.*alphaY;

y=Dy.*sin(Cy.*atan(x-Ey.*(x-atan(x))))+Svy;
end

%% ========================================================================
function r=globalResidual(q,a,fz,ia,p,fy,Fz0,P0)
pred=cmmMFglobal(q,a,fz,ia,p,Fz0,P0);
scale=max(fz,250);
r=(pred-fy)./scale;
r(~isfinite(r))=1e3;
end

%% ========================================================================
function X=binMedianData(A,da,dfz,dia,dp)
if isempty(A), X=A; return; end
k1=round(A(:,1)/da);
k2=round(A(:,2)/dfz);
k3=round(A(:,3)/dia);
k4=round(A(:,4)/dp);
[~,~,ic]=unique([k1 k2 k3 k4],'rows');
n=max(ic);
X=zeros(n,5);
for j=1:n
    m=(ic==j);
    X(j,1)=median(A(m,1),'omitnan');
    X(j,2)=median(A(m,2),'omitnan');
    X(j,3)=median(A(m,3),'omitnan');
    X(j,4)=median(A(m,4),'omitnan');
    X(j,5)=median(A(m,5),'omitnan');
end
X=X(all(isfinite(X),2),:);
end

%% ========================================================================
function tf=hasVariable(T,names)
vnames=string(T.Properties.VariableNames);
tf=false;
for k=1:numel(names)
    if any(strcmpi(vnames,string(names{k})))
        tf=true;
        return;
    end
end
end

%% ========================================================================
function x=getNumeric(T,names)
vnames=string(T.Properties.VariableNames);
idx=[];
for k=1:numel(names)
    m=find(strcmpi(vnames,string(names{k})),1);
    if ~isempty(m)
        idx=m; break;
    end
end
if isempty(idx)
    fprintf('\nAvailable table variables:\n');
    disp(vnames(:));
    error('Required variable not found. Tried: %s',strjoin(string(names),', '));
end
v=T{:,idx};
if iscell(v)
    v=str2double(string(v));
elseif isstring(v)||ischar(v)||iscategorical(v)
    v=str2double(string(v));
end
if ~isnumeric(v)
    error('Variable %s is not numeric.',vnames(idx));
end
x=double(v(:));
end

%% ========================================================================
function r2=calcR2(y,yhat)
den=sum((y-mean(y)).^2);
if den<=eps
    r2=NaN;
else
    r2=1-sum((y-yhat).^2)/den;
end
end
