function PATHS = CMM_paths()
% ================================================================
% CMM PATH CONFIGURATION
% Pipeline v03
%
% PURPOSE
%   Centralize filesystem paths for the complete CMM v03 pipeline.
%
% DESIGN PRINCIPLE
%   pipelinev03 is a clean rebuild.
%
%   v02 is treated as a BASELINE / REFERENCE only.
%   v03 does NOT depend on the old v02 outputs directory.
%
% ================================================================


%% ================================================================
% REPOSITORY / PIPELINE ROOT
% ================================================================

thisFile = mfilename('fullpath');

configDir  = fileparts(thisFile);
pipelineDir = fileparts(configDir);
repoRoot    = fileparts(pipelineDir);

PATHS.repoRoot    = repoRoot;
PATHS.pipelineV03 = pipelineDir;
PATHS.pipelineV02 = fullfile(repoRoot, 'pipelinev02');


%% ================================================================
% PRIVATE DATA ROOT
% ================================================================

% Raw TTC data and processed databases are NOT part of the Git
% source tree.
%
% Recommended structure:
%
%   CMM/
%       data/
%           raw/
%           processed/
%           canonical/
%
% The entire data/ directory should be Git-ignored.

PATHS.dataRoot = fullfile(repoRoot, 'data');

PATHS.rawData = fullfile( ...
    PATHS.dataRoot, 'raw');

PATHS.processedData = fullfile( ...
    PATHS.dataRoot, 'processed');

PATHS.canonicalData = fullfile( ...
    PATHS.dataRoot, 'canonical');


%% ================================================================
% V02 REFERENCE DATA / ARTIFACTS
% ================================================================

% IMPORTANT:
%
% v02 is NOT a dependency of the v03 output pipeline.
%
% We only retain access to selected v02 artifacts for:
%
%   1. baseline comparison
%   2. validation
%   3. regression checking
%   4. migration/reference
%
% v03 must NEVER overwrite or modify v02 files.


%% ------------------------------------------------
% MAIN V02 REFERENCE
% ------------------------------------------------

PATHS.v02Root = PATHS.pipelineV02;


%% ------------------------------------------------
% V02 MODEL REFERENCE
% ------------------------------------------------

% Existing locked global lateral model.
%
% This is a REFERENCE MODEL ONLY.
%
% v03 will compare against it but will not modify it.

PATHS.v02LockedModel = fullfile( ...
    PATHS.v02Root, ...
    'MF validator&audits', ...
    'CMM_GLOBAL_MF_LATERAL_v2_0.mat');


%% ------------------------------------------------
% V02 DATABASE REFERENCE
% ------------------------------------------------

% The following represent the important database architecture
% inherited from v02.
%
% Exact filenames can be updated once the v03 database loader is
% connected to the current canonical data.

PATHS.v02DatabaseReference = fullfile( ...
    PATHS.canonicalData, ...
    'CMM_PRIMARY_LATERAL_MODEL_DATABASE_v4_0.csv');

PATHS.v02ConditionManifest = fullfile( ...
    PATHS.canonicalData, ...
    'CMM_CONDITION_MANIFEST_v4_0.csv');

PATHS.v02SweepManifest = fullfile( ...
    PATHS.canonicalData, ...
    'CMM_SWEEP_MANIFEST_v4_0.csv');


%% ================================================================
% V02 COMPONENTS WE ARE RETAINING
% ================================================================

% These are NOT copied blindly into v03.
%
% They define the parts of v02 whose methodology/data contracts
% v03 is deliberately preserving.

PATHS.V02_REFERENCE_COMPONENTS = { ...
    'Run mapping and tire/rim identity', ...
    '7-inch model routing: Runs 2 and 4', ...
    '8-inch separation: Runs 5, 6 and 7', ...
    'Operating-condition definition', ...
    'Sweep detection and sweep-level QC', ...
    'Canonical sweep manifest', ...
    'Canonical condition manifest', ...
    'Canonical lateral model database', ...
    'Run 2 development / Run 4 holdout strategy', ...
    'Pre-MF physical characterization', ...
    'Existing CMM Magic Formula formulation', ...
    'Existing parameter contract for baseline comparison', ...
    'Existing model-lock / validation philosophy' ...
};


%% ================================================================
% V03 OUTPUT ROOT
% ================================================================

% IMPORTANT:
%
% This is COMPLETELY SEPARATE from the old v02 outputs.
%
% Do NOT use:
%
%   outputs/
%   outputs_v02/
%   pipelinev02 outputs
%
% for v03 generated artifacts.

PATHS.outputRoot = fullfile( ...
    repoRoot, 'outputs_v03');


%% ================================================================
% V03 OUTPUT SUBDIRECTORIES
% ================================================================

PATHS.outputData = fullfile( ...
    PATHS.outputRoot, '01_data');

PATHS.outputCharacterization = fullfile( ...
    PATHS.outputRoot, '02_characterization');

PATHS.outputLocalFitting = fullfile( ...
    PATHS.outputRoot, '03_local_fitting');

PATHS.outputParameterSurfaces = fullfile( ...
    PATHS.outputRoot, '04_parameter_surfaces');

PATHS.outputGlobalModel = fullfile( ...
    PATHS.outputRoot, '05_global_model');

PATHS.outputValidation = fullfile( ...
    PATHS.outputRoot, '06_validation');

PATHS.outputTireModel = fullfile( ...
    PATHS.outputRoot, '07_tire_model');

PATHS.outputVehicleInterface = fullfile( ...
    PATHS.outputRoot, '08_vehicle_interface');

PATHS.outputExport = fullfile( ...
    PATHS.outputRoot, '09_export');


%% ================================================================
% V03 MODEL IDENTITY
% ================================================================

PATHS.pipelineVersion = 'v03.0.0';

PATHS.modelName = 'CMM_7IN_LATERAL_V03';


%% ================================================================
% MODEL RUN ROUTING
% ================================================================

% Current CMM 7-inch model dataset.

PATHS.modelRuns = [2 4];

% Development data.
PATHS.developmentRuns = 2;

% Independent holdout.
PATHS.holdoutRuns = 4;

% Explicitly excluded from the current 7-inch model.
PATHS.excludedRuns = [5 6 7];


%% ================================================================
% REFERENCE RIM
% ================================================================

PATHS.modelRimDiameter_in = 7;



%% ================================================================
% BASIC PATH VALIDATION
% ================================================================

if ~isfolder(PATHS.repoRoot)

    error( ...
        'CMM_paths:InvalidRepoRoot', ...
        'Repository root does not exist:\n%s', ...
        PATHS.repoRoot);

end


if ~isfolder(PATHS.pipelineV03)

    error( ...
        'CMM_paths:InvalidPipeline', ...
        'pipelinev03 does not exist:\n%s', ...
        PATHS.pipelineV03);

end


%% ================================================================
% DISPLAY CONFIGURATION
% ================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' CMM PIPELINE v03 PATH CONFIGURATION\n');
fprintf('============================================================\n');

fprintf('\nREPOSITORY\n');
fprintf('  Root       : %s\n', PATHS.repoRoot);
fprintf('  Pipeline   : %s\n', PATHS.pipelineV03);
fprintf('  Baseline   : %s\n', PATHS.pipelineV02);

fprintf('\nDATA\n');
fprintf('  Root       : %s\n', PATHS.dataRoot);
fprintf('  Raw        : %s\n', PATHS.rawData);
fprintf('  Processed  : %s\n', PATHS.processedData);
fprintf('  Canonical  : %s\n', PATHS.canonicalData);

fprintf('\nOUTPUTS\n');
fprintf('  v03 Root   : %s\n', PATHS.outputRoot);

fprintf('\nMODEL ROUTING\n');
fprintf('  Model runs : [%s]\n', ...
    num2str(PATHS.modelRuns));

fprintf('  Development: Run %d\n', ...
    PATHS.developmentRuns);

fprintf('  Holdout    : Run %d\n', ...
    PATHS.holdoutRuns);

fprintf('  Excluded   : [%s]\n', ...
    num2str(PATHS.excludedRuns));

fprintf('\nMODEL\n');
fprintf('  Name       : %s\n', PATHS.modelName);
fprintf('  Rim        : %.0f inch\n', ...
    PATHS.modelRimDiameter_in);

fprintf('\n');
fprintf('V02 is REFERENCE ONLY.\n');
fprintf('V03 outputs are COMPLETELY SEPARATE.\n');

fprintf('============================================================\n');
fprintf('\n');

end