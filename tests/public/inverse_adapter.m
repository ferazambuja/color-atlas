function XYZ=inverse_adapter(model,appearance,white,La,Yb,D,surround)
% Map independently named fixture models to the maintained public API.
switch string(model)
    case "CAM02", key="ciecam02";
    case "CAM16", key="cam16";
    case "modCAM16", key="hellwig2022";
    case "modCAM02", key="hellwig2022cat02";
    otherwise,error('Unknown fixture model %s',model);
end
XYZ=ColorAtlasScience.inverseCAM(key,appearance,white,'La',La,'Yb',Yb,'D',D,'surround',surround);
end
