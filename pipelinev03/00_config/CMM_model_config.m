function MODEL = CMM_model_config()
% ================================================================
% CMM MODEL CONFIGURATION
% Pipeline v03
%
% PURPOSE
%   Define the mathematical structure and allowed behavior of the
%   CMM tire model.
%
% IMPORTANT
%   This file contains MODEL CONFIGURATION only.
%   It must not:
%       - load data
%       - fit parameters
%       - create outputs
%       - modify files
%       - run optimization
%
% ================================================================


%% ================================================================
% MODEL IDENTITY
% ================================================================

MODEL.Version = 'v03.0.0';

MODEL.Name = 'CMM_7IN_LATERAL_V03';

MODEL.TireType = '7-inch FSAE tire';

MODEL.ModelType = 'Magic Formula';


%% ================================================================
% LATERAL MODEL
% ================================================================

MODEL.Lateral = struct();


% ------------------------------------------------
% FORMULATION
% ------------------------------------------------

MODEL.Lateral.Formulation = 'CMM_MF_LATERAL';

MODEL.Lateral.Output = 'Fy';


% ------------------------------------------------
% INPUTS
% ------------------------------------------------

MODEL.Lateral.Inputs = { ...
    'alpha', ...
    'Fz', ...
    'camber', ...
    'pressure' ...
    };


% ------------------------------------------------
% PRIMARY PARAMETERS
% ------------------------------------------------

% These correspond to the current CMM lateral MF
% parameterization.
%
% They are listed explicitly so that parameter order
% never becomes ambiguous between scripts.

MODEL.Lateral.ParameterNames = { ...
    'PCY1', ...
    'PDY1', ...
    'PDY2', ...
    'PDY3', ...
    'PEY1', ...
    'PEY2', ...
    'PKY1', ...
    'PKY2', ...
    'PKY3', ...
    'PHY1', ...
    'PHY2', ...
    'PHY3', ...
    'PVY1', ...
    'PVY2', ...
    'PVY3', ...
    'PVY4', ...
    'P_MU1', ...
    'P_MU2', ...
    'P_K1' ...
    };


MODEL.Lateral.NumParameters = ...
    numel(MODEL.Lateral.ParameterNames);


%% ================================================================
% PARAMETER GROUPS
% ================================================================

MODEL.Lateral.ParameterGroups = struct();


MODEL.Lateral.ParameterGroups.Shape = { ...
    'PCY1', ...
    'PEY1', ...
    'PEY2' ...
    };


MODEL.Lateral.ParameterGroups.Friction = { ...
    'PDY1', ...
    'PDY2', ...
    'PDY3' ...
    };


MODEL.Lateral.ParameterGroups.CorneringStiffness = { ...
    'PKY1', ...
    'PKY2', ...
    'PKY3' ...
    };


MODEL.Lateral.ParameterGroups.HorizontalShift = { ...
    'PHY1', ...
    'PHY2', ...
    'PHY3' ...
    };


MODEL.Lateral.ParameterGroups.VerticalShift = { ...
    'PVY1', ...
    'PVY2', ...
    'PVY3', ...
    'PVY4' ...
    };


MODEL.Lateral.ParameterGroups.Pressure = { ...
    'P_MU1', ...
    'P_MU2', ...
    'P_K1' ...
    };


%% ================================================================
% OPERATING-CONDITION DEPENDENCIES
% ================================================================

% These switches allow us to test model complexity later without
% rewriting the MF equation.

MODEL.Lateral.Dependencies = struct();


MODEL.Lateral.Dependencies.Load = true;

MODEL.Lateral.Dependencies.Camber = true;

MODEL.Lateral.Dependencies.Pressure = true;


%% ================================================================
% LOCAL MODEL
% ================================================================

% Local fits characterize individual operating conditions before
% the global model is constructed.

MODEL.Local = struct();

MODEL.Local.Enabled = true;

MODEL.Local.FitParameters = { ...
    'C', ...
    'D', ...
    'E', ...
    'K', ...
    'H', ...
    'V' ...
    };


%% ================================================================
% RESPONSE SURFACES
% ================================================================

MODEL.Surfaces = struct();

MODEL.Surfaces.Enabled = true;


% Variables available to explain local parameter variation.

MODEL.Surfaces.Inputs = { ...
    'dFz', ...
    'dPressure', ...
    'camber' ...
    };


% Parameters that will initially be investigated.

MODEL.Surfaces.Targets = { ...
    'C', ...
    'D', ...
    'E', ...
    'K', ...
    'H', ...
    'V' ...
    };


%% ================================================================
% MODEL COMPLEXITY POLICY
% ================================================================

MODEL.Complexity = struct();


% Important principle:
%
% A parameter dependency should only be introduced when the
% experimental data demonstrates systematic variation.
%
% We do NOT automatically give every parameter dependence on
% every operating variable.

MODEL.Complexity.MinimumEvidenceRequired = true;

MODEL.Complexity.AllowAutomaticTermAddition = false;

MODEL.Complexity.PreferSimplerModel = true;


%% ================================================================
% PHYSICAL BEHAVIOR
% ================================================================

MODEL.Physics = struct();


% Normal force must remain positive.

MODEL.Physics.RequirePositiveFz = true;


% Lateral force must remain finite.

MODEL.Physics.RequireFiniteFy = true;


% Cornering stiffness should remain physically meaningful.

MODEL.Physics.RequirePositiveCorneringStiffness = true;


% Model should not generate NaN/Inf anywhere inside the
% validated operating domain.

MODEL.Physics.RequireFiniteDomainPrediction = true;


%% ================================================================
% VALIDATED OPERATING DOMAIN
% ================================================================

MODEL.Domain = struct();


% These are the current approximate measured limits.
%
% Exact limits will eventually be determined from the canonical
% database rather than assumed blindly.

MODEL.Domain.SlipAngle_deg = [-10.5 10.5];


% Nominal pressure states.

MODEL.Domain.Pressure_psi = [8 10 12 14];


% Nominal camber states.

MODEL.Domain.Camber_deg = [0 2 4];


% Load limits will be populated from the database.

MODEL.Domain.Fz_N = [];


%% ================================================================
% EXTREME-BEHAVIOR MODELING
% ================================================================

MODEL.Extremes = struct();


% Pipeline v03 explicitly evaluates the following features.

MODEL.Extremes.UsePeakForce = true;

MODEL.Extremes.UsePeakSlipAngle = true;

MODEL.Extremes.UseCorneringStiffness = true;

MODEL.Extremes.UseSaturation = true;

MODEL.Extremes.UsePostPeakBehavior = true;


% These are evaluation features rather than free parameters.

MODEL.Extremes.Features = { ...
    'Fy_peak', ...
    'alpha_peak', ...
    'mu_peak', ...
    'cornering_stiffness', ...
    'saturation_onset', ...
    'post_peak_slope' ...
    };


%% ================================================================
% MODEL COMPARISON
% ================================================================

MODEL.Comparison = struct();


% v02 remains the baseline/champion model.

MODEL.Comparison.CompareAgainstV02 = true;

MODEL.Comparison.V02IsReferenceOnly = true;

MODEL.Comparison.AllowV02Modification = false;


%% ================================================================
% VEHICLE MODEL INTERFACE
% ================================================================

MODEL.Interface = struct();


% Future standardized interface.

MODEL.Interface.Name = 'CMMTireModel';

MODEL.Interface.InputState = { ...
    'Fz', ...
    'alpha', ...
    'kappa', ...
    'camber', ...
    'pressure', ...
    'velocity' ...
    };


MODEL.Interface.Outputs = { ...
    'Fx', ...
    'Fy', ...
    'Mz' ...
    };


%% ================================================================
% SUMMARY
% ================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' CMM MODEL CONFIGURATION LOADED\n');
fprintf('============================================================\n');

fprintf('Model       : %s\n', MODEL.Name);
fprintf('Formulation : %s\n', MODEL.Lateral.Formulation);

fprintf('Parameters  : %d\n', ...
    MODEL.Lateral.NumParameters);

fprintf('Local fit   : %d\n', ...
    MODEL.Local.Enabled);

fprintf('Surfaces    : %d\n', ...
    MODEL.Surfaces.Enabled);

fprintf('Extreme     : %d\n', ...
    MODEL.Extremes.UsePeakForce);

fprintf('V02 compare : %d\n', ...
    MODEL.Comparison.CompareAgainstV02);

fprintf('============================================================\n');
fprintf('\n');

end