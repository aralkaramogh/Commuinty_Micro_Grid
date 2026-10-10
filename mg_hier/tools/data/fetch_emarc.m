function files = fetch_emarc(P)
% FETCH_EMARC  Check (and explain how to get) the Prayas eMARC household
% smart-meter data: Harvard Dataverse, licence CC0, about 377 MB.
% The dataset has a GUESTBOOK: Dataverse asks each downloader for name, e-mail,
% institution and purpose before the first download, so it cannot be fetched by
% a script. Download it once in a browser (steps printed below); this function
% then only checks that every file is present and complete.
if nargin < 1, P = hier_params(); end
d = fullfile(P.data.dir, 'raw', 'emarc'); if ~exist(d, 'dir'), mkdir(d); end
api = 'https://dataverse.harvard.edu/api';
info = webread([api '/datasets/:persistentId/?persistentId=' P.data.emarc_doi], weboptions('Timeout', 60));
f = info.data.latestVersion.files; if ~iscell(f), f = num2cell(f); end
files = strings(0, 1); missing = strings(0, 1);
for k = 1:numel(f)
    df = f{k}.dataFile; name = string(df.filename);
    cand = [name, replace(name, '.tab', '.tsv'), replace(name, '.tab', '.csv'), replace(name, '.tab', '.txt')];
    hit = cand(arrayfun(@(c) isfile(fullfile(d, c)), cand));
    if isempty(hit)
        missing(end+1) = sprintf('%s (%.1f MB)', name, df.filesize / 1e6); %#ok<AGROW>
    else
        files(end+1) = fullfile(d, hit(1)); %#ok<AGROW>
        fprintf('  have %-40s %8.1f MB\n', hit(1), dir(files(end)).bytes / 1e6);
    end
end
if ~isempty(missing)
    fprintf(['\nMissing: %s\nTo download (once, about 377 MB):\n' ...
             '  1 open https://doi.org/10.7910/DVN/YJ5SP1 in a browser\n' ...
             '  2 click "Access Dataset" -> "Download ZIP" (or download each file)\n' ...
             '  3 fill the short guestbook form (name, e-mail, institution, purpose: "student research")\n' ...
             '  4 unzip/save the files into %s\n' ...
             '  5 run fetch_emarc again to check them\n'], strjoin(missing, ', '), d);
end
end
