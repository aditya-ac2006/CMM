function [Fy_N, M] = CMM_TIRE_LATERAL_MODEL_v1_0( ...
    alpha_deg, Fz_N, camber_deg, pressure_psi)
% ================================================================
% CMM TIRE LATERAL MODEL v1.0
% PURE-LATERAL MAGIC FORMULA PREDICTION LAYER
% ================================================================
%
% This prediction equation mirrors the current CMM v1.5.1
% cmmMFglobal() implementation.
%
% Inputs:
%   alpha_deg    - slip angle [deg]
%   Fz_N         - vertical load [N], positive magnitude
%   camber_deg   - camber / inclination angle [deg]
%   pressure_psi - inflation pressure [psi]
%
% Outputs:
%   Fy_N - predicted lateral force [N]
%   M   - loaded model structure
%
% NO FITTING IS PERFORMED HERE.
% ================================================================

M = CMM_TIRE_LATERAL_PARAMS_v1_0();
q = M.Parameters;

a = double(alpha_deg) * pi/180;
g = double(camber_deg) * pi/180;
Fz = max(double(Fz_N),1);
P  = double(pressure_psi);

Fz0 = M.Reference.Fz0_N;
P0  = M.Reference.P0_psi;

dfz = (Fz-Fz0)./Fz0;
dP  = P-P0;

PCY1=q(1);
PDY1=q(2); PDY2=q(3); PDY3=q(4);
PEY1=q(5); PEY2=q(6);
PKY1=q(7); PKY2=q(8); PKY3=q(9);
PHY1=q(10); PHY2=q(11); PHY3=q(12);
PVY1=q(13); PVY2=q(14); PVY3=q(15); PVY4=q(16);
Pmu1=q(17); Pmu2=q(18); Pk1=q(19);

% Shape factor
Cy = PCY1;

% Friction / peak factor
mu = (PDY1+PDY2.*dfz).*(1-PDY3.*g.^2);
muP = 1+Pmu1.*dP+Pmu2.*dP.^2;
mu = mu.*muP;

% Positivity guard used in the current CMM model.
mu = max(mu,0.20);

Dy = mu.*Fz;

% Curvature
Ey = PEY1+PEY2.*dfz;
Ey = max(-1.0,min(1.0,Ey));

% Cornering stiffness
stiffCamber = max(0.10,1-PKY3.*g.^2);
Ky = PKY1.*Fz0.* ...
     sin(2.*atan(Fz./(PKY2.*Fz0))).*stiffCamber;

% Pressure dependence of stiffness
Ky = Ky.*(1+Pk1.*dP);
Ky = max(Ky,100);

% Convert stiffness to MF B factor
By = Ky./max(Cy.*Dy,1);

% Horizontal shift
Shy = PHY1+PHY2.*dfz+PHY3.*g;

% Vertical shift
Svy = Fz.*(PVY1+PVY2.*dfz) + ...
      mu.*Fz.*(PVY3+PVY4.*dfz).*g;

% Composite slip variable
alphaY = a+Shy;
x = By.*alphaY;

% Standard sine-form Magic Formula
Fy_N = Dy.*sin(Cy.*atan( ...
    x-Ey.*(x-atan(x)))) + Svy;

end
