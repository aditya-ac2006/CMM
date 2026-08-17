%% ╔══════════════════════════════════════════════════════════════╗
%  ║       CMM TTC SWEEP EXTRACTOR + QUALITY FILTER v3.2        ║
%  ║      Stage-2 Regions → Structural Legs → Clean Sweeps      ║
%  ╚══════════════════════════════════════════════════════════════╝
%
% CMM Formula Student Tire Modeling Pipeline
%
% PRODUCTION PIPELINE — CMM_OUTPUT_V02
%
% INPUT
% -----
% CMM_SEGMENTER_CONTRACT_v2_0.mat
%
% STAGE-2 REGION STRUCTURE
% ------------------------
%
%      ENTRY LEG            FULL CENTRAL SWEEP          EXIT LEG
%
%   start → +SA peak       +SA peak → -SA peak       -SA peak → end
%          (~+12°)               (~24° span)               (~-12°)
%
% Validator v3.1 established that the Stage-2 regions contain this
% multi-direction structure.
%
% POLICY
% ------
% ENTRY_PARTIAL_LEG:
%       preserved for traceability
%       NOT used for model fitting
%
% FULL_CENTRAL_SWEEP:
%       endpoint trimmed
%       QC checked
%       routed to PRIMARY_MODEL_FIT or VALIDATION_SPEED_DATA
%
% EXIT_PARTIAL_LEG:
%       preserved for traceability
%       NOT used for model fitting
%
% OUTPUT ROOT
% -----------
% CMM_OUTPUT_V02
%
% OUTPUT STAGE
% ------------
% CMM_OUTPUT_V02\03_SWEEP_EXTRACTOR
%
% Version: 3.2
% -------------------------------------------------------------------------

clear;
clc;
close all;

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║       CMM TTC SWEEP EXTRACTOR + QUALITY FILTER v3.2        ║\n');
fprintf('║      Stage-2 Regions → Structural Legs → Clean Sweeps      ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');


%% ========================================================================
% CONFIGURATION
% =========================================================================

CFG = struct();

CFG.Version      = "3.2";
CFG.Pipeline     = "CMM_OUTPUT_V02";
CFG.ModelName    = "CMM_7IN_LATERAL_MODEL";

% -------------------------------------------------------------------------
% EXPECTED INPUT CONTRACT
% -------------------------------------------------------------------------

CFG.ExpectedStage2Regions = 90;
CFG.AllowedRuns           = [2 4];

% -------------------------------------------------------------------------
% TURNING-POINT DETECTION
% -------------------------------------------------------------------------

% Smooth SA ONLY for locating structural peaks.
% Raw SA is retained in exported data.
CFG.SASmoothingWindow_samples = 21;

% Expected TTC sweep amplitude.
CFG.MinPositivePeak_deg = 9.0;
CFG.MaxNegativePeak_deg = -9.0;

% Minimum expected peak-to-peak central sweep span.
CFG.MinCentralRawSpan_deg = 20.0;

% -------------------------------------------------------------------------
% CENTRAL SWEEP TRIMMING
% -------------------------------------------------------------------------
%
% Do not retain reversal/dwell behaviour directly at +/-12 deg.
% Final fitting sweep uses approximately +/-10.5 deg.
%

CFG.TrimLimit_deg = 10.5;

% Minimum required SA range AFTER trimming.
CFG.MinTrimmedSARange_deg = 18.0;

% -------------------------------------------------------------------------
% SAMPLE / DURATION QUALITY
% -------------------------------------------------------------------------

CFG.MinSamples = 100;

CFG.MinSweepDuration_s = 1.5;

% -------------------------------------------------------------------------
% MONOTONICITY
% -------------------------------------------------------------------------

CFG.DirectionDeadband_deg = 0.002;

CFG.MinMonotonicFraction = 0.80;

% -------------------------------------------------------------------------
% FY QUALITY
% -------------------------------------------------------------------------

CFG.MinFYRange_N = 100;

% -------------------------------------------------------------------------
% OPERATING CONDITION QUALITY
% -------------------------------------------------------------------------

CFG.MaxPressureStd_kPa = 3.0;

CFG.MaxIAStd_deg = 0.20;

CFG.MaxSpeedStd_kph = 2.0;

% -------------------------------------------------------------------------
% FREE ROLLING
% -------------------------------------------------------------------------

CFG.MaxAbsSL = 0.03;

CFG.MinFreeRollingFraction = 0.98;

% -------------------------------------------------------------------------
% FZ QUALITY
% -------------------------------------------------------------------------
%
% We retain ACTUAL measured FZ statistics per sweep.
%
% Stage-2 FZ labels are metadata only and are NOT treated as the fitting
% load.
%

CFG.MaxFZRelativeRange = 0.45;

% -------------------------------------------------------------------------
% MODEL ROUTING
% -------------------------------------------------------------------------

CFG.PrimaryModelSpeed_mph = 25;

CFG.SpeedMatchTolerance_mph = 4;

% -------------------------------------------------------------------------
% OUTPUT
% -------------------------------------------------------------------------

CFG.OutputRoot = "CMM_OUTPUT_V02"; % stored under repoRoot\outputs

CFG.StageFolder = "03_SWEEP_EXTRACTOR";

% -------------------------------------------------------------------------
% FIGURE THEME
% -------------------------------------------------------------------------

CFG.FigureBackground = [0 0 0];
CFG.AxesBackground   = [0 0 0];

CFG.Foreground = [1 1 1];

CFG.GridColor = [0.35 0.35 0.35];

CFG.MinorGridColor = [0.20 0.20 0.20];


%% ========================================================================
% [1] SELECT TTC PROJECT FOLDER
% =========================================================================

fprintf('[1] SELECT TTC PROJECT FOLDER\n');
fprintf('──────────────────────────────────────────────────────────────\n');

dataFolder = uigetdir( ...
    pwd, ...
    'Select TTC folder containing source data and CMM outputs');

if isequal(dataFolder,0)

    error( ...
        'CMM:UserCancelled', ...
        'Folder selection cancelled.');

end

fprintf('Selected folder:\n%s\n\n',dataFolder);


%% ========================================================================
% [2] LOCATE STAGE-2 CONTRACT
% =========================================================================

fprintf('[2] LOCATING STAGE-2 CONTRACT\n');
fprintf('──────────────────────────────────────────────────────────────\n');

% Locate Stage-2 contract in the clean Git repository outputs.
thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));
outputRoot = fullfile(repoRoot,'outputs',CFG.OutputRoot);

contractFiles = dir(fullfile( ...
    outputRoot, ...
    '02_OPERATING_CONDITION_SEGMENTER', ...
    'CMM_SEGMENTER_CONTRACT_v2_0.mat'));

if isempty(contractFiles)

    error( ...
        'CMM:Stage2Missing', ...
        ['Could not locate:\n' ...
         'CMM_SEGMENTER_CONTRACT_v2_0.mat\n\n' ...
         'Stage 2 must be completed before Stage 3.']);

end

if numel(contractFiles) > 1

    fprintf('WARNING: Multiple Stage-2 contracts found.\n');
    fprintf('Using:\n');

end

contractPath = fullfile( ...
    contractFiles(1).folder, ...
    contractFiles(1).name);

fprintf('Contract found:\n%s\n\n',contractPath);


%% ========================================================================
% [3] LOAD STAGE-2 CONTRACT
% =========================================================================

fprintf('[3] LOADING STAGE-2 CONTRACT\n');
fprintf('──────────────────────────────────────────────────────────────\n');

S = load(contractPath);

if ~isfield(S,'SegmenterContract')

    error( ...
        'CMM:InvalidContract', ...
        'MAT file does not contain SegmenterContract.');

end

Stage2 = S.SegmenterContract;

requiredContractFields = [ ...
    "SweepManifest", ...
    "SegmentedData"];

for i = 1:numel(requiredContractFields)

    fieldName = requiredContractFields(i);

    if ~isfield(Stage2,fieldName)

        error( ...
            'CMM:InvalidContract', ...
            'Stage-2 contract missing field: %s', ...
            fieldName);

    end

end

RegionManifest = Stage2.SweepManifest;
SegmentedData  = Stage2.SegmentedData;

fprintf('Stage-2 regions : %d\n',height(RegionManifest));
fprintf('Stage-2 samples : %d\n',height(SegmentedData));
fprintf('Model            : %s\n',CFG.ModelName);
fprintf('Pipeline         : %s\n\n',CFG.Pipeline);


%% ========================================================================
% [4] VALIDATE STAGE-2 DATABASE
% =========================================================================

fprintf('[4] VALIDATING STAGE-2 DATABASE\n');
fprintf('──────────────────────────────────────────────────────────────\n');

requiredVariables = [ ...
    "SweepID", ...
    "RunNumber", ...
    "ET_s", ...
    "SA_deg", ...
    "FY_N", ...
    "FZ_Load_N", ...
    "IA_deg", ...
    "P_kPa", ...
    "V_kph", ...
    "SL", ...
    "SweepType"];

dataVariables = string( ...
    SegmentedData.Properties.VariableNames);

for i = 1:numel(requiredVariables)

    variableName = requiredVariables(i);

    if ~ismember(variableName,dataVariables)

        error( ...
            'CMM:MissingVariable', ...
            'Segmented database missing variable: %s', ...
            variableName);

    end

    fprintf('  ✓ %-15s\n',variableName);

end

fprintf('\n');

regionIDs = unique(SegmentedData.SweepID);

fprintf('Unique Stage-2 regions : %d\n',numel(regionIDs));

runsPresent = unique(SegmentedData.RunNumber);

fprintf('Runs represented       : ');

fprintf('%d ',runsPresent);

fprintf('\n');

if any(~ismember(runsPresent,CFG.AllowedRuns))

    error( ...
        'CMM:InvalidRunRouting', ...
        'Stage-2 database contains runs outside Runs 2 and 4.');

end

fprintf('7-inch run routing     : PASS\n');

if numel(regionIDs) == CFG.ExpectedStage2Regions

    fprintf('Expected 90 regions    : PASS\n');

else

    fprintf('Expected 90 regions    : WARNING (%d detected)\n', ...
        numel(regionIDs));

end

fprintf('\n');


%% ========================================================================
% [5] CREATE CMM_OUTPUT_V02
% =========================================================================

fprintf('[5] OUTPUT DIRECTORY\n');
fprintf('──────────────────────────────────────────────────────────────\n');

% All Stage-3 artifacts live under CMM_GIT\outputs.
outputRoot = fullfile(repoRoot,'outputs',CFG.OutputRoot);

outputFolder = fullfile( ...
    outputRoot, ...
    '03_SWEEP_EXTRACTOR');

figureFolder = fullfile( ...
    outputFolder, ...
    'FIGURES');

if ~exist(outputRoot,'dir')
    mkdir(outputRoot);
end

if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end

if ~exist(figureFolder,'dir')
    mkdir(figureFolder);
end

fprintf('Pipeline root:\n%s\n\n',outputRoot);

fprintf('Stage-3 output:\n%s\n\n',outputFolder);

fprintf('Figure output:\n%s\n\n',figureFolder);


%% ========================================================================
% STORAGE
% =========================================================================

StructuralLegManifest = table();

FullSweepManifest = table();

AcceptedSweepManifest = table();

RejectedSweepManifest = table();

AllStructuralLegData = table();

AllFullSweepData = table();

CleanLateralDatabase = table();

ValidationSpeedDatabase = table();

fullSweepID = 0;
structuralLegID = 0;

positivePeakFailures = 0;
negativePeakFailures = 0;
peakOrderFailures    = 0;
centralSpanFailures  = 0;


%% ========================================================================
% [6] EXTRACT STRUCTURAL LEGS
% =========================================================================

fprintf('[6] EXTRACTING STRUCTURAL LEGS\n');
fprintf('──────────────────────────────────────────────────────────────\n\n');

for rr = 1:numel(regionIDs)

    regionID = regionIDs(rr);

    regionMask = ...
        SegmentedData.SweepID == regionID;

    R = SegmentedData(regionMask,:);

    R = sortrows(R,'ET_s');

    runNumber = R.RunNumber(1);

    sweepType = string(R.SweepType(1));

    SAraw = R.SA_deg;

    nRegionSamples = height(R);


    %% --------------------------------------------------------------------
    % Smooth SA for structural peak detection
    % ---------------------------------------------------------------------

    if nRegionSamples >= CFG.SASmoothingWindow_samples

        SAsmooth = movmean( ...
            SAraw, ...
            CFG.SASmoothingWindow_samples, ...
            'omitnan');

    else

        SAsmooth = SAraw;

    end


    %% --------------------------------------------------------------------
    % Detect measured positive and negative turning points
    % ---------------------------------------------------------------------

    [positivePeakSA,iPositivePeak] = max(SAsmooth);

    [negativePeakSA,iNegativePeak] = min(SAsmooth);

    rawCentralSpan = ...
        positivePeakSA-negativePeakSA;


    %% --------------------------------------------------------------------
    % Structural validation
    % ---------------------------------------------------------------------

    positivePeakPass = ...
        positivePeakSA >= CFG.MinPositivePeak_deg;

    negativePeakPass = ...
        negativePeakSA <= CFG.MaxNegativePeak_deg;

    peakOrderPass = ...
        iPositivePeak < iNegativePeak;

    centralSpanPass = ...
        rawCentralSpan >= CFG.MinCentralRawSpan_deg;


    if ~positivePeakPass
        positivePeakFailures = positivePeakFailures+1;
    end

    if ~negativePeakPass
        negativePeakFailures = negativePeakFailures+1;
    end

    if ~peakOrderPass
        peakOrderFailures = peakOrderFailures+1;
    end

    if ~centralSpanPass
        centralSpanFailures = centralSpanFailures+1;
    end


    fprintf( ...
        ['Region %3d | Run %d | %-23s | ' ...
         '+Peak %6.2f° | -Peak %6.2f° | '], ...
        regionID, ...
        runNumber, ...
        sweepType, ...
        positivePeakSA, ...
        negativePeakSA);


    if ~( ...
            positivePeakPass && ...
            negativePeakPass && ...
            peakOrderPass && ...
            centralSpanPass)

        fprintf('STRUCTURE FAIL\n');

        continue;

    end


    %% --------------------------------------------------------------------
    % Structural indices
    % ---------------------------------------------------------------------

    entryIndices = ...
        (1:iPositivePeak)';

    centralIndices = ...
        (iPositivePeak:iNegativePeak)';

    exitIndices = ...
        (iNegativePeak:nRegionSamples)';


    %% --------------------------------------------------------------------
    % Preserve ENTRY leg
    % ---------------------------------------------------------------------

    structuralLegID = structuralLegID+1;

    Entry = R(entryIndices,:);

    Entry.StructuralLegID = ...
        repmat(structuralLegID,height(Entry),1);

    Entry.Stage2RegionID = ...
        repmat(regionID,height(Entry),1);

    Entry.LegType = ...
        repmat("ENTRY_PARTIAL_LEG",height(Entry),1);

    AllStructuralLegData = ...
        [AllStructuralLegData; Entry]; %#ok<AGROW>

    entryManifestRow = createStructuralLegRow( ...
        structuralLegID, ...
        regionID, ...
        runNumber, ...
        sweepType, ...
        "ENTRY_PARTIAL_LEG", ...
        Entry);

    StructuralLegManifest = ...
        [StructuralLegManifest; entryManifestRow]; %#ok<AGROW>


    %% --------------------------------------------------------------------
    % Preserve CENTRAL raw leg
    % ---------------------------------------------------------------------

    structuralLegID = structuralLegID+1;

    CentralRaw = R(centralIndices,:);

    CentralRaw.StructuralLegID = ...
        repmat(structuralLegID,height(CentralRaw),1);

    CentralRaw.Stage2RegionID = ...
        repmat(regionID,height(CentralRaw),1);

    CentralRaw.LegType = ...
        repmat("FULL_CENTRAL_SWEEP_RAW",height(CentralRaw),1);

    AllStructuralLegData = ...
        [AllStructuralLegData; CentralRaw]; %#ok<AGROW>

    centralManifestRow = createStructuralLegRow( ...
        structuralLegID, ...
        regionID, ...
        runNumber, ...
        sweepType, ...
        "FULL_CENTRAL_SWEEP_RAW", ...
        CentralRaw);

    StructuralLegManifest = ...
        [StructuralLegManifest; centralManifestRow]; %#ok<AGROW>


    %% --------------------------------------------------------------------
    % Preserve EXIT leg
    % ---------------------------------------------------------------------

    structuralLegID = structuralLegID+1;

    Exit = R(exitIndices,:);

    Exit.StructuralLegID = ...
        repmat(structuralLegID,height(Exit),1);

    Exit.Stage2RegionID = ...
        repmat(regionID,height(Exit),1);

    Exit.LegType = ...
        repmat("EXIT_PARTIAL_LEG",height(Exit),1);

    AllStructuralLegData = ...
        [AllStructuralLegData; Exit]; %#ok<AGROW>

    exitManifestRow = createStructuralLegRow( ...
        structuralLegID, ...
        regionID, ...
        runNumber, ...
        sweepType, ...
        "EXIT_PARTIAL_LEG", ...
        Exit);

    StructuralLegManifest = ...
        [StructuralLegManifest; exitManifestRow]; %#ok<AGROW>


    %% --------------------------------------------------------------------
    % Extract fitting portion from central sweep
    % ---------------------------------------------------------------------

    trimMask = ...
        abs(CentralRaw.SA_deg) <= CFG.TrimLimit_deg;

    trimIndices = find(trimMask);

    trimIndices = ...
        largestContiguousBlock(trimIndices);

    if isempty(trimIndices)

        fprintf('TRIM FAIL\n');

        continue;

    end

    T = CentralRaw(trimIndices,:);


    %% --------------------------------------------------------------------
    % Remove non-finite samples
    % ---------------------------------------------------------------------

    finiteMask = ...
        isfinite(T.ET_s)      & ...
        isfinite(T.SA_deg)    & ...
        isfinite(T.FY_N)      & ...
        isfinite(T.FZ_Load_N) & ...
        isfinite(T.IA_deg)    & ...
        isfinite(T.P_kPa)     & ...
        isfinite(T.V_kph)     & ...
        isfinite(T.SL);

    T = T(finiteMask,:);

    if isempty(T)

        fprintf('FINITE DATA FAIL\n');

        continue;

    end


    %% --------------------------------------------------------------------
    % Assign definitive full-sweep ID
    % ---------------------------------------------------------------------

    fullSweepID = fullSweepID+1;


    %% ====================================================================
    % SWEEP STATISTICS
    % =====================================================================

    sampleCount = height(T);

    startTime = T.ET_s(1);
    endTime   = T.ET_s(end);

    duration = endTime-startTime;

    saStart = T.SA_deg(1);
    saEnd   = T.SA_deg(end);

    saMin = min(T.SA_deg);
    saMax = max(T.SA_deg);

    saRange = saMax-saMin;

    fyMin = min(T.FY_N);
    fyMax = max(T.FY_N);

    fyRange = fyMax-fyMin;


    %% --------------------------------------------------------------------
    % FZ statistics
    % ---------------------------------------------------------------------

    FZmean = mean( ...
        T.FZ_Load_N, ...
        'omitnan');

    FZmedian = median( ...
        T.FZ_Load_N, ...
        'omitnan');

    FZstd = std( ...
        T.FZ_Load_N, ...
        'omitnan');

    FZmin = min(T.FZ_Load_N);
    FZmax = max(T.FZ_Load_N);

    FZrelativeRange = ...
        (FZmax-FZmin) / max(abs(FZmedian),1);


    %% --------------------------------------------------------------------
    % Pressure statistics
    % ---------------------------------------------------------------------

    Pmean = mean( ...
        T.P_kPa, ...
        'omitnan');

    Pstd = std( ...
        T.P_kPa, ...
        'omitnan');

    Pmean_psi = ...
        Pmean / 6.894757293;


    %% --------------------------------------------------------------------
    % IA statistics
    % ---------------------------------------------------------------------

    IAmean = mean( ...
        T.IA_deg, ...
        'omitnan');

    IAmedian = median( ...
        T.IA_deg, ...
        'omitnan');

    IAstd = std( ...
        T.IA_deg, ...
        'omitnan');


    %% --------------------------------------------------------------------
    % Speed statistics
    % ---------------------------------------------------------------------

    Vabs = abs(T.V_kph);

    Vmean = mean( ...
        Vabs, ...
        'omitnan');

    Vstd = std( ...
        Vabs, ...
        'omitnan');

    Vmean_mph = ...
        Vmean / 1.609344;


    %% --------------------------------------------------------------------
    % Slip-ratio / free-rolling statistics
    % ---------------------------------------------------------------------

    maxAbsSL = max(abs(T.SL));

    freeRollingFraction = ...
        mean(abs(T.SL) <= CFG.MaxAbsSL);


    %% --------------------------------------------------------------------
    % Monotonicity
    % ---------------------------------------------------------------------

    dSA = diff(T.SA_deg);

    significantDerivative = ...
        abs(dSA) >= CFG.DirectionDeadband_deg;

    dSAsignificant = ...
        dSA(significantDerivative);

    if isempty(dSAsignificant)

        monotonicFraction = 0;

    else

        % Central TTC sweep is expected POSITIVE → NEGATIVE.
        monotonicFraction = ...
            mean(dSAsignificant < 0);

    end


    %% ====================================================================
    % STAGE-2 METADATA
    % =====================================================================

    manifestMask = ...
        RegionManifest.SweepID == regionID;

    if any(manifestMask)

        RM = RegionManifest(find(manifestMask,1),:);

        stage2Pressure_psi = RM.Pressure_psi;
        stage2FZ_N         = RM.FZ_N;
        stage2IA_deg       = RM.IA_deg;
        stage2Speed_mph    = RM.Speed_mph;

    else

        stage2Pressure_psi = NaN;
        stage2FZ_N         = NaN;
        stage2IA_deg       = NaN;
        stage2Speed_mph    = NaN;

    end


    %% ====================================================================
    % QUALITY CONTROL
    % =====================================================================

    QC_SampleCount = ...
        sampleCount >= CFG.MinSamples;

    QC_Duration = ...
        duration >= CFG.MinSweepDuration_s;

    QC_SACoverage = ...
        saRange >= CFG.MinTrimmedSARange_deg;

    QC_FYRange = ...
        fyRange >= CFG.MinFYRange_N;

    QC_Monotonicity = ...
        monotonicFraction >= CFG.MinMonotonicFraction;

    QC_Pressure = ...
        Pstd <= CFG.MaxPressureStd_kPa;

    QC_IA = ...
        IAstd <= CFG.MaxIAStd_deg;

    QC_Speed = ...
        Vstd <= CFG.MaxSpeedStd_kph;

    QC_FreeRolling = ...
        freeRollingFraction >= CFG.MinFreeRollingFraction;

    QC_FZ = ...
        FZrelativeRange <= CFG.MaxFZRelativeRange;


    QCPass = ...
        QC_SampleCount  && ...
        QC_Duration     && ...
        QC_SACoverage   && ...
        QC_FYRange      && ...
        QC_Monotonicity && ...
        QC_Pressure     && ...
        QC_IA           && ...
        QC_Speed        && ...
        QC_FreeRolling  && ...
        QC_FZ;


    %% ====================================================================
    % MODEL ROUTING
    % =====================================================================

    primarySpeed = ...
        abs( ...
        Vmean_mph-CFG.PrimaryModelSpeed_mph) <= ...
        CFG.SpeedMatchTolerance_mph;

    if QCPass && primarySpeed

        ModelRouting = ...
            "PRIMARY_MODEL_FIT";

    elseif QCPass

        ModelRouting = ...
            "VALIDATION_SPEED_DATA";

    else

        ModelRouting = ...
            "REJECTED_QC";

    end


    %% ====================================================================
    % REJECTION REASONS
    % =====================================================================

    reasons = strings(0,1);

    if ~QC_SampleCount
        reasons(end+1) = "LOW_SAMPLE_COUNT";
    end

    if ~QC_Duration
        reasons(end+1) = "SHORT_DURATION";
    end

    if ~QC_SACoverage
        reasons(end+1) = "INSUFFICIENT_SA_RANGE";
    end

    if ~QC_FYRange
        reasons(end+1) = "INSUFFICIENT_FY_RANGE";
    end

    if ~QC_Monotonicity
        reasons(end+1) = "LOW_MONOTONICITY";
    end

    if ~QC_Pressure
        reasons(end+1) = "PRESSURE_UNSTABLE";
    end

    if ~QC_IA
        reasons(end+1) = "IA_UNSTABLE";
    end

    if ~QC_Speed
        reasons(end+1) = "SPEED_UNSTABLE";
    end

    if ~QC_FreeRolling
        reasons(end+1) = "NOT_FREE_ROLLING";
    end

    if ~QC_FZ
        reasons(end+1) = "FZ_UNSTABLE";
    end


    if isempty(reasons)

        rejectionReason = "NONE";

    else

        rejectionReason = ...
            strjoin(reasons,";");

    end


    %% ====================================================================
    % CREATE FULL-SWEEP MANIFEST ROW
    % =====================================================================

    manifestRow = table( ...
        fullSweepID, ...
        regionID, ...
        runNumber, ...
        sweepType, ...
        "POS_TO_NEG", ...
        positivePeakSA, ...
        negativePeakSA, ...
        rawCentralSpan, ...
        startTime, ...
        endTime, ...
        duration, ...
        sampleCount, ...
        saStart, ...
        saEnd, ...
        saMin, ...
        saMax, ...
        saRange, ...
        fyMin, ...
        fyMax, ...
        fyRange, ...
        stage2Pressure_psi, ...
        stage2FZ_N, ...
        stage2IA_deg, ...
        stage2Speed_mph, ...
        Pmean, ...
        Pmean_psi, ...
        Pstd, ...
        FZmean, ...
        FZmedian, ...
        FZstd, ...
        FZmin, ...
        FZmax, ...
        FZrelativeRange, ...
        IAmean, ...
        IAmedian, ...
        IAstd, ...
        Vmean, ...
        Vmean_mph, ...
        Vstd, ...
        maxAbsSL, ...
        freeRollingFraction, ...
        monotonicFraction, ...
        QC_SampleCount, ...
        QC_Duration, ...
        QC_SACoverage, ...
        QC_FYRange, ...
        QC_Monotonicity, ...
        QC_Pressure, ...
        QC_IA, ...
        QC_Speed, ...
        QC_FreeRolling, ...
        QC_FZ, ...
        QCPass, ...
        ModelRouting, ...
        rejectionReason, ...
        'VariableNames',{ ...
        'FullSweepID', ...
        'Stage2RegionID', ...
        'RunNumber', ...
        'Stage2SweepType', ...
        'Direction', ...
        'PositivePeakSA_deg', ...
        'NegativePeakSA_deg', ...
        'RawCentralSpan_deg', ...
        'StartTime_s', ...
        'EndTime_s', ...
        'Duration_s', ...
        'SampleCount', ...
        'SA_Start_deg', ...
        'SA_End_deg', ...
        'SA_Min_deg', ...
        'SA_Max_deg', ...
        'SA_Range_deg', ...
        'FY_Min_N', ...
        'FY_Max_N', ...
        'FY_Range_N', ...
        'Stage2Pressure_psi', ...
        'Stage2FZ_N', ...
        'Stage2IA_deg', ...
        'Stage2Speed_mph', ...
        'P_Mean_kPa', ...
        'P_Mean_psi', ...
        'P_Std_kPa', ...
        'FZ_Mean_N', ...
        'FZ_Median_N', ...
        'FZ_Std_N', ...
        'FZ_Min_N', ...
        'FZ_Max_N', ...
        'FZ_RelativeRange', ...
        'IA_Mean_deg', ...
        'IA_Median_deg', ...
        'IA_Std_deg', ...
        'V_Mean_kph', ...
        'V_Mean_mph', ...
        'V_Std_kph', ...
        'MaxAbsSL', ...
        'FreeRollingFraction', ...
        'MonotonicFraction', ...
        'QC_SampleCount', ...
        'QC_Duration', ...
        'QC_SACoverage', ...
        'QC_FYRange', ...
        'QC_Monotonicity', ...
        'QC_Pressure', ...
        'QC_IA', ...
        'QC_Speed', ...
        'QC_FreeRolling', ...
        'QC_FZ', ...
        'QCPass', ...
        'ModelRouting', ...
        'RejectionReason'});


    FullSweepManifest = ...
        [FullSweepManifest; manifestRow]; %#ok<AGROW>


    %% ====================================================================
    % CREATE SAMPLE-LEVEL FULL SWEEP
    % =====================================================================

    T.FullSweepID = ...
        repmat(fullSweepID,height(T),1);

    T.Stage2RegionID = ...
        repmat(regionID,height(T),1);

    T.StructuralRole = ...
        repmat("FULL_CENTRAL_SWEEP",height(T),1);

    T.Direction = ...
        repmat("POS_TO_NEG",height(T),1);

    T.QCPass = ...
        repmat(QCPass,height(T),1);

    T.ModelRouting = ...
        repmat(ModelRouting,height(T),1);

    T.SweepFZ_Mean_N = ...
        repmat(FZmean,height(T),1);

    T.SweepFZ_Median_N = ...
        repmat(FZmedian,height(T),1);

    T.SweepPressure_Mean_psi = ...
        repmat(Pmean_psi,height(T),1);

    T.SweepIA_Mean_deg = ...
        repmat(IAmean,height(T),1);

    T.SweepSpeed_Mean_mph = ...
        repmat(Vmean_mph,height(T),1);


    AllFullSweepData = ...
        [AllFullSweepData; T]; %#ok<AGROW>


    %% ====================================================================
    % ROUTE ACCEPTED / REJECTED
    % =====================================================================

    if QCPass

        AcceptedSweepManifest = ...
            [AcceptedSweepManifest; manifestRow]; %#ok<AGROW>

        if ModelRouting == "PRIMARY_MODEL_FIT"

            CleanLateralDatabase = ...
                [CleanLateralDatabase; T]; %#ok<AGROW>

        elseif ModelRouting == "VALIDATION_SPEED_DATA"

            ValidationSpeedDatabase = ...
                [ValidationSpeedDatabase; T]; %#ok<AGROW>

        end

    else

        RejectedSweepManifest = ...
            [RejectedSweepManifest; manifestRow]; %#ok<AGROW>

    end


    fprintf( ...
        'FULL SWEEP | %4d samples | %s\n', ...
        sampleCount, ...
        ModelRouting);

end

fprintf('\n');


%% ========================================================================
% [7] STRUCTURAL EXTRACTION CONTRACT
% =========================================================================

fprintf('[7] STRUCTURAL EXTRACTION CONTRACT\n');
fprintf('──────────────────────────────────────────────────────────────\n');

fprintf('Stage-2 regions              : %d\n', ...
    numel(regionIDs));

fprintf('Positive peak failures       : %d\n', ...
    positivePeakFailures);

fprintf('Negative peak failures       : %d\n', ...
    negativePeakFailures);

fprintf('Peak-order failures          : %d\n', ...
    peakOrderFailures);

fprintf('Central-span failures        : %d\n', ...
    centralSpanFailures);

fprintf('Full central sweeps          : %d\n', ...
    height(FullSweepManifest));

fprintf('Structural legs preserved    : %d\n', ...
    height(StructuralLegManifest));

fprintf('\n');

structuralContractPass = ...
    positivePeakFailures == 0 && ...
    negativePeakFailures == 0 && ...
    peakOrderFailures == 0 && ...
    centralSpanFailures == 0 && ...
    height(FullSweepManifest) == numel(regionIDs);

if structuralContractPass

    fprintf('STRUCTURAL CONTRACT : PASS\n');

else

    fprintf('STRUCTURAL CONTRACT : FAIL\n');

end

fprintf('\n');


%% ========================================================================
% [8] QUALITY CONTROL SUMMARY
% =========================================================================

fprintf('[8] QUALITY CONTROL SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');

fprintf('Full sweeps evaluated : %d\n', ...
    height(FullSweepManifest));

fprintf('QC accepted           : %d\n', ...
    height(AcceptedSweepManifest));

fprintf('QC rejected           : %d\n', ...
    height(RejectedSweepManifest));

if ~isempty(FullSweepManifest)

    acceptanceRate = ...
        100 * ...
        height(AcceptedSweepManifest) / ...
        height(FullSweepManifest);

else

    acceptanceRate = 0;

end

fprintf('Acceptance rate       : %.1f %%\n\n', ...
    acceptanceRate);


%% ========================================================================
% [9] QC FAILURE BREAKDOWN
% =========================================================================

fprintf('[9] QC FAILURE BREAKDOWN\n');
fprintf('──────────────────────────────────────────────────────────────\n');

qcNames = [ ...
    "QC_SampleCount", ...
    "QC_Duration", ...
    "QC_SACoverage", ...
    "QC_FYRange", ...
    "QC_Monotonicity", ...
    "QC_Pressure", ...
    "QC_IA", ...
    "QC_Speed", ...
    "QC_FreeRolling", ...
    "QC_FZ"];

qcLabels = [ ...
    "LOW SAMPLE COUNT", ...
    "SHORT DURATION", ...
    "INSUFFICIENT SA RANGE", ...
    "INSUFFICIENT FY RANGE", ...
    "LOW MONOTONICITY", ...
    "PRESSURE INSTABILITY", ...
    "IA INSTABILITY", ...
    "SPEED INSTABILITY", ...
    "FREE-ROLLING FAILURE", ...
    "FZ INSTABILITY"];

QCFailureCount = zeros( ...
    numel(qcNames),1);

for i = 1:numel(qcNames)

    if isempty(FullSweepManifest)

        QCFailureCount(i) = 0;

    else

        QCFailureCount(i) = ...
            sum(~FullSweepManifest.(qcNames(i)));

    end

    fprintf('%-26s : %d\n', ...
        qcLabels(i), ...
        QCFailureCount(i));

end

QCSummary = table( ...
    qcLabels(:), ...
    QCFailureCount, ...
    'VariableNames',{ ...
    'QualityCheck', ...
    'FailureCount'});

fprintf('\n');


%% ========================================================================
% [10] MODEL ROUTING SUMMARY
% =========================================================================

fprintf('[10] MODEL ROUTING SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');

primaryCount = sum( ...
    FullSweepManifest.ModelRouting == ...
    "PRIMARY_MODEL_FIT");

validationCount = sum( ...
    FullSweepManifest.ModelRouting == ...
    "VALIDATION_SPEED_DATA");

rejectedCount = sum( ...
    FullSweepManifest.ModelRouting == ...
    "REJECTED_QC");

fprintf('PRIMARY_MODEL_FIT      : %d\n',primaryCount);
fprintf('VALIDATION_SPEED_DATA  : %d\n',validationCount);
fprintf('REJECTED_QC            : %d\n',rejectedCount);

fprintf('\n');


%% ========================================================================
% [11] RUN SUMMARY
% =========================================================================

fprintf('[11] RUN SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');

runList = unique( ...
    FullSweepManifest.RunNumber);

RunSummary = table();

for i = 1:numel(runList)

    runNumber = runList(i);

    runMask = ...
        FullSweepManifest.RunNumber == runNumber;

    totalRun = sum(runMask);

    acceptedRun = sum( ...
        runMask & ...
        FullSweepManifest.QCPass);

    primaryRun = sum( ...
        runMask & ...
        FullSweepManifest.ModelRouting == ...
        "PRIMARY_MODEL_FIT");

    validationRun = sum( ...
        runMask & ...
        FullSweepManifest.ModelRouting == ...
        "VALIDATION_SPEED_DATA");

    rejectedRun = sum( ...
        runMask & ...
        ~FullSweepManifest.QCPass);

    row = table( ...
        runNumber, ...
        totalRun, ...
        acceptedRun, ...
        primaryRun, ...
        validationRun, ...
        rejectedRun, ...
        'VariableNames',{ ...
        'RunNumber', ...
        'FullSweeps', ...
        'AcceptedSweeps', ...
        'PrimaryModelSweeps', ...
        'ValidationSweeps', ...
        'RejectedSweeps'});

    RunSummary = ...
        [RunSummary; row]; %#ok<AGROW>

end

disp(RunSummary);

fprintf('\n');


%% ========================================================================
% [12] MEASURED OPERATING CONDITION SUMMARY
% =========================================================================

fprintf('[12] MEASURED OPERATING CONDITION SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');

PrimaryManifest = FullSweepManifest( ...
    FullSweepManifest.ModelRouting == ...
    "PRIMARY_MODEL_FIT",:);

ConditionSummary = table();

if isempty(PrimaryManifest)

    fprintf('No sweeps routed to primary model.\n');

else

    PressureGroup_psi = ...
        round(PrimaryManifest.P_Mean_psi);

    IAGroup_deg = ...
        round(PrimaryManifest.IA_Mean_deg);

    % 50-N bins are REPORTING ONLY.
    % Actual FZ values remain preserved.
    FZGroup_N = ...
        round( ...
        PrimaryManifest.FZ_Median_N / 50) * 50;

    [G, ...
        PGroup, ...
        FGroup, ...
        IAGroup] = findgroups( ...
        PressureGroup_psi, ...
        FZGroup_N, ...
        IAGroup_deg);

    SweepCount = splitapply( ...
        @numel, ...
        PrimaryManifest.FullSweepID, ...
        G);

    MeanMeasuredFZ = splitapply( ...
        @mean, ...
        PrimaryManifest.FZ_Median_N, ...
        G);

    ConditionSummary = table( ...
        PGroup, ...
        FGroup, ...
        IAGroup, ...
        SweepCount, ...
        MeanMeasuredFZ, ...
        'VariableNames',{ ...
        'Pressure_psi', ...
        'FZ_ReportBin_N', ...
        'IA_deg', ...
        'SweepCount', ...
        'MeanMeasuredFZ_N'});

    ConditionSummary = sortrows( ...
        ConditionSummary, ...
        {'Pressure_psi','IA_deg','FZ_ReportBin_N'});

    disp(ConditionSummary);

end

fprintf('\n');


%% ========================================================================
% [13] SAVE TABLE OUTPUTS
% =========================================================================

fprintf('[13] SAVING DATABASE OUTPUTS\n');
fprintf('──────────────────────────────────────────────────────────────\n');

structuralManifestCSV = fullfile( ...
    outputFolder, ...
    'CMM_STRUCTURAL_LEG_MANIFEST_v3_2.csv');

fullManifestCSV = fullfile( ...
    outputFolder, ...
    'CMM_FULL_SWEEP_MANIFEST_v3_2.csv');

acceptedManifestCSV = fullfile( ...
    outputFolder, ...
    'CMM_ACCEPTED_SWEEP_MANIFEST_v3_2.csv');

rejectedManifestCSV = fullfile( ...
    outputFolder, ...
    'CMM_REJECTED_SWEEP_MANIFEST_v3_2.csv');

cleanDatabaseCSV = fullfile( ...
    outputFolder, ...
    'CMM_CLEAN_LATERAL_DATABASE_v3_2.csv');

validationDatabaseCSV = fullfile( ...
    outputFolder, ...
    'CMM_SPEED_VALIDATION_DATABASE_v3_2.csv');

allFullSweepCSV = fullfile( ...
    outputFolder, ...
    'CMM_ALL_FULL_SWEEP_DATA_v3_2.csv');

qcSummaryCSV = fullfile( ...
    outputFolder, ...
    'CMM_SWEEP_QC_SUMMARY_v3_2.csv');

runSummaryCSV = fullfile( ...
    outputFolder, ...
    'CMM_RUN_SUMMARY_v3_2.csv');

conditionSummaryCSV = fullfile( ...
    outputFolder, ...
    'CMM_PRIMARY_CONDITION_SUMMARY_v3_2.csv');


writetable( ...
    StructuralLegManifest, ...
    structuralManifestCSV);

writetable( ...
    FullSweepManifest, ...
    fullManifestCSV);

writetable( ...
    AcceptedSweepManifest, ...
    acceptedManifestCSV);

writetable( ...
    RejectedSweepManifest, ...
    rejectedManifestCSV);

writetable( ...
    CleanLateralDatabase, ...
    cleanDatabaseCSV);

writetable( ...
    ValidationSpeedDatabase, ...
    validationDatabaseCSV);

writetable( ...
    AllFullSweepData, ...
    allFullSweepCSV);

writetable( ...
    QCSummary, ...
    qcSummaryCSV);

writetable( ...
    RunSummary, ...
    runSummaryCSV);

if ~isempty(ConditionSummary)

    writetable( ...
        ConditionSummary, ...
        conditionSummaryCSV);

end

fprintf('Structural leg manifest saved.\n');
fprintf('Full sweep manifest saved.\n');
fprintf('Accepted/rejected manifests saved.\n');
fprintf('Primary lateral database saved.\n');
fprintf('Speed-validation database saved.\n\n');


%% ========================================================================
% [14] SAVE MAT CONTRACT
% =========================================================================

fprintf('[14] SAVING MAT CONTRACT\n');
fprintf('──────────────────────────────────────────────────────────────\n');

matContractPath = fullfile( ...
    outputFolder, ...
    'CMM_SWEEP_EXTRACTOR_CONTRACT_v3_2.mat');

SweepExtractorContract = struct();

SweepExtractorContract.Version = ...
    CFG.Version;

SweepExtractorContract.Pipeline = ...
    CFG.Pipeline;

SweepExtractorContract.ModelName = ...
    CFG.ModelName;

SweepExtractorContract.Configuration = ...
    CFG;

SweepExtractorContract.SourceStage2Contract = ...
    contractPath;

SweepExtractorContract.StructuralLegManifest = ...
    StructuralLegManifest;

SweepExtractorContract.FullSweepManifest = ...
    FullSweepManifest;

SweepExtractorContract.AcceptedSweepManifest = ...
    AcceptedSweepManifest;

SweepExtractorContract.RejectedSweepManifest = ...
    RejectedSweepManifest;

SweepExtractorContract.AllStructuralLegData = ...
    AllStructuralLegData;

SweepExtractorContract.AllFullSweepData = ...
    AllFullSweepData;

SweepExtractorContract.CleanLateralDatabase = ...
    CleanLateralDatabase;

SweepExtractorContract.ValidationSpeedDatabase = ...
    ValidationSpeedDatabase;

SweepExtractorContract.QCSummary = ...
    QCSummary;

SweepExtractorContract.RunSummary = ...
    RunSummary;

SweepExtractorContract.ConditionSummary = ...
    ConditionSummary;

SweepExtractorContract.StructuralContractPass = ...
    structuralContractPass;

save( ...
    matContractPath, ...
    'SweepExtractorContract', ...
    '-v7.3');

fprintf('MAT contract saved:\n%s\n\n', ...
    matContractPath);


%% ========================================================================
% [15] GENERATE BLACK-BACKGROUND DIAGNOSTIC FIGURES
% =========================================================================

fprintf('[15] GENERATING BLACK-BACKGROUND DIAGNOSTIC FIGURES\n');
fprintf('──────────────────────────────────────────────────────────────\n');

if ~isempty(AllFullSweepData)

    runList = unique( ...
        AllFullSweepData.RunNumber);

    for rr = 1:numel(runList)

        runNumber = runList(rr);

        runMask = ...
            AllFullSweepData.RunNumber == runNumber;

        D = AllFullSweepData(runMask,:);


        %% ----------------------------------------------------------------
        % FIGURE A — ALL CENTRAL SWEEPS
        % -----------------------------------------------------------------

        fig = figure( ...
            'Color',CFG.FigureBackground, ...
            'InvertHardcopy','off', ...
            'Visible','off');

        ax = axes(fig);

        applyDarkAxes(ax,CFG);

        hold(ax,'on');

        sweepIDs = unique(D.FullSweepID);

        for ss = 1:numel(sweepIDs)

            sid = sweepIDs(ss);

            m = D.FullSweepID == sid;

            plot( ...
                ax, ...
                D.SA_deg(m), ...
                D.FY_N(m), ...
                'LineWidth',0.8);

        end

        xlabel( ...
            ax, ...
            'Slip Angle SA [deg]', ...
            'Color',CFG.Foreground);

        ylabel( ...
            ax, ...
            'Lateral Force FY [N]', ...
            'Color',CFG.Foreground);

        title( ...
            ax, ...
            sprintf( ...
            'Run %d — Full Central Sweeps', ...
            runNumber), ...
            'Color',CFG.Foreground);

        figurePath = fullfile( ...
            figureFolder, ...
            sprintf( ...
            'RUN_%d_FULL_CENTRAL_SWEEPS_v3_2.png', ...
            runNumber));

        exportgraphics( ...
            fig, ...
            figurePath, ...
            'Resolution',220, ...
            'BackgroundColor',CFG.FigureBackground);

        close(fig);


        %% ----------------------------------------------------------------
        % FIGURE B — PRIMARY MODEL SWEEPS
        % -----------------------------------------------------------------

        primaryMask = ...
            D.ModelRouting == "PRIMARY_MODEL_FIT";

        if any(primaryMask)

            DP = D(primaryMask,:);

            fig = figure( ...
                'Color',CFG.FigureBackground, ...
                'InvertHardcopy','off', ...
                'Visible','off');

            ax = axes(fig);

            applyDarkAxes(ax,CFG);

            hold(ax,'on');

            sweepIDs = unique(DP.FullSweepID);

            for ss = 1:numel(sweepIDs)

                sid = sweepIDs(ss);

                m = DP.FullSweepID == sid;

                plot( ...
                    ax, ...
                    DP.SA_deg(m), ...
                    DP.FY_N(m), ...
                    'LineWidth',0.8);

            end

            xlabel( ...
                ax, ...
                'Slip Angle SA [deg]', ...
                'Color',CFG.Foreground);

            ylabel( ...
                ax, ...
                'Lateral Force FY [N]', ...
                'Color',CFG.Foreground);

            title( ...
                ax, ...
                sprintf( ...
                'Run %d — Primary Model Sweeps', ...
                runNumber), ...
                'Color',CFG.Foreground);

            figurePath = fullfile( ...
                figureFolder, ...
                sprintf( ...
                'RUN_%d_PRIMARY_MODEL_SWEEPS_v3_2.png', ...
                runNumber));

            exportgraphics( ...
                fig, ...
                figurePath, ...
                'Resolution',220, ...
                'BackgroundColor',CFG.FigureBackground);

            close(fig);

        end


        %% ----------------------------------------------------------------
        % FIGURE C — SA vs TIME STRUCTURAL EXAMPLE
        % -----------------------------------------------------------------

        runManifest = FullSweepManifest( ...
            FullSweepManifest.RunNumber == runNumber,:);

        if ~isempty(runManifest)

            exampleRegion = ...
                runManifest.Stage2RegionID(1);

            regionMask = ...
                SegmentedData.SweepID == exampleRegion;

            RE = SegmentedData(regionMask,:);

            RE = sortrows(RE,'ET_s');

            SAexample = RE.SA_deg;

            SAsmooth = movmean( ...
                SAexample, ...
                CFG.SASmoothingWindow_samples, ...
                'omitnan');

            [~,iPos] = max(SAsmooth);
            [~,iNeg] = min(SAsmooth);

            fig = figure( ...
                'Color',CFG.FigureBackground, ...
                'InvertHardcopy','off', ...
                'Visible','off');

            ax = axes(fig);

            applyDarkAxes(ax,CFG);

            hold(ax,'on');

            plot( ...
                ax, ...
                RE.ET_s, ...
                RE.SA_deg, ...
                'LineWidth',0.8);

            plot( ...
                ax, ...
                RE.ET_s, ...
                SAsmooth, ...
                'LineWidth',1.4);

            plot( ...
                ax, ...
                RE.ET_s(iPos), ...
                SAsmooth(iPos), ...
                'o', ...
                'MarkerSize',8, ...
                'LineWidth',1.5);

            plot( ...
                ax, ...
                RE.ET_s(iNeg), ...
                SAsmooth(iNeg), ...
                'o', ...
                'MarkerSize',8, ...
                'LineWidth',1.5);

            xline( ...
                ax, ...
                RE.ET_s(iPos), ...
                '--', ...
                'Color',CFG.Foreground);

            xline( ...
                ax, ...
                RE.ET_s(iNeg), ...
                '--', ...
                'Color',CFG.Foreground);

            xlabel( ...
                ax, ...
                'Elapsed Time ET [s]', ...
                'Color',CFG.Foreground);

            ylabel( ...
                ax, ...
                'Slip Angle SA [deg]', ...
                'Color',CFG.Foreground);

            title( ...
                ax, ...
                sprintf( ...
                'Run %d — Region %d Structural Extraction', ...
                runNumber, ...
                exampleRegion), ...
                'Color',CFG.Foreground);

            legend( ...
                ax, ...
                { ...
                'Raw SA', ...
                'Smoothed SA', ...
                'Positive turning point', ...
                'Negative turning point'}, ...
                'TextColor',CFG.Foreground, ...
                'Color',CFG.AxesBackground, ...
                'EdgeColor',CFG.GridColor, ...
                'Location','best');

            figurePath = fullfile( ...
                figureFolder, ...
                sprintf( ...
                'RUN_%d_STRUCTURAL_EXTRACTION_EXAMPLE_v3_2.png', ...
                runNumber));

            exportgraphics( ...
                fig, ...
                figurePath, ...
                'Resolution',220, ...
                'BackgroundColor',CFG.FigureBackground);

            close(fig);

        end

    end

end

fprintf('Dark-theme diagnostic figures generated.\n\n');


%% ========================================================================
% [16] DATABASE INTEGRITY CHECK
% =========================================================================

fprintf('[16] DATABASE INTEGRITY CHECK\n');
fprintf('──────────────────────────────────────────────────────────────\n');

integrityPass = true;


%% ------------------------------------------------------------------------
% Unique FullSweepID
% -------------------------------------------------------------------------

if height(FullSweepManifest) ~= ...
        numel(unique(FullSweepManifest.FullSweepID))

    fprintf('Unique FullSweepID          : FAIL\n');

    integrityPass = false;

else

    fprintf('Unique FullSweepID          : PASS\n');

end


%% ------------------------------------------------------------------------
% One full sweep per Stage-2 region
% -------------------------------------------------------------------------

if height(FullSweepManifest) ~= numel(regionIDs)

    fprintf('1 sweep / Stage-2 region    : FAIL\n');

    integrityPass = false;

else

    representedRegions = ...
        unique(FullSweepManifest.Stage2RegionID);

    if numel(representedRegions) == numel(regionIDs)

        fprintf('1 sweep / Stage-2 region    : PASS\n');

    else

        fprintf('1 sweep / Stage-2 region    : FAIL\n');

        integrityPass = false;

    end

end


%% ------------------------------------------------------------------------
% Structural contract
% -------------------------------------------------------------------------

if structuralContractPass

    fprintf('Structural extraction       : PASS\n');

else

    fprintf('Structural extraction       : FAIL\n');

    integrityPass = false;

end


%% ------------------------------------------------------------------------
% Clean database contains only QC PASS
% -------------------------------------------------------------------------

if ~isempty(CleanLateralDatabase) && ...
        any(~CleanLateralDatabase.QCPass)

    fprintf('Clean database QC           : FAIL\n');

    integrityPass = false;

else

    fprintf('Clean database QC           : PASS\n');

end


%% ------------------------------------------------------------------------
% Clean database routing
% -------------------------------------------------------------------------

if ~isempty(CleanLateralDatabase) && ...
        any( ...
        CleanLateralDatabase.ModelRouting ~= ...
        "PRIMARY_MODEL_FIT")

    fprintf('Primary model routing       : FAIL\n');

    integrityPass = false;

else

    fprintf('Primary model routing       : PASS\n');

end


%% ------------------------------------------------------------------------
% Speed validation routing
% -------------------------------------------------------------------------

if ~isempty(ValidationSpeedDatabase) && ...
        any( ...
        ValidationSpeedDatabase.ModelRouting ~= ...
        "VALIDATION_SPEED_DATA")

    fprintf('Speed validation routing    : FAIL\n');

    integrityPass = false;

else

    fprintf('Speed validation routing    : PASS\n');

end


%% ------------------------------------------------------------------------
% Allowed runs
% -------------------------------------------------------------------------

allRuns = unique( ...
    FullSweepManifest.RunNumber);

if any(~ismember(allRuns,CFG.AllowedRuns))

    fprintf('7-inch run contract         : FAIL\n');

    integrityPass = false;

else

    fprintf('7-inch run contract         : PASS\n');

end


%% ------------------------------------------------------------------------
% Direction contract
% -------------------------------------------------------------------------

if any( ...
        FullSweepManifest.Direction ~= ...
        "POS_TO_NEG")

    fprintf('Central sweep direction     : FAIL\n');

    integrityPass = false;

else

    fprintf('Central sweep direction     : PASS\n');

end


fprintf('\n');

if integrityPass

    fprintf('OVERALL DATABASE INTEGRITY  : PASS\n');

else

    fprintf('OVERALL DATABASE INTEGRITY  : FAIL\n');

end

fprintf('\n');


%% ========================================================================
% [17] WRITE TEXT REPORT
% =========================================================================

fprintf('[17] WRITING STAGE-3 REPORT\n');
fprintf('──────────────────────────────────────────────────────────────\n');

reportPath = fullfile( ...
    outputFolder, ...
    'CMM_SWEEP_EXTRACTOR_REPORT_v3_2.txt');

fid = fopen(reportPath,'w');

if fid == -1

    warning( ...
        'CMM:ReportWriteFailure', ...
        'Could not create Stage-3 text report.');

else

    fprintf(fid, ...
        'CMM TTC SWEEP EXTRACTOR + QUALITY FILTER v3.2\n');

    fprintf(fid, ...
        '============================================================\n\n');

    fprintf(fid, ...
        'Pipeline: %s\n',CFG.Pipeline);

    fprintf(fid, ...
        'Model: %s\n\n',CFG.ModelName);

    fprintf(fid, ...
        'Stage-2 regions: %d\n', ...
        numel(regionIDs));

    fprintf(fid, ...
        'Full central sweeps: %d\n', ...
        height(FullSweepManifest));

    fprintf(fid, ...
        'Structural legs preserved: %d\n', ...
        height(StructuralLegManifest));

    fprintf(fid, ...
        'QC accepted: %d\n', ...
        height(AcceptedSweepManifest));

    fprintf(fid, ...
        'QC rejected: %d\n', ...
        height(RejectedSweepManifest));

    fprintf(fid, ...
        'Primary model sweeps: %d\n', ...
        primaryCount);

    fprintf(fid, ...
        'Speed validation sweeps: %d\n', ...
        validationCount);

    fprintf(fid, ...
        'Primary model samples: %d\n', ...
        height(CleanLateralDatabase));

    fprintf(fid, ...
        'Speed validation samples: %d\n\n', ...
        height(ValidationSpeedDatabase));

    fprintf(fid, ...
        'Positive peak failures: %d\n', ...
        positivePeakFailures);

    fprintf(fid, ...
        'Negative peak failures: %d\n', ...
        negativePeakFailures);

    fprintf(fid, ...
        'Peak-order failures: %d\n', ...
        peakOrderFailures);

    fprintf(fid, ...
        'Central-span failures: %d\n\n', ...
        centralSpanFailures);

    fprintf(fid, ...
        'Structural contract: %s\n', ...
        passFailString(structuralContractPass));

    fprintf(fid, ...
        'Database integrity: %s\n', ...
        passFailString(integrityPass));

    fclose(fid);

end

fprintf('Report saved:\n%s\n\n',reportPath);


%% ========================================================================
% [18] FINAL SUMMARY
% =========================================================================

fprintf('[18] FINAL SUMMARY\n');
fprintf('──────────────────────────────────────────────────────────────\n');

fprintf('Pipeline                    : %s\n', ...
    CFG.Pipeline);

fprintf('Model                       : %s\n', ...
    CFG.ModelName);

fprintf('Stage-2 regions             : %d\n', ...
    numel(regionIDs));

fprintf('Structural legs preserved  : %d\n', ...
    height(StructuralLegManifest));

fprintf('Full central sweeps        : %d\n', ...
    height(FullSweepManifest));

fprintf('QC accepted sweeps         : %d\n', ...
    height(AcceptedSweepManifest));

fprintf('QC rejected sweeps         : %d\n', ...
    height(RejectedSweepManifest));

fprintf('Primary model sweeps       : %d\n', ...
    primaryCount);

fprintf('Speed validation sweeps    : %d\n', ...
    validationCount);

fprintf('Primary model samples      : %d\n', ...
    height(CleanLateralDatabase));

fprintf('Validation samples         : %d\n', ...
    height(ValidationSpeedDatabase));

fprintf('Structural contract        : %s\n', ...
    passFailString(structuralContractPass));

fprintf('Database integrity         : %s\n', ...
    passFailString(integrityPass));

fprintf('\n');

fprintf('Output root:\n%s\n\n',outputRoot);

fprintf('Stage output:\n%s\n\n',outputFolder);

fprintf('╔══════════════════════════════════════════════════════════════╗\n');
fprintf('║       SWEEP EXTRACTION + QUALITY FILTERING COMPLETE        ║\n');
fprintf('╚══════════════════════════════════════════════════════════════╝\n\n');


if structuralContractPass && integrityPass

    fprintf('STAGE 3 STATUS:\n');
    fprintf('PASS — production extraction contract satisfied.\n\n');

    fprintf('PRIMARY MODEL DATABASE:\n');
    fprintf('QC-passed 25 mph full central sweeps only.\n\n');

    fprintf('VALIDATION DATABASE:\n');
    fprintf('QC-passed non-25-mph speed sweeps preserved separately.\n\n');

    fprintf('TRACEABILITY DATABASE:\n');
    fprintf('Entry, raw-central and exit structural legs preserved.\n\n');

    fprintf('NEXT PIPELINE STAGE:\n');
    fprintf('CMM LATERAL TIRE CHARACTERIZER v4.0\n\n');

else

    fprintf('STAGE 3 STATUS:\n');
    fprintf('HOLD — extraction/integrity contract failed.\n\n');

    fprintf('DO NOT PROCEED TO MODEL FITTING.\n\n');

end


%% ========================================================================
% LOCAL FUNCTION — STRUCTURAL LEG MANIFEST
% =========================================================================

function row = createStructuralLegRow( ...
    structuralLegID, ...
    regionID, ...
    runNumber, ...
    sweepType, ...
    legType, ...
    T)

    row = table( ...
        structuralLegID, ...
        regionID, ...
        runNumber, ...
        string(sweepType), ...
        string(legType), ...
        height(T), ...
        T.ET_s(1), ...
        T.ET_s(end), ...
        T.ET_s(end)-T.ET_s(1), ...
        T.SA_deg(1), ...
        T.SA_deg(end), ...
        min(T.SA_deg), ...
        max(T.SA_deg), ...
        max(T.SA_deg)-min(T.SA_deg), ...
        mean(T.FZ_Load_N,'omitnan'), ...
        median(T.FZ_Load_N,'omitnan'), ...
        mean(T.P_kPa,'omitnan'), ...
        mean(T.IA_deg,'omitnan'), ...
        mean(abs(T.V_kph),'omitnan'), ...
        'VariableNames',{ ...
        'StructuralLegID', ...
        'Stage2RegionID', ...
        'RunNumber', ...
        'Stage2SweepType', ...
        'LegType', ...
        'SampleCount', ...
        'StartTime_s', ...
        'EndTime_s', ...
        'Duration_s', ...
        'SA_Start_deg', ...
        'SA_End_deg', ...
        'SA_Min_deg', ...
        'SA_Max_deg', ...
        'SA_Range_deg', ...
        'FZ_Mean_N', ...
        'FZ_Median_N', ...
        'P_Mean_kPa', ...
        'IA_Mean_deg', ...
        'V_Mean_kph'});

end


%% ========================================================================
% LOCAL FUNCTION — LARGEST CONTIGUOUS BLOCK
% =========================================================================

function idx = largestContiguousBlock(idx)

    idx = idx(:);

    if isempty(idx)
        return;
    end

    if numel(idx) == 1
        return;
    end

    breaks = find( ...
        diff(idx) > 1);

    starts = [ ...
        1; ...
        breaks+1];

    ends = [ ...
        breaks; ...
        numel(idx)];

    lengths = ...
        ends-starts+1;

    [~,largestBlock] = ...
        max(lengths);

    idx = idx( ...
        starts(largestBlock): ...
        ends(largestBlock));

end


%% ========================================================================
% LOCAL FUNCTION — DARK AXES
% =========================================================================

function applyDarkAxes(ax,CFG)

    set( ...
        ax, ...
        'Color',CFG.AxesBackground, ...
        'XColor',CFG.Foreground, ...
        'YColor',CFG.Foreground, ...
        'GridColor',CFG.GridColor, ...
        'MinorGridColor',CFG.MinorGridColor, ...
        'GridAlpha',0.45, ...
        'MinorGridAlpha',0.30, ...
        'Box','on', ...
        'Layer','top');

    grid(ax,'on');

    disableDefaultInteractivity(ax);

end


%% ========================================================================
% LOCAL FUNCTION — PASS / FAIL STRING
% =========================================================================

function output = passFailString(value)

    if value
        output = 'PASS';
    else
        output = 'FAIL';
    end

end