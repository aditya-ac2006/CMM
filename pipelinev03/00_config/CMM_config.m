function CFG = CMM_config()
% ================================================================
% CMM PIPELINE v03 MASTER CONFIGURATION
%
% Purpose:
%   Central configuration for the CMM tire-modeling engine.
%
% ================================================================

%% PATHS

CFG.PATHS = CMM_paths();


%% ---------------------------------------------------------------
% DATA CONTRACT
% ---------------------------------------------------------------

CFG.Data = struct();

% Current model uses the canonical Stage-4 database.
CFG.Data.DatabaseVersion = 'v4.0';

% Only these runs may enter the current 7-inch model branch.
CFG.Data.ModelRuns = [2 4];

% Run 2 = development / fitting
CFG.Data.DevelopmentRuns = 2;

% Run 4 = independent holdout
CFG.Data.HoldoutRuns = 4;

% Explicitly excluded from current model.
CFG.Data.ExcludedRuns = [5 6 7];


%% ---------------------------------------------------------------
% TIRE / RIM
% ---------------------------------------------------------------

CFG.Tire = struct();

CFG.Tire.RimDiameter_in = 7;

CFG.Tire.ModelName = 'CMM_7IN_LATERAL';


%% ---------------------------------------------------------------
% OPERATING CONDITION GRID
% ---------------------------------------------------------------

CFG.Conditions = struct();

% These are the nominal condition states represented in the
% canonical CMM database.

CFG.Conditions.Pressure_psi = [8 10 12 14];

CFG.Conditions.Camber_deg = [0 2 4];

% Load states will be read from the canonical condition manifest
% rather than hard-coded here.


%% ---------------------------------------------------------------
% SLIP-ANGLE CHARACTERIZATION
% ---------------------------------------------------------------

CFG.SlipAngle = struct();

% Used for initial cornering-stiffness estimation.
CFG.SlipAngle.LinearRegion_deg = 1.0;

% Main measured region.
CFG.SlipAngle.ExpectedMin_deg = -10.5;
CFG.SlipAngle.ExpectedMax_deg = 10.5;


%% ---------------------------------------------------------------
% LOCAL FITTING
% ---------------------------------------------------------------

CFG.LocalFit = struct();

% Minimum number of samples in a condition before attempting a
% local fit. This is intentionally conservative and will later
% be supplemented with slip-angle coverage checks.

CFG.LocalFit.MinSamples = 50;

% Require both sides of the slip-angle sweep.
CFG.LocalFit.RequireNegativeAlpha = true;
CFG.LocalFit.RequirePositiveAlpha = true;

% Number of optimization starts.
%
% We will NOT blindly use one optimizer start.
% This is one of the major upgrades in pipelinev03.

CFG.LocalFit.NumStarts = 20;


%% ---------------------------------------------------------------
% EXTREME CHARACTERIZATION
% ---------------------------------------------------------------

CFG.Extremes = struct();

% Fraction of the peak used for saturation characterization.

CFG.Extremes.SaturationFraction = 0.90;

% Fraction of peak used for post-peak analysis.

CFG.Extremes.PostPeakFraction = 0.95;


%% ---------------------------------------------------------------
% MODEL OBJECTIVE
% ---------------------------------------------------------------

CFG.Objective = struct();

% These will eventually control multi-objective model selection.

CFG.Objective.UseRMSE = true;
CFG.Objective.UsePeakForce = true;
CFG.Objective.UsePeakSlipAngle = true;
CFG.Objective.UseCorneringStiffness = true;
CFG.Objective.UseSaturation = true;
CFG.Objective.UsePostPeak = true;
CFG.Objective.UseExtremeConditions = true;


%% ---------------------------------------------------------------
% MODEL PHYSICS
% ---------------------------------------------------------------

CFG.Physics = struct();

% Degrees are used in the data layer.
% Radians are used internally by the mathematical model.

CFG.Physics.InputSlipAngleUnits = 'deg';

CFG.Physics.InternalSlipAngleUnits = 'rad';

% Normal force must be positive.
CFG.Physics.RequirePositiveFz = true;

% Peak friction coefficient must be finite.
CFG.Physics.RequireFiniteMu = true;


%% ---------------------------------------------------------------
% GLOBAL MODEL
% ---------------------------------------------------------------

CFG.GlobalFit = struct();

CFG.GlobalFit.NumStarts = 50;

CFG.GlobalFit.UseLocalInitialization = true;

CFG.GlobalFit.UsePhysicalConstraints = true;

CFG.GlobalFit.UseBehavioralConstraints = true;


%% ---------------------------------------------------------------
% VALIDATION
% ---------------------------------------------------------------

CFG.Validation = struct();

CFG.Validation.CompareAgainstV02 = true;

CFG.Validation.UseHoldout = true;

CFG.Validation.HoldoutRun = 4;

CFG.Validation.EvaluateExtremes = true;


%% ---------------------------------------------------------------
% OUTPUT POLICY
% ---------------------------------------------------------------

CFG.Output = struct();

CFG.Output.SaveFigures = true;

CFG.Output.SaveTables = true;

CFG.Output.SaveMAT = true;

CFG.Output.OverwriteExisting = false;


%% ---------------------------------------------------------------
% VERSION
% ---------------------------------------------------------------

CFG.Version = struct();

CFG.Version.Pipeline = 'v03.0.0';

CFG.Version.Config = 'v03.0.0';

CFG.Version.Description = ...
    'CMM tire-modeling pipeline with hierarchical local-to-global identification';


%% ---------------------------------------------------------------
% SUMMARY
% ---------------------------------------------------------------

fprintf('\n');
fprintf('============================================================\n');
fprintf(' CMM PIPELINE v03 CONFIGURATION LOADED\n');
fprintf('============================================================\n');

fprintf('Model       : %s\n', CFG.Tire.ModelName);
fprintf('Rim         : %.0f inch\n', CFG.Tire.RimDiameter_in);

fprintf('Model runs  : [%s]\n', ...
    num2str(CFG.Data.ModelRuns));

fprintf('Development : Run %d\n', ...
    CFG.Data.DevelopmentRuns);

fprintf('Holdout     : Run %d\n', ...
    CFG.Data.HoldoutRuns);

fprintf('Local starts: %d\n', ...
    CFG.LocalFit.NumStarts);

fprintf('Global starts: %d\n', ...
    CFG.GlobalFit.NumStarts);

fprintf('============================================================\n');
fprintf('\n');

end