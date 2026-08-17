function CMM_MF_LATERAL_GLOBAL_v1_5_1
% ================================================================
% CMM MF LATERAL GLOBAL v1.5.1
% REFERENCE-ANCHORED / CONDITION-WEIGHTED / PARALLEL
% STANDARD MF-TYRE PURE-LATERAL + CMM LOAD/CAMBER/PRESSURE WRAPPER
% ================================================================
%
% PURPOSE
%   Build a global pure-lateral tyre model while protecting the
%   validated CMM reference-condition curve from being diluted by
%   the much larger multidimensional database.
%
% KEY CHANGES FROM v1.5
%   1) Reference condition is explicitly weighted in the optimizer.
%   2) Global fit and reference fit are both included in the objective.
%   3) C-alpha unit conversion is fixed: internal N/rad, reported N/deg.
%   4) Reference-condition peak force is explicitly checked.
%   5) Condition-wise validation is added for load, pressure and camber.
%   6) Parallel multi-start fitting is retained.
%   7) Validation uses actual measured-condition subsets where possible.
%
% PURE LATERAL ONLY. No Fx, slip ratio or combined-slip model.
% ================================================================

clc;
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL GLOBAL v1.5.1\n');
fprintf(' REFERENCE-ANCHORED / CONDITION-WEIGHTED / PARALLEL\n');
fprintf('============================================================\n\n');

%% ---------------- USER CONTRACT ----------------
INPUT_CSV = 'C:\Users\adity\CMM\all tests are here\_PRE_MF_MATRIX_v1_3\TTC_CONDITION_ASSIGNED_DATABASE.csv';
OUTDIR = 'C:\Users\adity\CMM\all tests are here\_MF_LATERAL_GLOBAL_v1_5_1';
if ~exist(OUTDIR,'dir'), mkdir(OUTDIR); end

FZ0 = 871.5;
P0  = 12.10;
IA0 = 0.0;

FZ_TOL = 75.0;
P_TOL  = 0.20;
IA_TOL = 0.20;

ALPHA_MAX_FIT = 12.0;
MIN_FZ_FIT = 180;
MAX_FZ_FIT = 1150;

ALPHA_BIN = 0.05;
FZ_BIN    = 25;
IA_BIN    = 0.25;
P_BIN     = 0.50;

MAX_GLOBAL_POINTS = 30000;

USE_PARALLEL = true;
N_STARTS = 16;

% Reference objective weight.
% 1.0 = equal point density after normalization.
% 2.0 = strong reference protection.
% 3.0 = very strong reference protection.
REFERENCE_WEIGHT = 3.0;

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

% TTC SAE/CMM sign convention retained.
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

%% ---------------- GLOBAL FIT DATA ----------------
fitMask = FZ>=MIN_FZ_FIT & FZ<=MAX_FZ_FIT & abs(SA)<=ALPHA_MAX_FIT;

Xraw = [SA(fitMask),FZ(fitMask),IA(fitMask),P(fitMask),FY(fitMask)];
Xfit = binMedianData(Xraw,ALPHA_BIN,FZ_BIN,IA_BIN,P_BIN);

if size(Xfit,1)>MAX_GLOBAL_POINTS
    rng(42);
    Xfit = Xfit(randperm(size(Xfit,1),MAX_GLOBAL_POINTS),:);
end

aFit  = Xfit(:,1);
fzFit = Xfit(:,2);
iaFit = Xfit(:,3);
pFit  = Xfit(:,4);
fyFit = Xfit(:,5);

% Reference points are separately binned for a stable, condition-specific
% objective. This prevents the reference condition from being represented
% only by the random global bin sample.
XrefRaw = [SA(ref),FZ(ref),IA(ref),P(ref),FY(ref)];
XrefFit = binMedianData(XrefRaw,0.05,10,0.10,0.10);

aRefFit  = XrefFit(:,1);
fzRefFit = XrefFit(:,2);
iaRefFit = XrefFit(:,3);
pRefFit  = XrefFit(:,4);
fyRefFit = XrefFit(:,5);

fprintf('[4] GLOBAL FIT DATA\n');
fprintf('Binned global points     : %d\n',numel(fyFit));
fprintf('Binned reference points  : %d\n',numel(fyRefFit));
fprintf('Fz fit range             : %.1f -> %.1f N\n',min(fzFit),max(fzFit));
fprintf('P fit range              : %.2f -> %.2f psi\n',min(pFit),max(pFit));
fprintf('IA fit range              : %.2f -> %.2f deg\n',min(iaFit),max(iaFit));
fprintf('Alpha range               : %.2f -> %.2f deg\n\n',min(aFit),max(aFit));

%% ---------------- INITIALIZATION ----------------
B0 = 10.925835;
C0 = 1.4562862;
D0 = 2023.049;
E0 = 0.35435126;
Sh0_deg = 0.025991;

K0 = B0*C0*D0;                         % N/rad
PKY2_0 = 1.60;
PKY1_0 = K0/(FZ0*sin(2*atan(1/PKY2_0)));

fprintf('[5] INITIALIZATION CHECK\n');
fprintf('Reference K_y          : %.2f N/rad\n',K0);
fprintf('Reference K_y          : %.2f N/deg\n',K0*pi/180);
fprintf('Derived PKY1 init      : %.4f\n',PKY1_0);
fprintf('PKY2 init              : %.4f\n',PKY2_0);
fprintf('Shy init               : %.6f rad (%.6f deg)\n',Sh0_deg*pi/180,Sh0_deg);
fprintf('Expected mu0           : %.5f\n',D0/FZ0);
fprintf('\n');

p0 = [ ...
    C0, ...
    D0/FZ0, ...
   -0.69, ...
    8.0, ...
    E0, ...
    0.0, ...
    PKY1_0, ...
    PKY2_0, ...
    0.0, ...
    Sh0_deg*pi/180, ...
    0.0, ...
    0.0, ...
    0.0, ...
    0.0, ...
    0.0, ...
    0.0, ...
    0.0, ...
    0.0, ...
    0.0];

lb = [ ...
    1.15, 1.70, -1.50, 0.0, 0.05, -1.00, ...
   20.0, 0.30, -20.0, -0.020, -0.020, -0.50, ...
   -0.15, -0.15, -1.00, -1.00, -0.030, -0.005, -0.030];

ub = [ ...
    1.80, 3.00, 0.50, 40.0, 0.90, 1.00, ...
   80.0, 5.00, 20.0, 0.020, 0.020, 0.50, ...
    0.15, 0.15, 1.00, 1.00, 0.030, 0.005, 0.030];

typicalX = max(abs(p0),[1 2 0.5 8 0.35 0.2 40 1.6 1 0.001 0.001 0.05 ...
                         0.02 0.02 0.2 0.2 0.01 0.001 0.01]);

%% ---------------- PARALLEL MULTI-START ----------------
fprintf('[6] PARALLEL REFERENCE-ANCHORED GLOBAL FIT\n');

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

obj = @(q) globalResidualWeighted(q, ...
    aFit,fzFit,iaFit,pFit,fyFit, ...
    aRefFit,fzRefFit,iaRefFit,pRefFit,fyRefFit, ...
    FZ0,P0,REFERENCE_WEIGHT);

rng(2026);
starts = zeros(N_STARTS,numel(p0));
starts(1,:) = p0;

for s=2:N_STARTS
    q0 = p0;
    span = ub-lb;
    perturb = 0.10*span.*randn(size(q0));
    q0 = q0 + perturb;
    q0 = max(lb,min(ub,q0));
    starts(s,:) = q0;
end

results = cell(N_STARTS,1);

if ~isempty(pool) && pool.NumWorkers>1
    parfor s=1:N_STARTS
        results{s}=runOneStart(starts(s,:),lb,ub,typicalX,obj);
    end
else
    for s=1:N_STARTS
        results{s}=runOneStart(starts(s,:),lb,ub,typicalX,obj);
    end
end

costs=inf(N_STARTS,1);
flags=nan(N_STARTS,1);
iters=nan(N_STARTS,1);

for s=1:N_STARTS
    if ~isempty(results{s})
        costs(s)=results{s}.cost;
        flags(s)=results{s}.exitflag;
        iters(s)=results{s}.iterations;
    end
end

[bestCost,bestIdx]=min(costs);
if ~isfinite(bestCost)
    error('All global multi-start fits failed.');
end

best=results{bestIdx};
q=best.q;
exitflag=best.exitflag;
output=best.output;

fprintf('Multi-start results:\n');
for s=1:N_STARTS
    fprintf('  Start %02d | cost %.6g | exit %g | iterations %.0f\n', ...
        s,costs(s),flags(s),iters(s));
end
fprintf('Selected start       : %02d\n',bestIdx);
fprintf('Best weighted cost   : %.8g\n\n',bestCost);

%% ---------------- GLOBAL VALIDATION ----------------
fyHatFit=cmmMFglobal(q,aFit,fzFit,iaFit,pFit,FZ0,P0);
errFit=fyFit-fyHatFit;

R2=1-sum(errFit.^2)/sum((fyFit-mean(fyFit)).^2);
RMSE=sqrt(mean(errFit.^2));
MAE=mean(abs(errFit));

%% ---------------- REFERENCE VALIDATION ----------------
refA=SA(ref); refFz=FZ(ref); refIA=IA(ref); refP=P(ref); refFY=FY(ref);

refPred=cmmMFglobal(q,refA,refFz,refIA,refP,FZ0,P0);
refErr=refFY-refPred;

R2ref=1-sum(refErr.^2)/sum((refFY-mean(refFY)).^2);
RMSEref=sqrt(mean(refErr.^2));
MAEref=mean(abs(refErr));

h=1e-5; % radians
caRad=(cmmMFglobal(q,h*180/pi,FZ0,IA0,P0,FZ0,P0)- ...
       cmmMFglobal(q,-h*180/pi,FZ0,IA0,P0,FZ0,P0))/(2*h);
caDeg=caRad*pi/180;  % CORRECT: N/rad -> N/deg

alphaGrid=linspace(-12,12,481)';
refMF=cmmMFglobal(q,alphaGrid,FZ0*ones(size(alphaGrid)), ...
    IA0*ones(size(alphaGrid)),P0*ones(size(alphaGrid)),FZ0,P0);

pos=alphaGrid>=0;
measGrid=linspace(0,12,241)';
refCurve=nan(size(measGrid));

for k=1:numel(measGrid)
    m=abs(abs(refA)-measGrid(k))<=0.05;
    if nnz(m)>=5
        refCurve(k)=median(abs(refFY(m)),'omitnan');
    end
end

valid=isfinite(refCurve);
peakMeasured=max(refCurve(valid));
peakMF=max(abs(refMF(pos)));
peakMuMeasured=peakMeasured/FZ0;
peakMuMF=peakMF/FZ0;

fprintf('[7] VALIDATION\n');
fprintf('Global R2              : %.6f\n',R2);
fprintf('Global RMSE            : %.3f N\n',RMSE);
fprintf('Global MAE             : %.3f N\n',MAE);
fprintf('Reference R2           : %.6f\n',R2ref);
fprintf('Reference RMSE         : %.3f N\n',RMSEref);
fprintf('Reference MAE          : %.3f N\n',MAEref);
fprintf('Reference C-alpha      : %.3f N/rad\n',caRad);
fprintf('Reference C-alpha      : %.3f N/deg\n',caDeg);
fprintf('Measured peak mu       : %.4f\n',peakMuMeasured);
fprintf('Global MF peak mu      : %.4f\n',peakMuMF);

%% ---------------- CONDITION VALIDATION ----------------
loadGrid=[210 432 656 875 1096]';
muLoad=zeros(size(loadGrid));
caLoad=zeros(size(loadGrid));
r2Load=nan(size(loadGrid));
rmseLoad=nan(size(loadGrid));

for k=1:numel(loadGrid)
    fz=loadGrid(k);

    yy=cmmMFglobal(q,measGrid,fz*ones(size(measGrid)), ...
        IA0*ones(size(measGrid)),P0*ones(size(measGrid)),FZ0,P0);

    muLoad(k)=max(abs(yy))/fz;

    caLoad(k)=(cmmMFglobal(q,h*180/pi,fz,0,P0,FZ0,P0)- ...
               cmmMFglobal(q,-h*180/pi,fz,0,P0,FZ0,P0))/(2*h)*pi/180;

    m=abs(FZ-fz)<=25 & abs(P-P0)<=0.35 & abs(IA-IA0)<=0.25 & abs(SA)<=12;
    if nnz(m)>=100
        yp=cmmMFglobal(q,SA(m),FZ(m),IA(m),P(m),FZ0,P0);
        ee=FY(m)-yp;
        r2Load(k)=1-sum(ee.^2)/sum((FY(m)-mean(FY(m))).^2);
        rmseLoad(k)=sqrt(mean(ee.^2));
    end
end

pressureGrid=[8.1 10.1 12.1 14.1]';
muPressure=zeros(size(pressureGrid));
caPressure=zeros(size(pressureGrid));
r2Pressure=nan(size(pressureGrid));
rmsePressure=nan(size(pressureGrid));

for k=1:numel(pressureGrid)
    pp=pressureGrid(k);

    yy=cmmMFglobal(q,measGrid,FZ0*ones(size(measGrid)), ...
        IA0*ones(size(measGrid)),pp*ones(size(measGrid)),FZ0,P0);

    muPressure(k)=max(abs(yy))/FZ0;

    caPressure(k)=(cmmMFglobal(q,h*180/pi,FZ0,0,pp,FZ0,P0)- ...
                   cmmMFglobal(q,-h*180/pi,FZ0,0,pp,FZ0,P0))/(2*h)*pi/180;

    m=abs(P-pp)<=0.35 & abs(FZ-FZ0)<=75 & abs(IA-IA0)<=0.25 & abs(SA)<=12;
    if nnz(m)>=100
        yp=cmmMFglobal(q,SA(m),FZ(m),IA(m),P(m),FZ0,P0);
        ee=FY(m)-yp;
        r2Pressure(k)=1-sum(ee.^2)/sum((FY(m)-mean(FY(m))).^2);
        rmsePressure(k)=sqrt(mean(ee.^2));
    end
end

camberGrid=[0 2 4]';
muCamber=zeros(size(camberGrid));
caCamber=zeros(size(camberGrid));
r2Camber=nan(size(camberGrid));
rmseCamber=nan(size(camberGrid));

for k=1:numel(camberGrid)
    gg=camberGrid(k);

    yy=cmmMFglobal(q,measGrid,FZ0*ones(size(measGrid)), ...
        gg*ones(size(measGrid)),P0*ones(size(measGrid)),FZ0,P0);

    muCamber(k)=max(abs(yy))/FZ0;

    caCamber(k)=(cmmMFglobal(q,h*180/pi,FZ0,gg,P0,FZ0,P0)- ...
                 cmmMFglobal(q,-h*180/pi,FZ0,gg,P0,FZ0,P0))/(2*h)*pi/180;

    m=abs(IA-gg)<=0.25 & abs(FZ-FZ0)<=75 & abs(P-P0)<=0.35 & abs(SA)<=12;
    if nnz(m)>=100
        yp=cmmMFglobal(q,SA(m),FZ(m),IA(m),P(m),FZ0,P0);
        ee=FY(m)-yp;
        r2Camber(k)=1-sum(ee.^2)/sum((FY(m)-mean(FY(m))).^2);
        rmseCamber(k)=sqrt(mean(ee.^2));
    end
end

%% ---------------- ACCEPTANCE ----------------
referencePass = R2ref >= 0.90 && RMSEref <= 150;
globalPass = R2 >= 0.95;

if referencePass && globalPass
    status='PASS';
else
    status='REVIEW';
end

fprintf('\n[8] ACCEPTANCE\n');
fprintf('Global acceptance       : %s\n',ternary(globalPass,'PASS','REVIEW'));
fprintf('Reference acceptance    : %s\n',ternary(referencePass,'PASS','REVIEW'));
fprintf('Overall model status    : %s\n',status);

%% ---------------- SAVE ----------------
Names={ ...
 'PCY1','PDY1','PDY2','PDY3','PEY1','PEY2', ...
 'PKY1','PKY2','PKY3','PHY1','PHY2','PHY3', ...
 'PVY1','PVY2','PVY3','PVY4','P_MU_1','P_MU_2','P_K_1'};

GlobalMF=struct();
GlobalMF.Version='CMM MF LATERAL GLOBAL v1.5.1';
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
GlobalMF.Metrics.Reference.Calpha_N_per_rad=caRad;
GlobalMF.Metrics.Reference.Calpha_N_per_deg=caDeg;
GlobalMF.Metrics.Reference.PeakMu_MF=peakMuMF;
GlobalMF.Metrics.Reference.PeakMuMeasured=peakMuMeasured;

GlobalMF.Validation.Load.Fz_N=loadGrid;
GlobalMF.Validation.Load.R2=r2Load;
GlobalMF.Validation.Load.RMSE_N=rmseLoad;
GlobalMF.Validation.Load.MuPeak=muLoad;
GlobalMF.Validation.Load.Calpha_N_per_deg=caLoad;

GlobalMF.Validation.Pressure.Psi=pressureGrid;
GlobalMF.Validation.Pressure.R2=r2Pressure;
GlobalMF.Validation.Pressure.RMSE_N=rmsePressure;
GlobalMF.Validation.Pressure.MuPeak=muPressure;
GlobalMF.Validation.Pressure.Calpha_N_per_deg=caPressure;

GlobalMF.Validation.Camber.Deg=camberGrid;
GlobalMF.Validation.Camber.R2=r2Camber;
GlobalMF.Validation.Camber.RMSE_N=rmseCamber;
GlobalMF.Validation.Camber.MuPeak=muCamber;
GlobalMF.Validation.Camber.Calpha_N_per_deg=caCamber;

GlobalMF.MultiStart.SelectedStart=bestIdx;
GlobalMF.MultiStart.Costs=costs;
GlobalMF.MultiStart.ExitFlags=flags;

GlobalMF.Envelope.Fz_N=[min(FZ) max(FZ)];
GlobalMF.Envelope.P_psi=[min(P) max(P)];
GlobalMF.Envelope.IA_deg=[min(IA) max(IA)];
GlobalMF.Envelope.SA_deg=[min(SA) max(SA)];

GlobalMF.Acceptance.Status=status;
GlobalMF.Acceptance.ReferencePass=referencePass;
GlobalMF.Acceptance.GlobalPass=globalPass;

save(fullfile(OUTDIR,'CMM_GLOBAL_MF_LATERAL_v1_5_1.mat'),'GlobalMF');

ParamTable=table(string(Names(:)),q(:),'VariableNames',{'Parameter','Value'});
writetable(ParamTable,fullfile(OUTDIR,'GLOBAL_MF_PARAMETERS.csv'));

LoadTable=table(loadGrid,muLoad,caLoad,r2Load,rmseLoad, ...
    'VariableNames',{'Fz_N','MuPeak','Calpha_N_per_deg','R2','RMSE_N'});
writetable(LoadTable,fullfile(OUTDIR,'LOAD_VALIDATION.csv'));

PressureTable=table(pressureGrid,muPressure,caPressure,r2Pressure,rmsePressure, ...
    'VariableNames',{'Pressure_psi','MuPeak','Calpha_N_per_deg','R2','RMSE_N'});
writetable(PressureTable,fullfile(OUTDIR,'PRESSURE_VALIDATION.csv'));

CamberTable=table(camberGrid,muCamber,caCamber,r2Camber,rmseCamber, ...
    'VariableNames',{'Camber_deg','MuPeak','Calpha_N_per_deg','R2','RMSE_N'});
writetable(CamberTable,fullfile(OUTDIR,'CAMBER_VALIDATION.csv'));

%% ---------------- PLOTS ----------------
fprintf('\n[9] FIGURES\n');

fig1=figure('Color','k','Name','CMM v1.5.1 Reference MF');
ax=axes(fig1); styleAxes(ax);
plot(ax,abs(refA),abs(refFY),'.','Color',[.2 .6 1]); hold(ax,'on');
plot(ax,abs(alphaGrid),abs(refMF),'LineWidth',2,'Color',[1 .6 .1]);
xlabel(ax,'|\alpha| [deg]'); ylabel(ax,'|F_y| [N]');
title(ax,sprintf('Reference MF | R^2=%.4f | RMSE=%.1f N',R2ref,RMSEref));
legend(ax,'Measured','Global MF','Location','southeast');
exportgraphics(fig1,fullfile(OUTDIR,'01_REFERENCE_GLOBAL_MF.png'),'Resolution',180);

fig2=figure('Color','k','Name','CMM v1.5.1 Global Data');
ax=axes(fig2); styleAxes(ax);
scatter(ax,aFit,fyFit,8,'o','MarkerEdgeColor',[.2 .6 1], ...
    'MarkerFaceColor','none'); hold(ax,'on');
ag=linspace(-12,12,481)';
yg=cmmMFglobal(q,ag,FZ0*ones(size(ag)),IA0*ones(size(ag)),P0*ones(size(ag)),FZ0,P0);
plot(ax,ag,yg,'LineWidth',2,'Color',[1 .6 .1]);
xlabel(ax,'Slip angle [deg]'); ylabel(ax,'F_y [N]');
title(ax,sprintf('Global Data + Reference Operating Curve | R^2=%.4f',R2));
legend(ax,'Binned data','Reference condition MF','Location','southeast');
exportgraphics(fig2,fullfile(OUTDIR,'02_GLOBAL_DATA_AND_REFERENCE.png'),'Resolution',180);

fig3=figure('Color','k','Name','CMM v1.5.1 Residual');
ax=axes(fig3); styleAxes(ax);
scatter(ax,aFit,errFit,8,'filled'); hold(ax,'on'); yline(ax,0,'--');
xlabel(ax,'Slip angle [deg]'); ylabel(ax,'Measured - MF [N]');
title(ax,'Global MF Residual');
exportgraphics(fig3,fullfile(OUTDIR,'03_GLOBAL_RESIDUAL.png'),'Resolution',180);

fig4=figure('Color','k','Name','CMM v1.5.1 Load Sensitivity');
ax=axes(fig4); styleAxes(ax);
yyaxis(ax,'left'); plot(ax,loadGrid,muLoad,'-o','LineWidth',2); ylabel(ax,'\mu_{peak}');
yyaxis(ax,'right'); plot(ax,loadGrid,caLoad,'-s','LineWidth',2); ylabel(ax,'C_\alpha [N/deg]');
xlabel(ax,'F_z [N]'); title(ax,'Global MF Load Sensitivity'); grid(ax,'on');
exportgraphics(fig4,fullfile(OUTDIR,'04_LOAD_SENSITIVITY.png'),'Resolution',180);

fig5=figure('Color','k','Name','CMM v1.5.1 Pressure Sensitivity');
ax=axes(fig5); styleAxes(ax);
yyaxis(ax,'left'); plot(ax,pressureGrid,muPressure,'-o','LineWidth',2); ylabel(ax,'\mu_{peak}');
yyaxis(ax,'right'); plot(ax,pressureGrid,caPressure,'-s','LineWidth',2); ylabel(ax,'C_\alpha [N/deg]');
xlabel(ax,'Pressure [psi]'); title(ax,'Global MF Pressure Sensitivity'); grid(ax,'on');
exportgraphics(fig5,fullfile(OUTDIR,'05_PRESSURE_SENSITIVITY.png'),'Resolution',180);

fig6=figure('Color','k','Name','CMM v1.5.1 Camber Sensitivity');
ax=axes(fig6); styleAxes(ax);
yyaxis(ax,'left'); plot(ax,camberGrid,muCamber,'-o','LineWidth',2); ylabel(ax,'\mu_{peak}');
yyaxis(ax,'right'); plot(ax,camberGrid,caCamber,'-s','LineWidth',2); ylabel(ax,'C_\alpha [N/deg]');
xlabel(ax,'Camber / IA [deg]'); title(ax,'Global MF Camber Sensitivity'); grid(ax,'on');
exportgraphics(fig6,fullfile(OUTDIR,'06_CAMBER_SENSITIVITY.png'),'Resolution',180);

fig7=figure('Color','k','Name','CMM v1.5.1 Condition R2');
ax=axes(fig7); styleAxes(ax);
plot(ax,loadGrid,r2Load,'-o','LineWidth',2); hold(ax,'on');
plot(ax,pressureGrid,r2Pressure,'-s','LineWidth',2);
plot(ax,camberGrid,r2Camber,'-^','LineWidth',2);
yline(ax,0.90,'--');
xlabel(ax,'Condition index'); ylabel(ax,'R^2');
title(ax,'Condition-wise Validation R^2');
legend(ax,'Load','Pressure','Camber','0.90 target','Location','best');
exportgraphics(fig7,fullfile(OUTDIR,'07_CONDITION_R2.png'),'Resolution',180);

%% ---------------- AUDIT ----------------
fid=fopen(fullfile(OUTDIR,'GLOBAL_MF_AUDIT_REPORT.txt'),'w');
fprintf(fid,'CMM MF LATERAL GLOBAL v1.5.1 AUDIT\n');
fprintf(fid,'===================================\n');
fprintf(fid,'Input: %s\n',INPUT_CSV);
fprintf(fid,'Reference: Fz0=%.3f N, P0=%.3f psi, IA0=%.3f deg\n',FZ0,P0,IA0);
fprintf(fid,'Reference objective weight: %.3f\n',REFERENCE_WEIGHT);
fprintf(fid,'\nGlobal R2: %.8f\nGlobal RMSE: %.6f N\nGlobal MAE: %.6f N\n',R2,RMSE,MAE);
fprintf(fid,'Reference R2: %.8f\nReference RMSE: %.6f N\nReference MAE: %.6f N\n',R2ref,RMSEref,MAEref);
fprintf(fid,'Reference C-alpha: %.6f N/rad\n',caRad);
fprintf(fid,'Reference C-alpha: %.6f N/deg\n',caDeg);
fprintf(fid,'Reference measured peak mu: %.8f\n',peakMuMeasured);
fprintf(fid,'Reference MF peak mu: %.8f\n',peakMuMF);
fprintf(fid,'Selected multi-start: %d\n',bestIdx);
fprintf(fid,'Overall status: %s\n',status);
fprintf(fid,'\nParameter list:\n');
for k=1:numel(q)
    fprintf(fid,'%s = %.12g\n',Names{k},q(k));
end
fprintf(fid,'\nFixed: PEY3=0, PEY4=0\n');
fprintf(fid,'No longitudinal/braking data available; pure lateral only.\n');
fprintf(fid,'Pressure terms are a CMM wrapper and are not standard MF-Tyre .tir coefficients.\n');
fprintf(fid,'C-alpha reporting explicitly converts N/rad to N/deg.\n');
fclose(fid);

fprintf('\n[10] OUTPUT\n');
pngs=dir(fullfile(OUTDIR,'*.png'));
fprintf('PNG files present : %d\n',numel(pngs));
fprintf('MAT/CSV/audit files saved.\n');
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL GLOBAL v1.5.1 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Global R2           : %.6f\n',R2);
fprintf('Global RMSE         : %.2f N\n',RMSE);
fprintf('Reference R2        : %.6f\n',R2ref);
fprintf('Reference RMSE      : %.2f N\n',RMSEref);
fprintf('Reference C-alpha   : %.2f N/deg\n',caDeg);
fprintf('Measured peak mu    : %.4f\n',peakMuMeasured);
fprintf('Model peak mu       : %.4f\n',peakMuMF);
fprintf('Reference weight    : %.2f\n',REFERENCE_WEIGHT);
fprintf('Parallel starts     : %d\n',N_STARTS);
fprintf('Longitudinal model  : NOT AVAILABLE\n');
fprintf('.tir generation     : BLOCKED until validation passes\n');
fprintf('Status              : %s\n',status);
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
end
end

%% ========================================================================
function r=globalResidualWeighted(q,a,fz,ia,p,fy,aRef,fzRef,iaRef,pRef,fyRef,Fz0,P0,refWeight)

pred=cmmMFglobal(q,a,fz,ia,p,Fz0,P0);
predRef=cmmMFglobal(q,aRef,fzRef,iaRef,pRef,Fz0,P0);

% Normalized force residual: effectively error in friction coefficient.
scale=max(fz,250);
scaleRef=max(fzRef,250);

rGlobal=(pred-fy)./scale;
rRef=(predRef-fyRef)./scaleRef;

% Explicit reference protection.
r=[rGlobal; sqrt(refWeight)*rRef];

r(~isfinite(r))=1e3;
end

%% ========================================================================
function y=cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)

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
function out=ternary(cond,a,b)
if cond
    out=a;
else
    out=b;
end
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
