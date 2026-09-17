function app = launch_color_atlas(varargin)
%LAUNCH_COLOR_ATLAS Launch Color Atlas 2 without changing the current folder.
% Optional scalar struct configures initial state; see ColorAtlas.setState.
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'app'));
app = ColorAtlas(varargin{:});
end
