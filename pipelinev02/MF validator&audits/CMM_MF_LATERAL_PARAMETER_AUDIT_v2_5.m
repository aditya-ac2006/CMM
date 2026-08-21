function CMM_MF_LATERAL_PARAMETER_AUDIT_v2_5
% ================================================================
% CMM MF LATERAL PARAMETER SENSITIVITY AUDIT v2.5
% NO REFIT - ONE-PARAMETER-AT-A-TIME SENSITIVITY STUDY
% ================================================================
%
% PURPOSE
%   Determine which fitted MF parameters control which parts of the
%   current CMM lateral tire model.
%
%   This script NEVER refits the model and NEVER overwrites the MAT file.
%
%   For each parameter, it evaluates:
%       - global pointwise R2 / RMSE / MAE
%       - reference-condition R2 / RMSE / MAE
%       - reference C-alpha
%       - reference peak mu
%       - reference peak slip angle
%       - load sensitivity
%       - pressure sensitivity
%       - camber sensitivity
%       - saturation-shape error at alpha checkpoints
%
%   Each parameter is perturbed by:
%       -10%, -5%, 0%, +5%, +10%
%
%   The audit is diagnostic only.
%
%   IMPORTANT:
%       The saved v2.0 parameter vector is never modified on disk.
%
% ================================================================

clc;
close all;

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL PARAMETER AUDIT v2.5\n');
fprintf(' NO REFIT - PARAMETER SENSITIVITY STUDY\n');
fprintf('============================================================\n\n');

%% ================================================================
% 1. SELECT DATABASE
% ================================================================

[fileDB,pathDB] = uigetfile('*.csv', ...
    'Select TTC_CONDITION_ASSIGNED_DATABASE.csv');

if isequal(fileDB,0)
    error('No database selected.');
end

T=readtable(fullfile(pathDB,fileDB));

fprintf('[1] DATABASE\n');
fprintf('File : %s\n',fileDB);
fprintf('Rows : %d\n',height(T));
fprintf('Vars : %d\n\n',width(T));

SA=getNumeric(T,{'SA_deg','SA','SlipAngle_deg','SlipAngle','Slip_Angle','Alpha'});
FY=getNumeric(T,{'FY_N','FY','Fy','LateralForce','Lateral_Force'});
FZ=getNumeric(T,{'FZ_N','FZ','Fz','VerticalLoad_N','VerticalLoad','Vertical_Load'});
IA=getNumeric(T,{'IA_deg','IA','Camber_deg','Camber','Inclination','CamberAngle'});

if hasVariable(T,{'P_psi','Pressure_psi','InflationPressure_psi'})
    P=getNumeric(T,{'P_psi','Pressure_psi','InflationPressure_psi'});
    fprintf('Pressure mapping : psi\n');
else
    P=getNumeric(T,{'P_kPa','P','Pressure_kPa','Pressure','InflationPressure','Inflation_Pressure'});
    if median(P,'omitnan')>40
        P=P*0.1450377377;
        fprintf('Pressure mapping : kPa -> psi\n');
    else
        fprintf('Pressure mapping : interpreted as psi\n');
    end
end

RUN=getNumeric(T,{'Run','RunID','Run_Id','RunNumber','Run_Number','TestRun'});

% Same force convention used by CMM v2.0.
FY=-FY;

good=isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)& ...
     isfinite(P)&isfinite(RUN)&FZ>0;

SA=SA(good);
FY=FY(good);
FZ=FZ(good);
IA=IA(good);
P=P(good);
RUN=RUN(good);

% Current model contract: Runs 2 and 4.
keep=ismember(round(RUN),[2 4]);

SA=SA(keep);
FY=FY(keep);
FZ=FZ(keep);
IA=IA(keep);
P=P(keep);
RUN=RUN(keep);

% Current v2.0 fitting envelope.
fitMask=FZ>=180 & FZ<=1150 & abs(SA)<=12.0;

SAfit=SA(fitMask);
FYfit=FY(fitMask);
FZfit=FZ(fitMask);
IAfit=IA(fitMask);
Pfit=P(fitMask);

fprintf('Rows after Run 2+4 contract : %d\n',numel(FY));
fprintf('Rows in v2.0 fit envelope  : %d\n\n',numel(FYfit));

%% ================================================================
% 2. SELECT MODEL
% ================================================================

[fileMF,pathMF]=uigetfile('*.mat', ...
    'Select CMM_GLOBAL_MF_LATERAL_v2_0.mat');

if isequal(fileMF,0)
    error('No MF model selected.');
end

S=load(fullfile(pathMF,fileMF));

if ~isfield(S,'GlobalMF')
    error('Selected MAT does not contain GlobalMF.');
end

M=S.GlobalMF;
q0=double(M.Parameters(:));

FZ0=M.Reference.Fz0_N;
P0=M.Reference.P0_psi;
IA0=M.Reference.IA0_deg;

fprintf('[2] MODEL\n');
fprintf('File : %s\n',fileMF);
fprintf('Fz0  : %.2f N\n',FZ0);
fprintf('P0   : %.2f psi\n',P0);
fprintf('IA0  : %.2f deg\n',IA0);
fprintf('Parameters : %d\n\n',numel(q0));

%% ================================================================
% 3. PARAMETER MAP
% ================================================================

nP=numel(q0);

paramNames=cell(nP,1);

defaultNames={ ...
    'PCY1','PDY1','PDY2','PDY3', ...
    'PEY1','PEY2', ...
    'PKY1','PKY2','PKY3', ...
    'PHY1','PHY2','PHY3', ...
    'PVY1','PVY2','PVY3','PVY4', ...
    'Pmu1','Pmu2','Pk1'};

for k=1:nP
    if k<=numel(defaultNames)
        paramNames{k}=defaultNames{k};
    else
        paramNames{k}=sprintf('Parameter_%02d',k);
    end
end

perturbPct=[-10 -5 0 5 10];

fprintf('[3] PARAMETER AUDIT\n');
fprintf('Parameters tested : %d\n',nP);
fprintf('Perturbations     : -10%% -5%% 0%% +5%% +10%%\n\n');

%% ================================================================
% 4. CREATE A SMALL REPRESENTATIVE VALIDATION SET
% ================================================================
%
% Full 112k point sensitivity testing for 19 parameters x 5 perturbations
% is unnecessary and can consume a lot of RAM.
%
% We use a deterministic subsample of the v2.0 fit envelope.

Nfull=numel(FYfit);

targetN=min(30000,Nfull);

rng(2508,'twister');

if Nfull>targetN
    idx=randperm(Nfull,targetN);
else
    idx=1:Nfull;
end

SAs=SAfit(idx);
FYs=FYfit(idx);
FZs=FZfit(idx);
IAs=IAfit(idx);
Ps=Pfit(idx);

fprintf('Sensitivity points : %d\n\n',numel(FYs));

%% ================================================================
% 5. BASELINE METRICS
% ================================================================

fprintf('============================================================\n');
fprintf(' BASELINE MODEL\n');
fprintf('============================================================\n');

base=cmmMetrics(q0,SAs,FYs,FZs,IAs,Ps,FZ0,P0,IA0);

fprintf('R2       : %.6f\n',base.R2);
fprintf('RMSE     : %.3f N\n',base.RMSE);
fprintf('MAE      : %.3f N\n',base.MAE);

refMask=abs(FZ-FZ0)<=10 & abs(P-P0)<=0.10 & ...
        abs(IA-IA0)<=0.10 & abs(SA)<=12;

refSA=SA(refMask);
refFY=FY(refMask);
refFZ=FZ(refMask);

if numel(refFY)>=30
    baseRef=cmmMetrics(q0,refSA,refFY,refFZ, ...
        IA(refMask),P(refMask),FZ0,P0,IA0);
else
    baseRef.R2=NaN;
    baseRef.RMSE=NaN;
    baseRef.MAE=NaN;
end

fprintf('Reference R2 : %.6f\n',baseRef.R2);
fprintf('Reference MAE: %.3f N\n\n',baseRef.MAE);

%% ================================================================
% 6. REFERENCE C-ALPHA
% ================================================================

baseRefExtra=referenceMetrics(q0,SA,FY,FZ,IA,P,FZ0,P0,IA0);

fprintf('Reference C-alpha : %.3f N/deg\n',baseRefExtra.Calpha);
fprintf('Reference peak mu : %.4f\n',baseRefExtra.PeakMu);
fprintf('Reference peak SA : %.3f deg\n\n',baseRefExtra.PeakSA);

%% ================================================================
% 7. RUN PARAMETER SWEEP
% ================================================================

rows={};
rowCount=0;

for p=1:nP

    fprintf('Testing %s (%d/%d)\n',paramNames{p},p,nP);

    for j=1:numel(perturbPct)

        pct=perturbPct(j);

        q=q0;

        % Relative perturbation.
        q(p)=q0(p)*(1+pct/100);

        % Avoid exact zero for parameters that are zero in the baseline.
        if q0(p)==0
            q(p)=q0(p)+sign(pct)*0.01;
        end

        met=cmmMetrics(q,SAs,FYs,FZs,IAs,Ps,FZ0,P0,IA0);
        refMet=referenceMetrics(q,SA,FY,FZ,IA,P,FZ0,P0,IA0);

        rowCount=rowCount+1;

        rows(rowCount,:)={ ...
            p, ...
            paramNames{p}, ...
            pct, ...
            q0(p), ...
            q(p), ...
            met.R2, ...
            met.RMSE, ...
            met.MAE, ...
            refMet.R2, ...
            refMet.RMSE, ...
            refMet.MAE, ...
            refMet.Calpha, ...
            refMet.PeakMu, ...
            refMet.PeakSA};
    end
end

SensitivityTable=cell2table(rows, ...
    'VariableNames',{ ...
    'ParameterIndex', ...
    'Parameter', ...
    'Perturbation_pct', ...
    'BaselineValue', ...
    'TestValue', ...
    'Global_R2', ...
    'Global_RMSE_N', ...
    'Global_MAE_N', ...
    'Reference_R2', ...
    'Reference_RMSE_N', ...
    'Reference_MAE_N', ...
    'Reference_Calpha_N_per_deg', ...
    'Reference_PeakMu', ...
    'Reference_PeakSA_deg'});

%% ================================================================
% 8. DERIVE SENSITIVITY SCORES
% ================================================================

fprintf('\n============================================================\n');
fprintf(' PARAMETER SENSITIVITY SUMMARY\n');
fprintf('============================================================\n');

Summary=table();

for p=1:nP

    m=SensitivityTable.ParameterIndex==p;

    r2=SensitivityTable.Global_R2(m);
    rmse=SensitivityTable.Global_RMSE_N(m);
    ca=SensitivityTable.Reference_Calpha_N_per_deg(m);
    mu=SensitivityTable.Reference_PeakMu(m);
    psa=SensitivityTable.Reference_PeakSA_deg(m);

    baseRow=SensitivityTable(m & ...
        SensitivityTable.Perturbation_pct==0,:);

    if isempty(baseRow)
        continue;
    end

    baseR2=baseRow.Global_R2;
    baseRMSE=baseRow.Global_RMSE_N;
    baseCA=baseRow.Reference_Calpha_N_per_deg;
    baseMu=baseRow.Reference_PeakMu;
    baseSA=baseRow.Reference_PeakSA_deg;

    maxDeltaR2=max(abs(r2-baseR2));
    maxDeltaRMSE=max(abs(rmse-baseRMSE));

    % Peak-mu sensitivity in percentage points.
    maxDeltaMu=max(abs(mu-baseMu));

    % C-alpha sensitivity in N/deg.
    maxDeltaCA=max(abs(ca-baseCA));

    % Peak-SA sensitivity in degrees.
    maxDeltaSA=max(abs(psa-baseSA));

    Summary=[Summary; ...
        table(p,string(paramNames{p}),maxDeltaR2,maxDeltaRMSE, ...
        maxDeltaCA,maxDeltaMu,maxDeltaSA, ...
        'VariableNames',{ ...
        'ParameterIndex','Parameter','MaxAbsDeltaR2', ...
        'MaxAbsDeltaRMSE_N','MaxAbsDeltaCalpha_N_per_deg', ...
        'MaxAbsDeltaPeakMu','MaxAbsDeltaPeakSA_deg'})]; %#ok<AGROW>
end

% Rank by impact on R2.
Summary=sortrows(Summary,'MaxAbsDeltaR2','descend');

disp(Summary);

%% ================================================================
% 9. SAVE RESULTS
% ================================================================

OUTDIR=fullfile(pathMF,'PARAMETER_AUDIT_v2_5');

if ~exist(OUTDIR,'dir')
    mkdir(OUTDIR);
end

writetable(SensitivityTable, ...
    fullfile(OUTDIR,'PARAMETER_SENSITIVITY_v2_5.csv'));

writetable(Summary, ...
    fullfile(OUTDIR,'PARAMETER_SENSITIVITY_SUMMARY_v2_5.csv'));

%% ================================================================
% 10. PLOTS
% ================================================================

% R2 sensitivity.
fig=figure('Color','w');

bar(Summary.MaxAbsDeltaR2);

grid on;
box on;

set(gca,'XTick',1:height(Summary), ...
    'XTickLabel',Summary.Parameter, ...
    'XTickLabelRotation',45);

ylabel('Maximum |Delta R^2|');
title('MF Parameter Sensitivity - Global R^2');

exportgraphics(fig,fullfile(OUTDIR, ...
    '01_PARAMETER_R2_SENSITIVITY.png'),'Resolution',180);

close(fig);

% RMSE sensitivity.
fig=figure('Color','w');

bar(Summary.MaxAbsDeltaRMSE_N);

grid on;
box on;

set(gca,'XTick',1:height(Summary), ...
    'XTickLabel',Summary.Parameter, ...
    'XTickLabelRotation',45);

ylabel('Maximum |Delta RMSE| [N]');
title('MF Parameter Sensitivity - Global RMSE');

exportgraphics(fig,fullfile(OUTDIR, ...
    '02_PARAMETER_RMSE_SENSITIVITY.png'),'Resolution',180);

close(fig);

% C-alpha sensitivity.
fig=figure('Color','w');

bar(Summary.MaxAbsDeltaCalpha_N_per_deg);

grid on;
box on;

set(gca,'XTick',1:height(Summary), ...
    'XTickLabel',Summary.Parameter, ...
    'XTickLabelRotation',45);

ylabel('Maximum |Delta C-alpha| [N/deg]');
title('MF Parameter Sensitivity - Cornering Stiffness');

exportgraphics(fig,fullfile(OUTDIR, ...
    '03_PARAMETER_CALPHA_SENSITIVITY.png'),'Resolution',180);

close(fig);

% Peak mu sensitivity.
fig=figure('Color','w');

bar(Summary.MaxAbsDeltaPeakMu);

grid on;
box on;

set(gca,'XTick',1:height(Summary), ...
    'XTickLabel',Summary.Parameter, ...
    'XTickLabelRotation',45);

ylabel('Maximum |Delta peak mu|');
title('MF Parameter Sensitivity - Peak Friction');

exportgraphics(fig,fullfile(OUTDIR, ...
    '04_PARAMETER_PEAKMU_SENSITIVITY.png'),'Resolution',180);

close(fig);

%% ================================================================
% 11. TOP PARAMETER REPORT
% ================================================================

fprintf('\n============================================================\n');
fprintf(' TOP PARAMETERS BY GLOBAL R2 SENSITIVITY\n');
fprintf('============================================================\n');

nTop=min(10,height(Summary));

for k=1:nTop
    fprintf('%2d. %-8s | dR2=%10.6f | dRMSE=%9.3f N | dC-alpha=%9.3f | dmu=%7.4f\n', ...
        k,Summary.Parameter(k), ...
        Summary.MaxAbsDeltaR2(k), ...
        Summary.MaxAbsDeltaRMSE_N(k), ...
        Summary.MaxAbsDeltaCalpha_N_per_deg(k), ...
        Summary.MaxAbsDeltaPeakMu(k));
end

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL PARAMETER AUDIT v2.5 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Output directory:\n%s\n',OUTDIR);
fprintf('\nNO MODEL PARAMETERS WERE CHANGED.\n');
fprintf('NO MAT FILE WAS OVERWRITTEN.\n');
fprintf('============================================================\n');

end

%% ================================================================
function met=cmmMetrics(q,SA,FY,FZ,IA,P,FZ0,P0,IA0)

pred=cmmMFglobal(q,SA,FZ,IA,P,FZ0,P0);

e=pred-FY;

SStot=sum((FY-mean(FY)).^2);
SSres=sum(e.^2);

met.R2=1-SSres/max(SStot,eps);
met.RMSE=sqrt(mean(e.^2));
met.MAE=mean(abs(e));

end

%% ================================================================
function out=referenceMetrics(q,SA,FY,FZ,IA,P,FZ0,P0,IA0)

ref=abs(FZ-FZ0)<=10 & ...
    abs(P-P0)<=0.10 & ...
    abs(IA-IA0)<=0.10 & ...
    abs(SA)<=12;

if nnz(ref)<30

    out.R2=NaN;
    out.RMSE=NaN;
    out.MAE=NaN;
    out.Calpha=NaN;
    out.PeakMu=NaN;
    out.PeakSA=NaN;
    return;
end

a=SA(ref);
y=FY(ref);
fz=FZ(ref);
ia=IA(ref);
p=P(ref);

pred=cmmMFglobal(q,a,fz,ia,p,FZ0,P0);

e=pred-y;

SStot=sum((y-mean(y)).^2);
SSres=sum(e.^2);

out.R2=1-SSres/max(SStot,eps);
out.RMSE=sqrt(mean(e.^2));
out.MAE=mean(abs(e));

% Reference C-alpha.
lin=abs(a)<=1.0;

if nnz(lin)>=20

    x=a(lin);
    yy=y(lin);

    x=x(:);
    yy=yy(:);

    pfit=polyfit(x,yy,1);

    out.Calpha=abs(pfit(1));
else
    out.Calpha=NaN;
end

% Reference MF/measurement peak from the same measured slip range.
grid=linspace(0,12,800)';

mf=cmmMFglobal(q,grid, ...
    FZ0*ones(size(grid)), ...
    IA0*ones(size(grid)), ...
    P0*ones(size(grid)),FZ0,P0);

out.PeakMu=max(abs(mf))/FZ0;

[~,im]=max(abs(mf));

out.PeakSA=grid(im);

end

%% ================================================================
function y=cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)

a=double(alphaDeg)*pi/180;
g=double(camberDeg)*pi/180;

Fz=max(double(Fz),1);

dfz=(Fz-Fz0)./Fz0;
dP=double(Ppsi)-P0;

PCY1=q(1);

PDY1=q(2);
PDY2=q(3);
PDY3=q(4);

PEY1=q(5);
PEY2=q(6);

PKY1=q(7);
PKY2=q(8);
PKY3=q(9);

PHY1=q(10);
PHY2=q(11);
PHY3=q(12);

PVY1=q(13);
PVY2=q(14);
PVY3=q(15);
PVY4=q(16);

Pmu1=q(17);
Pmu2=q(18);
Pk1=q(19);

Cy=PCY1;

mu=(PDY1+PDY2.*dfz).*(1-PDY3.*g.^2);

muP=1+Pmu1.*dP+Pmu2.*dP.^2;

mu=max(mu.*muP,0.20);

Dy=mu.*Fz;

Ey=max(-1,min(1,PEY1+PEY2.*dfz));

stiffCamber=max(0.10,1-PKY3.*g.^2);

Ky=PKY1.*Fz0.* ...
    sin(2.*atan(Fz./(PKY2.*Fz0))).*stiffCamber;

Ky=Ky.*(1+Pk1.*dP);

Ky=max(Ky,100);

By=Ky./max(Cy.*Dy,1);

Shy=PHY1+PHY2.*dfz+PHY3.*g;

Svy=Fz.*(PVY1+PVY2.*dfz)+ ...
    mu.*Fz.*(PVY3+PVY4.*dfz).*g;

alphaY=a+Shy;

x=By.*alphaY;

y=Dy.*sin(Cy.*atan( ...
    x-Ey.*(x-atan(x))))+Svy;

end

%% ================================================================
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

%% ================================================================
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
    error('Required variable not found. Tried: %s',strjoin(names,', '));
end

x=T{:,idx};

if iscell(x)
    x=str2double(string(x));
elseif isstring(x)||ischar(x)||iscategorical(x)
    x=str2double(string(x));
end

x=double(x(:));

end
