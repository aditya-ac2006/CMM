%% ╔══════════════════════════════════════════════════════════════╗
%  ║       CMM TTC LATERAL MODEL DATABASE BUILDER v4.0          ║
%  ║     Clean Sweeps → Canonical Database → Model Contract     ║
%  ╚══════════════════════════════════════════════════════════════╝
%
% CMM Formula Student Tire Modeling Pipeline
%
% =========================================================================
% PURPOSE
% =========================================================================
%
% This is the FINAL DATABASE GENERATION stage before tire
% characterization and Magic Formula fitting.
%
% INPUT:
%
%   CMM_SWEEP_EXTRACTOR_CONTRACT_v3_2.mat
%
% FROM STAGE 3:
%
%   PRIMARY_MODEL_FIT
%       → 7-inch CORNERING data
%       → Runs 2 + 4
%       → QC accepted
%
%   VALIDATION_SPEED_DATA
%       → speed-test sweeps
%       → kept separate from fitting database
%
% THIS STAGE:
%
%   ✓ validates Stage-3 contract
%   ✓ validates sample-level channels
%   ✓ removes invalid/non-finite samples
%   ✓ enforces positive loaded FZ convention
%   ✓ preserves raw FY sign
%   ✓ creates canonical sample IDs
%   ✓ creates canonical sweep IDs
%   ✓ creates operating-condition IDs
%   ✓ builds PRIMARY model database
%   ✓ builds SPEED VALIDATION database
%   ✓ builds sweep manifest
%   ✓ builds condition manifest
%   ✓ builds coverage matrix
%   ✓ performs final database integrity checks
%   ✓ exports CSV + MAT + TXT contract
%
% IMPORTANT:
%
% THIS STAGE DOES NOT:
%
%   ✗ re-detect sweeps
%   ✗ re-run Stage-3 QC
%   ✗ average tire curves
%   ✗ fit Magic Formula
%   ✗ modify measured tire forces
%
% Stage 3 remains authoritative for sweep acceptance.
%
% =========================================================================
% PIPELINE
% =========================================================================
%
% CMM_OUTPUT_V02
%
%   01_FILE_RUN_MAPPER
%           ↓
%   02_OPERATING_CONDITION_SEGMENTER
%           ↓
%   03_SWEEP_EXTRACTOR
%           ↓
%   04_LATERAL_MODEL_DATABASE
%           ↓
%   05_LATERAL_CHARACTERIZATION
%           ↓
%   06_MAGIC_FORMULA_FITTER
%           ↓
%   07_MODEL_VALIDATION
%
% Version: 4.0
% =========================================================================

clear;
clc;
close all;

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║       CMM TTC LATERAL MODEL DATABASE BUILDER v4.0          ║\n');
fprintf('║     Clean Sweeps → Canonical Database → Model Contract     ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');


%% ========================================================================
% CONFIGURATION
% =========================================================================

CFG = struct();

CFG.Version = "4.0";

CFG.Pipeline = "CMM_OUTPUT_V02";

CFG.ModelName = "CMM_7IN_LATERAL_MODEL";

CFG.TireModel = "43075 16x7.5-10";

CFG.Compound = "R25B";

CFG.RimWidth_in = 7.0;

CFG.RequiredRuns = [2 4];

CFG.RequiredTestFamily = "CORNERING";


%% ------------------------------------------------------------------------
% EXPECTED STAGE-3 DATABASE
% -------------------------------------------------------------------------

CFG.ExpectedPrimarySweeps = 80;

CFG.ExpectedValidationSweeps = 10;

CFG.ExpectedTotalSweeps = 90;


%% ------------------------------------------------------------------------
% SAMPLE VALIDATION
% -------------------------------------------------------------------------

CFG.MinLoadedFZ_N = 50;

CFG.MaxLoadedFZ_N = 2000;

CFG.MaxAbsSA_deg = 20;

CFG.MaxAbsIA_deg = 10;

CFG.MinPressure_kPa = 30;

CFG.MaxPressure_kPa = 150;

CFG.MinSpeed_kph = 5;

CFG.MaxSpeed_kph = 150;


%% ------------------------------------------------------------------------
% CONDITION GROUPING
% ------------------------------------------------------------------------
%
% These are ONLY labels used to build the operating-condition manifest.
%
% Actual measured values are preserved separately.
%

CFG.FZConditionBin_N = 50;

CFG.PressureConditionBin_psi = 1;

CFG.IAConditionBin_deg = 1;

CFG.SpeedConditionBin_mph = 1;


%% ------------------------------------------------------------------------
% OUTPUT
% -------------------------------------------------------------------------

CFG.OutputRoot = "CMM_OUTPUT_V02";

CFG.StageFolder = "04_LATERAL_MODEL_DATABASE";

CFG.TableFolder = "TABLES";


%% ========================================================================
% [1] SELECT TTC PROJECT FOLDER
% =========================================================================

fprintf('[1] SELECT TTC PROJECT FOLDER\n');
fprintf('──────────────────────────────────────────────────────────────\n');

projectFolder = uigetdir( ...
    pwd, ...
    'Select TTC project folder');

if isequal(projectFolder,0)

    error( ...
        'CMM:UserCancelled', ...
        'Folder selection cancelled.');

end

fprintf('Selected folder:\n%s\n\n',projectFolder);


%% ========================================================================
% [2] LOCATE STAGE-3 CONTRACT
% =========================================================================

fprintf('[2] LOCATING STAGE-3 CONTRACT\n');
fprintf('──────────────────────────────────────────────────────────────\n');

thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));
outputRoot = fullfile(repoRoot,'outputs',CFG.OutputRoot);

preferredLocations = { ...

    fullfile( ...
        outputRoot, ...
        '03_SWEEP_EXTRACTOR', ...
        'CMM_SWEEP_EXTRACTOR_CONTRACT_v3_2.mat') ...
    };


contractPath = "";

for i = 1:numel(preferredLocations)

    if exist(preferredLocations{i},'file')

        contractPath = string(preferredLocations{i});

        break;

    end

end


if strlength(contractPath) == 0

    fprintf('Preferred location not found.\n');
    fprintf('Searching project recursively...\n');

    results = dir(fullfile( ...
        projectFolder, ...
        '**', ...
        'CMM_SWEEP_EXTRACTOR_CONTRACT_v3_2.mat'));

    if isempty(results)

        error( ...
            'CMM:Stage3ContractMissing', ...
            ['Unable to locate ' ...
             'CMM_SWEEP_EXTRACTOR_CONTRACT_v3_2.mat']);

    end

    contractPath = string(fullfile( ...
        results(1).folder, ...
        results(1).name));

end


fprintf('Stage-3 contract found:\n%s\n\n',contractPath);


%% ========================================================================
% [3] LOAD STAGE-3 CONTRACT
% =========================================================================

fprintf('[3] LOADING STAGE-3 CONTRACT\n');
fprintf('──────────────────────────────────────────────────────────────\n');

S = load(contractPath);


if isfield(S,'SweepExtractorContract')

    Stage3 = S.SweepExtractorContract;

    fprintf('Contract variable : SweepExtractorContract\n');

else

    names = fieldnames(S);

    fprintf('\nVariables found in MAT file:\n');

    for i = 1:numel(names)

        fprintf('  %s\n',names{i});

    end

    error( ...
        'CMM:InvalidStage3Contract', ...
        'SweepExtractorContract was not found.');

end


fprintf('\nStage-3 fields:\n');

stage3Fields = fieldnames(Stage3);

for i = 1:numel(stage3Fields)

    fprintf('  %-35s',stage3Fields{i});

    value = Stage3.(stage3Fields{i});

    if istable(value)

        fprintf(' table [%d x %d]', ...
            height(value), ...
            width(value));

    elseif isnumeric(value)

        fprintf(' numeric %s', ...
            mat2str(size(value)));

    elseif isstruct(value)

        fprintf(' struct');

    end

    fprintf('\n');

end

fprintf('\n');


%% ========================================================================
% [4] EXTRACT PRIMARY + VALIDATION DATABASES
% =========================================================================

fprintf('[4] EXTRACTING STAGE-3 DATABASES\n');
fprintf('──────────────────────────────────────────────────────────────\n');


if isfield(Stage3,'CleanLateralDatabase')

    PrimaryRaw = Stage3.CleanLateralDatabase;

else

    error( ...
        'CMM:PrimaryDatabaseMissing', ...
        'Stage-3 CleanLateralDatabase not found.');

end


if isfield(Stage3,'ValidationSpeedDatabase')

    ValidationRaw = Stage3.ValidationSpeedDatabase;

else

    warning( ...
        'CMM:ValidationDatabaseMissing', ...
        'ValidationSpeedDatabase not found.');

    ValidationRaw = PrimaryRaw([],:);

end


if ~istable(PrimaryRaw)

    error( ...
        'CMM:InvalidPrimaryDatabase', ...
        'CleanLateralDatabase must be a MATLAB table.');

end


if ~istable(ValidationRaw)

    error( ...
        'CMM:InvalidValidationDatabase', ...
        'ValidationSpeedDatabase must be a MATLAB table.');

end


fprintf('Primary samples       : %d\n',height(PrimaryRaw));
fprintf('Validation samples    : %d\n',height(ValidationRaw));

fprintf('\n');


%% ========================================================================
% [5] DISCOVER DATABASE CHANNELS
% =========================================================================

fprintf('[5] VALIDATING DATABASE CHANNELS\n');
fprintf('──────────────────────────────────────────────────────────────\n');


requiredChannels = [ ...
    "FullSweepID", ...
    "Stage2RegionID", ...
    "RunNumber", ...
    "ET_s", ...
    "SA_deg", ...
    "FY_N", ...
    "FZ_Load_N", ...
    "IA_deg", ...
    "P_kPa", ...
    "V_kph"];


primaryVars = string( ...
    PrimaryRaw.Properties.VariableNames);


channelPass = true;


for i = 1:numel(requiredChannels)

    channel = requiredChannels(i);

    if ismember(channel,primaryVars)

        fprintf('  ✓ %-20s\n',channel);

    else

        fprintf('  ✗ %-20s MISSING\n',channel);

        channelPass = false;

    end

end


if ~channelPass

    fprintf('\nVariables actually present:\n');

    for i = 1:numel(primaryVars)

        fprintf('  %s\n',primaryVars(i));

    end

    error( ...
        'CMM:MissingDatabaseChannels', ...
        'Stage-3 primary database is missing required channels.');

end

fprintf('\nChannel validation : PASS\n\n');


%% ========================================================================
% [6] VALIDATE RUN ROUTING
% =========================================================================

fprintf('[6] VALIDATING RUN ROUTING\n');
fprintf('──────────────────────────────────────────────────────────────\n');


runsPresent = unique(PrimaryRaw.RunNumber);

fprintf('Runs in primary database : ');

fprintf('%d ',runsPresent);

fprintf('\n');


invalidRuns = ...
    ~ismember(runsPresent,CFG.RequiredRuns);


if any(invalidRuns)

    fprintf('Invalid runs detected : ');

    fprintf('%d ',runsPresent(invalidRuns));

    fprintf('\n');

    error( ...
        'CMM:InvalidRunRouting', ...
        'Primary database contains runs outside Runs 2 + 4.');

end


if ~all(ismember(CFG.RequiredRuns,runsPresent))

    warning( ...
        'CMM:MissingRequiredRun', ...
        'Not all expected Runs 2 + 4 are represented.');

end


fprintf('Allowed runs          : 2 4\n');
fprintf('Run routing           : PASS\n\n');


%% ========================================================================
% [7] VALIDATE STAGE-3 SWEEP ROUTING
% =========================================================================

fprintf('[7] VALIDATING SWEEP ROUTING\n');
fprintf('──────────────────────────────────────────────────────────────\n');


primarySweepIDs = unique( ...
    PrimaryRaw.FullSweepID);

validationSweepIDs = unique( ...
    ValidationRaw.FullSweepID);


nPrimarySweeps = numel(primarySweepIDs);

nValidationSweeps = numel(validationSweepIDs);


fprintf('Primary sweeps       : %d\n',nPrimarySweeps);
fprintf('Validation sweeps    : %d\n',nValidationSweeps);


if nPrimarySweeps == CFG.ExpectedPrimarySweeps

    fprintf('Expected primary     : PASS\n');

else

    fprintf( ...
        'Expected primary     : WARNING (%d expected)\n', ...
        CFG.ExpectedPrimarySweeps);

end


if nValidationSweeps == CFG.ExpectedValidationSweeps

    fprintf('Expected validation  : PASS\n');

else

    fprintf( ...
        'Expected validation  : WARNING (%d expected)\n', ...
        CFG.ExpectedValidationSweeps);

end


overlap = intersect( ...
    primarySweepIDs, ...
    validationSweepIDs);


if isempty(overlap)

    fprintf('Routing overlap      : PASS\n');

else

    error( ...
        'CMM:RoutingOverlap', ...
        ['Primary and validation databases contain ' ...
         'overlapping sweep IDs.']);

end

fprintf('\n');


%% ========================================================================
% [8] SAMPLE-LEVEL SANITIZATION
% =========================================================================

fprintf('[8] SAMPLE-LEVEL SANITIZATION\n');
fprintf('──────────────────────────────────────────────────────────────\n');


[PrimaryClean,PrimaryCleaningReport] = ...
    sanitizeDatabase( ...
        PrimaryRaw, ...
        CFG, ...
        "PRIMARY_MODEL_FIT");


[ValidationClean,ValidationCleaningReport] = ...
    sanitizeDatabase( ...
        ValidationRaw, ...
        CFG, ...
        "VALIDATION_SPEED_DATA");


fprintf('\nPRIMARY MODEL DATABASE\n');
fprintf('──────────────────────────────────────────────────────────────\n');

printCleaningReport(PrimaryCleaningReport);


fprintf('\nSPEED VALIDATION DATABASE\n');
fprintf('──────────────────────────────────────────────────────────────\n');

printCleaningReport(ValidationCleaningReport);

fprintf('\n');


%% ========================================================================
% [9] BUILD CANONICAL PRIMARY DATABASE
% =========================================================================

fprintf('[9] BUILDING CANONICAL PRIMARY DATABASE\n');
fprintf('──────────────────────────────────────────────────────────────\n');


PrimaryDatabase = ...
    buildCanonicalDatabase( ...
        PrimaryClean, ...
        CFG, ...
        "PRIMARY_MODEL_FIT");


fprintf('Samples generated : %d\n', ...
    height(PrimaryDatabase));

fprintf('Sweeps represented: %d\n', ...
    numel(unique(PrimaryDatabase.SweepID)));

fprintf('\n');


%% ========================================================================
% [10] BUILD CANONICAL SPEED VALIDATION DATABASE
% =========================================================================

fprintf('[10] BUILDING SPEED VALIDATION DATABASE\n');
fprintf('──────────────────────────────────────────────────────────────\n');


ValidationDatabase = ...
    buildCanonicalDatabase( ...
        ValidationClean, ...
        CFG, ...
        "VALIDATION_SPEED_DATA");


fprintf('Samples generated : %d\n', ...
    height(ValidationDatabase));

fprintf('Sweeps represented: %d\n', ...
    numel(unique(ValidationDatabase.SweepID)));

fprintf('\n');


%% ========================================================================
% [11] ASSIGN OPERATING CONDITION IDS
% =========================================================================

fprintf('[11] ASSIGNING OPERATING CONDITION IDS\n');
fprintf('──────────────────────────────────────────────────────────────\n');


[PrimaryDatabase,ConditionManifest] = ...
    assignConditionIDs( ...
        PrimaryDatabase, ...
        CFG);


fprintf('Operating conditions : %d\n', ...
    height(ConditionManifest));


fprintf('\nDetected condition states:\n');


pressureStates = unique( ...
    ConditionManifest.Pressure_State_psi);

loadStates = unique( ...
    ConditionManifest.FZ_State_N);

IAStates = unique( ...
    ConditionManifest.IA_State_deg);

speedStates = unique( ...
    ConditionManifest.Speed_State_mph);


fprintf('Pressure : ');

fprintf('%.0f ',pressureStates);

fprintf('psi\n');


fprintf('FZ       : ');

fprintf('%.0f ',loadStates);

fprintf('N\n');


fprintf('IA       : ');

fprintf('%.0f ',IAStates);

fprintf('deg\n');


fprintf('Speed    : ');

fprintf('%.0f ',speedStates);

fprintf('mph\n\n');


%% ========================================================================
% [12] ASSIGN VALIDATION CONDITION IDS
% =========================================================================

fprintf('[12] ASSIGNING VALIDATION CONDITION IDS\n');
fprintf('──────────────────────────────────────────────────────────────\n');


if ~isempty(ValidationDatabase)

    [ValidationDatabase,ValidationConditionManifest] = ...
        assignConditionIDs( ...
            ValidationDatabase, ...
            CFG);

else

    ValidationConditionManifest = table();

end


fprintf('Validation conditions : %d\n\n', ...
    height(ValidationConditionManifest));


%% ========================================================================
% [13] BUILD SWEEP MANIFEST
% =========================================================================

fprintf('[13] BUILDING SWEEP MANIFEST\n');
fprintf('──────────────────────────────────────────────────────────────\n');


PrimarySweepManifest = ...
    buildSweepManifest( ...
        PrimaryDatabase, ...
        "PRIMARY_MODEL_FIT");


ValidationSweepManifest = ...
    buildSweepManifest( ...
        ValidationDatabase, ...
        "VALIDATION_SPEED_DATA");


SweepManifest = [ ...
    PrimarySweepManifest; ...
    ValidationSweepManifest];


fprintf('Primary sweeps    : %d\n', ...
    height(PrimarySweepManifest));

fprintf('Validation sweeps : %d\n', ...
    height(ValidationSweepManifest));

fprintf('Total sweeps      : %d\n\n', ...
    height(SweepManifest));


%% ========================================================================
% [14] BUILD OPERATING CONDITION COVERAGE MATRIX
% =========================================================================

fprintf('[14] BUILDING OPERATING CONDITION COVERAGE MATRIX\n');
fprintf('──────────────────────────────────────────────────────────────\n');


CoverageMatrix = ...
    buildCoverageMatrix( ...
        PrimarySweepManifest);


fprintf('Coverage combinations : %d\n\n', ...
    height(CoverageMatrix));


fprintf('PRIMARY MODEL CONDITION COVERAGE:\n\n');

disp(CoverageMatrix);


%% ========================================================================
% [15] DATABASE INTEGRITY CHECKS
% =========================================================================

fprintf('[15] DATABASE INTEGRITY CHECKS\n');
fprintf('──────────────────────────────────────────────────────────────\n');


checkNames = strings(0,1);

checkPass = false(0,1);

checkDetails = strings(0,1);


%% ------------------------------------------------------------------------
% PRIMARY DATABASE NONEMPTY
% -------------------------------------------------------------------------

checkNames(end+1,1) = ...
    "PRIMARY_DATABASE_NONEMPTY";

checkPass(end+1,1) = ...
    ~isempty(PrimaryDatabase);

checkDetails(end+1,1) = sprintf( ...
    '%d samples', ...
    height(PrimaryDatabase));


%% ------------------------------------------------------------------------
% FINITE PRIMARY CHANNELS
% -------------------------------------------------------------------------

finitePrimary = ...
    all(isfinite(PrimaryDatabase.SA_deg)) && ...
    all(isfinite(PrimaryDatabase.FY_N)) && ...
    all(isfinite(PrimaryDatabase.FZ_N)) && ...
    all(isfinite(PrimaryDatabase.IA_deg)) && ...
    all(isfinite(PrimaryDatabase.P_kPa)) && ...
    all(isfinite(PrimaryDatabase.V_kph));


checkNames(end+1,1) = ...
    "PRIMARY_CHANNELS_FINITE";

checkPass(end+1,1) = ...
    finitePrimary;

checkDetails(end+1,1) = ...
    passFail(finitePrimary);


%% ------------------------------------------------------------------------
% POSITIVE LOADED FZ
% -------------------------------------------------------------------------

positiveFZ = ...
    all(PrimaryDatabase.FZ_N > 0);


checkNames(end+1,1) = ...
    "POSITIVE_LOADED_FZ";

checkPass(end+1,1) = ...
    positiveFZ;

checkDetails(end+1,1) = sprintf( ...
    'FZ %.1f → %.1f N', ...
    min(PrimaryDatabase.FZ_N), ...
    max(PrimaryDatabase.FZ_N));


%% ------------------------------------------------------------------------
% RUN ROUTING
% -------------------------------------------------------------------------

runPass = ...
    all(ismember( ...
        unique(PrimaryDatabase.RunNumber), ...
        CFG.RequiredRuns));


checkNames(end+1,1) = ...
    "RUN_ROUTING";

checkPass(end+1,1) = ...
    runPass;

checkDetails(end+1,1) = ...
    "Runs 2 + 4 only";


%% ------------------------------------------------------------------------
% PRIMARY / VALIDATION ISOLATION
% -------------------------------------------------------------------------

databaseOverlap = intersect( ...
    unique(PrimaryDatabase.OriginalFullSweepID), ...
    unique(ValidationDatabase.OriginalFullSweepID));


isolationPass = isempty(databaseOverlap);


checkNames(end+1,1) = ...
    "PRIMARY_VALIDATION_ISOLATION";

checkPass(end+1,1) = ...
    isolationPass;

checkDetails(end+1,1) = ...
    passFail(isolationPass);


%% ------------------------------------------------------------------------
% UNIQUE SAMPLE IDS
% -------------------------------------------------------------------------

sampleIDPass = ...
    numel(unique(PrimaryDatabase.SampleID)) == ...
    height(PrimaryDatabase);


checkNames(end+1,1) = ...
    "UNIQUE_PRIMARY_SAMPLE_IDS";

checkPass(end+1,1) = ...
    sampleIDPass;

checkDetails(end+1,1) = ...
    passFail(sampleIDPass);


%% ------------------------------------------------------------------------
% CONDITION ID ASSIGNMENT
% -------------------------------------------------------------------------

conditionPass = ...
    all(PrimaryDatabase.ConditionID > 0);


checkNames(end+1,1) = ...
    "CONDITION_ID_ASSIGNMENT";

checkPass(end+1,1) = ...
    conditionPass;

checkDetails(end+1,1) = sprintf( ...
    '%d conditions', ...
    height(ConditionManifest));


%% ------------------------------------------------------------------------
% SWEEP ID ASSIGNMENT
% -------------------------------------------------------------------------

sweepPass = ...
    all(PrimaryDatabase.SweepID > 0);


checkNames(end+1,1) = ...
    "SWEEP_ID_ASSIGNMENT";

checkPass(end+1,1) = ...
    sweepPass;

checkDetails(end+1,1) = sprintf( ...
    '%d sweeps', ...
    numel(unique(PrimaryDatabase.SweepID)));


%% ------------------------------------------------------------------------
% NO SAMPLE LOSS BY ID GENERATION
% -------------------------------------------------------------------------

samplePreservationPass = ...
    height(PrimaryDatabase) == ...
    height(PrimaryClean);


checkNames(end+1,1) = ...
    "CANONICAL_BUILD_SAMPLE_PRESERVATION";

checkPass(end+1,1) = ...
    samplePreservationPass;

checkDetails(end+1,1) = sprintf( ...
    '%d → %d samples', ...
    height(PrimaryClean), ...
    height(PrimaryDatabase));


%% ------------------------------------------------------------------------
% EXPECTED SWEEP COUNT
% -------------------------------------------------------------------------

expectedSweepPass = ...
    numel(unique(PrimaryDatabase.SweepID)) == ...
    CFG.ExpectedPrimarySweeps;


checkNames(end+1,1) = ...
    "EXPECTED_PRIMARY_SWEEP_COUNT";

checkPass(end+1,1) = ...
    expectedSweepPass;

checkDetails(end+1,1) = sprintf( ...
    '%d / %d', ...
    numel(unique(PrimaryDatabase.SweepID)), ...
    CFG.ExpectedPrimarySweeps);


IntegrityChecks = table( ...
    checkNames, ...
    checkPass, ...
    checkDetails, ...
    'VariableNames',{ ...
    'Check', ...
    'Pass', ...
    'Details'});


for i = 1:height(IntegrityChecks)

    fprintf('%-38s : %-4s | %s\n', ...
        IntegrityChecks.Check(i), ...
        passFail(IntegrityChecks.Pass(i)), ...
        IntegrityChecks.Details(i));

end


DatabaseIntegrityPass = ...
    all(IntegrityChecks.Pass);


fprintf('\n');

if DatabaseIntegrityPass

    fprintf('DATABASE INTEGRITY : PASS\n');

else

    fprintf('DATABASE INTEGRITY : FAIL\n');

end

fprintf('\n');


%% ========================================================================
% [16] DATABASE STATISTICS
% =========================================================================

fprintf('[16] DATABASE STATISTICS\n');
fprintf('──────────────────────────────────────────────────────────────\n');


fprintf('PRIMARY MODEL DATABASE\n\n');

fprintf('Samples       : %d\n', ...
    height(PrimaryDatabase));

fprintf('Sweeps        : %d\n', ...
    numel(unique(PrimaryDatabase.SweepID)));

fprintf('Conditions    : %d\n', ...
    height(ConditionManifest));

fprintf('Runs          : ');

fprintf('%d ',unique(PrimaryDatabase.RunNumber));

fprintf('\n');


fprintf('\nMeasured ranges:\n');

fprintf('SA       : %8.3f → %8.3f deg\n', ...
    min(PrimaryDatabase.SA_deg), ...
    max(PrimaryDatabase.SA_deg));

fprintf('FY       : %8.1f → %8.1f N\n', ...
    min(PrimaryDatabase.FY_N), ...
    max(PrimaryDatabase.FY_N));

fprintf('FZ       : %8.1f → %8.1f N\n', ...
    min(PrimaryDatabase.FZ_N), ...
    max(PrimaryDatabase.FZ_N));

fprintf('IA       : %8.3f → %8.3f deg\n', ...
    min(PrimaryDatabase.IA_deg), ...
    max(PrimaryDatabase.IA_deg));

fprintf('Pressure : %8.2f → %8.2f kPa\n', ...
    min(PrimaryDatabase.P_kPa), ...
    max(PrimaryDatabase.P_kPa));

fprintf('Speed    : %8.2f → %8.2f kph\n', ...
    min(PrimaryDatabase.V_kph), ...
    max(PrimaryDatabase.V_kph));

fprintf('\n');


%% ========================================================================
% [17] CREATE OUTPUT DIRECTORY
% =========================================================================

fprintf('[17] OUTPUT DIRECTORY\n');
fprintf('──────────────────────────────────────────────────────────────\n');


outputRoot = fullfile(repoRoot,'outputs',CFG.OutputRoot);


outputFolder = fullfile( ...
    outputRoot, ...
    '04_LATERAL_MODEL_DATABASE');


tableFolder = fullfile( ...
    outputFolder, ...
    CFG.TableFolder);


if ~exist(outputRoot,'dir')
    mkdir(outputRoot);
end


if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end


if ~exist(tableFolder,'dir')
    mkdir(tableFolder);
end


fprintf('%s\n\n',outputFolder);


%% ========================================================================
% [18] SAVE CSV DATABASES
% =========================================================================

fprintf('[18] SAVING DATABASE TABLES\n');
fprintf('──────────────────────────────────────────────────────────────\n');


primaryPath = fullfile( ...
    tableFolder, ...
    'CMM_PRIMARY_LATERAL_MODEL_DATABASE_v4_0.csv');


validationPath = fullfile( ...
    tableFolder, ...
    'CMM_SPEED_VALIDATION_DATABASE_v4_0.csv');


sweepManifestPath = fullfile( ...
    tableFolder, ...
    'CMM_SWEEP_MANIFEST_v4_0.csv');


conditionManifestPath = fullfile( ...
    tableFolder, ...
    'CMM_CONDITION_MANIFEST_v4_0.csv');


validationConditionPath = fullfile( ...
    tableFolder, ...
    'CMM_VALIDATION_CONDITION_MANIFEST_v4_0.csv');


coveragePath = fullfile( ...
    tableFolder, ...
    'CMM_OPERATING_CONDITION_COVERAGE_v4_0.csv');


integrityPath = fullfile( ...
    tableFolder, ...
    'CMM_DATABASE_INTEGRITY_CHECKS_v4_0.csv');


writetable(PrimaryDatabase,primaryPath);

writetable(ValidationDatabase,validationPath);

writetable(SweepManifest,sweepManifestPath);

writetable(ConditionManifest,conditionManifestPath);

if ~isempty(ValidationConditionManifest)

    writetable( ...
        ValidationConditionManifest, ...
        validationConditionPath);

end

writetable(CoverageMatrix,coveragePath);

writetable(IntegrityChecks,integrityPath);


fprintf('Primary database      : SAVED\n');
fprintf('Validation database   : SAVED\n');
fprintf('Sweep manifest        : SAVED\n');
fprintf('Condition manifest    : SAVED\n');
fprintf('Coverage matrix       : SAVED\n');
fprintf('Integrity checks      : SAVED\n\n');


%% ========================================================================
% [19] BUILD STAGE-4 DATABASE CONTRACT
% =========================================================================

fprintf('[19] BUILDING DATABASE CONTRACT\n');
fprintf('──────────────────────────────────────────────────────────────\n');


LateralModelDatabaseContract = struct();


LateralModelDatabaseContract.Version = ...
    CFG.Version;


LateralModelDatabaseContract.Pipeline = ...
    CFG.Pipeline;


LateralModelDatabaseContract.ModelName = ...
    CFG.ModelName;


LateralModelDatabaseContract.TireModel = ...
    CFG.TireModel;


LateralModelDatabaseContract.Compound = ...
    CFG.Compound;


LateralModelDatabaseContract.RimWidth_in = ...
    CFG.RimWidth_in;


LateralModelDatabaseContract.Configuration = ...
    CFG;


LateralModelDatabaseContract.SourceStage3Contract = ...
    contractPath;


LateralModelDatabaseContract.Primary = ...
    PrimaryDatabase;


LateralModelDatabaseContract.ValidationSpeed = ...
    ValidationDatabase;


LateralModelDatabaseContract.SweepManifest = ...
    SweepManifest;


LateralModelDatabaseContract.PrimarySweepManifest = ...
    PrimarySweepManifest;


LateralModelDatabaseContract.ValidationSweepManifest = ...
    ValidationSweepManifest;


LateralModelDatabaseContract.ConditionManifest = ...
    ConditionManifest;


LateralModelDatabaseContract.ValidationConditionManifest = ...
    ValidationConditionManifest;


LateralModelDatabaseContract.CoverageMatrix = ...
    CoverageMatrix;


LateralModelDatabaseContract.PrimaryCleaningReport = ...
    PrimaryCleaningReport;


LateralModelDatabaseContract.ValidationCleaningReport = ...
    ValidationCleaningReport;


LateralModelDatabaseContract.IntegrityChecks = ...
    IntegrityChecks;


LateralModelDatabaseContract.DatabaseIntegrityPass = ...
    DatabaseIntegrityPass;


LateralModelDatabaseContract.PrimarySampleCount = ...
    height(PrimaryDatabase);


LateralModelDatabaseContract.ValidationSampleCount = ...
    height(ValidationDatabase);


LateralModelDatabaseContract.PrimarySweepCount = ...
    height(PrimarySweepManifest);


LateralModelDatabaseContract.ValidationSweepCount = ...
    height(ValidationSweepManifest);


LateralModelDatabaseContract.ConditionCount = ...
    height(ConditionManifest);


fprintf('Contract structure : BUILT\n\n');


%% ========================================================================
% [20] SAVE MAT CONTRACT
% =========================================================================

fprintf('[20] SAVING MAT CONTRACT\n');
fprintf('──────────────────────────────────────────────────────────────\n');


contractOutputPath = fullfile( ...
    outputFolder, ...
    'CMM_LATERAL_MODEL_DATABASE_CONTRACT_v4_0.mat');


save( ...
    contractOutputPath, ...
    'LateralModelDatabaseContract', ...
    '-v7.3');


fprintf('MAT contract saved:\n%s\n\n', ...
    contractOutputPath);


%% ========================================================================
% [21] WRITE DATABASE REPORT
% =========================================================================

fprintf('[21] WRITING DATABASE REPORT\n');
fprintf('──────────────────────────────────────────────────────────────\n');


reportPath = fullfile( ...
    outputFolder, ...
    'CMM_LATERAL_MODEL_DATABASE_REPORT_v4_0.txt');


fid = fopen(reportPath,'w');


if fid ~= -1

    fprintf(fid, ...
        'CMM TTC LATERAL MODEL DATABASE BUILDER v4.0\n');

    fprintf(fid, ...
        '============================================================\n\n');


    fprintf(fid, ...
        'MODEL\n');

    fprintf(fid, ...
        '------------------------------------------------------------\n');

    fprintf(fid, ...
        'Model       : %s\n', ...
        CFG.ModelName);

    fprintf(fid, ...
        'Tire        : %s\n', ...
        CFG.TireModel);

    fprintf(fid, ...
        'Compound    : %s\n', ...
        CFG.Compound);

    fprintf(fid, ...
        'Rim width   : %.1f in\n\n', ...
        CFG.RimWidth_in);


    fprintf(fid, ...
        'PRIMARY MODEL DATABASE\n');

    fprintf(fid, ...
        '------------------------------------------------------------\n');

    fprintf(fid, ...
        'Samples     : %d\n', ...
        height(PrimaryDatabase));

    fprintf(fid, ...
        'Sweeps      : %d\n', ...
        height(PrimarySweepManifest));

    fprintf(fid, ...
        'Conditions  : %d\n\n', ...
        height(ConditionManifest));


    fprintf(fid, ...
        'VALIDATION DATABASE\n');

    fprintf(fid, ...
        '------------------------------------------------------------\n');

    fprintf(fid, ...
        'Samples     : %d\n', ...
        height(ValidationDatabase));

    fprintf(fid, ...
        'Sweeps      : %d\n\n', ...
        height(ValidationSweepManifest));


    fprintf(fid, ...
        'MEASURED PRIMARY RANGE\n');

    fprintf(fid, ...
        '------------------------------------------------------------\n');

    fprintf(fid, ...
        'SA : %.4f to %.4f deg\n', ...
        min(PrimaryDatabase.SA_deg), ...
        max(PrimaryDatabase.SA_deg));

    fprintf(fid, ...
        'FY : %.4f to %.4f N\n', ...
        min(PrimaryDatabase.FY_N), ...
        max(PrimaryDatabase.FY_N));

    fprintf(fid, ...
        'FZ : %.4f to %.4f N\n', ...
        min(PrimaryDatabase.FZ_N), ...
        max(PrimaryDatabase.FZ_N));

    fprintf(fid, ...
        'IA : %.4f to %.4f deg\n', ...
        min(PrimaryDatabase.IA_deg), ...
        max(PrimaryDatabase.IA_deg));

    fprintf(fid, ...
        'P  : %.4f to %.4f kPa\n', ...
        min(PrimaryDatabase.P_kPa), ...
        max(PrimaryDatabase.P_kPa));

    fprintf(fid, ...
        'V  : %.4f to %.4f kph\n\n', ...
        min(PrimaryDatabase.V_kph), ...
        max(PrimaryDatabase.V_kph));


    fprintf(fid, ...
        'DATABASE INTEGRITY\n');

    fprintf(fid, ...
        '------------------------------------------------------------\n');


    for i = 1:height(IntegrityChecks)

        fprintf(fid, ...
            '%-38s : %-4s | %s\n', ...
            IntegrityChecks.Check(i), ...
            passFail(IntegrityChecks.Pass(i)), ...
            IntegrityChecks.Details(i));

    end


    fprintf(fid,'\nFINAL STATUS: %s\n', ...
        passFail(DatabaseIntegrityPass));


    fclose(fid);

end


fprintf('Report saved:\n%s\n\n',reportPath);


%% ========================================================================
% [22] FINAL DATABASE CONTRACT SUMMARY
% =========================================================================

fprintf('[22] FINAL DATABASE CONTRACT SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');


fprintf('Primary samples             : %d\n', ...
    height(PrimaryDatabase));

fprintf('Primary sweeps              : %d\n', ...
    height(PrimarySweepManifest));

fprintf('Primary operating conditions: %d\n', ...
    height(ConditionManifest));

fprintf('Validation samples          : %d\n', ...
    height(ValidationDatabase));

fprintf('Validation sweeps           : %d\n', ...
    height(ValidationSweepManifest));

fprintf('Runs represented            : ');

fprintf('%d ',unique(PrimaryDatabase.RunNumber));

fprintf('\n');

fprintf('Database integrity          : %s\n', ...
    passFail(DatabaseIntegrityPass));

fprintf('\n');


fprintf('Canonical primary channels:\n\n');

disp(PrimaryDatabase.Properties.VariableNames');


fprintf('\n');


%% ========================================================================
% [23] FINAL STATUS
% =========================================================================

fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║            LATERAL MODEL DATABASE COMPLETE                 ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');


if DatabaseIntegrityPass

    fprintf('STAGE 4 STATUS:\n');
    fprintf('PASS — canonical lateral model database generated.\n\n');

    fprintf('DATABASE CONTRACT:\n');
    fprintf('%s\n\n',contractOutputPath);

    fprintf('NEXT PIPELINE STAGE:\n');
    fprintf('CMM TTC LATERAL TIRE CHARACTERIZER v5.0\n\n');

else

    fprintf('STAGE 4 STATUS:\n');
    fprintf('FAIL — database integrity checks failed.\n\n');

    fprintf('DO NOT PROCEED TO TIRE CHARACTERIZATION.\n\n');

end


%% ========================================================================
% LOCAL FUNCTION
% SANITIZE DATABASE
% =========================================================================

function [Clean,Report] = sanitizeDatabase(T,CFG,routingName)

    Report = struct();

    Report.Routing = routingName;

    Report.InputSamples = height(T);


    if isempty(T)

        Clean = T;

        Report.NonFiniteRemoved = 0;
        Report.RangeRemoved = 0;
        Report.OutputSamples = 0;
        Report.TotalRemoved = 0;

        return;

    end


    %% --------------------------------------------------------------------
    % Required finite channels
    % ---------------------------------------------------------------------

    finiteMask = ...
        isfinite(T.FullSweepID) & ...
        isfinite(T.Stage2RegionID) & ...
        isfinite(T.RunNumber) & ...
        isfinite(T.ET_s) & ...
        isfinite(T.SA_deg) & ...
        isfinite(T.FY_N) & ...
        isfinite(T.FZ_Load_N) & ...
        isfinite(T.IA_deg) & ...
        isfinite(T.P_kPa) & ...
        isfinite(T.V_kph);


    Report.NonFiniteRemoved = ...
        sum(~finiteMask);


    Tfinite = T(finiteMask,:);


    %% --------------------------------------------------------------------
    % Physical range checks
    % --------------------------------------------------------------------

    rangeMask = ...
        Tfinite.FZ_Load_N >= CFG.MinLoadedFZ_N & ...
        Tfinite.FZ_Load_N <= CFG.MaxLoadedFZ_N & ...
        abs(Tfinite.SA_deg) <= CFG.MaxAbsSA_deg & ...
        abs(Tfinite.IA_deg) <= CFG.MaxAbsIA_deg & ...
        Tfinite.P_kPa >= CFG.MinPressure_kPa & ...
        Tfinite.P_kPa <= CFG.MaxPressure_kPa & ...
        abs(Tfinite.V_kph) >= CFG.MinSpeed_kph & ...
        abs(Tfinite.V_kph) <= CFG.MaxSpeed_kph;


    Report.RangeRemoved = ...
        sum(~rangeMask);


    Clean = ...
        Tfinite(rangeMask,:);


    %% --------------------------------------------------------------------
    % Sort chronologically inside sweeps
    % --------------------------------------------------------------------

    Clean = sortrows( ...
        Clean, ...
        {'FullSweepID','ET_s'});


    Report.OutputSamples = ...
        height(Clean);


    Report.TotalRemoved = ...
        Report.InputSamples - ...
        Report.OutputSamples;


    Report.RemovalFraction = ...
        Report.TotalRemoved / ...
        max(Report.InputSamples,1);

end


%% ========================================================================
% LOCAL FUNCTION
% PRINT CLEANING REPORT
% =========================================================================

function printCleaningReport(R)

    fprintf('Input samples       : %d\n', ...
        R.InputSamples);

    fprintf('Non-finite removed  : %d\n', ...
        R.NonFiniteRemoved);

    fprintf('Range removed       : %d\n', ...
        R.RangeRemoved);

    fprintf('Total removed       : %d\n', ...
        R.TotalRemoved);

    fprintf('Output samples      : %d\n', ...
        R.OutputSamples);

end


%% ========================================================================
% LOCAL FUNCTION
% BUILD CANONICAL DATABASE
% =========================================================================

function DB = buildCanonicalDatabase(T,CFG,routingName)

    if isempty(T)

        DB = table( ...
            'Size',[0 21], ...
            'VariableTypes',{ ...
            'double','double','double','double','double', ...
            'double','double','double','double','double', ...
            'double','double','double','double','double', ...
            'double','double','double','double','string','string'}, ...
            'VariableNames',{ ...
            'SampleID', ...
            'SweepID', ...
            'OriginalFullSweepID', ...
            'Stage2RegionID', ...
            'RunNumber', ...
            'ET_s', ...
            'SA_deg', ...
            'FY_N', ...
            'FZ_N', ...
            'IA_deg', ...
            'P_kPa', ...
            'P_psi', ...
            'V_kph', ...
            'V_mph', ...
            'FZ_State_N', ...
            'Pressure_State_psi', ...
            'IA_State_deg', ...
            'Speed_State_mph', ...
            'ConditionID', ...
            'Routing', ...
            'ModelName'});

        return;

    end


    %% --------------------------------------------------------------------
    % Map Stage-3 FullSweepID → canonical sequential SweepID
    % --------------------------------------------------------------------

    originalIDs = unique( ...
        T.FullSweepID, ...
        'stable');


    canonicalSweepID = zeros(height(T),1);


    for i = 1:numel(originalIDs)

        canonicalSweepID( ...
            T.FullSweepID == originalIDs(i)) = i;

    end


    %% --------------------------------------------------------------------
    % Unit conversion
    % --------------------------------------------------------------------

    Ppsi = ...
        T.P_kPa / 6.894757293;

    Vmph = ...
        abs(T.V_kph) / 1.609344;


    %% --------------------------------------------------------------------
    % Operating-state labels
    % --------------------------------------------------------------------

    FZstate = ...
        round( ...
        T.FZ_Load_N / ...
        CFG.FZConditionBin_N) * ...
        CFG.FZConditionBin_N;


    Pstate = ...
        round( ...
        Ppsi / ...
        CFG.PressureConditionBin_psi) * ...
        CFG.PressureConditionBin_psi;


    IAstate = ...
        round( ...
        T.IA_deg / ...
        CFG.IAConditionBin_deg) * ...
        CFG.IAConditionBin_deg;


    Vstate = ...
        round( ...
        Vmph / ...
        CFG.SpeedConditionBin_mph) * ...
        CFG.SpeedConditionBin_mph;


    %% --------------------------------------------------------------------
    % Sample IDs
    % --------------------------------------------------------------------

    sampleID = ...
        (1:height(T))';


    %% --------------------------------------------------------------------
    % Routing metadata
    % --------------------------------------------------------------------

    routing = ...
        repmat( ...
        string(routingName), ...
        height(T),1);


    modelName = ...
        repmat( ...
        string(CFG.ModelName), ...
        height(T),1);


    %% --------------------------------------------------------------------
    % Condition IDs populated later
    % --------------------------------------------------------------------

    conditionID = ...
        zeros(height(T),1);


    %% --------------------------------------------------------------------
    % Canonical database
    % --------------------------------------------------------------------

    DB = table( ...
        sampleID, ...
        canonicalSweepID, ...
        T.FullSweepID, ...
        T.Stage2RegionID, ...
        T.RunNumber, ...
        T.ET_s, ...
        T.SA_deg, ...
        T.FY_N, ...
        T.FZ_Load_N, ...
        T.IA_deg, ...
        T.P_kPa, ...
        Ppsi, ...
        abs(T.V_kph), ...
        Vmph, ...
        FZstate, ...
        Pstate, ...
        IAstate, ...
        Vstate, ...
        conditionID, ...
        routing, ...
        modelName, ...
        'VariableNames',{ ...
        'SampleID', ...
        'SweepID', ...
        'OriginalFullSweepID', ...
        'Stage2RegionID', ...
        'RunNumber', ...
        'ET_s', ...
        'SA_deg', ...
        'FY_N', ...
        'FZ_N', ...
        'IA_deg', ...
        'P_kPa', ...
        'P_psi', ...
        'V_kph', ...
        'V_mph', ...
        'FZ_State_N', ...
        'Pressure_State_psi', ...
        'IA_State_deg', ...
        'Speed_State_mph', ...
        'ConditionID', ...
        'Routing', ...
        'ModelName'});

end


%% ========================================================================
% LOCAL FUNCTION
% ASSIGN OPERATING CONDITION IDS
% =========================================================================

function [DB,Manifest] = assignConditionIDs(DB,CFG)

    if isempty(DB)

        Manifest = table();

        return;

    end


    %% --------------------------------------------------------------------
    % Use sweep-level median state.
    %
    % This prevents small sample-level fluctuations from splitting a
    % single physical sweep into several condition IDs.
    % --------------------------------------------------------------------

    sweepIDs = unique(DB.SweepID);

    sweepConditions = table();


    for i = 1:numel(sweepIDs)

        sid = sweepIDs(i);

        mask = DB.SweepID == sid;

        FZmedian = ...
            median(DB.FZ_N(mask),'omitnan');

        Pmedian = ...
            median(DB.P_psi(mask),'omitnan');

        IAmedian = ...
            median(DB.IA_deg(mask),'omitnan');

        Vmedian = ...
            median(DB.V_mph(mask),'omitnan');


        FZstate = ...
            round( ...
            FZmedian / ...
            CFG.FZConditionBin_N) * ...
            CFG.FZConditionBin_N;


        Pstate = ...
            round( ...
            Pmedian / ...
            CFG.PressureConditionBin_psi) * ...
            CFG.PressureConditionBin_psi;


        IAstate = ...
            round( ...
            IAmedian / ...
            CFG.IAConditionBin_deg) * ...
            CFG.IAConditionBin_deg;


        Vstate = ...
            round( ...
            Vmedian / ...
            CFG.SpeedConditionBin_mph) * ...
            CFG.SpeedConditionBin_mph;


        row = table( ...
            sid, ...
            FZstate, ...
            Pstate, ...
            IAstate, ...
            Vstate, ...
            'VariableNames',{ ...
            'SweepID', ...
            'FZ_State_N', ...
            'Pressure_State_psi', ...
            'IA_State_deg', ...
            'Speed_State_mph'});


        sweepConditions = ...
            [sweepConditions;row]; %#ok<AGROW>

    end


    %% --------------------------------------------------------------------
    % Find unique condition combinations
    % --------------------------------------------------------------------

    conditionKeys = unique( ...
        sweepConditions(:,{ ...
        'FZ_State_N', ...
        'Pressure_State_psi', ...
        'IA_State_deg', ...
        'Speed_State_mph'}), ...
        'rows');


    conditionKeys = sortrows( ...
        conditionKeys,{ ...
        'Pressure_State_psi', ...
        'IA_State_deg', ...
        'FZ_State_N', ...
        'Speed_State_mph'});


    conditionKeys.ConditionID = ...
        (1:height(conditionKeys))';


    conditionKeys = movevars( ...
        conditionKeys, ...
        'ConditionID', ...
        'Before',1);


    %% --------------------------------------------------------------------
    % Assign condition ID to each sweep/sample
    % --------------------------------------------------------------------

    for i = 1:height(conditionKeys)

        conditionMask = ...
            sweepConditions.FZ_State_N == ...
                conditionKeys.FZ_State_N(i) & ...
            sweepConditions.Pressure_State_psi == ...
                conditionKeys.Pressure_State_psi(i) & ...
            sweepConditions.IA_State_deg == ...
                conditionKeys.IA_State_deg(i) & ...
            sweepConditions.Speed_State_mph == ...
                conditionKeys.Speed_State_mph(i);


        sweeps = ...
            sweepConditions.SweepID(conditionMask);


        DB.ConditionID( ...
            ismember(DB.SweepID,sweeps)) = ...
            conditionKeys.ConditionID(i);

    end


    %% --------------------------------------------------------------------
    % Build manifest
    % --------------------------------------------------------------------

    Manifest = conditionKeys;


    Manifest.SweepCount = ...
        zeros(height(Manifest),1);


    Manifest.SampleCount = ...
        zeros(height(Manifest),1);


    Manifest.MeasuredFZ_Mean_N = ...
        zeros(height(Manifest),1);


    Manifest.MeasuredFZ_Median_N = ...
        zeros(height(Manifest),1);


    Manifest.MeasuredPressure_Mean_psi = ...
        zeros(height(Manifest),1);


    Manifest.MeasuredIA_Mean_deg = ...
        zeros(height(Manifest),1);


    Manifest.MeasuredSpeed_Mean_mph = ...
        zeros(height(Manifest),1);


    Manifest.SA_Min_deg = ...
        zeros(height(Manifest),1);


    Manifest.SA_Max_deg = ...
        zeros(height(Manifest),1);


    Manifest.FY_Min_N = ...
        zeros(height(Manifest),1);


    Manifest.FY_Max_N = ...
        zeros(height(Manifest),1);


    for i = 1:height(Manifest)

        mask = ...
            DB.ConditionID == ...
            Manifest.ConditionID(i);


        Manifest.SweepCount(i) = ...
            numel(unique(DB.SweepID(mask)));


        Manifest.SampleCount(i) = ...
            sum(mask);


        Manifest.MeasuredFZ_Mean_N(i) = ...
            mean(DB.FZ_N(mask),'omitnan');


        Manifest.MeasuredFZ_Median_N(i) = ...
            median(DB.FZ_N(mask),'omitnan');


        Manifest.MeasuredPressure_Mean_psi(i) = ...
            mean(DB.P_psi(mask),'omitnan');


        Manifest.MeasuredIA_Mean_deg(i) = ...
            mean(DB.IA_deg(mask),'omitnan');


        Manifest.MeasuredSpeed_Mean_mph(i) = ...
            mean(DB.V_mph(mask),'omitnan');


        Manifest.SA_Min_deg(i) = ...
            min(DB.SA_deg(mask));


        Manifest.SA_Max_deg(i) = ...
            max(DB.SA_deg(mask));


        Manifest.FY_Min_N(i) = ...
            min(DB.FY_N(mask));


        Manifest.FY_Max_N(i) = ...
            max(DB.FY_N(mask));

    end

end


%% ========================================================================
% LOCAL FUNCTION
% BUILD SWEEP MANIFEST
% =========================================================================

function Manifest = buildSweepManifest(DB,routingName)

    if isempty(DB)

        Manifest = table();

        return;

    end


    sweepIDs = unique(DB.SweepID);

    Manifest = table();


    for i = 1:numel(sweepIDs)

        sid = sweepIDs(i);

        mask = DB.SweepID == sid;


        row = table( ...
            sid, ...
            DB.OriginalFullSweepID(find(mask,1)), ...
            DB.Stage2RegionID(find(mask,1)), ...
            DB.RunNumber(find(mask,1)), ...
            DB.ConditionID(find(mask,1)), ...
            sum(mask), ...
            min(DB.ET_s(mask)), ...
            max(DB.ET_s(mask)), ...
            min(DB.SA_deg(mask)), ...
            max(DB.SA_deg(mask)), ...
            mean(DB.FZ_N(mask),'omitnan'), ...
            median(DB.FZ_N(mask),'omitnan'), ...
            std(DB.FZ_N(mask),'omitnan'), ...
            mean(DB.P_psi(mask),'omitnan'), ...
            mean(DB.IA_deg(mask),'omitnan'), ...
            mean(DB.V_mph(mask),'omitnan'), ...
            string(routingName), ...
            'VariableNames',{ ...
            'SweepID', ...
            'OriginalFullSweepID', ...
            'Stage2RegionID', ...
            'RunNumber', ...
            'ConditionID', ...
            'SampleCount', ...
            'ET_Start_s', ...
            'ET_End_s', ...
            'SA_Min_deg', ...
            'SA_Max_deg', ...
            'FZ_Mean_N', ...
            'FZ_Median_N', ...
            'FZ_Std_N', ...
            'Pressure_Mean_psi', ...
            'IA_Mean_deg', ...
            'Speed_Mean_mph', ...
            'Routing'});


        Manifest = ...
            [Manifest;row]; %#ok<AGROW>

    end

end


%% ========================================================================
% LOCAL FUNCTION
% BUILD COVERAGE MATRIX
% =========================================================================

function Coverage = buildCoverageMatrix(SweepManifest)

    if isempty(SweepManifest)

        Coverage = table();

        return;

    end


    P = round(SweepManifest.Pressure_Mean_psi);

    IA = round(SweepManifest.IA_Mean_deg);

    FZ = round(SweepManifest.FZ_Median_N/50)*50;

    V = round(SweepManifest.Speed_Mean_mph);


    keys = table( ...
        P, ...
        FZ, ...
        IA, ...
        V, ...
        'VariableNames',{ ...
        'Pressure_psi', ...
        'FZ_State_N', ...
        'IA_deg', ...
        'Speed_mph'});


    uniqueKeys = unique(keys,'rows');


    SweepCount = zeros( ...
        height(uniqueKeys),1);


    SampleCount = zeros( ...
        height(uniqueKeys),1);


    for i = 1:height(uniqueKeys)

        mask = ...
            P == uniqueKeys.Pressure_psi(i) & ...
            FZ == uniqueKeys.FZ_State_N(i) & ...
            IA == uniqueKeys.IA_deg(i) & ...
            V == uniqueKeys.Speed_mph(i);


        SweepCount(i) = ...
            sum(mask);


        SampleCount(i) = ...
            sum(SweepManifest.SampleCount(mask));

    end


    Coverage = [ ...
        uniqueKeys, ...
        table(SweepCount,SampleCount)];


    Coverage = sortrows( ...
        Coverage,{ ...
        'Pressure_psi', ...
        'IA_deg', ...
        'FZ_State_N', ...
        'Speed_mph'});

end


%% ========================================================================
% LOCAL FUNCTION
% PASS / FAIL
% =========================================================================

function output = passFail(value)

    if value

        output = "PASS";

    else

        output = "FAIL";

    end

end