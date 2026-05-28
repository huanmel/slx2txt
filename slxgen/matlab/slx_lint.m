function slx_lint(slx_path, out_json_path)
% slx_lint  Open a Simulink model, run sfLintChart on every Stateflow chart,
%           write results to a JSON file, then close the model.
%
%   slx_lint(SLX_PATH, OUT_JSON_PATH)
%
%   SLX_PATH      - Full path to the .slx file (forward slashes recommended).
%   OUT_JSON_PATH - Path where the JSON issue list will be written.
%
%   JSON format: array of objects, one per issue:
%     { "chart":   "ModelName/ChartName",
%       "index":   1,
%       "name":    "UnreachableState",
%       "path":    "ModelName/ChartName/STATENAME",
%       "details": "State "X" in "..." has no incoming transitions." }
%
%   Called from Python:
%     matlab -batch "addpath('slxgen/matlab'); slx_lint('model.slx', 'issues.json')"
%
%   When the model contains no Stateflow, writes an empty array [].

load_system(slx_path);
[~, mdl, ~] = fileparts(slx_path);

% Locate the Stateflow machine for this model only.
r        = sfroot;
machines = find(r, '-isa', 'Stateflow.Machine', 'Name', mdl);

if isempty(machines)
    writeJson(out_json_path, {});
    bdclose(mdl);
    return
end

charts = find(machines(1), '-isa', 'Stateflow.Chart');

% Run sfLintChart on each chart and accumulate results as plain structs
% (no Stateflow object handles — those cannot be serialised to JSON).
entries = {};
for ci = 1:numel(charts)
    ch  = charts(ci);
    iss = sfLintChart(ch);
    for ii = 1:numel(iss)
        e.chart   = ch.Path;
        e.index   = ii;
        e.name    = iss(ii).name;
        h = iss(ii).handle;
        if isa(h, 'Stateflow.State')
            e.path = [h.Path '/' h.Name];   % full path including state name
        else
            e.path = h.Path;
        end
        e.details = iss(ii).details;
        entries{end+1} = e; %#ok<AGROW>
    end
end

writeJson(out_json_path, dedup(entries));
bdclose(mdl);

end % slx_lint

% -------------------------------------------------------------------------
function unique_entries = dedup(entries)
% Remove duplicate issues (same name + path + details) that sfLintChart
% may emit when a check fires from multiple container scopes.
seen = {};
unique_entries = {};
for i = 1:numel(entries)
    e   = entries{i};
    key = [e.name '|' e.path '|' e.details];
    if ~any(strcmp(seen, key))
        seen{end+1}         = key; %#ok<AGROW>
        unique_entries{end+1} = e;  %#ok<AGROW>
    end
end
end

% -------------------------------------------------------------------------
function writeJson(path, entries)
if isempty(entries)
    json = '[]';
else
    json = jsonencode(entries, 'PrettyPrint', true);
end
fid = fopen(path, 'w', 'n', 'UTF-8');
if fid == -1
    error('slx_lint: cannot open output file: %s', path);
end
fprintf(fid, '%s\n', json);
fclose(fid);
end
