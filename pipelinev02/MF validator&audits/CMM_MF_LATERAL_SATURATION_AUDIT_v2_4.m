function CMM_MF_LATERAL_SATURATION_AUDIT_v2_4
% ================================================================
% CMM MF LATERAL SATURATION-SHAPE AUDIT v2.4
% NO REFIT - MEASURED vs MF SHAPE COMPARISON
% ================================================================
%
% PURPOSE
%   Compare the measured TTC lateral-force curve against the saved
%   v2.0 MF model at fixed slip-angle points.
%
%   This script does NOT change or refit the model.
%
%   Main question:
%       WHERE does the MF curve begin to diverge from the measured tire?
%
%   Slip-angle checkpoints:
%       1, 2, 4, 6, 8, 9, 10, 11, 12 deg
%
%   Conditions:
%       Fz = 210, 432, 656, 875, 1096 N
%       P  = 12.1 psi
%       IA = 0 deg
%
%   Also produces:
%       - measured-vs-MF curve plots
%       - normalized Fy/Fy_peak comparison
%       - residual vs slip angle
%       - checkpoint error table
%       - saturation onset estimate
%
% ================================================================

clc;
close all;

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL SATURATION-SHAPE AUDIT v2.4\n');
fprintf(' NO REFIT - MEASURED vs MF SHAPE COMPARISON\n');
fprintf('============================================================\n\n');

%% ================================================================
% 1. SELECT DATABASE
% ================================================================

[fileDB,pathDB] = uigetfile('*.csv', ...
    'Select TTC_CONDITION_ASSIGNED_DATABASE.csv');

if isequal(fileDB,0)
    error('No database selected.');
end

T = readtable(fullfile(pathDB,fileDB));

fprintf('[1] DATABASE\n');
fprintf('File : %s\n',fileDB);
fprintf('Rows : %d\n',height(T));
fprintf('Vars : %d\n\n',width(T));

SA = getNumeric(T,{'SA_deg','SA','SlipAngle_deg','SlipAngle','Slip_Angle','Alpha'});
FY = getNumeric(T,{'FY_N','FY','Fy','LateralForce','Lateral_Force'});
FZ = getNumeric(T,{'FZ_N','FZ','Fz','VerticalLoad_N','VerticalLoad','Vertical_Load'});
IA = getNumeric(T,{'IA_deg','IA','Camber_deg','Camber','Inclination','CamberAngle'});

if hasVariable(T,{'P_psi','Pressure_psi','InflationPressure_psi'})
    P = getNumeric(T,{'P_psi','Pressure_psi','InflationPressure_psi'});
    fprintf('Pressure mapping : psi\n');
else
    P = getNumeric(T,{'P_kPa','P','Pressure_kPa','Pressure','InflationPressure','Inflation_Pressure'});
    if median(P,'omitnan') > 40
        P = P*0.1450377377;
        fprintf('Pressure mapping : kPa -> psi\n');
    else
        fprintf('Pressure mapping : interpreted as psi\n');
    end
end

RUN = getNumeric(T,{'Run','RunID','Run_Id','RunNumber','Run_Number','TestRun'});

% Same CMM sign convention used by v2.0.
FY = -FY;

good = isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)& ...
       isfinite(P)&isfinite(RUN)&FZ>0;

SA=SA(good);
FY=FY(good);
FZ=FZ(good);
IA=IA(good);
P=P(good);
RUN=RUN(good);

keep = ismember(round(RUN),[2 4]);

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
% 2. SELECT MODEL
% ================================================================

[fileMF,pathMF] = uigetfile('*.mat', ...
    'Select CMM_GLOBAL_MF_LATERAL_v2_0.mat');

if isequal(fileMF,0)
    error('No MF model selected.');
end

S = load(fullfile(pathMF,fileMF));

if ~isfield(S,'GlobalMF')
    error('Selected MAT does not contain GlobalMF.');
end

M=S.GlobalMF;
q=M.Parameters;

FZ0=M.Reference.Fz0_N;
P0=M.Reference.P0_psi;
IA0=M.Reference.IA0_deg;

fprintf('[2] MODEL\n');
fprintf('File : %s\n',fileMF);
fprintf('Fz0  : %.2f N\n',FZ0);
fprintf('P0   : %.2f psi\n',P0);
fprintf('IA0  : %.2f deg\n\n',IA0);

%% ================================================================
% 3. AUDIT SETTINGS
% ================================================================

loadCenters=[210 432 656 875 1096];

alphaCheck=[1 2 4 6 8 9 10 11 12];

FZ_TOL=35;
P_TOL=0.35;
IA_TOL=0.50;

BIN=0.10;
SMOOTH_SPAN=7;

fprintf('[3] AUDIT SETTINGS\n');
fprintf('Loads       : ');
fprintf('%.0f ',loadCenters);
fprintf('N\n');

fprintf('Alpha check : ');
fprintf('%.0f ',alphaCheck);
fprintf('deg\n');

fprintf('Fz tolerance: +/- %.1f N\n',FZ_TOL);
fprintf('P tolerance : +/- %.2f psi\n',P_TOL);
fprintf('IA tolerance: +/- %.2f deg\n',IA_TOL);
fprintf('Bin width   : %.2f deg\n\n',BIN);

%% ================================================================
% 4. PREALLOCATE
% ================================================================

nL=numel(loadCenters);
nA=numel(alphaCheck);

MeasuredFy=nan(nL,nA);
MFFy=nan(nL,nA);

MeasuredMu=nan(nL,nA);
MFMu=nan(nL,nA);

MeasuredN=zeros(nL,1);
MeasuredPeak=nan(nL,1);
MFPeak=nan(nL,1);

MeasuredPeakSA=nan(nL,1);
MFPeakSA=nan(nL,1);

%% ================================================================
% 5. CONDITION CURVE EXTRACTION
% ================================================================

fprintf('============================================================\n');
fprintf(' SATURATION-SHAPE CHECKPOINTS\n');
fprintf('============================================================\n');

for k=1:nL

    fzc=loadCenters(k);

    band=abs(FZ-fzc)<=FZ_TOL & ...
         abs(P-P0)<=P_TOL & ...
         abs(IA-IA0)<=IA_TOL & ...
         abs(SA)<=12.0;

    MeasuredN(k)=nnz(band);

    if MeasuredN(k)<30
        warning('Too few samples at Fz = %.0f N.',fzc);
        continue;
    end

    [a,y]=binMedianCurve(SA(band),FY(band),BIN);

    if numel(a)<10
        continue;
    end

    % Smooth only to estimate curve shape. Raw binned values are retained.
    ys=smoothdata(y,'movmedian',SMOOTH_SPAN);
    ys=smoothdata(ys,'movmean',SMOOTH_SPAN);

    % Use the positive slip-angle branch for the main comparison.
    pos=a>=0;
    ap=a(pos);
    yp=ys(pos);

    [MeasuredPeak(k),ip]=max(abs(yp));
    MeasuredPeakSA(k)=ap(ip);

    alphaMF=linspace(0,12,1000)';

    yMF=cmmMFglobal(q,alphaMF, ...
        fzc*ones(size(alphaMF)), ...
        IA0*ones(size(alphaMF)), ...
        P0*ones(size(alphaMF)),FZ0,P0);

    [MFPeak(k),imf]=max(abs(yMF));
    MFPeakSA(k)=alphaMF(imf);

    % Interpolate measured smoothed curve at checkpoints.
    for j=1:nA

        aa=alphaCheck(j);

        if aa>=min(ap) && aa<=max(ap)
            MeasuredFy(k,j)=interp1(ap,yp,aa,'linear',NaN);
        end

        MFFy(k,j)=interp1(alphaMF,yMF,aa,'linear',NaN);

        if isfinite(MeasuredFy(k,j))
            MeasuredMu(k,j)=MeasuredFy(k,j)/fzc;
        end

        if isfinite(MFFy(k,j))
            MFMu(k,j)=MFFy(k,j)/fzc;
        end
    end

    fprintf('\nFz = %.0f N | N = %d\n',fzc,MeasuredN(k));
    fprintf('Measured peak candidate : %.2f N at %.2f deg\n', ...
        MeasuredPeak(k),MeasuredPeakSA(k));
    fprintf('MF peak                 : %.2f N at %.2f deg\n', ...
        MFPeak(k),MFPeakSA(k));

    fprintf('Alpha    Measured Fy    MF Fy    Error %%\n');

    for j=1:nA

        if isfinite(MeasuredFy(k,j))

            e=100*(MFFy(k,j)-MeasuredFy(k,j))/ ...
                max(abs(MeasuredFy(k,j)),1);

            fprintf('%5.1f    %10.2f    %8.2f    %+8.2f\n', ...
                alphaCheck(j),MeasuredFy(k,j),MFFy(k,j),e);

        end
    end
end

%% ================================================================
% 6. ERROR BY SLIP ANGLE
% ================================================================

ErrorPct=100*(MFFy-MeasuredFy)./max(abs(MeasuredFy),1);

MeanAbsErrorByAlpha=nan(1,nA);
MedianAbsErrorByAlpha=nan(1,nA);

for j=1:nA

    e=abs(ErrorPct(:,j));
    e=e(isfinite(e));

    if ~isempty(e)
        MeanAbsErrorByAlpha(j)=mean(e);
        MedianAbsErrorByAlpha(j)=median(e);
    end
end

fprintf('\n============================================================\n');
fprintf(' ERROR BY SLIP ANGLE\n');
fprintf('============================================================\n');

fprintf('Alpha    Mean abs error    Median abs error\n');

for j=1:nA
    fprintf('%5.1f    %14.3f %%    %17.3f %%\n', ...
        alphaCheck(j),MeanAbsErrorByAlpha(j),MedianAbsErrorByAlpha(j));
end

%% ================================================================
% 7. NORMALIZED SATURATION SHAPE
% ================================================================

NormMeasured=nan(size(MeasuredFy));
NormMF=nan(size(MFFy));

for k=1:nL

    if isfinite(MeasuredPeak(k))
        NormMeasured(k,:)=MeasuredFy(k,:)/MeasuredPeak(k);
    end

    if isfinite(MFPeak(k))
        NormMF(k,:)=MFFy(k,:)/MFPeak(k);
    end
end

ShapeErrorPct=100*(NormMF-NormMeasured)./ ...
    max(abs(NormMeasured),0.05);

fprintf('\n============================================================\n');
fprintf(' NORMALIZED SHAPE ERROR\n');
fprintf('============================================================\n');

fprintf('Alpha    Mean abs shape error\n');

for j=1:nA

    e=abs(ShapeErrorPct(:,j));
    e=e(isfinite(e));

    if isempty(e)
        v=NaN;
    else
        v=mean(e);
    end

    fprintf('%5.1f    %20.3f %%\n',alphaCheck(j),v);
end

%% ================================================================
% 8. FIND SATURATION ONSET
% ================================================================
%
% Define saturation onset as the first checkpoint at which the
% normalized measured force reaches >= 95% of its measured candidate
% peak. This is descriptive, not a fitted physical parameter.

SatOnsetMeasured=nan(nL,1);
SatOnsetMF=nan(nL,1);

for k=1:nL

    if isfinite(MeasuredPeak(k))

        m=NormMeasured(k,:)>=0.95;

        idx=find(m,1,'first');

        if ~isempty(idx)
            SatOnsetMeasured(k)=alphaCheck(idx);
        end
    end

    if isfinite(MFPeak(k))

        m=NormMF(k,:)>=0.95;

        idx=find(m,1,'first');

        if ~isempty(idx)
            SatOnsetMF(k)=alphaCheck(idx);
        end
    end
end

fprintf('\n============================================================\n');
fprintf(' SATURATION ONSET\n');
fprintf('============================================================\n');

fprintf('Fz       Measured onset    MF onset\n');

for k=1:nL
    fprintf('%4.0f N       %6.2f deg       %6.2f deg\n', ...
        loadCenters(k),SatOnsetMeasured(k),SatOnsetMF(k));
end

%% ================================================================
% 9. OUTPUT DIRECTORY
% ================================================================

OUTDIR=fullfile(pathMF,'SATURATION_AUDIT_v2_4');

if ~exist(OUTDIR,'dir')
    mkdir(OUTDIR);
end

%% ================================================================
% 10. FIGURES - INDIVIDUAL LOAD CURVES
% ================================================================

for k=1:nL

    fzc=loadCenters(k);

    band=abs(FZ-fzc)<=FZ_TOL & ...
         abs(P-P0)<=P_TOL & ...
         abs(IA-IA0)<=IA_TOL & ...
         abs(SA)<=12.0;

    [a,y]=binMedianCurve(SA(band),FY(band),BIN);

    if numel(a)<10
        continue;
    end

    ys=smoothdata(y,'movmedian',SMOOTH_SPAN);
    ys=smoothdata(ys,'movmean',SMOOTH_SPAN);

    alphaMF=linspace(0,12,1000)';
    yMF=cmmMFglobal(q,alphaMF, ...
        fzc*ones(size(alphaMF)), ...
        IA0*ones(size(alphaMF)), ...
        P0*ones(size(alphaMF)),FZ0,P0);

    fig=figure('Color','w');

    plot(a(a>=0),ys(a>=0),'o-','LineWidth',1.3); hold on;
    plot(alphaMF,yMF,'LineWidth',2);

    for j=1:nA
        xline(alphaCheck(j),':');
    end

    grid on;
    box on;

    xlabel('\alpha [deg]');
    ylabel('F_y [N]');

    title(sprintf('Saturation Shape: F_z = %.0f N',fzc));

    legend('Measured','MF','Location','southeast');

    exportgraphics(fig,fullfile(OUTDIR, ...
        sprintf('01_FY_ALPHA_%04dN.png',fzc)), ...
        'Resolution',180);

    close(fig);
end

%% ================================================================
% 11. NORMALIZED SHAPE PLOT
% ================================================================

fig=figure('Color','w');

for k=1:nL
    plot(alphaCheck,NormMeasured(k,:),'-o','LineWidth',1.4); hold on;
end

grid on;
box on;

xlabel('\alpha [deg]');
ylabel('F_y / F_{y,peak}');

title('Measured Normalized Saturation Shape');

legend(compose('F_z = %.0f N',loadCenters), ...
    'Location','southeast');

exportgraphics(fig,fullfile(OUTDIR, ...
    '02_MEASURED_NORMALIZED_SHAPE.png'),'Resolution',180);

close(fig);

fig=figure('Color','w');

for k=1:nL
    plot(alphaCheck,NormMF(k,:),'-s','LineWidth',1.4); hold on;
end

grid on;
box on;

xlabel('\alpha [deg]');
ylabel('F_y / F_{y,peak}');

title('MF Normalized Saturation Shape');

legend(compose('F_z = %.0f N',loadCenters), ...
    'Location','southeast');

exportgraphics(fig,fullfile(OUTDIR, ...
    '03_MF_NORMALIZED_SHAPE.png'),'Resolution',180);

close(fig);

%% ================================================================
% 12. ERROR VS ALPHA
% ================================================================

fig=figure('Color','w');

plot(alphaCheck,MeanAbsErrorByAlpha,'-o','LineWidth',2); hold on;
plot(alphaCheck,MedianAbsErrorByAlpha,'-s','LineWidth',2);

grid on;
box on;

xlabel('\alpha [deg]');
ylabel('Absolute error [%]');

title('MF vs Measured Error by Slip Angle');

legend('Mean absolute','Median absolute','Location','best');

exportgraphics(fig,fullfile(OUTDIR, ...
    '04_ERROR_VS_ALPHA.png'),'Resolution',180);

close(fig);

%% ================================================================
% 13. SHAPE ERROR VS ALPHA
% ================================================================

meanShapeError=nan(1,nA);

for j=1:nA

    e=abs(ShapeErrorPct(:,j));
    e=e(isfinite(e));

    if ~isempty(e)
        meanShapeError(j)=mean(e);
    end
end

fig=figure('Color','w');

plot(alphaCheck,meanShapeError,'-o','LineWidth',2);

grid on;
box on;

xlabel('\alpha [deg]');
ylabel('Normalized shape error [%]');

title('MF Saturation-Shape Error');

exportgraphics(fig,fullfile(OUTDIR, ...
    '05_NORMALIZED_SHAPE_ERROR.png'),'Resolution',180);

close(fig);

%% ================================================================
% 14. SAVE TABLES
% ================================================================

% Long-form checkpoint table.
rows=[];

for k=1:nL
    for j=1:nA

        rows=[rows; ...
            loadCenters(k), ...
            alphaCheck(j), ...
            MeasuredFy(k,j), ...
            MFFy(k,j), ...
            ErrorPct(k,j), ...
            NormMeasured(k,j), ...
            NormMF(k,j), ...
            ShapeErrorPct(k,j)]; %#ok<AGROW>
    end
end

CheckpointTable=array2table(rows, ...
    'VariableNames',{ ...
    'Fz_N', ...
    'Alpha_deg', ...
    'Measured_Fy_N', ...
    'MF_Fy_N', ...
    'Fy_Error_pct', ...
    'Measured_Normalized', ...
    'MF_Normalized', ...
    'Shape_Error_pct'});

writetable(CheckpointTable, ...
    fullfile(OUTDIR,'SATURATION_CHECKPOINTS_v2_4.csv'));

SummaryTable=table( ...
    loadCenters(:), ...
    MeasuredN, ...
    MeasuredPeak, ...
    MeasuredPeakSA, ...
    MFPeak, ...
    MFPeakSA, ...
    SatOnsetMeasured, ...
    SatOnsetMF, ...
    'VariableNames',{ ...
    'Fz_N', ...
    'N', ...
    'Measured_Peak_N', ...
    'Measured_PeakSA_deg', ...
    'MF_Peak_N', ...
    'MF_PeakSA_deg', ...
    'Measured_SaturationOnset_deg', ...
    'MF_SaturationOnset_deg'});

writetable(SummaryTable, ...
    fullfile(OUTDIR,'SATURATION_SUMMARY_v2_4.csv'));

ErrorTable=table( ...
    alphaCheck(:), ...
    MeanAbsErrorByAlpha(:), ...
    MedianAbsErrorByAlpha(:), ...
    meanShapeError(:), ...
    'VariableNames',{ ...
    'Alpha_deg', ...
    'MeanAbsFyError_pct', ...
    'MedianAbsFyError_pct', ...
    'MeanNormalizedShapeError_pct'});

writetable(ErrorTable, ...
    fullfile(OUTDIR,'SATURATION_ERROR_BY_ALPHA_v2_4.csv'));

%% ================================================================
% 15. FINAL CONSOLE SUMMARY
% ================================================================

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL SATURATION AUDIT v2.4 COMPLETE\n');
fprintf('============================================================\n');

fprintf('\nCheckpoint error trend:\n');

for j=1:nA
    fprintf('  %4.1f deg : mean abs Fy error = %7.3f %% | shape error = %7.3f %%\n', ...
        alphaCheck(j),MeanAbsErrorByAlpha(j),meanShapeError(j));
end

fprintf('\nOutput directory:\n%s\n',OUTDIR);

fprintf('\nNO MODEL PARAMETERS WERE CHANGED.\n');

fprintf('============================================================\n');

end

%% ================================================================
function [aOut,yOut]=binMedianCurve(a,y,binWidth)

a=a(:);
y=y(:);

good=isfinite(a)&isfinite(y);

a=a(good);
y=y(good);

if isempty(a)
    aOut=[]; yOut=[]; return;
end

edges=floor(min(a)/binWidth)*binWidth: ...
      binWidth: ...
      ceil(max(a)/binWidth)*binWidth;

if numel(edges)<3
    aOut=[]; yOut=[]; return;
end

ib=discretize(a,edges);

n=max(ib);

aOut=zeros(n,1);
yOut=zeros(n,1);

for i=1:n

    m=ib==i;

    if any(m)
        aOut(i)=median(a(m),'omitnan');
        yOut(i)=median(y(m),'omitnan');
    end
end

good=isfinite(aOut)&isfinite(yOut);

aOut=aOut(good);
yOut=yOut(good);

[aOut,ord]=sort(aOut);
yOut=yOut(ord);

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
