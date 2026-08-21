function CMM_MF_LATERAL_PARAMETER_DIAGNOSTIC_v2_6
% ================================================================
% CMM MF LATERAL PARAMETER DIAGNOSTIC v2.6.2
% TARGETED 4-PARAMETER DIAGNOSTIC / NO REFIT
%
% Purpose:
%   Diagnose the four parameters identified by v2.5 as dominant:
%       PDY1, PKY1, PKY2, PCY1
%
%   Perturb each parameter by:
%       -10%, -5%, 0%, +5%, +10%
%
%   Metrics:
%       Global R2 / RMSE / MAE
%       Exact-reference R2 / RMSE / MAE
%       Reference C-alpha [N/deg]
%       Reference peak mu
%       Reference peak slip angle
%
% IMPORTANT:
%   - NO model parameters are fitted.
%   - NO MAT file is overwritten.
%   - Uses the existing v2.0 model equation and parameter order.
%   - All figures use BLACK figure + BLACK axes with visible light axes.
% ================================================================

clc;
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL PARAMETER DIAGNOSTIC v2.6.2\n');
fprintf(' TARGETED 4-PARAMETER DIAGNOSTIC - NO REFIT\n');
fprintf('============================================================\n\n');

%% ---------------- USER CONTRACT ----------------
INPUT_CSV = 'C:\Users\adity\CMM_GIT\outputs\_PRE_MF_MATRIX_v1_3\TTC_CONDITION_ASSIGNED_DATABASE.csv';

MODEL_MAT = 'C:\Users\adity\CMM_GIT\outputs\_MF_LATERAL_GLOBAL_v2_0\CMM_GLOBAL_MF_LATERAL_v2_0.mat';

OUTDIR = 'C:\Users\adity\CMM_GIT\outputs\_MF_LATERAL_GLOBAL_v2_0\PARAMETER_DIAGNOSTIC_v2_6';
if ~exist(OUTDIR,'dir'), mkdir(OUTDIR); end

% Frozen reference condition
FZ0 = 871.5;
P0  = 12.10;
IA0 = 0.0;

% Same data contract used by the existing v2.x audits
RUNS_REQUIRED = [2 4];
FY_MULTIPLIER = -1;

% v2.0 fit envelope
MIN_FZ_FIT = 180;
MAX_FZ_FIT = 1150;
ALPHA_MAX_FIT = 12.0;

% Exact reference validation band
REF_FZ_TOL = 10.0;
REF_P_TOL  = 0.10;
REF_IA_TOL = 0.10;

% Sensitivity definition
PERTURB_PCT = [-10 -5 0 5 10];
TARGET_NAMES = {'PDY1','PKY1','PKY2','PCY1'};
TARGET_INDEX = [2 7 8 1];

% Keep the audit lightweight
MAX_SENSITIVITY_POINTS = 30000;
RNG_SEED = 2026;

% C-alpha numerical derivative in DEGREES
CALPHA_STEP_DEG = 0.001;

% Peak-search resolution
PEAK_STEP_DEG = 0.01;

%% ---------------- LOAD MODEL ----------------
fprintf('[1] MODEL\n');
fprintf('File : %s\n',MODEL_MAT);

S = load(MODEL_MAT);

if isfield(S,'GlobalMF')
    M = S.GlobalMF;
else
    fn = fieldnames(S);
    if numel(fn)==1 && isstruct(S.(fn{1}))
        M = S.(fn{1});
    else
        error('Could not locate GlobalMF structure in MAT file.');
    end
end

if ~isfield(M,'Parameters')
    error('MAT file does not contain GlobalMF.Parameters.');
end

q0 = double(M.Parameters(:)).';

if numel(q0) ~= 19
    error('Expected 19 MF parameters; found %d.',numel(q0));
end

Names = {'PCY1','PDY1','PDY2','PDY3','PEY1','PEY2', ...
         'PKY1','PKY2','PKY3','PHY1','PHY2','PHY3', ...
         'PVY1','PVY2','PVY3','PVY4','P_MU_1','P_MU_2','P_K_1'};

fprintf('Version : %s\n',getStructString(M,'Version','unknown'));
fprintf('Fz0     : %.2f N\n',FZ0);
fprintf('P0      : %.2f psi\n',P0);
fprintf('IA0     : %.2f deg\n',IA0);
fprintf('Parameters : %d\n\n',numel(q0));

%% ---------------- LOAD DATABASE ----------------
fprintf('[2] DATABASE\n');
fprintf('File : %s\n',INPUT_CSV);

T = readtable(INPUT_CSV);
fprintf('Rows : %d\n',height(T));
fprintf('Vars : %d\n',width(T));

SA = getNumeric(T,{'SA_deg','SA','SlipAngle','Slip_Angle','alpha','Alpha'});
FY = getNumeric(T,{'FY_N','FY','Fy','LateralForce','Lateral_Force'});
FZ = getNumeric(T,{'FZ_N','FZ','Fz','VerticalLoad','Vertical_Load'});
IA = getNumeric(T,{'IA_deg','IA','Camber','Camber_deg','Inclination'});
% IMPORTANT: TTC_CONDITION_ASSIGNED_DATABASE uses Pressure_kPa.
% Convert explicitly to psi rather than guessing from magnitude.
P_kPa = getNumeric(T,{'Pressure_kPa','Pressure_kpa','P_kPa','P_kpa'});
P = P_kPa * 0.1450377377;
RUN = getNumeric(T,{'RUN','Run','RunID','Run_ID','RunNumber','Run_Number'});

fprintf('Pressure mapping : Pressure_kPa -> psi\n');

FY = FY*FY_MULTIPLIER;

valid = isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)&isfinite(P)&isfinite(RUN);
SA=SA(valid); FY=FY(valid); FZ=FZ(valid); IA=IA(valid); P=P(valid); RUN=RUN(valid);

runMask = ismember(round(RUN),RUNS_REQUIRED);
SA=SA(runMask); FY=FY(runMask); FZ=FZ(runMask); IA=IA(runMask); P=P(runMask); RUN=RUN(runMask);

fprintf('Rows after Run 2+4 contract : %d\n',numel(FY));
for rr = RUNS_REQUIRED
    fprintf('Run %d rows                : %d\n',rr,nnz(round(RUN)==rr));
end

%% ---------------- FIT ENVELOPE ----------------
fitMask = FZ>=MIN_FZ_FIT & FZ<=MAX_FZ_FIT & abs(SA)<=ALPHA_MAX_FIT;

aFit = SA(fitMask);
fzFit = FZ(fitMask);
iaFit = IA(fitMask);
pFit = P(fitMask);
fyFit = FY(fitMask);

fprintf('Rows in v2.0 fit envelope  : %d\n',numel(fyFit));

rng(RNG_SEED);
if numel(fyFit) > MAX_SENSITIVITY_POINTS
    idx = randperm(numel(fyFit),MAX_SENSITIVITY_POINTS);
    aEval=aFit(idx); fzEval=fzFit(idx); iaEval=iaFit(idx);
    pEval=pFit(idx); fyEval=fyFit(idx);
else
    aEval=aFit; fzEval=fzFit; iaEval=iaFit;
    pEval=pFit; fyEval=fyFit;
end

fprintf('Sensitivity points         : %d\n\n',numel(fyEval));

%% ---------------- REFERENCE DATA ----------------
refMask = abs(FZ-FZ0)<=REF_FZ_TOL & ...
          abs(P-P0)<=REF_P_TOL & ...
          abs(IA-IA0)<=REF_IA_TOL & ...
          abs(SA)<=ALPHA_MAX_FIT;

aRef=SA(refMask);
fzRef=FZ(refMask);
iaRef=IA(refMask);
pRef=P(refMask);
fyRef=FY(refMask);

fprintf('[3] EXACT REFERENCE CONDITION\n');
fprintf('Fz : %.1f +/- %.1f N\n',FZ0,REF_FZ_TOL);
fprintf('P  : %.2f +/- %.2f psi\n',P0,REF_P_TOL);
fprintf('IA : %.2f +/- %.2f deg\n',IA0,REF_IA_TOL);
fprintf('Samples : %d\n\n',numel(fyRef));

if numel(fyRef)<100
    error('Too few exact-reference samples for diagnostic.');
end

%% ---------------- BASELINE ----------------
base = evaluateModel(q0,aEval,fzEval,iaEval,pEval,fyEval, ...
                     aRef,fzRef,iaRef,pRef,fyRef, ...
                     FZ0,P0,PEAK_STEP_DEG,CALPHA_STEP_DEG);

fprintf('[4] BASELINE MODEL\n');
printMetrics(base);

%% ---------------- TARGETED SENSITIVITY ----------------
Npar = numel(TARGET_NAMES);
Nlev = numel(PERTURB_PCT);
Ntot = Npar*Nlev;

Rows = cell(Ntot,1);
krow=0;

fprintf('\n[5] TARGETED PARAMETER DIAGNOSTIC\n');
fprintf('Parameters : PDY1, PKY1, PKY2, PCY1\n');
fprintf('Perturbations : -10%% -5%% 0%% +5%% +10%%\n\n');

for ip=1:Npar
    nm=TARGET_NAMES{ip};
    qi=TARGET_INDEX(ip);

    fprintf('Testing %s (%d/%d)\n',nm,ip,Npar);

    for jp=1:Nlev
        pct=PERTURB_PCT(jp);

        q=q0;
        q(qi)=q0(qi)*(1+pct/100);

        m=evaluateModel(q,aEval,fzEval,iaEval,pEval,fyEval, ...
                        aRef,fzRef,iaRef,pRef,fyRef, ...
                        FZ0,P0,PEAK_STEP_DEG,CALPHA_STEP_DEG);

        krow=krow+1;
        Rows{krow}=table(string(nm),qi,pct,q(qi), ...
            m.R2,m.RMSE,m.MAE, ...
            m.RefR2,m.RefRMSE,m.RefMAE, ...
            m.Calpha,m.PeakMu,m.PeakSA, ...
            'VariableNames',{'Parameter','ParameterIndex','Perturbation_pct', ...
            'ParameterValue','Global_R2','Global_RMSE_N','Global_MAE_N', ...
            'Reference_R2','Reference_RMSE_N','Reference_MAE_N', ...
            'Reference_Calpha_N_per_deg','Reference_PeakMu','Reference_PeakSA_deg'});
    end
end

ResultTable=vertcat(Rows{:});

%% ---------------- DELTAS FROM BASELINE ----------------
ResultTable.DeltaR2 = ResultTable.Global_R2-base.R2;
ResultTable.DeltaRMSE_N = ResultTable.Global_RMSE_N-base.RMSE;
ResultTable.DeltaMAE_N = ResultTable.Global_MAE_N-base.MAE;
ResultTable.DeltaReferenceCAlpha_N_per_deg = ...
    ResultTable.Reference_Calpha_N_per_deg-base.Calpha;
ResultTable.DeltaReferencePeakMu = ...
    ResultTable.Reference_PeakMu-base.PeakMu;
ResultTable.DeltaReferencePeakSA_deg = ...
    ResultTable.Reference_PeakSA_deg-base.PeakSA;

writetable(ResultTable,fullfile(OUTDIR,'TARGETED_PARAMETER_DIAGNOSTIC_v2_6_2.csv'));

%% ---------------- SUMMARY ----------------
SummaryRows=cell(Npar,1);

for ip=1:Npar
    nm=TARGET_NAMES{ip};
    m=strcmp(ResultTable.Parameter,nm);
    R=ResultTable(m,:);

    dR2=max(abs(R.DeltaR2));
    dRMSE=max(abs(R.DeltaRMSE_N));
    dCA=max(abs(R.DeltaReferenceCAlpha_N_per_deg));
    dMu=max(abs(R.DeltaReferencePeakMu));
    dSA=max(abs(R.DeltaReferencePeakSA_deg));

    % Local slopes using the -5/+5 perturbation around baseline.
    pm5=R.Perturbation_pct==-5;
    pp5=R.Perturbation_pct==5;

    slopeCA=(R.Reference_Calpha_N_per_deg(pp5)- ...
             R.Reference_Calpha_N_per_deg(pm5))/10;
    slopeMu=(R.Reference_PeakMu(pp5)-R.Reference_PeakMu(pm5))/10;
    slopeR2=(R.Global_R2(pp5)-R.Global_R2(pm5))/10;

    SummaryRows{ip}=table(string(nm),TARGET_INDEX(ip), ...
        dR2,dRMSE,dCA,dMu,dSA,slopeR2,slopeCA,slopeMu, ...
        'VariableNames',{'Parameter','ParameterIndex', ...
        'MaxAbsDeltaR2','MaxAbsDeltaRMSE_N', ...
        'MaxAbsDeltaCalpha_N_per_deg','MaxAbsDeltaPeakMu', ...
        'MaxAbsDeltaPeakSA_deg','LocalSlope_R2_per_pct', ...
        'LocalSlope_Calpha_N_per_deg_per_pct', ...
        'LocalSlope_PeakMu_per_pct'});
end

SummaryTable=vertcat(SummaryRows{:});
SummaryTable=sortrows(SummaryTable,'MaxAbsDeltaR2','descend');

writetable(SummaryTable,fullfile(OUTDIR,'TARGETED_PARAMETER_SUMMARY_v2_6_2.csv'));

%% ---------------- CONSOLE REPORT ----------------
fprintf('\n============================================================\n');
fprintf(' TARGETED PARAMETER SUMMARY\n');
fprintf('============================================================\n');

disp(SummaryTable);

fprintf('\n============================================================\n');
fprintf(' DETAILED PERTURBATION RESULTS\n');
fprintf('============================================================\n');
disp(ResultTable(:,{'Parameter','Perturbation_pct','ParameterValue', ...
    'Global_R2','Global_RMSE_N','Reference_Calpha_N_per_deg', ...
    'Reference_PeakMu','Reference_PeakSA_deg'}));

%% ---------------- PLOTS ----------------
fprintf('\n[6] FIGURES\n');

% 01: Global R2
makeMetricPlot(ResultTable,TARGET_NAMES,'Perturbation_pct','Global_R2', ...
    'Perturbation [%]','Global R^2', ...
    'v2.6 Parameter Diagnostic - Global R^2', ...
    fullfile(OUTDIR,'01_TARGETED_R2.png'));

% 02: Global RMSE
makeMetricPlot(ResultTable,TARGET_NAMES,'Perturbation_pct','Global_RMSE_N', ...
    'Perturbation [%]','RMSE [N]', ...
    'v2.6 Parameter Diagnostic - Global RMSE', ...
    fullfile(OUTDIR,'02_TARGETED_RMSE.png'));

% 03: Reference C-alpha
makeMetricPlot(ResultTable,TARGET_NAMES,'Perturbation_pct', ...
    'Reference_Calpha_N_per_deg', ...
    'Perturbation [%]','C_\alpha [N/deg]', ...
    'v2.6 Parameter Diagnostic - Reference C_\alpha', ...
    fullfile(OUTDIR,'03_TARGETED_CALPHA.png'));

% 04: Reference peak mu
makeMetricPlot(ResultTable,TARGET_NAMES,'Perturbation_pct', ...
    'Reference_PeakMu', ...
    'Perturbation [%]','\mu_{peak}', ...
    'v2.6 Parameter Diagnostic - Reference Peak \mu', ...
    fullfile(OUTDIR,'04_TARGETED_PEAKMU.png'));

% 05: Reference peak slip angle
makeMetricPlot(ResultTable,TARGET_NAMES,'Perturbation_pct', ...
    'Reference_PeakSA_deg', ...
    'Perturbation [%]','Peak slip angle [deg]', ...
    'v2.6 Parameter Diagnostic - Reference Peak Slip Angle', ...
    fullfile(OUTDIR,'05_TARGETED_PEAKSA.png'));

% 06: Local sensitivity summary
fig=figure('Color','k','Name','v2.6 Local Sensitivity');
ax=axes(fig); styleAxes(ax);
bar(ax,SummaryTable.LocalSlope_Calpha_N_per_deg_per_pct);
xticks(ax,1:Npar);
xticklabels(ax,cellstr(SummaryTable.Parameter));
ylabel(ax,'dC_\alpha / dParameter [%] [N/deg/%]');
title(ax,'v2.6 Local C_\alpha Sensitivity');
exportgraphics(fig,fullfile(OUTDIR,'06_LOCAL_CALPHA_SLOPE.png'),'Resolution',180);

%% ---------------- SAVE DIAGNOSTIC MAT ----------------
Diagnostic=struct();
Diagnostic.Version='CMM MF LATERAL PARAMETER DIAGNOSTIC v2.6.2';
Diagnostic.ModelFile=MODEL_MAT;
Diagnostic.InputCSV=INPUT_CSV;
Diagnostic.Reference.Fz0_N=FZ0;
Diagnostic.Reference.P0_psi=P0;
Diagnostic.Reference.IA0_deg=IA0;
Diagnostic.ReferenceBand.FzTol_N=REF_FZ_TOL;
Diagnostic.ReferenceBand.PTol_psi=REF_P_TOL;
Diagnostic.ReferenceBand.IATol_deg=REF_IA_TOL;
Diagnostic.Perturbations_pct=PERTURB_PCT;
Diagnostic.TargetNames=TARGET_NAMES;
Diagnostic.TargetIndices=TARGET_INDEX;
Diagnostic.Baseline=base;
Diagnostic.Results=ResultTable;
Diagnostic.Summary=SummaryTable;
Diagnostic.Note='NO REFIT. NO MODEL PARAMETERS CHANGED. NO MAT FILE OVERWRITTEN.';

save(fullfile(OUTDIR,'PARAMETER_DIAGNOSTIC_v2_6_2.mat'),'Diagnostic','-v7.3');

%% ---------------- TEXT REPORT ----------------
fid=fopen(fullfile(OUTDIR,'PARAMETER_DIAGNOSTIC_REPORT_v2_6_2.txt'),'w');

fprintf(fid,'CMM MF LATERAL PARAMETER DIAGNOSTIC v2.6.2\n');
fprintf(fid,'=========================================\n');
fprintf(fid,'NO REFIT - NO MODEL PARAMETERS CHANGED\n\n');
fprintf(fid,'Model: %s\n',MODEL_MAT);
fprintf(fid,'Database: %s\n',INPUT_CSV);
fprintf(fid,'Reference: Fz=%.2f N, P=%.2f psi, IA=%.2f deg\n\n',FZ0,P0,IA0);

fprintf(fid,'Baseline metrics\n');
fprintf(fid,'Global R2   = %.8f\n',base.R2);
fprintf(fid,'Global RMSE = %.6f N\n',base.RMSE);
fprintf(fid,'Global MAE  = %.6f N\n',base.MAE);
fprintf(fid,'Reference R2   = %.8f\n',base.RefR2);
fprintf(fid,'Reference RMSE = %.6f N\n',base.RefRMSE);
fprintf(fid,'Reference MAE  = %.6f N\n',base.RefMAE);
fprintf(fid,'Reference C-alpha = %.6f N/deg\n',base.Calpha);
fprintf(fid,'Reference peak mu = %.8f\n',base.PeakMu);
fprintf(fid,'Reference peak SA = %.6f deg\n\n',base.PeakSA);

fprintf(fid,'Targeted parameters\n');
for ip=1:Npar
    fprintf(fid,'%s = q(%d) = %.12g\n',TARGET_NAMES{ip}, ...
        TARGET_INDEX(ip),q0(TARGET_INDEX(ip)));
end

fprintf(fid,'\nSummary\n');
for i=1:height(SummaryTable)
    fprintf(fid,'%s | max|dR2|=%.8g | max|dRMSE|=%.4f N | ', ...
        SummaryTable.Parameter(i),SummaryTable.MaxAbsDeltaR2(i), ...
        SummaryTable.MaxAbsDeltaRMSE_N(i));
    fprintf(fid,'max|dCalpha|=%.6f N/deg | max|dmu|=%.6f | max|dSA|=%.6f deg\n', ...
        SummaryTable.MaxAbsDeltaCalpha_N_per_deg(i), ...
        SummaryTable.MaxAbsDeltaPeakMu(i), ...
        SummaryTable.MaxAbsDeltaPeakSA_deg(i));
end

fprintf(fid,'\nC-alpha calculation: central finite difference using %.6f deg step.\n', ...
    CALPHA_STEP_DEG);
fprintf(fid,'All plots use black figure and black axes backgrounds with visible light axes.\n');
fprintf(fid,'NO MAT FILE WAS OVERWRITTEN.\n');
fclose(fid);

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL PARAMETER DIAGNOSTIC v2.6.2 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Baseline R2       : %.6f\n',base.R2);
fprintf('Baseline RMSE     : %.3f N\n',base.RMSE);
fprintf('Baseline C-alpha  : %.3f N/deg\n',base.Calpha);
fprintf('Baseline peak mu  : %.4f\n',base.PeakMu);
fprintf('Baseline peak SA  : %.3f deg\n',base.PeakSA);
fprintf('Output             : %s\n',OUTDIR);
fprintf('NO MODEL PARAMETERS WERE CHANGED.\n');
fprintf('NO MAT FILE WAS OVERWRITTEN.\n');
fprintf('============================================================\n');

end

%% ========================================================================
function printMetrics(m)
% Console helper for the baseline/diagnostic metrics.
fprintf('Global R2       : %.8f\n',m.R2);
fprintf('Global RMSE     : %.3f N\n',m.RMSE);
fprintf('Global MAE      : %.3f N\n',m.MAE);
fprintf('Reference R2    : %.8f\n',m.RefR2);
fprintf('Reference RMSE  : %.3f N\n',m.RefRMSE);
fprintf('Reference MAE   : %.3f N\n',m.RefMAE);
fprintf('Reference C-alpha: %.3f N/deg\n',m.Calpha);
fprintf('Reference peak mu: %.5f\n',m.PeakMu);
fprintf('Reference peak SA: %.3f deg\n',m.PeakSA);
end

%% ========================================================================
function m=evaluateModel(q,a,fz,ia,p,fy,aRef,fzRef,iaRef,pRef,fyRef,Fz0,P0,peakStepDeg,hDeg)

% Global
y=cmmMFglobal(q,a,fz,ia,p,Fz0,P0);
e=fy-y;

m.R2=1-sum(e.^2)/sum((fy-mean(fy)).^2);
m.RMSE=sqrt(mean(e.^2));
m.MAE=mean(abs(e));

% Exact reference
yr=cmmMFglobal(q,aRef,fzRef,iaRef,pRef,Fz0,P0);
er=fyRef-yr;

m.RefR2=1-sum(er.^2)/sum((fyRef-mean(fyRef)).^2);
m.RefRMSE=sqrt(mean(er.^2));
m.RefMAE=mean(abs(er));

% Reference C-alpha in N/deg.
yp=cmmMFglobal(q,hDeg,Fz0,IA0_local(),P0,Fz0,P0);
ym=cmmMFglobal(q,-hDeg,Fz0,IA0_local(),P0,Fz0,P0);
m.Calpha=(yp-ym)/(2*hDeg);

% Reference peak over measured audit domain.
ag=(0:peakStepDeg:12).';
yg=cmmMFglobal(q,ag,Fz0*ones(size(ag)), ...
              zeros(size(ag)),P0*ones(size(ag)),Fz0,P0);

[peakFy,idx]=max(abs(yg));
m.PeakMu=peakFy/Fz0;
m.PeakSA=ag(idx);

end

%% ========================================================================
function y=cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)
% Same CMM v2.x pure-lateral equation used by the validated model.

a=double(alphaDeg)*pi/180;
g=double(camberDeg)*pi/180;
Fz=max(double(Fz),1);
Ppsi=double(Ppsi);

dfz=(Fz-Fz0)./Fz0;
dP=Ppsi-P0;

PCY1=q(1);
PDY1=q(2); PDY2=q(3); PDY3=q(4);
PEY1=q(5); PEY2=q(6);
PKY1=q(7); PKY2=q(8); PKY3=q(9);
PHY1=q(10); PHY2=q(11); PHY3=q(12);
PVY1=q(13); PVY2=q(14); PVY3=q(15); PVY4=q(16);
Pmu1=q(17); Pmu2=q(18); Pk1=q(19);

Cy=PCY1;

mu=(PDY1+PDY2.*dfz).*(1-PDY3.*g.^2);
muP=1+Pmu1.*dP+Pmu2.*dP.^2;
mu=mu.*muP;
mu=max(mu,0.20);

Dy=mu.*Fz;

Ey=PEY1+PEY2.*dfz;
Ey=max(-1.0,min(1.0,Ey));

stiffCamber=max(0.10,1-PKY3.*g.^2);
Ky=PKY1.*Fz0.*sin(2.*atan(Fz./(PKY2.*Fz0))).*stiffCamber;

Ky=Ky.*(1+Pk1.*dP);
Ky=max(Ky,100);

By=Ky./max(Cy.*Dy,1);

Shy=PHY1+PHY2.*dfz+PHY3.*g;

Svy=Fz.*(PVY1+PVY2.*dfz) + ...
    mu.*Fz.*(PVY3+PVY4.*dfz).*g;

alphaY=a+Shy;
x=By.*alphaY;

Fy=Dy.*sin(Cy.*atan(x-Ey.*(x-atan(x))))+Svy;
y=Fy;

end

%% ========================================================================
function makeMetricPlot(R,TARGET_NAMES,xvar,yvar,xlab,ylab,ttl,outfile)

fig=figure('Color','k','Name',ttl);
ax=axes(fig); styleAxes(ax); hold(ax,'on');

for i=1:numel(TARGET_NAMES)
    m=strcmp(R.Parameter,TARGET_NAMES{i});
    x=R{m,xvar};
    y=R{m,yvar};
    plot(ax,x,y,'-o','LineWidth',2,'MarkerSize',6, ...
        'DisplayName',TARGET_NAMES{i});
end

xline(ax,0,'--','HandleVisibility','off');
xlabel(ax,xlab);
ylabel(ax,ylab);
title(ax,ttl);
legend(ax,'Location','best');
exportgraphics(fig,outfile,'Resolution',180);

end

%% ========================================================================
function styleAxes(ax)
% REQUIRED CMM dark plotting style.
set(ax,'Color','k', ...
       'XColor',[0.92 0.92 0.92], ...
       'YColor',[0.92 0.92 0.92], ...
       'GridColor',[0.35 0.35 0.35], ...
       'MinorGridColor',[0.25 0.25 0.25], ...
       'GridAlpha',0.45, ...
       'MinorGridAlpha',0.25, ...
       'FontSize',11);
grid(ax,'on');
box(ax,'on');

t=ax.Title;
t.Color=[0.92 0.92 0.92];

ax.XLabel.Color=[0.92 0.92 0.92];
ax.YLabel.Color=[0.92 0.92 0.92];

end

%% ========================================================================
function v=getNumeric(T,names)

vnames=string(T.Properties.VariableNames);
idx=[];

for k=1:numel(names)
    m=find(strcmpi(vnames,string(names{k})),1);
    if ~isempty(m)
        idx=m;
        break;
    end
end

if isempty(idx)
    fprintf('\nAvailable variables:\n');
    disp(vnames(:));
    error('Required variable not found. Tried: %s',strjoin(string(names),', '));
end

v=T{:,idx};

if iscell(v)
    v=str2double(string(v));
elseif isstring(v)||ischar(v)||iscategorical(v)
    v=str2double(string(v));
end

if ~isnumeric(v)
    error('Variable %s is not numeric.',vnames(idx));
end

v=double(v(:));

end

%% ========================================================================
function s=getStructString(S,name,defaultValue)

if isfield(S,name)
    x=S.(name);
    if ischar(x) || isstring(x)
        s=char(string(x));
    else
        s=defaultValue;
    end
else
    s=defaultValue;
end

end

%% ========================================================================
function x=IA0_local()
% Local helper so evaluateModel remains self-contained.
x=0;
end
