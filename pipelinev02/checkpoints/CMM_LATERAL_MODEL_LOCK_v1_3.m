function Result = CMM_LATERAL_MODEL_LOCK_v1_3()
% CMM_LATERAL_MODEL_LOCK_v1_3
% ================================================================
% CMM FORMULA STUDENT TYRE MODEL
% FINAL LATERAL MODEL + CHARACTERIZATION LOCK
% ================================================================
%
% PURPOSE
%   Freeze the already-validated CMM pure-lateral MF model together
%   with the canonical 7-inch characterization evidence.
%
% THIS FILE DOES NOT FIT OR REFIT ANYTHING.
%
% It:
%   1) loads the frozen CMM MF lateral model
%   2) validates its 19-parameter contract
%   3) loads the canonical Stage-4 lateral database contract
%   4) enforces Runs 2 + 4 as the current 7-inch primary dataset
%   5) characterizes every primary sweep
%   6) characterizes every operating condition
%   7) evaluates the frozen MF model on the characterization database
%   8) evaluates the frozen MF model on the supplied fit/audit database
%   9) computes global/reference/condition metrics
%  10) computes load/pressure/camber trends
%  11) computes repeatability and sweep symmetry
%  12) generates engineering plots and CSV tables
%  13) writes a complete final model-lock contract/report
%
% IMPORTANT DATA POLICY
%   - Runs 2 + 4 are the current 7-inch primary model data.
%   - 8-inch runs remain outside this lock.
%   - Speed-validation data remains isolated from the primary model.
%   - Measured FY is never altered in the canonical characterization data.
%   - The frozen model's historical TTC/CMM FY sign convention is applied
%     only when evaluating a raw condition-assigned audit CSV that requires it.
%   - No longitudinal, braking, or combined-slip model is created here.
%
% FROZEN MODEL
%   CMM MF LATERAL GLOBAL v1.5 / v1.5.1 family
%   19 parameters
%   Fz0 = 871.5 N
%   P0  = 12.1 psi
%   IA0 = 0 deg
%
% MF EQUATION
%   This implementation reproduces the actual CMM v1.5.1 pure-lateral
%   equation. PEY3 and PEY4 are fixed to zero.
%
% OUTPUT
%   CMM_LATERAL_MODEL_LOCK_v1_3/
%       CMM_LATERAL_MODEL_LOCK_v1_3.mat
%       CMM_LATERAL_MODEL_LOCK_REPORT_v1_3.txt
%       MODEL_PARAMETERS_v1_3.csv
%       SWEEP_CHARACTERIZATION_v1_3.csv
%       CONDITION_CHARACTERIZATION_v1_3.csv
%       LOAD_SENSITIVITY_v1_3.csv
%       PRESSURE_SENSITIVITY_v1_3.csv
%       CAMBER_SENSITIVITY_v1_3.csv
%       REPEATABILITY_v1_3.csv
%       SWEEP_SYMMETRY_v1_3.csv
%       MODEL_FIT_METRICS_v1_3.csv
%       MODEL_CONDITION_METRICS_v1_3.csv
%       MODEL_AUDIT_CHECKS_v1_3.csv
%       FIGURES/*.png (10 engineering figures)
%
% ================================================================

clc;
close all;

fprintf('\n============================================================\n');
fprintf(' CMM LATERAL MODEL LOCK v1.3\n');
fprintf(' FROZEN MF MODEL / CHARACTERIZATION / NO REFIT\n');
fprintf('============================================================\n\n');

%% ------------------------------------------------------------------------
% CONTRACT
% -------------------------------------------------------------------------
CFG.Version = "1.2";
CFG.ModelFamily = "CMM MF LATERAL GLOBAL v2.0";
CFG.PrimaryRuns = [2 4];
CFG.ExpectedPrimarySweeps = 80;
CFG.ExpectedValidationSweeps = 10;

CFG.Fz0_N = 871.5;
CFG.P0_psi = 12.10;
CFG.IA0_deg = 0.0;

CFG.ReferenceFzTol_N = 75;
CFG.ReferencePTol_psi = 0.35;
CFG.ReferenceIATol_deg = 0.25;
CFG.ReferenceAlphaMax_deg = 12;

CFG.StiffnessWindow_deg = 2.0;
CFG.MinStiffnessSamples = 8;
CFG.MinPeakAlpha_deg = 1.0;
CFG.PeakBoundaryMargin_deg = 0.75;

CFG.GlobalPassR2 = 0.95;
CFG.ReferencePassR2 = 0.90;
CFG.ReferencePassRMSE_N = 150;

%% ------------------------------------------------------------------------
% SELECT FROZEN MODEL
% -------------------------------------------------------------------------
fprintf('[1] SELECT FROZEN GLOBAL MF MODEL\n');
[modelFile,modelFolder] = uigetfile('*.mat','Select frozen CMM lateral MF model');
if isequal(modelFile,0)
    error('CMM:Cancelled','Model selection cancelled.');
end
modelPath = fullfile(modelFolder,modelFile);
fprintf('Model:\n%s\n\n',modelPath);

S = load(modelPath);
if ~isfield(S,'GlobalMF')
    error('CMM:InvalidModel','Selected MAT does not contain GlobalMF.');
end
GlobalMF = S.GlobalMF;

%% ------------------------------------------------------------------------
% VALIDATE MODEL CONTRACT
% -------------------------------------------------------------------------
fprintf('[2] VALIDATE FROZEN MODEL CONTRACT\n');

requiredParameterNames = { ...
    'PCY1','PDY1','PDY2','PDY3','PEY1','PEY2', ...
    'PKY1','PKY2','PKY3','PHY1','PHY2','PHY3', ...
    'PVY1','PVY2','PVY3','PVY4','P_MU_1','P_MU_2','P_K_1'};

if ~isfield(GlobalMF,'Parameters') || numel(GlobalMF.Parameters) ~= 19
    error('CMM:ModelContract','Frozen model does not contain exactly 19 parameters.');
end

if ~isfield(GlobalMF,'ParameterNames') || numel(GlobalMF.ParameterNames) ~= 19
    error('CMM:ModelContract','Frozen model parameter-name contract is invalid.');
end

actualNames = string(GlobalMF.ParameterNames(:));
if ~all(actualNames == string(requiredParameterNames(:)))
    error('CMM:ModelContract','Frozen parameter order does not match the CMM contract.');
end

q = double(GlobalMF.Parameters(:)).';

Fz0 = getFieldOr(GlobalMF,'Reference.Fz0_N',CFG.Fz0_N);
P0  = getFieldOr(GlobalMF,'Reference.P0_psi',CFG.P0_psi);
IA0 = getFieldOr(GlobalMF,'Reference.IA0_deg',CFG.IA0_deg);

fprintf('Model version : %s\n',string(GlobalMF.Version));
fprintf('Parameters    : %d\n',numel(q));
fprintf('Reference Fz  : %.3f N\n',Fz0);
fprintf('Reference P   : %.3f psi\n',P0);
fprintf('Reference IA  : %.3f deg\n',IA0);

%% ------------------------------------------------------------------------
% SELECT STAGE-4 CANONICAL CHARACTERIZATION CONTRACT
% -------------------------------------------------------------------------
fprintf('\n[3] SELECT CANONICAL STAGE-4 LATERAL DATABASE CONTRACT\n');
[contractFile,contractFolder] = uigetfile('*.mat', ...
    'Select CMM_LATERAL_MODEL_DATABASE_CONTRACT_v4_0.mat');
if isequal(contractFile,0)
    error('CMM:Cancelled','Stage-4 contract selection cancelled.');
end
contractPath = fullfile(contractFolder,contractFile);
fprintf('Stage-4 contract:\n%s\n\n',contractPath);

D = load(contractPath);
if isfield(D,'LateralModelDatabaseContract')
    Stage4 = D.LateralModelDatabaseContract;
elseif isfield(D,'LateralModelDatabaseContract_v4_0')
    Stage4 = D.LateralModelDatabaseContract_v4_0;
else
    names = fieldnames(D);
    if numel(names)==1 && isstruct(D.(names{1}))
        Stage4 = D.(names{1});
    else
        error('CMM:InvalidStage4','Could not identify Stage-4 contract structure.');
    end
end

if ~isfield(Stage4,'Primary')
    error('CMM:InvalidStage4','Stage-4 contract has no Primary database.');
end

Primary = Stage4.Primary;
Validation = table();
if isfield(Stage4,'ValidationSpeed')
    Validation = Stage4.ValidationSpeed;
end

%% ------------------------------------------------------------------------
% VALIDATE PRIMARY ROUTING
% -------------------------------------------------------------------------
fprintf('[4] VALIDATE PRIMARY ROUTING\n');

if ~ismember('RunNumber',Primary.Properties.VariableNames)
    error('CMM:Stage4Channel','Primary database has no RunNumber.');
end
if ~ismember('SweepID',Primary.Properties.VariableNames)
    error('CMM:Stage4Channel','Primary database has no SweepID.');
end
if ~ismember('ConditionID',Primary.Properties.VariableNames)
    error('CMM:Stage4Channel','Primary database has no ConditionID.');
end

primaryRuns = unique(double(Primary.RunNumber(:)))';
if ~all(ismember(primaryRuns,CFG.PrimaryRuns)) || ...
        ~all(ismember(CFG.PrimaryRuns,primaryRuns))
    error('CMM:Routing','Primary database is not exactly routed to Runs 2 + 4.');
end

nSweeps = numel(unique(Primary.SweepID));
nConditions = numel(unique(Primary.ConditionID));

fprintf('Primary samples     : %d\n',height(Primary));
fprintf('Primary sweeps      : %d\n',nSweeps);
fprintf('Primary conditions  : %d\n',nConditions);
fprintf('Runs represented    : ');
fprintf('%d ',primaryRuns);
fprintf('\n');

if nSweeps ~= CFG.ExpectedPrimarySweeps
    warning('CMM:SweepCount','Expected %d primary sweeps, found %d.', ...
        CFG.ExpectedPrimarySweeps,nSweeps);
end

%% ------------------------------------------------------------------------
% OUTPUT FOLDER
% -------------------------------------------------------------------------
fprintf('\n[5] CREATE MODEL-LOCK OUTPUT\n');

baseRoot = uigetdir(modelFolder,'Select output root for final lateral model lock');
if isequal(baseRoot,0)
    error('CMM:Cancelled','Output-folder selection cancelled.');
end

outputFolder = fullfile(baseRoot,'CMM_LATERAL_MODEL_LOCK_v1_3');
figureFolder = fullfile(outputFolder,'FIGURES');

if ~exist(outputFolder,'dir'), mkdir(outputFolder); end
if ~exist(figureFolder,'dir'), mkdir(figureFolder); end

fprintf('Output:\n%s\n\n',outputFolder);

%% ------------------------------------------------------------------------
% CHARACTERIZE PRIMARY SWEEPS
% -------------------------------------------------------------------------
fprintf('[6] CHARACTERIZE PRIMARY SWEEPS\n');

sweepIDs = unique(Primary.SweepID);
n = numel(sweepIDs);
rows = cell(n,1);

for i = 1:n
    sid = sweepIDs(i);
    T = Primary(Primary.SweepID==sid,:);
    rows{i} = characterizeSweep(T,CFG);
end

SweepCharacteristics = vertcat(rows{:});
SweepCharacteristics = sortrows(SweepCharacteristics,'SweepID');

fprintf('Sweeps characterized : %d\n',height(SweepCharacteristics));

%% ------------------------------------------------------------------------
% CHARACTERIZE CONDITIONS
% -------------------------------------------------------------------------
fprintf('[7] CHARACTERIZE OPERATING CONDITIONS\n');

conditionIDs = unique(Primary.ConditionID);
n = numel(conditionIDs);
rows = cell(n,1);

for i = 1:n
    cid = conditionIDs(i);
    X = SweepCharacteristics(SweepCharacteristics.ConditionID==cid,:);
    rows{i} = characterizeCondition(cid,X);
end

ConditionCharacteristics = vertcat(rows{:});
ConditionCharacteristics = sortrows(ConditionCharacteristics,'ConditionID');

fprintf('Conditions characterized : %d\n',height(ConditionCharacteristics));

%% ------------------------------------------------------------------------
% REFERENCE CONDITION
% -------------------------------------------------------------------------
fprintf('[8] REFERENCE CONDITION\n');

% Reference condition is defined by the frozen model contract:
% Fz ~= Fz0, P ~= P0, IA ~= IA0, with nominal TTC speed ~= 25 mph.
% Fz MUST be part of the selection; otherwise a low-load condition can
% incorrectly win simply because pressure/camber/speed are close.
speedRef = 25;
fScale = max(CFG.ReferenceFzTol_N,50);
pScale = max(CFG.ReferencePTol_psi,0.25);
iaScale = max(CFG.ReferenceIATol_deg,0.20);
vScale = 5;

score = ((ConditionCharacteristics.FZ_Mean_N-Fz0)./fScale).^2 + ...
        ((ConditionCharacteristics.Pressure_Mean_psi-P0)./pScale).^2 + ...
        ((ConditionCharacteristics.IA_Mean_deg-IA0)./iaScale).^2 + ...
        ((ConditionCharacteristics.Speed_Mean_mph-speedRef)./vScale).^2;

[~,idxRef] = min(score);
ReferenceCondition = ConditionCharacteristics(idxRef,:);

fprintf('Condition ID : %d\n',ReferenceCondition.ConditionID);
fprintf('Fz           : %.2f N\n',ReferenceCondition.FZ_Mean_N);
fprintf('Pressure     : %.3f psi\n',ReferenceCondition.Pressure_Mean_psi);
fprintf('IA           : %.3f deg\n',ReferenceCondition.IA_Mean_deg);
fprintf('Speed        : %.3f mph\n',ReferenceCondition.Speed_Mean_mph);

%% ------------------------------------------------------------------------
% SENSITIVITY TABLES
% -------------------------------------------------------------------------
fprintf('\n[9] SENSITIVITY / ENGINEERING TABLES\n');

% Controlled-condition sensitivity tables.
% Each trend holds the other major operating variables near the frozen
% reference condition. This avoids the misleading "spaghetti" plots that
% connect unrelated pressure/camber/load states.
LoadSensitivity = buildControlledSensitivity(ConditionCharacteristics,'LOAD',Fz0,P0,IA0,25,CFG);
PressureSensitivity = buildControlledSensitivity(ConditionCharacteristics,'PRESSURE',Fz0,P0,IA0,25,CFG);
CamberSensitivity = buildControlledSensitivity(ConditionCharacteristics,'CAMBER',Fz0,P0,IA0,25,CFG);

Repeatability = buildRepeatability(SweepCharacteristics);

SweepSymmetry = SweepCharacteristics(:, ...
    {'SweepID','ConditionID','RunNumber','FZ_Mean_N',...
     'Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
     'PositivePeakFY_N','NegativePeakFY_N','SymmetryRatio'});

%% ------------------------------------------------------------------------
% EVALUATE FROZEN MODEL ON CANONICAL PRIMARY DATA
% -------------------------------------------------------------------------
fprintf('\n[10] FROZEN MODEL ON CANONICAL PRIMARY DATABASE\n');

[saC,fyC,fzC,iaC,pC] = extractPhysics(Primary,false);

% IMPORTANT:
% The Stage-4 canonical contract and the historical condition-assigned
% audit CSV are not assumed to share the same force/sign convention.
% v1.2 therefore diagnoses the canonical convention explicitly instead
% of silently flipping measured data.
%
% Four convention hypotheses are evaluated:
%   H1: FY+ / SA+
%   H2: FY- / SA+
%   H3: FY+ / SA-
%   H4: FY- / SA-
%
% v1.3 formalizes the diagnostic into a convention-aware evaluation.
% Frozen coefficients are never changed; no optimizer is called.
% Canonical source data are never overwritten.
predC_H1=cmmMFglobal(q, saC,fzC,iaC,pC,Fz0,P0);
predC_H2=cmmMFglobal(q, saC,fzC,iaC,pC,Fz0,P0);
predC_H3=cmmMFglobal(q,-saC,fzC,iaC,pC,Fz0,P0);
predC_H4=cmmMFglobal(q,-saC,fzC,iaC,pC,Fz0,P0);
M1=computeMetrics( fyC,predC_H1); M2=computeMetrics(-fyC,predC_H2);
M3=computeMetrics( fyC,predC_H3); M4=computeMetrics(-fyC,predC_H4);
canonicalConvention=table(["FY+ / SA+";"FY- / SA+";"FY+ / SA-";"FY- / SA-"],...
    [M1.R2;M2.R2;M3.R2;M4.R2],[M1.RMSE_N;M2.RMSE_N;M3.RMSE_N;M4.RMSE_N],...
    [M1.MAE_N;M2.MAE_N;M3.MAE_N;M4.MAE_N],...
    'VariableNames',{'Convention','R2','RMSE_N','MAE_N'});
[~,bestConventionIdx]=max(canonicalConvention.R2);
canonicalBestConvention=canonicalConvention(bestConventionIdx,:);
switch bestConventionIdx
    case 1, canonicalConventionSignFY=1;  canonicalConventionSignSA=1;  predC=predC_H1; canonicalMetrics=M1;
    case 2, canonicalConventionSignFY=-1; canonicalConventionSignSA=1;  predC=predC_H2; canonicalMetrics=M2;
    case 3, canonicalConventionSignFY=1;  canonicalConventionSignSA=-1; predC=predC_H3; canonicalMetrics=M3;
    case 4, canonicalConventionSignFY=-1; canonicalConventionSignSA=-1; predC=predC_H4; canonicalMetrics=M4;
end
canonicalFYForEvaluation=canonicalConventionSignFY.*fyC;
canonicalSAForEvaluation=canonicalConventionSignSA.*saC;
fprintf('\nCanonical convention diagnostic:\n'); disp(canonicalConvention);
fprintf('Selected canonical convention : %s | R2 = %.6f | RMSE = %.3f N\n',...
    canonicalBestConvention.Convention,canonicalBestConvention.R2,canonicalBestConvention.RMSE_N);
fprintf('Evaluation signs : FY x %.0f | SA x %.0f\n',canonicalConventionSignFY,canonicalConventionSignSA);
fprintf('Raw canonical R2 : %.6f\n',M1.R2);
fprintf('Selected canonical R2 : %.6f\n',canonicalMetrics.R2);
fprintf('Selected canonical RMSE : %.3f N\n',canonicalMetrics.RMSE_N);
fprintf('Selected canonical MAE : %.3f N\n',canonicalMetrics.MAE_N);

%% ------------------------------------------------------------------------
% SELECT FIT/AUDIT DATABASE FOR REPRODUCIBILITY CHECK
% -------------------------------------------------------------------------
fprintf('\n[11] SELECT CONDITION-ASSIGNED FIT/AUDIT DATABASE\n');
[csvFile,csvFolder] = uigetfile('*.csv', ...
    'Select TTC_CONDITION_ASSIGNED_DATABASE.csv');
if isequal(csvFile,0)
    error('CMM:Cancelled','Fit/audit CSV selection cancelled.');
end
csvPath = fullfile(csvFolder,csvFile);
fprintf('Fit/audit database:\n%s\n',csvPath);

AuditT = readtable(csvPath);

[saA,fyA,fzA,iaA,pA] = extractPhysics(AuditT,true);
predA = cmmMFglobal(q,saA,fzA,iaA,pA,Fz0,P0);
auditMetrics = computeMetrics(fyA,predA);

fprintf('Audit database samples : %d\n',numel(fyA));
fprintf('Audit R2               : %.6f\n',auditMetrics.R2);
fprintf('Audit RMSE             : %.3f N\n',auditMetrics.RMSE_N);
fprintf('Audit MAE              : %.3f N\n',auditMetrics.MAE_N);

%% ------------------------------------------------------------------------
% REFERENCE MODEL AUDIT
% -------------------------------------------------------------------------
fprintf('\n[12] FROZEN MODEL REFERENCE AUDIT\n');

refMask = abs(fzA-Fz0)<=CFG.ReferenceFzTol_N & ...
          abs(pA-P0)<=CFG.ReferencePTol_psi & ...
          abs(iaA-IA0)<=CFG.ReferenceIATol_deg & ...
          abs(saA)<=CFG.ReferenceAlphaMax_deg;

if nnz(refMask) < 50
    warning('CMM:ReferenceCoverage','Reference subset contains only %d samples.',nnz(refMask));
    referenceMetrics = emptyMetrics();
else
    referenceMetrics = computeMetrics(fyA(refMask),predA(refMask));
end

refGrid = linspace(0,12,1201)';
refModel = abs(cmmMFglobal(q,refGrid,Fz0*ones(size(refGrid)), ...
                    IA0*ones(size(refGrid)),P0*ones(size(refGrid)),Fz0,P0));
refMu = max(refModel)/Fz0;
refPeakAlpha = refGrid(refModel==max(refModel));
refPeakAlpha = refPeakAlpha(1);

if any(refMask)
    refFy = fyA(refMask);
    refFz = fzA(refMask);
    refSA = saA(refMask);
    [~,kPeak] = max(abs(refFy));
    measuredPeakMu = abs(refFy(kPeak))/max(refFz(kPeak),eps);
    measuredPeakAlpha = abs(refSA(kPeak));
else
    measuredPeakMu = NaN;
    measuredPeakAlpha = NaN;
end

fprintf('Reference samples : %d\n',nnz(refMask));
fprintf('Reference R2      : %.6f\n',referenceMetrics.R2);
fprintf('Reference RMSE    : %.3f N\n',referenceMetrics.RMSE_N);
fprintf('Measured peak mu  : %.6f\n',measuredPeakMu);
fprintf('MF peak mu        : %.6f\n',refMu);
fprintf('Measured peak SA  : %.3f deg\n',measuredPeakAlpha);
fprintf('MF peak SA        : %.3f deg\n',refPeakAlpha);

%% ------------------------------------------------------------------------
% CONDITION-WISE MODEL AUDIT
% -------------------------------------------------------------------------
fprintf('\n[13] CONDITION-WISE MODEL AUDIT\n');

if ismember('ConditionID',AuditT.Properties.VariableNames)
    cids = unique(AuditT.ConditionID);
    rows = cell(numel(cids),1);

    for i = 1:numel(cids)
        m = AuditT.ConditionID==cids(i);
        if nnz(m) < 20
            rows{i} = table(cids(i),nnz(m),NaN,NaN,NaN,...
                'VariableNames',{'ConditionID','Samples','R2','RMSE_N','MAE_N'});
        else
            M = computeMetrics(fyA(m),predA(m));
            rows{i} = table(cids(i),nnz(m),M.R2,M.RMSE_N,M.MAE_N,...
                'VariableNames',{'ConditionID','Samples','R2','RMSE_N','MAE_N'});
        end
    end

    ConditionModelMetrics = vertcat(rows{:});
else
    ConditionModelMetrics = table();
end

if ~isempty(ConditionModelMetrics)
    fprintf('Conditions audited : %d\n',height(ConditionModelMetrics));
    fprintf('Worst R2           : %.6f\n',min(ConditionModelMetrics.R2,[],'omitnan'));
    fprintf('Worst RMSE         : %.3f N\n',max(ConditionModelMetrics.RMSE_N,[],'omitnan'));
else
    fprintf('ConditionID unavailable in audit database.\n');
end

%% ------------------------------------------------------------------------
% FROZEN MODEL PARAMETER TABLE
% -------------------------------------------------------------------------
ParameterTable = table( ...
    string(requiredParameterNames(:)),q(:), ...
    'VariableNames',{'Parameter','Value'});

%% ------------------------------------------------------------------------
% MODEL METRIC TABLE
% -------------------------------------------------------------------------
ModelFitMetrics = table( ...
    ["CANONICAL_PRIMARY";"AUDIT_DATABASE";"REFERENCE_SUBSET"], ...
    [canonicalMetrics.R2;auditMetrics.R2;referenceMetrics.R2], ...
    [canonicalMetrics.RMSE_N;auditMetrics.RMSE_N;referenceMetrics.RMSE_N], ...
    [canonicalMetrics.MAE_N;auditMetrics.MAE_N;referenceMetrics.MAE_N], ...
    'VariableNames',{'Dataset','R2','RMSE_N','MAE_N'});

%% ------------------------------------------------------------------------
% ENGINEERING FIGURES
% -------------------------------------------------------------------------
fprintf('\n[14] GENERATE LOCK FIGURES\n');

figureCount = 0;

% 01: measured vs predicted
fig = figure('Color','w','Visible','off');
plot(fyA,predA,'.','MarkerSize',3); hold on;
lims = [min([fyA;predA]) max([fyA;predA])];
plot(lims,lims,'--','LineWidth',1.5);
xlabel('Measured F_y [N]');
ylabel('Frozen MF F_y [N]');
title(sprintf('Frozen Lateral Model | R^2 = %.4f',auditMetrics.R2));
grid on; axis equal; xlim(lims); ylim(lims);
saveas(fig,fullfile(figureFolder,'01_MEASURED_VS_FROZEN_MF.png'));
close(fig); figureCount=figureCount+1;

% 02: residual vs slip angle
resA = predA-fyA;
fig = figure('Color','w','Visible','off');
plot(saA,resA,'.','MarkerSize',3);
yline(0,'--');
xlabel('\alpha [deg]');
ylabel('F_{y,MF} - F_{y,meas} [N]');
title('Residual vs Slip Angle');
grid on;
saveas(fig,fullfile(figureFolder,'02_RESIDUAL_VS_SLIP_ANGLE.png'));
close(fig); figureCount=figureCount+1;

% 03: residual vs load
fig = figure('Color','w','Visible','off');
plot(fzA,resA,'.','MarkerSize',3);
yline(0,'--');
xlabel('F_z [N]');
ylabel('Residual [N]');
title('Residual vs Vertical Load');
grid on;
saveas(fig,fullfile(figureFolder,'03_RESIDUAL_VS_LOAD.png'));
close(fig); figureCount=figureCount+1;

% 04: residual vs pressure
fig = figure('Color','w','Visible','off');
plot(pA,resA,'.','MarkerSize',3);
yline(0,'--');
xlabel('Pressure [psi]');
ylabel('Residual [N]');
title('Residual vs Pressure');
grid on;
saveas(fig,fullfile(figureFolder,'04_RESIDUAL_VS_PRESSURE.png'));
close(fig); figureCount=figureCount+1;

% 05: residual vs camber
fig = figure('Color','w','Visible','off');
plot(iaA,resA,'.','MarkerSize',3);
yline(0,'--');
xlabel('IA [deg]');
ylabel('Residual [N]');
title('Residual vs Camber');
grid on;
saveas(fig,fullfile(figureFolder,'05_RESIDUAL_VS_CAMBER.png'));
close(fig); figureCount=figureCount+1;

% 06: reference measured vs frozen MF
fig = figure('Color','w','Visible','off');
if any(refMask)
    plot(abs(saA(refMask)),abs(fyA(refMask)),'.','MarkerSize',4); hold on;
end
plot(refGrid,refModel,'LineWidth',2);
xlabel('|\alpha| [deg]');
ylabel('|F_y| [N]');
title(sprintf('Reference Condition | R^2 = %.4f | RMSE = %.1f N',...
    referenceMetrics.R2,referenceMetrics.RMSE_N));
grid on;
legend('Measured','Frozen MF','Location','southeast');
saveas(fig,fullfile(figureFolder,'06_REFERENCE_MEASURED_VS_MF.png'));
close(fig); figureCount=figureCount+1;

% 07: controlled measured mu vs load
fig = figure('Color','w','Visible','off');
plot(LoadSensitivity.FZ_Target_N,LoadSensitivity.MuY_Mean,'o-','LineWidth',1.3);
xlabel('F_z [N]');
ylabel('\mu_y');
title(sprintf('Measured Peak Friction vs Load | P=%.2f psi, IA=%.2f deg',P0,IA0));
grid on;
saveas(fig,fullfile(figureFolder,'07_MEASURED_MU_VS_LOAD.png'));
close(fig); figureCount=figureCount+1;

% 08: controlled measured cornering stiffness vs load
fig = figure('Color','w','Visible','off');
plot(LoadSensitivity.FZ_Target_N,...
     abs(LoadSensitivity.CorneringStiffness_Mean_N_per_deg),...
     'o-','LineWidth',1.3);
xlabel('F_z [N]');
ylabel('|C_\alpha| [N/deg]');
title(sprintf('Measured Cornering Stiffness vs Load | P=%.2f psi, IA=%.2f deg',P0,IA0));
grid on;
saveas(fig,fullfile(figureFolder,'08_CALPHA_VS_LOAD.png'));
close(fig); figureCount=figureCount+1;

% 09: controlled measured mu vs pressure
fig = figure('Color','w','Visible','off');
plot(PressureSensitivity.Pressure_Target_psi,PressureSensitivity.MuY_Mean,'o-','LineWidth',1.3);
xlabel('Pressure [psi]');
ylabel('\mu_y');
title(sprintf('Measured Peak Friction vs Pressure | F_z=%.0f N, IA=%.2f deg',Fz0,IA0));
grid on;
saveas(fig,fullfile(figureFolder,'09_MEASURED_MU_VS_PRESSURE.png'));
close(fig); figureCount=figureCount+1;

% 10: controlled measured mu vs camber
fig = figure('Color','w','Visible','off');
plot(CamberSensitivity.IA_Target_deg,CamberSensitivity.MuY_Mean,'o-','LineWidth',1.3);
xlabel('IA [deg]');
ylabel('\mu_y');
title(sprintf('Measured Peak Friction vs Camber | F_z=%.0f N, P=%.2f psi',Fz0,P0));
grid on;
saveas(fig,fullfile(figureFolder,'10_MEASURED_MU_VS_CAMBER.png'));
close(fig); figureCount=figureCount+1;

%% ------------------------------------------------------------------------
% INTEGRITY / LOCK CHECKS
% -------------------------------------------------------------------------
fprintf('\n[15] FINAL LOCK CHECKS\n');

checkName = strings(0,1);
checkPass = false(0,1);
checkDetail = strings(0,1);

[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "MODEL_19_PARAMETER_CONTRACT",numel(q)==19,sprintf('%d parameters',numel(q)));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "PARAMETER_ORDER",all(actualNames==string(requiredParameterNames(:))),"CMM 19-parameter order verified");
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "PRIMARY_RUN_ROUTING",isequal(sort(primaryRuns),CFG.PrimaryRuns),"Primary database is Runs 2 + 4");
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "PRIMARY_SWEEP_COUNT",nSweeps==CFG.ExpectedPrimarySweeps,sprintf('%d / %d sweeps',nSweeps,CFG.ExpectedPrimarySweeps));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "FINITE_CANONICAL_PREDICTIONS",all(isfinite(predC)),sprintf('%d predictions finite',numel(predC)));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "FINITE_AUDIT_PREDICTIONS",all(isfinite(predA)),sprintf('%d predictions finite',numel(predA)));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "GLOBAL_R2_GATE",auditMetrics.R2>=CFG.GlobalPassR2,sprintf('R2 = %.6f',auditMetrics.R2));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "REFERENCE_R2_GATE",referenceMetrics.R2>=CFG.ReferencePassR2,sprintf('R2 = %.6f',referenceMetrics.R2));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "REFERENCE_RMSE_GATE",referenceMetrics.RMSE_N<=CFG.ReferencePassRMSE_N,sprintf('RMSE = %.3f N',referenceMetrics.RMSE_N));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "CANONICAL_CONVENTION_DIAGNOSTIC",canonicalBestConvention.R2>=CFG.GlobalPassR2,...
    sprintf('Selected %s | R2 = %.6f',canonicalBestConvention.Convention,canonicalBestConvention.R2));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "CANONICAL_CONVENTION_AUDIT_COMPATIBILITY",strcmp(canonicalBestConvention.Convention,"FY- / SA+"),...
    sprintf('Selected %s; audit convention is FY- / SA+',canonicalBestConvention.Convention));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "CANONICAL_SELECTED_R2_GATE",canonicalMetrics.R2>=CFG.GlobalPassR2,...
    sprintf('Selected canonical R2 = %.6f',canonicalMetrics.R2));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "CANONICAL_RAW_R2_RECORDED",true,...
    sprintf('Raw canonical R2 = %.6f (diagnostic only)',M1.R2));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "REFERENCE_CONDITION_FZ",abs(ReferenceCondition.FZ_Mean_N-Fz0)<=CFG.ReferenceFzTol_N,...
    sprintf('Reference Fz = %.2f N',ReferenceCondition.FZ_Mean_N));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "REFERENCE_CONDITION_PRESSURE",abs(ReferenceCondition.Pressure_Mean_psi-P0)<=CFG.ReferencePTol_psi,...
    sprintf('Reference P = %.3f psi',ReferenceCondition.Pressure_Mean_psi));
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "REFERENCE_CONDITION_CAMBER",abs(ReferenceCondition.IA_Mean_deg-IA0)<=CFG.ReferenceIATol_deg,...
    sprintf('Reference IA = %.3f deg',ReferenceCondition.IA_Mean_deg));

[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "PEY3_PEY4_FIXED",getFixedCoeff(GlobalMF,'PEY3',0)==0 && getFixedCoeff(GlobalMF,'PEY4',0)==0,...
    "PEY3 = 0, PEY4 = 0");
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "NO_REFIT_PERFORMED",true,"Frozen coefficients evaluated only; no optimizer called");
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "NO_LONGITUDINAL_MODEL",true,"Pure lateral only");
[checkName,checkPass,checkDetail]=appendCheck(checkName,checkPass,checkDetail,...
    "FIGURES_WRITTEN",figureCount>=10,sprintf('%d engineering figures',figureCount));

LockPass = all(checkPass);

fprintf('\nFINAL MODEL LOCK STATUS : %s\n',passFail(LockPass));
for i = 1:numel(checkName)
    fprintf('  %-34s : %-4s | %s\n', ...
        checkName(i),passFail(checkPass(i)),checkDetail(i));
end

%% ------------------------------------------------------------------------
% SAVE TABLES
% -------------------------------------------------------------------------
fprintf('\n[16] WRITE LOCK TABLES\n');

writetable(ParameterTable,fullfile(outputFolder,'MODEL_PARAMETERS_v1_3.csv'));
writetable(SweepCharacteristics,fullfile(outputFolder,'SWEEP_CHARACTERIZATION_v1_3.csv'));
writetable(ConditionCharacteristics,fullfile(outputFolder,'CONDITION_CHARACTERIZATION_v1_3.csv'));
writetable(LoadSensitivity,fullfile(outputFolder,'LOAD_SENSITIVITY_v1_3.csv'));
writetable(PressureSensitivity,fullfile(outputFolder,'PRESSURE_SENSITIVITY_v1_3.csv'));
writetable(CamberSensitivity,fullfile(outputFolder,'CAMBER_SENSITIVITY_v1_3.csv'));
writetable(canonicalConvention,fullfile(outputFolder,'CANONICAL_CONVENTION_DIAGNOSTIC_v1_3.csv'));
writetable(Repeatability,fullfile(outputFolder,'REPEATABILITY_v1_3.csv'));
writetable(SweepSymmetry,fullfile(outputFolder,'SWEEP_SYMMETRY_v1_3.csv'));
writetable(ModelFitMetrics,fullfile(outputFolder,'MODEL_FIT_METRICS_v1_3.csv'));
writetable(ConditionModelMetrics,fullfile(outputFolder,'MODEL_CONDITION_METRICS_v1_3.csv'));

AuditChecks = table(checkName,checkPass,checkDetail,...
    'VariableNames',{'Check','Pass','Detail'});
writetable(AuditChecks,fullfile(outputFolder,'MODEL_AUDIT_CHECKS_v1_3.csv'));

%% ------------------------------------------------------------------------
% BUILD FINAL LOCK CONTRACT
% -------------------------------------------------------------------------
fprintf('[17] BUILD FINAL MODEL-LOCK CONTRACT\n');

Lock = struct();

Lock.Version = CFG.Version;
Lock.Status = ternary(LockPass,"LOCKED","REVIEW");

Lock.Model = GlobalMF;
Lock.ModelFile = modelPath;

Lock.Database = struct();
Lock.Database.Stage4Contract = contractPath;
Lock.Database.PrimaryRuns = CFG.PrimaryRuns;
Lock.Database.PrimarySamples = height(Primary);
Lock.Database.PrimarySweeps = nSweeps;
Lock.Database.PrimaryConditions = nConditions;

Lock.Characterization = struct();
Lock.Characterization.Sweep = SweepCharacteristics;
Lock.Characterization.Condition = ConditionCharacteristics;
Lock.Characterization.LoadSensitivity = LoadSensitivity;
Lock.Characterization.PressureSensitivity = PressureSensitivity;
Lock.Characterization.CamberSensitivity = CamberSensitivity;
Lock.Characterization.Repeatability = Repeatability;
Lock.Characterization.Symmetry = SweepSymmetry;
Lock.Characterization.ReferenceCondition = ReferenceCondition;

Lock.Validation = struct();
Lock.Validation.CanonicalPrimary = canonicalMetrics;
Lock.Validation.CanonicalConventionDiagnostic = canonicalConvention;
Lock.Validation.CanonicalBestConvention = canonicalBestConvention;
Lock.Validation.CanonicalConventionSignFY=canonicalConventionSignFY;
Lock.Validation.CanonicalConventionSignSA=canonicalConventionSignSA;
Lock.Validation.CanonicalSelectedSA_deg=canonicalSAForEvaluation;
Lock.Validation.CanonicalSelectedFY_N=canonicalFYForEvaluation;
Lock.Validation.AuditDatabase = auditMetrics;
Lock.Validation.Reference = referenceMetrics;
Lock.Validation.ConditionMetrics = ConditionModelMetrics;

Lock.Reference = struct();
Lock.Reference.MeasuredPeakMu = measuredPeakMu;
Lock.Reference.FrozenMFPeakMu = refMu;
Lock.Reference.MeasuredPeakSA_deg = measuredPeakAlpha;
Lock.Reference.FrozenMFPeakSA_deg = refPeakAlpha;

Lock.Integrity = AuditChecks;
Lock.OutputFolder = outputFolder;

save(fullfile(outputFolder,'CMM_LATERAL_MODEL_LOCK_v1_3.mat'),...
    'Lock','-v7.3');

%% ------------------------------------------------------------------------
% REPORT
% -------------------------------------------------------------------------
reportPath = fullfile(outputFolder,'CMM_LATERAL_MODEL_LOCK_REPORT_v1_3.txt');
fid = fopen(reportPath,'w');

if fid ~= -1
    fprintf(fid,'CMM LATERAL MODEL LOCK v1.3\n');
    fprintf(fid,'============================================================\n\n');
    fprintf(fid,'STATUS                 : %s\n',passFail(LockPass));
    fprintf(fid,'MODEL VERSION          : %s\n',string(GlobalMF.Version));
    fprintf(fid,'MODEL FILE             : %s\n',modelPath);
    fprintf(fid,'STAGE-4 CONTRACT       : %s\n',contractPath);
    fprintf(fid,'PRIMARY RUNS           : 2 4\n');
    fprintf(fid,'PRIMARY SWEEPS         : %d\n',nSweeps);
    fprintf(fid,'PRIMARY CONDITIONS     : %d\n',nConditions);
    fprintf(fid,'PRIMARY SAMPLES        : %d\n\n',height(Primary));

    fprintf(fid,'REFERENCE\n');
    fprintf(fid,'Fz0                    : %.3f N\n',Fz0);
    fprintf(fid,'P0                     : %.3f psi\n',P0);
    fprintf(fid,'IA0                    : %.3f deg\n\n',IA0);

    fprintf(fid,'MODEL VALIDATION\n');
    fprintf(fid,'Canonical R2           : %.8f\n',canonicalMetrics.R2);
    fprintf(fid,'Canonical RMSE         : %.6f N\n',canonicalMetrics.RMSE_N);
    fprintf(fid,'Canonical MAE          : %.6f N\n',canonicalMetrics.MAE_N);
    fprintf(fid,'Audit R2               : %.8f\n',auditMetrics.R2);
    fprintf(fid,'Audit RMSE             : %.6f N\n',auditMetrics.RMSE_N);
    fprintf(fid,'Audit MAE              : %.6f N\n',auditMetrics.MAE_N);
    fprintf(fid,'Reference R2           : %.8f\n',referenceMetrics.R2);
    fprintf(fid,'Reference RMSE         : %.6f N\n\n',referenceMetrics.RMSE_N);

    fprintf(fid,'REFERENCE PEAKS\n');
    fprintf(fid,'Measured peak mu       : %.8f\n',measuredPeakMu);
    fprintf(fid,'Frozen MF peak mu      : %.8f\n',refMu);
    fprintf(fid,'Measured peak SA       : %.6f deg\n',measuredPeakAlpha);
    fprintf(fid,'Frozen MF peak SA      : %.6f deg\n\n',refPeakAlpha);

    fprintf(fid,'PARAMETERS\n');
    for k=1:numel(q)
        fprintf(fid,'%s = %.15g\n',requiredParameterNames{k},q(k));
    end

    fprintf(fid,'\nFIXED COEFFICIENTS\n');
    fprintf(fid,'PEY3 = 0\n');
    fprintf(fid,'PEY4 = 0\n');

    fprintf(fid,'\nSCOPE\n');
    fprintf(fid,'Pure lateral steady-state MF model only.\n');
    fprintf(fid,'No longitudinal, braking, or combined-slip model is included.\n');
    fprintf(fid,'Runs 5-7 / 8-inch data are not part of this lock.\n');
    fprintf(fid,'Speed-validation data remains isolated from primary fitting data.\n');
    fprintf(fid,'No refit was performed by this lock script.\n');

    fprintf(fid,'\nINTEGRITY CHECKS\n');
    for i=1:height(AuditChecks)
        fprintf(fid,'%-34s : %-4s | %s\n',...
            AuditChecks.Check(i),passFail(AuditChecks.Pass(i)),AuditChecks.Detail(i));
    end

    fclose(fid);
end

%% ------------------------------------------------------------------------
% FINAL CONSOLE SUMMARY
% -------------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf(' CMM LATERAL MODEL LOCK v1.3 COMPLETE\n');
fprintf(' STATUS : %s\n',passFail(LockPass));
fprintf(' OUTPUT : %s\n',outputFolder);
fprintf('============================================================\n');

Result = Lock;

%% ========================================================================
% LOCAL FUNCTION: FROZEN CMM MF LATERAL MODEL
% ========================================================================
function Fy = cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)

a = double(alphaDeg)*pi/180;
g = double(camberDeg)*pi/180;
Fz = max(double(Fz),1);
Ppsi = double(Ppsi);

dfz = (Fz-Fz0)./Fz0;
dP = Ppsi-P0;

PCY1=q(1);
PDY1=q(2); PDY2=q(3); PDY3=q(4);
PEY1=q(5); PEY2=q(6);
PKY1=q(7); PKY2=q(8); PKY3=q(9);
PHY1=q(10); PHY2=q(11); PHY3=q(12);
PVY1=q(13); PVY2=q(14); PVY3=q(15); PVY4=q(16);
Pmu1=q(17); Pmu2=q(18); Pk1=q(19);

Cy = PCY1;

mu = (PDY1 + PDY2.*dfz).*(1-PDY3.*g.^2);
muP = 1 + Pmu1.*dP + Pmu2.*dP.^2;
mu = mu.*muP;

% Frozen CMM v1.5/v1.5.1 positivity guard.
mu = max(mu,0.20);

Dy = mu.*Fz;

% PEY3 and PEY4 are intentionally fixed to zero.
Ey = PEY1 + PEY2.*dfz;
Ey = max(-1.0,min(1.0,Ey));

stiffCamber = max(0.10,1-PKY3.*g.^2);

Ky = PKY1.*Fz0 .* ...
     sin(2.*atan(Fz./(PKY2.*Fz0))) .* stiffCamber;

% CMM pressure wrapper for stiffness.
Ky = Ky.*(1+Pk1.*dP);
Ky = max(Ky,100);

By = Ky./max(Cy.*Dy,1);

Shy = PHY1 + PHY2.*dfz + PHY3.*g;

Svy = Fz.*(PVY1+PVY2.*dfz) + ...
      mu.*Fz.*(PVY3+PVY4.*dfz).*g;

alphaY = a + Shy;
x = By.*alphaY;

Fy = Dy.*sin( ...
    Cy.*atan(x-Ey.*(x-atan(x))) ) + Svy;
end

%% ========================================================================
% LOCAL FUNCTION: EXTRACT PHYSICS
% ========================================================================
function [SA,FY,FZ,IA,P] = extractPhysics(T,applyTTCSign)

SA = getNumeric(T,{'SA_deg','SA','SlipAngle_deg','SlipAngle','Alpha'});
FY = getNumeric(T,{'FY_N','FY','Fy','LateralForce','Lateral_Force'});
FZ = getNumeric(T,{'FZ_N','FZ','Fz','VerticalLoad_N','VerticalLoad'});
IA = getNumeric(T,{'IA_deg','IA','Camber_deg','Camber','Inclination','CamberAngle'});

if hasVariable(T,{'P_psi','Pressure_psi','InflationPressure_psi'})
    P = getNumeric(T,{'P_psi','Pressure_psi','InflationPressure_psi'});
elseif hasVariable(T,{'Pressure_kPa','P_kPa','P_kPa_'})
    P = getNumeric(T,{'Pressure_kPa','P_kPa','P_kPa_'})*0.1450377377;
elseif hasVariable(T,{'P','Pressure','InflationPressure'})
    P = getNumeric(T,{'P','Pressure','InflationPressure'});
    if median(P,'omitnan')>40
        P = P*0.1450377377;
    end
else
    error('CMM:PressureChannel','No pressure channel found.');
end

if applyTTCSign
    % Canonical Stage-4 data is expected to preserve measured FY.
    % The condition-assigned TTC database used by the frozen v1.5 model
    % requires the historical FY=-FY transformation.
    if ismember('Routing',T.Properties.VariableNames)
        % Stage-4 canonical data: do not alter measured FY.
    else
        FY = -FY;
    end
end

good = isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)&isfinite(P)&FZ>0;

SA=SA(good); FY=FY(good); FZ=FZ(good); IA=IA(good); P=P(good);
end

%% ========================================================================
% LOCAL FUNCTION: SWEEP CHARACTERIZATION
% ========================================================================
function row = characterizeSweep(T,CFG)

[SA,FY,FZ,IA,P] = extractPhysics(T,false);

n = numel(SA);
fzm = mean(FZ,'omitnan');
pm = mean(P,'omitnan');
iam = mean(IA,'omitnan');

[peakAbs,ip] = max(abs(FY));
peakSA = SA(ip);

saMin = min(SA);
saMax = max(SA);
boundaryDistance = min(abs(peakSA-[saMin saMax]));

if abs(peakSA) < CFG.MinPeakAlpha_deg
    peakStatus = "LOW_ALPHA_PEAK";
elseif boundaryDistance <= CFG.PeakBoundaryMargin_deg
    peakStatus = "BOUNDARY_LIMITED";
else
    peakStatus = "RESOLVED";
end

muPeak = peakAbs/max(fzm,eps);

m = abs(SA)<=CFG.StiffnessWindow_deg;
if nnz(m)>=CFG.MinStiffnessSamples
    p = polyfit(SA(m),FY(m),1);
    slope = p(1);
    Calpha = -slope;
    yhat = polyval(p,SA(m));
    ssRes = sum((FY(m)-yhat).^2);
    ssTot = sum((FY(m)-mean(FY(m))).^2);
    stiffR2 = 1-ssRes/max(ssTot,eps);
else
    Calpha = NaN;
    stiffR2 = NaN;
end

pos = FY(SA>=0);
neg = FY(SA<=0);

if isempty(pos) || isempty(neg)
    posPeak = NaN;
    negPeak = NaN;
    symmetry = NaN;
else
    posPeak = max(abs(pos));
    negPeak = max(abs(neg));
    symmetry = min(posPeak,negPeak)/max(posPeak,negPeak);
end

row = table( ...
    getFirstNumeric(T,'SweepID',NaN), ...
    getFirstNumeric(T,'ConditionID',NaN), ...
    getFirstNumeric(T,'RunNumber',NaN), ...
    n, fzm, median(FZ,'omitnan'), pm, iam, ...
    getMeanOptional(T,'V_mph',NaN), ...
    peakAbs, muPeak, peakSA, string(peakStatus),boundaryDistance,...
    Calpha,stiffR2,posPeak,negPeak,symmetry,...
    'VariableNames',{ ...
    'SweepID','ConditionID','RunNumber','SampleCount',...
    'FZ_Mean_N','FZ_Median_N','Pressure_Mean_psi','IA_Mean_deg',...
    'Speed_Mean_mph','PeakAbsFY_N','MuY_Peak','SA_AtPeak_deg',...
    'PeakStatus','PeakBoundaryDistance_deg',...
    'CorneringStiffness_N_per_deg','StiffnessR2',...
    'PositivePeakFY_N','NegativePeakFY_N','SymmetryRatio'});
end

%% ========================================================================
% LOCAL FUNCTION: CONDITION CHARACTERIZATION
% ========================================================================
function row = characterizeCondition(cid,SC)

resolved = SC.PeakStatus=="RESOLVED";
saResolved = abs(SC.SA_AtPeak_deg(resolved));

row = table( ...
    cid,height(SC),sum(SC.SampleCount),...
    mean(SC.FZ_Mean_N,'omitnan'),median(SC.FZ_Median_N,'omitnan'),...
    mean(SC.Pressure_Mean_psi,'omitnan'),...
    mean(SC.IA_Mean_deg,'omitnan'),...
    mean(SC.Speed_Mean_mph,'omitnan'),...
    mean(SC.PeakAbsFY_N,'omitnan'),...
    std(SC.PeakAbsFY_N,'omitnan'),...
    mean(SC.MuY_Peak,'omitnan'),...
    std(SC.MuY_Peak,'omitnan'),...
    mean(SC.CorneringStiffness_N_per_deg,'omitnan'),...
    std(SC.CorneringStiffness_N_per_deg,'omitnan'),...
    mean(saResolved,'omitnan'),std(saResolved,'omitnan'),...
    mean(SC.SymmetryRatio,'omitnan'),...
    'VariableNames',{ ...
    'ConditionID','SweepCount','SampleCount','FZ_Mean_N','FZ_Median_N',...
    'Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
    'PeakFY_Mean_N','PeakFY_Std_N','MuY_Mean','MuY_Std',...
    'CorneringStiffness_Mean_N_per_deg',...
    'CorneringStiffness_Std_N_per_deg',...
    'PeakSlipAngle_Mean_deg','PeakSlipAngle_Std_deg',...
    'SymmetryRatio_Mean'});
end

%% ========================================================================
% LOCAL FUNCTION: CONTROLLED SENSITIVITY
% ========================================================================
function Summary = buildControlledSensitivity(C,type,Fz0,P0,IA0,V0,CFG)

if isempty(C)
    Summary=table();
    return;
end

% Keep the non-target variables near the reference condition.
Ftol = CFG.ReferenceFzTol_N;
Ptol = CFG.ReferencePTol_psi;
IAtol = CFG.ReferenceIATol_deg;
Vtol = 5;

switch upper(string(type))
    case "LOAD"
        keep = abs(C.Pressure_Mean_psi-P0)<=Ptol & ...
               abs(C.IA_Mean_deg-IA0)<=IAtol & ...
               abs(C.Speed_Mean_mph-V0)<=Vtol;
        X = C(keep,:);
        if isempty(X)
            X=C;
        end

        % Use naturally occurring target loads, rounded to the nearest 50 N.
        targets = unique(50*round(X.FZ_Mean_N/50));
        targets = targets(isfinite(targets));
        targets = targets(targets>0);

        rows=cell(numel(targets),1);
        for i=1:numel(targets)
            d = ((X.FZ_Mean_N-targets(i))/max(25,Ftol)).^2 + ...
                ((X.Pressure_Mean_psi-P0)/max(Ptol,0.25)).^2 + ...
                ((X.IA_Mean_deg-IA0)/max(IAtol,0.20)).^2 + ...
                ((X.Speed_Mean_mph-V0)/Vtol).^2;
            [~,k]=min(d);
            r=X(k,:);
            rows{i}=table(targets(i),r.ConditionID,r.FZ_Mean_N,...
                r.Pressure_Mean_psi,r.IA_Mean_deg,r.Speed_Mean_mph,...
                r.MuY_Mean,r.PeakFY_Mean_N,r.CorneringStiffness_Mean_N_per_deg,...
                'VariableNames',{'FZ_Target_N','ConditionID','FZ_Mean_N',...
                'Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
                'MuY_Mean','PeakFY_Mean_N','CorneringStiffness_Mean_N_per_deg'});
        end
        Summary=vertcat(rows{:});

    case "PRESSURE"
        keep = abs(C.FZ_Mean_N-Fz0)<=Ftol & ...
               abs(C.IA_Mean_deg-IA0)<=IAtol & ...
               abs(C.Speed_Mean_mph-V0)<=Vtol;
        X=C(keep,:);
        if isempty(X), X=C; end

        targets=unique(round(X.Pressure_Mean_psi,1));
        targets=targets(isfinite(targets));
        rows=cell(numel(targets),1);
        for i=1:numel(targets)
            d=((X.Pressure_Mean_psi-targets(i))/max(0.10,Ptol)).^2 + ...
              ((X.FZ_Mean_N-Fz0)/max(25,Ftol)).^2 + ...
              ((X.IA_Mean_deg-IA0)/max(IAtol,0.20)).^2 + ...
              ((X.Speed_Mean_mph-V0)/Vtol).^2;
            [~,k]=min(d);
            r=X(k,:);
            rows{i}=table(targets(i),r.ConditionID,r.FZ_Mean_N,...
                r.Pressure_Mean_psi,r.IA_Mean_deg,r.Speed_Mean_mph,...
                r.MuY_Mean,r.PeakFY_Mean_N,r.CorneringStiffness_Mean_N_per_deg,...
                'VariableNames',{'Pressure_Target_psi','ConditionID','FZ_Mean_N',...
                'Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
                'MuY_Mean','PeakFY_Mean_N','CorneringStiffness_Mean_N_per_deg'});
        end
        Summary=vertcat(rows{:});

    case "CAMBER"
        keep = abs(C.FZ_Mean_N-Fz0)<=Ftol & ...
               abs(C.Pressure_Mean_psi-P0)<=Ptol & ...
               abs(C.Speed_Mean_mph-V0)<=Vtol;
        X=C(keep,:);
        if isempty(X), X=C; end

        targets=unique(round(X.IA_Mean_deg,1));
        targets=targets(isfinite(targets));
        rows=cell(numel(targets),1);
        for i=1:numel(targets)
            d=((X.IA_Mean_deg-targets(i))/max(0.10,IAtol)).^2 + ...
              ((X.FZ_Mean_N-Fz0)/max(25,Ftol)).^2 + ...
              ((X.Pressure_Mean_psi-P0)/max(0.10,Ptol)).^2 + ...
              ((X.Speed_Mean_mph-V0)/Vtol).^2;
            [~,k]=min(d);
            r=X(k,:);
            rows{i}=table(targets(i),r.ConditionID,r.FZ_Mean_N,...
                r.Pressure_Mean_psi,r.IA_Mean_deg,r.Speed_Mean_mph,...
                r.MuY_Mean,r.PeakFY_Mean_N,r.CorneringStiffness_Mean_N_per_deg,...
                'VariableNames',{'IA_Target_deg','ConditionID','FZ_Mean_N',...
                'Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
                'MuY_Mean','PeakFY_Mean_N','CorneringStiffness_Mean_N_per_deg'});
        end
        Summary=vertcat(rows{:});

    otherwise
        error('CMM:Sensitivity','Unknown controlled sensitivity type.');
end
end

%% ========================================================================
% LOCAL FUNCTION: STATE SENSITIVITY
% ========================================================================
function Summary = buildStateSensitivity(C,type)

if isempty(C)
    Summary=table();
    return;
end

switch upper(string(type))
    case "PRESSURE"
        state = round(C.Pressure_Mean_psi);
        name = 'Pressure_State_psi';
    case "CAMBER"
        state = round(C.IA_Mean_deg);
        name = 'IA_State_deg';
    otherwise
        error('CMM:Sensitivity','Unknown sensitivity type.');
end

states = unique(state(isfinite(state)));
rows=cell(numel(states),1);

for i=1:numel(states)
    X=C(state==states(i),:);
    rows{i}=table(states(i),height(X),...
        mean(X.FZ_Mean_N,'omitnan'),...
        mean(X.PeakFY_Mean_N,'omitnan'),...
        mean(X.MuY_Mean,'omitnan'),...
        mean(X.CorneringStiffness_Mean_N_per_deg,'omitnan'),...
        mean(X.PeakSlipAngle_Mean_deg,'omitnan'),...
        'VariableNames',{name,'ConditionCount','FZ_Mean_N',...
        'PeakFY_Mean_N','MuY_Mean',...
        'CorneringStiffness_Mean_N_per_deg','PeakSlipAngle_Mean_deg'});
end

Summary=vertcat(rows{:});
end

%% ========================================================================
% LOCAL FUNCTION: REPEATABILITY
% ========================================================================
function R = buildRepeatability(SC)

ids=unique(SC.ConditionID);
rows={};

for i=1:numel(ids)
    X=SC(SC.ConditionID==ids(i),:);
    if height(X)<2, continue; end

    peakMean=mean(X.PeakAbsFY_N,'omitnan');
    peakStd=std(X.PeakAbsFY_N,'omitnan');
    stiffMean=mean(X.CorneringStiffness_N_per_deg,'omitnan');
    stiffStd=std(X.CorneringStiffness_N_per_deg,'omitnan');

    rows{end+1,1}=table(ids(i),height(X),...
        peakMean,peakStd,...
        100*peakStd/max(abs(peakMean),eps),...
        stiffMean,stiffStd,...
        100*stiffStd/max(abs(stiffMean),eps),...
        'VariableNames',{'ConditionID','RepeatCount',...
        'PeakFY_Mean_N','PeakFY_Std_N','PeakFY_CV_pct',...
        'CorneringStiffness_Mean_N_per_deg',...
        'CorneringStiffness_Std_N_per_deg',...
        'CorneringStiffness_CV_pct'});
end

if isempty(rows)
    R=table();
else
    R=vertcat(rows{:});
end
end

%% ========================================================================
% LOCAL FUNCTION: METRICS
% ========================================================================
function M = computeMetrics(y,yp)

y=double(y(:));
yp=double(yp(:));
m=isfinite(y)&isfinite(yp);

y=y(m); yp=yp(m);

if isempty(y)
    M=emptyMetrics();
    return;
end

e=yp-y;

M.R2=1-sum(e.^2)/max(sum((y-mean(y)).^2),eps);
M.RMSE_N=sqrt(mean(e.^2));
M.MAE_N=mean(abs(e));
M.N=numel(y);
end

function M=emptyMetrics()
M=struct('R2',NaN,'RMSE_N',NaN,'MAE_N',NaN,'N',0);
end

%% ========================================================================
% LOCAL FUNCTION: TABLE FIELD HELPERS
% ========================================================================
function tf=hasVariable(T,names)
v=string(T.Properties.VariableNames);
tf=false;
for i=1:numel(names)
    if any(strcmpi(v,string(names{i})))
        tf=true;
        return;
    end
end
end

function x=getNumeric(T,names)

v=string(T.Properties.VariableNames);
idx=[];

for i=1:numel(names)
    k=find(strcmpi(v,string(names{i})),1);
    if ~isempty(k)
        idx=k;
        break;
    end
end

if isempty(idx)
    error('CMM:Channel','Required variable not found. Candidates: %s',...
        strjoin(string(names),', '));
end

x=T{:,idx};

if iscell(x) || isstring(x) || iscategorical(x) || ischar(x)
    x=str2double(string(x));
end

x=double(x(:));
end

function x=getFirstNumeric(T,name,default)

if ~ismember(name,T.Properties.VariableNames)
    x=default;
    return;
end

v=T{:,name};
if iscell(v) || isstring(v) || iscategorical(v)
    v=str2double(string(v));
end

x=double(v(1));
end

function x=getMeanOptional(T,name,default)

if ~ismember(name,T.Properties.VariableNames)
    x=default;
    return;
end

v=T{:,name};
if iscell(v) || isstring(v) || iscategorical(v)
    v=str2double(string(v));
end

x=mean(double(v(:)),'omitnan');
end

function value=getFieldOr(S,path,default)

parts=strsplit(path,'.');
value=default;

try
    x=S;
    for i=1:numel(parts)
        if isstruct(x) && isfield(x,parts{i})
            x=x.(parts{i});
        else
            return;
        end
    end
    value=x;
catch
    value=default;
end
end

function value=getFixedCoeff(S,name,default)

value=default;
if isfield(S,'FixedCoefficients') && isfield(S.FixedCoefficients,name)
    value=S.FixedCoefficients.(name);
end
end

%% ========================================================================
% LOCAL FUNCTION: CHECK STORAGE
% ========================================================================
function [names,passes,details]=appendCheck(names,passes,details,name,pass,detail)
names(end+1,1)=string(name);
passes(end+1,1)=logical(pass);
details(end+1,1)=string(detail);
end

function s=passFail(tf)
if tf
    s='PASS';
else
    s='REVIEW';
end
end

function y=ternary(cond,a,b)
if cond
    y=a;
else
    y=b;
end
end

end
