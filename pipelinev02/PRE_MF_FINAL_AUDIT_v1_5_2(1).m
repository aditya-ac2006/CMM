%% CMM PRE-MF FINAL AUDIT v1.5.2
% Corrected targeted audit before Pacejka fitting.
%
% v1.5.2 fixes the v1.5.1 TTC Fy/SA sign-convention issue.
%
% Checks:
%   A) Peak resolution / boundary limitation
%   B) Reference-load coverage
%   C) Cornering stiffness robustness
%   D) Left/right symmetry
%   E) TTC sign-convention diagnostics
%
% IMPORTANT:
%   - Does NOT fit Pacejka.
%   - Does NOT modify the v1.5 master database.
%   - Uses the condition-assigned TTC database.
%   - Reports physical |Fy| and a normalized Fy sign for stiffness.
%
% Expected input:
%   _PRE_MF_MATRIX_v1_3\TTC\TTC_CONDITION_ASSIGNED_DATABASE.csv
%
% Outputs:
%   _PRE_MF_FINAL_AUDIT_v1_5_2\
%       AUDIT_REPORT_v1_5_2.txt
%       AUDIT_RESULTS_v1_5_2.mat
%       REFERENCE_LOAD_COVERAGE_v1_5_2.csv
%       CORNERING_STIFFNESS_AUDIT_v1_5_2.csv
%       plots\A_PEAK_RESOLUTION.png
%       plots\B_REFERENCE_LOAD_COVERAGE.png
%       plots\C_CORNERING_STIFFNESS.png
%       plots\D_SYMMETRY.png
%       plots\E_SIGN_CONVENTION.png

clear; clc; close all;

fprintf('\n============================================================\n');
fprintf(' CMM PRE-MF FINAL AUDIT v1.5.2\n');
fprintf(' TTC SIGN-CORRECTED PRE-PACEJKA AUDIT\n');
fprintf('============================================================\n\n');

%% [1] SELECT PROJECT
rootFolder = uigetdir(pwd,'SELECT CMM TTC PROJECT FOLDER');
if isequal(rootFolder,0)
    error('No project folder selected.');
end

fprintf('[1] PROJECT FOLDER\n%s\n\n',rootFolder);

%% [2] LOCATE CONDITION DATABASE
candidates = { ...
    fullfile(rootFolder,'_PRE_MF_MATRIX_v1_3','TTC','TTC_CONDITION_ASSIGNED_DATABASE.csv'), ...
    fullfile(rootFolder,'_PRE_MF_MATRIX_v1_3','TTC_CONDITION_ASSIGNED_DATABASE.csv'), ...
    fullfile(rootFolder,'_PRE_MF_MATRIX_v1','TTC','TTC_CONDITION_ASSIGNED_DATABASE.csv')};

dbFile = '';
for k = 1:numel(candidates)
    if isfile(candidates{k})
        dbFile = candidates{k};
        break;
    end
end

if isempty(dbFile)
    [fn,fp] = uigetfile('*.csv','SELECT TTC CONDITION ASSIGNED DATABASE');
    if isequal(fn,0)
        error('No database selected.');
    end
    dbFile = fullfile(fp,fn);
end

fprintf('[2] CONDITION DATABASE\n%s\n\n',dbFile);

%% [3] OUTPUT
thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));
OUT  = fullfile(repoRoot,'outputs','09_PRE_MF_FINAL_AUDIT_v1_5_2');
PLOT = fullfile(OUT,'plots');

if ~exist(OUT,'dir'), mkdir(OUT); end
if ~exist(PLOT,'dir'), mkdir(PLOT); end

%% [4] LOAD DATABASE
fprintf('[3] LOADING DATABASE\n');

D = readtable(dbFile);

fprintf('Rows loaded : %d\n',height(D));
fprintf('Variables   : %d\n\n',width(D));

SA = getVar(D,{'SA_deg','SA','SlipAngle_deg','SlipAngle'});
FY = getVar(D,{'FY_N','FY','Fy','LateralForce'});
FZ = getVar(D,{'FZ_N','FZ','Fz','VerticalLoad'});
IA = getVar(D,{'IA_deg','IA','Camber_deg','Camber'});
P  = getVar(D,{'P_kPa','P','Pressure_kPa','Pressure'});

if median(FZ,'omitnan') < 0
    FZ = -FZ;
    fprintf('FZ convention: raw negative -> converted to positive physical load.\n');
else
    fprintf('FZ convention: already positive.\n');
end

valid = isfinite(SA) & isfinite(FY) & isfinite(FZ) & ...
        isfinite(IA) & isfinite(P);

SA = SA(valid);
FY = FY(valid);
FZ = FZ(valid);
IA = IA(valid);
P  = P(valid);

fprintf('\n[4] SIGNAL QC\n');
fprintf('Valid samples : %d\n',numel(SA));
fprintf('SA : %.3f -> %.3f deg\n',min(SA),max(SA));
fprintf('FY : %.2f -> %.2f N\n',min(FY),max(FY));
fprintf('FZ : %.2f -> %.2f N\n',min(FZ),max(FZ));

%% ============================================================
% [5] TTC SIGN-CONVENTION DIAGNOSTIC
% =============================================================
fprintf('\n============================================================\n');
fprintf('[5] TTC Fy / SA SIGN-CONVENTION DIAGNOSTIC\n');
fprintf('============================================================\n');

% Determine whether Fy and SA have the same or opposite sign tendency.
% Use the reference condition, where the physical force magnitude is clear.
PREF = 12.10*6.894757293;
Ptol = 0.35*6.894757293;
IAREF = 0;

refAll = abs(P-PREF)<=Ptol & abs(IA-IAREF)<=0.35 & ...
         FZ>=250 & FZ<=1200 & abs(SA)<=12.25;

a0  = SA(refAll);
fy0 = FY(refAll);

% For each side of alpha, calculate the median sign of Fy.
pos = a0 > 1;
neg = a0 < -1;

medFyPos = median(fy0(pos),'omitnan');
medFyNeg = median(fy0(neg),'omitnan');

% The expected physical cornering convention for this audit is:
% positive normalized alpha -> positive normalized Fy.
% If raw Fy has opposite sign, flip Fy.
rawSameSign = sign(medFyPos) == sign(median(a0(pos),'omitnan'));

if rawSameSign
    FY_SIGN = +1;
    signStatus = 'RAW Fy SIGN RETAINED';
else
    FY_SIGN = -1;
    signStatus = 'RAW Fy SIGN FLIPPED FOR PHYSICAL AUDIT';
end

FYn = FY*FY_SIGN;

fprintf('Reference samples : %d\n',sum(refAll));
fprintf('Median raw Fy at +SA : %.3f N\n',medFyPos);
fprintf('Median raw Fy at -SA : %.3f N\n',medFyNeg);
fprintf('Applied Fy sign      : %+d\n',FY_SIGN);
fprintf('Status               : %s\n',signStatus);

% Diagnostic plot
f = figure('Color','k','Position',[80 80 1200 750]);
ax = gca;
set(ax,'Color','k','XColor','w','YColor','w');
hold on;
scatter(a0,fy0,4,[0.25 0.75 1.0],'filled','MarkerFaceAlpha',0.05);
yline(0,'w:');
xline(0,'w:');
grid on; box on;
xlabel('SA [deg]','Color','w');
ylabel('Raw TTC F_y [N]','Color','w');
title(sprintf('AUDIT E — TTC Sign Convention | Fy sign multiplier = %+d',FY_SIGN),...
      'Color','w');
saveas(f,fullfile(PLOT,'E_SIGN_CONVENTION.png'));

%% Reference physical data
a  = a0;
fy = FYn(refAll);
fz = FZ(refAll);

FZREF = 871.5;

fprintf('\nPhysical audit convention:\n');
fprintf('SA > 0 -> normalized Fy > 0\n');
fprintf('All peak calculations use |Fy|.\n');

%% ============================================================
% [6A] AUDIT A — PEAK RESOLUTION
% =============================================================
fprintf('\n============================================================\n');
fprintf('[6A] AUDIT A — PEAK RESOLUTION\n');
fprintf('============================================================\n');

BIN = 0.10;
[aBin,fyBin,nBin] = binCurve(a,fy,BIN);

% Use magnitude of the two sides, not force addition.
pos = aBin >= 0;
ap  = aBin(pos);
fp  = abs(fyBin(pos));

neg = aBin <= 0;
an  = abs(aBin(neg));
fn  = abs(fyBin(neg));

[an,ord] = sort(an);
fn = fn(ord);

common = (0:BIN:min(max(ap),max(an)))';

fpI = interpUnique(ap,fp,common);
fnI = interpUnique(an,fn,common);

good = isfinite(fpI) & isfinite(fnI);
common = common(good);
fpI = fpI(good);
fnI = fnI(good);

fMean = (fpI + fnI)/2;

[peakFY,ipk] = max(fMean);
peakSA = common(ipk);
boundary = max(common);

% Local slopes near boundary.
near1 = common >= max(0,boundary-1.0);
near2 = common >= max(0,boundary-2.0) & ...
        common < max(0,boundary-1.0);

slopeLast = NaN;
slopePrev = NaN;

if sum(near1)>=2
    q = polyfit(common(near1),fMean(near1),1);
    slopeLast = q(1);
end

if sum(near2)>=2
    q = polyfit(common(near2),fMean(near2),1);
    slopePrev = q(1);
end

lastForce = median(fMean(near1),'omitnan');
prevForce = median(fMean(near2),'omitnan');

plateauDrop = (prevForce-lastForce)/max(peakFY,eps);

% Normalized slope relative to peak.
normSlope = slopeLast/max(peakFY,eps);

% Better classification:
% RESOLVED: peak comfortably before boundary and force not climbing.
% NEAR PLATEAU: peak before boundary and small final slope.
% BOUNDARY LIMITED: peak at/near boundary with positive slope.
% REVIEW: ambiguous.
if peakSA <= boundary-1.5 && normSlope <= 0
    peakStatus = 'RESOLVED';
elseif peakSA <= boundary-1.0 && abs(normSlope)<0.02
    peakStatus = 'LIKELY RESOLVED / NEAR PLATEAU';
elseif peakSA >= boundary-0.75 && normSlope>0.02
    peakStatus = 'LIKELY TEST-WINDOW LIMITED';
elseif peakSA >= boundary-0.75
    peakStatus = 'REVIEW — PEAK NEAR BOUNDARY';
else
    peakStatus = 'REVIEW';
end

fprintf('Combined |Fy| peak       : %.2f N\n',peakFY);
fprintf('Combined peak |SA|       : %.3f deg\n',peakSA);
fprintf('Available |SA| boundary : %.3f deg\n',boundary);
fprintf('Final 1-deg slope        : %.4f N/deg\n',slopeLast);
fprintf('Previous 1-deg slope     : %.4f N/deg\n',slopePrev);
fprintf('Normalized final slope   : %.5f /deg\n',normSlope);
fprintf('Plateau drop             : %.3f %% of peak\n',100*plateauDrop);
fprintf('Peak status              : %s\n',peakStatus);

f = figure('Color','k','Position',[100 100 1200 750]);
ax=gca;
set(ax,'Color','k','XColor','w','YColor','w');
hold on;
scatter(a,abs(fy),4,[0.25 0.75 1.0],'filled','MarkerFaceAlpha',0.04);
plot(common,fMean,'w-','LineWidth',2.5);
plot(peakSA,peakFY,'o','Color',[1 0.75 0.1],...
    'MarkerFaceColor',[1 0.75 0.1],'MarkerSize',8);
xline(10.95,'--','Color',[1 0.35 0.25],'LineWidth',1.5);
xline(boundary,'w:','LineWidth',1.5);
grid on; box on;
xlabel('|\alpha| [deg]','Color','w');
ylabel('|F_y| [N]','Color','w');
title('AUDIT A — Sign-Corrected Reference Peak Resolution','Color','w');
lg=legend('Raw reference data','Binned +/-SA magnitude median',...
    'Audited peak','v1.5 reported peak','Measured boundary','Location','best');
lg.TextColor='w'; lg.Color='k';
saveas(f,fullfile(PLOT,'A_PEAK_RESOLUTION.png'));

%% ============================================================
% [6B] AUDIT B — REFERENCE LOAD COVERAGE
% =============================================================
fprintf('\n============================================================\n');
fprintf('[6B] AUDIT B — REFERENCE LOAD COVERAGE\n');
fprintf('============================================================\n');

edges = [250 350 450 550 650 750 825 875 925 1000 1100 1200];
rows = [];

for k=1:numel(edges)-1
    ix = fz>=edges(k) & fz<edges(k+1);
    if any(ix)
        rows(end+1,:) = [ ...
            edges(k),edges(k+1),sum(ix),median(fz(ix)),...
            median(abs(fy(ix))./max(fz(ix),eps))]; %#ok<AGROW>
    end
end

LoadCoverage = array2table(rows,...
    'VariableNames',{'FZ_Low_N','FZ_High_N','Samples',...
                     'MedianFZ_N','MedianMu'});

writetable(LoadCoverage,...
    fullfile(OUT,'REFERENCE_LOAD_COVERAGE_v1_5_2.csv'));

refWindow = abs(fz-FZREF)<=125;
peakMask = refWindow & abs(a)>=6;
peakMu = abs(fy(peakMask))./max(fz(peakMask),eps);

nearBins = LoadCoverage.MedianFZ_N>=FZREF-125 & ...
           LoadCoverage.MedianFZ_N<=FZREF+125;

fprintf('Reference window : %.1f +/- 125 N\n',FZREF);
fprintf('Raw samples      : %d\n',sum(refWindow));
fprintf('Peak-region raw  : %d\n',sum(peakMask));

if ~isempty(peakMu)
    fprintf('Peak-region median mu : %.4f\n',median(peakMu));
    fprintf('Peak-region P10/P90   : %.4f / %.4f\n',...
        prctile(peakMu,10),prctile(peakMu,90));
end

fprintf('Usable load bins : %d\n',sum(nearBins));

if sum(nearBins)>=3
    refBinStatus='GOOD COVERAGE';
elseif sum(nearBins)==2
    refBinStatus='LIMITED — 2 BINS';
else
    refBinStatus='INSUFFICIENT';
end

fprintf('Reference-bin status : %s\n',refBinStatus);

f=figure('Color','k','Position',[120 120 1200 750]);
ax=gca;
set(ax,'Color','k','XColor','w','YColor','w');
bar(LoadCoverage.MedianFZ_N,LoadCoverage.Samples,1);
hold on;
xline(FZREF,'w--','LineWidth',2);
xline(FZREF-125,'--','Color',[1 0.75 0.1],'LineWidth',1.2);
xline(FZREF+125,'--','Color',[1 0.75 0.1],'LineWidth',1.2);
grid on; box on;
xlabel('Median F_z per load bin [N]','Color','w');
ylabel('Raw samples','Color','w');
title('AUDIT B — Reference Load Coverage','Color','w');
saveas(f,fullfile(PLOT,'B_REFERENCE_LOAD_COVERAGE.png'));

%% ============================================================
% [6C] AUDIT C — CORNERING STIFFNESS
% =============================================================
fprintf('\n============================================================\n');
fprintf('[6C] AUDIT C — CORNERING STIFFNESS\n');
fprintf('============================================================\n');

ranges = [ ...
    0.25 1.00
    0.25 1.50
    0.25 2.00
    0.50 2.00
    0.50 2.50];

K = NaN(size(ranges,1),1);
R2 = NaN(size(ranges,1),1);
NN = zeros(size(ranges,1),1);

for k=1:size(ranges,1)

    ix = abs(a)>=ranges(k,1) & abs(a)<=ranges(k,2);
    NN(k)=sum(ix);

    if NN(k)>=30

        % Normalize the negative side into the same physical direction:
        % Fy_norm vs alpha_norm.
        alphaN = a(ix);
        forceN = fy(ix);

        q=polyfit(alphaN,forceN,1);
        pred=polyval(q,alphaN);

        K(k)=q(1);
        R2(k)=1-sum((forceN-pred).^2)/...
            max(sum((forceN-mean(forceN)).^2),eps);
    end
end

StiffAudit=table(...
    ranges(:,1),ranges(:,2),K,R2,NN,...
    'VariableNames',{'AlphaMin_deg','AlphaMax_deg',...
    'C_alpha_N_per_deg','R2','Samples'});

writetable(StiffAudit,...
    fullfile(OUT,'CORNERING_STIFFNESS_AUDIT_v1_5_2.csv'));

for k=1:height(StiffAudit)
    fprintf('%.2f -> %.2f deg : C-alpha %.3f N/deg | R2 %.5f | N %d\n',...
        StiffAudit.AlphaMin_deg(k),...
        StiffAudit.AlphaMax_deg(k),...
        StiffAudit.C_alpha_N_per_deg(k),...
        StiffAudit.R2(k),StiffAudit.Samples(k));
end

validK=K(isfinite(K));

Kmedian=median(validK);
Kspread=(max(validK)-min(validK))/max(abs(Kmedian),eps);

fprintf('\nRobust median C-alpha : %.3f N/deg\n',Kmedian);
fprintf('Range spread          : %.2f %%\n',100*Kspread);

if Kspread<=0.10
    stiffnessStatus='ROBUST';
elseif Kspread<=0.20
    stiffnessStatus='ACCEPTABLE / SENSITIVE TO RANGE';
else
    stiffnessStatus='NOT ROBUST';
end

fprintf('Stiffness status      : %s\n',stiffnessStatus);

% Display regression using 0.25-2 deg.
primary = abs(a)>=0.25 & abs(a)<=2.0;
q=polyfit(a(primary),fy(primary),1);

f=figure('Color','k','Position',[140 140 1200 750]);
ax=gca;
set(ax,'Color','k','XColor','w','YColor','w');
scatter(a,fy,5,[0.25 0.75 1.0],'filled','MarkerFaceAlpha',0.05);
hold on;
xx=linspace(-2.5,2.5,200);
plot(xx,polyval(q,xx),'w-','LineWidth',2.5);
xline(0,'w:');
grid on; box on;
xlabel('\alpha [deg]','Color','w');
ylabel('Normalized F_y [N]','Color','w');
title(sprintf('AUDIT C — C-alpha | %.1f N/deg median',Kmedian),...
      'Color','w');
saveas(f,fullfile(PLOT,'C_CORNERING_STIFFNESS.png'));

%% ============================================================
% [6D] AUDIT D — LEFT / RIGHT SYMMETRY
% =============================================================
fprintf('\n============================================================\n');
fprintf('[6D] AUDIT D — LEFT / RIGHT SYMMETRY\n');
fprintf('============================================================\n');

gridA=(0.5:0.25:11.5)';
ratio=NaN(size(gridA));

for k=1:numel(gridA)

    aa=gridA(k);

    ip=abs(a-aa)<=0.125;
    in=abs(a+aa)<=0.125;

    if sum(ip)>=20 && sum(in)>=20

        posForce=median(abs(fy(ip)));
        negForce=median(abs(fy(in)));

        ratio(k)=posForce/max(negForce,eps);
    end
end

goodR=isfinite(ratio)&ratio>0.5&ratio<1.5;

ratioMedian=median(ratio(goodR));
ratioMean=mean(ratio(goodR));
ratioStd=std(ratio(goodR));

if sum(goodR)>=5
    tr=polyfit(gridA(goodR),ratio(goodR),1);
    ratioTrend=tr(1);
else
    ratioTrend=NaN;
end

fprintf('Median ratio : %.4f\n',ratioMedian);
fprintf('Mean ratio   : %.4f\n',ratioMean);
fprintf('Std          : %.4f\n',ratioStd);
fprintf('Valid paired bins : %d\n',sum(goodR));
fprintf('Ratio trend [1/deg] : %.6f\n',ratioTrend);

if abs(ratioMedian-1)<=0.05 && ratioStd<=0.05
    symmetryStatus='GOOD';
elseif abs(ratioMedian-1)<=0.10 && ratioStd<=0.08
    symmetryStatus='ACCEPTABLE / REVIEW';
else
    symmetryStatus='INVESTIGATE';
end

fprintf('Symmetry status : %s\n',symmetryStatus);

f=figure('Color','k','Position',[160 160 1200 750]);
ax=gca;
set(ax,'Color','k','XColor','w','YColor','w');
plot(gridA,ratio,'o-','Color',[0.25 0.75 1.0],'LineWidth',1.5);
hold on;
yline(1,'w--','LineWidth',1.5);
yline(ratioMedian,'Color',[1 0.75 0.1],'LineWidth',2);
grid on; box on;
xlabel('|\alpha| [deg]','Color','w');
ylabel('|F_y(+\alpha)| / |F_y(-\alpha)|','Color','w');
title(sprintf('AUDIT D — Symmetry | %.4f median',ratioMedian),...
      'Color','w');
lg=legend('Ratio','Perfect symmetry','Median','Location','best');
lg.TextColor='w'; lg.Color='k';
saveas(f,fullfile(PLOT,'D_SYMMETRY.png'));

%% ============================================================
% [7] FINAL DECISION
% =============================================================
fprintf('\n============================================================\n');
fprintf('[7] FINAL PRE-MF DECISION\n');
fprintf('============================================================\n');

peakPass = any(strcmp(peakStatus,...
    {'RESOLVED','LIKELY RESOLVED / NEAR PLATEAU'}));

refPass = any(strcmp(refBinStatus,...
    {'GOOD COVERAGE','LIMITED — 2 BINS'}));

stiffPass = any(strcmp(stiffnessStatus,...
    {'ROBUST','ACCEPTABLE / SENSITIVE TO RANGE'}));

symPass = any(strcmp(symmetryStatus,...
    {'GOOD','ACCEPTABLE / REVIEW'}));

fprintf('Peak resolution : %s\n',tf(peakPass));
fprintf('Reference bins  : %s\n',tf(refPass));
fprintf('C-alpha         : %s\n',tf(stiffPass));
fprintf('Symmetry        : %s\n',tf(symPass));

allPass=peakPass && refPass && stiffPass && symPass;

if allPass
    decision='PRE-MF PASS — READY FOR PACEJKA DATASET FREEZE';
else
    decision='PRE-MF REVIEW REQUIRED — DO NOT FREEZE YET';
end

fprintf('\n============================================================\n');
fprintf('%s\n',decision);
fprintf('============================================================\n');

%% [8] SAVE RESULTS
Audit=struct();

Audit.version='PRE_MF_FINAL_AUDIT_v1_5_2';

Audit.sign.raw_median_Fy_positive_SA=medFyPos;
Audit.sign.raw_median_Fy_negative_SA=medFyNeg;
Audit.sign.FY_multiplier=FY_SIGN;
Audit.sign.status=signStatus;

Audit.peak.peak_Fy_N=peakFY;
Audit.peak.peak_SA_deg=peakSA;
Audit.peak.boundary_deg=boundary;
Audit.peak.final_1deg_slope_N_per_deg=slopeLast;
Audit.peak.previous_1deg_slope_N_per_deg=slopePrev;
Audit.peak.normalized_final_slope_per_deg=normSlope;
Audit.peak.plateau_drop_fraction=plateauDrop;
Audit.peak.status=peakStatus;

Audit.reference.raw_samples=sum(refWindow);
Audit.reference.peak_region_samples=sum(peakMask);
Audit.reference.usable_bins=sum(nearBins);
Audit.reference.status=refBinStatus;

Audit.stiffness.median_N_per_deg=Kmedian;
Audit.stiffness.spread_fraction=Kspread;
Audit.stiffness.status=stiffnessStatus;

Audit.symmetry.median_ratio=ratioMedian;
Audit.symmetry.mean_ratio=ratioMean;
Audit.symmetry.std=ratioStd;
Audit.symmetry.trend_per_deg=ratioTrend;
Audit.symmetry.status=symmetryStatus;

Audit.decision=decision;

save(fullfile(OUT,'AUDIT_RESULTS_v1_5_2.mat'),'Audit');

%% [9] TEXT REPORT
reportFile=fullfile(OUT,'AUDIT_REPORT_v1_5_2.txt');
fid=fopen(reportFile,'w');

if fid>0

    fprintf(fid,'CMM PRE-MF FINAL AUDIT v1.5.2\n');
    fprintf(fid,'========================================\n\n');

    fprintf(fid,'INPUT\n%s\n\n',dbFile);

    fprintf(fid,'SIGN CONVENTION\n');
    fprintf(fid,'Raw median Fy at +SA : %.4f N\n',medFyPos);
    fprintf(fid,'Raw median Fy at -SA : %.4f N\n',medFyNeg);
    fprintf(fid,'Applied Fy multiplier: %+d\n',FY_SIGN);
    fprintf(fid,'Status: %s\n\n',signStatus);

    fprintf(fid,'AUDIT A — PEAK RESOLUTION\n');
    fprintf(fid,'Peak Fy: %.4f N\n',peakFY);
    fprintf(fid,'Peak SA: %.4f deg\n',peakSA);
    fprintf(fid,'Boundary: %.4f deg\n',boundary);
    fprintf(fid,'Final 1-deg slope: %.6f N/deg\n',slopeLast);
    fprintf(fid,'Normalized slope: %.8f /deg\n',normSlope);
    fprintf(fid,'Plateau drop: %.5f %%\n',100*plateauDrop);
    fprintf(fid,'Status: %s\n\n',peakStatus);

    fprintf(fid,'AUDIT B — REFERENCE LOAD\n');
    fprintf(fid,'Reference Fz: %.1f N\n',FZREF);
    fprintf(fid,'Raw samples in +/-125 N: %d\n',sum(refWindow));
    fprintf(fid,'Peak-region samples: %d\n',sum(peakMask));
    fprintf(fid,'Usable load bins: %d\n',sum(nearBins));
    if ~isempty(peakMu)
        fprintf(fid,'Peak-region median mu: %.5f\n',median(peakMu));
        fprintf(fid,'P10/P90: %.5f / %.5f\n',...
            prctile(peakMu,10),prctile(peakMu,90));
    end
    fprintf(fid,'Status: %s\n\n',refBinStatus);

    fprintf(fid,'AUDIT C — CORNERING STIFFNESS\n');
    fprintf(fid,'Median C-alpha: %.4f N/deg\n',Kmedian);
    fprintf(fid,'Range spread: %.4f %%\n',100*Kspread);
    fprintf(fid,'Status: %s\n\n',stiffnessStatus);

    fprintf(fid,'AUDIT D — SYMMETRY\n');
    fprintf(fid,'Median ratio: %.5f\n',ratioMedian);
    fprintf(fid,'Mean ratio: %.5f\n',ratioMean);
    fprintf(fid,'Std: %.5f\n',ratioStd);
    fprintf(fid,'Trend: %.7f / deg\n',ratioTrend);
    fprintf(fid,'Status: %s\n\n',symmetryStatus);

    fprintf(fid,'FINAL DECISION\n%s\n\n',decision);

    if allPass
        fprintf(fid,'NEXT STEP\n');
        fprintf(fid,'Freeze the Pre-MF characterization dataset and begin load/pressure/camber-dependent Pacejka fitting.\n');
    else
        fprintf(fid,'NEXT STEP\n');
        fprintf(fid,'Review the failed/review items before freezing the Pre-MF database.\n');
    end

    fclose(fid);
end

fprintf('\nREPORT:\n%s\n',reportFile);
fprintf('OUTPUT:\n%s\n',OUT);
fprintf('Audit complete.\n');

%% ============================================================
% LOCAL FUNCTIONS
% =============================================================

function x=getVar(T,names)

vn=T.Properties.VariableNames;
x=[];

for i=1:numel(names)

    j=find(strcmpi(vn,names{i}),1);

    if ~isempty(j)
        x=T.(vn{j});
        x=x(:);
        return;
    end
end

error('Required variable not found. Tried: %s',strjoin(names,', '));

end

function [ab,fb,nb]=binCurve(a,f,w)

a=a(:);
f=f(:);

ok=isfinite(a)&isfinite(f);

a=a(ok);
f=f(ok);

lo=floor(min(a)/w)*w;
hi=ceil(max(a)/w)*w;

edges=lo:w:(hi+w);

b=discretize(a,edges);

ab=[];
fb=[];
nb=[];

for i=1:numel(edges)-1

    ix=b==i;

    if sum(ix)>=3

        ab(end+1,1)=median(a(ix)); %#ok<AGROW>
        fb(end+1,1)=median(f(ix)); %#ok<AGROW>
        nb(end+1,1)=sum(ix); %#ok<AGROW>

    end
end

[ab,o]=sort(ab);

fb=fb(o);
nb=nb(o);

[ab,u]=unique(ab,'stable');

fb=fb(u);
nb=nb(u);

end

function y=interpUnique(x,v,xq)

[x,u]=unique(x,'stable');

v=v(u);

if numel(x)<2

    y=nan(size(xq));

else

    y=interp1(x,v,xq,'linear',NaN);

end

end

function s=tf(x)

if x
    s='PASS';
else
    s='FAIL';
end

end
