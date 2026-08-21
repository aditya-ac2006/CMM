function MF = CMM_TIRE_LATERAL_PARAMS_v1_0()
% ================================================================
% CMM TIRE LATERAL PARAMETERS v1.0
% FROZEN INTERFACE FOR THE CMM PURE-LATERAL MF MODEL
% ================================================================
%
% Purpose:
%   Provide one stable interface for the current CMM lateral MF model.
%
% IMPORTANT:
%   The fitted coefficient vector is NOT re-fit here.
%   It is loaded from the output MAT file produced by:
%
%       CMM_MF_LATERAL_GLOBAL_v1_5_ROBUST.m
%
%   Expected file:
%       CMM_GLOBAL_MF_LATERAL_v1_5.mat
%
% This keeps the fitted result separate from the fitting algorithm.
%
% Reference condition:
%   Fz0 = 871.5 N
%   P0  = 12.10 psi
%   IA0 = 0 deg
%
% Fixed:
%   PEY3 = 0
%   PEY4 = 0
%
% Model scope:
%   PURE LATERAL ONLY
%   No Fx / kappa / combined-slip model yet.
%
% ================================================================

MF = struct();

MF.Version = 'CMM Tire Lateral Model v1.0';
MF.ModelType = 'Pure-Lateral Magic Formula';
MF.SourceFitter = 'CMM_MF_LATERAL_GLOBAL_v1_5_ROBUST';

% ---- Reference operating point ----
MF.Reference.Fz0_N = 871.5;
MF.Reference.P0_psi = 12.10;
MF.Reference.IA0_deg = 0.0;

% ---- Fixed coefficients not currently identified ----
MF.Fixed.PEY3 = 0.0;
MF.Fixed.PEY4 = 0.0;

% ---- Expected coefficient names ----
MF.ParameterNames = { ...
    'PCY1','PDY1','PDY2','PDY3','PEY1','PEY2', ...
    'PKY1','PKY2','PKY3','PHY1','PHY2','PHY3', ...
    'PVY1','PVY2','PVY3','PVY4','P_MU_1','P_MU_2','P_K_1'};

% ---- Locate saved fit ----
thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);

candidateFiles = { "C:\Users\adity\CMM_GIT\outputs\_MF_LATERAL_GLOBAL_v1_5_1\CMM_GLOBAL_MF_LATERAL_v1_5_1.mat",
    "C:\Users\adity\CMM_GIT\outputs\08_PRE_MF_FINAL_v1_5\FINAL_TIRE_CHARACTERIZATION_v1_5.mat"
   };

modelFile = '';
for k = 1:numel(candidateFiles)
    if isfile(candidateFiles{k})
        modelFile = candidateFiles{k};
        break;
    end
end

if isempty(modelFile)
    error(['CMM lateral MF parameter file not found.\n' ...
           'Run CMM_MF_LATERAL_GLOBAL_v1_5_ROBUST.m first and place:\n' ...
           'CMM_GLOBAL_MF_LATERAL_v1_5.mat\n' ...
           'beside this parameter file or in the model output folder.']);
end

S = load(modelFile);

if ~isfield(S,'GlobalMF')
    error('MAT file does not contain the expected GlobalMF structure.');
end

G = S.GlobalMF;

% ---- Copy fitted result ----
if ~isfield(G,'Parameters') || numel(G.Parameters) ~= 19
    error('Expected exactly 19 fitted lateral MF parameters.');
end

MF.Parameters = double(G.Parameters(:)).';

if isfield(G,'ParameterNames')
    MF.ParameterNames = cellstr(string(G.ParameterNames));
end

% ---- Preserve audit information ----
MF.Fixed = struct('PEY3',0,'PEY4',0);

if isfield(G,'Metrics')
    MF.Metrics = G.Metrics;
end

if isfield(G,'Envelope')
    MF.Envelope = G.Envelope;
end

if isfield(G,'MultiStart')
    MF.MultiStart = G.MultiStart;
end

MF.SourceFile = modelFile;

% ---- Name/value table for easy inspection ----
MF.ParameterTable = table( ...
    string(MF.ParameterNames(:)), ...
    MF.Parameters(:), ...
    'VariableNames', {'Parameter','Value'});

fprintf('\n============================================================\n');
fprintf(' CMM TIRE LATERAL PARAMETERS v1.0\n');
fprintf('============================================================\n');
fprintf('Source : %s\n',MF.SourceFile);
fprintf('Fz0    : %.1f N\n',MF.Reference.Fz0_N);
fprintf('P0     : %.2f psi\n',MF.Reference.P0_psi);
fprintf('IA0    : %.1f deg\n',MF.Reference.IA0_deg);
fprintf('Parameters loaded : %d\n',numel(MF.Parameters));

if isfield(MF,'Metrics') && isfield(MF.Metrics,'Global')
    fprintf('Global R2  : %.6f\n',MF.Metrics.Global.R2);
    fprintf('Global RMSE: %.3f N\n',MF.Metrics.Global.RMSE_N);
end

if isfield(MF,'Metrics') && isfield(MF.Metrics,'Reference')
    fprintf('Reference R2: %.6f\n',MF.Metrics.Reference.R2);
end

fprintf('============================================================\n\n');

end
