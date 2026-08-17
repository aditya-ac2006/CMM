%% CMM TTC LATERAL TIRE — TEAM SUMMARY v5.2
clc;
clear;

fprintf('\n============================================================\n');
fprintf('       CMM LATERAL TIRE CHARACTERIZATION — TEAM SUMMARY\n');
fprintf('============================================================\n\n');

%% SELECT v5.2 CONTRACT
[file,path] = uigetfile('*.mat','Select v5.2 Tire Characterization Contract');
if isequal(file,0)
    error('No contract selected.');
end

S = load(fullfile(path,file));
C = S.TireCharacterizationContract;

SC  = C.SweepCharacteristics;
CC  = C.ConditionCharacteristics;
Ref = C.ReferenceCondition;

%% BASIC TIRE INFORMATION
fprintf('TIRE / TEST\n');
fprintf('------------------------------------------------------------\n');
fprintf('Tire model        : %s\n',C.TireModel);
fprintf('Compound          : %s\n',C.Compound);
fprintf('Rim width         : %.1f in\n',C.RimWidth_in);
fprintf('Primary runs      : 2 + 4\n');
fprintf('Primary sweeps    : %d\n',height(SC));
fprintf('Primary samples   : %d\n',height(C.PrimaryDatabase));
fprintf('Validation sweeps : %d\n',height(C.SpeedSensitivity));
fprintf('\n');

%% REFERENCE CONDITION
fprintf('REFERENCE CONDITION\n');
fprintf('------------------------------------------------------------\n');
fprintf('Pressure          : %.2f psi\n',Ref.Pressure_Mean_psi);
fprintf('Camber            : %.2f deg\n',Ref.IA_Mean_deg);
fprintf('Speed             : %.2f mph\n',Ref.Speed_Mean_mph);
fprintf('Vertical load     : %.1f N\n',Ref.FZ_Mean_N);
fprintf('\n');

%% KEY TIRE CHARACTERISTICS
fprintf('KEY CHARACTERISTICS\n');
fprintf('------------------------------------------------------------\n');

[maxFY,idxFY] = max(SC.PeakAbsFY_N);
[maxMu,idxMu] = max(SC.MuY_Peak);

fprintf('Maximum |FY|      : %.1f N\n',maxFY);
fprintf('  at FZ           : %.1f N\n',SC.FZ_Mean_N(idxFY));
fprintf('  at SA           : %.2f deg\n',abs(SC.SA_AtPeak_deg(idxFY)));

fprintf('Maximum peak mu_y : %.3f\n',maxMu);
fprintf('  at FZ           : %.1f N\n',SC.FZ_Mean_N(idxMu));

fprintf('Median C_alpha    : %.2f N/deg\n', ...
    median(abs(SC.CorneringStiffness_N_per_deg),'omitnan'));

fprintf('Median C_alpha    : %.2f N/rad\n', ...
    median(abs(SC.CorneringStiffness_N_per_rad),'omitnan'));

fprintf('\n');

%% PEAK CLASSIFICATION
fprintf('PEAK / DATA QC\n');
fprintf('------------------------------------------------------------\n');

resolved = sum(SC.PeakStatus=="RESOLVED");
boundary = sum(SC.PeakStatus=="BOUNDARY_LIMITED");

fprintf('Resolved peaks    : %d / %d\n',resolved,height(SC));
fprintf('Boundary-limited  : %d / %d\n',boundary,height(SC));

fprintf('Mean symmetry     : %.4f\n', ...
    mean(SC.SymmetryRatio,'omitnan'));

fprintf('Symmetry std      : %.4f\n', ...
    std(SC.SymmetryRatio,'omitnan'));

fprintf('Stiffness coverage: %.1f %%\n', ...
    100*mean(isfinite(SC.CorneringStiffness_N_per_deg)));

fprintf('\n');

%% SENSITIVITY SUMMARY
fprintf('SENSITIVITY\n');
fprintf('------------------------------------------------------------\n');

fprintf('Pressure states   : %d\n',height(C.PressureSensitivity));
fprintf('Camber states     : %d\n',height(C.CamberSensitivity));

fprintf('\n');

%% FINAL STATUS
fprintf('FINAL STATUS\n');
fprintf('------------------------------------------------------------\n');
fprintf('Characterization integrity : %s\n', ...
    string(C.CharacterizationIntegrityPass));

fprintf('Figure audit               : %d / %d PASS\n', ...
    sum(C.FigureAudit.Pass),height(C.FigureAudit));

fprintf('\n============================================================\n');
fprintf('   READY FOR ENGINEERING REVIEW / MF FITTING\n');
fprintf('============================================================\n\n');