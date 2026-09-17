classdef ColorAtlas_v1_2 < ColorAtlas
%COLORATLAS_V1_2 Compatibility entrypoint; launches the maintained Color Atlas.
    methods
        function app = ColorAtlas_v1_2(varargin)
            app@ColorAtlas(varargin{:});
        end
    end
end
