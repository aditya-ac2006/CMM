%% ========================================================================
%  CMM TTC FILE + RUN MAPPER v1.1
%
%  Dataset Discovery → Run Identity → Tire Configuration → Model Eligibility
%
%  PURPOSE
%  ------------------------------------------------------------------------
%  Creates the authoritative run-level manifest for the CMM TTC pipeline.
%
%  This module DOES NOT process tire measurements.
%
%  It answers:
%
%      What file is this?
%      What TTC run is it?
%      What test family does it belong to?
%      What rim width was used?
%      Is it eligible for the CURRENT tire model?
%
%  CURRENT CMM MODEL
%  ------------------------------------------------------------------------
%  Tire      : Hoosier 43075 16x7.5-10
%  Compound  : R25B
%  Rim       : 7 inch
%  Analysis  : Steady-state lateral / cornering
%
%  Current eligible runs:
%
%      Run 2
%      Run 4
%
%  IMPORTANT
%  ------------------------------------------------------------------------
%  8-inch data is NOT rejected as bad data.
%
%  It is preserved in the manifest but excluded from the CURRENT
%  7-inch tire-model branch.
%
%  Version : 1.1.0
%  ========================================================================

clear;
clc;

%% ========================================================================
% MODULE INFORMATION
% ========================================================================

MODULE_NAME    = "CMM TTC File + Run Mapper";
MODULE_VERSION = "1.1.0";

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║              CMM TTC FILE + RUN MAPPER v1.1                ║\n');
fprintf('║       Run Identity → Configuration → Model Routing         ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');


%% ========================================================================
% CURRENT MODEL CONFIGURATION
% ========================================================================

CURRENT_MODEL_NAME = ...
    "CMM_7IN_LATERAL_MODEL";

CURRENT_TIRE_MODEL = ...
    "43075 16x7.5-10";

CURRENT_COMPOUND = ...
    "R25B";

CURRENT_RIM_WIDTH_IN = ...
    7.0;

CURRENT_TEST_FAMILY = ...
    "CORNERING";


%% ========================================================================
% AUTHORITATIVE CMM RUN DEFINITIONS
%
% These are dataset metadata.
%
% Do NOT infer these using odd/even run numbering.
% ========================================================================

RUN_NUMBER = ...
    [1; 2; 4; 5; 6; 7];

OFFICIAL_TYPE = ...
    ["TRANSIENT";
     "CORNERING_PART_1";
     "CORNERING_PART_2";
     "TRANSIENT";
     "CORNERING_PART_1";
     "CORNERING_PART_2"];

TEST_FAMILY = ...
    ["TRANSIENT";
     "CORNERING";
     "CORNERING";
     "TRANSIENT";
     "CORNERING";
     "CORNERING"];

RIM_WIDTH_IN = ...
    [7;
     7;
     7;
     8;
     8;
     8];

TIRE_MODEL = repmat( ...
    CURRENT_TIRE_MODEL,...
    numel(RUN_NUMBER),1);

COMPOUND = repmat( ...
    CURRENT_COMPOUND,...
    numel(RUN_NUMBER),1);


RunDefinition = table( ...
    RUN_NUMBER,...
    OFFICIAL_TYPE,...
    TEST_FAMILY,...
    RIM_WIDTH_IN,...
    TIRE_MODEL,...
    COMPOUND,...
    'VariableNames',{ ...
    'RunNumber',...
    'OfficialType',...
    'TestFamily',...
    'RimWidth_in',...
    'TireModel',...
    'Compound'});


%% ========================================================================
% [1] SELECT TTC DATA FOLDER
% ========================================================================

fprintf('[1] SELECT TTC DATA FOLDER\n');
fprintf('──────────────────────────────────────────────────────────────\n');

folder = uigetdir( ...
    pwd,...
    'Select folder containing B1965 TTC MAT files');

if isequal(folder,0)
    error('No TTC data folder selected.');
end

fprintf('Selected folder:\n%s\n\n',folder);


%% ========================================================================
% [2] DISCOVER TTC FILES
% ========================================================================

fprintf('[2] DISCOVERING TTC FILES\n');
fprintf('──────────────────────────────────────────────────────────────\n');

files = dir(fullfile(folder,'B1965run*.mat'));

if isempty(files)
    error('No B1965run*.mat files found.');
end


% ------------------------------------------------------------
% Extract run number from filename
% ------------------------------------------------------------

detectedRuns = nan(numel(files),1);

for i = 1:numel(files)

    token = regexp( ...
        files(i).name,...
        'run(\d+)',...
        'tokens',...
        'once');

    if ~isempty(token)

        detectedRuns(i) = ...
            str2double(token{1});

    end

end


% Remove files whose run number could not be determined

validFile = isfinite(detectedRuns);

files = files(validFile);
detectedRuns = detectedRuns(validFile);


% Sort numerically

[detectedRuns,order] = sort(detectedRuns);

files = files(order);


fprintf('Files discovered : %d\n\n',numel(files));


%% ========================================================================
% [3] LOAD AUTHORITATIVE RUN DEFINITIONS
% ========================================================================

fprintf('[3] LOADING CMM RUN DEFINITIONS\n');
fprintf('──────────────────────────────────────────────────────────────\n');

fprintf('Known run definitions : %d\n',height(RunDefinition));

fprintf('Current model         : %s\n',CURRENT_MODEL_NAME);
fprintf('Current rim width     : %.1f in\n',CURRENT_RIM_WIDTH_IN);
fprintf('Required test family  : %s\n\n',CURRENT_TEST_FAMILY);


%% ========================================================================
% STORAGE
% ========================================================================

Manifest = table();


%% ========================================================================
% [4] SCAN FILES
% ========================================================================

fprintf('[4] SCANNING TTC FILES\n');
fprintf('──────────────────────────────────────────────────────────────\n\n');


for i = 1:numel(files)

    fileName = string(files(i).name);

    filePath = fullfile( ...
        folder,...
        files(i).name);

    runNumber = detectedRuns(i);


    %% --------------------------------------------------------------------
    % Find authoritative run definition
    % ---------------------------------------------------------------------

    idxDef = find( ...
        RunDefinition.RunNumber == runNumber,...
        1);


    if isempty(idxDef)

        officialType = "UNKNOWN";
        testFamily   = "UNKNOWN";
        rimWidth     = NaN;
        tireModel    = "UNKNOWN";
        compound     = "UNKNOWN";

        definitionStatus = "UNKNOWN_RUN";

    else

        officialType = ...
            RunDefinition.OfficialType(idxDef);

        testFamily = ...
            RunDefinition.TestFamily(idxDef);

        rimWidth = ...
            RunDefinition.RimWidth_in(idxDef);

        tireModel = ...
            RunDefinition.TireModel(idxDef);

        compound = ...
            RunDefinition.Compound(idxDef);

        definitionStatus = "KNOWN";

    end


    %% --------------------------------------------------------------------
    % Load file
    % ---------------------------------------------------------------------

    try

        D = load(filePath);

        loadStatus = "PASS";

    catch ME

        warning( ...
            'Unable to load %s: %s',...
            fileName,...
            ME.message);

        loadStatus = "FAIL";

        D = struct();

    end


    %% --------------------------------------------------------------------
    % Basic channel validation
    % ---------------------------------------------------------------------

    requiredChannels = { ...
        'ET',...
        'SA',...
        'FY',...
        'FZ',...
        'IA',...
        'P',...
        'V'};


    missingChannels = strings(0,1);


    for c = 1:numel(requiredChannels)

        channel = requiredChannels{c};

        if ~isfield(D,channel)

            missingChannels(end+1,1) = ...
                string(channel); %#ok<SAGROW>

        end

    end


    if isempty(missingChannels)

        channelStatus = "PASS";
        missingChannelString = "NONE";

    else

        channelStatus = "FAIL";

        missingChannelString = ...
            strjoin(missingChannels,", ");

    end


    %% --------------------------------------------------------------------
    % Sample count
    % ---------------------------------------------------------------------

    sampleCount = NaN;


    if isfield(D,'ET')

        sampleCount = ...
            numel(D.ET);

    elseif isfield(D,'SA')

        sampleCount = ...
            numel(D.SA);

    end


    %% --------------------------------------------------------------------
    % Sample rate and duration
    % ---------------------------------------------------------------------

    sampleRate = NaN;
    duration = NaN;


    if isfield(D,'ET')

        ET = double(D.ET(:));

        ETfinite = ET(isfinite(ET));


        if numel(ETfinite) >= 2

            dt = diff(ETfinite);

            dt = dt( ...
                isfinite(dt) & ...
                dt > 0);


            if ~isempty(dt)

                sampleRate = ...
                    1 / median(dt);

            end


            duration = ...
                max(ETfinite) - min(ETfinite);

        end

    end


    %% --------------------------------------------------------------------
    % Basic signal ranges
    % ---------------------------------------------------------------------

    [SAmin,SAmax] = ...
        getRange(D,'SA');

    [FZmin,FZmax] = ...
        getRange(D,'FZ');

    [FYmin,FYmax] = ...
        getRange(D,'FY');

    [Pmin,Pmax] = ...
        getRange(D,'P');

    [IAmin,IAmax] = ...
        getRange(D,'IA');

    [Vmin,Vmax] = ...
        getRange(D,'V');


    %% --------------------------------------------------------------------
    % Determine current model eligibility
    % ---------------------------------------------------------------------

    rimMatch = ...
        isfinite(rimWidth) && ...
        abs(rimWidth - CURRENT_RIM_WIDTH_IN) < 1e-9;


    familyMatch = ...
        testFamily == CURRENT_TEST_FAMILY;


    knownDefinition = ...
        definitionStatus == "KNOWN";


    fileValid = ...
        loadStatus == "PASS" && ...
        channelStatus == "PASS";


    currentModelEligible = ...
        knownDefinition && ...
        rimMatch && ...
        familyMatch && ...
        fileValid;


    %% --------------------------------------------------------------------
    % Routing decision
    % ---------------------------------------------------------------------

    if definitionStatus ~= "KNOWN"

        routingStatus = ...
            "EXCLUDE_UNKNOWN_RUN";


    elseif loadStatus ~= "PASS"

        routingStatus = ...
            "EXCLUDE_LOAD_FAILURE";


    elseif channelStatus ~= "PASS"

        routingStatus = ...
            "EXCLUDE_MISSING_CHANNEL";


    elseif ~rimMatch

        routingStatus = ...
            "EXCLUDE_RIM_WIDTH";


    elseif ~familyMatch

        routingStatus = ...
            "EXCLUDE_TEST_FAMILY";


    else

        routingStatus = ...
            "INCLUDE_CURRENT_MODEL";

    end


    %% --------------------------------------------------------------------
    % Future analysis branch
    % ---------------------------------------------------------------------

    if testFamily == "TRANSIENT"

        futureBranch = ...
            "TRANSIENT_ANALYSIS";


    elseif testFamily == "CORNERING" && ...
            rimWidth == 8

        futureBranch = ...
            "8IN_LATERAL_MODEL";


    elseif currentModelEligible

        futureBranch = ...
            "CURRENT_7IN_LATERAL_MODEL";


    else

        futureBranch = ...
            "UNASSIGNED";

    end


    %% --------------------------------------------------------------------
    % Channel inventory
    % ---------------------------------------------------------------------

    if ~isempty(fieldnames(D))

        channelNames = ...
            string(fieldnames(D));

        channelsPresent = ...
            strjoin(channelNames,", ");

    else

        channelsPresent = ...
            "NONE";

    end


    %% --------------------------------------------------------------------
    % Add manifest row
    % ---------------------------------------------------------------------

    row = table( ...
        runNumber,...
        fileName,...
        officialType,...
        testFamily,...
        rimWidth,...
        tireModel,...
        compound,...
        definitionStatus,...
        loadStatus,...
        channelStatus,...
        missingChannelString,...
        sampleCount,...
        sampleRate,...
        duration,...
        SAmin,...
        SAmax,...
        FZmin,...
        FZmax,...
        FYmin,...
        FYmax,...
        Pmin,...
        Pmax,...
        IAmin,...
        IAmax,...
        Vmin,...
        Vmax,...
        rimMatch,...
        familyMatch,...
        currentModelEligible,...
        routingStatus,...
        futureBranch,...
        channelsPresent,...
        'VariableNames',{ ...
        'RunNumber',...
        'FileName',...
        'OfficialType',...
        'TestFamily',...
        'RimWidth_in',...
        'TireModel',...
        'Compound',...
        'DefinitionStatus',...
        'LoadStatus',...
        'ChannelStatus',...
        'MissingChannels',...
        'SampleCount',...
        'SampleRate_Hz',...
        'Duration_s',...
        'SA_Min_deg',...
        'SA_Max_deg',...
        'FZ_Min_N',...
        'FZ_Max_N',...
        'FY_Min_N',...
        'FY_Max_N',...
        'P_Min_kPa',...
        'P_Max_kPa',...
        'IA_Min_deg',...
        'IA_Max_deg',...
        'V_Min_kph',...
        'V_Max_kph',...
        'RimMatch',...
        'FamilyMatch',...
        'CurrentModelEligible',...
        'RoutingStatus',...
        'FutureBranch',...
        'ChannelsPresent'});


    Manifest = [Manifest; row];


    %% --------------------------------------------------------------------
    % Console output
    % ---------------------------------------------------------------------

    fprintf( ...
        'Run %-3d | %-20s | %-17s | %4.1f in | %s\n',...
        runNumber,...
        fileName,...
        testFamily,...
        rimWidth,...
        routingStatus);

end


%% ========================================================================
% [5] VALIDATE MANIFEST
% ========================================================================

fprintf('\n[5] VALIDATING MASTER RUN MANIFEST\n');
fprintf('──────────────────────────────────────────────────────────────\n');


duplicateRuns = ...
    numel(unique(Manifest.RunNumber)) ~= ...
    height(Manifest);


if duplicateRuns

    fprintf('Duplicate run numbers       : FAIL\n');

else

    fprintf('Duplicate run numbers       : PASS\n');

end


allLoaded = ...
    all(Manifest.LoadStatus == "PASS");


if allLoaded

    fprintf('File loading               : PASS\n');

else

    fprintf('File loading               : WARNING\n');

end


allRequiredChannels = ...
    all(Manifest.ChannelStatus == "PASS");


if allRequiredChannels

    fprintf('Required channels          : PASS\n');

else

    fprintf('Required channels          : WARNING\n');

end


knownRuns = ...
    all(Manifest.DefinitionStatus == "KNOWN");


if knownRuns

    fprintf('Run definitions            : PASS\n');

else

    fprintf('Run definitions            : WARNING\n');

end


%% ========================================================================
% [6] MODEL ROUTING SUMMARY
% ========================================================================

fprintf('\n[6] CURRENT MODEL ROUTING\n');
fprintf('──────────────────────────────────────────────────────────────\n');


eligibleMask = ...
    Manifest.CurrentModelEligible;


fprintf( ...
    'Current model eligible : %d / %d runs\n\n',...
    sum(eligibleMask),...
    height(Manifest));


fprintf('INCLUDED:\n');

if any(eligibleMask)

    included = Manifest(eligibleMask,:);

    for i = 1:height(included)

        fprintf( ...
            '  ✓ Run %-3d | %-20s | %.1f in | %s\n',...
            included.RunNumber(i),...
            included.FileName(i),...
            included.RimWidth_in(i),...
            included.TestFamily(i));

    end

else

    fprintf('  NONE\n');

end


fprintf('\nEXCLUDED FROM CURRENT MODEL:\n');

excluded = Manifest(~eligibleMask,:);


if isempty(excluded)

    fprintf('  NONE\n');

else

    for i = 1:height(excluded)

        fprintf( ...
            '  - Run %-3d | %-20s | %-22s | Future: %s\n',...
            excluded.RunNumber(i),...
            excluded.FileName(i),...
            excluded.RoutingStatus(i),...
            excluded.FutureBranch(i));

    end

end


%% ========================================================================
% [7] CREATE MODEL INPUT MANIFEST
% ========================================================================

fprintf('\n[7] BUILDING CURRENT MODEL INPUT MANIFEST\n');
fprintf('──────────────────────────────────────────────────────────────\n');


CurrentModelManifest = ...
    Manifest(Manifest.CurrentModelEligible,:);


fprintf( ...
    'Files routed to current model : %d\n',...
    height(CurrentModelManifest));


for i = 1:height(CurrentModelManifest)

    fprintf( ...
        '  ✓ Run %d → %s\n',...
        CurrentModelManifest.RunNumber(i),...
        CurrentModelManifest.FileName(i));

end


%% ========================================================================
% [8] OUTPUT DIRECTORY
% ========================================================================

fprintf('\n[8] OUTPUT DIRECTORY\n');
fprintf('──────────────────────────────────────────────────────────────\n');


% Keep all generated artifacts inside the clean Git repository.
% The script lives in CMM_GIT\pipeline, so its repository root is one
% directory above the pipeline folder.
thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));
outputRoot = fullfile(repoRoot,'outputs','CMM_OUTPUT_V02');

outputFolder = fullfile( ...
    outputRoot,...
    '01_FILE_RUN_MAPPER');


if ~exist(outputFolder,'dir')

    mkdir(outputFolder);

end


fprintf('%s\n\n',outputFolder);


%% ========================================================================
% [9] SAVE CSV OUTPUTS
% ========================================================================

manifestCSV = fullfile( ...
    outputFolder,...
    'CMM_RUN_MANIFEST_v1_1.csv');


writetable( ...
    Manifest,...
    manifestCSV);


modelCSV = fullfile( ...
    outputFolder,...
    'CMM_CURRENT_MODEL_INPUT_MANIFEST_v1_1.csv');


writetable( ...
    CurrentModelManifest,...
    modelCSV);


fprintf('Master manifest saved:\n%s\n\n',manifestCSV);

fprintf('Current model manifest saved:\n%s\n\n',modelCSV);


%% ========================================================================
% [10] METADATA CONTRACT
% ========================================================================

Metadata = struct();


Metadata.moduleName = ...
    MODULE_NAME;


Metadata.moduleVersion = ...
    MODULE_VERSION;


Metadata.generated = ...
    datetime('now');


Metadata.sourceFolder = ...
    string(folder);


Metadata.currentModelName = ...
    CURRENT_MODEL_NAME;


Metadata.currentTireModel = ...
    CURRENT_TIRE_MODEL;


Metadata.currentCompound = ...
    CURRENT_COMPOUND;


Metadata.currentRimWidth_in = ...
    CURRENT_RIM_WIDTH_IN;


Metadata.currentTestFamily = ...
    CURRENT_TEST_FAMILY;


Metadata.totalRuns = ...
    height(Manifest);


Metadata.currentModelRuns = ...
    Manifest.RunNumber( ...
    Manifest.CurrentModelEligible);


Metadata.datasetContractVersion = ...
    "CMM_TTC_DATASET_CONTRACT_1.0";


%% ========================================================================
% [11] SAVE MAT CONTRACT
% ========================================================================

matPath = fullfile( ...
    outputFolder,...
    'CMM_RUN_MANIFEST_v1_1.mat');


save( ...
    matPath,...
    'Manifest',...
    'CurrentModelManifest',...
    'RunDefinition',...
    'Metadata');


fprintf('MAT contract saved:\n%s\n\n',matPath);


%% ========================================================================
% [12] WRITE TXT REPORT
% ========================================================================

reportPath = fullfile( ...
    outputFolder,...
    'CMM_FILE_RUN_MAPPER_REPORT_v1_1.txt');


fid = fopen(reportPath,'w');


if fid < 0

    warning('Could not create TXT report.');

else

    fprintf(fid,...
        'CMM TTC FILE + RUN MAPPER v1.1\n');

    fprintf(fid,...
        '============================================\n\n');


    fprintf(fid,...
        'Generated: %s\n\n',...
        char(datetime('now')));


    fprintf(fid,...
        'CURRENT MODEL\n');

    fprintf(fid,...
        '--------------------------------------------\n');

    fprintf(fid,...
        'Model       : %s\n',...
        CURRENT_MODEL_NAME);

    fprintf(fid,...
        'Tire        : %s\n',...
        CURRENT_TIRE_MODEL);

    fprintf(fid,...
        'Compound    : %s\n',...
        CURRENT_COMPOUND);

    fprintf(fid,...
        'Rim width   : %.1f in\n',...
        CURRENT_RIM_WIDTH_IN);

    fprintf(fid,...
        'Test family : %s\n\n',...
        CURRENT_TEST_FAMILY);


    fprintf(fid,...
        'RUN ROUTING\n');

    fprintf(fid,...
        '--------------------------------------------\n');


    for i = 1:height(Manifest)

        fprintf(fid,...
            '\nRUN %d\n',...
            Manifest.RunNumber(i));

        fprintf(fid,...
            'File            : %s\n',...
            Manifest.FileName(i));

        fprintf(fid,...
            'Official type   : %s\n',...
            Manifest.OfficialType(i));

        fprintf(fid,...
            'Test family     : %s\n',...
            Manifest.TestFamily(i));

        fprintf(fid,...
            'Rim width       : %.1f in\n',...
            Manifest.RimWidth_in(i));

        fprintf(fid,...
            'Tire            : %s\n',...
            Manifest.TireModel(i));

        fprintf(fid,...
            'Compound        : %s\n',...
            Manifest.Compound(i));

        fprintf(fid,...
            'Routing         : %s\n',...
            Manifest.RoutingStatus(i));

        fprintf(fid,...
            'Future branch   : %s\n',...
            Manifest.FutureBranch(i));

        fprintf(fid,...
            'Model eligible  : %d\n',...
            Manifest.CurrentModelEligible(i));

        fprintf(fid,...
            'Samples         : %.0f\n',...
            Manifest.SampleCount(i));

        fprintf(fid,...
            'Sample rate     : %.3f Hz\n',...
            Manifest.SampleRate_Hz(i));

        fprintf(fid,...
            'Duration        : %.3f s\n',...
            Manifest.Duration_s(i));

    end


    fprintf(fid,...
        '\n\nCURRENT MODEL INPUT SET\n');

    fprintf(fid,...
        '--------------------------------------------\n');


    for i = 1:height(CurrentModelManifest)

        fprintf(fid,...
            'Run %d : %s\n',...
            CurrentModelManifest.RunNumber(i),...
            CurrentModelManifest.FileName(i));

    end


    fclose(fid);

end


fprintf('TXT report saved:\n%s\n\n',reportPath);


%% ========================================================================
% [13] FINAL SUMMARY
% ========================================================================

fprintf('[13] FINAL SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');


fprintf( ...
    'Files processed            : %d\n',...
    height(Manifest));


fprintf( ...
    '7-inch runs                : %d\n',...
    sum(Manifest.RimWidth_in == 7));


fprintf( ...
    '8-inch runs                : %d\n',...
    sum(Manifest.RimWidth_in == 8));


fprintf( ...
    'Transient runs             : %d\n',...
    sum(Manifest.TestFamily == "TRANSIENT"));


fprintf( ...
    'Cornering runs             : %d\n',...
    sum(Manifest.TestFamily == "CORNERING"));


fprintf( ...
    'Current model input runs   : %d\n',...
    sum(Manifest.CurrentModelEligible));


fprintf('\n');

disp( ...
    Manifest(:,{ ...
    'RunNumber',...
    'OfficialType',...
    'TestFamily',...
    'RimWidth_in',...
    'CurrentModelEligible',...
    'RoutingStatus',...
    'FutureBranch'}));


%% ========================================================================
% COMPLETE
% ========================================================================

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║                FILE + RUN MAPPING COMPLETE                 ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');


fprintf('CURRENT MODEL PIPELINE INPUT:\n');

fprintf('7-inch CORNERING runs only.\n\n');


fprintf('NEXT PIPELINE STAGE:\n');
fprintf('CMM TTC OPERATING CONDITION SEGMENTER v2.0\n\n');


%% ========================================================================
% LOCAL FUNCTIONS
% ========================================================================

function [xmin,xmax] = getRange(D,name)

    xmin = NaN;
    xmax = NaN;


    if ~isfield(D,name)
        return;
    end


    x = D.(name);


    if ~isnumeric(x)
        return;
    end


    x = double(x(:));

    x = x(isfinite(x));


    if isempty(x)
        return;
    end


    xmin = min(x);
    xmax = max(x);

end