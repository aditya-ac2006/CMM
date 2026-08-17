%% ================================================================
% CMM TTC TEST MATRIX MAPPER v1.3
%
% PURPOSE:
%   Identify the actual TTC test-condition structure BEFORE
%   extracting tire peaks or fitting Magic Formula.
%
% MATRIX EXPECTED:
%   4 pressure states x 3 camber states
%
%   ~8 psi
%   ~10 psi
%   ~12 psi
%   ~14 psi
%
%   IA = 0 / 2 / 4 deg
%
% ================================================================

clear;
clc;
close all;

fprintf('\n');
fprintf('============================================================\n');
fprintf(' CMM TTC TEST MATRIX MAPPER v1.3\n');
fprintf('============================================================\n\n');

%% ================================================================
% 1. SELECT PROJECT
% ================================================================

projectFolder = uigetdir(pwd,...
    'Select CMM / TTC project folder');

if isequal(projectFolder,0)
    error('No project folder selected.');
end

%% ================================================================
% 2. LOCATE FILES
% ================================================================

files = dir(fullfile(projectFolder,'*.mat'));

run2File = '';
run4File = '';

for k = 1:numel(files)

    fname = lower(files(k).name);

    if contains(fname,'run2')
        run2File = fullfile(files(k).folder,files(k).name);
    end

    if contains(fname,'run4')
        run4File = fullfile(files(k).folder,files(k).name);
    end

end

if isempty(run2File) || isempty(run4File)
    error('Run 2 and/or Run 4 not found.');
end

fprintf('[1] FILES\n');
fprintf('------------------------------------------------------------\n');
fprintf('Run 2 : %s\n',run2File);
fprintf('Run 4 : %s\n\n',run4File);

%% ================================================================
% 3. LOAD
% ================================================================

S2 = load(run2File);
S4 = load(run4File);

fprintf('[2] TTC METADATA\n');
fprintf('------------------------------------------------------------\n');

fprintf('Tire ID:\n%s\n\n',S2.tireid);

fprintf('Test ID:\n%s\n\n',S2.testid);

fprintf('Source:\n%s\n\n',S2.source);

%% ================================================================
% 4. PRINT CHANNEL NAMES + UNITS
% ================================================================

fprintf('[3] TTC CHANNEL DEFINITIONS\n');
fprintf('------------------------------------------------------------\n');

try

    names = S2.channel.name;
    units = S2.channel.units;

    for k = 1:numel(names)

        fprintf('%-12s : %s\n',...
            names{k},units{k});

    end

catch

    fprintf('Could not read channel definitions.\n');

end

%% ================================================================
% 5. COMBINE
% ================================================================

ET = [S2.ET;S4.ET];
SA = [S2.SA;S4.SA];
FY = [S2.FY;S4.FY];
FZ = -[S2.FZ;S4.FZ];
IA = [S2.IA;S4.IA];
P  = [S2.P;S4.P];
V  = [S2.V;S4.V];
RUN = [S2.RUN;S4.RUN];

%% ================================================================
% 6. BASIC QC
% ================================================================

valid = isfinite(ET) & ...
        isfinite(SA) & ...
        isfinite(FY) & ...
        isfinite(FZ) & ...
        isfinite(IA) & ...
        isfinite(P) & ...
        isfinite(V);

ET = ET(valid);
SA = SA(valid);
FY = FY(valid);
FZ = FZ(valid);
IA = IA(valid);
P = P(valid);
V = V(valid);
RUN = RUN(valid);

fprintf('\n[4] SIGNAL RANGES\n');
fprintf('------------------------------------------------------------\n');

fprintf('ET : %.2f -> %.2f\n',min(ET),max(ET));
fprintf('SA : %.3f -> %.3f deg\n',min(SA),max(SA));
fprintf('FY : %.2f -> %.2f N\n',min(FY),max(FY));
fprintf('FZ : %.2f -> %.2f N\n',min(FZ),max(FZ));
fprintf('IA : %.3f -> %.3f\n',min(IA),max(IA));
fprintf('P  : %.2f -> %.2f\n',min(P),max(P));
fprintf('V  : %.2f -> %.2f\n',min(V),max(V));

%% ================================================================
% 7. FIND PRESSURE PLATEAUS
% ================================================================

fprintf('\n[5] PRESSURE STATES\n');
fprintf('------------------------------------------------------------\n');

% Pressure is continuously changing during inflation/deflation
% transitions. We identify the four large stable plateaus.

P_smooth = movmean(P,501);

% Histogram to identify dominant states
[pHist,pEdges] = histcounts(P_smooth,200);

[pSorted,pOrder] = sort(pHist,'descend');

candidateP = [];

for k = 1:numel(pOrder)

    centre = (pEdges(pOrder(k)) + ...
              pEdges(pOrder(k)+1))/2;

    if isempty(candidateP) || ...
       all(abs(candidateP-centre)>2.0)

        candidateP(end+1) = centre; %#ok<SAGROW>
    end

    if numel(candidateP)>=4
        break;
    end
end

candidateP = sort(candidateP);

fprintf('Detected dominant pressure states:\n');

for k = 1:numel(candidateP)

    psi = candidateP(k)*0.1450377;

    fprintf('  State %d : %.2f kPa = %.2f psi\n',...
        k,candidateP(k),psi);

end

%% ================================================================
% 8. CAMBER STATES
% ================================================================

fprintf('\n[6] CAMBER STATES\n');
fprintf('------------------------------------------------------------\n');

IA_round = round(IA);

% Find dominant rounded states
uniqueIA = unique(IA_round);

for k = 1:numel(uniqueIA)

    n = sum(abs(IA-uniqueIA(k))<0.25);

    if n > 1000

        fprintf('IA = %+5.2f deg : %d samples\n',...
            uniqueIA(k),n);

    end

end

%% ================================================================
% 9. CONDITION ASSIGNMENT
% ================================================================

% ------------------------------------------------
% Assign each sample to nearest pressure state.
% ------------------------------------------------

pressureState = zeros(size(P));

for k = 1:numel(candidateP)

    if k == 1

        pressureState = pressureState + ...
            (abs(P-candidateP(k)) <= ...
             abs(P-candidateP(1)));

    end

end

% Better nearest-state assignment
D = zeros(numel(P),numel(candidateP));

for k = 1:numel(candidateP)
    D(:,k) = abs(P-candidateP(k));
end

[~,pressureState] = min(D,[],2);

% ------------------------------------------------
% Camber assignment
% ------------------------------------------------

camberStates = [0 2 4];

DIA = zeros(numel(IA),numel(camberStates));

for k = 1:numel(camberStates)

    DIA(:,k) = abs(IA-camberStates(k));

end

[~,camberState] = min(DIA,[],2);

camberValue = camberStates(camberState);

%% ================================================================
% 10. MATRIX SUMMARY
% ================================================================

fprintf('\n[7] TEST MATRIX\n');
fprintf('============================================================\n');

for p = 1:numel(candidateP)

    fprintf('\nPRESSURE STATE %d\n',p);
    fprintf('Pressure = %.2f kPa = %.2f psi\n',...
        candidateP(p),...
        candidateP(p)*0.1450377);

    for c = 1:numel(camberStates)

        mask = pressureState==p & ...
               camberState==c;

        n = sum(mask);

        if n==0
            continue;
        end

        fprintf('  IA = %+2d deg : %7d samples',...
            camberStates(c),n);

        fprintf(' | FZ %.1f-%.1f N',...
            min(FZ(mask)),...
            max(FZ(mask)));

        fprintf(' | SA %.1f to %.1f deg',...
            min(SA(mask)),...
            max(SA(mask)));

        fprintf('\n');

    end

end

%% ================================================================
% 11. CONDITION PLOTS
% ================================================================

outputFolder = fullfile(projectFolder,...
    '_PRE_MF_MATRIX_v1_3');

if ~exist(outputFolder,'dir')
    mkdir(outputFolder);
end

fprintf('\n[8] GENERATING CONDITION PLOTS\n');
fprintf('------------------------------------------------------------\n');

for p = 1:numel(candidateP)

    for c = 1:numel(camberStates)

        mask = pressureState==p & ...
               camberState==c;

        if sum(mask)<100
            continue;
        end

        figure('Color','w');

        plot(SA(mask),FY(mask),'.',...
            'MarkerSize',3);

        xlabel('Slip Angle [deg]');
        ylabel('F_Y [N]');

        title(sprintf(...
            'P = %.2f psi | IA = %+d deg',...
            candidateP(p)*0.1450377,...
            camberStates(c)));

        grid on;

        filename = sprintf(...
            'P%02d_IA%+02d_FY_SA.png',...
            p,...
            camberStates(c));

        saveas(gcf,...
            fullfile(outputFolder,filename));

        close;

    end

end

%% ================================================================
% 12. CONDITION LOAD MAP
% ================================================================

figure('Color','w');

hold on;

for p = 1:numel(candidateP)

    for c = 1:numel(camberStates)

        mask = pressureState==p & ...
               camberState==c;

        if sum(mask)<100
            continue;
        end

        plot(...
            mean(FZ(mask)),...
            max(abs(FY(mask))),...
            'o',...
            'MarkerSize',8);

        text(...
            mean(FZ(mask)),...
            max(abs(FY(mask))),...
            sprintf(' P%.1f IA%d',...
            candidateP(p)*0.1450377,...
            camberStates(c)));

    end

end

xlabel('Mean F_Z [N]');
ylabel('Maximum |F_Y| [N]');
title('TTC Condition Load / Force Map');
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    'CONDITION_LOAD_FORCE_MAP.png'));

%% ================================================================
% 13. TEST SEQUENCE WITH CONDITION COLOURING
% ================================================================

figure('Color','w');

scatter(ET,...
        SA,...
        3,...
        pressureState,...
        'filled');

xlabel('Elapsed Time');
ylabel('Slip Angle [deg]');
title('TTC Test Sequence - Pressure State');
colorbar;
grid on;

saveas(gcf,...
    fullfile(outputFolder,...
    'TEST_SEQUENCE_PRESSURE_STATES.png'));

%% ================================================================
% 14. SAVE CONDITION DATABASE
% ================================================================

fprintf('\n[9] BUILDING CONDITION DATABASE\n');
fprintf('------------------------------------------------------------\n');

% ------------------------------------------------
% Force every variable to be a column vector.
% This prevents MATLAB table row-count errors.
% ------------------------------------------------

ET = ET(:);
SA = SA(:);
FY = FY(:);
FZ = FZ(:);
IA = IA(:);
P  = P(:);
V  = V(:);
RUN = RUN(:);

pressureState = pressureState(:);
camberState   = camberState(:);
camberValue   = camberValue(:);

% ------------------------------------------------
% Safety check
% ------------------------------------------------

nRows = numel(ET);

fprintf('Expected database rows : %d\n',nRows);

fprintf('ET             : %d\n',numel(ET));
fprintf('SA             : %d\n',numel(SA));
fprintf('FY             : %d\n',numel(FY));
fprintf('FZ             : %d\n',numel(FZ));
fprintf('IA             : %d\n',numel(IA));
fprintf('P              : %d\n',numel(P));
fprintf('V              : %d\n',numel(V));
fprintf('RUN            : %d\n',numel(RUN));
fprintf('Pressure state : %d\n',numel(pressureState));
fprintf('Camber state   : %d\n',numel(camberState));
fprintf('Camber value   : %d\n',numel(camberValue));

% ------------------------------------------------
% Hard validation
% ------------------------------------------------

if any([ ...
        numel(SA),...
        numel(FY),...
        numel(FZ),...
        numel(IA),...
        numel(P),...
        numel(V),...
        numel(RUN),...
        numel(pressureState),...
        numel(camberState),...
        numel(camberValue)] ~= nRows)

    error(['Condition database vectors do not have identical ',...
           'lengths. Check the printed sizes above.']);

end

% ------------------------------------------------
% Unique condition ID
%
% 10, 20, 30, 40 = pressure states
% +1 / +2 / +3 = camber states
% ------------------------------------------------

conditionID = pressureState*10 + camberState;
conditionID = conditionID(:);

% ------------------------------------------------
% Create table
% ------------------------------------------------

DATA = table(...
    ET,...
    SA,...
    FY,...
    FZ,...
    IA,...
    P,...
    V,...
    RUN,...
    pressureState,...
    camberState,...
    camberValue,...
    conditionID,...
    'VariableNames',{...
    'ET',...
    'SA_deg',...
    'FY_N',...
    'FZ_N',...
    'IA_deg',...
    'Pressure_kPa',...
    'Speed_kph',...
    'RUN',...
    'PressureState',...
    'CamberState',...
    'Camber_deg',...
    'ConditionID'});

% ------------------------------------------------
% Save CSV
% ------------------------------------------------

csvFile = fullfile(outputFolder,...
    'TTC_CONDITION_ASSIGNED_DATABASE.csv');

writetable(DATA,csvFile);

% ------------------------------------------------
% Save MAT
% ------------------------------------------------

matFile = fullfile(outputFolder,...
    'TTC_CONDITION_ASSIGNED_DATABASE.mat');

save(matFile,...
    'DATA',...
    'candidateP',...
    'camberStates');

fprintf('\nCondition database created successfully.\n');
fprintf('Rows : %d\n',height(DATA));

fprintf('\nCSV:\n%s\n',csvFile);

fprintf('\nMAT:\n%s\n',matFile);
%% ================================================================
% 15. FINAL
% ================================================================

fprintf('\n============================================================\n');
fprintf(' TTC MATRIX MAPPING COMPLETE\n');
fprintf('============================================================\n');

fprintf('\nDetected pressure states : %d\n',numel(candidateP));
fprintf('Detected camber states   : %d\n',numel(camberStates));

fprintf('\nOutput:\n%s\n',outputFolder);

fprintf('\nIMPORTANT:\n');
fprintf('Do NOT fit Pacejka yet.\n');
fprintf('Do NOT send final mu values yet.\n');
fprintf('Review the 12 condition plots first.\n');

fprintf('\n============================================================\n');