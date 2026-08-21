function CMM_MF_LATERAL_PEAK_AUDIT_v2_3
% ================================================================
% CMM MF LATERAL PEAK AUDIT v2.3
% PEAK RESOLUTION / SWEEP-LIMIT AUDIT - NO REFIT
% ================================================================
%
% PURPOSE
%   Determine whether measured lateral-force peaks are actually resolved
%   inside the available TTC slip-angle sweep.
%
%   This script does NOT modify or refit the MF model.
%
%   For selected load / pressure / camber conditions it:
%       1) bins the measured Fy-alpha data,
%       2) smooths the binned curve,
%       3) calculates dFy/dAlpha,
%       4) classifies the measured peak,
%       5) compares the measured curve with the saved MF model,
%       6) distinguishes a true peak from a sweep-boundary value.
%
%   Status definitions:
%       RESOLVED
%       NEAR-PLATEAU
%       BOUNDARY-LIMITED
%       NO-RELIABLE-PEAK
%
% ================================================================

clc;
close all;

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL PEAK AUDIT v2.3\n');
fprintf(' PEAK RESOLUTION / SWEEP-LIMIT AUDIT - NO REFIT\n');
fprintf('============================================================\n\n');

%% ================================================================
% 1. SELECT DATABASE
% ================================================================

[fn,fp] = uigetfile('*.csv', ...
    'Select TTC_CONDITION_ASSIGNED_DATABASE.csv');

if isequal(fn,0)
    error('No database selected.');
end

T = readtable(fullfile(fp,fn));

fprintf('[1] DATABASE\n');
fprintf('File : %s\n',fn);
fprintf('Rows : %d\n',height(T));
fprintf('Vars : %d\n\n',width(T));

SA = getNumeric(T,{'SA_deg','SA','SlipAngle_deg','SlipAngle','Slip_Angle','Alpha'});
FY = getNumeric(T,{'FY_N','FY','Fy','LateralForce','Lateral_Force'});
FZ = getNumeric(T,{'FZ_N','FZ','Fz','VerticalLoad_N','VerticalLoad','Vertical_Load'});
IA = getNumeric(T,{'IA_deg','IA','Camber_deg','Camber','Inclination','CamberAngle'});

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

% Same CMM force sign convention used by v2.0/v2.2.
FY=-FY;

good=isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)& ...
     isfinite(P)&isfinite(RUN)&FZ>0;

SA=SA(good);
FY=FY(good);
FZ=FZ(good);
IA=IA(good);
P=P(good);
RUN=RUN(good);

keep=ismember(round(RUN),[2 4]);

SA=SA(keep);
FY=FY(keep);
FZ=FZ(keep);
IA=IA(keep);
P=P(keep);
RUN=RUN(keep);

fprintf('Rows used : %d\n',numel(FY));
fprintf('Run 2     : %d\n',nnz(round(RUN)==2));
fprintf('Run 4     : %d\n\n',nnz(round(RUN)==4));

%% ================================================================
% 2. SELECT MF MODEL
% ================================================================

[mn,mp]=uigetfile('*.mat', ...
    'Select CMM_GLOBAL_MF_LATERAL_v2_0.mat');

if isequal(mn,0)
    error('No model selected.');
end

S=load(fullfile(mp,mn));

if ~isfield(S,'GlobalMF')
    error('Selected MAT does not contain GlobalMF.');
end

M=S.GlobalMF;
q=M.Parameters;

FZ0=M.Reference.Fz0_N;
P0=M.Reference.P0_psi;
IA0=M.Reference.IA0_deg;

fprintf('[2] MF MODEL\n');
fprintf('File : %s\n',mn);
fprintf('Fz0  : %.2f N\n',FZ0);
fprintf('P0   : %.2f psi\n',P0);
fprintf('IA0  : %.2f deg\n\n',IA0);

%% ================================================================
% 3. AUDIT SETTINGS
% ================================================================

loadCenters=[210 432 656 875 1096];
pressureCenters=[8.1 10.1 12.1 14.1];
camberCenters=[0 2 4];

FZ_TOL=35;
P_TOL=0.35;
IA_TOL=0.50;

BIN=0.10;
SMOOTH_SPAN=7;

SWEEP_LIMIT=12.0;
BOUNDARY_MARGIN=0.25;
PLATEAU_SLOPE=12;       % N/deg
MIN_POINTS=30;

fprintf('[3] AUDIT SETTINGS\n');
fprintf('Slip-angle bin        : %.2f deg\n',BIN);
fprintf('Smoothing span        : %d bins\n',SMOOTH_SPAN);
fprintf('Sweep boundary        : +/- %.2f deg\n',SWEEP_LIMIT);
fprintf('Boundary margin       : %.2f deg\n',BOUNDARY_MARGIN);
fprintf('Near-plateau slope    : %.1f N/deg\n',PLATEAU_SLOPE);
fprintf('Minimum samples       : %d\n\n',MIN_POINTS);

%% ================================================================
% 4. BUILD CONDITION LIST
% ================================================================

conditions=[];

% Load sweep at reference pressure/camber.
for k=1:numel(loadCenters)
    conditions(end+1,:)=[loadCenters(k) P0 IA0 1]; %#ok<AGROW>
end

% Pressure sweep at reference load/camber.
for k=1:numel(pressureCenters)
    conditions(end+1,:)=[FZ0 pressureCenters(k) IA0 2]; %#ok<AGROW>
end

% Camber sweep at reference load/pressure.
for k=1:numel(camberCenters)
    conditions(end+1,:)=[FZ0 P0 camberCenters(k) 3]; %#ok<AGROW>
end

nC=size(conditions,1);

Results=cell(nC,1);

%% ================================================================
% 5. RUN CONDITION AUDIT
% ================================================================

fprintf('============================================================\n');
fprintf(' PEAK CLASSIFICATION\n');
fprintf('============================================================\n');

for c=1:nC

    fzc=conditions(c,1);
    pc=conditions(c,2);
    iac=conditions(c,3);

    band=abs(FZ-fzc)<=FZ_TOL & ...
         abs(P-pc)<=P_TOL & ...
         abs(IA-iac)<=IA_TOL & ...
         abs(SA)<=SWEEP_LIMIT;

    nRaw=nnz(band);

    if nRaw<MIN_POINTS
        status="NO-RELIABLE-PEAK";

        Results{c}=makeResult(fzc,pc,iac,nRaw,status, ...
            NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN);

        fprintf('%s\n',formatCondition(c,conditions(c,:),nRaw,status));
        continue;
    end

    [a,y,nBin]=binMedianSigned(SA(band),FY(band),BIN);

    if numel(a)<8
        status="NO-RELIABLE-PEAK";

        Results{c}=makeResult(fzc,pc,iac,nRaw,status, ...
            NaN,NaN,NaN,NaN,NaN,NaN,NaN,NaN);

        fprintf('%s\n',formatCondition(c,conditions(c,:),nRaw,status));
        continue;
    end

    % Smooth the binned curve only for classification.
    ys=smoothdata(y,'movmedian',SMOOTH_SPAN);
    ys=smoothdata(ys,'movmean',SMOOTH_SPAN);

    dy=gradient(ys,a);

    % Use magnitude consistently. We find the positive-force side and
    % negative-force side separately, then choose the stronger one.
    pos=a>=0;
    neg=a<=0;

    [pkPos,idxPos]=max(ys(pos));
    apos=a(pos);
    dpos=dy(pos);

    [pkNegAbs,idxNeg]=max(abs(ys(neg)));
    aneg=a(neg);
    dneg=dy(neg);

    if isempty(pkPos) || isempty(pkNegAbs)
        status="NO-RELIABLE-PEAK";
        peakFy=NaN; peakSA=NaN; peakSlope=NaN;
    elseif pkPos>=pkNegAbs
        peakFy=pkPos;
        peakSA=apos(idxPos);
        peakSlope=dpos(idxPos);
    else
        peakFy=pkNegAbs;
        peakSA=abs(aneg(idxNeg));
        peakSlope=dneg(idxNeg);
    end

    % Peak status.
    if ~isfinite(peakFy) || peakFy<=0
        status="NO-RELIABLE-PEAK";
    else
        % Peak near the positive/negative sweep boundary.
        atBoundary=peakSA >= SWEEP_LIMIT-BOUNDARY_MARGIN;

        % Determine whether force is still rising at the last 1 degree.
        edge=a>=max(a)-1.0;
        edgeSlope=median(abs(dy(edge)),'omitnan');

        % A peak with a very small slope and a broad plateau is not a
        % precisely resolved maximum, even if it occurs before the edge.
        nearPlateau=edgeSlope<=PLATEAU_SLOPE;

        if atBoundary && ~nearPlateau
            status="BOUNDARY-LIMITED";
        elseif atBoundary && nearPlateau
            status="NEAR-PLATEAU";
        elseif abs(peakSlope)<=PLATEAU_SLOPE
            status="NEAR-PLATEAU";
        else
            status="RESOLVED";
        end
    end

    % Raw envelope for comparison only.
    rawMu=max(abs(FY(band)))/median(FZ(band));
    robustMu=peakFy/median(FZ(band));

    % MF curve.
    alphaGrid=linspace(0,SWEEP_LIMIT,800)';
    mfFy=cmmMFglobal(q,alphaGrid, ...
        fzc*ones(size(alphaGrid)), ...
        iac*ones(size(alphaGrid)), ...
        pc*ones(size(alphaGrid)),FZ0,P0);

    [mfPeak,imf]=max(abs(mfFy));
    mfPeakSA=alphaGrid(imf);

    fprintf('%s\n',formatCondition(c,conditions(c,:),nRaw,status, ...
        robustMu,peakSA,mfPeak/fzc,mfPeakSA,peakSlope,edgeSlope));

    Results{c}=makeResult(fzc,pc,iac,nRaw,status, ...
        rawMu,robustMu,peakSA,peakSlope,edgeSlope, ...
        mfPeak/fzc,mfPeakSA);
end

%% ================================================================
% 6. RESULTS TABLE
% ================================================================

R=vertcat(Results{:});

fprintf('\n============================================================\n');
fprintf(' STATUS COUNTS\n');
fprintf('============================================================\n');

statuses=unique(string(R.Status));

for k=1:numel(statuses)
    fprintf('%-20s : %d\n',statuses(k),nnz(string(R.Status)==statuses(k)));
end

disp(R);

%% ================================================================
% 7. PLOTS
% ================================================================

OUTDIR=fullfile(mp,'PEAK_AUDIT_v2_3');

if ~exist(OUTDIR,'dir')
    mkdir(OUTDIR);
end

fprintf('\nGenerating diagnostic plots...\n');

% One plot per load condition.
for k=1:numel(loadCenters)

    fzc=loadCenters(k);

    band=abs(FZ-fzc)<=FZ_TOL & ...
         abs(P-P0)<=P_TOL & ...
         abs(IA-IA0)<=IA_TOL & ...
         abs(SA)<=SWEEP_LIMIT;

    [a,y,nBin]=binMedianSigned(SA(band),FY(band),BIN);

    if numel(a)<8
        continue;
    end

    ys=smoothdata(y,'movmedian',SMOOTH_SPAN);
    ys=smoothdata(ys,'movmean',SMOOTH_SPAN);

    alphaGrid=linspace(-SWEEP_LIMIT,SWEEP_LIMIT,1200)';
    mf=cmmMFglobal(q,alphaGrid, ...
        fzc*ones(size(alphaGrid)), ...
        IA0*ones(size(alphaGrid)), ...
        P0*ones(size(alphaGrid)),FZ0,P0);

    fig=figure('Color','w');

    plot(a,y,'o'); hold on;
    plot(a,ys,'LineWidth',2);
    plot(alphaGrid,mf,'LineWidth',2);

    xline(-SWEEP_LIMIT,'--');
    xline(SWEEP_LIMIT,'--');

    grid on;
    box on;

    xlabel('\alpha [deg]');
    ylabel('F_y [N]');

    title(sprintf('Peak Audit: F_z = %.0f N',fzc));

    legend('Measured binned','Measured smoothed','MF','Sweep limit', ...
        'Location','best');

    exportgraphics(fig,fullfile(OUTDIR, ...
        sprintf('LOAD_%04dN.png',fzc)),'Resolution',180);

    close(fig);
end

% Reference curve.
band=abs(FZ-FZ0)<=10 & abs(P-P0)<=0.10 & ...
     abs(IA-IA0)<=0.10 & abs(SA)<=SWEEP_LIMIT;

[a,y,~]=binMedianSigned(SA(band),FY(band),BIN);

if numel(a)>=8

    ys=smoothdata(y,'movmedian',SMOOTH_SPAN);
    ys=smoothdata(ys,'movmean',SMOOTH_SPAN);

    alphaGrid=linspace(-SWEEP_LIMIT,SWEEP_LIMIT,1200)';
    mf=cmmMFglobal(q,alphaGrid, ...
        FZ0*ones(size(alphaGrid)), ...
        IA0*ones(size(alphaGrid)), ...
        P0*ones(size(alphaGrid)),FZ0,P0);

    fig=figure('Color','w');

    plot(a,y,'o'); hold on;
    plot(a,ys,'LineWidth',2);
    plot(alphaGrid,mf,'LineWidth',2);

    xline(-SWEEP_LIMIT,'--');
    xline(SWEEP_LIMIT,'--');

    grid on;
    box on;

    xlabel('\alpha [deg]');
    ylabel('F_y [N]');

    title('Reference Peak Resolution Audit');

    legend('Measured binned','Measured smoothed','MF','Sweep limit', ...
        'Location','best');

    exportgraphics(fig,fullfile(OUTDIR, ...
        'REFERENCE_PEAK_AUDIT.png'),'Resolution',180);

    close(fig);
end

% Peak SA summary.
fig=figure('Color','w');

plot(R.Fz_N,R.MeasuredPeakSA_deg,'o-','LineWidth',1.8); hold on;
yline(SWEEP_LIMIT,'--','LineWidth',1.2);

grid on;
box on;

xlabel('F_z [N]');
ylabel('Measured peak candidate |\alpha| [deg]');

title('Measured Peak Location vs Sweep Limit');

legend('Measured candidate','Sweep limit','Location','best');

exportgraphics(fig,fullfile(OUTDIR, ...
    'PEAK_LOCATION_VS_LOAD.png'),'Resolution',180);

close(fig);

%% ================================================================
% 8. SAVE RESULTS
% ================================================================

writetable(R,fullfile(OUTDIR,'PEAK_CLASSIFICATION_v2_3.csv'));

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL PEAK AUDIT v2.3 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Output directory:\n%s\n',OUTDIR);
fprintf('NO MODEL PARAMETERS WERE CHANGED.\n');
fprintf('============================================================\n');

end

%% ================================================================
function R=makeResult(fz,p,ia,n,status,rawMu,robustMu,peakSA,peakSlope,edgeSlope,mfMu,mfSA)

R=table(fz,p,ia,n,string(status),rawMu,robustMu,peakSA, ...
    peakSlope,edgeSlope,mfMu,mfSA, ...
    'VariableNames',{'Fz_N','Pressure_psi','Camber_deg','N', ...
    'Status','RawMu','RobustMu','MeasuredPeakSA_deg', ...
    'PeakSlope_N_per_deg','EdgeSlope_N_per_deg','MF_mu','MF_peakSA_deg'});
end

%% ================================================================
function s=formatCondition(k,c,n,status,varargin)

if numel(varargin)>=6
    robustMu=varargin{1};
    peakSA=varargin{2};
    mfMu=varargin{3};
    mfSA=varargin{4};
    peakSlope=varargin{5};
    edgeSlope=varargin{6};

    s=sprintf(['%02d | Fz=%6.1f N | P=%5.2f psi | IA=%5.2f deg | ', ...
        'N=%5d | %-17s | robust mu=%6.3f | peak SA=%5.2f | ', ...
        'slope=%7.1f | edge=%7.1f | MF mu=%6.3f | MF SA=%5.2f'], ...
        k,c(1),c(2),c(3),n,status,robustMu,peakSA, ...
        peakSlope,edgeSlope,mfMu,mfSA);
else
    s=sprintf('%02d | Fz=%6.1f N | P=%5.2f psi | IA=%5.2f deg | N=%5d | %s', ...
        k,c(1),c(2),c(3),n,status);
end
end

%% ================================================================
function [aOut,yOut,nOut]=binMedianSigned(a,y,binWidth)

a=a(:);
y=y(:);

good=isfinite(a)&isfinite(y);

a=a(good);
y=y(good);

if isempty(a)
    aOut=[]; yOut=[]; nOut=[]; return;
end

amin=floor(min(a)/binWidth)*binWidth;
amax=ceil(max(a)/binWidth)*binWidth;

edges=amin:binWidth:amax;

if numel(edges)<3
    aOut=[]; yOut=[]; nOut=[]; return;
end

ib=discretize(a,edges);

n=max(ib);
aOut=zeros(n,1);
yOut=zeros(n,1);
nOut=zeros(n,1);

for i=1:n

    m=ib==i;

    if any(m)
        aOut(i)=median(a(m),'omitnan');
        yOut(i)=median(y(m),'omitnan');
        nOut(i)=nnz(m);
    end

end

good=isfinite(aOut)&isfinite(yOut)&nOut>0;

aOut=aOut(good);
yOut=yOut(good);
nOut=nOut(good);

[aOut,ord]=sort(aOut);
yOut=yOut(ord);
nOut=nOut(ord);
end

%% ================================================================
function y=cmmMFglobal(q,alphaDeg,Fz,camberDeg,Ppsi,Fz0,P0)

a=double(alphaDeg)*pi/180;
g=double(camberDeg)*pi/180;
Fz=max(double(Fz),1);

dfz=(Fz-Fz0)./Fz0;
dP=double(Ppsi)-P0;

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

Ey=max(-1,min(1,PEY1+PEY2.*dfz));

stiffCamber=max(0.10,1-PKY3.*g.^2);

Ky=PKY1.*Fz0.*sin(2.*atan(Fz./(PKY2.*Fz0))).*stiffCamber;

Ky=Ky.*(1+Pk1.*dP);
Ky=max(Ky,100);

By=Ky./max(Cy.*Dy,1);

Shy=PHY1+PHY2.*dfz+PHY3.*g;

Svy=Fz.*(PVY1+PVY2.*dfz)+ ...
    mu.*Fz.*(PVY3+PVY4.*dfz).*g;

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
