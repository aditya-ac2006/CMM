%% ╔══════════════════════════════════════════════════════════════╗
%  ║       CMM TTC OPERATING CONDITION SEGMENTER v2.0           ║
%  ║      TTC Runs → Operating Blocks → Sweep Candidates        ║
%  ╚══════════════════════════════════════════════════════════════╝
%
% CMM Formula Student Tire Modeling Pipeline
%
% PURPOSE
% -------
% Stage 2 of the CMM TTC processing pipeline.
%
% Reads ONLY files routed by:
%   CMM_CURRENT_MODEL_INPUT_MANIFEST_v1_1.csv
%
% Current model:
%   Hoosier 43075 16x7.5-10 R25B
%   7-inch rim
%   Free-rolling lateral/cornering model
%
% Expected input runs:
%   Run 2 = Cornering Part 1
%   Run 4 = Cornering Part 2
%
% This script:
%   1. Loads the mapper manifest
%   2. Loads each eligible TTC .mat file
%   3. Validates required channels
%   4. Converts raw channels into a unified table
%   5. Detects pressure / IA / load / speed operating states
%   6. Detects active SA sweep regions
%   7. Rejects obvious non-lateral regions
%   8. Creates candidate sweep records
%   9. Classifies special TTC regions
%  10. Exports Stage-2 database and MAT contract
%
% IMPORTANT:
% This stage DOES NOT perform Pacejka fitting.
% This stage DOES NOT delete excluded TTC data.
%
% Version: 2.0
% -------------------------------------------------------------------------

clear;
clc;
close all;

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║       CMM TTC OPERATING CONDITION SEGMENTER v2.0           ║\n');
fprintf('║      TTC Runs → Operating Blocks → Sweep Candidates        ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

%% ========================================================================
% CONFIGURATION
% =========================================================================

CFG = struct();

CFG.Version = "2.0";
CFG.ModelName = "CMM_7IN_LATERAL_MODEL";

% -------------------------------------------------------------------------
% Operating-condition quantisation
% -------------------------------------------------------------------------

% TTC pressures are nominally 8, 10, 12 and 14 psi.
% SI files normally store pressure in kPa.
CFG.NominalPressure_psi = [8 10 12 14];
CFG.NominalPressure_kPa = CFG.NominalPressure_psi * 6.894757293;

% Expected main TTC inclination angles.
CFG.NominalIA_deg = [-4 -2 0 2 4];

% Round-8 10-inch cornering loads.
% The exact measured FZ oscillates during a sweep, so load states are
% determined from magnitude and clustered automatically.
CFG.LoadTolerance_N = 120;

% Pressure state tolerance.
CFG.PressureTolerance_kPa = 8;

% IA state tolerance.
CFG.IATolerance_deg = 0.40;

% -------------------------------------------------------------------------
% Sweep detection
% -------------------------------------------------------------------------

% Main cornering sweeps go approximately +/-12 deg.
CFG.SweepMinSARange_deg = 15;

% A sweep should contain meaningful lateral-force variation.
CFG.SweepMinFYRange_N = 100;

% Ignore near-stationary data.
CFG.MinRoadSpeed_kph = 10;

% Free rolling check.
CFG.MaxAbsSL = 0.05;

% SA activity threshold.
CFG.MinAbsSA_deg = 1.0;

% Minimum samples in candidate region.
CFG.MinSweepSamples = 150;

% Minimum time duration.
CFG.MinSweepDuration_s = 2.0;

% Gap used to join nearby active-SA regions.
CFG.MaxGap_s = 1.5;

% Nominal TTC road speeds.
CFG.SpeedTargets_kph = [24.14 40.23 72.42];  % 15,25,45 mph
CFG.SpeedTolerance_kph = 5;

% -------------------------------------------------------------------------
% Output
% -------------------------------------------------------------------------

CFG.OutputFolderName = "CMM_Output";
CFG.StageFolderName = "Operating_Condition_Segmenter_v2_0";

%% ========================================================================
% [1] SELECT TTC DATA FOLDER
% =========================================================================

fprintf('[1] SELECT TTC DATA FOLDER\n');
fprintf('──────────────────────────────────────────────────────────────\n');

dataFolder = uigetdir(pwd, ...
    'Select TTC folder containing mapper output and TTC MAT files');

if isequal(dataFolder,0)
    error('CMM:UserCancelled', ...
        'Folder selection cancelled by user.');
end

fprintf('Selected folder:\n%s\n\n', dataFolder);

%% ========================================================================
% [2] LOCATE CURRENT MODEL MANIFEST
% =========================================================================

fprintf('[2] LOCATING CURRENT MODEL MANIFEST\n');
fprintf('──────────────────────────────────────────────────────────────\n');

% Locate Stage-1 output in the clean Git repository.
thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));
outputRoot = fullfile(repoRoot,'outputs','CMM_OUTPUT_V02');

manifestCandidates = dir(fullfile( ...
    outputRoot, ...
    '01_FILE_RUN_MAPPER', ...
    'CMM_CURRENT_MODEL_INPUT_MANIFEST_v1_1.csv'));

if isempty(manifestCandidates)

    error('CMM:ManifestMissing', ...
        ['Could not find:\n' ...
         'CMM_CURRENT_MODEL_INPUT_MANIFEST_v1_1.csv\n\n' ...
         'Run FILE + RUN MAPPER v1.1 first.']);

end

manifestPath = fullfile( ...
    manifestCandidates(1).folder, ...
    manifestCandidates(1).name);

fprintf('Manifest found:\n%s\n\n', manifestPath);

%% ========================================================================
% [3] LOAD CURRENT MODEL MANIFEST
% =========================================================================

fprintf('[3] LOADING CURRENT MODEL INPUT MANIFEST\n');
fprintf('──────────────────────────────────────────────────────────────\n');

Manifest = readtable(manifestPath, ...
    'TextType','string', ...
    'VariableNamingRule','preserve');

fprintf('Manifest rows : %d\n', height(Manifest));

disp(Manifest);

fprintf('\n');

%% ========================================================================
% FIND REQUIRED MANIFEST VARIABLES
% =========================================================================

varNames = string(Manifest.Properties.VariableNames);

runCol = findManifestColumn(varNames, ...
    ["RunNumber","Run","Run_Number"]);

fileCol = findManifestColumn(varNames, ...
    ["FileName","Filename","File","MATFile"]);

if isempty(runCol)
    error('CMM:ManifestFormat', ...
        'Could not identify RunNumber column in manifest.');
end

if isempty(fileCol)
    error('CMM:ManifestFormat', ...
        'Could not identify file-name column in manifest.');
end

RunNumbers = double(Manifest{:,runCol});
FileNames = string(Manifest{:,fileCol});

%% ========================================================================
% [4] VALIDATE MODEL ROUTING
% =========================================================================

fprintf('[4] VALIDATING MODEL ROUTING\n');
fprintf('──────────────────────────────────────────────────────────────\n');

fprintf('Current model : %s\n', CFG.ModelName);
fprintf('Input runs    : ');

fprintf('%d ', RunNumbers);
fprintf('\n');

expectedRuns = [2 4];

if all(ismember(expectedRuns,RunNumbers))
    fprintf('Expected Runs 2 + 4 : PASS\n');
else
    warning('CMM:UnexpectedRuns', ...
        'Current manifest does not contain both expected Runs 2 and 4.');
end

if any(~ismember(RunNumbers,expectedRuns))
    warning('CMM:ExtraRuns', ...
        ['Manifest contains runs other than 2 and 4.\n' ...
         'They will still be processed because the mapper routed them.']);
end

fprintf('\n');

%% ========================================================================
% [5] CREATE OUTPUT DIRECTORY
% =========================================================================

outputFolder = fullfile( ...
    outputRoot, ...
    '02_OPERATING_CONDITION_SEGMENTER');

if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end

fprintf('[5] OUTPUT DIRECTORY\n');
fprintf('──────────────────────────────────────────────────────────────\n');
fprintf('%s\n\n', outputFolder);

%% ========================================================================
% MASTER STORAGE
% =========================================================================

AllData = table();
SweepDB = table();
RunSummary = table();

globalSweepID = 0;

%% ========================================================================
% [6] PROCESS CURRENT MODEL RUNS
% =========================================================================

fprintf('[6] PROCESSING CURRENT MODEL RUNS\n');
fprintf('──────────────────────────────────────────────────────────────\n\n');

for r = 1:numel(RunNumbers)

    runNumber = RunNumbers(r);
    fileName  = FileNames(r);

    fprintf('==============================================================\n');
    fprintf('RUN %d\n', runNumber);
    fprintf('==============================================================\n');

    %% --------------------------------------------------------------------
    % Locate file
    % ---------------------------------------------------------------------

    directPath = fullfile(dataFolder,fileName);

    if exist(directPath,'file')

        filePath = directPath;

    else

        searchResult = dir(fullfile(dataFolder,'**',fileName));

        if isempty(searchResult)
            error('CMM:FileMissing', ...
                'Could not locate %s', fileName);
        end

        filePath = fullfile( ...
            searchResult(1).folder, ...
            searchResult(1).name);

    end

    fprintf('Loading : %s\n', fileName);

    Raw = load(filePath);

    %% --------------------------------------------------------------------
    % Validate channels
    % ---------------------------------------------------------------------

    requiredChannels = [ ...
        "ET", ...
        "FY", ...
        "FZ", ...
        "IA", ...
        "P", ...
        "SA", ...
        "V"];

    fprintf('Channel validation:\n');

    for c = 1:numel(requiredChannels)

        ch = requiredChannels(c);

        if ~isfield(Raw,ch)
            error('CMM:MissingChannel', ...
                'Run %d is missing required channel %s.', ...
                runNumber,ch);
        end

        fprintf('  ✓ %-6s\n',ch);

    end

    % SL is useful but allow SR fallback.
    if isfield(Raw,'SL')

        SL = columnVector(Raw.SL);
        slipChannel = "SL";

    elseif isfield(Raw,'SR')

        SL = columnVector(Raw.SR);
        slipChannel = "SR";

        warning('CMM:UsingSR', ...
            'Run %d has no SL channel. Using SR as fallback.',runNumber);

    else

        SL = zeros(size(columnVector(Raw.ET)));
        slipChannel = "NONE";

        warning('CMM:NoSlipRatio', ...
            'No SL/SR channel found in Run %d.',runNumber);

    end

    %% --------------------------------------------------------------------
    % Extract channels
    % ---------------------------------------------------------------------

    ET = columnVector(Raw.ET);
    FY = columnVector(Raw.FY);
    FZ = columnVector(Raw.FZ);
    IA = columnVector(Raw.IA);
    P  = columnVector(Raw.P);
    SA = columnVector(Raw.SA);
    V  = columnVector(Raw.V);

    n = numel(ET);

    channels = {FY,FZ,IA,P,SA,V,SL};

    for cc = 1:numel(channels)

        if numel(channels{cc}) ~= n

            error('CMM:ChannelLengthMismatch', ...
                'Channel length mismatch detected in Run %d.',runNumber);

        end

    end

    fprintf('\nSamples loaded : %d\n',n);
    fprintf('Time range     : %.2f → %.2f s\n', ...
        min(ET),max(ET));

    %% --------------------------------------------------------------------
    % Remove invalid samples
    % ---------------------------------------------------------------------

    valid = ...
        isfinite(ET) & ...
        isfinite(FY) & ...
        isfinite(FZ) & ...
        isfinite(IA) & ...
        isfinite(P)  & ...
        isfinite(SA) & ...
        isfinite(V);

    fprintf('Finite samples : %d / %d\n',sum(valid),n);

    ET = ET(valid);
    FY = FY(valid);
    FZ = FZ(valid);
    IA = IA(valid);
    P  = P(valid);
    SA = SA(valid);
    V  = V(valid);
    SL = SL(valid);

    %% --------------------------------------------------------------------
    % Determine SI / USCS pressure
    % ---------------------------------------------------------------------

    medianP = median(P,'omitnan');

    if medianP < 30

        % Data appears to be psi.
        fprintf('Pressure units : psi detected → converting to kPa\n');

        P_kPa = P * 6.894757293;

    else

        fprintf('Pressure units : kPa\n');

        P_kPa = P;

    end

    %% --------------------------------------------------------------------
    % Determine velocity units
    % ---------------------------------------------------------------------

    medianV = median(abs(V(V > 1)),'omitnan');

    % Round-8 SI data normally uses kph.
    % USCS files use mph.
    if ~isempty(medianV) && medianV < 35

        fprintf('Velocity units : mph detected → converting to kph\n');

        V_kph = V * 1.609344;

    else

        fprintf('Velocity units : kph\n');

        V_kph = V;

    end

    %% --------------------------------------------------------------------
    % Handle SAE FZ sign
    % ---------------------------------------------------------------------

    medianFZ = median(FZ,'omitnan');

    if medianFZ < 0

        fprintf('FZ convention  : negative loaded force detected\n');
        FZ_Load_N = abs(FZ);

    else

        fprintf('FZ convention  : positive loaded force detected\n');
        FZ_Load_N = abs(FZ);

    end

    %% --------------------------------------------------------------------
    % Nominal pressure
    % ---------------------------------------------------------------------

    PressureNominal_psi = nan(size(P_kPa));

    for i = 1:numel(P_kPa)

        [err,idx] = min(abs( ...
            CFG.NominalPressure_kPa - P_kPa(i)));

        if err <= CFG.PressureTolerance_kPa

            PressureNominal_psi(i) = ...
                CFG.NominalPressure_psi(idx);

        end

    end

    %% --------------------------------------------------------------------
    % Nominal IA
    % ---------------------------------------------------------------------

    IANominal_deg = nan(size(IA));

    for i = 1:numel(IA)

        [err,idx] = min(abs( ...
            CFG.NominalIA_deg - IA(i)));

        if err <= CFG.IATolerance_deg

            IANominal_deg(i) = ...
                CFG.NominalIA_deg(idx);

        end

    end

    %% --------------------------------------------------------------------
    % Nominal speed
    % ---------------------------------------------------------------------

    SpeedNominal_mph = nan(size(V_kph));

    speedTargets_mph = [15 25 45];

    for i = 1:numel(V_kph)

        [err,idx] = min(abs( ...
            CFG.SpeedTargets_kph - abs(V_kph(i))));

        if err <= CFG.SpeedTolerance_kph

            SpeedNominal_mph(i) = ...
                speedTargets_mph(idx);

        end

    end

    %% --------------------------------------------------------------------
    % Detect nominal FZ states
    % ---------------------------------------------------------------------

    fprintf('\nDetecting vertical-load states...\n');

    FZNominal_N = detectLoadStates( ...
        FZ_Load_N, ...
        CFG.LoadTolerance_N);

    loadStates = unique(FZNominal_N(isfinite(FZNominal_N)));

    fprintf('Detected load states : ');

    if isempty(loadStates)

        fprintf('NONE');

    else

        fprintf('%.0f N ',loadStates);

    end

    fprintf('\n');

    %% --------------------------------------------------------------------
    % Free rolling mask
    % ---------------------------------------------------------------------

    if slipChannel ~= "NONE"

        freeRolling = abs(SL) <= CFG.MaxAbsSL;

    else

        freeRolling = true(size(SL));

    end

    moving = abs(V_kph) >= CFG.MinRoadSpeed_kph;

    %% --------------------------------------------------------------------
    % SA sweep activity
    % ---------------------------------------------------------------------

    saActive = ...
        abs(SA) >= CFG.MinAbsSA_deg & ...
        moving & ...
        freeRolling;

    %% --------------------------------------------------------------------
    % Detect active regions
    % ---------------------------------------------------------------------

    candidateRegions = logicalRegions( ...
        saActive, ...
        ET, ...
        CFG.MaxGap_s);

    fprintf('\nCandidate SA-active regions : %d\n', ...
        height(candidateRegions));

    acceptedThisRun = 0;

    %% --------------------------------------------------------------------
    % Analyse each candidate region
    % ---------------------------------------------------------------------

    for regionID = 1:height(candidateRegions)

        i1 = candidateRegions.StartIndex(regionID);
        i2 = candidateRegions.EndIndex(regionID);

        idx = i1:i2;

        sampleCount = numel(idx);
        duration_s = ET(i2)-ET(i1);

        saRange = max(SA(idx))-min(SA(idx));
        fyRange = max(FY(idx))-min(FY(idx));

        if sampleCount < CFG.MinSweepSamples
            continue;
        end

        if duration_s < CFG.MinSweepDuration_s
            continue;
        end

        if saRange < CFG.SweepMinSARange_deg
            continue;
        end

        if fyRange < CFG.SweepMinFYRange_N
            continue;
        end

        % -------------------------------------------------------------
        % Determine dominant operating condition
        % -------------------------------------------------------------

        pressure = robustMode(PressureNominal_psi(idx));
        ia       = robustMode(IANominal_deg(idx));
        fz       = robustMode(FZNominal_N(idx));
        speed    = robustMode(SpeedNominal_mph(idx));

        % If nominal values could not be resolved, use medians.
        if isnan(pressure)
            pressure = median(P_kPa(idx),'omitnan') / 6.894757293;
        end

        if isnan(ia)
            ia = median(IA(idx),'omitnan');
        end

        if isnan(fz)
            fz = median(FZ_Load_N(idx),'omitnan');
        end

        if isnan(speed)
            speed = median(abs(V_kph(idx)),'omitnan') / 1.609344;
        end

        %% -------------------------------------------------------------
        % Classify sweep
        % -------------------------------------------------------------

        sweepType = classifySweep( ...
            runNumber, ...
            pressure, ...
            ia, ...
            speed, ...
            SA(idx), ...
            IA(idx));

        %% -------------------------------------------------------------
        % Determine sweep direction
        % -------------------------------------------------------------

        saStart = median(SA(idx(1:min(20,end))), ...
            'omitnan');

        saEnd = median(SA(idx(max(1,end-19):end)), ...
            'omitnan');

        if saEnd > saStart
            direction = "NEG_TO_POS";
        elseif saEnd < saStart
            direction = "POS_TO_NEG";
        else
            direction = "UNKNOWN";
        end

        %% -------------------------------------------------------------
        % Add sweep
        % -------------------------------------------------------------

        globalSweepID = globalSweepID + 1;
        acceptedThisRun = acceptedThisRun + 1;

        row = table( ...
            globalSweepID, ...
            runNumber, ...
            fileName, ...
            regionID, ...
            ET(i1), ...
            ET(i2), ...
            duration_s, ...
            sampleCount, ...
            pressure, ...
            fz, ...
            ia, ...
            speed, ...
            min(SA(idx)), ...
            max(SA(idx)), ...
            min(FY(idx)), ...
            max(FY(idx)), ...
            direction, ...
            sweepType, ...
            'VariableNames',{ ...
            'SweepID', ...
            'RunNumber', ...
            'FileName', ...
            'RegionID', ...
            'StartTime_s', ...
            'EndTime_s', ...
            'Duration_s', ...
            'SampleCount', ...
            'Pressure_psi', ...
            'FZ_N', ...
            'IA_deg', ...
            'Speed_mph', ...
            'SA_Min_deg', ...
            'SA_Max_deg', ...
            'FY_Min_N', ...
            'FY_Max_N', ...
            'Direction', ...
            'SweepType'});

        SweepDB = [SweepDB; row]; %#ok<AGROW>

        %% -------------------------------------------------------------
        % Store sample-level data
        % -------------------------------------------------------------

        sweepIDVector = ...
            repmat(globalSweepID,numel(idx),1);

        runVector = ...
            repmat(runNumber,numel(idx),1);

        fileVector = ...
            repmat(fileName,numel(idx),1);

        typeVector = ...
            repmat(sweepType,numel(idx),1);

        SampleTable = table( ...
            sweepIDVector, ...
            runVector, ...
            fileVector, ...
            ET(idx), ...
            SA(idx), ...
            FY(idx), ...
            FZ(idx), ...
            FZ_Load_N(idx), ...
            IA(idx), ...
            P_kPa(idx), ...
            V_kph(idx), ...
            SL(idx), ...
            typeVector, ...
            'VariableNames',{ ...
            'SweepID', ...
            'RunNumber', ...
            'FileName', ...
            'ET_s', ...
            'SA_deg', ...
            'FY_N', ...
            'FZ_Raw_N', ...
            'FZ_Load_N', ...
            'IA_deg', ...
            'P_kPa', ...
            'V_kph', ...
            'SL', ...
            'SweepType'});

        AllData = [AllData; SampleTable]; %#ok<AGROW>

    end

    %% --------------------------------------------------------------------
    % Run summary
    % ---------------------------------------------------------------------

    fprintf('Accepted sweep regions     : %d\n', ...
        acceptedThisRun);

    summaryRow = table( ...
        runNumber, ...
        fileName, ...
        numel(ET), ...
        height(candidateRegions), ...
        acceptedThisRun, ...
        'VariableNames',{ ...
        'RunNumber', ...
        'FileName', ...
        'ValidSamples', ...
        'CandidateRegions', ...
        'AcceptedSweeps'});

    RunSummary = [RunSummary; summaryRow]; %#ok<AGROW>

    fprintf('\n');

end

%% ========================================================================
% [7] VALIDATING SEGMENTED DATABASE
% =========================================================================

fprintf('[7] VALIDATING SEGMENTED DATABASE\n');
fprintf('──────────────────────────────────────────────────────────────\n');

if isempty(SweepDB)

    error('CMM:NoSweeps', ...
        ['No valid slip-angle sweep regions were detected.\n' ...
         'Inspect thresholds and source data before continuing.']);

end

fprintf('Total accepted sweeps : %d\n',height(SweepDB));
fprintf('Total samples routed  : %d\n',height(AllData));

fprintf('\nRuns represented:\n');

disp(unique(SweepDB(:,{'RunNumber','FileName'})));

fprintf('Pressure states detected : ');

pStates = unique(round(SweepDB.Pressure_psi,1));

fprintf('%.1f ',pStates);
fprintf('psi\n');

fprintf('IA states detected       : ');

iaStates = unique(round(SweepDB.IA_deg,1));

fprintf('%.1f ',iaStates);
fprintf('deg\n');

fprintf('Speed states detected    : ');

vStates = unique(round(SweepDB.Speed_mph,1));

fprintf('%.1f ',vStates);
fprintf('mph\n');

fprintf('\n');

%% ========================================================================
% [8] SWEEP TYPE SUMMARY
% =========================================================================

fprintf('[8] SWEEP CLASSIFICATION SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');

types = unique(SweepDB.SweepType);

for i = 1:numel(types)

    count = sum(SweepDB.SweepType == types(i));

    fprintf('%-25s : %d\n',types(i),count);

end

fprintf('\n');

%% ========================================================================
% [9] OPERATING CONDITION MATRIX
% =========================================================================

fprintf('[9] OPERATING CONDITION MATRIX\n');
fprintf('──────────────────────────────────────────────────────────────\n');

% Build one row per unique operating-condition combination.
%
% Using findgroups + splitapply instead of groupsummary improves
% compatibility across MATLAB releases.

groupVars = { ...
    'Pressure_psi', ...
    'FZ_N', ...
    'IA_deg', ...
    'Speed_mph', ...
    'SweepType'};

[G, ...
    PressureGroup, ...
    FZGroup, ...
    IAGroup, ...
    SpeedGroup, ...
    SweepTypeGroup] = findgroups( ...
        SweepDB.Pressure_psi, ...
        SweepDB.FZ_N, ...
        SweepDB.IA_deg, ...
        SweepDB.Speed_mph, ...
        SweepDB.SweepType);

SweepCount = splitapply(@numel, SweepDB.SweepID, G);

ConditionTable = table( ...
    PressureGroup, ...
    FZGroup, ...
    IAGroup, ...
    SpeedGroup, ...
    SweepTypeGroup, ...
    SweepCount, ...
    'VariableNames',{ ...
        'Pressure_psi', ...
        'FZ_N', ...
        'IA_deg', ...
        'Speed_mph', ...
        'SweepType', ...
        'SweepCount'});

% Sort into a readable engineering order.
ConditionTable = sortrows( ...
    ConditionTable, ...
    {'Speed_mph','Pressure_psi','IA_deg','FZ_N'});

disp(ConditionTable);

fprintf('\n');
%% ========================================================================
% [10] SAVE OUTPUT FILES
% =========================================================================

fprintf('[10] SAVING STAGE-2 OUTPUTS\n');
fprintf('──────────────────────────────────────────────────────────────\n');

sweepCSV = fullfile( ...
    outputFolder, ...
    'CMM_SWEEP_MANIFEST_v2_0.csv');

sampleCSV = fullfile( ...
    outputFolder, ...
    'CMM_SEGMENTED_LATERAL_DATA_v2_0.csv');

conditionCSV = fullfile( ...
    outputFolder, ...
    'CMM_OPERATING_CONDITION_MATRIX_v2_0.csv');

summaryCSV = fullfile( ...
    outputFolder, ...
    'CMM_SEGMENTER_RUN_SUMMARY_v2_0.csv');

matFile = fullfile( ...
    outputFolder, ...
    'CMM_SEGMENTER_CONTRACT_v2_0.mat');

writetable(SweepDB,sweepCSV);
writetable(AllData,sampleCSV);
writetable(ConditionTable,conditionCSV);
writetable(RunSummary,summaryCSV);

SegmenterContract = struct();

SegmenterContract.Version = CFG.Version;
SegmenterContract.ModelName = CFG.ModelName;
SegmenterContract.Configuration = CFG;
SegmenterContract.SweepManifest = SweepDB;
SegmenterContract.SegmentedData = AllData;
SegmenterContract.ConditionMatrix = ConditionTable;
SegmenterContract.RunSummary = RunSummary;
SegmenterContract.SourceManifest = Manifest;

save(matFile,'SegmenterContract','-v7.3');

fprintf('Sweep manifest saved:\n%s\n\n',sweepCSV);

fprintf('Segmented sample database saved:\n%s\n\n',sampleCSV);

fprintf('Operating-condition matrix saved:\n%s\n\n',conditionCSV);

fprintf('Run summary saved:\n%s\n\n',summaryCSV);

fprintf('MAT contract saved:\n%s\n\n',matFile);

%% ========================================================================
% [11] GENERATE DIAGNOSTIC FIGURES
% =========================================================================

fprintf('[11] GENERATING DIAGNOSTIC FIGURES\n');
fprintf('──────────────────────────────────────────────────────────────\n');

runList = unique(AllData.RunNumber);

for r = 1:numel(runList)

    runNumber = runList(r);

    mask = AllData.RunNumber == runNumber;

    fig = figure( ...
        'Name',sprintf('CMM Run %d Segmented Sweeps',runNumber), ...
        'Color','w');

    scatter( ...
        AllData.SA_deg(mask), ...
        AllData.FY_N(mask), ...
        5, ...
        AllData.SweepID(mask), ...
        'filled');

    grid on;

    xlabel('Slip Angle SA [deg]');
    ylabel('Lateral Force FY [N]');

    title(sprintf( ...
        'CMM TTC Run %d — Detected Sweep Candidates', ...
        runNumber));

    cb = colorbar;
    cb.Label.String = 'Sweep ID';

    figPath = fullfile( ...
        outputFolder, ...
        sprintf('RUN_%d_SEGMENTED_SWEEPS.png',runNumber));

    exportgraphics(fig,figPath,'Resolution',200);

end

fprintf('Diagnostic figures generated.\n\n');

%% ========================================================================
% [12] FINAL SUMMARY
% =========================================================================

fprintf('[12] FINAL SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');

fprintf('Model                     : %s\n',CFG.ModelName);
fprintf('Runs processed            : %d\n',height(RunSummary));
fprintf('Accepted sweep regions    : %d\n',height(SweepDB));
fprintf('Segmented data samples    : %d\n',height(AllData));
fprintf('Operating-condition rows  : %d\n',height(ConditionTable));

fprintf('\n');

disp(RunSummary);

fprintf('\n');

fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║          OPERATING CONDITION SEGMENTATION COMPLETE         ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');

fprintf('CURRENT MODEL:\n');
fprintf('7-inch CORNERING data only.\n\n');

fprintf('STAGE-2 OUTPUT:\n');
fprintf('Operating conditions + candidate SA sweep regions.\n\n');

fprintf('NEXT PIPELINE STAGE:\n');
fprintf('CMM TTC SWEEP EXTRACTOR + QUALITY FILTER v3.0\n\n');


%% ========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function idx = findManifestColumn(names,candidates)

    idx = [];

    namesLower = lower(names);

    for i = 1:numel(candidates)

        candidate = lower(candidates(i));

        hit = find(namesLower == candidate,1);

        if ~isempty(hit)
            idx = hit;
            return;
        end

    end

end


function x = columnVector(x)

    x = double(x(:));

end


function nominal = detectLoadStates(FZ,tolerance)

    nominal = nan(size(FZ));

    valid = isfinite(FZ) & FZ > 50;

    if ~any(valid)
        return;
    end

    values = FZ(valid);

    % Round the load to coarse 50 N bins first.
    coarse = round(values/50)*50;

    states = unique(coarse);

    % Remove very sparsely populated states.
    counts = zeros(size(states));

    for i = 1:numel(states)
        counts(i) = sum(abs(values-states(i)) <= tolerance);
    end

    minimumPopulation = max(100,round(0.002*numel(values)));

    states = states(counts >= minimumPopulation);

    if isempty(states)
        return;
    end

    % Merge nearby states.
    states = sort(states);

    merged = states(1);

    for i = 2:numel(states)

        if states(i)-merged(end) <= tolerance

            merged(end) = ...
                round(mean([merged(end),states(i)])/10)*10;

        else

            merged(end+1) = states(i); %#ok<AGROW>

        end

    end

    for i = 1:numel(FZ)

        if ~valid(i)
            continue;
        end

        [err,k] = min(abs(merged-FZ(i)));

        if err <= tolerance
            nominal(i) = merged(k);
        end

    end

end


function regions = logicalRegions(mask,time,maxGap)

    mask = logical(mask(:));
    time = time(:);

    activeIndices = find(mask);

    if isempty(activeIndices)

        regions = table( ...
            zeros(0,1), ...
            zeros(0,1), ...
            'VariableNames',{'StartIndex','EndIndex'});

        return;

    end

    starts = activeIndices(1);
    ends = [];

    for i = 2:numel(activeIndices)

        previous = activeIndices(i-1);
        current  = activeIndices(i);

        gap = time(current)-time(previous);

        if gap > maxGap

            ends(end+1,1) = previous; %#ok<AGROW>
            starts(end+1,1) = current; %#ok<AGROW>

        end

    end

    ends(end+1,1) = activeIndices(end);

    regions = table( ...
        starts(:), ...
        ends(:), ...
        'VariableNames',{'StartIndex','EndIndex'});

end


function value = robustMode(x)

    x = x(isfinite(x));

    if isempty(x)

        value = NaN;
        return;

    end

    rounded = round(x,2);

    value = mode(rounded);

end


function sweepType = classifySweep( ...
    runNumber,pressure,ia,speed,SA,IAraw)

    %#ok<INUSD>

    % -------------------------------------------------------------
    % High/low-speed TTC blocks
    % -------------------------------------------------------------

    if abs(speed-15) < 3

        sweepType = "SPEED_TEST_15MPH";
        return;

    elseif abs(speed-45) < 5

        sweepType = "SPEED_TEST_45MPH";
        return;

    end

    % -------------------------------------------------------------
    % Camber sweep detection
    %
    % Camber sweeps should normally NOT enter here because they occur
    % around SA = 0, but retain explicit protection.
    % -------------------------------------------------------------

    if range(IAraw) > 5 && range(SA) < 5

        sweepType = "CAMBER_SWEEP";
        return;

    end

    % -------------------------------------------------------------
    % Standard 25 mph lateral sweep
    % -------------------------------------------------------------

    if abs(speed-25) < 5

        if runNumber == 2

            sweepType = "MAIN_CORNERING_PART_1";

        elseif runNumber == 4

            if abs(pressure-12) < 1

                sweepType = "RUN4_12PSI_OR_REPEAT";

            else

                sweepType = "MAIN_CORNERING_PART_2";

            end

        else

            sweepType = "STANDARD_CORNERING";

        end

        return;

    end

    sweepType = "UNCLASSIFIED";

end