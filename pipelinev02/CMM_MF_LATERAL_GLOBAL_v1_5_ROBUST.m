function CMM_MF_LATERAL_GLOBAL_v1_5_ROBUST
% ================================================================
% CMM MF LATERAL GLOBAL v1.5 ROBUST
% STANDARD MF-TYRE PURE-LATERAL / LOAD + CAMBER + PRESSURE
% ================================================================
%
% PURPOSE
%   Corrected global pure-lateral MF fit for the CMM 7-inch TTC database.
%
%   IMPORTANT FIXES FROM v1.4.1:
%     1) Uses the standard MF-Tyre lateral coefficient structure.
%     2) Uses radians internally for alpha, camber and shifts.
%     3) Correct PKY1 scale: it is the maximum K_y/Fz0 coefficient.
%        The previous v1.4.1 value of PKY1=0.02 was catastrophically
%        too small; the reference data require PKY1 on the order of 40.
%     4) Reference B/C/D/E/Sh from the validated v1.3 fit are used to
%        initialize the global coefficient model.
%     5) Camber sensitivity is allowed enough range to be identifiable
%        over the measured 0 -> 4 deg envelope.
%     6) Pressure is kept as an explicit CMM wrapper.
%     7) Multi-start lsqnonlin is parallelized across workers.
%     8) Fit is weighted in normalized force (Fy/Fz) so high-load data
%        do not completely dominate the condition dependencies.
%
%   This is PURE LATERAL only. No Fx, slip ratio or combined-slip model.
%
% ================================================================

clc;
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL GLOBAL v1.5 ROBUST\n');
fprintf(' STANDARD MF-TYRE PURE-LATERAL / LOAD + CAMBER + PRESSURE\n');
fprintf('============================================================\n\n');

%% ---------------- USER CONTRACT ----------------
INPUT_CSV = 'C:\Users\adity\CMM_GIT\outputs\_PRE_MF_MATRIX_v1_3\TTC_CONDITION_ASSIGNED_DATABASE.csv';

OUTDIR = 'C:\Users\adity\CMM_GIT\outputs\_MF_LATERAL_GLOBAL_v1_5';
if ~exist(OUTDIR,'dir'), mkdir(OUTDIR); end

% Frozen CMM reference condition
FZ0 = 871.5;       % N
P0  = 12.10;       % psi
IA0 = 0.0;         % deg

FZ_TOL = 75.0;
P_TOL  = 0.20;
IA_TOL = 0.20;

ALPHA_MAX_FIT = 12.0;
MIN_FZ_FIT = 180;
MAX_FZ_FIT = 1150;

% Smaller multidimensional bins than v1.4.1.
ALPHA_BIN = 0.05;  % deg
FZ_BIN    = 25;    % N
IA_BIN    = 0.25;  % deg
P_BIN     = 0.50;  % psi

MAX_GLOBAL_POINTS = 30000;

USE_PARALLEL = true;
N_STARTS = 16;

%% ---------------- LOAD DATABASE ----------------
fprintf('[1] INPUT\n%s\n\n',INPUT_CSV);

T = readtable(INPUT_CSV);
fprintf('[2] DATABASE\n');
fprintf('Rows : %d\n',height(T));
fprintf('Vars : %d\n\n',width(T));

SA = getNumeric(T, {'SA_deg','SA','SlipAngle_deg','SlipAngle','Slip_Angle','Alpha'});
FY = getNumeric(T, {'FY_N','FY','Fy','LateralForce','Lateral_Force'});
FZ = getNumeric(T, {'FZ_N','FZ','Fz','VerticalLoad_N','VerticalLoad','Vertical_Load'});
IA = getNumeric(T, {'IA_deg','IA','Camber_deg','Camber','Inclination','CamberAngle'});

if hasVariable(T, {'P_psi','Pressure_psi','InflationPressure_psi'})
    P = getNumeric(T, {'P_psi','Pressure_psi','InflationPressure_psi'});
    fprintf('Pressure mapping : using canonical P_psi\n');
else
    P = getNumeric(T, {'P_kPa','P','Pressure_kPa','Pressure','InflationPressure','Inflation_Pressure'});
    if median(P,'omitnan') > 40
        P = P * 0.1450377377;
        fprintf('Pressure mapping : detected kPa -> converted to psi\n');
    else
        fprintf('Pressure mapping : interpreted as psi\n');
    end
end

% TTC SAE/CMM sign correction retained from v1.3.
FY = -FY;

good = isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)&isfinite(P)&FZ>0;
SA=SA(good); FY=FY(good); FZ=FZ(good); IA=IA(good); P=P(good);

fprintf('Fy multiplier    : -1\n');
fprintf('SA : %.3f -> %.3f deg\n',min(SA),max(SA));
fprintf('FY : %.2f -> %.2f N\n',min(FY),max(FY));
fprintf('FZ : %.2f -> %.2f N\n',min(FZ),max(FZ));
fprintf('IA : %.3f -> %.3f deg\n',min(IA),max(IA));
fprintf('P  : %.2f -> %.2f psi\n\n',min(P),max(P));

%% ---------------- REFERENCE DATA ----------------
ref = abs(FZ-FZ0)<=FZ_TOL & abs(P-P0)<=P_TOL & abs(IA-IA0)<=IA_TOL & ...
      abs(SA)<=ALPHA_MAX_FIT;

fprintf('[3] REFERENCE CONTRACT\n');
fprintf('Fz0 : %.1f N +/- %.1f N\n',FZ0,FZ_TOL);
fprintf('P0  : %.2f psi +/- %.2f psi\n',P0,P_TOL);
fprintf('IA0 : %.1f deg +/- %.1f deg\n',IA0,IA_TOL);
fprintf('Reference samples : %d\n\n',nnz(ref));

if nnz(ref)<500
    error('Reference condition has too few samples.');
end

%% ---------------- FIT DATA ----------------
fitMask = FZ>=MIN_FZ_FIT & FZ<=MAX_FZ_FIT & abs(SA)<=ALPHA_MAX_FIT;

Xraw = [SA(fitMask),FZ(fitMask),IA(fitMask),P(fitMask),FY(fitMask)];
Xfit = binMedianData(Xraw,ALPHA_BIN,FZ_BIN,IA_BIN,P_BIN);

if size(Xfit,1)>MAX_GLOBAL_POINTS
    rng(42);
    Xfit = Xfit(randperm(size(Xfit,1),MAX_GLOBAL_POINTS),:);
end

aFit = Xfit(:,1);
fzFit = Xfit(:,2);
iaFit = Xfit(:,3);
pFit = Xfit(:,4);
fyFit = Xfit(:,5);

fprintf('[4] GLOBAL FIT DATA\n');
fprintf('Binned points : %d\n',numel(fyFit));
fprintf('Fz fit range  : %.1f -> %.1f N\n',min(fzFit),max(fzFit));
fprintf('P fit range   : %.2f -> %.2f psi\n',min(pFit),max(pFit));
fprintf('IA fit range  : %.2f -> %.2f deg\n',min(iaFit),max(iaFit));
fprintf('Alpha range   : %.2f -> %.2f deg\n\n',min(aFit),max(aFit));

%% ---------------- CORRECTED PARAMETERIZATION ----------------
% Parameter vector:
%
%  1 PCY1
%  2 PDY1
%  3 PDY2
%  4 PDY3
%  5 PEY1
%  6 PEY2
%  7 PKY1
%  8 PKY2
%  9 PKY3
% 10 PHY1
% 11 PHY2
% 12 PHY3
% 13 PVY1
% 14 PVY2
% 15 PVY3
% 16 PVY4
% 17 P_MU_1
% 18 P_MU_2
% 19 P_K_1
%
% PEY3 and PEY4 are intentionally fixed to zero initially because the
% current dataset does not robustly identify separate camber-curvature
% terms. They can be unlocked later if the residual structure demands it.

% Validated v1.3 reference:
B0 = 10.925835;
C0 = 1.4562862;
D0 = 2023.049;
E0 = 0.35435126;
Sh0_deg = 0.025991;

K0 = B0*C0*D0;  % N/rad
PKY2_0 = 1.60;
PKY1_0 = K0/(FZ0*sin(2*atan(1/PKY2_0)));

fprintf('[5] INITIALIZATION CHECK\n');
fprintf('Reference K_y      : %.2f N/rad\n',K0);
fprintf('Reference K_y      : %.2f N/deg\n',K0*pi/180);
fprintf('Derived PKY1 init  : %.4f\n',PKY1_0);
fprintf('PKY2 init           : %.4f\n',PKY2_0);
fprintf('Shy init            : %.6f rad (%.6f deg)\n',Sh0_deg*pi/180,Sh0_deg);
fprintf('Expected mu0        : %.5f\n',D0/FZ0);
fprintf('\n');

% Initial load sensitivity is taken from the v1.3 load-slice trend.
p0 = [ ...
    C0, ...              % PCY1
    D0/FZ0, ...          % PDY1
   -0.69, ...             % PDY2
    8.0, ...              % PDY3
    E0, ...               % PEY1
    0.0, ...              % PEY2
    PKY1_0, ...           % PKY1
    PKY2_0, ...           % PKY2
    0.0, ...              % PKY3
    Sh0_deg*pi/180, ...   % PHY1 [rad]
    0.0, ...              % PHY2 [rad]
    0.0, ...              % PHY3 [rad/rad]
    0.0, ...              % PVY1
    0.0, ...              % PVY2
    0.0, ...              % PVY3
    0.0, ...              % PVY4
    0.0, ...              % pressure mu linear
    0.0, ...              % pressure mu quadratic
    0.0];                 % pressure stiffness linear

lb = [ ...
    1.15, ...      % PCY1
    1.70, ...      % PDY1
   -1.50, ...      % PDY2
    0.0, ...       % PDY3
    0.05, ...      % PEY1
   -1.00, ...      % PEY2
   20.0, ...       % PKY1
    0.30, ...      % PKY2
  -20.0, ...       % PKY3
   -0.020, ...     % PHY1 rad
   -0.020, ...     % PHY2 rad
   -0.50, ...      % PHY3
   -0.15, ...      % PVY1
   -0.15, ...      % PVY2
   -1.00, ...      % PVY3
   -1.00, ...      % PVY4
   -0.030, ...     % P_MU_1 / psi
   -0.005, ...     % P_MU_2 / psi^2
   -0.030];        % P_K_1 / psi

ub = [ ...
    1.80, ...
    3.00, ...
    0.50, ...
   40.0, ...
    0.90, ...
    1.00, ...
   80.0, ...
    5.00, ...
   20.0, ...
    0.020, ...
    0.020, ...
    0.50, ...
    0.15, ...
    0.15, ...
    1.00, ...
    1.00, ...
    0.030, ...
    0.005, ...
    0.030];

typicalX = max(abs(p0),[1 2 0.5 8 0.35 0.2 40 1.6 1 0.001 0.001 0.05 ...
                         0.02 0.02 0.2 0.2 0.01 0.001 0.01]);

%% ---------------- PARALLEL MULTI-START ----------------
fprintf('[6] PARALLEL GLOBAL FIT\n');

pool = [];
if USE_PARALLEL && license('test','Distrib_Computing_Toolbox')
    try
        pool = gcp('nocreate');
        if isempty(pool)
            pool = parpool('local');
        end
        fprintf('[MF] Parallel Computing available: %d workers.\n',pool.NumWorkers);
    catch ME
        fprintf('[MF] Parallel pool unavailable: %s\n',ME.message);
    end
end

obj = @(q) globalResidual(q,aFit,fzFit,iaFit,pFit,fyFit,FZ0,P0);

% Build deterministic multi-start set.
rng(2026);
starts = zeros(N_STARTS,numel(p0));
starts(1,:) = p0;

for s=2:N_STARTS
    q = p0;
    span = ub-lb;
    perturb = 0.10*span.*randn(size(q));
    q = q + perturb;
    % Keep some starts close to the validated reference.
    q = max(lb,min(ub,q));
    starts(s,:) = q;
end

results = cell(N_STARTS,1);

if ~isempty(pool) && pool.NumWorkers>1
    parfor s=1:N_STARTS
        results{s} = runOneStart(starts(s,:),lb,ub,typicalX,obj);
    end
else
    for s=1:N_STARTS
        results{s} = runOneStart(starts(s,:),lb,ub,typicalX,obj);
    end
end

costs = inf(N_STARTS,1);
flags = nan(N_STARTS,1);
iters = nan(N_STARTS,1);

for s=1:N_STARTS
    if ~isempty(results{s})
        costs(s)=results{s}.cost;
        flags(s)=results{s}.exitflag;
        iters(s)=results{s}.iterations;
    end
end

[bestCost,bestIdx] = min(costs);
if ~isfinite(bestCost)
    error('All global multi-start fits failed.');
end

best = results{bestIdx};
q = best.q;
residual = best.residual;
exitflag = best.exitflag;
output = best.output;

fprintf('Multi-start results:\n');
for s=1:N_STARTS
    fprintf('  Start %02d | cost %.6g | exit %g | iterations %.0f\n', ...
        s,costs(s),flags(s),iters(s));
end
fprintf('Selected start : %02d\n',bestIdx);
fprintf('Best normalized cost : %.8g\n\n',bestCost);

%% ---------------- GLOBAL VALIDATION ----------------
fyHat = cmmMFglobal(q,aFit,fzFit,iaFit,pFit,FZ0,P0);
err = fyFit-fyHat;

R2 = 1-sum(err.^2)/sum((fyFit-mean(fyFit)).^2);
RMSE = sqrt(mean(err.^2));
MAE = mean(abs(err));

fprintf('[7] GLOBAL VALIDATION\n');
fprintf('Global R2   : %.6f\n',R2);
fprintf('Global RMSE : %.3f N\n',RMSE);
fprintf('Global MAE  : %.3f N\n',MAE);
fprintf('Exit flag   : %g\n',exitflag);

%% ---------------- REFERENCE VALIDATION ----------------
refA=SA(ref); refFz=FZ(ref); refIA=IA(ref); refP=P(ref); refFY=FY(ref);

alphaGrid = linspace(-12,12,481)';
refMF = cmmMFglobal(q,alphaGrid,FZ0*ones(size(alphaGrid)), ...
    IA0*ones(size(alphaGrid)),P0*ones(size(alphaGrid)),FZ0,P0);

refPred = cmmMFglobal(q,refA,refFz,refIA,refP,FZ0,P0);

R2ref = 1-sum((refFY-refPred).^2)/sum((refFY-mean(refFY)).^2);
RMSEref = sqrt(mean((refFY-refPred).^2));
MAEref = mean(abs(refFY-refPred));

h = 1e-5; % rad
ca = (cmmMFglobal(q,h*180/pi,FZ0,IA0,P0,FZ0,P0)- ...
      cmmMFglobal(q,-h*180/pi,FZ0,IA0,P0,FZ0,P0))/(2*h);

pos = alphaGrid>=0;
measGrid = linspace(0,12,241)';
refCurve = nan(size(measGrid));
for k=1:numel(measGrid)
    m = abs(abs(refA)-measGrid(k))<=0.05;
    if nnz(m)>=5
        % Use median absolute force for a clean reference envelope.
        refCurve(k)=median(abs(refFY(m)),'omitnan');
    end
end
valid=isfinite(refCurve);

peakMeasured=max(refCurve(valid));
peakMF=max(abs(refMF(pos)));
peakMuMeasured=peakMeasured/FZ0;
peakMuMF=peakMF/FZ0;

fprintf('\n[8] REFERENCE VALIDATION\n');
fprintf('Reference R2       : %.6f\n',R2ref);
fprintf('Reference RMSE     : %.3f N\n',RMSEref);
fprintf('Reference MAE      : %.3f N\n',MAEref);
fprintf('Reference C-alpha  : %.3f N/deg\n',ca);
fprintf('Measured peak mu   : %.4f\n',peakMuMeasured);
fprintf('Global MF peak mu  : %.4f\n',peakMuMF);

if R2ref < 0.90
    fprintf('WARNING: reference fit is below the acceptance target.\n');
else
    fprintf('Reference fit passes R2 acceptance target (>0.90).\n');
end

%% ---------------- CONDITION METRICS ----------------
loadGrid=[210 432 656 875 1096]';
muLoad=zeros(size(loadGrid));
caLoad=zeros(size(loadGrid));

for k=1:numel(loadGrid)
    fz=loadGrid(k);
    yy=cmmMFglobal(q,measGrid,fz*ones(size(measGrid)), ...
        IA0*ones(size(measGrid)),P0*ones(size(measGrid)),FZ0,P0);
    muLoad(k)=max(abs(yy))/fz;
    caLoad(k)=(cmmMFglobal(q,h*180/pi,fz,0,P0,FZ0,P0)- ...
               cmmMFglobal(q,-h*180/pi,fz,0,P0,FZ0,P0))/(2*h);
end

pressureGrid=[8.1 10.1 12.1 14.1]';
muPressure=zeros(size(pressureGrid));
caPressure=zeros(size(pressureGrid));

for k=1:numel(pressureGrid)
    pp=pressureGrid(k);
    yy=cmmMFglobal(q,measGrid,FZ0*ones(size(measGrid)), ...
        IA0*ones(size(measGrid)),pp*ones(size(measGrid)),FZ0,P0);
    muPressure(k)=max(abs(yy))/FZ0;
    caPressure(k)=(cmmMFglobal(q,h*180/pi,FZ0,0,pp,FZ0,P0)- ...
                   cmmMFglobal(q,-h*180/pi,FZ0,0,pp,FZ0,P0))/(2*h);
end

camberGrid=[0 2 4]';
muCamber=zeros(size(camberGrid));
caCamber=zeros(size(camberGrid));

for k=1:numel(camberGrid)
    gg=camberGrid(k);
    yy=cmmMFglobal(q,measGrid,FZ0*ones(size(measGrid)), ...
        gg*ones(size(measGrid)),P0*ones(size(measGrid)),FZ0,P0);
    muCamber(k)=max(abs(yy))/FZ0;
    caCamber(k)=(cmmMFglobal(q,h*180/pi,FZ0,gg,P0,FZ0,P0)- ...
                 cmmMFglobal(q,-h*180/pi,FZ0,gg,P0,FZ0,P0))/(2*h);
end

%% ---------------- SAVE ----------------
Names={ ...
 'PCY1','PDY1','PDY2','PDY3','PEY1','PEY2', ...
 'PKY1','PKY2','PKY3','PHY1','PHY2','PHY3', ...
 'PVY1','PVY2','PVY3','PVY4','P_MU_1','P_MU_2','P_K_1'};

GlobalMF=struct();
GlobalMF.Version='CMM MF LATERAL GLOBAL v1.5 ROBUST';
GlobalMF.InputCSV=INPUT_CSV;
GlobalMF.Reference.Fz0_N=FZ0;
GlobalMF.Reference.P0_psi=P0;
GlobalMF.Reference.IA0_deg=IA0;
GlobalMF.Parameters=q;
GlobalMF.ParameterNames=Names;
GlobalMF.FixedCoefficients.PEY3=0;
GlobalMF.FixedCoefficients.PEY4=0;
GlobalMF.Metrics.Global.R2=R2;
GlobalMF.Metrics.Global.RMSE_N=RMSE;
GlobalMF.Metrics.Global.MAE_N=MAE;
GlobalMF.Metrics.Reference.R2=R2ref;
GlobalMF.Metrics.Reference.RMSE_N=RMSEref;
GlobalMF.Metrics.Reference.MAE_N=MAEref;
GlobalMF.Metrics.Reference.Calpha_N_per_deg=ca;
GlobalMF.Metrics.Reference.PeakMu_MF=peakMuMF;
GlobalMF.Metrics.Reference.PeakMuMeasured=peakMuMeasured;
GlobalMF.MultiStart.SelectedStart=bestIdx;
GlobalMF.MultiStart.Costs=costs;
GlobalMF.MultiStart.ExitFlags=flags;
GlobalMF.Envelope.Fz_N=[min(FZ) max(FZ)];
GlobalMF.Envelope.P_psi=[min(P) max(P)];
GlobalMF.Envelope.IA_deg=[min(IA) max(IA)];
GlobalMF.Envelope.SA_deg=[min(SA) max(SA)];

save(fullfile(OUTDIR,'CMM_GLOBAL_MF_LATERAL_v1_5.mat'),'GlobalMF');

ParamTable=table(string(Names(:)),q(:),'VariableNames',{'Parameter','Value'});
writetable(ParamTable,fullfile(OUTDIR,'GLOBAL_MF_PARAMETERS.csv'));

MetricTable=table(loadGrid,muLoad,caLoad, ...
    'VariableNames',{'Fz_N','MuPeak','Calpha_N_per_deg'});
writetable(MetricTable,fullfile(OUTDIR,'LOAD_METRICS.csv'));

PressureTable=table(pressureGrid,muPressure,caPressure, ...
    'VariableNames',{'Pressure_psi','MuPeak','Calpha_N_per_deg'});
writetable(PressureTable,fullfile(OUTDIR,'PRESSURE_METRICS.csv'));

CamberTable=table(camberGrid,muCamber,caCamber, ...
    'VariableNames',{'Camber_deg','MuPeak','Calpha_N_per_deg'});
writetable(CamberTable,fullfile(OUTDIR,'CAMBER_METRICS.csv'));

%% ---------------- PLOTS ----------------
fprintf('\n[9] FIGURES\n');

% Reference curve
fig1=figure('Color','k','Name','CMM v1.5 Reference MF');
ax=axes(fig1); styleAxes(ax);
plot(ax,abs(refA),abs(refFY),'.','Color',[.2 .6 1]); hold(ax,'on');
plot(ax,abs(alphaGrid),abs(refMF),'LineWidth',2,'Color',[1 .6 .1]);
xlabel(ax,'|\alpha| [deg]'); ylabel(ax,'|F_y| [N]');
title(ax,sprintf('Reference MF | R^2=%.4f | RMSE=%.1f N',R2ref,RMSEref));
legend(ax,'Measured','Global MF','Location','southeast');
exportgraphics(fig1,fullfile(OUTDIR,'01_REFERENCE_GLOBAL_MF.png'),'Resolution',180);

% Global binned data at their actual conditions
fig2=figure('Color','k','Name','CMM v1.5 Global Data');
ax=axes(fig2); styleAxes(ax);
scatter(ax,aFit,fyFit,8,'o','MarkerEdgeColor',[.2 .6 1], ...
    'MarkerFaceColor','none'); hold(ax,'on');
% Reference prediction overlaid for orientation only.
ag=linspace(-12,12,481)';
yg=cmmMFglobal(q,ag,FZ0*ones(size(ag)),IA0*ones(size(ag)),P0*ones(size(ag)),FZ0,P0);
plot(ax,ag,yg,'LineWidth',2,'Color',[1 .6 .1]);
xlabel(ax,'Slip angle [deg]'); ylabel(ax,'F_y [N]');
title(ax,sprintf('Global Data + Reference Operating Curve | R^2=%.4f',R2));
legend(ax,'Binned data','Reference condition MF','Location','southeast');
exportgraphics(fig2,fullfile(OUTDIR,'02_GLOBAL_DATA_AND_REFERENCE.png'),'Resolution',180);

% Residual
fig3=figure('Color','k','Name','CMM v1.5 Residual');
ax=axes(fig3); styleAxes(ax);
scatter(ax,aFit,err,8,'filled'); hold(ax,'on'); yline(ax,0,'--');
xlabel(ax,'Slip angle [deg]'); ylabel(ax,'Measured - MF [N]');
title(ax,'Global MF Residual');
exportgraphics(fig3,fullfile(OUTDIR,'03_GLOBAL_RESIDUAL.png'),'Resolution',180);

% Load sensitivity
fig4=figure('Color','k','Name','CMM v1.5 Load Sensitivity');
ax=axes(fig4); styleAxes(ax);
yyaxis(ax,'left'); plot(ax,loadGrid,muLoad,'-o','LineWidth',2); ylabel(ax,'\mu_{peak}');
yyaxis(ax,'right'); plot(ax,loadGrid,caLoad,'-s','LineWidth',2); ylabel(ax,'C_\alpha [N/deg]');
xlabel(ax,'F_z [N]'); title(ax,'Global MF Load Sensitivity'); grid(ax,'on');
exportgraphics(fig4,fullfile(OUTDIR,'04_LOAD_SENSITIVITY.png'),'Resolution',180);

% Pressure sensitivity
fig5=figure('Color','k','Name','CMM v1.5 Pressure Sensitivity');
ax=axes(fig5); styleAxes(ax);
yyaxis(ax,'left'); plot(ax,pressureGrid,muPressure,'-o','LineWidth',2); ylabel(ax,'\mu_{peak}');
yyaxis(ax,'right'); plot(ax,pressureGrid,caPressure,'-s','LineWidth',2); ylabel(ax,'C_\alpha [N/deg]');
xlabel(ax,'Pressure [psi]'); title(ax,'Global MF Pressure Sensitivity'); grid(ax,'on');
exportgraphics(fig5,fullfile(OUTDIR,'05_PRESSURE_SENSITIVITY.png'),'Resolution',180);

% Camber sensitivity
fig6=figure('Color','k','Name','CMM v1.5 Camber Sensitivity');
ax=axes(fig6); styleAxes(ax);
yyaxis(ax,'left'); plot(ax,camberGrid,muCamber,'-o','LineWidth',2); ylabel(ax,'\mu_{peak}');
yyaxis(ax,'right'); plot(ax,camberGrid,caCamber,'-s','LineWidth',2); ylabel(ax,'C_\alpha [N/deg]');
xlabel(ax,'Camber / IA [deg]'); title(ax,'Global MF Camber Sensitivity'); grid(ax,'on');
exportgraphics(fig6,fullfile(OUTDIR,'06_CAMBER_SENSITIVITY.png'),'Resolution',180);

%% ---------------- AUDIT ----------------
fid=fopen(fullfile(OUTDIR,'GLOBAL_MF_AUDIT_REPORT.txt'),'w');
fprintf(fid,'CMM MF LATERAL GLOBAL v1.5 ROBUST AUDIT\n');
fprintf(fid,'========================================\n');
fprintf(fid,'Input: %s\n',INPUT_CSV);
fprintf(fid,'Reference: Fz0=%.3f N, P0=%.3f psi, IA0=%.3f deg\n',FZ0,P0,IA0);
fprintf(fid,'\nGlobal R2: %.8f\nGlobal RMSE: %.6f N\nGlobal MAE: %.6f N\n',R2,RMSE,MAE);
fprintf(fid,'Reference R2: %.8f\nReference RMSE: %.6f N\nReference MAE: %.6f N\n',R2ref,RMSEref,MAEref);
fprintf(fid,'Reference C-alpha: %.6f N/deg\n',ca);
fprintf(fid,'Reference measured peak mu: %.8f\nReference MF peak mu: %.8f\n',peakMuMeasured,peakMuMF);
fprintf(fid,'Selected multi-start: %d\n',bestIdx);
fprintf(fid,'\nParameter list:\n');
for k=1:numel(q)
    fprintf(fid,'%s = %.12g\n',Names{k},q(k));
end
fprintf(fid,'\nFixed: PEY3=0, PEY4=0\n');
fprintf(fid,'No longitudinal/braking data available; pure lateral only.\n');
fprintf(fid,'No validated negative-camber data in supplied database.\n');
fprintf(fid,'Pressure terms are a CMM wrapper and are not standard MF-Tyre .tir coefficients.\n');
fclose(fid);

fprintf('\n[10] OUTPUT\n');
pngs=dir(fullfile(OUTDIR,'*.png'));
fprintf('PNG files present : %d\n',numel(pngs));
fprintf('MAT/CSV/audit files saved.\n');
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL GLOBAL v1.5 ROBUST COMPLETE\n');
fprintf('============================================================\n');
fprintf('Global R2           : %.6f\n',R2);
fprintf('Global RMSE         : %.2f N\n',RMSE);
fprintf('Reference R2        : %.6f\n',R2ref);
fprintf('Reference C-alpha   : %.2f N/deg\n',ca);
fprintf('Reference peak mu   : %.4f\n',peakMuMF);
fprintf('Parallel starts     : %d\n',N_STARTS);
fprintf('Longitudinal model  : NOT AVAILABLE\n');
fprintf('.tir generation     : BLOCKED until validation passes\n');
fprintf('Output              : %s\n',OUTDIR);
fprintf('============================================================\n');

end

%% ========================================================================
function result=runOneStart(q0,lb,ub,typicalX,obj)
result=[];
try
    opts=optimoptions('lsqnonlin', ...
        'Display','off', ...
        'MaxIterations',800, ...
        'MaxFunctionEvaluations',30000, ...
        'FunctionTolerance',1e-10, ...
        'StepTolerance',1e-10, ...
        'OptimalityTolerance',1e-8, ...
        'TypicalX',typicalX, ...
        'FiniteDifferenceType','forward');
    [q,resnorm,residual,exitflag,output]=lsqnonlin(obj,q0,lb,ub,opts);
    result.q=q;
    result.cost=resnorm;
    result.residual=residual;
    result.exitflag=exitflag;
    result.output=output;
    result.iterations=output.iterations;
catch
    % Failed starts remain empty and are ignored by the master.
end
end

%% ========================================================================
function y=cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)
% Standard MF-Tyre pure-lateral equation.
% Alpha and camber are converted to radians before entering the MF formula.

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

% Keep friction positive inside the measured envelope.
mu=max(mu,0.20);

Dy=mu.*Fz;

% PEY3/PEY4 fixed at zero in this robust first global model.
Ey=PEY1+PEY2.*dfz;
Ey=max(-1.0,min(1.0,Ey));

% Standard MF-Tyre stiffness structure.
stiffCamber=max(0.10,1-PKY3.*g.^2);
Ky=PKY1.*Fz0.*sin(2.*atan(Fz./(PKY2.*Fz0))).*stiffCamber;

% CMM pressure wrapper for stiffness.
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
function r=globalResidual(q,a,fz,ia,p,fy,Fz0,P0)
pred=cmmMFglobal(q,a,fz,ia,p,Fz0,P0);

% Normalize by Fz so each load level contributes comparably in friction
% coefficient space. Small floor avoids excessive low-load weighting.
scale=max(fz,250);
r=(pred-fy)./scale;
r(~isfinite(r))=1e3;
end

%% ========================================================================
function X=binMedianData(A,da,dfz,dia,dp)
if isempty(A), X=A; return; end

k1=round(A(:,1)/da);
k2=round(A(:,2)/dfz);
k3=round(A(:,3)/dia);
k4=round(A(:,4)/dp);

[~,~,ic]=unique([k1 k2 k3 k4],'rows');
n=max(ic);
X=zeros(n,5);

for j=1:n
    m=(ic==j);
    X(j,1)=median(A(m,1),'omitnan');
    X(j,2)=median(A(m,2),'omitnan');
    X(j,3)=median(A(m,3),'omitnan');
    X(j,4)=median(A(m,4),'omitnan');
    X(j,5)=median(A(m,5),'omitnan');
end

X=X(all(isfinite(X),2),:);
end

%% ========================================================================
function tf=hasVariable(T,names)
vnames=string(T.Properties.VariableNames);
tf=false;
for k=1:numel(names)
    if any(strcmpi(vnames,string(names{k})))
        tf=true;
        return;
    end
end
end

%% ========================================================================
function x=getNumeric(T,names)
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
    fprintf('\nAvailable table variables:\n');
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

x=double(v(:));
end

%% ========================================================================
function styleAxes(ax)
ax.Color='k';
ax.XColor=[.95 .95 .95];
ax.YColor=[.95 .95 .95];
ax.GridColor=[.2 .2 .2];
ax.MinorGridColor=[.15 .15 .15];
ax.GridAlpha=.35;
grid(ax,'on');
end
