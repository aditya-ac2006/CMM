function CMM_MF_LATERAL_VALIDATE_v2_1
% ================================================================
% CMM MF LATERAL VALIDATOR v2.1
% VALIDATION ONLY - DOES NOT REFIT THE MODEL
% ================================================================
%
% PURPOSE

%   Validate the saved CMM MF Lateral Global v2.0 model correctly.
%
%   v2.1 fixes the validation problems in v2.0:
%     1) Correct C-alpha units: alpha is in degrees everywhere.
%     2) Exact reference-condition validation is separated from the
%        broader reference neighborhood.
%     3) Global validation uses measured-vs-predicted Fy.
%     4) Run 2 and Run 4 are reported separately.
%     5) Load / camber / pressure sensitivity are compared against
%        measured data, not only model predictions.
%     6) No fitting is performed.
%
% INPUTS
%   - CMM_GLOBAL_MF_LATERAL_v2_0.mat
%   - TTC_CONDITION_ASSIGNED_DATABASE.csv
%
% ================================================================

clc;
close all;

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL VALIDATOR v2.1\n');
fprintf(' VALIDATION ONLY - NO REFIT\n');
fprintf('============================================================\n\n');

%% ================================================================
% 1. SELECT MODEL
% ================================================================

[fileMF,pathMF] = uigetfile('*.mat','Select CMM_GLOBAL_MF_LATERAL_v2_0.mat');

if isequal(fileMF,0)
    error('No MF model selected.');
end

S = load(fullfile(pathMF,fileMF));

if ~isfield(S,'GlobalMF')
    error('Selected MAT file does not contain GlobalMF.');
end

M = S.GlobalMF;
q = M.Parameters;

FZ0 = M.Reference.Fz0_N;
P0  = M.Reference.P0_psi;
IA0 = M.Reference.IA0_deg;

fprintf('[1] MODEL\n');
fprintf('File      : %s\n',fileMF);
fprintf('Version   : %s\n',M.Version);
fprintf('Fz0       : %.2f N\n',FZ0);
fprintf('P0        : %.2f psi\n',P0);
fprintf('IA0       : %.2f deg\n\n',IA0);

%% ================================================================
% 2. SELECT DATABASE
% ================================================================

[fileDB,pathDB] = uigetfile('*.csv', ...
    'Select TTC_CONDITION_ASSIGNED_DATABASE.csv');

if isequal(fileDB,0)
    error('No database selected.');
end

T = readtable(fullfile(pathDB,fileDB));

fprintf('[2] DATABASE\n');
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

%% ================================================================
% 3. APPLY SAME CMM FORCE CONVENTION
% ================================================================

FY = -FY;

good = isfinite(SA)&isfinite(FY)&isfinite(FZ)&isfinite(IA)& ...
       isfinite(P)&isfinite(RUN)&FZ>0;

SA=SA(good);
FY=FY(good);
FZ=FZ(good);
IA=IA(good);
P=P(good);
RUN=RUN(good);

fprintf('Clean rows       : %d\n',numel(FY));
fprintf('Run 2 rows       : %d\n',nnz(round(RUN)==2));
fprintf('Run 4 rows       : %d\n\n',nnz(round(RUN)==4));

%% ================================================================
% 4. POINTWISE GLOBAL PREDICTION
% ================================================================

FY_MF = cmmMFglobal(q,SA,FZ,IA,P,FZ0,P0);

valid = isfinite(FY)&isfinite(FY_MF);

y = FY(valid);
yp = FY_MF(valid);
runv = RUN(valid);
sa = SA(valid);
fz = FZ(valid);
ia = IA(valid);
pp = P(valid);

err = y-yp;

R2_global = calcR2(y,yp);
RMSE_global = sqrt(mean(err.^2));
MAE_global = mean(abs(err));

relDen = max(abs(y),50);
MAPE_global = mean(abs(err)./relDen)*100;

fprintf('============================================================\n');
fprintf(' GLOBAL POINTWISE VALIDATION\n');
fprintf('============================================================\n');
fprintf('N                  : %d\n',numel(y));
fprintf('R2                 : %.6f\n',R2_global);
fprintf('RMSE               : %.3f N\n',RMSE_global);
fprintf('MAE                : %.3f N\n',MAE_global);
fprintf('Mean relative err  : %.3f %%\n\n',MAPE_global);

%% ================================================================
% 5. RUN-BY-RUN VALIDATION
% ================================================================

runIDs = [2 4];

RunName = strings(numel(runIDs),1);
Nrun = zeros(numel(runIDs),1);
R2run = nan(numel(runIDs),1);
RMSErun = nan(numel(runIDs),1);
MAErun = nan(numel(runIDs),1);
MAPErun = nan(numel(runIDs),1);

fprintf('============================================================\n');
fprintf(' RUN-BY-RUN VALIDATION\n');
fprintf('============================================================\n');

for k=1:numel(runIDs)

    m = round(runv)==runIDs(k);

    RunName(k) = "Run "+runIDs(k);
    Nrun(k)=nnz(m);

    if Nrun(k)>0
        R2run(k)=calcR2(y(m),yp(m));
        RMSErun(k)=sqrt(mean((y(m)-yp(m)).^2));
        MAErun(k)=mean(abs(y(m)-yp(m)));
        MAPErun(k)=mean(abs(y(m)-yp(m))./max(abs(y(m)),50))*100;
    end

    fprintf('Run %d\n',runIDs(k));
    fprintf('  N                : %d\n',Nrun(k));
    fprintf('  R2               : %.6f\n',R2run(k));
    fprintf('  RMSE             : %.3f N\n',RMSErun(k));
    fprintf('  MAE              : %.3f N\n',MAErun(k));
    fprintf('  Mean rel. error  : %.3f %%\n\n',MAPErun(k));
end

%% ================================================================
% 6. EXACT REFERENCE CONDITION
% ================================================================
%
% Tight window. This is deliberately NOT the old +/-75 N neighborhood.

REF_FZ_TOL = 10;
REF_P_TOL  = 0.10;
REF_IA_TOL = 0.10;

ref = abs(fz-FZ0)<=REF_FZ_TOL & ...
      abs(pp-P0)<=REF_P_TOL & ...
      abs(ia-IA0)<=REF_IA_TOL;

fprintf('============================================================\n');
fprintf(' EXACT REFERENCE CONDITION\n');
fprintf('============================================================\n');
fprintf('Fz : %.1f +/- %.1f N\n',FZ0,REF_FZ_TOL);
fprintf('P  : %.2f +/- %.2f psi\n',P0,REF_P_TOL);
fprintf('IA : %.2f +/- %.2f deg\n',IA0,REF_IA_TOL);
fprintf('Samples: %d\n',nnz(ref));

if nnz(ref)<50
    warning('Tight reference condition has fewer than 50 samples. Using the nearest 250 samples for the reference curve.');
    d = sqrt(((fz-FZ0)/25).^2 + ((pp-P0)/0.1).^2 + ((ia-IA0)/0.1).^2);
    [~,idx] = sort(d);
    idx = idx(1:min(250,numel(idx)));
    ref = false(size(fz));
    ref(idx)=true;
end

refSA = sa(ref);
refY  = y(ref);
refP  = yp(ref);

% Reference curve on absolute slip angle
refAbsSA = abs(refSA);
refAbsFY = abs(refY);

% Use binned median values for a clean measured reference curve
refCurveData = binMedianCurve([refAbsSA,refAbsFY],0.05);

refGrid = linspace(0,12.3,600)';
refMF = abs(cmmMFglobal(q,refGrid,FZ0,IA0,P0,FZ0,P0));

% Pointwise reference metrics
refR2 = calcR2(refY,refP);
refRMSE = sqrt(mean((refY-refP).^2));
refMAE = mean(abs(refY-refP));

fprintf('Reference R2      : %.6f\n',refR2);
fprintf('Reference RMSE    : %.3f N\n',refRMSE);
fprintf('Reference MAE     : %.3f N\n',refMAE);

%% ================================================================
% 7. CORNERING STIFFNESS - CORRECT DEGREES
% ================================================================

h = 0.01;  % DEGREES

C_alpha_MF = ...
    (cmmMFglobal(q,h,FZ0,IA0,P0,FZ0,P0) - ...
     cmmMFglobal(q,-h,FZ0,IA0,P0,FZ0,P0))/(2*h);

% Measured C-alpha: fit only a small central region.
nearZero = ref & abs(sa)<=1.0;

if nnz(nearZero)>=10
    p = polyfit(sa(nearZero),y(nearZero),1);
    C_alpha_measured = abs(p(1));
else
    C_alpha_measured = NaN;
end

fprintf('\nC-alpha measured  : %.3f N/deg\n',C_alpha_measured);
fprintf('C-alpha MF        : %.3f N/deg\n',C_alpha_MF);

if isfinite(C_alpha_measured)
    fprintf('C-alpha error     : %.3f %%\n', ...
        100*(C_alpha_MF-C_alpha_measured)/C_alpha_measured);
end

%% ================================================================
% 8. MEASURED VS MF PEAK MU BY LOAD
% ================================================================

loadCenters = [210 432 656 875 1096]';

loadMeasured = nan(size(loadCenters));
loadMF = nan(size(loadCenters));
loadN = zeros(size(loadCenters));

for k=1:numel(loadCenters)

    band = abs(fz-loadCenters(k))<=35 & ...
           abs(pp-P0)<=0.35 & ...
           abs(ia)<=0.5 & ...
           abs(sa)<=12.3;

    loadN(k)=nnz(band);

    if loadN(k)>=20

        loadMeasured(k)=max(abs(y(band)))./median(fz(band));

        yy = cmmMFglobal(q,refGrid, ...
            loadCenters(k)*ones(size(refGrid)), ...
            zeros(size(refGrid)), ...
            P0*ones(size(refGrid)),FZ0,P0);

        loadMF(k)=max(abs(yy))/loadCenters(k);
    end
end

%% ================================================================
% 9. MEASURED VS MF PEAK MU BY PRESSURE
% ================================================================

pressureCenters = [8.1 10.1 12.1 14.1]';

pressureMeasured = nan(size(pressureCenters));
pressureMF = nan(size(pressureCenters));
pressureN = zeros(size(pressureCenters));

for k=1:numel(pressureCenters)

    band = abs(pp-pressureCenters(k))<=0.35 & ...
           abs(fz-FZ0)<=75 & ...
           abs(ia)<=0.5 & ...
           abs(sa)<=12.3;

    pressureN(k)=nnz(band);

    if pressureN(k)>=20

        pressureMeasured(k)=max(abs(y(band)))/median(fz(band));

        yy=cmmMFglobal(q,refGrid,FZ0*ones(size(refGrid)), ...
            zeros(size(refGrid)), ...
            pressureCenters(k)*ones(size(refGrid)),FZ0,P0);

        pressureMF(k)=max(abs(yy))/FZ0;
    end
end

%% ================================================================
% 10. MEASURED VS MF PEAK MU BY CAMBER
% ================================================================

camberCenters = [0 2 4]';

camberMeasured = nan(size(camberCenters));
camberMF = nan(size(camberCenters));
camberN = zeros(size(camberCenters));

for k=1:numel(camberCenters)

    band = abs(ia-camberCenters(k))<=0.35 & ...
           abs(fz-FZ0)<=75 & ...
           abs(pp-P0)<=0.5 & ...
           abs(sa)<=12.3;

    camberN(k)=nnz(band);

    if camberN(k)>=20

        camberMeasured(k)=max(abs(y(band)))/median(fz(band));

        yy=cmmMFglobal(q,refGrid,FZ0*ones(size(refGrid)), ...
            camberCenters(k)*ones(size(refGrid)), ...
            P0*ones(size(refGrid)),FZ0,P0);

        camberMF(k)=max(abs(yy))/FZ0;
    end
end

%% ================================================================
% 11. SENSITIVITY TABLES
% ================================================================

fprintf('\n============================================================\n');
fprintf(' LOAD SENSITIVITY\n');
fprintf('============================================================\n');
disp(table(loadCenters,loadN,loadMeasured,loadMF, ...
    'VariableNames',{'Fz_N','N','Measured_mu','MF_mu'}));

fprintf('============================================================\n');
fprintf(' PRESSURE SENSITIVITY\n');
fprintf('============================================================\n');
disp(table(pressureCenters,pressureN,pressureMeasured,pressureMF, ...
    'VariableNames',{'Pressure_psi','N','Measured_mu','MF_mu'}));

fprintf('============================================================\n');
fprintf(' CAMBER SENSITIVITY\n');
fprintf('============================================================\n');
disp(table(camberCenters,camberN,camberMeasured,camberMF, ...
    'VariableNames',{'Camber_deg','N','Measured_mu','MF_mu'}));

%% ================================================================
% 12. CORRECT C-ALPHA SENSITIVITY
% ================================================================

loadCaMeasured = nan(size(loadCenters));
loadCaMF = nan(size(loadCenters));

for k=1:numel(loadCenters)

    band = abs(fz-loadCenters(k))<=35 & ...
           abs(pp-P0)<=0.35 & abs(ia)<=0.5 & abs(sa)<=1.0;

    if nnz(band)>=10
        ppfit=polyfit(sa(band),y(band),1);
        loadCaMeasured(k)=abs(ppfit(1));
    end

    loadCaMF(k)= ...
        (cmmMFglobal(q,h,loadCenters(k),IA0,P0,FZ0,P0)- ...
         cmmMFglobal(q,-h,loadCenters(k),IA0,P0,FZ0,P0))/(2*h);
end

pressureCaMeasured = nan(size(pressureCenters));
pressureCaMF = nan(size(pressureCenters));

for k=1:numel(pressureCenters)

    band = abs(pp-pressureCenters(k))<=0.35 & ...
           abs(fz-FZ0)<=75 & abs(ia)<=0.5 & abs(sa)<=1.0;

    if nnz(band)>=10
        ppfit=polyfit(sa(band),y(band),1);
        pressureCaMeasured(k)=abs(ppfit(1));
    end

    pressureCaMF(k)= ...
        (cmmMFglobal(q,h,FZ0,IA0,pressureCenters(k),FZ0,P0)- ...
         cmmMFglobal(q,-h,FZ0,IA0,pressureCenters(k),FZ0,P0))/(2*h);
end

camberCaMeasured = nan(size(camberCenters));
camberCaMF = nan(size(camberCenters));

for k=1:numel(camberCenters)

    band = abs(ia-camberCenters(k))<=0.35 & ...
           abs(fz-FZ0)<=75 & abs(pp-P0)<=0.5 & abs(sa)<=1.0;

    if nnz(band)>=10
        ppfit=polyfit(sa(band),y(band),1);
        camberCaMeasured(k)=abs(ppfit(1));
    end

    camberCaMF(k)= ...
        (cmmMFglobal(q,h,FZ0,camberCenters(k),P0,FZ0,P0)- ...
         cmmMFglobal(q,-h,FZ0,camberCenters(k),P0,FZ0,P0))/(2*h);
end

%% ================================================================
% 13. OUTPUT DIRECTORY
% ================================================================

OUTDIR = fullfile(pathMF,'VALIDATION_v2_1');

if ~exist(OUTDIR,'dir')
    mkdir(OUTDIR);
end

%% ================================================================
% 14. FIGURE 1 - EXACT REFERENCE CURVE
% ================================================================

fig=figure('Color','w');

plot(refCurveData(:,1),refCurveData(:,2),'o'); hold on;
plot(refGrid,refMF,'LineWidth',2);

grid on;
box on;

xlabel('|\alpha| [deg]');
ylabel('|F_y| [N]');

title(sprintf('Exact Reference Validation | R^2 = %.4f | RMSE = %.1f N', ...
    refR2,refRMSE));

legend('Measured reference','MF','Location','southeast');

exportgraphics(fig,fullfile(OUTDIR,'01_EXACT_REFERENCE_CURVE.png'),'Resolution',180);
close(fig);

%% ================================================================
% 15. FIGURE 2 - GLOBAL MEASURED VS PREDICTED
% ================================================================

fig=figure('Color','w');

scatter(yp,y,5,'filled'); hold on;

lims=[min([y;yp]) max([y;yp])];

plot(lims,lims,'--','LineWidth',1.5);

grid on;
box on;
axis equal;

xlim(lims);
ylim(lims);

xlabel('MF predicted F_y [N]');
ylabel('Measured F_y [N]');

title(sprintf('Global Measured vs MF | R^2 = %.4f | RMSE = %.1f N', ...
    R2_global,RMSE_global));

legend('Samples','Perfect prediction','Location','southeast');

exportgraphics(fig,fullfile(OUTDIR,'02_GLOBAL_MEASURED_VS_PREDICTED.png'),'Resolution',180);
close(fig);

%% ================================================================
% 16. FIGURE 3 - RUN COMPARISON
% ================================================================

fig=figure('Color','w');

m2=round(runv)==2;
m4=round(runv)==4;

scatter(yp(m2),y(m2),5,'filled'); hold on;
scatter(yp(m4),y(m4),5,'filled');

lims=[min([y;yp]) max([y;yp])];
plot(lims,lims,'--','LineWidth',1.5);

grid on;
axis equal;
xlim(lims); ylim(lims);

xlabel('MF predicted F_y [N]');
ylabel('Measured F_y [N]');

title('Run 2 vs Run 4 Measured-MF Validation');
legend('Run 2','Run 4','Perfect prediction','Location','southeast');

exportgraphics(fig,fullfile(OUTDIR,'03_RUN2_RUN4_COMPARISON.png'),'Resolution',180);
close(fig);

%% ================================================================
% 17. FIGURE 4 - RESIDUAL VS SLIP ANGLE
% ================================================================

fig=figure('Color','w');

scatter(sa,err,5,'filled'); hold on;
yline(0,'--','LineWidth',1.2);

grid on;
box on;

xlabel('\alpha [deg]');
ylabel('Measured - MF F_y [N]');

title(sprintf('Pointwise Residual vs Slip Angle | R^2 = %.4f',R2_global));

exportgraphics(fig,fullfile(OUTDIR,'04_GLOBAL_RESIDUAL_VS_ALPHA.png'),'Resolution',180);
close(fig);

%% ================================================================
% 18. FIGURE 5 - LOAD SENSITIVITY
% ================================================================

fig=figure('Color','w');

plot(loadCenters,loadMeasured,'o-','LineWidth',1.8); hold on;
plot(loadCenters,loadMF,'s-','LineWidth',1.8);

grid on;
box on;

xlabel('F_z [N]');
ylabel('\mu_{peak}');

title('Measured vs MF Load Sensitivity');

legend('Measured','MF','Location','best');

exportgraphics(fig,fullfile(OUTDIR,'05_LOAD_SENSITIVITY_VALIDATED.png'),'Resolution',180);
close(fig);

%% ================================================================
% 19. FIGURE 6 - PRESSURE SENSITIVITY
% ================================================================

fig=figure('Color','w');

plot(pressureCenters,pressureMeasured,'o-','LineWidth',1.8); hold on;
plot(pressureCenters,pressureMF,'s-','LineWidth',1.8);

grid on;
box on;

xlabel('Pressure [psi]');
ylabel('\mu_{peak}');

title('Measured vs MF Pressure Sensitivity');

legend('Measured','MF','Location','best');

exportgraphics(fig,fullfile(OUTDIR,'06_PRESSURE_SENSITIVITY_VALIDATED.png'),'Resolution',180);
close(fig);

%% ================================================================
% 20. FIGURE 7 - CAMBER SENSITIVITY
% ================================================================

fig=figure('Color','w');

plot(camberCenters,camberMeasured,'o-','LineWidth',1.8); hold on;
plot(camberCenters,camberMF,'s-','LineWidth',1.8);

grid on;
box on;

xlabel('Camber / IA [deg]');
ylabel('\mu_{peak}');

title('Measured vs MF Camber Sensitivity');

legend('Measured','MF','Location','best');

exportgraphics(fig,fullfile(OUTDIR,'07_CAMBER_SENSITIVITY_VALIDATED.png'),'Resolution',180);
close(fig);

%% ================================================================
% 21. FIGURE 8 - C-ALPHA SENSITIVITY
% ================================================================

fig=figure('Color','w');

plot(loadCenters,loadCaMeasured,'o-','LineWidth',1.8); hold on;
plot(loadCenters,loadCaMF,'s-','LineWidth',1.8);

grid on;
box on;

xlabel('F_z [N]');
ylabel('C_\alpha [N/deg]');

title('Corrected Cornering Stiffness vs Load');

legend('Measured','MF','Location','best');

exportgraphics(fig,fullfile(OUTDIR,'08_CALPHA_LOAD_VALIDATED.png'),'Resolution',180);
close(fig);

%% ================================================================
% 22. SAVE TABLES
% ================================================================

RunTable=table(RunName,Nrun,R2run,RMSErun,MAErun,MAPErun, ...
    'VariableNames',{'Run','N','R2','RMSE_N','MAE_N','MeanRelativeError_pct'});

writetable(RunTable,fullfile(OUTDIR,'RUN_VALIDATION_v2_1.csv'));

LoadTable=table(loadCenters,loadN,loadMeasured,loadMF,loadCaMeasured,loadCaMF, ...
    'VariableNames',{'Fz_N','N','Measured_mu','MF_mu', ...
    'Measured_Calpha_N_per_deg','MF_Calpha_N_per_deg'});

writetable(LoadTable,fullfile(OUTDIR,'LOAD_VALIDATION_v2_1.csv'));

PressureTable=table(pressureCenters,pressureN,pressureMeasured,pressureMF, ...
    pressureCaMeasured,pressureCaMF, ...
    'VariableNames',{'Pressure_psi','N','Measured_mu','MF_mu', ...
    'Measured_Calpha_N_per_deg','MF_Calpha_N_per_deg'});

writetable(PressureTable,fullfile(OUTDIR,'PRESSURE_VALIDATION_v2_1.csv'));

CamberTable=table(camberCenters,camberN,camberMeasured,camberMF, ...
    camberCaMeasured,camberCaMF, ...
    'VariableNames',{'Camber_deg','N','Measured_mu','MF_mu', ...
    'Measured_Calpha_N_per_deg','MF_Calpha_N_per_deg'});

writetable(CamberTable,fullfile(OUTDIR,'CAMBER_VALIDATION_v2_1.csv'));

SummaryTable=table( ...
    ["Global";"Run2";"Run4";"ExactReference"], ...
    [R2_global;R2run(1);R2run(2);refR2], ...
    [RMSE_global;RMSErun(1);RMSErun(2);refRMSE], ...
    [MAE_global;MAErun(1);MAErun(2);refMAE], ...
    'VariableNames',{'Set','R2','RMSE_N','MAE_N'});

writetable(SummaryTable,fullfile(OUTDIR,'SUMMARY_VALIDATION_v2_1.csv'));

%% ================================================================
% 23. REPORT
% ================================================================

fid=fopen(fullfile(OUTDIR,'VALIDATION_REPORT_v2_1.txt'),'w');

fprintf(fid,'CMM MF LATERAL VALIDATOR v2.1\n');
fprintf(fid,'=============================\n\n');

fprintf(fid,'Model: %s\n',fileMF);
fprintf(fid,'Database: %s\n\n',fileDB);

fprintf(fid,'REFERENCE\n');
fprintf(fid,'Fz0 = %.3f N\nP0 = %.3f psi\nIA0 = %.3f deg\n\n',FZ0,P0,IA0);

fprintf(fid,'GLOBAL\n');
fprintf(fid,'N = %d\nR2 = %.8f\nRMSE = %.6f N\nMAE = %.6f N\nMean relative error = %.6f %%\n\n', ...
    numel(y),R2_global,RMSE_global,MAE_global,MAPE_global);

fprintf(fid,'RUN 2\n');
fprintf(fid,'N = %d\nR2 = %.8f\nRMSE = %.6f N\nMAE = %.6f N\n\n', ...
    Nrun(1),R2run(1),RMSErun(1),MAErun(1));

fprintf(fid,'RUN 4\n');
fprintf(fid,'N = %d\nR2 = %.8f\nRMSE = %.6f N\nMAE = %.6f N\n\n', ...
    Nrun(2),R2run(2),RMSErun(2),MAErun(2));

fprintf(fid,'EXACT REFERENCE\n');
fprintf(fid,'N = %d\nR2 = %.8f\nRMSE = %.6f N\nMAE = %.6f N\n', ...
    nnz(ref),refR2,refRMSE,refMAE);
fprintf(fid,'Measured C-alpha = %.6f N/deg\n',C_alpha_measured);
fprintf(fid,'MF C-alpha = %.6f N/deg\n',C_alpha_MF);

fclose(fid);

%% ================================================================
% 24. FINAL CONSOLE SUMMARY
% ================================================================

fprintf('\n============================================================\n');
fprintf(' CMM MF LATERAL VALIDATOR v2.1 COMPLETE\n');
fprintf('============================================================\n');
fprintf('Global R2             : %.6f\n',R2_global);
fprintf('Global RMSE           : %.3f N\n',RMSE_global);
fprintf('Global MAE            : %.3f N\n',MAE_global);
fprintf('Run 2 R2              : %.6f\n',R2run(1));
fprintf('Run 4 R2              : %.6f\n',R2run(2));
fprintf('Exact reference R2    : %.6f\n',refR2);
fprintf('Measured C-alpha      : %.3f N/deg\n',C_alpha_measured);
fprintf('MF C-alpha            : %.3f N/deg\n',C_alpha_MF);
fprintf('\nOutput directory:\n%s\n',OUTDIR);
fprintf('============================================================\n');

end

%% ========================================================================
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

y=Dy.*sin(Cy.*atan(x-Ey.*(x-atan(x))))+Svy;

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

    error('Required variable not found.');

end

v=T{:,idx};

if iscell(v)
    v=str2double(string(v));
elseif isstring(v)||ischar(v)||iscategorical(v)
    v=str2double(string(v));
end

x=double(v(:));

end

%% ========================================================================
function X=binMedianCurve(A,dx)

if isempty(A)
    X=A;
    return;
end

k=round(A(:,1)/dx);

[~,~,ic]=unique(k);

n=max(ic);

X=zeros(n,2);

for j=1:n

    m=ic==j;

    X(j,1)=median(A(m,1),'omitnan');
    X(j,2)=median(A(m,2),'omitnan');

end

X=X(all(isfinite(X),2),:);

end

%% ========================================================================
function r2=calcR2(y,yhat)

den=sum((y-mean(y)).^2);

if den<=eps
    r2=NaN;
else
    r2=1-sum((y-yhat).^2)/den;
end

end
