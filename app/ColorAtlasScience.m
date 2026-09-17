classdef ColorAtlasScience
%COLORATLASSCIENCE Numerical core of Color Atlas (no user-interface dependency).
%
% All methods are static and vectorised over rows. XYZ arrays are n-by-3.
% This class is the intended boundary for independent numerical probing.
% Uses adapted MCSL-Tools implementations; see CREDITS.md and
% THIRD_PARTY_NOTICES.md for contributors, scientific sources and license.
%
% Appearance models (inverse: appearance -> XYZ on the reference-white scale of xyzw):
%   [XYZ, status, info] = ColorAtlasScience.inverseCAM(model, appearance, xyzw, ...
%        'La', 20, 'Yb', 20, 'Yw', 100, 'surround', "average", 'D', NaN)
%     model      : "ciecam02" | "cam16" | "hellwig2022" | "hellwig2022cat02"
%     appearance : struct with one of J/Q, one of C/M/s, and h (real numeric scalars
%                  or equal-length vectors; nonfinite rows return "not-finite")
%     xyzw       : 1x3 adopted white (any positive scale; output uses the same scale)
%     D          : NaN = automatic D from surround F and La, otherwise clipped to [0,1]
%     status     : n-by-1 string, "valid" or a reason (see STATUS_REASONS)
%     XYZ rows are NaN wherever status is not "valid".
%   Compatible name-value entry points with status output:
%   [XYZ, status] = ColorAtlasScience.inverse_CAM02(appearance, xyzw, 'adaptingLuminance', La, ...)
%   ... inverse_CAM16, inverse_modCAM02 (Hellwig 2022 correlates on CAT02/HPE), inverse_modCAM16.
%   Qw = ColorAtlasScience.whiteBrightness(model, xyzw, ...)   brightness of the adopted white
%
% CIELAB:
%   XYZ = ColorAtlasScience.cielabToXYZ(L, C, h, whiteName)   (Y of white = 1, MATLAB whitepoint names)
%
% Dichromat simulation (Brettel-style two-wing construction, see simulateDichromat):
%   [XYZp, wingNm] = ColorAtlasScience.simulateDichromat(kind, XYZ, xyzw)
%
% Preview / gamut classification:
%   P = ColorAtlasScience.previewCells(XYZ, selectedSpace, whiteName)
%   XYZ = ColorAtlasScience.backgroundXYZ(kind, whiteName, value)
%
% Version: ColorAtlasScience.version() reads the repository VERSION file.

    properties (Constant)
        MODELS = ["ciecam02" "cam16" "hellwig2022" "hellwig2022cat02"]
        SURROUNDS = ["average" "dim" "dark"]
        STATUS_REASONS = ["valid" "negative-correlate" "zero-lightness-chromatic" ...
            "chroma-out-of-domain" "response-out-of-domain" "not-finite" "not-real"]
        % Encoded-RGB tolerance for the closed [0,1] gamut test. Values within this
        % distance outside the cube are treated as boundary noise and clipped after
        % classification. It is far below one 8-bit step (1/255 = 0.0039).
        GAMUT_TOLERANCE = 1e-6
        % D65-normalised Hunt-Pointer-Estevez cone matrix (maps D65 to ~[1 1 1]).
        LMS_HPE = [0.4002 0.7075 -0.0807; -0.2280 1.1500 0.0612; 0 0 0.9184]
        % CIE 1931 2-degree colour-matching values x100 at the anchor wavelengths.
        ANCHOR_475 = [14.21 11.26 104.19]
        ANCHOR_485 = [5.795001 16.93 61.62]
        ANCHOR_575 = [84.25 91.54 0.18]
        ANCHOR_660 = [16.49 6.10 0.00]
        CAT02 = [0.7328 0.4296 -0.1624; -0.7036 1.6975 0.0061; 0.0030 0.0136 0.9834]
        CAT16 = [0.401288 0.650173 -0.051461; -0.250268 1.204414 0.045854; -0.002079 0.048952 0.953127]
        HPE = [0.38971 0.68898 -0.07868; -0.22981 1.18340 0.04641; 0 0 1]
    end

    methods (Static)

        function v = version()
            root = fileparts(fileparts(mfilename('fullpath')));
            file = fullfile(root, 'VERSION');
            assert(isfile(file), 'ColorAtlas:missingVersion', 'VERSION file not found at %s', file);
            v = strtrim(fileread(file));
        end

        function label = modelLabel(key)
            switch string(key)
                case "cielab",           label = "CIELAB";
                case "ciecam02",         label = "CIECAM02 (CIE 159:2004)";
                case "cam16",            label = "CAM16 (Li et al. 2017)";
                case "hellwig2022",      label = "Hellwig & Fairchild 2022 (CAM16 basis)";
                case "hellwig2022cat02", label = "Hellwig 2022 correlates on CAT02/HPE (composition)";
                otherwise, error('ColorAtlas:unknownModel', 'Unknown model key %s', key);
            end
        end

        %% ---------------------------------------------------------------- CIELAB
        function XYZ = cielabToXYZ(L, C, h, whiteName)
            % L, C (C*ab), h (degrees): scalars or equal-length columns. Output Y_white = 1.
            [L, C, h] = ColorAtlasScience.broadcastColumns(L, C, h);
            mustBeReal(L); mustBeReal(C); mustBeReal(h);
            lab = [L, C .* cosd(h), C .* sind(h)];
            XYZ = lab2xyz(lab, 'WhitePoint', whiteName);
        end

        %% ------------------------------------------------- appearance-model inverses
        function [XYZ, status, info] = inverseCAM(model, appearance, xyzw, vc)
            arguments
                model (1,1) string {mustBeMember(model, ["ciecam02" "cam16" "hellwig2022" "hellwig2022cat02"])}
                appearance (1,1) struct
                xyzw (1,3) {mustBeNumeric, mustBeReal, mustBeFinite}
                vc.La (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive} = 20
                vc.Yb (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive} = 20
                vc.Yw (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive} = 100
                vc.surround (1,1) string {mustBeMember(vc.surround, ["average" "dim" "dark"])} = "average"
                vc.D (1,1) {mustBeNumeric, mustBeReal} = NaN
            end
            xyzw = double(xyzw);
            vc.La = double(vc.La); vc.Yb = double(vc.Yb); vc.Yw = double(vc.Yw); vc.D = double(vc.D);
            assert(xyzw(2) > 0, 'ColorAtlas:invalidWhite', 'The adopted white must have Y > 0.');
            assert(isnan(vc.D) || isfinite(vc.D), 'ColorAtlas:invalidAdaptation', ...
                'D must be finite, or NaN to request automatic adaptation.');
            switch model
                case "ciecam02",         basis = "cat02"; formulation = "standard";
                case "cam16",            basis = "cat16"; formulation = "standard";
                case "hellwig2022",      basis = "cat16"; formulation = "hellwig";
                case "hellwig2022cat02", basis = "cat02"; formulation = "hellwig";
            end
            p = ColorAtlasScience.conditionParameters(basis, formulation, xyzw, vc);
            [tone, toneName, chroma, chromaName, h] = ColorAtlasScience.parseAppearance(appearance);
            n = numel(tone);
            XYZ = NaN(n, 3);
            status = repmat("valid", n, 1);

            % Lightness J and brightness Q of every row.
            if toneName == "J"
                J = tone;
            elseif formulation == "standard"
                J = 6.25 * ((p.c * tone) ./ ((p.Aw + 4) * p.Fl^0.25)).^2;
            else
                J = 50 * p.c * tone / p.Aw;
            end
            if formulation == "standard"
                Q = (4 / p.c) * sqrt(J / 100) * (p.Aw + 4) * p.Fl^0.25;
            else
                Q = (2 / p.c) * (J / 100) * p.Aw;
            end

            % Explicit domain handling before any arithmetic on degenerate rows.
            bad = ~isfinite(tone) | ~isfinite(chroma) | ~isfinite(h);
            status(bad) = "not-finite";
            neg = ~bad & (tone < 0 | chroma < 0);
            status(neg) = "negative-correlate";
            zeroTone = ~bad & ~neg & tone == 0;
            black = zeroTone & chroma == 0;
            XYZ(black, :) = 0;              % black is the unique stimulus with J = 0 and no chroma
            % J = 0 with positive C (standard models) or positive s (all models) has no
            % pre-image: the forward correlate is 0/0 or identically zero there.
            undefined = zeroTone & chroma > 0 & (chromaName == "s" | formulation == "standard");
            status(undefined) = "zero-lightness-chromatic";
            todo = ~bad & ~neg & ~black & ~undefined;
            if ~any(todo)
                info = p; return
            end
            J = J(todo); Q = Q(todo); h = h(todo); chroma = chroma(todo);
            A = p.Aw * (J / 100).^(1 / (p.c * p.z));

            if formulation == "standard"
                switch chromaName
                    case "C", C = chroma;
                    case "M", C = chroma / p.Fl^0.25;
                end
                if chromaName == "s"
                    t = (chroma / 50).^2 * (p.Aw + 4) / p.c;
                else
                    t = C ./ sqrt(J / 100);
                end
                t = (t / (1.64 - 0.29^p.n)^0.73).^(1 / 0.9);
                et = 0.25 * (cos(h * pi / 180 + 2) + 3.8);
                p1p = et * (50000 / 13) * p.Nc * p.Ncb;
                p2p = A / p.Nbb;
                den = 23 * p1p + 11 * t .* cosd(h) + 108 * t .* sind(h);
                % A non-positive denominator means the requested chroma exceeds what the
                % model can express at this lightness and hue: the solved opponent
                % magnitude would flip the hue by 180 degrees.
                rowOk = den > 0;
                gamma = zeros(size(t));
                gamma(rowOk) = 23 * (p2p(rowOk) + 0.305) .* t(rowOk) ./ den(rowOk);
            else
                et = 1 + [cosd(h) cosd(2*h) cosd(3*h) cosd(4*h) sind(h) sind(2*h) sind(3*h) sind(4*h)] * ...
                    [-0.0582 -0.0258 -0.1347 0.0289 -0.1475 -0.0308 0.0385 0.0096]';
                switch chromaName
                    case "M", M = chroma;
                    case "C", M = chroma * p.Aw / 35;
                    case "s", M = chroma .* Q / 100;
                end
                p1p = et * 43 * p.Nc;
                p2p = A;
                rowOk = true(size(M));
                gamma = M ./ p1p;
            end
            a = gamma .* cosd(h);
            b = gamma .* sind(h);
            Minv = (1 / 1403) * [460 451 288; 460 -891 -261; 460 -220 -6300];
            RGBap = [p2p a b] * Minv';                     % offset-free compressed responses
            % The compression 400*u^0.42/(u^0.42+27.13) has range (-400, 400); there is no
            % real signal for |response| >= 400. Reject rows beyond this response domain.
            inRange = all(abs(RGBap) < 400, 2);
            good = rowOk & inRange;
            RGBc = NaN(size(RGBap));
            u = abs(RGBap(good, :));
            RGBc(good, :) = sign(RGBap(good, :)) .* (100 / p.Fl) .* (27.13 * u ./ (400 - u)).^(1 / 0.42);
            if basis == "cat02"
                RGBc(good, :) = (ColorAtlasScience.CAT02 * (ColorAtlasScience.HPE \ RGBc(good, :)'))';
            end
            RGB = RGBc ./ p.DRGB;
            XYZn = (p.Mcat \ RGB')' / p.knorm;
            idx = find(todo);
            XYZ(idx(good), :) = XYZn(good, :);
            s = status(todo);
            s(~rowOk) = "chroma-out-of-domain";
            s(rowOk & ~inRange) = "response-out-of-domain";
            status(todo) = s;
            % Intermediate response checks cannot prevent overflow in the final
            % inverse matrices or white-scale conversion. A valid row is real and finite.
            nonReal = status == "valid" & any(imag(XYZ) ~= 0, 2);
            nonFinite = status == "valid" & ~nonReal & any(~isfinite(XYZ), 2);
            status(nonReal) = "not-real";
            status(nonFinite) = "not-finite";
            XYZ(nonReal | nonFinite, :) = NaN;
            info = p;
            info.J = NaN(n, 1); info.J(todo) = J;
            info.Q = NaN(n, 1); info.Q(todo) = Q;
        end

        function Qw = whiteBrightness(model, xyzw, vc)
            % Brightness correlate Q of the adopted white (J = 100) under the conditions.
            % This is a sampling reference for the atlas, not a maximum of the model: J > 100
            % stimuli (brighter than the adopted white) are representable.
            arguments
                model (1,1) string
                xyzw (1,3) {mustBeNumeric}
                vc.La (1,1) {mustBeNumeric} = 20
                vc.Yb (1,1) {mustBeNumeric} = 20
                vc.Yw (1,1) {mustBeNumeric} = 100
                vc.surround (1,1) string = "average"
                vc.D (1,1) {mustBeNumeric} = NaN
            end
            args = namedargs2cell(vc);
            [~, status, info] = ColorAtlasScience.inverseCAM(model, struct('J', 100, 'C', 0, 'h', 0), xyzw, args{:});
            Qw = info.Q;
            assert(status == "valid" && isreal(Qw) && isfinite(Qw) && Qw > 0, ...
                'ColorAtlas:invalidBrightness', 'Reference-white brightness must be finite and positive.');
        end

        % ---- compatible name-value entry points with status output
        function [XYZ, status] = inverse_CAM02(appearance, xyzw, varargin)
            [XYZ, status] = ColorAtlasScience.legacyCall("ciecam02", appearance, xyzw, varargin{:});
        end
        function [XYZ, status] = inverse_CAM16(appearance, xyzw, varargin)
            [XYZ, status] = ColorAtlasScience.legacyCall("cam16", appearance, xyzw, varargin{:});
        end
        function [XYZ, status] = inverse_modCAM16(appearance, xyzw, varargin)
            [XYZ, status] = ColorAtlasScience.legacyCall("hellwig2022", appearance, xyzw, varargin{:});
        end
        function [XYZ, status] = inverse_modCAM02(appearance, xyzw, varargin)
            [XYZ, status] = ColorAtlasScience.legacyCall("hellwig2022cat02", appearance, xyzw, varargin{:});
        end

        %% -------------------------------------------------------- dichromat simulation
        function [XYZp, wingNm] = simulateDichromat(kind, XYZ, xyzw)
            %SIMULATEDICHROMAT Brettel-style two-wing projection in the HPE cone space.
            %
            % Convention (documented, not a claim of published-observer parity):
            %   cone basis : D65-normalised Hunt-Pointer-Estevez matrix LMS_HPE (not the
            %                Stockman fundamentals of Brettel et al. 1997);
            %   neutral    : the selected adopted white xyzw (Brettel: equal-energy E;
            %                Vienot et al. 1999: the display white);
            %   anchors    : protan and deutan 475 / 575 nm, tritan 485 / 660 nm;
            %   wing test  : division-free comparison of the retained cone ratio with the
            %                neutral's ratio (protan S/M, deutan S/L, tritan M/L);
            %   missing cone replaced so that the result lies on the plane through the
            %   origin, the neutral and the chosen anchor; the two retained cones are kept.
            % The projection is linear on each wing, idempotent, homogeneous for nonnegative scale and
            % preserves every multiple of xyzw and both anchors. Rows with NaN pass through.
            arguments
                kind (1,1) string {mustBeMember(kind, ["protan" "deutan" "tritan"])}
                XYZ (:,3) {mustBeNumeric, mustBeReal}
                xyzw (1,3) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
            end
            XYZ = double(XYZ); xyzw = double(xyzw);
            M = ColorAtlasScience.LMS_HPE;
            LMS = XYZ * M';
            E = (M * xyzw')';
            switch kind
                case "protan"
                    onFirst = LMS(:,3) * E(2) < LMS(:,2) * E(3);      % S/M below neutral -> 575 nm
                    anchors = [ColorAtlasScience.ANCHOR_575; ColorAtlasScience.ANCHOR_475];
                    missing = 1;
                case "deutan"
                    onFirst = LMS(:,3) * E(1) < LMS(:,1) * E(3);      % S/L below neutral -> 575 nm
                    anchors = [ColorAtlasScience.ANCHOR_575; ColorAtlasScience.ANCHOR_475];
                    missing = 2;
                case "tritan"
                    onFirst = LMS(:,2) * E(1) < LMS(:,1) * E(2);      % M/L below neutral -> 660 nm
                    anchors = [ColorAtlasScience.ANCHOR_660; ColorAtlasScience.ANCHOR_485];
                    missing = 3;
            end
            nmList = [575 475]; if kind == "tritan", nmList = [660 485]; end
            normals = [cross(E, (M * anchors(1,:)')'); cross(E, (M * anchors(2,:)')')];
            assert(all(isfinite(normals), 'all') && all(normals(:, missing) ~= 0), ...
                'ColorAtlas:invalidDichromatWhite', ...
                'The adopted white does not define finite, invertible dichromat projection planes.');
            wingIndex = 2 - double(onFirst);                      % 1 = first anchor, 2 = second
            nrm = normals(wingIndex, :);
            keep = setdiff(1:3, missing);
            LMSp = LMS;
            LMSp(:, missing) = -(nrm(:, keep(1)) .* LMS(:, keep(1)) + nrm(:, keep(2)) .* LMS(:, keep(2))) ./ nrm(:, missing);
            XYZp = (M \ LMSp')';
            wingNm = nmList(wingIndex)';
            wingNm(any(isnan(XYZ), 2)) = NaN;
        end

        %% ---------------------------------------------------- preview and background
        function P = previewCells(XYZ, selectedSpace, whiteName)
            %PREVIEWCELLS Selected-space gamut test and sRGB preview encoding, kept separate.
            %
            % XYZ rows are on the Y_white = 1 scale; NaN rows are model-invalid.
            % selectedSpace: 'srgb' | 'linear-rgb' | 'adobe-rgb-1998' | 'prophoto-rgb'.
            % The preview is always sRGB-encoded (the display encoding), computed with
            % MATLAB xyz2rgb, which Bradford-adapts from whiteName to the space's native
            % white. This is an encoded preview, not a full CAM appearance match between
            % separately specified source and display viewing conditions.
            % P.status per row: "model-invalid" | "outside-selected-gamut" |
            %   "clipped-preview" (inside the selected gamut, outside sRGB) | "displayable".
            % P.rgbSelected and P.rgbPreview are unclipped floating values; P.rgbDisplay is
            % the clipped preview for drawable rows (displayable or clipped-preview), NaN otherwise.
            arguments
                XYZ (:,3) {mustBeNumeric, mustBeReal}
                selectedSpace (1,1) string
                whiteName (1,1) string
            end
            XYZ = double(XYZ);
            tol = ColorAtlasScience.GAMUT_TOLERANCE;
            n = size(XYZ, 1);
            valid = all(isfinite(XYZ), 2);
            rgbSel = NaN(n, 3); rgbPre = NaN(n, 3);
            if any(valid)
                rgbSel(valid, :) = xyz2rgb(XYZ(valid, :), 'ColorSpace', char(selectedSpace), 'WhitePoint', char(whiteName));
                rgbPre(valid, :) = xyz2rgb(XYZ(valid, :), 'ColorSpace', 'srgb', 'WhitePoint', char(whiteName));
            end
            inSel = valid & all(rgbSel >= -tol & rgbSel <= 1 + tol, 2);
            inPre = valid & all(rgbPre >= -tol & rgbPre <= 1 + tol, 2);
            status = repmat("model-invalid", n, 1);
            status(valid & ~inSel) = "outside-selected-gamut";
            status(inSel & ~inPre) = "clipped-preview";
            status(inSel & inPre) = "displayable";
            rgbDisplay = NaN(n, 3);
            rgbDisplay(inSel, :) = min(max(rgbPre(inSel, :), 0), 1);
            P = struct('status', status, 'rgbSelected', rgbSel, 'rgbPreview', rgbPre, ...
                'rgbDisplay', rgbDisplay, 'selectedSpace', selectedSpace, 'whiteName', whiteName, ...
                'tolerance', tol);
        end

        function XYZ = backgroundXYZ(kind, whiteName, value)
            % kind "lab": value is the background L* (neutral, a* = b* = 0).
            % kind "cam": value is Yb/Yw, the relative luminance of the neutral background.
            % Output on the Y_white = 1 scale, proportional to the adopted white.
            arguments
                kind (1,1) string {mustBeMember(kind, ["lab" "cam"])}
                whiteName (1,1) string
                value (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBeNonnegative}
            end
            value = double(value);
            if kind == "lab"
                XYZ = lab2xyz([value 0 0], 'WhitePoint', char(whiteName));
            else
                XYZ = whitepoint(char(whiteName)) * value;
            end
        end
    end

    methods (Static, Access = private)

        function p = conditionParameters(basis, formulation, xyzw, vc)
            switch vc.surround
                case "average", F = 1.0; c = 0.69;  Nc = 1.0;
                case "dim",     F = 0.9; c = 0.59;  Nc = 0.9;
                case "dark",    F = 0.8; c = 0.525; Nc = 0.8;
            end
            La = vc.La; Yb = vc.Yb; Yw = vc.Yw;
            knorm = 100 / xyzw(2);
            w = xyzw * knorm;
            assert(isfinite(knorm) && knorm > 0 && all(isfinite(w)), ...
                'ColorAtlas:invalidViewingCondition', 'White normalization exceeds the numerical domain.');
            if basis == "cat02", Mcat = ColorAtlasScience.CAT02; else, Mcat = ColorAtlasScience.CAT16; end
            rgbw = (Mcat * w')';
            assert(all(isfinite(rgbw)) && all(rgbw ~= 0), ...
                'ColorAtlas:invalidViewingCondition', 'White adaptation divisors must be finite and nonzero.');
            if isnan(vc.D)
                D = F * (1 - (1 / 3.6) * exp((-La - 42) / 92));
            else
                D = vc.D;
            end
            D = min(max(D, 0), 1);
            DRGB = D * w(2) ./ rgbw + 1 - D;
            k = 1 / (5 * La + 1);
            Fl = 0.2 * k^4 * (5 * La) + 0.1 * (1 - k^4)^2 * (5 * La)^(1/3);
            n = Yb / Yw;
            assert(isfinite(n) && n > 0, 'ColorAtlas:invalidViewingCondition', ...
                'The background-to-white ratio must be finite and positive.');
            z = 1.48 + sqrt(n);
            Nbb = 0.725 * (1 / n)^0.2;
            Ncb = Nbb;
            RGBwc = DRGB .* rgbw;
            if basis == "cat02"
                RGBwcp = (ColorAtlasScience.HPE * (Mcat \ RGBwc'))';
            else
                RGBwcp = RGBwc;
            end
            uw = (0.01 * Fl * abs(RGBwcp)).^0.42;
            RGBaw = 400 * sign(RGBwcp) .* uw ./ (uw + 27.13);
            Aw = 2 * RGBaw(1) + RGBaw(2) + RGBaw(3) / 20;
            if formulation == "standard", Aw = Aw * Nbb; end
            assert(all(isfinite([DRGB Fl z Nbb Ncb Aw 100 / Fl])) && ...
                all(DRGB ~= 0) && Fl > 0 && Nbb > 0 && Aw > 0, ...
                'ColorAtlas:invalidViewingCondition', ...
                'Derived viewing parameters exceed the finite, invertible numerical domain.');
            p = struct('basis', basis, 'formulation', formulation, 'F', F, 'c', c, 'Nc', Nc, ...
                'La', La, 'Yb', Yb, 'Yw', Yw, 'D', D, 'DRGB', DRGB, 'Fl', Fl, 'n', n, 'z', z, ...
                'Nbb', Nbb, 'Ncb', Ncb, 'Aw', Aw, 'knorm', knorm, 'Mcat', Mcat);
        end

        function [tone, toneName, chroma, chromaName, h] = parseAppearance(appearance)
            f = string(fieldnames(appearance))';
            toneName = intersect(f, ["J" "Q"], 'stable');
            chromaName = intersect(f, ["C" "M" "s"], 'stable');
            assert(isscalar(toneName), 'ColorAtlas:appearance', 'Appearance must include exactly one of J or Q.');
            assert(isscalar(chromaName), 'ColorAtlas:appearance', 'Appearance must include exactly one of C, M or s.');
            assert(ismember("h", f), 'ColorAtlas:appearance', 'Appearance must include h.');
            [tone, chroma, h] = ColorAtlasScience.broadcastColumns( ...
                appearance.(toneName), appearance.(chromaName), appearance.h);
            h = mod(h, 360);
        end

        function varargout = broadcastColumns(varargin)
            % Validate raw inputs before conversion: double('50') is [53 48],
            % and flattening a matrix would silently invent an appearance batch.
            for i = 1:numel(varargin)
                v = varargin{i};
                assert(isnumeric(v) && ~isempty(v) && isvector(v), ...
                    'ColorAtlas:appearance','Appearance fields must be nonempty numeric scalars or vectors.');
                assert(isreal(v),'ColorAtlas:complexAppearance','Appearance correlates must be real.');
                varargin{i} = double(v);
            end
            lengths = cellfun(@numel, varargin);
            n = max(lengths);
            assert(all(lengths == 1 | lengths == n), 'ColorAtlas:appearance', ...
                'Appearance fields must be scalars or vectors of equal length.');
            varargout = cell(size(varargin));
            for i = 1:numel(varargin)
                v = varargin{i}(:);
                if isscalar(v), v = repmat(v, n, 1); end
                varargout{i} = v;
            end
        end

        function [XYZ, status] = legacyCall(model, appearance, xyzw, in)
            arguments
                model (1,1) string
                appearance (1,1) struct
                xyzw {mustBeNumeric, mustBeReal}
                in.relativeReferenceWhite (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive} = 100
                in.relativeBackgroundLuminance (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive} = 20
                in.D (1,1) {mustBeNumeric, mustBeReal} = NaN
                in.adaptingLuminance (1,1) {mustBeNumeric, mustBeReal} = NaN
                in.whiteLuminance (1,1) {mustBeNumeric, mustBeReal} = NaN
                in.Condition (1,1) string = "average"
            end
            xyzw = reshape(double(xyzw), 1, []);
            assert(numel(xyzw) == 3, 'ColorAtlas:invalidWhite', 'A single 3-element white is supported.');
            fields = {'relativeReferenceWhite','relativeBackgroundLuminance','D','adaptingLuminance','whiteLuminance'};
            for i = 1:numel(fields), in.(fields{i}) = double(in.(fields{i})); end
            if isnan(in.whiteLuminance), Lw = xyzw(2); else, Lw = in.whiteLuminance; end
            if isnan(in.adaptingLuminance)
                La = Lw * in.relativeBackgroundLuminance / in.relativeReferenceWhite;
            else
                La = in.adaptingLuminance;
            end
            [XYZ, status] = ColorAtlasScience.inverseCAM(model, appearance, xyzw, ...
                'La', La, 'Yb', in.relativeBackgroundLuminance, 'Yw', in.relativeReferenceWhite, ...
                'surround', lower(string(in.Condition)), 'D', in.D);
        end
    end
end
