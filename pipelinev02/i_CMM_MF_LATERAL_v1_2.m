function CMM_MF_LATERAL_v1
% ================================================================
% CMM MF LATERAL IMPLEMENTATION v1.2
% Pure lateral Magic Formula fitting from frozen CMM TTC database
%
% PURPOSE
%   1) Fit a reduced Pacejka/Magic-Formula lateral model to measured
%      pure-cornering data.
%   2) Fit the reference operating point first.
%   3) Fit representative load / pressure / camber condition slices.
%   4) Validate every fit against measured data.
%   5) Keep all figures inside ONE MATLAB UIFigure using tabs.
%   6) Save figures + parameter tables + audit report.
%
% IMPORTANT
%   This version fits ONLY lateral behavior:
%       Fy = f(alpha,Fz,P,IA)
%   It does NOT invent longitudinal or combined-slip coefficients.
%   It does NOT create a .tir file yet.
%
% INPUT CONTRACT
%   Frozen CMM database:
%   _PRE_MF_MATRIX_v1_3\TTC_CONDITION_ASSIGNED_DATABASE.csv
%
% REFERENCE CONTRACT
%   Fz0 = 871.5 N
%   P0  = 12.10 psi
%   IA0 = 0 deg
%
% MATLAB requirements:
%   Base MATLAB only. No Curve Fitting Toolbox required.
%   Uses fminsearch for the nonlinear MF fit.
% ================================================================

clc;
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL IMPLEMENTATION v1.2\n');
fprintf(' REDUCED MAGIC FORMULA / PURE LATERAL ONLY\n');
fprintf('============================================================\n\n');

%% ----------------------- CONTRACT ------------------------------
inputFile = 'C:\Users\adity\CMM\all tests are here\_PRE_MF_MATRIX_v1_3\TTC_CONDITION_ASSIGNED_DATABASE.csv';

FZ0 = 871.5;       % N
P0  = 12.10;       % psi
IA0 = 0.0;         % deg
P_TOL  = 0.20;     % psi
FZ_TOL = 75.0;     % N
IA_TOL = 0.20;     % deg

SA_MAX_FIT = 12.0; % deg
SA_MIN_FIT = 0.10; % deg
N_GRID = 240;

thisFile = mfilename('fullpath');
repoRoot = fileparts(fileparts(thisFile));
outDir = fullfile(repoRoot,'outputs','12_MF_LATERAL_v1_2');
if ~exist(outDir,'dir'), mkdir(outDir); end

fprintf('[1] INPUT\n%s\n\n', inputFile);
if ~isfile(inputFile)
    error('Input CSV not found:\n%s', inputFile);
end

%% ----------------------- LOAD DATA ------------------------------
T = readtable(inputFile, 'VariableNamingRule','preserve');

fprintf('[2] DATABASE\n');
fprintf('Rows : %d\n', height(T));
fprintf('Vars : %d\n\n', width(T));

[SA,saName] = pickVar(T, {'SA_deg','SA','SlipAngle','slip_angle'});
[FY,fyName] = pickVar(T, {'FY_N','FY','Fy','LateralForce'});
[FZ,fzName] = pickVar(T, {'FZ_N','FZ','Fz','NormalLoad','VerticalLoad'});
[IA,iaName] = pickVar(T, {'IA_deg','IA','InclinationAngle','Camber','Camber_deg'});
[Praw,pName] = pickVar(T, {'Pressure_psi','Pressure','P_psi','P','Pressure_kPa'});

% Defensive numeric conversion. pickVar should already return arrays, but
% accept a table too so this script cannot fail on tabular/double.
if istable(SA),   SA   = table2array(SA);   end
if istable(FY),   FY   = table2array(FY);   end
if istable(FZ),   FZ   = table2array(FZ);   end
if istable(IA),   IA   = table2array(IA);   end
if istable(Praw), Praw = table2array(Praw); end

SA   = double(SA(:));
FY   = double(FY(:));
FZ   = double(FZ(:));
IA   = double(IA(:));
Praw = double(Praw(:));

% Pressure mapping: frozen database stores Pressure_kPa in current project.
% If the detected variable is kPa, convert to psi.
pName = lower(string(pName));
if contains(pName,'kpa') || median(Praw,'omitnan') > 30
    P = Praw / 6.894757293168;
    pressureSource = 'detected kPa -> converted to psi';
else
    P = Praw;
    pressureSource = 'used as psi';
end

% Fy sign normalization: use the project convention determined in PRE-MF.
posSA = FY(SA > 1 & abs(SA) < 3);
negSA = FY(SA < -1 & abs(SA) < 3);
if ~isempty(posSA) && ~isempty(negSA) && median(posSA,'omitnan') < 0 && median(negSA,'omitnan') > 0
    FY = -FY;
    fyMultiplier = -1;
else
    fyMultiplier = 1;
end

valid = isfinite(SA) & isfinite(FY) & isfinite(FZ) & isfinite(IA) & isfinite(P) & FZ > 0;
SA = SA(valid); FY = FY(valid); FZ = FZ(valid); IA = IA(valid); P = P(valid);

fprintf('Pressure mapping : %s\n', pressureSource);
fprintf('Fy multiplier    : %+g\n', fyMultiplier);
fprintf('SA : %.3f -> %.3f deg\n', min(SA), max(SA));
fprintf('FY : %.2f -> %.2f N\n', min(FY), max(FY));
fprintf('FZ : %.2f -> %.2f N\n', min(FZ), max(FZ));
fprintf('IA : %.3f -> %.3f deg\n', min(IA), max(IA));
fprintf('P  : %.2f -> %.2f psi\n\n', min(P), max(P));

%% ---------------- REFERENCE DATA -------------------------------
refMask = abs(P-P0) <= P_TOL & abs(IA-IA0) <= IA_TOL & ...
          abs(FZ-FZ0) <= FZ_TOL & abs(SA) <= SA_MAX_FIT;

if nnz(refMask) < 100
    error('Reference window contains only %d samples. Cannot fit.', nnz(refMask));
end

% Work with magnitude because the engineering characterization is
% symmetric |Fy| vs |SA|.
saRef = abs(SA(refMask));
fyRef = abs(FY(refMask));

[alphaRef, fyRefCurve, nRef] = makeSweep(saRef, fyRef, N_GRID, SA_MIN_FIT, SA_MAX_FIT);

if numel(alphaRef) < 25
    error('Reference sweep extraction produced too few points.');
end

fprintf('[3] REFERENCE CURVE\n');
fprintf('Fz0 : %.1f N +/- %.1f N\n',FZ0,FZ_TOL);
fprintf('P0  : %.2f psi +/- %.2f psi\n',P0,P_TOL);
fprintf('IA0 : %.1f deg +/- %.1f deg\n',IA0,IA_TOL);
fprintf('Samples : %d\n',nnz(refMask));
fprintf('Curve points : %d\n\n',numel(alphaRef));

%% ---------------- REFERENCE MF FIT ------------------------------
p0 = initialGuessMF(alphaRef, fyRefCurve);
opts = optimset('Display','off','MaxIter',5000,'MaxFunEvals',15000,...
                'TolX',1e-9,'TolFun',1e-9);

% Optional Parallel Computing Toolbox support.
% Reference fit remains serial for deterministic startup. Independent
% load/pressure/camber fits can be parallelized when a pool is available.
useParallel = false;
try
    useParallel = license('test','Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
catch
    useParallel = false;
end
if useParallel
    try
        pool = gcp('nocreate');
        if isempty(pool)
            pool = parpool('threads');
        end
        fprintf('[MF] Parallel Computing available: %d workers.\n', pool.NumWorkers);
    catch
        try
            pool = gcp('nocreate');
            if isempty(pool), pool = parpool('local'); end
            fprintf('[MF] Parallel Computing available: %d workers.\n', pool.NumWorkers);
        catch
            useParallel = false;
            fprintf('[MF] Parallel pool unavailable; using serial fitting.\n');
        end
    end
else
    fprintf('[MF] Parallel Computing Toolbox not available; using serial fitting.\n');
end

% Parameters are represented as:
% z = [log(B), log(C), log(D), atanh(E/0.999), SH(deg)]
% B is rad^-1, C dimensionless, D N, E bounded (-0.999,0.999).
z0 = encodeMF(p0);

obj = @(z) mfObjective(z, alphaRef, fyRefCurve);
[zFit, fval, exitflag] = fminsearch(obj, z0, opts);
pRef = decodeMF(zFit);

alphaGrid = linspace(0,SA_MAX_FIT,N_GRID)';
fyMF = mfEval(alphaGrid,pRef);

metricsRef = fitMetrics(alphaRef,fyRefCurve,mfEval(alphaRef,pRef),pRef,FZ0);

fprintf('[4] REFERENCE MF FIT\n');
fprintf('B : %.8g rad^-1\n',pRef.B);
fprintf('C : %.8g\n',pRef.C);
fprintf('D : %.3f N\n',pRef.D);
fprintf('E : %.8g\n',pRef.E);
fprintf('Sh: %.6f deg\n',pRef.Sh);
fprintf('C-alpha : %.3f N/deg\n',metricsRef.Calpha_Ndeg);
fprintf('R2      : %.6f\n',metricsRef.R2);
fprintf('RMSE    : %.3f N\n',metricsRef.RMSE);
fprintf('Peak mu measured : %.5f\n',metricsRef.muMeasured);
fprintf('Peak mu MF       : %.5f\n',metricsRef.muMF);
fprintf('Peak SA measured : %.3f deg\n',metricsRef.peakSAMeasured);
fprintf('Peak SA MF       : %.3f deg\n',metricsRef.peakSAMF);
fprintf('Fit objective    : %.6g\n',fval);
fprintf('Exit flag        : %d\n\n',exitflag);

%% ---------------- CONDITION SLICES -----------------------------
% Select representative conditions that actually exist in the data.
loadTargets = [250 450 650 875 1100];
pressureTargets = [8 10 12 14];
camberTargets = [0 2 4];

fitRows = table();
fitStruct = struct();

% Reference first
fitStruct(1).kind = "REFERENCE";
fitStruct(1).Fz = FZ0;
fitStruct(1).P = P0;
fitStruct(1).IA = IA0;
fitStruct(1).params = pRef;
fitStruct(1).metrics = metricsRef;
fitStruct(1).n = nnz(refMask);
fitStruct(1).alpha = alphaRef;
fitStruct(1).fy = fyRefCurve;

% Load slices at P0, IA0
fprintf('[5] LOAD-SLICE FITS\n');
for k=1:numel(loadTargets)
    target = loadTargets(k);
    mask = abs(P-P0)<=P_TOL & abs(IA-IA0)<=IA_TOL & ...
           abs(FZ-target)<=max(60,0.10*target) & abs(SA)<=SA_MAX_FIT;
    if nnz(mask) < 100, continue; end
    [a,y,n] = makeSweep(abs(SA(mask)),abs(FY(mask)),N_GRID,SA_MIN_FIT,SA_MAX_FIT);
    if numel(a)<25, continue; end
    pp0 = initialGuessMF(a,y);
    zz0 = encodeMF(pp0);
    [zz,~,~] = fminsearch(@(z) mfObjective(z,a,y),zz0,opts);
    pf = decodeMF(zz);
    m = fitMetrics(a,y,mfEval(a,pf),pf,median(FZ(mask),'omitnan'));

    j = numel(fitStruct)+1;
    fitStruct(j).kind="LOAD";
    fitStruct(j).Fz=median(FZ(mask),'omitnan');
    fitStruct(j).P=median(P(mask),'omitnan');
    fitStruct(j).IA=median(IA(mask),'omitnan');
    fitStruct(j).params=pf;
    fitStruct(j).metrics=m;
    fitStruct(j).n=nnz(mask);
    fitStruct(j).alpha=a;
    fitStruct(j).fy=y;

    fprintf('Fz %.1f N | B %.5g | C %.5g | D %.1f N | E %.5g | C-alpha %.2f N/deg | R2 %.4f | N %d\n',...
        fitStruct(j).Fz,pf.B,pf.C,pf.D,pf.E,m.Calpha_Ndeg,m.R2,nnz(mask));
end
fprintf('\n');

% Pressure slices around Fz0, IA0
fprintf('[6] PRESSURE-SLICE FITS\n');
for k=1:numel(pressureTargets)
    target = pressureTargets(k);
    mask = abs(P-target)<=0.30 & abs(IA-IA0)<=IA_TOL & ...
           abs(FZ-FZ0)<=FZ_TOL & abs(SA)<=SA_MAX_FIT;
    if nnz(mask) < 100, continue; end
    [a,y,n] = makeSweep(abs(SA(mask)),abs(FY(mask)),N_GRID,SA_MIN_FIT,SA_MAX_FIT);
    if numel(a)<25, continue; end
    pp0=initialGuessMF(a,y); zz0=encodeMF(pp0);
    [zz,~,~]=fminsearch(@(z) mfObjective(z,a,y),zz0,opts);
    pf=decodeMF(zz); m=fitMetrics(a,y,mfEval(a,pf),pf,median(FZ(mask),'omitnan'));
    j=numel(fitStruct)+1;
    fitStruct(j).kind="PRESSURE";
    fitStruct(j).Fz=median(FZ(mask),'omitnan');
    fitStruct(j).P=median(P(mask),'omitnan');
    fitStruct(j).IA=median(IA(mask),'omitnan');
    fitStruct(j).params=pf; fitStruct(j).metrics=m; fitStruct(j).n=nnz(mask);
    fitStruct(j).alpha=a; fitStruct(j).fy=y;
    fprintf('P %.2f psi | B %.5g | C %.5g | D %.1f N | E %.5g | C-alpha %.2f N/deg | R2 %.4f | N %d\n',...
        fitStruct(j).P,pf.B,pf.C,pf.D,pf.E,m.Calpha_Ndeg,m.R2,nnz(mask));
end
fprintf('\n');

% Camber slices around Fz0, P0
fprintf('[7] CAMBER-SLICE FITS\n');
for k=1:numel(camberTargets)
    target = camberTargets(k);
    mask = abs(P-P0)<=P_TOL & abs(IA-target)<=0.25 & ...
           abs(FZ-FZ0)<=FZ_TOL & abs(SA)<=SA_MAX_FIT;
    if nnz(mask) < 100, continue; end
    [a,y,n] = makeSweep(abs(SA(mask)),abs(FY(mask)),N_GRID,SA_MIN_FIT,SA_MAX_FIT);
    if numel(a)<25, continue; end
    pp0=initialGuessMF(a,y); zz0=encodeMF(pp0);
    [zz,~,~]=fminsearch(@(z) mfObjective(z,a,y),zz0,opts);
    pf=decodeMF(zz); m=fitMetrics(a,y,mfEval(a,pf),pf,median(FZ(mask),'omitnan'));
    j=numel(fitStruct)+1;
    fitStruct(j).kind="CAMBER";
    fitStruct(j).Fz=median(FZ(mask),'omitnan');
    fitStruct(j).P=median(P(mask),'omitnan');
    fitStruct(j).IA=median(IA(mask),'omitnan');
    fitStruct(j).params=pf; fitStruct(j).metrics=m; fitStruct(j).n=nnz(mask);
    fitStruct(j).alpha=a; fitStruct(j).fy=y;
    fprintf('IA %.2f deg | B %.5g | C %.5g | D %.1f N | E %.5g | C-alpha %.2f N/deg | R2 %.4f | N %d\n',...
        fitStruct(j).IA,pf.B,pf.C,pf.D,pf.E,m.Calpha_Ndeg,m.R2,nnz(mask));
end
fprintf('\n');

% Explicit parameter-bound diagnostics. These are NOT accepted as valid
% engineering fits when the optimizer hits a hard bound.
Nf=numel(fitStruct);
boundFlags = false(Nf,1);
for ii=1:numel(fitStruct)
    pf=fitStruct(ii).params;
    boundFlags(ii) = (pf.C <= 0.3005) || (pf.E >= 0.9985) || ...
                     (pf.E <= -0.9985) || (abs(pf.Sh) >= 0.999);
end

fprintf('[8] FIT QUALITY FLAGS\n');
for ii=1:numel(fitStruct)
    if boundFlags(ii)
        fprintf('WARNING: %s | Fz %.1f N | P %.2f psi | IA %.2f deg | MF parameter at bound.\n',...
            fitStruct(ii).kind,fitStruct(ii).Fz,fitStruct(ii).P,fitStruct(ii).IA);
    end
end
fprintf('\n');

%% ---------------- BUILD OUTPUT TABLE ---------------------------
Kind=strings(Nf,1); FzOut=nan(Nf,1); POut=nan(Nf,1); IAOut=nan(Nf,1);
BOut=nan(Nf,1); COut=nan(Nf,1); DOut=nan(Nf,1); EOut=nan(Nf,1); ShOut=nan(Nf,1);
CAlphaOut=nan(Nf,1); R2Out=nan(Nf,1); RMSEOut=nan(Nf,1);
MuOut=nan(Nf,1); PeakSAOut=nan(Nf,1); NOut=zeros(Nf,1);

for i=1:Nf
    Kind(i)=fitStruct(i).kind;
    FzOut(i)=fitStruct(i).Fz;
    POut(i)=fitStruct(i).P;
    IAOut(i)=fitStruct(i).IA;
    BOut(i)=fitStruct(i).params.B;
    COut(i)=fitStruct(i).params.C;
    DOut(i)=fitStruct(i).params.D;
    EOut(i)=fitStruct(i).params.E;
    ShOut(i)=fitStruct(i).params.Sh;
    CAlphaOut(i)=fitStruct(i).metrics.Calpha_Ndeg;
    R2Out(i)=fitStruct(i).metrics.R2;
    RMSEOut(i)=fitStruct(i).metrics.RMSE;
    MuOut(i)=fitStruct(i).metrics.muMF;
    PeakSAOut(i)=fitStruct(i).metrics.peakSAMF;
    NOut(i)=fitStruct(i).n;
end

BoundFlag=boundFlags;
MFTable=table(Kind,FzOut,POut,IAOut,BOut,COut,DOut,EOut,ShOut,...
    CAlphaOut,R2Out,RMSEOut,MuOut,PeakSAOut,NOut,BoundFlag,...
    'VariableNames',{'Type','Fz_N','Pressure_psi','Camber_deg','B_radInv','C','D_N','E','Sh_deg',...
    'CAlpha_NperDeg','R2','RMSE_N','PeakMu','PeakSA_deg','Samples','ParameterBoundFlag'});

writetable(MFTable,fullfile(outDir,'MF_LATERAL_CONDITION_FITS.csv'));

refTable=table(["Fz0_N";"P0_psi";"IA0_deg";"B_radInv";"C";"D_N";"E";"Sh_deg";...
    "CAlpha_NperDeg";"R2";"RMSE_N";"PeakMuMeasured";"PeakMuMF";"PeakSAMeasured_deg";"PeakSAMF_deg"],...
    [FZ0;P0;IA0;pRef.B;pRef.C;pRef.D;pRef.E;pRef.Sh;metricsRef.Calpha_Ndeg;...
     metricsRef.R2;metricsRef.RMSE;metricsRef.muMeasured;metricsRef.muMF;...
     metricsRef.peakSAMeasured;metricsRef.peakSAMF],...
    'VariableNames',{'Metric','Value'});
writetable(refTable,fullfile(outDir,'MF_REFERENCE_PARAMETERS.csv'));

%% ---------------- FIGURE WINDOW WITH TABS ----------------------
fig = uifigure('Name','CMM MF Lateral v1.0 — Engineering Characterization',...
               'Color',[0 0 0],...
               'Position',[80 50 1500 900]);

tg = uitabgroup(fig,'Position',[5 5 1490 890]);

% Tab 1: reference fit
tab1=uitab(tg,'Title','01 Reference MF');
ax=darkAxes(tab1);
plot(ax,alphaRef,fyRefCurve,'o','MarkerSize',4,'Color',[0.15 0.65 1.0],...
    'DisplayName','Measured sweep');
hold(ax,'on');
plot(ax,alphaGrid,fyMF,'-','LineWidth',2.2,'Color',[1.0 0.65 0.1],...
    'DisplayName','MF fit');
grid(ax,'on');
xlabel(ax,'|\alpha| [deg]'); ylabel(ax,'|F_y| [N]');
title(ax,sprintf('Reference MF Fit | F_z=%.1f N | P=%.2f psi | IA=%.1f deg',FZ0,P0,IA0));
legend(ax,'Location','southeast');
txt=sprintf('C_\\alpha = %.1f N/deg\\nR^2 = %.5f\\nRMSE = %.1f N\\n\\mu_{peak}=%.3f',...
    metricsRef.Calpha_Ndeg,metricsRef.R2,metricsRef.RMSE,metricsRef.muMF);
text(ax,0.03,0.95,txt,'Units','normalized','VerticalAlignment','top',...
    'Color',[1 1 1],'FontWeight','bold','BackgroundColor',[0.08 0.08 0.08]);

% Tab 2: residual
tab2=uitab(tg,'Title','02 Reference Residual');
ax=darkAxes(tab2);
res=fyRefCurve-mfEval(alphaRef,pRef);
plot(ax,alphaRef,res,'.','MarkerSize',9,'Color',[1 0.35 0.35]);
yline(ax,0,'--','Color',[0.7 0.7 0.7]);
grid(ax,'on');
xlabel(ax,'|\alpha| [deg]'); ylabel(ax,'Measured - MF [N]');
title(ax,'Reference MF Residual');

% Tab 3: load
tab3=uitab(tg,'Title','03 Load Fits');
ax=darkAxes(tab3);
hold(ax,'on');
for i=1:Nf
    if fitStruct(i).kind=="LOAD"
        a=fitStruct(i).alpha; y=fitStruct(i).fy;
        plot(ax,a,y,'o','MarkerSize',3,'HandleVisibility','off');
        ag=linspace(0,SA_MAX_FIT,200)';
        ym=mfEval(ag,fitStruct(i).params);
        plot(ax,ag,ym,'-','LineWidth',1.7,'DisplayName',sprintf('%.0f N | C_a %.0f',fitStruct(i).Fz,fitStruct(i).metrics.Calpha_Ndeg));
    end
end
grid(ax,'on'); xlabel(ax,'|\alpha| [deg]'); ylabel(ax,'|F_y| [N]');
title(ax,'MF Fits Across Load');
legend(ax,'Location','eastoutside');

% Tab 4: C-alpha load
tab4=uitab(tg,'Title','04 C-alpha vs Load');
ax=darkAxes(tab4);
idx=find(Kind=="LOAD");
plot(ax,FzOut(idx),CAlphaOut(idx),'o-','LineWidth',1.8,'MarkerSize',7,...
    'Color',[0.2 0.75 1]);
hold(ax,'on');
xline(ax,FZ0,'--','Color',[0.75 0.75 0.75],'DisplayName','Reference load');
grid(ax,'on');
xlabel(ax,'F_z [N]'); ylabel(ax,'C_\alpha [N/deg]');
title(ax,'MF-Derived Cornering Stiffness vs Load');

% Tab 5: peak mu load
tab5=uitab(tg,'Title','05 Peak Mu vs Load');
ax=darkAxes(tab5);
plot(ax,FzOut(idx),MuOut(idx),'o-','LineWidth',1.8,'MarkerSize',7,...
    'Color',[1 0.75 0.15]);
hold(ax,'on'); yline(ax,metricsRef.muMF,'--','Color',[0.7 0.7 0.7]);
grid(ax,'on');
xlabel(ax,'F_z [N]'); ylabel(ax,'\mu_{y,peak}');
title(ax,'MF Peak Friction vs Load');

% Tab 6: pressure
tab6=uitab(tg,'Title','06 Pressure Fits');
ax=darkAxes(tab6);
hold(ax,'on');
idx=find(Kind=="PRESSURE");
for q=1:numel(idx)
    i=idx(q);
    plot(ax,fitStruct(i).alpha,fitStruct(i).fy,'o','MarkerSize',3,'HandleVisibility','off');
    ag=linspace(0,SA_MAX_FIT,200)';
    plot(ax,ag,mfEval(ag,fitStruct(i).params),'-','LineWidth',1.7,...
        'DisplayName',sprintf('%.1f psi',fitStruct(i).P));
end
grid(ax,'on'); xlabel(ax,'|\alpha| [deg]'); ylabel(ax,'|F_y| [N]');
title(ax,'MF Fits Across Pressure');
legend(ax,'Location','eastoutside');

% Tab 7: pressure metrics
tab7=uitab(tg,'Title','07 Pressure Metrics');
ax=darkAxes(tab7);
pidx=find(Kind=="PRESSURE");
yyaxis(ax,'left');
plot(ax,POut(pidx),MuOut(pidx),'o-','LineWidth',1.8,'MarkerSize',7);
ylabel(ax,'\mu_{y,peak}');
yyaxis(ax,'right');
plot(ax,POut(pidx),CAlphaOut(pidx),'s-','LineWidth',1.8,'MarkerSize',6);
ylabel(ax,'C_\alpha [N/deg]');
grid(ax,'on'); xlabel(ax,'Pressure [psi]');
title(ax,'Pressure Sensitivity from Independent MF Fits');

% Tab 8: camber
tab8=uitab(tg,'Title','08 Camber Fits');
ax=darkAxes(tab8);
hold(ax,'on');
idx=find(Kind=="CAMBER");
for q=1:numel(idx)
    i=idx(q);
    plot(ax,fitStruct(i).alpha,fitStruct(i).fy,'o','MarkerSize',3,'HandleVisibility','off');
    ag=linspace(0,SA_MAX_FIT,200)';
    plot(ax,ag,mfEval(ag,fitStruct(i).params),'-','LineWidth',1.7,...
        'DisplayName',sprintf('IA %.1f deg',fitStruct(i).IA));
end
grid(ax,'on'); xlabel(ax,'|\alpha| [deg]'); ylabel(ax,'|F_y| [N]');
title(ax,'MF Fits Across Camber');
legend(ax,'Location','eastoutside');

% Tab 9: camber metrics
tab9=uitab(tg,'Title','09 Camber Metrics');
ax=darkAxes(tab9);
cidx=find(Kind=="CAMBER");
yyaxis(ax,'left');
plot(ax,IAOut(cidx),MuOut(cidx),'o-','LineWidth',1.8,'MarkerSize',7);
ylabel(ax,'\mu_{y,peak}');
yyaxis(ax,'right');
plot(ax,IAOut(cidx),CAlphaOut(cidx),'s-','LineWidth',1.8,'MarkerSize',6);
ylabel(ax,'C_\alpha [N/deg]');
grid(ax,'on'); xlabel(ax,'Camber / IA [deg]');
title(ax,'Camber Sensitivity from Independent MF Fits');

% Tab 10: fit table
tab10=uitab(tg,'Title','10 Parameter Table');
uilabel(tab10,'Text','See MF_LATERAL_CONDITION_FITS.csv and MF_REFERENCE_PARAMETERS.csv in output folder.',...
    'Position',[40 760 1100 30],'FontColor',[1 1 1],'FontSize',16);

fprintf('[8] FIGURES\n');
fprintf('One MATLAB window created with %d tabs.\n',numel(tg.Children));
fprintf('Black figure + axes background enabled.\n');
fprintf('PNG files are also exported below.\n\n');

%% ---------------- SAVE PNGS ------------------------------------
exportTabPNG(tab1,fullfile(outDir,'01_REFERENCE_MF.png'));
exportTabPNG(tab2,fullfile(outDir,'02_REFERENCE_RESIDUAL.png'));
exportTabPNG(tab3,fullfile(outDir,'03_LOAD_MF_FITS.png'));
exportTabPNG(tab4,fullfile(outDir,'04_CALPHA_LOAD.png'));
exportTabPNG(tab5,fullfile(outDir,'05_PEAK_MU_LOAD.png'));
exportTabPNG(tab6,fullfile(outDir,'06_PRESSURE_MF_FITS.png'));
exportTabPNG(tab7,fullfile(outDir,'07_PRESSURE_METRICS.png'));
exportTabPNG(tab8,fullfile(outDir,'08_CAMBER_MF_FITS.png'));
exportTabPNG(tab9,fullfile(outDir,'09_CAMBER_METRICS.png'));

%% ---------------- AUDIT REPORT ---------------------------------
auditFile=fullfile(outDir,'AUDIT_REPORT_MF_LATERAL_v1_2.txt');
fid=fopen(auditFile,'w');
fprintf(fid,'CMM MF LATERAL IMPLEMENTATION v1.2\n');
fprintf(fid,'==================================\n\n');
fprintf(fid,'INPUT\n%s\n\n',inputFile);
fprintf(fid,'DATABASE ROWS: %d\n',height(T));
fprintf(fid,'Fy multiplier: %+g\n',fyMultiplier);
fprintf(fid,'Pressure mapping: %s\n\n',pressureSource);
fprintf(fid,'REFERENCE CONTRACT\n');
fprintf(fid,'Fz0 = %.3f N\nP0  = %.3f psi\nIA0 = %.3f deg\n',FZ0,P0,IA0);
fprintf(fid,'Fz tolerance = +/- %.3f N\nP tolerance = +/- %.3f psi\nIA tolerance = +/- %.3f deg\n\n',FZ_TOL,P_TOL,IA_TOL);
fprintf(fid,'REFERENCE MF PARAMETERS\n');
fprintf(fid,'B = %.12g rad^-1\nC = %.12g\nD = %.12g N\nE = %.12g\nSh = %.12g deg\n',pRef.B,pRef.C,pRef.D,pRef.E,pRef.Sh);
fprintf(fid,'C-alpha = %.6f N/deg\nR2 = %.8f\nRMSE = %.6f N\n',metricsRef.Calpha_Ndeg,metricsRef.R2,metricsRef.RMSE);
fprintf(fid,'Measured peak mu = %.6f\nMF peak mu = %.6f\n',metricsRef.muMeasured,metricsRef.muMF);
fprintf(fid,'Measured peak SA = %.6f deg\nMF peak SA = %.6f deg\n\n',metricsRef.peakSAMeasured,metricsRef.peakSAMF);
fprintf(fid,'MODEL SCOPE\n');
fprintf(fid,'This file contains PURE LATERAL fitting only.\n');
fprintf(fid,'No Fx, longitudinal slip, or combined-slip parameters are inferred.\n');
fprintf(fid,'No .tir file is generated by this version.\n');
fprintf(fid,'The independent load/pressure/camber fits are diagnostic building blocks.\n');
fprintf(fid,'A global MF-Tyre parameterization is the next fitting stage after validation.\n');
fprintf(fid,'\nFIT QUALITY FLAGS\n');
for ii=1:numel(fitStruct)
    if boundFlags(ii)
        fprintf(fid,'BOUND-HIT: %s | Fz %.3f N | P %.3f psi | IA %.3f deg | B %.8g | C %.8g | D %.8g | E %.8g | Sh %.8g deg\\n',...
            fitStruct(ii).kind,fitStruct(ii).Fz,fitStruct(ii).P,fitStruct(ii).IA,...
            fitStruct(ii).params.B,fitStruct(ii).params.C,fitStruct(ii).params.D,...
            fitStruct(ii).params.E,fitStruct(ii).params.Sh);
    end
end
fclose(fid);

fprintf('[9] OUTPUT\n%s\n',outDir);
fprintf('Reference MF parameters saved.\n');
fprintf('Condition fits saved.\n');
fprintf('Audit report saved.\n');
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL v1.2 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Reference C-alpha : %.3f N/deg\n',metricsRef.Calpha_Ndeg);
fprintf('Reference peak mu : %.4f\n',metricsRef.muMF);
fprintf('Reference R2      : %.5f\n',metricsRef.R2);
fprintf('No longitudinal / combined-slip fitting performed.\n');
safeBoundCount = sum(boundFlags);
fprintf('Parameter-bound fits flagged: %d / %d\n',safeBoundCount,Nf);
fprintf('No .tir generated yet.\n');
fprintf('============================================================\n\n');

end

%% =================================================================
function [v,varName] = pickVar(T,candidates)
names=string(T.Properties.VariableNames);
v=[];
varName="";
for i=1:numel(candidates)
    hit=find(strcmpi(names,candidates{i}),1);
    if ~isempty(hit)
        v=table2array(T(:,hit));
        v=double(v(:));
        varName=names(hit);
        return;
    end
end
% normalized fallback
normNames=lower(regexprep(names,'[^a-zA-Z0-9]',''));
for i=1:numel(candidates)
    c=lower(regexprep(string(candidates{i}),'[^a-zA-Z0-9]',''));
    hit=find(contains(normNames,c),1);
    if ~isempty(hit)
        v=table2array(T(:,hit));
        v=double(v(:));
        varName=names(hit);
        return;
    end
end
error('Could not locate required variable. Candidates: %s',strjoin(string(candidates),', '));
end

%% =================================================================
function [a,y,n] = makeSweep(sa,fy,N,amin,amax)
edges=linspace(amin,amax,N+1);
bc=(edges(1:end-1)+edges(2:end))/2;
a=[]; y=[]; n=[];
for k=1:N
    m=sa>=edges(k) & sa<edges(k+1) & isfinite(fy);
    if nnz(m)>=3
        a(end+1,1)=bc(k); %#ok<AGROW>
        y(end+1,1)=median(fy(m),'omitnan'); %#ok<AGROW>
        n(end+1,1)=nnz(m); %#ok<AGROW>
    end
end
end

%% =================================================================
function p=initialGuessMF(alphaDeg,y)
alphaDeg=alphaDeg(:); y=y(:);
D=max(y);
if ~isfinite(D) || D<=0, D=1; end

% Estimate small-angle slope using first 10% of points.
m=alphaDeg<=max(0.5,min(2,max(alphaDeg)*0.15));
if nnz(m)<4, m=alphaDeg<=1.0; end
if nnz(m)>=3
    q=polyfit(alphaDeg(m),y(m),1);
    Kdeg=max(abs(q(1)),1);
else
    Kdeg=max(D/max(alphaDeg(end),1),1);
end
Krad=Kdeg*180/pi;

C=1.3;
B=Krad/(C*D);
B=max(B,0.1);
E=0.5;

p.B=B;
p.C=C;
p.D=D;
p.E=E;
p.Sh=0;
end

%% =================================================================
function z=encodeMF(p)
z=[log(max(p.B,1e-8));...
   log(max(p.C,1e-8));...
   log(max(p.D,1e-8));...
   atanh(max(min(p.E/0.999,0.999999),-0.999999));...
   p.Sh];
end

%% =================================================================
function p=decodeMF(z)
p.B=exp(z(1));
p.C=exp(z(2));
p.D=exp(z(3));
p.E=0.999*tanh(z(4));
p.Sh=z(5);
end

%% =================================================================
function y=mfEval(alphaDeg,p)
% Reduced sine-form Magic Formula.
% alpha is supplied in degrees; internal angle is radians.
x=(alphaDeg-p.Sh)*pi/180;
Bx=p.B*x;
inner=Bx-p.E.*(Bx-atan(Bx));
y=p.D.*sin(p.C.*atan(inner));
end

%% =================================================================
function J=mfObjective(z,a,y)
p=decodeMF(z);
yp=mfEval(a,p);

if any(~isfinite(yp)) || p.D<=0 || p.B<=0 || p.C<=0
    J=1e30;
    return;
end

% Relative weighting prevents high-force points from completely
% dominating the low-slip region, while retaining force accuracy.
scale=max(y,50);
r=(yp-y)./scale;
J=sum(r.^2);

% Mild regularization against pathological parameters.
if p.C<0.3 || p.C>3.5, J=J+1e3*(abs(p.C-1.3)^2); end
if p.E<-0.999 || p.E>0.999, J=J+1e6; end
if abs(p.Sh)>1.0, J=J+100*(abs(p.Sh)-1)^2; end
end

%% =================================================================
function m=fitMetrics(a,y,yp,p,FzMetric)
r=y-yp;
SStot=sum((y-mean(y)).^2);
SSres=sum(r.^2);
m.R2=1-SSres/max(SStot,eps);
m.RMSE=sqrt(mean(r.^2));

% Derivative at zero in N/rad = B*C*D.
% Convert to N/deg because the project reports C-alpha in N/deg.
m.Calpha_Ndeg=p.B*p.C*p.D*pi/180;

[peakMeasured,ii]=max(y);
m.muMeasured=peakMeasured/max(FzMetric,eps);
m.peakSAMeasured=a(ii);

[peakMF,jj]=max(yp);
m.muMF=peakMF/max(FzMetric,eps);
m.peakSAMF=a(jj);
end

%% =================================================================
function ax=darkAxes(parent)
ax=uiaxes(parent,'Position',[45 45 1400 780]);
ax.Color=[0 0 0];
ax.XColor=[0.95 0.95 0.95];
ax.YColor=[0.95 0.95 0.95];
ax.GridColor=[0.25 0.25 0.25];
ax.MinorGridColor=[0.15 0.15 0.15];
ax.Title.Color=[1 1 1];
ax.XLabel.Color=[0.95 0.95 0.95];
ax.YLabel.Color=[0.95 0.95 0.95];
try
    ax.FontSize=13;
catch
end
end

%% =================================================================
function exportTabPNG(tab,filename)
% Export the tab's first axes without opening another figure.
try
    ax=findobj(tab,'Type','uiaxes');
    if isempty(ax), return; end
    exportgraphics(ax(1),filename,'Resolution',180,'BackgroundColor','black');
catch
    % PNG export is auxiliary; the interactive tab remains available.
end
end
