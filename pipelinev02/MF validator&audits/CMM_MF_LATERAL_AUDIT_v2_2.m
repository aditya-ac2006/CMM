function CMM_MF_LATERAL_AUDIT_v2_2
% ================================================================
% CMM MF LATERAL AUDIT v2.2
% NO REFIT - PEAK / SENSITIVITY / DATA-QUALITY AUDIT
% ================================================================
%
% Purpose:
%   Audit the v2.0 lateral MF without changing its parameters.
%   The previous validator used max(abs(FY)) over a broad raw-data band.
%   That can make a single noisy/boundary point look like a tire peak.
%
% This script:
%   1) Loads the same TTC condition database.
%   2) Loads the already-fitted v2.0 MAT.
%   3) Recomputes load/pressure/camber sensitivity using CONDITION-BINNED
%      median curves rather than a raw maximum.
%   4) Reports raw-envelope peak vs robust binned peak.
%   5) Reports peak slip angle and whether the peak is boundary-limited.
%   6) Audits the suspicious 210 N condition.
%   7) Checks the exact reference curve.
%   8) Does NOT refit anything.
%
% ================================================================

clc;
fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL AUDIT v2.2\n');
fprintf(' NO REFIT - PEAK / SENSITIVITY / DATA QUALITY AUDIT\n');
fprintf('============================================================\n\n');

%% ---------------- SELECT INPUTS ----------------
[fn,fp] = uigetfile({'*.csv','CSV files (*.csv)'}, ...
    'Select TTC_CONDITION_ASSIGNED_DATABASE.csv');
if isequal(fn,0), error('No database selected.'); end
INPUT_CSV = fullfile(fp,fn);

[mn,mp] = uigetfile({'*.mat','MAT files (*.mat)'}, ...
    'Select CMM_GLOBAL_MF_LATERAL_v2_0.mat');
if isequal(mn,0), error('No model selected.'); end
MODEL_MAT = fullfile(mp,mn);

S = load(MODEL_MAT);
if isfield(S,'GlobalMF')
    M = S.GlobalMF;
else
    error('Selected MAT does not contain GlobalMF.');
end

q = M.Parameters;
FZ0 = M.Reference.Fz0_N;
P0  = M.Reference.P0_psi;
IA0 = M.Reference.IA0_deg;

fprintf('[1] MODEL\n');
fprintf('File : %s\n',MODEL_MAT);
fprintf('Fz0  : %.2f N\n',FZ0);
fprintf('P0   : %.2f psi\n',P0);
fprintf('IA0  : %.2f deg\n\n',IA0);

%% ---------------- LOAD DATABASE ----------------
T = readtable(INPUT_CSV);

SA = getNumeric(T, {'SA_deg','SA','SlipAngle_deg','SlipAngle','Slip_Angle','Alpha'});
FY = getNumeric(T, {'FY_N','FY','Fy','LateralForce','Lateral_Force'});
FZ = getNumeric(T, {'FZ_N','FZ','Fz','VerticalLoad_N','VerticalLoad','Vertical_Load'});
IA = getNumeric(T, {'IA_deg','IA','Camber_deg','Camber','Inclination','CamberAngle'});

if hasVariable(T, {'P_psi','Pressure_psi','InflationPressure_psi'})
    P = getNumeric(T, {'P_psi','Pressure_psi','InflationPressure_psi'});
else
    P = getNumeric(T, {'P_kPa','P','Pressure_kPa','Pressure','InflationPressure','Inflation_Pressure'});
    if median(P,'omitnan') > 40
        P = P*0.1450377377;
    end
end

RUN = getNumeric(T, {'Run','RunID','Run_Id','RunNumber','Run_Number','TestRun'});

% Same explicit sign convention as v2.0.
FY = -FY;

good = isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)&isfinite(P)& ...
       isfinite(RUN)&FZ>0;

SA=SA(good); FY=FY(good); FZ=FZ(good);
IA=IA(good); P=P(good); RUN=RUN(good);

mrun = ismember(round(RUN),[2 4]);
SA=SA(mrun); FY=FY(mrun); FZ=FZ(mrun);
IA=IA(mrun); P=P(mrun); RUN=RUN(mrun);

fprintf('[2] DATABASE\n');
fprintf('Rows used : %d\n',numel(FY));
fprintf('Run 2     : %d\n',nnz(RUN==2));
fprintf('Run 4     : %d\n\n',nnz(RUN==4));

%% ---------------- REFERENCE CURVE AUDIT ----------------
fprintf('============================================================\n');
fprintf(' REFERENCE CURVE AUDIT\n');
fprintf('============================================================\n');

ref = abs(FZ-FZ0)<=10 & abs(P-P0)<=0.10 & abs(IA-IA0)<=0.10 & abs(SA)<=12.3;

fprintf('Reference samples : %d\n',nnz(ref));

if nnz(ref)<50
    warning('Reference sample count is low.');
end

[refSA,refFY] = robustCurve(SA(ref),FY(ref),0.05);

mfGrid = linspace(0,12.3,600)';
mfRef = cmmMFglobal(q,mfGrid,FZ0*ones(size(mfGrid)), ...
                    IA0*ones(size(mfGrid)),P0*ones(size(mfGrid)),FZ0,P0);

measPeak = max(abs(refFY));
[~,im] = max(abs(refFY));
measPeakSA = abs(refSA(im));
mfPeak = max(abs(mfRef));
[~,imf] = max(abs(mfRef));
mfPeakSA = abs(mfGrid(imf));

fprintf('Measured robust peak : %.2f N at %.2f deg\n',measPeak,measPeakSA);
fprintf('MF peak              : %.2f N at %.2f deg\n',mfPeak,mfPeakSA);
fprintf('Measured robust mu   : %.4f\n',measPeak/FZ0);
fprintf('MF mu                : %.4f\n\n',mfPeak/FZ0);

%% ---------------- LOAD AUDIT ----------------
loadCenters = [210 432 656 875 1096]';

fprintf('============================================================\n');
fprintf(' LOAD PEAK AUDIT\n');
fprintf('============================================================\n');
fprintf('Columns: raw-envelope peak is NOT used as the final estimate.\n');
fprintf('Robust peak = median-binned Fy curve within the condition band.\n\n');

loadRows = [];
for k=1:numel(loadCenters)
    fzc = loadCenters(k);

    band = abs(FZ-fzc)<=35 & abs(P-P0)<=0.35 & ...
           abs(IA)<=0.5 & abs(SA)<=12.3;

    rawN = nnz(band);

    if rawN<20
        continue;
    end

    rawMu = max(abs(FY(band)))/median(FZ(band));
    rawSA = abs(SA(find(band,1,'first')));

    [aCurve,yCurve] = robustCurve(SA(band),FY(band),0.10);

    if isempty(yCurve)
        continue;
    end

    [~,ip] = max(abs(yCurve));
    robustPeak = abs(yCurve(ip));
    robustSA = abs(aCurve(ip));
    robustMu = robustPeak/median(FZ(band));

    % Boundary test: peak within 0.25 deg of available curve limit.
    amax = max(abs(aCurve));
    boundary = robustSA >= amax-0.25;

    yy = cmmMFglobal(q,mfGrid,fzc*ones(size(mfGrid)), ...
        zeros(size(mfGrid)),P0*ones(size(mfGrid)),FZ0,P0);
    mfPeak = max(abs(yy))/fzc;

    fprintf('Fz %4.0f N | N=%5d | raw mu=%6.3f | robust mu=%6.3f | ', ...
        fzc,rawN,rawMu,robustMu);
    fprintf('robust SA=%5.2f deg | boundary=%d | MF mu=%6.3f\n', ...
        robustSA,boundary,mfPeak);

    loadRows = [loadRows; fzc rawN rawMu robustMu robustSA boundary mfPeak]; %#ok<AGROW>
end

%% ---------------- PRESSURE AUDIT ----------------
pressureCenters = [8.1 10.1 12.1 14.1]';

fprintf('\n============================================================\n');
fprintf(' PRESSURE PEAK AUDIT\n');
fprintf('============================================================\n');

pressureRows = [];
for k=1:numel(pressureCenters)
    pc = pressureCenters(k);

    band = abs(P-pc)<=0.35 & abs(FZ-FZ0)<=75 & ...
           abs(IA)<=0.5 & abs(SA)<=12.3;

    rawN=nnz(band);
    if rawN<20, continue; end

    rawMu=max(abs(FY(band)))/median(FZ(band));

    [aCurve,yCurve]=robustCurve(SA(band),FY(band),0.10);
    [~,ip]=max(abs(yCurve));
    robustPeak=abs(yCurve(ip));
    robustSA=abs(aCurve(ip));
    robustMu=robustPeak/median(FZ(band));
    boundary=robustSA >= max(abs(aCurve))-0.25;

    yy=cmmMFglobal(q,mfGrid,FZ0*ones(size(mfGrid)), ...
        zeros(size(mfGrid)),pc*ones(size(mfGrid)),FZ0,P0);
    mfMu=max(abs(yy))/FZ0;

    fprintf('P %5.1f psi | N=%5d | raw mu=%6.3f | robust mu=%6.3f | ', ...
        pc,rawN,rawMu,robustMu);
    fprintf('robust SA=%5.2f deg | boundary=%d | MF mu=%6.3f\n', ...
        robustSA,boundary,mfMu);

    pressureRows=[pressureRows; pc rawN rawMu robustMu robustSA boundary mfMu]; %#ok<AGROW>
end

%% ---------------- CAMBER AUDIT ----------------
camberCenters=[0 2 4]';

fprintf('\n============================================================\n');
fprintf(' CAMBER PEAK AUDIT\n');
fprintf('============================================================\n');

camberRows=[];
for k=1:numel(camberCenters)
    gc=camberCenters(k);

    band=abs(IA-gc)<=0.35 & abs(FZ-FZ0)<=75 & ...
         abs(P-P0)<=0.5 & abs(SA)<=12.3;

    rawN=nnz(band);
    if rawN<20, continue; end

    rawMu=max(abs(FY(band)))/median(FZ(band));

    [aCurve,yCurve]=robustCurve(SA(band),FY(band),0.10);
    [~,ip]=max(abs(yCurve));
    robustPeak=abs(yCurve(ip));
    robustSA=abs(aCurve(ip));
    robustMu=robustPeak/median(FZ(band));
    boundary=robustSA >= max(abs(aCurve))-0.25;

    yy=cmmMFglobal(q,mfGrid,FZ0*ones(size(mfGrid)), ...
        gc*ones(size(mfGrid)),P0*ones(size(mfGrid)),FZ0,P0);
    mfMu=max(abs(yy))/FZ0;

    fprintf('IA %3.0f deg | N=%5d | raw mu=%6.3f | robust mu=%6.3f | ', ...
        gc,rawN,rawMu,robustMu);
    fprintf('robust SA=%5.2f deg | boundary=%d | MF mu=%6.3f\n', ...
        robustSA,boundary,mfMu);

    camberRows=[camberRows; gc rawN rawMu robustMu robustSA boundary mfMu]; %#ok<AGROW>
end

%% ---------------- LOW-LOAD DEEP AUDIT ----------------
fprintf('\n============================================================\n');
fprintf(' 210 N LOW-LOAD DEEP AUDIT\n');
fprintf('============================================================\n');

band=abs(FZ-210)<=35 & abs(P-P0)<=0.35 & abs(IA)<=0.5 & abs(SA)<=12.3;

fprintf('Samples in band : %d\n',nnz(band));

if nnz(band)>0
    [aCurve,yCurve]=robustCurve(SA(band),FY(band),0.05);

    fprintf('Fz range        : %.2f -> %.2f N\n',min(FZ(band)),max(FZ(band)));
    fprintf('Fy range        : %.2f -> %.2f N\n',min(FY(band)),max(FY(band)));
    fprintf('SA range        : %.2f -> %.2f deg\n',min(SA(band)),max(SA(band)));

    [~,ip]=max(abs(yCurve));
    fprintf('Robust peak     : %.2f N\n',abs(yCurve(ip)));
    fprintf('Robust peak SA  : %.2f deg\n',abs(aCurve(ip)));
    fprintf('Robust mu       : %.4f\n',abs(yCurve(ip))/median(FZ(band)));

    % Count how many individual raw points exceed mu thresholds.
    muRaw=abs(FY(band))./FZ(band);
    fprintf('Raw point mu median : %.4f\n',median(muRaw));
    fprintf('Raw point mu 95%%ile : %.4f\n',prctile(muRaw,95));
    fprintf('Raw point mu max    : %.4f\n',max(muRaw));
    fprintf('Raw points mu > 3.0 : %d\n',nnz(muRaw>3.0));
end

%% ---------------- SAVE AUDIT TABLES ----------------
OUTDIR=fullfile(fp,'_MF_LATERAL_GLOBAL_v2_0','AUDIT_v2_2');
if ~exist(OUTDIR,'dir'), mkdir(OUTDIR); end

if ~isempty(loadRows)
    writetable(array2table(loadRows,'VariableNames', ...
        {'Fz_N','N','RawMu','RobustMu','RobustPeakSA_deg','Boundary','MF_mu'}), ...
        fullfile(OUTDIR,'LOAD_PEAK_AUDIT_v2_2.csv'));
end

if ~isempty(pressureRows)
    writetable(array2table(pressureRows,'VariableNames', ...
        {'Pressure_psi','N','RawMu','RobustMu','RobustPeakSA_deg','Boundary','MF_mu'}), ...
        fullfile(OUTDIR,'PRESSURE_PEAK_AUDIT_v2_2.csv'));
end

if ~isempty(camberRows)
    writetable(array2table(camberRows,'VariableNames', ...
        {'Camber_deg','N','RawMu','RobustMu','RobustPeakSA_deg','Boundary','MF_mu'}), ...
        fullfile(OUTDIR,'CAMBER_PEAK_AUDIT_v2_2.csv'));
end

% Save reference curve.
if ~isempty(refSA)
    writetable(table(refSA,refFY,'VariableNames',{'AbsSA_deg','Measured_Fy_N'}), ...
        fullfile(OUTDIR,'REFERENCE_ROBUST_CURVE_v2_2.csv'));
end

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL AUDIT v2.2 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Output: %s\n',OUTDIR);
fprintf('NO MODEL PARAMETERS WERE CHANGED.\n');
fprintf('============================================================\n');

end

%% ================================================================
function [aOut,yOut]=robustCurve(a,y,binWidth)
% Median Fy in slip-angle bins. Use absolute alpha and absolute Fy
% consistently for pure-lateral peak extraction.

a=abs(a(:));
y=y(:);

good=isfinite(a)&isfinite(y);
a=a(good); y=y(good);

if isempty(a)
    aOut=[]; yOut=[]; return;
end

edges=(0:binWidth:(max(a)+binWidth));
ib=discretize(a,edges);

n=max(ib);
aOut=zeros(n,1);
yOut=zeros(n,1);

for i=1:n
    m=ib==i;
    if any(m)
        aOut(i)=median(a(m),'omitnan');
        % Preserve the dominant force direction while taking magnitude.
        yOut(i)=median(y(m),'omitnan');
    end
end

good=isfinite(aOut)&isfinite(yOut);
aOut=aOut(good);
yOut=yOut(good);

[~,ord]=sort(aOut);
aOut=aOut(ord);
yOut=yOut(ord);
end

%% ================================================================
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
mu=max(mu.*muP,0.20);

Dy=mu.*Fz;

Ey=max(-1.0,min(1.0,PEY1+PEY2.*dfz));

stiffCamber=max(0.10,1-PKY3.*g.^2);
Ky=PKY1.*Fz0.*sin(2.*atan(Fz./(PKY2.*Fz0))).*stiffCamber;
Ky=Ky.*(1+Pk1.*dP);
Ky=max(Ky,100);

By=Ky./max(Cy.*Dy,1);

Shy=PHY1+PHY2.*dfz+PHY3.*g;
Svy=Fz.*(PVY1+PVY2.*dfz)+mu.*Fz.*(PVY3+PVY4.*dfz).*g;

alphaY=a+Shy;
x=By.*alphaY;

y=Dy.*sin(Cy.*atan(x-Ey.*(x-atan(x))))+Svy;
end

%% ================================================================
function tf=hasVariable(T,names)
vnames=string(T.Properties.VariableNames);
tf=false;
for k=1:numel(names)
    if any(strcmpi(vnames,string(names{k})))
        tf=true; return;
    end
end
end

%% ================================================================
function x=getNumeric(T,names)
vnames=string(T.Properties.VariableNames);
idx=find(ismember(lower(vnames),lower(string(names))),1);
if isempty(idx)
    error('Required variable not found. Tried: %s',strjoin(names,', '));
end
x=T.(T.Properties.VariableNames{idx});
if iscell(x), x=str2double(string(x)); end
if isstring(x), x=str2double(x); end
x=double(x);
x=x(:);
end
