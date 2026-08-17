function Result = CMM_TTC_Lateral_Tire_Characterizer_v5_2()
% CMM TTC LATERAL TIRE CHARACTERIZER v5.2
% Golden baseline: v5.1
%
% v5.2 PURPOSE
%   - Preserve v5.1 characterization mathematics.
%   - Parallelize independent sweep/condition characterization.
%   - Report engineering-positive cornering stiffness:
%         C_alpha = -dFY/dSA
%   - Generate engineering line/curve plots instead of scatter-only plots.
%   - Keep raw measured FY/SA data unchanged.
%   - Explicitly audit every requested figure.
%   - Never silently save an empty comparison figure.
%   - Preserve boundary-limited peak classification.
%   - Write all v5.2 figures/tables/contracts into new folders.
%
% INPUT
%   CMM_LATERAL_MODEL_DATABASE_CONTRACT_v4_0.mat
%
% PRIMARY MODEL DATA
%   Runs 2 + 4 / 7-inch-rim database only.
%
% VALIDATION
%   ValidationSpeed remains isolated from the primary fitting database.
%
% IMPORTANT
%   This stage does NOT fit Magic Formula coefficients.

clc;
close all;

fprintf('\n');
fprintf('============================================================\n');
fprintf(' CMM TTC LATERAL TIRE CHARACTERIZER v5.2\n');
fprintf(' v5.1 baseline + parallel processing + engineering plots\n');
fprintf('============================================================\n\n');

%% CONFIGURATION
CFG = struct();
CFG.Version = "5.2";
CFG.BaselineVersion = "5.1";
CFG.Pipeline = "CMM_OUTPUT_V02";
CFG.ModelName = "CMM_7IN_LATERAL_MODEL";
CFG.RequiredRuns = [2 4];

CFG.ExpectedPrimarySweeps = 80;
CFG.ExpectedValidationSweeps = 10;

CFG.CorneringStiffnessWindow_deg = 2.0;
CFG.StiffnessWindows_deg = [1.0 1.5 2.0 2.5 3.0];
CFG.MinStiffnessSamples = 8;

CFG.MinPeakSlipAngle_deg = 1.0;
CFG.PeakBoundaryMargin_deg = 0.75;

CFG.ReferencePressure_psi = 12;
CFG.ReferenceIA_deg = 0;
CFG.ReferenceSpeed_mph = 25;

CFG.MatchPressure_psi = 0.75;
CFG.MatchIA_deg = 0.50;
CFG.MatchSpeed_mph = 1.50;
CFG.MatchFZ_N = 90;

% Physics QC thresholds are flags, not automatic data deletion.
CFG.LowLoadThreshold_N = 300;
CFG.HighMuThreshold = 3.0;
CFG.ExtremeMuThreshold = 3.5;
CFG.PoorStiffnessR2Threshold = 0.95;
CFG.MaxPlotSweepsPerCondition = 12;
CFG.RepresentativeCurveCount = 6;

CFG.FigureResolution = 220;
CFG.BlackFigures = false;
CFG.SaveFIG = false;

CFG.OutputRoot = "CMM_OUTPUT_V02";
CFG.StageFolder = "05_LATERAL_CHARACTERIZATION";
CFG.FigureFolder = "FIGURES";
CFG.TableFolder = "TABLES";
CFG.VersionFolder = "_V5_2";

%% [1] SELECT PROJECT
fprintf('[1] SELECT TTC PROJECT FOLDER\n');
projectFolder = uigetdir(pwd,'Select TTC project folder');
if isequal(projectFolder,0)
    error('CMM:UserCancelled','Folder selection cancelled.');
end
fprintf('Selected folder:\n%s\n\n',projectFolder);

%% [2] LOCATE STAGE-4 CONTRACT
fprintf('[2] LOCATING STAGE-4 CONTRACT\n');
thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));
outputRoot = fullfile(repoRoot,'outputs',CFG.OutputRoot);

preferredPath = fullfile(outputRoot,...
    '04_LATERAL_MODEL_DATABASE',...
    'CMM_LATERAL_MODEL_DATABASE_CONTRACT_v4_0.mat');

if exist(preferredPath,'file')
    contractPath = string(preferredPath);
else
    results = dir(fullfile(outputRoot,'04_LATERAL_MODEL_DATABASE',...
        'CMM_LATERAL_MODEL_DATABASE_CONTRACT_v4_0.mat'));
    if isempty(results)
        error('CMM:Stage4ContractMissing',...
            'Unable to locate CMM_LATERAL_MODEL_DATABASE_CONTRACT_v4_0.mat');
    end
    contractPath = string(fullfile(results(1).folder,results(1).name));
end
fprintf('Stage-4 contract:\n%s\n\n',contractPath);

%% [3] LOAD + VALIDATE CONTRACT
fprintf('[3] LOADING / VALIDATING DATABASE\n');
S = load(contractPath);
if ~isfield(S,'LateralModelDatabaseContract')
    error('CMM:InvalidStage4Contract',...
        'LateralModelDatabaseContract was not found.');
end
Stage4 = S.LateralModelDatabaseContract;

requiredFields = ["Primary","ValidationSpeed","PrimarySweepManifest",...
    "ValidationSweepManifest","ConditionManifest","DatabaseIntegrityPass"];
stage4Fields = string(fieldnames(Stage4));
for k = 1:numel(requiredFields)
    if ~ismember(requiredFields(k),stage4Fields)
        error('CMM:Stage4FieldMissing',...
            'Required Stage-4 field missing: %s',requiredFields(k));
    end
end
if ~Stage4.DatabaseIntegrityPass
    error('CMM:Stage4IntegrityFailure',...
        'Stage-4 database integrity is not PASS.');
end

Primary = Stage4.Primary;
Validation = Stage4.ValidationSpeed;

requiredChannels = ["SweepID","ConditionID","RunNumber","SA_deg","FY_N",...
    "FZ_N","P_psi","IA_deg","V_mph"];
primaryVars = string(Primary.Properties.VariableNames);
validationVars = string(Validation.Properties.VariableNames);

for k = 1:numel(requiredChannels)
    if ~ismember(requiredChannels(k),primaryVars)
        error('CMM:PrimaryChannelFailure',...
            'Primary database missing required channel: %s',requiredChannels(k));
    end
end
for k = 1:numel(requiredChannels)
    if ~ismember(requiredChannels(k),validationVars)
        error('CMM:ValidationChannelFailure',...
            'Validation database missing required channel: %s',requiredChannels(k));
    end
end

runsPresent = unique(Primary.RunNumber);
if ~all(ismember(runsPresent,CFG.RequiredRuns))
    error('CMM:InvalidRunRouting',...
        'Primary database contains runs outside the required 7-inch routing.');
end

primarySweepIDs = unique(Primary.SweepID);
validationSweepIDs = unique(Validation.SweepID);

fprintf('Primary samples    : %d\n',height(Primary));
fprintf('Validation samples : %d\n',height(Validation));
fprintf('Primary sweeps     : %d\n',numel(primarySweepIDs));
fprintf('Validation sweeps  : %d\n',numel(validationSweepIDs));
fprintf('Primary runs       : ');
fprintf('%d ',runsPresent);
fprintf('\n\n');

%% [4] OUTPUT DIRECTORIES
fprintf('[4] CREATING v5.2 OUTPUT DIRECTORIES\n');
outputFolder = fullfile(outputRoot,CFG.StageFolder);
figureRoot = fullfile(outputFolder,CFG.FigureFolder,CFG.VersionFolder);
tableFolder = fullfile(outputFolder,CFG.TableFolder,CFG.VersionFolder);

figureFolders = { ...
    '01_FY_SA_REFERENCE', ...
    '02_FY_SA_REPRESENTATIVE', ...
    '03_LOAD_SENSITIVITY', ...
    '04_FRICTION_LOAD_SENSITIVITY', ...
    '05_CORNERING_STIFFNESS', ...
    '06_PEAK_SLIP_ANGLE', ...
    '07_PRESSURE_SENSITIVITY', ...
    '08_CAMBER_SENSITIVITY', ...
    '09_SPEED_SENSITIVITY', ...
    '10_REPEATABILITY', ...
    '11_SYMMETRY', ...
    '12_STIFFNESS_QC', ...
    '13_PEAK_QC', ...
    '14_OUTLIER_QC', ...
    '15_FIGURE_AUDIT'};

if ~exist(figureRoot,'dir'), mkdir(figureRoot); end
if ~exist(tableFolder,'dir'), mkdir(tableFolder); end
for k = 1:numel(figureFolders)
    p = fullfile(figureRoot,figureFolders{k});
    if ~exist(p,'dir'), mkdir(p); end
end

fprintf('Figures : %s\n',figureRoot);
fprintf('Tables  : %s\n\n',tableFolder);

%% [5] PARALLEL POOL
fprintf('[5] INITIALIZING PARALLEL POOL\n');
parallelUsed = false;
poolSize = 0;
try
    if license('test','Distrib_Computing_Toolbox')
        pool = gcp('nocreate');
        if isempty(pool)
            pool = parpool('local');
        end
        parallelUsed = true;
        poolSize = pool.NumWorkers;
        fprintf('Parallel pool : ACTIVE (%d workers)\n\n',poolSize);
    else
        fprintf('Parallel Computing Toolbox unavailable. Using serial mode.\n\n');
    end
catch ME
    fprintf('Parallel pool unavailable (%s). Using serial mode.\n\n',ME.message);
end

%% [6] CHARACTERIZE PRIMARY SWEEPS
fprintf('[6] CHARACTERIZING PRIMARY SWEEPS\n');
nPrimary = numel(primarySweepIDs);
Ccell = cell(nPrimary,1);

if parallelUsed
    parfor i = 1:nPrimary
        sid = primarySweepIDs(i);
        T = Primary(Primary.SweepID == sid,:);
        Ccell{i} = characterizeSweep_v52(T,CFG);
    end
else
    for i = 1:nPrimary
        sid = primarySweepIDs(i);
        T = Primary(Primary.SweepID == sid,:);
        Ccell{i} = characterizeSweep_v52(T,CFG);
    end
end

SweepCharacteristics = buildSweepTable(Primary,primarySweepIDs,Ccell);
fprintf('Sweeps characterized : %d\n\n',height(SweepCharacteristics));

%% [7] CHARACTERIZE CONDITIONS
fprintf('[7] CHARACTERIZING OPERATING CONDITIONS\n');
conditionIDs = unique(Primary.ConditionID);
nConditions = numel(conditionIDs);
conditionCells = cell(nConditions,1);

if parallelUsed
    parfor i = 1:nConditions
        cid = conditionIDs(i);
        SC = SweepCharacteristics(SweepCharacteristics.ConditionID == cid,:);
        conditionCells{i} = characterizeCondition_v52(cid,SC);
    end
else
    for i = 1:nConditions
        cid = conditionIDs(i);
        SC = SweepCharacteristics(SweepCharacteristics.ConditionID == cid,:);
        conditionCells{i} = characterizeCondition_v52(cid,SC);
    end
end

ConditionCharacteristics = vertcat(conditionCells{:});
fprintf('Conditions characterized : %d\n\n',height(ConditionCharacteristics));

%% [8] REFERENCE CONDITION
fprintf('[8] REFERENCE CONDITION\n');
metric = abs(ConditionCharacteristics.Pressure_Mean_psi-CFG.ReferencePressure_psi) + ...
         abs(ConditionCharacteristics.IA_Mean_deg-CFG.ReferenceIA_deg) + ...
         abs(ConditionCharacteristics.Speed_Mean_mph-CFG.ReferenceSpeed_mph);
[~,ri] = min(metric);
ReferenceCondition = ConditionCharacteristics(ri,:);
fprintf('Condition %d | P %.2f psi | IA %.2f deg | V %.2f mph | FZ %.1f N\n\n',...
    ReferenceCondition.ConditionID,...
    ReferenceCondition.Pressure_Mean_psi,...
    ReferenceCondition.IA_Mean_deg,...
    ReferenceCondition.Speed_Mean_mph,...
    ReferenceCondition.FZ_Mean_N);

%% [9] SENSITIVITY TABLES
fprintf('[9] BUILDING SENSITIVITY TABLES\n');
LoadSensitivity = ConditionCharacteristics;
LoadSensitivity.MuY = LoadSensitivity.PeakFY_Mean_N ./ ...
    max(LoadSensitivity.FZ_Mean_N,eps);
LoadSensitivity.LoadSensitivity_FY_per_FZ = ...
    LoadSensitivity.PeakFY_Mean_N ./ max(LoadSensitivity.FZ_Mean_N,eps);

PressureSensitivity = buildSensitivitySummary_v52(ConditionCharacteristics,"PRESSURE");
CamberSensitivity = buildSensitivitySummary_v52(ConditionCharacteristics,"CAMBER");

%% [10] VALIDATION SWEEPS
fprintf('[10] CHARACTERIZING SPEED-VALIDATION SWEEPS\n');
nValidation = numel(validationSweepIDs);
VCcell = cell(nValidation,1);

if parallelUsed
    parfor i = 1:nValidation
        sid = validationSweepIDs(i);
        T = Validation(Validation.SweepID == sid,:);
        VCcell{i} = characterizeSweep_v52(T,CFG);
    end
else
    for i = 1:nValidation
        sid = validationSweepIDs(i);
        T = Validation(Validation.SweepID == sid,:);
        VCcell{i} = characterizeSweep_v52(T,CFG);
    end
end
ValidationSweepCharacteristics = buildSweepTable(Validation,validationSweepIDs,VCcell);
fprintf('Validation sweeps characterized : %d\n\n',height(ValidationSweepCharacteristics));

%% [11] REPEATABILITY
fprintf('[11] REPEATABILITY\n');
Repeatability = buildRepeatability_v52(SweepCharacteristics);
fprintf('Repeated conditions : %d\n\n',height(Repeatability));

%% [12] SYMMETRY
fprintf('[12] SWEEP SYMMETRY\n');
SweepSymmetry = SweepCharacteristics(:,{'SweepID','ConditionID','RunNumber',...
    'FZ_Mean_N','Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
    'PositivePeakFY_N','NegativePeakFY_N','SymmetryRatio'});
symmetryFinite = SweepSymmetry.SymmetryRatio(isfinite(SweepSymmetry.SymmetryRatio));
fprintf('Mean symmetry ratio : %.4f\n',mean(symmetryFinite,'omitnan'));
fprintf('Std symmetry ratio  : %.4f\n\n',std(symmetryFinite,'omitnan'));

%% [13] FIGURE GENERATION
fprintf('[13] GENERATING ENGINEERING FIGURES\n');
figureAudit = table(strings(0,1),strings(0,1),strings(0,1),...
    false(0,1),strings(0,1),...
    'VariableNames',{'FigureID','File','Type','Pass','Detail'});

% Reference and representative FY-SA curves
[figureAudit] = addFigureAudit(figureAudit,...
    plotReferenceFYSA_v52(Primary,SweepCharacteristics,ReferenceCondition,CFG,...
    fullfile(figureRoot,'01_FY_SA_REFERENCE')));

[figureAudit] = addFigureAudit(figureAudit,...
    plotRepresentativeFYSA_v52(Primary,SweepCharacteristics,CFG,...
    fullfile(figureRoot,'02_FY_SA_REPRESENTATIVE')));

% Load, mu, stiffness, peak
[figureAudit] = addFigureAudit(figureAudit,...
    plotTrendFigure_v52(ConditionCharacteristics.FZ_Mean_N,...
    ConditionCharacteristics.PeakFY_Mean_N,...
    'Measured Vertical Load, F_Z [N]','Peak |F_Y| [N]',...
    'Lateral Force Load Sensitivity',...
    fullfile(figureRoot,'03_LOAD_SENSITIVITY'),'Peak_FY_vs_FZ.png',...
    'Ordered engineering trend'));

[figureAudit] = addFigureAudit(figureAudit,...
    plotTrendFigure_v52(ConditionCharacteristics.FZ_Mean_N,...
    ConditionCharacteristics.MuY_Mean,...
    'Measured Vertical Load, F_Z [N]','Peak lateral friction coefficient, \mu_y',...
    'Lateral Friction Load Sensitivity',...
    fullfile(figureRoot,'04_FRICTION_LOAD_SENSITIVITY'),'MuY_vs_FZ.png',...
    'Ordered engineering trend'));

[figureAudit] = addFigureAudit(figureAudit,...
    plotTrendFigure_v52(ConditionCharacteristics.FZ_Mean_N,...
    abs(ConditionCharacteristics.CorneringStiffness_Mean_N_per_deg),...
    'Measured Vertical Load, F_Z [N]','Cornering stiffness, C_\alpha [N/deg]',...
    'Cornering Stiffness vs Vertical Load',...
    fullfile(figureRoot,'05_CORNERING_STIFFNESS'),'Cornering_Stiffness_vs_FZ.png',...
    'Engineering-positive C_alpha'));

[figureAudit] = addFigureAudit(figureAudit,...
    plotPeakStatus_v52(SweepCharacteristics,CFG,...
    fullfile(figureRoot,'06_PEAK_SLIP_ANGLE')));

%% Pressure/camber trend curves
[figureAudit] = addFigureAudit(figureAudit,...
    plotSensitivityTrend_v52(ConditionCharacteristics,"PRESSURE",CFG,...
    fullfile(figureRoot,'07_PRESSURE_SENSITIVITY')));

[figureAudit] = addFigureAudit(figureAudit,...
    plotSensitivityTrend_v52(ConditionCharacteristics,"CAMBER",CFG,...
    fullfile(figureRoot,'08_CAMBER_SENSITIVITY')));

%% Speed validation
[figureAudit] = addFigureAudit(figureAudit,...
    plotSpeedValidation_v52(Primary,Validation,SweepCharacteristics,...
    ValidationSweepCharacteristics,CFG,...
    fullfile(figureRoot,'09_SPEED_SENSITIVITY')));

%% Repeatability and symmetry
[figureAudit] = addFigureAudit(figureAudit,...
    plotRepeatability_v52(Primary,Repeatability,CFG,...
    fullfile(figureRoot,'10_REPEATABILITY')));

[figureAudit] = addFigureAudit(figureAudit,...
    plotSymmetry_v52(SweepSymmetry,CFG,...
    fullfile(figureRoot,'11_SYMMETRY')));

%% Stiffness-window QC
[figureAudit] = addFigureAudit(figureAudit,...
    plotStiffnessWindowQC(Primary,SweepCharacteristics,CFG,...
    fullfile(figureRoot,'12_STIFFNESS_QC')));

%% Peak/outlier QC
PeakSAQC = SweepCharacteristics(:,{'SweepID','ConditionID','RunNumber',...
    'FZ_Mean_N','Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
    'PeakAbsFY_N','SA_AtPeak_deg','PeakStatus','PeakBoundaryDistance_deg'});
[figureAudit] = addFigureAudit(figureAudit,...
    plotOutlierQC_v52(SweepCharacteristics,CFG,...
    fullfile(figureRoot,'13_PEAK_QC')));

[figureAudit] = addFigureAudit(figureAudit,...
    plotPhysicsOutlierQC_v52(SweepCharacteristics,CFG,...
    fullfile(figureRoot,'14_OUTLIER_QC')));

%% Figure audit visualization itself
auditFile = fullfile(figureRoot,'15_FIGURE_AUDIT','Figure_Audit.csv');
writetable(figureAudit,auditFile);
[figureAudit] = addFigureAudit(figureAudit,...
    plotFigureAudit_v52(figureAudit,CFG,...
    fullfile(figureRoot,'15_FIGURE_AUDIT')));

fprintf('\nFigure audit:\n');
fprintf('  Requested/registered : %d\n',height(figureAudit));
fprintf('  PASS                  : %d\n',sum(figureAudit.Pass));
fprintf('  FAIL                  : %d\n\n',sum(~figureAudit.Pass));

%% [14] TABLES
fprintf('[14] SAVING v5.2 TABLES\n');
writetable(SweepCharacteristics,fullfile(tableFolder,...
    'CMM_SWEEP_CHARACTERISTICS_v5_2.csv'));
writetable(ConditionCharacteristics,fullfile(tableFolder,...
    'CMM_CONDITION_CHARACTERISTICS_v5_2.csv'));
writetable(LoadSensitivity,fullfile(tableFolder,...
    'CMM_LOAD_SENSITIVITY_v5_2.csv'));
writetable(PressureSensitivity,fullfile(tableFolder,...
    'CMM_PRESSURE_SENSITIVITY_v5_2.csv'));
writetable(CamberSensitivity,fullfile(tableFolder,...
    'CMM_CAMBER_SENSITIVITY_v5_2.csv'));
writetable(ValidationSweepCharacteristics,fullfile(tableFolder,...
    'CMM_SPEED_SENSITIVITY_v5_2.csv'));
writetable(Repeatability,fullfile(tableFolder,...
    'CMM_REPEATABILITY_v5_2.csv'));
writetable(SweepSymmetry,fullfile(tableFolder,...
    'CMM_SWEEP_SYMMETRY_v5_2.csv'));
writetable(PeakSAQC,fullfile(tableFolder,...
    'CMM_PEAK_SA_QC_v5_2.csv'));
writetable(figureAudit,fullfile(tableFolder,...
    'CMM_FIGURE_AUDIT_v5_2.csv'));

%% [15] INTEGRITY
fprintf('[15] CHARACTERIZATION INTEGRITY\n');
checks = strings(0,1);
passes = false(0,1);
details = strings(0,1);

[checks,passes,details] = addCheck(checks,passes,details,...
    "STAGE4_DATABASE_INTEGRITY",Stage4.DatabaseIntegrityPass,...
    string(Stage4.DatabaseIntegrityPass));

[checks,passes,details] = addCheck(checks,passes,details,...
    "PRIMARY_SWEEP_COUNT",height(SweepCharacteristics)==CFG.ExpectedPrimarySweeps,...
    sprintf('%d / %d',height(SweepCharacteristics),CFG.ExpectedPrimarySweeps));

[checks,passes,details] = addCheck(checks,passes,details,...
    "VALIDATION_SWEEP_COUNT",height(ValidationSweepCharacteristics)==CFG.ExpectedValidationSweeps,...
    sprintf('%d / %d',height(ValidationSweepCharacteristics),CFG.ExpectedValidationSweeps));

[checks,passes,details] = addCheck(checks,passes,details,...
    "CONDITION_CHARACTERIZATION",height(ConditionCharacteristics)>0,...
    sprintf('%d conditions',height(ConditionCharacteristics)));

[checks,passes,details] = addCheck(checks,passes,details,...
    "FINITE_PEAK_FY",all(isfinite(SweepCharacteristics.PeakAbsFY_N)),...
    "All primary peak forces finite");

[checks,passes,details] = addCheck(checks,passes,details,...
    "FINITE_MUY",all(isfinite(SweepCharacteristics.MuY_Peak)),...
    "All primary peak mu_y finite");

stiffCoverage = mean(isfinite(SweepCharacteristics.CorneringStiffness_N_per_deg));
[checks,passes,details] = addCheck(checks,passes,details,...
    "CORNERING_STIFFNESS_COVERAGE",stiffCoverage>=0.90,...
    sprintf('%.1f%% finite',100*stiffCoverage));

peakClassPass = all(SweepCharacteristics.PeakStatus=="RESOLVED" | ...
    SweepCharacteristics.PeakStatus=="BOUNDARY_LIMITED");
[checks,passes,details] = addCheck(checks,passes,details,...
    "PEAK_CLASSIFICATION",peakClassPass,...
    sprintf('%d resolved / %d boundary-limited',...
    sum(SweepCharacteristics.PeakStatus=="RESOLVED"),...
    sum(SweepCharacteristics.PeakStatus=="BOUNDARY_LIMITED")));

auditPass = all(figureAudit.Pass);
[checks,passes,details] = addCheck(checks,passes,details,...
    "FIGURE_GENERATION",auditPass,...
    sprintf('%d/%d figures PASS',sum(figureAudit.Pass),height(figureAudit)));

CharacterizationIntegrity = table(checks,passes,details,...
    'VariableNames',{'Check','Pass','Details'});
writetable(CharacterizationIntegrity,fullfile(tableFolder,...
    'CMM_CHARACTERIZATION_INTEGRITY_v5_2.csv'));

CharacterizationIntegrityPass = all(passes);

for k = 1:height(CharacterizationIntegrity)
    fprintf('%-34s : %-4s | %s\n',...
        CharacterizationIntegrity.Check(k),...
        passFail_v52(CharacterizationIntegrity.Pass(k)),...
        CharacterizationIntegrity.Details(k));
end
fprintf('\nCHARACTERIZATION INTEGRITY : %s\n\n',...
    passFail_v52(CharacterizationIntegrityPass));

%% [16] CONTRACT
fprintf('[16] BUILDING v5.2 CONTRACT\n');
TireCharacterizationContract = struct();
TireCharacterizationContract.Version = CFG.Version;
TireCharacterizationContract.BaselineVersion = CFG.BaselineVersion;
TireCharacterizationContract.Pipeline = CFG.Pipeline;
TireCharacterizationContract.ModelName = Stage4.ModelName;
TireCharacterizationContract.TireModel = Stage4.TireModel;
TireCharacterizationContract.Compound = Stage4.Compound;
TireCharacterizationContract.RimWidth_in = Stage4.RimWidth_in;
TireCharacterizationContract.Configuration = CFG;
TireCharacterizationContract.SourceStage4Contract = contractPath;
TireCharacterizationContract.PrimaryDatabase = Primary;
TireCharacterizationContract.ValidationSpeedDatabase = Validation;
TireCharacterizationContract.SweepCharacteristics = SweepCharacteristics;
TireCharacterizationContract.ConditionCharacteristics = ConditionCharacteristics;
TireCharacterizationContract.LoadSensitivity = LoadSensitivity;
TireCharacterizationContract.PressureSensitivity = PressureSensitivity;
TireCharacterizationContract.CamberSensitivity = CamberSensitivity;
TireCharacterizationContract.SpeedSensitivity = ValidationSweepCharacteristics;
TireCharacterizationContract.Repeatability = Repeatability;
TireCharacterizationContract.SweepSymmetry = SweepSymmetry;
TireCharacterizationContract.PeakSAQC = PeakSAQC;
TireCharacterizationContract.ReferenceCondition = ReferenceCondition;
TireCharacterizationContract.FigureAudit = figureAudit;
TireCharacterizationContract.IntegrityChecks = CharacterizationIntegrity;
TireCharacterizationContract.CharacterizationIntegrityPass = CharacterizationIntegrityPass;
TireCharacterizationContract.ParallelProcessingUsed = parallelUsed;
TireCharacterizationContract.ParallelPoolWorkers = poolSize;

contractPathOut = fullfile(outputFolder,...
    'CMM_TIRE_CHARACTERIZATION_CONTRACT_v5_2.mat');
save(contractPathOut,'TireCharacterizationContract','-v7.3');

%% [17] REPORT
reportPath = fullfile(outputFolder,'CMM_TIRE_CHARACTERIZATION_REPORT_v5_2.txt');
fid = fopen(reportPath,'w');
if fid ~= -1
    fprintf(fid,'CMM TTC LATERAL TIRE CHARACTERIZER v5.2\n');
    fprintf(fid,'============================================================\n\n');
    fprintf(fid,'BASELINE : v5.1\n');
    fprintf(fid,'PARALLEL : %s (%d workers)\n\n',passFail_v52(parallelUsed),poolSize);
    fprintf(fid,'PRIMARY SAMPLES     : %d\n',height(Primary));
    fprintf(fid,'PRIMARY SWEEPS      : %d\n',height(SweepCharacteristics));
    fprintf(fid,'CONDITIONS          : %d\n',height(ConditionCharacteristics));
    fprintf(fid,'VALIDATION SWEEPS   : %d\n\n',height(ValidationSweepCharacteristics));
    fprintf(fid,'REFERENCE CONDITION : %d\n',ReferenceCondition.ConditionID);
    fprintf(fid,'P                   : %.3f psi\n',ReferenceCondition.Pressure_Mean_psi);
    fprintf(fid,'IA                  : %.3f deg\n',ReferenceCondition.IA_Mean_deg);
    fprintf(fid,'V                   : %.3f mph\n',ReferenceCondition.Speed_Mean_mph);
    fprintf(fid,'FZ                  : %.3f N\n\n',ReferenceCondition.FZ_Mean_N);
    fprintf(fid,'MAX PEAK |FY|       : %.3f N\n',max(SweepCharacteristics.PeakAbsFY_N));
    fprintf(fid,'MAX PEAK MUY        : %.5f\n',max(SweepCharacteristics.MuY_Peak));
    fprintf(fid,'MEDIAN C_ALPHA      : %.3f N/deg\n',...
        median(abs(SweepCharacteristics.CorneringStiffness_N_per_deg),'omitnan'));
    resolvedSA = SweepCharacteristics.SA_AtPeak_deg(...
        SweepCharacteristics.PeakStatus=="RESOLVED");
    fprintf(fid,'MEDIAN RESOLVED SA  : %.3f deg\n',median(abs(resolvedSA),'omitnan'));
    fprintf(fid,'MEAN SYMMETRY       : %.5f\n',mean(symmetryFinite,'omitnan'));
    fprintf(fid,'FIGURES PASS        : %d / %d\n',sum(figureAudit.Pass),height(figureAudit));
    fprintf(fid,'FINAL INTEGRITY     : %s\n',passFail_v52(CharacterizationIntegrityPass));
    fclose(fid);
end

%% RESULT
Result = TireCharacterizationContract;

fprintf('\n============================================================\n');
if CharacterizationIntegrityPass
    fprintf(' STAGE 5 v5.2 STATUS : PASS\n');
else
    fprintf(' STAGE 5 v5.2 STATUS : FAIL\n');
    fprintf(' DO NOT PROCEED TO MAGIC FORMULA FITTING.\n');
end
fprintf(' Contract:\n%s\n',contractPathOut);
fprintf(' Figures:\n%s\n',figureRoot);
fprintf(' Tables:\n%s\n',tableFolder);
fprintf('============================================================\n\n');

end

%% ========================================================================
% LOCAL: SWEEP CHARACTERIZATION
% ========================================================================
function C = characterizeSweep_v52(T,CFG)
SA = double(T.SA_deg(:));
FY = double(T.FY_N(:));
FZ = double(T.FZ_N(:));

finite = isfinite(SA) & isfinite(FY) & isfinite(FZ);
SA = SA(finite); FY = FY(finite); FZ = FZ(finite);

C = struct();
C.FZ_Mean_N = mean(FZ,'omitnan');
C.FZ_Median_N = median(FZ,'omitnan');
C.FZ_Std_N = std(FZ,'omitnan');
C.Pressure_Mean_psi = mean(double(T.P_psi(finite)),'omitnan');
C.IA_Mean_deg = mean(double(T.IA_deg(finite)),'omitnan');
C.Speed_Mean_mph = mean(double(T.V_mph(finite)),'omitnan');
C.SA_Min_deg = min(SA);
C.SA_Max_deg = max(SA);
C.FY_Min_N = min(FY);
C.FY_Max_N = max(FY);

peakMask = abs(SA) >= CFG.MinPeakSlipAngle_deg;
if ~any(peakMask), peakMask = true(size(SA)); end
candidateFY = FY(peakMask);
candidateSA = SA(peakMask);
[C.PeakAbsFY_N,idx] = max(abs(candidateFY));
C.PeakSignedFY_N = candidateFY(idx);
C.SA_AtPeak_deg = candidateSA(idx);

C.PeakBoundaryDistance_deg = min(...
    abs(C.SA_AtPeak_deg-C.SA_Min_deg),...
    abs(C.SA_Max_deg-C.SA_AtPeak_deg));

if C.PeakBoundaryDistance_deg <= CFG.PeakBoundaryMargin_deg
    C.PeakStatus = "BOUNDARY_LIMITED";
else
    C.PeakStatus = "RESOLVED";
end

C.MuY_Peak = C.PeakAbsFY_N/max(C.FZ_Mean_N,eps);

m = abs(SA) <= CFG.CorneringStiffnessWindow_deg;
SAlinear = SA(m); FYlinear = FY(m);

if numel(SAlinear) >= CFG.MinStiffnessSamples && ...
        numel(unique(SAlinear)) >= 3
    p = polyfit(SAlinear,FYlinear,1);
    fit = polyval(p,SAlinear);
    ssres = sum((FYlinear-fit).^2);
    sstot = sum((FYlinear-mean(FYlinear)).^2);
    if sstot > eps, R2 = 1-ssres/sstot; else, R2 = NaN; end

    % Engineering-positive convention. Raw fit slope remains available.
    C.RawCorneringSlope_N_per_deg = p(1);
    C.CorneringStiffness_N_per_deg = -p(1);
    C.CorneringStiffness_N_per_rad = -p(1)*180/pi;
    C.Stiffness_R2 = R2;
    C.ZeroSlipFY_N = p(2);
else
    C.RawCorneringSlope_N_per_deg = NaN;
    C.CorneringStiffness_N_per_deg = NaN;
    C.CorneringStiffness_N_per_rad = NaN;
    C.Stiffness_R2 = NaN;
    C.ZeroSlipFY_N = NaN;
end

pos = SA > 0;
neg = SA < 0;
if any(pos), C.PositivePeakFY_N = max(abs(FY(pos))); else, C.PositivePeakFY_N = NaN; end
if any(neg), C.NegativePeakFY_N = max(abs(FY(neg))); else, C.NegativePeakFY_N = NaN; end

if isfinite(C.PositivePeakFY_N) && isfinite(C.NegativePeakFY_N) && C.NegativePeakFY_N > eps
    C.SymmetryRatio = C.PositivePeakFY_N/C.NegativePeakFY_N;
else
    C.SymmetryRatio = NaN;
end

if C.FZ_Mean_N < CFG.LowLoadThreshold_N
    C.LoadQC = "LOW_LOAD";
elseif C.MuY_Peak >= CFG.ExtremeMuThreshold
    C.LoadQC = "EXTREME_MU";
elseif C.MuY_Peak >= CFG.HighMuThreshold
    C.LoadQC = "HIGH_MU";
else
    C.LoadQC = "NORMAL";
end

if ~isfinite(C.Stiffness_R2) || C.Stiffness_R2 < CFG.PoorStiffnessR2Threshold
    C.StiffnessQC = "POOR";
else
    C.StiffnessQC = "GOOD";
end
end

%% ========================================================================
% LOCAL: BUILD SWEEP TABLE
% ========================================================================
function TOut = buildSweepTable(Database,sweepIDs,Ccell)
n = numel(sweepIDs);
rows = cell(n,1);

for i = 1:n
    sid = sweepIDs(i);
    T = Database(Database.SweepID==sid,:);
    C = Ccell{i};

    rows{i} = table(sid,...
        T.OriginalFullSweepID(1),T.Stage2RegionID(1),...
        T.RunNumber(1),T.ConditionID(1),height(T),...
        C.FZ_Mean_N,C.FZ_Median_N,C.FZ_Std_N,...
        C.Pressure_Mean_psi,C.IA_Mean_deg,C.Speed_Mean_mph,...
        C.SA_Min_deg,C.SA_Max_deg,C.FY_Min_N,C.FY_Max_N,...
        C.PeakAbsFY_N,C.PeakSignedFY_N,C.SA_AtPeak_deg,C.MuY_Peak,...
        C.RawCorneringSlope_N_per_deg,C.CorneringStiffness_N_per_deg,...
        C.CorneringStiffness_N_per_rad,C.Stiffness_R2,C.ZeroSlipFY_N,...
        C.PositivePeakFY_N,C.NegativePeakFY_N,C.SymmetryRatio,...
        string(C.PeakStatus),C.PeakBoundaryDistance_deg,...
        string(C.LoadQC),string(C.StiffnessQC),...
        'VariableNames',{'SweepID','OriginalFullSweepID','Stage2RegionID',...
        'RunNumber','ConditionID','SampleCount','FZ_Mean_N','FZ_Median_N',...
        'FZ_Std_N','Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
        'SA_Min_deg','SA_Max_deg','FY_Min_N','FY_Max_N','PeakAbsFY_N',...
        'PeakSignedFY_N','SA_AtPeak_deg','MuY_Peak',...
        'RawCorneringSlope_N_per_deg','CorneringStiffness_N_per_deg',...
        'CorneringStiffness_N_per_rad','Stiffness_R2','ZeroSlipFY_N',...
        'PositivePeakFY_N','NegativePeakFY_N','SymmetryRatio','PeakStatus',...
        'PeakBoundaryDistance_deg','LoadQC','StiffnessQC'});
end
TOut = vertcat(rows{:});
TOut = sortrows(TOut,'SweepID');
end

%% ========================================================================
% LOCAL: CONDITION CHARACTERIZATION
% ========================================================================
function row = characterizeCondition_v52(cid,SC)
row = table(cid,height(SC),sum(SC.SampleCount),...
    mean(SC.FZ_Mean_N,'omitnan'),median(SC.FZ_Median_N,'omitnan'),...
    mean(SC.Pressure_Mean_psi,'omitnan'),mean(SC.IA_Mean_deg,'omitnan'),...
    mean(SC.Speed_Mean_mph,'omitnan'),...
    mean(SC.PeakAbsFY_N,'omitnan'),std(SC.PeakAbsFY_N,'omitnan'),...
    mean(SC.MuY_Peak,'omitnan'),std(SC.MuY_Peak,'omitnan'),...
    mean(SC.CorneringStiffness_N_per_deg,'omitnan'),...
    std(SC.CorneringStiffness_N_per_deg,'omitnan'),...
    mean(abs(SC.SA_AtPeak_deg(SC.PeakStatus=="RESOLVED")),'omitnan'),...
    std(abs(SC.SA_AtPeak_deg(SC.PeakStatus=="RESOLVED")),'omitnan'),...
    mean(SC.SymmetryRatio,'omitnan'),...
    'VariableNames',{'ConditionID','SweepCount','SampleCount','FZ_Mean_N',...
    'FZ_Median_N','Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
    'PeakFY_Mean_N','PeakFY_Std_N','MuY_Mean','MuY_Std',...
    'CorneringStiffness_Mean_N_per_deg','CorneringStiffness_Std_N_per_deg',...
    'PeakSlipAngle_Mean_deg','PeakSlipAngle_Std_deg','SymmetryRatio_Mean'});
end

%% ========================================================================
% LOCAL: SENSITIVITY SUMMARY
% ========================================================================
function Summary = buildSensitivitySummary_v52(C,type)
if isempty(C), Summary = table(); return; end

switch upper(string(type))
    case "PRESSURE"
        state = round(C.Pressure_Mean_psi);
        stateName = 'Pressure_State_psi';
    case "CAMBER"
        state = round(C.IA_Mean_deg);
        stateName = 'IA_State_deg';
    otherwise
        error('CMM:UnknownSensitivityType','Unknown sensitivity type.');
end

states = unique(state(isfinite(state)));
rows = cell(numel(states),1);
for i = 1:numel(states)
    X = C(state==states(i),:);
    rows{i} = table(states(i),height(X),mean(X.FZ_Mean_N,'omitnan'),...
        mean(X.PeakFY_Mean_N,'omitnan'),mean(X.MuY_Mean,'omitnan'),...
        mean(X.CorneringStiffness_Mean_N_per_deg,'omitnan'),...
        mean(X.PeakSlipAngle_Mean_deg,'omitnan'),...
        'VariableNames',{stateName,'ConditionCount','FZ_Mean_N',...
        'PeakFY_Mean_N','MuY_Mean','CorneringStiffness_Mean_N_per_deg',...
        'PeakSlipAngle_Mean_deg'});
end
Summary = vertcat(rows{:});
end

%% ========================================================================
% LOCAL: REPEATABILITY
% ========================================================================
function R = buildRepeatability_v52(SC)
ids = unique(SC.ConditionID);
rows = {};
for i = 1:numel(ids)
    X = SC(SC.ConditionID==ids(i),:);
    if height(X) < 2, continue; end
    peakMean = mean(X.PeakAbsFY_N,'omitnan');
    peakStd = std(X.PeakAbsFY_N,'omitnan');
    stiffMean = mean(X.CorneringStiffness_N_per_deg,'omitnan');
    stiffStd = std(X.CorneringStiffness_N_per_deg,'omitnan');
    rows{end+1,1} = table(ids(i),height(X),mean(X.FZ_Mean_N,'omitnan'),...
        mean(X.Pressure_Mean_psi,'omitnan'),mean(X.IA_Mean_deg,'omitnan'),...
        mean(X.Speed_Mean_mph,'omitnan'),peakMean,peakStd,...
        100*peakStd/max(abs(peakMean),eps),stiffMean,stiffStd,...
        100*stiffStd/max(abs(stiffMean),eps),...
        'VariableNames',{'ConditionID','RepeatCount','FZ_Mean_N',...
        'Pressure_Mean_psi','IA_Mean_deg','Speed_Mean_mph',...
        'PeakFY_Mean_N','PeakFY_Std_N','PeakFY_CV_pct',...
        'CorneringStiffness_Mean_N_per_deg','CorneringStiffness_Std_N_per_deg',...
        'CorneringStiffness_CV_pct'});
end
if isempty(rows), R = table(); else, R = vertcat(rows{:}); end
end

%% ========================================================================
% LOCAL: FIGURE AUDIT
% ========================================================================
function [A] = addFigureAudit(A,newRows)
if isempty(newRows), return; end
A = [A; newRows]; %#ok<AGROW>
end

function row = figureRow(id,file,type,pass,detail)
row = table(string(id),string(file),string(type),logical(pass),string(detail),...
    'VariableNames',{'FigureID','File','Type','Pass','Detail'});
end

%% ========================================================================
% LOCAL: REFERENCE FY-SA
% ========================================================================
function row = plotReferenceFYSA_v52(Primary,SC,Ref,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
sidCandidates = SC(SC.ConditionID==Ref.ConditionID,:);
if isempty(sidCandidates)
    row = figureRow('REFERENCE_FY_SA','','curve',false,'Reference condition has no sweep.');
    return;
end
fig = createCMMFigure_v52(CFG); hold on;
ids = sidCandidates.SweepID;
for i = 1:numel(ids)
    T = Primary(Primary.SweepID==ids(i),:);
    [x,y] = orderedCurve(T.SA_deg,T.FY_N);
    if numel(x)>=2
        plot(x,y,'LineWidth',1.4,'DisplayName',sprintf('Sweep %d',ids(i)));
    end
end
formatAxes_v52('Slip Angle, \alpha [deg]','Lateral Force, F_Y [N]',...
    sprintf('Reference FY-SA | P %.2f psi | IA %.2f deg | V %.2f mph | FZ %.0f N',...
    Ref.Pressure_Mean_psi,Ref.IA_Mean_deg,Ref.Speed_Mean_mph,Ref.FZ_Mean_N));
legend('Location','best');
file = fullfile(folder,'Reference_FY_vs_SA.png');
pass = finishFigure_v52(fig,file,CFG);
row = figureRow('REFERENCE_FY_SA',file,'curve',pass,...
    sprintf('%d sweep curves plotted',numel(ids)));
end

%% ========================================================================
% LOCAL: REPRESENTATIVE FY-SA
% ========================================================================
function row = plotRepresentativeFYSA_v52(Primary,SC,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
valid = SC(isfinite(SC.FZ_Mean_N),:);
if isempty(valid)
    row = figureRow('REPRESENTATIVE_FY_SA','','curve',false,'No valid sweeps.');
    return;
end
[~,ord] = sort(valid.FZ_Mean_N);
idx = unique(round(linspace(1,height(valid),min(CFG.RepresentativeCurveCount,height(valid)))));
chosen = valid(ord(idx),:);

fig = createCMMFigure_v52(CFG); hold on;
nPlotted = 0;
for i = 1:height(chosen)
    T = Primary(Primary.SweepID==chosen.SweepID(i),:);
    [x,y] = orderedCurve(T.SA_deg,T.FY_N);
    if numel(x)>=2
        plot(x,y,'LineWidth',1.5,'DisplayName',...
            sprintf('F_Z %.0f N | Sweep %d',chosen.FZ_Mean_N(i),chosen.SweepID(i)));
        nPlotted = nPlotted+1;
    end
end
formatAxes_v52('Slip Angle, \alpha [deg]','Lateral Force, F_Y [N]',...
    'Representative FY-SA Curves Across Vertical Load');
legend('Location','best');
file = fullfile(folder,'Representative_FY_vs_SA.png');
pass = finishFigure_v52(fig,file,CFG) && nPlotted>0;
row = figureRow('REPRESENTATIVE_FY_SA',file,'curve',pass,...
    sprintf('%d representative curves plotted',nPlotted));
end

%% ========================================================================
% LOCAL: GENERIC TREND
% ========================================================================
function row = plotTrendFigure_v52(x,y,xlab,ylab,tit,folder,name,detail)
if ~exist(folder,'dir'), mkdir(folder); end
m = isfinite(x) & isfinite(y);
x=x(m); y=y(m);
if isempty(x)
    row = figureRow(name,'','trend',false,'No finite data.');
    return;
end
[x,ord] = sort(x); y=y(ord);

fig = createCMMFigure_v52(struct('BlackFigures',false)); hold on;
plot(x,y,'-o','LineWidth',1.6,'MarkerSize',4);
formatAxes_v52(xlab,ylab,tit);
file=fullfile(folder,name);
pass=finishFigure_v52(fig,file,struct('FigureResolution',220,'SaveFIG',false));
row=figureRow(name,file,'trend',pass,detail);
end

%% ========================================================================
% LOCAL: PEAK STATUS
% ========================================================================
function row = plotPeakStatus_v52(SC,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
fig=createCMMFigure_v52(CFG); hold on;
r=SC(SC.PeakStatus=="RESOLVED",:);
b=SC(SC.PeakStatus=="BOUNDARY_LIMITED",:);
if ~isempty(r)
    [x,ord]=sort(r.FZ_Mean_N);
    plot(x,abs(r.SA_AtPeak_deg(ord)),'-o','LineWidth',1.5,...
        'DisplayName','Resolved peaks');
end
if ~isempty(b)
    [x,ord]=sort(b.FZ_Mean_N);
    plot(x,abs(b.SA_AtPeak_deg(ord)),'--x','LineWidth',1.3,...
        'DisplayName','Boundary-limited peaks');
end
formatAxes_v52('Measured Vertical Load, F_Z [N]',...
    '|Observed Slip Angle at Maximum |F_Y|| [deg]',...
    'Peak Slip-Angle Status vs Vertical Load');
legend('Location','best');
file=fullfile(folder,'Peak_Slip_Angle_Status_vs_FZ.png');
pass=finishFigure_v52(fig,file,CFG);
row=figureRow('PEAK_SLIP_ANGLE',file,'trend',pass,...
    sprintf('%d resolved / %d boundary-limited',height(r),height(b)));
end

%% ========================================================================
% LOCAL: PRESSURE/CAMBER SENSITIVITY
% ========================================================================
function row = plotSensitivityTrend_v52(C,mode,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
mode=upper(string(mode));
if mode=="PRESSURE"
    state=round(C.Pressure_Mean_psi);
    states=unique(state);
    titleText=sprintf('Pressure Sensitivity | IA≈%.1f° | V≈%.0f mph',...
        CFG.ReferenceIA_deg,CFG.ReferenceSpeed_mph);
    xlab='Measured Vertical Load, F_Z [N]';
    ylab='Peak |F_Y| [N]';
    name='Pressure_Sensitivity_PeakFY.png';
    prefix='Pressure';
else
    state=round(C.IA_Mean_deg);
    states=unique(state);
    titleText=sprintf('Camber Sensitivity | P≈%.0f psi | V≈%.0f mph',...
        CFG.ReferencePressure_psi,CFG.ReferenceSpeed_mph);
    xlab='Measured Vertical Load, F_Z [N]';
    ylab='Peak |F_Y| [N]';
    name='Camber_Sensitivity_PeakFY.png';
    prefix='IA';
end

fig=createCMMFigure_v52(CFG); hold on;
n=0;
for i=1:numel(states)
    if mode=="PRESSURE"
        m=state==states(i) & abs(C.IA_Mean_deg-CFG.ReferenceIA_deg)<=CFG.MatchIA_deg;
    else
        m=state==states(i) & abs(C.Pressure_Mean_psi-CFG.ReferencePressure_psi)<=CFG.MatchPressure_psi;
    end
    if ~any(m), continue; end
    X=C(m,:);
    [x,ord]=sort(X.FZ_Mean_N);
    y=X.PeakFY_Mean_N(ord);
    if numel(x)>=2
        plot(x,y,'-o','LineWidth',1.4,...
            'DisplayName',sprintf('%s %g',prefix,states(i)));
        n=n+1;
    end
end
formatAxes_v52(xlab,ylab,titleText);
if n>0, legend('Location','best'); end
file=fullfile(folder,name);
pass=finishFigure_v52(fig,file,CFG) && n>0;
row=figureRow(char(mode),file,'trend',pass,...
    sprintf('%d valid state curves',n));
end

%% ========================================================================
% LOCAL: SPEED VALIDATION
% ========================================================================
function row = plotSpeedValidation_v52(Primary,Validation,SC,VSC,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
fig=createCMMFigure_v52(CFG); hold on;
n=0;

% Plot validation curves, one per sweep, sorted by speed.
if ~isempty(VSC)
    [~,ord]=sort(VSC.Speed_Mean_mph);
    for i=1:numel(ord)
        r=VSC(ord(i),:);
        T=Validation(Validation.SweepID==r.SweepID,:);
        [x,y]=orderedCurve(T.SA_deg,T.FY_N);
        if numel(x)>=2
            plot(x,y,'LineWidth',1.3,...
                'DisplayName',sprintf('Validation %.1f mph | FZ %.0f N',...
                r.Speed_Mean_mph,r.FZ_Mean_N));
            n=n+1;
        end
    end
end

% Add closest primary reference-speed curve.
m=abs(SC.Speed_Mean_mph-CFG.ReferenceSpeed_mph)<=CFG.MatchSpeed_mph;
if any(m)
    X=SC(m,:);
    [~,ii]=min(abs(X.FZ_Mean_N-median(VSC.FZ_Mean_N,'omitnan')));
    r=X(ii,:);
    T=Primary(Primary.SweepID==r.SweepID,:);
    [x,y]=orderedCurve(T.SA_deg,T.FY_N);
    if numel(x)>=2
        plot(x,y,'k--','LineWidth',1.8,...
            'DisplayName',sprintf('Primary %.1f mph | FZ %.0f N',...
            r.Speed_Mean_mph,r.FZ_Mean_N));
        n=n+1;
    end
end

formatAxes_v52('Slip Angle, \alpha [deg]','Lateral Force, F_Y [N]',...
    'Speed Validation — FY-SA Curves');
if n>0, legend('Location','best'); end
file=fullfile(folder,'Speed_Validation_FY_vs_SA.png');
pass=finishFigure_v52(fig,file,CFG) && n>0;
row=figureRow('SPEED_VALIDATION',file,'curve',pass,...
    sprintf('%d curves plotted; validation remains isolated',n));
end

%% ========================================================================
% LOCAL: REPEATABILITY
% ========================================================================
function row = plotRepeatability_v52(Primary,R,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
if isempty(R)
    row=figureRow('REPEATABILITY','','curve',false,'No repeated conditions found.');
    return;
end
% Choose the repeated condition with the largest repeat count.
[~,ii]=max(R.RepeatCount);
cid=R.ConditionID(ii);
T=Primary(Primary.ConditionID==cid,:);
ids=unique(T.SweepID);

fig=createCMMFigure_v52(CFG); hold on;
n=0;
for i=1:numel(ids)
    X=T(T.SweepID==ids(i),:);
    [x,y]=orderedCurve(X.SA_deg,X.FY_N);
    if numel(x)>=2
        plot(x,y,'LineWidth',1.4,'DisplayName',sprintf('Sweep %d',ids(i)));
        n=n+1;
    end
end
formatAxes_v52('Slip Angle, \alpha [deg]','Lateral Force, F_Y [N]',...
    sprintf('Repeatability Overlay | Condition %d',cid));
legend('Location','best');
file=fullfile(folder,sprintf('Condition_%03d_Repeatability.png',cid));
pass=finishFigure_v52(fig,file,CFG) && n>=2;
row=figureRow('REPEATABILITY',file,'curve',pass,...
    sprintf('Condition %d: %d repeat curves',cid,n));
end

%% ========================================================================
% LOCAL: SYMMETRY
% ========================================================================
function row = plotSymmetry_v52(Sym,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
m=isfinite(Sym.FZ_Mean_N)&isfinite(Sym.SymmetryRatio);
x=Sym.FZ_Mean_N(m); y=Sym.SymmetryRatio(m);
if isempty(x)
    row=figureRow('SYMMETRY','','trend',false,'No finite symmetry data.');
    return;
end
[x,ord]=sort(x); y=y(ord);
fig=createCMMFigure_v52(CFG); hold on;
plot(x,y,'-o','LineWidth',1.5,'MarkerSize',4,'DisplayName','Measured symmetry');
yline(1,'--','Ideal symmetry','LineWidth',1.2);
formatAxes_v52('Measured Vertical Load, F_Z [N]',...
    '|Positive Peak F_Y| / |Negative Peak F_Y|',...
    'Sweep Force Symmetry vs Vertical Load');
legend('Location','best');
file=fullfile(folder,'Sweep_Symmetry_vs_FZ.png');
pass=finishFigure_v52(fig,file,CFG);
row=figureRow('SYMMETRY',file,'trend',pass,'Ordered symmetry trend');
end

%% ========================================================================
% LOCAL: STIFFNESS WINDOW QC
% ========================================================================
function row = plotStiffnessWindowQC(Primary,SC,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
ids=chooseRepresentativeSweeps_v52(SC,6);
fig=createCMMFigure_v52(CFG); hold on;
n=0;
for q=1:numel(ids)
    T=Primary(Primary.SweepID==ids(q),:);
    SA=double(T.SA_deg); FY=double(T.FY_N);
    m=isfinite(SA)&isfinite(FY);
    SA=SA(m); FY=FY(m);
    if numel(SA)<CFG.MinStiffnessSamples, continue; end
    vals=nan(size(CFG.StiffnessWindows_deg));
    for j=1:numel(CFG.StiffnessWindows_deg)
        mm=abs(SA)<=CFG.StiffnessWindows_deg(j);
        if sum(mm)>=CFG.MinStiffnessSamples
            p=polyfit(SA(mm),FY(mm),1);
            vals(j)=-p(1);
        end
    end
    plot(CFG.StiffnessWindows_deg,vals,'-o','LineWidth',1.2,...
        'DisplayName',sprintf('Sweep %d',ids(q)));
    n=n+1;
end
formatAxes_v52('Linear-fit window, |SA| [deg]',...
    'Engineering-positive C_\alpha [N/deg]',...
    'Cornering Stiffness Sensitivity to Fit Window');
legend('Location','best');
file=fullfile(folder,'Cornering_Stiffness_Window_Sensitivity.png');
pass=finishFigure_v52(fig,file,CFG)&&n>0;
row=figureRow('STIFFNESS_WINDOW_QC',file,'trend',pass,...
    sprintf('%d representative sweeps',n));
end

%% ========================================================================
% LOCAL: PEAK QC
% ========================================================================
function row = plotOutlierQC_v52(SC,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
fig=createCMMFigure_v52(CFG); hold on;
classes=["NORMAL","HIGH_MU","EXTREME_MU","LOW_LOAD"];
markers={'-o','-s','--x',':d'};
n=0;
for i=1:numel(classes)
    m=SC.LoadQC==classes(i);
    if any(m)
        [x,ord]=sort(SC.FZ_Mean_N(m));
        y=SC.MuY_Peak(m); y=y(ord);
        plot(x,y,markers{i},'LineWidth',1.3,'DisplayName',classes(i));
        n=n+1;
    end
end
yline(CFG.HighMuThreshold,'--','High-\mu flag','LineWidth',1);
yline(CFG.ExtremeMuThreshold,':','Extreme-\mu flag','LineWidth',1);
formatAxes_v52('Measured Vertical Load, F_Z [N]','Peak \mu_y',...
    'Physics QC — Peak Friction Coefficient Classification');
legend('Location','best');
file=fullfile(folder,'Peak_MuY_QC_vs_FZ.png');
pass=finishFigure_v52(fig,file,CFG)&&n>0;
row=figureRow('PEAK_QC',file,'trend',pass,...
    sprintf('%d QC classes represented',n));
end

%% ========================================================================
% LOCAL: PHYSICS OUTLIER QC
% ========================================================================
function row = plotPhysicsOutlierQC_v52(SC,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
fig=createCMMFigure_v52(CFG); hold on;
m=isfinite(SC.FZ_Mean_N)&isfinite(SC.MuY_Peak);
X=SC(m,:);
[X.FZ_Mean_N,ord]=sort(X.FZ_Mean_N);
X.MuY_Peak=X.MuY_Peak(ord);
plot(X.FZ_Mean_N,X.MuY_Peak,'-o','LineWidth',1.4,...
    'DisplayName','All measured sweeps');
high=X.MuY_Peak>=CFG.HighMuThreshold;
if any(high)
    plot(X.FZ_Mean_N(high),X.MuY_Peak(high),'rx','LineWidth',1.8,...
        'MarkerSize',9,'DisplayName','High-\mu / extreme flag');
end
low=X.FZ_Mean_N<CFG.LowLoadThreshold_N;
if any(low)
    plot(X.FZ_Mean_N(low),X.MuY_Peak(low),'ks','LineWidth',1.4,...
        'MarkerSize',7,'DisplayName','Low-load flag');
end
formatAxes_v52('Measured Vertical Load, F_Z [N]','Peak \mu_y',...
    'Physics Outlier Audit — Flags Preserved, Not Deleted');
legend('Location','best');
file=fullfile(folder,'Physics_Outlier_Audit.png');
pass=finishFigure_v52(fig,file,CFG)&&~isempty(X);
row=figureRow('OUTLIER_QC',file,'trend',pass,...
    sprintf('%d finite sweep points',height(X)));
end

%% ========================================================================
% LOCAL: FIGURE AUDIT PLOT
% ========================================================================
function row = plotFigureAudit_v52(A,CFG,folder)
if ~exist(folder,'dir'), mkdir(folder); end
if isempty(A)
    row=figureRow('FIGURE_AUDIT','','bar',false,'No figure records.');
    return;
end
passCount=sum(A.Pass);
failCount=sum(~A.Pass);
fig=createCMMFigure_v52(CFG);
bar(categorical(["PASS","FAIL"]),[passCount failCount]);
ylabel('Figure count');
title('v5.2 Figure Generation Audit');
grid on; box on;
file=fullfile(folder,'Figure_Generation_Audit.png');
pass=finishFigure_v52(fig,file,CFG);
row=figureRow('FIGURE_AUDIT',file,'bar',pass,...
    sprintf('%d PASS / %d FAIL',passCount,failCount));
end

%% ========================================================================
% LOCAL: ORDERED CURVE
% ========================================================================
function [x,y] = orderedCurve(x,y)
x=double(x(:)); y=double(y(:));
m=isfinite(x)&isfinite(y);
x=x(m); y=y(m);
if isempty(x), return; end
[x,ord]=sort(x,'ascend');
y=y(ord);
% Remove exact duplicate x values without altering measured y values:
% retain their mean only for plotting, never for characterization tables.
[ux,~,g]=unique(x);
if numel(ux)<numel(x)
    uy=accumarray(g,y,[],@mean);
    x=ux; y=uy;
end
end

%% ========================================================================
% LOCAL: REPRESENTATIVE IDS
% ========================================================================
function ids=chooseRepresentativeSweeps_v52(SC,n)
valid=SC(isfinite(SC.FZ_Mean_N),:);
if isempty(valid), ids=[]; return; end
[~,ord]=sort(valid.FZ_Mean_N);
idx=unique(round(linspace(1,height(valid),min(n,height(valid)))));
ids=valid.SweepID(ord(idx));
end

%% ========================================================================
% LOCAL: FIGURE CREATION / FINISH
% ========================================================================
function fig=createCMMFigure_v52(CFG)
fig=figure('Visible','off','Position',[100 100 1150 720],...
    'Color','w');
ax=axes(fig);
set(ax,'FontSize',11,'LineWidth',1);
grid(ax,'on'); box(ax,'on');
if isfield(CFG,'BlackFigures') && CFG.BlackFigures
    set(fig,'Color','k','InvertHardcopy','off');
    set(ax,'Color','k','XColor','w','YColor','w',...
        'GridColor',[.45 .45 .45]);
end
end

function formatAxes_v52(xlab,ylab,tit)
xlabel(xlab,'Interpreter','tex');
ylabel(ylab,'Interpreter','tex');
title(tit,'Interpreter','tex');
grid on; box on;
end

function pass=finishFigure_v52(fig,file,CFG)
pass=false;
try
    drawnow;
    if isfield(CFG,'FigureResolution')
        exportgraphics(fig,file,'Resolution',CFG.FigureResolution);
    else
        exportgraphics(fig,file,'Resolution',220);
    end
    pass=exist(file,'file') && dir(file).bytes>1000;
    if isfield(CFG,'SaveFIG') && CFG.SaveFIG
        savefig(fig,strrep(file,'.png','.fig'));
    end
catch
    pass=false;
end
close(fig);
end

%% ========================================================================
% LOCAL: CHECKS
% ========================================================================
function [names,passes,details]=addCheck(names,passes,details,name,tf,detail)
names(end+1,1)=string(name);
passes(end+1,1)=logical(tf);
details(end+1,1)=string(detail);
end

function out=passFail_v52(tf)
if tf, out="PASS"; else, out="FAIL"; end
end
