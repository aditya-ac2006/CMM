function Result = pre_MF_v1_4_final_characterizer()
%% ================================================================
% CMM TTC CONDITION-BY-CONDITION CHARACTERIZER v1.4
%
% PURPOSE:
%   Final tire characterization BEFORE Magic Formula fitting.
%
% INPUT:
%   TTC_CONDITION_ASSIGNED_DATABASE.csv from v1.3
%
% OUTPUT:
%   - Load-binned FY
%   - Load-binned mu
%   - Peak slip angle
%   - Cornering stiffness
%   - Pressure sensitivity
%   - Camber sensitivity
%   - Reference-condition characterization
%   - Engineering plots
%   - Team-ready provisional report
%
% IMPORTANT:
%   No Pacejka fitting is performed.
%
% ================================================================

clear;
clc;
close all;

fprintf('\n');
fprintf('============================================================\n');
fprintf(' CMM TTC FINAL PRE-MF CHARACTERIZER v1.4\n');
fprintf('============================================================\n\n');

%% ================================================================
% 1. SETTINGS
% ================================================================

REF_FZ = 871.5;

REF_PRESSURE_PSI = 12.09;
REF_PRESSURE_KPA = REF_PRESSURE_PSI / 0.1450377;

REF_CAMBER = 0.0;
REF_SPEED_KPH = 40.22;       % 24.99 mph

% ------------------------------------------------
% Load range
% ------------------------------------------------

MIN_FZ_ANALYSIS = 300;
MAX_FZ_ANALYSIS = 1200;

LOAD_BIN_WIDTH = 100;

% Minimum samples in a load bin
MIN_BIN_SAMPLES = 50;

% ------------------------------------------------
% Peak filtering
% ------------------------------------------------

% Avoid single-sample spikes.
SMOOTH_FY_WINDOW = 21;

% ------------------------------------------------
% Cornering stiffness
% ------------------------------------------------

CA_RANGE_DEG = 2.0;

% ------------------------------------------------
% Reference load tolerance
% ------------------------------------------------

REF_FZ_TOL = 75;

%% ================================================================
% 2. SELECT PROJECT
% ================================================================

fprintf('[1] SELECT PROJECT FOLDER\n');
fprintf('------------------------------------------------------------\n');

projectFolder = uigetdir(pwd,...
    'Select CMM / TTC project folder');

if isequal(projectFolder,0)
    error('No folder selected.');
end

fprintf('Selected:\n%s\n\n',projectFolder);

%% ================================================================
% 3. LOCATE CONDITION DATABASE
% ================================================================

fprintf('[2] LOCATING CONDITION DATABASE\n');
fprintf('------------------------------------------------------------\n');

dbFile = fullfile(...
    projectFolder,...
    '_PRE_MF_MATRIX_v1_3',...
    'TTC_CONDITION_ASSIGNED_DATABASE.csv');

if ~isfile(dbFile)

    error(['Condition database not found:\n%s\n\n',...
           'Run v1.3 first.'],dbFile);

end

fprintf('Database:\n%s\n\n',dbFile);

%% ================================================================
% 4. LOAD DATABASE
% ================================================================

fprintf('[3] LOADING DATABASE\n');
fprintf('------------------------------------------------------------\n');

D = readtable(dbFile);

fprintf('Rows loaded : %d\n',height(D));

%% ================================================================
% 5. CHECK VARIABLES
% ================================================================

required = {...
    'ET',...
    'SA_deg',...
    'FY_N',...
    'FZ_N',...
    'IA_deg',...
    'Pressure_kPa',...
    'Speed_kph',...
    'PressureState',...
    'CamberState',...
    'Camber_deg'};

for k = 1:numel(required)

    if ~ismember(required{k},D.Properties.VariableNames)

        error('Missing database variable: %s',required{k});

    end

end

%% ================================================================
% 6. BASIC QC
% ================================================================

fprintf('\n[4] DATA QUALITY CONTROL\n');
fprintf('------------------------------------------------------------\n');

valid = isfinite(D.SA_deg) & ...
        isfinite(D.FY_N) & ...
        isfinite(D.FZ_N) & ...
        isfinite(D.IA_deg) & ...
        isfinite(D.Pressure_kPa) & ...
        isfinite(D.Speed_kph);

D = D(valid,:);

fprintf('Valid rows : %d\n',height(D));

fprintf('SA : %.2f to %.2f deg\n',...
    min(D.SA_deg),max(D.SA_deg));

fprintf('FY : %.2f to %.2f N\n',...
    min(D.FY_N),max(D.FY_N));

fprintf('FZ : %.2f to %.2f N\n',...
    min(D.FZ_N),max(D.FZ_N));

%% ================================================================
% 7. OUTPUT FOLDER
% ================================================================

thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));
outputFolder = fullfile(repoRoot,'outputs','07_PRE_MF_FINAL_v1_4');

if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end

%% ================================================================
% 8. IDENTIFY CONDITIONS
% ================================================================

fprintf('\n[5] IDENTIFYING TEST CONDITIONS\n');
fprintf('------------------------------------------------------------\n');

conditionIDs = unique(D.ConditionID);

fprintf('Conditions found : %d\n',numel(conditionIDs));

%% ================================================================
% 9. LOAD BINS
% ================================================================

loadEdges = MIN_FZ_ANALYSIS:LOAD_BIN_WIDTH:MAX_FZ_ANALYSIS;

loadCenters = ...
    loadEdges(1:end-1) + LOAD_BIN_WIDTH/2;

nBins = numel(loadCenters);

%% ================================================================
% 10. RESULT ARRAYS
% ================================================================

ConditionResults = struct();

allCondition = [];
allPressure = [];
allCamber = [];
allFz = [];
allPeakFY = [];
allMu = [];
allPeakSA = [];
allCA = [];
allN = [];

%% ================================================================
% 11. CONDITION-BY-CONDITION ANALYSIS
% ================================================================

for c = 1:numel(conditionIDs)

    cid = conditionIDs(c);

    maskCondition = D.ConditionID == cid;

    T = D(maskCondition,:);

    if height(T) < 100
        continue;
    end

    pressureKPa = median(T.Pressure_kPa,'omitnan');
    pressurePsi = pressureKPa*0.1450377;

    camberDeg = median(T.Camber_deg,'omitnan');

    fprintf('\n------------------------------------------------------------\n');
    fprintf('CONDITION %d\n',cid);
    fprintf('Pressure : %.2f kPa (%.2f psi)\n',...
        pressureKPa,pressurePsi);
    fprintf('Camber   : %.2f deg\n',camberDeg);
    fprintf('Samples  : %d\n',height(T));

    % ------------------------------------------------------------
    % Smooth FY only for peak detection.
    % ------------------------------------------------------------

    FYsmooth = movmean(T.FY_N,SMOOTH_FY_WINDOW);

    % ------------------------------------------------------------
    % Allocate condition arrays
    % ------------------------------------------------------------

    peakFY_bin = nan(nBins,1);
    peakFZ_bin = nan(nBins,1);
    peakSA_bin = nan(nBins,1);
    mu_bin = nan(nBins,1);
    CA_bin = nan(nBins,1);
    N_bin = zeros(nBins,1);

    % ------------------------------------------------------------
    % Load bins
    % ------------------------------------------------------------

    for b = 1:nBins

        fzLow = loadEdges(b);
        fzHigh = loadEdges(b+1);

        binMask = T.FZ_N >= fzLow & ...
                  T.FZ_N < fzHigh;

        if sum(binMask) < MIN_BIN_SAMPLES
            continue;
        end

        fzData = T.FZ_N(binMask);
        saData = T.SA_deg(binMask);
        fyData = FYsmooth(binMask);

        % --------------------------------------------------------
        % Peak force
        % --------------------------------------------------------

        [peakForce,idxPeak] = max(abs(fyData));

        peakFY_bin(b) = peakForce;
        peakFZ_bin(b) = median(fzData,'omitnan');
        peakSA_bin(b) = saData(idxPeak);

        mu_bin(b) = ...
            peakFY_bin(b) / peakFZ_bin(b);

        N_bin(b) = sum(binMask);

        % --------------------------------------------------------
        % Cornering stiffness
        % --------------------------------------------------------

        caMask = abs(saData) <= CA_RANGE_DEG;

        if sum(caMask) >= 20

            x = saData(caMask);
            y = fyData(caMask);

            % Remove duplicate SA values
            [xUnique,~,g] = unique(x);

            yUnique = accumarray(...
                g,...
                y,...
                [],...
                @mean);

            if numel(xUnique)>=5

                pp = polyfit(xUnique,...
                             yUnique,...
                             1);

                CA_bin(b) = abs(pp(1));

            end

        end

    end

    % ------------------------------------------------------------
    % Store
    % ------------------------------------------------------------

    ConditionResults(c).conditionID = cid;
    ConditionResults(c).pressureKPa = pressureKPa;
    ConditionResults(c).pressurePsi = pressurePsi;
    ConditionResults(c).camberDeg = camberDeg;

    ConditionResults(c).loadCenters = loadCenters(:);
    ConditionResults(c).peakFY = peakFY_bin;
    ConditionResults(c).peakFZ = peakFZ_bin;
    ConditionResults(c).peakSA = peakSA_bin;
    ConditionResults(c).mu = mu_bin;
    ConditionResults(c).CA = CA_bin;
    ConditionResults(c).N = N_bin;

    % ------------------------------------------------------------
    % Append summary points
    % ------------------------------------------------------------

    good = isfinite(mu_bin);

    allCondition = [allCondition; ...
                    repmat(cid,sum(good),1)];

    allPressure = [allPressure; ...
                   repmat(pressurePsi,sum(good),1)];

    allCamber = [allCamber; ...
                 repmat(camberDeg,sum(good),1)];

    allFz = [allFz;peakFZ_bin(good)];

    allPeakFY = [allPeakFY;peakFY_bin(good)];

    allMu = [allMu;mu_bin(good)];

    allPeakSA = [allPeakSA;peakSA_bin(good)];

    allCA = [allCA;CA_bin(good)];

    allN = [allN;N_bin(good)];

    fprintf('Valid load bins : %d / %d\n',...
        sum(good),nBins);

end

%% ================================================================
% 12. MASTER CHARACTERIZATION TABLE
% ================================================================

MASTER = table(...
    allCondition,...
    allPressure,...
    allCamber,...
    allFz,...
    allPeakFY,...
    allMu,...
    allPeakSA,...
    allCA,...
    allN,...
    'VariableNames',{...
    'ConditionID',...
    'Pressure_psi',...
    'Camber_deg',...
    'FZ_N',...
    'PeakFY_N',...
    'Mu_y',...
    'PeakSA_deg',...
    'CAlpha_NperDeg',...
    'Samples'});

masterFile = fullfile(...
    outputFolder,...
    'FINAL_LOAD_BIN_CHARACTERIZATION.csv');

writetable(MASTER,masterFile);

fprintf('\n[6] MASTER DATABASE\n');
fprintf('------------------------------------------------------------\n');
fprintf('Rows : %d\n',height(MASTER));
fprintf('Saved:\n%s\n',masterFile);

%% ================================================================
% 13. REFERENCE CONDITION
% ================================================================

fprintf('\n[7] REFERENCE CONDITION ANALYSIS\n');
fprintf('------------------------------------------------------------\n');

referenceMask = ...
    abs(MASTER.Pressure_psi-REF_PRESSURE_PSI)<=0.20 & ...
    abs(MASTER.Camber_deg-REF_CAMBER)<=0.25 & ...
    abs(MASTER.FZ_N-REF_FZ)<=REF_FZ_TOL;

REF = MASTER(referenceMask,:);

if isempty(REF)

    fprintf('No reference-load bins found.\n');

    referenceMu = NaN;
    referenceFY = NaN;
    referenceSA = NaN;
    referenceCA = NaN;

else

    referenceMu = median(REF.Mu_y,'omitnan');

    [~,imax] = max(REF.Mu_y);

    referenceFY = REF.PeakFY_N(imax);
    referenceSA = REF.PeakSA_deg(imax);

    referenceCA = median(REF.CAlpha_NperDeg,...
        'omitnan');

    fprintf('Reference pressure : %.2f psi\n',...
        REF_PRESSURE_PSI);

    fprintf('Reference camber   : %.2f deg\n',...
        REF_CAMBER);

    fprintf('Reference FZ       : %.1f N\n',...
        REF_FZ);

    fprintf('Bins found         : %d\n',height(REF));

    fprintf('Median mu_y        : %.4f\n',...
        referenceMu);

    fprintf('Peak FY near ref   : %.2f N\n',...
        referenceFY);

    fprintf('Peak SA            : %.2f deg\n',...
        referenceSA);

    fprintf('Median C-alpha     : %.3f N/deg\n',...
        referenceCA);

end

%% ================================================================
% 14. GLOBAL MAXIMUM MU
% ================================================================

fprintf('\n[8] GLOBAL CHARACTERISTICS\n');
fprintf('------------------------------------------------------------\n');

[globalMu,globalIdx] = max(MASTER.Mu_y);

fprintf('Maximum load-binned mu : %.4f\n',globalMu);

fprintf('Pressure               : %.2f psi\n',...
    MASTER.Pressure_psi(globalIdx));

fprintf('Camber                 : %.2f deg\n',...
    MASTER.Camber_deg(globalIdx));

fprintf('FZ                     : %.2f N\n',...
    MASTER.FZ_N(globalIdx));

fprintf('FY                     : %.2f N\n',...
    MASTER.PeakFY_N(globalIdx));

fprintf('SA                     : %.2f deg\n',...
    MASTER.PeakSA_deg(globalIdx));

%% ================================================================
% 15. PLOT: ALL LOAD-BIN MU
% ================================================================

figure('Color','w');

scatter(...
    MASTER.FZ_N,...
    MASTER.Mu_y,...
    35,...
    MASTER.Pressure_psi,...
    'filled');

hold on;

xline(REF_FZ,'--',...
    'Reference F_Z');

xlabel('F_Z [N]');
ylabel('\mu_y');
title('Load-Binned Tire Friction');
cb = colorbar;
ylabel(cb,'Pressure [psi]');
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    '01_LOAD_BIN_MU.png'));

%% ================================================================
% 16. PLOT: PRESSURE SENSITIVITY
% ================================================================

figure('Color','w');

hold on;

pressures = unique(MASTER.Pressure_psi);

for k = 1:numel(pressures)

    mask = MASTER.Pressure_psi == pressures(k) & ...
           abs(MASTER.Camber_deg)<0.5;

    if any(mask)

        plot(MASTER.FZ_N(mask),...
             MASTER.Mu_y(mask),...
             'o-',...
             'DisplayName',...
             sprintf('%.2f psi',pressures(k)));

    end

end

xlabel('F_Z [N]');
ylabel('\mu_y');
title('Pressure Sensitivity at 0° Camber');
legend('Location','best');
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    '02_PRESSURE_SENSITIVITY.png'));

%% ================================================================
% 17. PLOT: CAMBER SENSITIVITY
% ================================================================

figure('Color','w');

hold on;

cambers = unique(MASTER.Camber_deg);

for k = 1:numel(cambers)

    mask = abs(MASTER.Pressure_psi-REF_PRESSURE_PSI)<0.25 & ...
           abs(MASTER.Camber_deg-cambers(k))<0.25;

    if any(mask)

        plot(MASTER.FZ_N(mask),...
             MASTER.Mu_y(mask),...
             'o-',...
             'DisplayName',...
             sprintf('%+.0f deg',cambers(k)));

    end

end

xlabel('F_Z [N]');
ylabel('\mu_y');
title('Camber Sensitivity at ~12.1 psi');
legend('Location','best');
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    '03_CAMBER_SENSITIVITY.png'));

%% ================================================================
% 18. PLOT: PEAK FY VS FZ
% ================================================================

figure('Color','w');

scatter(...
    MASTER.FZ_N,...
    MASTER.PeakFY_N,...
    35,...
    MASTER.Camber_deg,...
    'filled');

xlabel('F_Z [N]');
ylabel('Peak |F_Y| [N]');
title('Peak Lateral Force vs Load');
cb = colorbar;
ylabel(cb,'Camber [deg]');
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    '04_PEAK_FY_VS_FZ.png'));

%% ================================================================
% 19. PLOT: PEAK SA VS FZ
% ================================================================

figure('Color','w');

scatter(...
    MASTER.FZ_N,...
    abs(MASTER.PeakSA_deg),...
    35,...
    MASTER.Pressure_psi,...
    'filled');

xlabel('F_Z [N]');
ylabel('|Peak SA| [deg]');
title('Peak Slip Angle vs Load');
cb = colorbar;
ylabel(cb,'Pressure [psi]');
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    '05_PEAK_SA_VS_FZ.png'));

%% ================================================================
% 20. PLOT: CORNERING STIFFNESS
% ================================================================

figure('Color','w');

scatter(...
    MASTER.FZ_N,...
    MASTER.CAlpha_NperDeg,...
    35,...
    MASTER.Camber_deg,...
    'filled');

xlabel('F_Z [N]');
ylabel('C_\alpha [N/deg]');
title('Cornering Stiffness vs Load');
cb = colorbar;
ylabel(cb,'Camber [deg]');
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    '06_CALPHA_VS_FZ.png'));

%% ================================================================
% 21. REFERENCE FY-SLIP CURVES
% ================================================================

figure('Color','w');

refDataMask = ...
    abs(D.Pressure_kPa-REF_PRESSURE_KPA)<1.0 & ...
    abs(D.Camber_deg)<0.25 & ...
    abs(D.FZ_N-REF_FZ)<REF_FZ_TOL;

if sum(refDataMask)>100

    scatter(...
        D.SA_deg(refDataMask),...
        D.FY_N(refDataMask),...
        6,...
        D.FZ_N(refDataMask),...
        'filled');

    xlabel('Slip Angle [deg]');
    ylabel('F_Y [N]');
    title('Reference Condition: FY vs Slip Angle');

    cb = colorbar;
    ylabel(cb,'F_Z [N]');

    grid on;

else

    text(0.2,0.5,...
        'Insufficient reference-condition data');

    axis off;

end

saveas(gcf,...
    fullfile(outputFolder,...
    '07_REFERENCE_FY_SA.png'));

%% ================================================================
% 22. MU HISTOGRAM
% ================================================================

figure('Color','w');

histogram(MASTER.Mu_y,25);

hold on;

xline(referenceMu,'--',...
    'Reference median \mu');

xlabel('\mu_y');
ylabel('Count');
title('Load-Binned Friction Coefficient Distribution');
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    '08_MU_DISTRIBUTION.png'));

%% ================================================================
% 23. SAVE RESULTS
% ================================================================

RESULTS = struct();

RESULTS.reference.pressurePsi = REF_PRESSURE_PSI;
RESULTS.reference.pressureKPa = REF_PRESSURE_KPA;
RESULTS.reference.camberDeg = REF_CAMBER;
RESULTS.reference.FzN = REF_FZ;
RESULTS.reference.mu = referenceMu;
RESULTS.reference.peakFyN = referenceFY;
RESULTS.reference.peakSADeg = referenceSA;
RESULTS.reference.CAlpha = referenceCA;

RESULTS.global.maxMu = globalMu;
RESULTS.global.pressurePsi = MASTER.Pressure_psi(globalIdx);
RESULTS.global.camberDeg = MASTER.Camber_deg(globalIdx);
RESULTS.global.FzN = MASTER.FZ_N(globalIdx);
RESULTS.global.FyN = MASTER.PeakFY_N(globalIdx);
RESULTS.global.peakSADeg = MASTER.PeakSA_deg(globalIdx);

RESULTS.dataRows = height(D);
RESULTS.characterizationRows = height(MASTER);

save(fullfile(outputFolder,...
    'FINAL_PRE_MF_RESULTS_v1_4.mat'),...
    'RESULTS',...
    'MASTER',...
    'ConditionResults');

%% ================================================================
% 24. TEAM REPORT
% ================================================================

reportFile = fullfile(...
    outputFolder,...
    'TEAM_TIRE_CHARACTERIZATION_v1_4.txt');

fid = fopen(reportFile,'w');

fprintf(fid,...
    '============================================================\n');
fprintf(fid,...
    ' CMM TIRE CHARACTERIZATION - PRE MF v1.4\n');
fprintf(fid,...
    '============================================================\n\n');

fprintf(fid,'STATUS: PROVISIONAL ENGINEERING CHARACTERIZATION\n');
fprintf(fid,'PACEJKA FITTING: NOT PERFORMED\n\n');

fprintf(fid,'TIRE\n');
fprintf(fid,...
    'Hoosier 43075 16x7.5-10 R25B, 7 inch rim\n\n');

fprintf(fid,'REFERENCE CONDITION\n');
fprintf(fid,...
    'Pressure : %.2f psi\n',REF_PRESSURE_PSI);
fprintf(fid,...
    'Camber   : %.2f deg\n',REF_CAMBER);
fprintf(fid,...
    'Speed    : %.2f kph\n',REF_SPEED_KPH);
fprintf(fid,...
    'FZ       : %.1f N\n\n',REF_FZ);

fprintf(fid,'REFERENCE CHARACTERIZATION\n');
fprintf(fid,...
    '------------------------------------------------------------\n');

fprintf(fid,...
    'Median mu_y      : %.4f\n',referenceMu);

fprintf(fid,...
    'Peak FY          : %.2f N\n',referenceFY);

fprintf(fid,...
    'Peak SA          : %.2f deg\n',referenceSA);

fprintf(fid,...
    'C-alpha          : %.3f N/deg\n',referenceCA);

fprintf(fid,'\n');

fprintf(fid,'GLOBAL LOAD-BINNED CHARACTERIZATION\n');
fprintf(fid,...
    '------------------------------------------------------------\n');

fprintf(fid,...
    'Maximum mu_y     : %.4f\n',globalMu);

fprintf(fid,...
    'Pressure         : %.2f psi\n',...
    MASTER.Pressure_psi(globalIdx));

fprintf(fid,...
    'Camber           : %.2f deg\n',...
    MASTER.Camber_deg(globalIdx));

fprintf(fid,...
    'FZ               : %.2f N\n',...
    MASTER.FZ_N(globalIdx));

fprintf(fid,...
    'Peak FY          : %.2f N\n',...
    MASTER.PeakFY_N(globalIdx));

fprintf(fid,...
    'Peak SA          : %.2f deg\n',...
    MASTER.PeakSA_deg(globalIdx));

fprintf(fid,'\n');

fprintf(fid,'IMPORTANT INTERPRETATION\n');
fprintf(fid,...
    '------------------------------------------------------------\n');

fprintf(fid,...
    ['Friction coefficient was NOT calculated from the single ',...
     'largest FY/FZ sample.\n']);

fprintf(fid,...
    ['Instead, FY peaks were evaluated inside vertical-load ',...
     'bins to reduce low-load ratio inflation.\n']);

fprintf(fid,'\n');

fprintf(fid,...
    ['The raw low-load value should therefore NOT be reported ',...
     'as tire peak mu.\n']);

fprintf(fid,'\n');

fprintf(fid,'MF READINESS\n');
fprintf(fid,...
    '------------------------------------------------------------\n');

fprintf(fid,...
    ['This dataset is now structurally organized and load-binned ',...
     'for MF fitting.\n']);

fprintf(fid,...
    ['Final MF fitting should proceed only after engineering ',...
     'review of the generated characterization plots.\n']);

fclose(fid);

%% ================================================================
% 25. FINAL CONSOLE SUMMARY
% ================================================================

fprintf('\n');
fprintf('============================================================\n');
fprintf(' v1.4 CHARACTERIZATION COMPLETE\n');
fprintf('============================================================\n');

fprintf('\nREFERENCE CONDITION\n');
fprintf('------------------------------------------------------------\n');

fprintf('Pressure        : %.2f psi\n',REF_PRESSURE_PSI);
fprintf('Camber          : %.2f deg\n',REF_CAMBER);
fprintf('FZ              : %.1f N\n',REF_FZ);
fprintf('Median mu       : %.4f\n',referenceMu);
fprintf('Peak FY         : %.2f N\n',referenceFY);
fprintf('Peak SA         : %.2f deg\n',referenceSA);
fprintf('C-alpha         : %.3f N/deg\n',referenceCA);

fprintf('\nGLOBAL\n');
fprintf('------------------------------------------------------------\n');

fprintf('Maximum binned mu : %.4f\n',globalMu);
fprintf('Pressure          : %.2f psi\n',...
    MASTER.Pressure_psi(globalIdx));
fprintf('Camber            : %.2f deg\n',...
    MASTER.Camber_deg(globalIdx));
fprintf('FZ                : %.2f N\n',...
    MASTER.FZ_N(globalIdx));

fprintf('\nOUTPUT\n');
fprintf('------------------------------------------------------------\n');

fprintf('%s\n',outputFolder);
fprintf('\nTeam report:\n%s\n',reportFile);

fprintf('\n============================================================\n');
fprintf(' REVIEW PLOTS 01-08 BEFORE PACEJKA.\n');
fprintf('============================================================\n');