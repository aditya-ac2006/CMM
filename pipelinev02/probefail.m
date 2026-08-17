clear;
clc;

fprintf('\n============================================================\n');
fprintf(' B1965 TTC VARIABLE STRUCTURE PROBE\n');
fprintf('============================================================\n\n');

file = 'C:\Users\adity\CMM\all tests are here\B1965run2.mat';

S = load(file);

vars = fieldnames(S);

fprintf('FILE: %s\n', file);
fprintf('VARIABLE COUNT: %d\n\n', numel(vars));

fprintf('============================================================\n');
fprintf(' TOP-LEVEL VARIABLES\n');
fprintf('============================================================\n\n');

for k = 1:numel(vars)

    name = vars{k};
    x = S.(name);

    fprintf('%-25s | class=%-12s', ...
        name, class(x));

    if isnumeric(x)

        fprintf(' | size=[');
        fprintf('%d ', size(x));
        fprintf(']');

        if ~isempty(x)

            xx = x(:);

            fprintf(' | min=%g | max=%g | mean=%g', ...
                min(xx,[],'omitnan'), ...
                max(xx,[],'omitnan'), ...
                mean(xx,'omitnan'));

        end

    elseif isstruct(x)

        fprintf(' | struct fields=%d', ...
            numel(fieldnames(x)));

    elseif iscell(x)

        fprintf(' | cells=%d', numel(x));

    elseif ischar(x)

        fprintf(' | value="%s"', x);

    elseif isstring(x)

        fprintf(' | value="%s"', x);

    end

    fprintf('\n');

end

fprintf('\n============================================================\n');
fprintf(' NON-NUMERIC / STRUCTURE DETAILS\n');
fprintf('============================================================\n\n');

for k = 1:numel(vars)

    name = vars{k};
    x = S.(name);

    if isstruct(x)

        fprintf('\n------------------------------------------------------------\n');
        fprintf('STRUCT: %s\n', name);
        fprintf('------------------------------------------------------------\n');

        disp(x);

    elseif iscell(x)

        fprintf('\n------------------------------------------------------------\n');
        fprintf('CELL: %s\n', name);
        fprintf('------------------------------------------------------------\n');

        n = min(10,numel(x));

        for j = 1:n
            fprintf('Cell {%d}: ',j);

            try
                disp(x{j});
            catch
                fprintf('[unable to display]\n');
            end
        end

    elseif ischar(x) || isstring(x)

        fprintf('\n%s = ',name);
        disp(x);

    end

end

fprintf('\n============================================================\n');
fprintf(' END OF PROBE\n');
fprintf('============================================================\n');